#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Combine
import Foundation

/// Live progress of a prepare or resume: counts include assets carried over
/// from a checkpoint, so `completed` of `total` is the whole import's state.
public struct PhotosPreparationProgress: Equatable, Sendable {
    public let total: Int
    public let completed: Int
    public let failed: Int
    public let currentAssetLabel: String?
    public let isWaitingForCloud: Bool
}

/// An interrupted import that can be resumed from its checkpoint.
public struct PhotosResumableImport: Equatable, Sendable {
    public let stagingDirectoryURL: URL
    public let checkpoint: PhotosImportCheckpoint
    public let readyCount: Int
    public let totalCount: Int
    public let interruptedAt: Date
    public let destinationMatches: Bool
}

/// Thread-safe flag the export's `isCancelled` closure reads.
private final class PhotosPreparationCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    var isCancelled: Bool { lock.withLock { cancelled } }
    func cancel() { lock.withLock { cancelled = true } }
    func reset() { lock.withLock { cancelled = false } }
}

/// View-model for the Photos import workspace: authorization state, album and
/// asset browsing, multi-selection, and the read-only export that populates a
/// staging directory before handing off to the verified-transfer pipeline.
///
/// The store never touches Setup or a profile. `prepareImport` captures the
/// destination that is active at click time (via the injected capture) and
/// returns a fully-pinned `PhotosImportContext`; the caller then drives the
/// normal preview → consent → transfer flow. The Photos library is only ever
/// read.
@MainActor
public final class PhotosImportStore: ObservableObject {
    /// The organize destination captured at import time.
    public struct DestinationCapture: Equatable, Sendable {
        public let path: String
        public let bookmarkKeys: [String]
        public init(path: String, bookmarkKeys: [String]) {
            self.path = path
            self.bookmarkKeys = bookmarkKeys
        }
    }

    @Published public private(set) var authorization: PhotosAuthorizationStatus
    @Published public private(set) var albums: [PhotosAlbumSummary] = []
    @Published public private(set) var selectedAlbumID: String?
    @Published public private(set) var assets: [PhotosAssetSummary] = []
    @Published public private(set) var totalAssetCount: Int = 0
    @Published public private(set) var hasMorePages: Bool = false
    @Published public private(set) var selectedAssetIDs: Set<String> = []
    @Published public private(set) var isLoadingAssets: Bool = false
    @Published public private(set) var preparation: PhotosPreparationProgress?
    @Published public private(set) var resumable: PhotosResumableImport?
    /// A plain, reassuring status/error line for the UI. Never raw error text.
    @Published public private(set) var statusMessage: String?

    private let access: any PhotosLibraryAccessing
    private let catalog: any PhotosCatalogReading
    private let exporter: any PhotosResourceExporting
    private let stagingParentURL: URL
    private let pageSize: Int
    private let checkpointStore: any PhotosImportCheckpointStoring
    private let exportExecutorFactory: (any PhotosResourceExporting) -> PhotosExportExecutor
    private let now: @Sendable () -> Date
    private let cancellation = PhotosPreparationCancellation()
    /// The checkpoint of the export in flight; only `runExport` and the event
    /// handler it drives touch these.
    private var activeCheckpoint: PhotosImportCheckpoint?
    private var activeStagingDirectory: URL?
    /// Staging directories handed out in a context whose run has not yet
    /// called `cleanupStaging(for:)`. A refresh must never treat these as
    /// consumed.
    private var preparedStagingPaths: Set<String> = []
    private var loadedPageCount = 0
    /// Each selected asset's summary, captured when it was selected, in
    /// selection order. Selections persist across albums and pages, so the
    /// export resolves from here rather than from the currently loaded
    /// `assets`, keeping the exported set equal to `selectedCount`.
    private var selectedSummaries: [PhotosAssetSummary] = []

    public init(
        access: any PhotosLibraryAccessing,
        catalog: any PhotosCatalogReading,
        exporter: any PhotosResourceExporting,
        stagingParentURL: URL,
        pageSize: Int = 120,
        checkpointStore: any PhotosImportCheckpointStoring = PhotosImportFileCheckpointStore(),
        exportExecutorFactory: @escaping (any PhotosResourceExporting) -> PhotosExportExecutor = { PhotosExportExecutor(exporter: $0) },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.access = access
        self.catalog = catalog
        self.exporter = exporter
        self.stagingParentURL = stagingParentURL
        self.pageSize = max(1, pageSize)
        self.checkpointStore = checkpointStore
        self.exportExecutorFactory = exportExecutorFactory
        self.now = now
        self.authorization = access.currentAuthorization()
    }

    public var isPreparingImport: Bool { preparation != nil }

    public var selectedCount: Int { selectedAssetIDs.count }

    /// True when there is at least one selection, access is granted, and no
    /// export is already running.
    public var canImport: Bool {
        !selectedAssetIDs.isEmpty && !isPreparingImport && authorization.allowsReading
    }

    // MARK: - Authorization

    public func refreshAuthorization() {
        authorization = access.currentAuthorization()
        loadAlbumsIfAuthorized()
    }

    public func requestAccess() async {
        authorization = await access.requestReadAccess()
        loadAlbumsIfAuthorized()
    }

    /// Loads albums when access is granted and they have not been loaded yet.
    public func loadAlbumsIfAuthorized() {
        guard authorization.allowsReading, albums.isEmpty else { return }
        loadAlbums()
    }

    private func loadAlbums() {
        let list = catalog.albums()
        albums = list
        if selectedAlbumID == nil, let first = list.first {
            selectAlbum(id: first.id)
        }
    }

    // MARK: - Browsing

    public func selectAlbum(id: String) {
        guard let album = albums.first(where: { $0.id == id }) else { return }
        selectedAlbumID = id
        assets = []
        loadedPageCount = 0
        totalAssetCount = 0
        hasMorePages = false
        loadNextPage(for: album)
    }

    public func loadMoreAssets() {
        guard hasMorePages, !isLoadingAssets else { return }
        guard let id = selectedAlbumID, let album = albums.first(where: { $0.id == id }) else { return }
        loadNextPage(for: album)
    }

    private func loadNextPage(for album: PhotosAlbumSummary) {
        isLoadingAssets = true
        defer { isLoadingAssets = false }
        let page = catalog.assetPage(in: album, pageIndex: loadedPageCount, pageSize: pageSize)
        assets.append(contentsOf: page.assets)
        totalAssetCount = page.totalCount
        hasMorePages = page.hasMore
        loadedPageCount += 1
    }

    // MARK: - Selection

    public func toggleSelection(_ assetID: String) {
        if selectedAssetIDs.contains(assetID) {
            deselect(assetID)
            return
        }
        // Only importable media (photo/video) can be selected.
        guard let summary = assets.first(where: { $0.id == assetID }),
              summary.mediaKind.isImportable
        else { return }
        select(summary)
    }

    public func isSelected(_ assetID: String) -> Bool {
        selectedAssetIDs.contains(assetID)
    }

    public func clearSelection() {
        selectedAssetIDs.removeAll()
        selectedSummaries.removeAll()
    }

    /// Adds one asset to the selection, keeping `selectedAssetIDs` and
    /// `selectedSummaries` in sync. Every path that grows the selection goes
    /// through this single helper so the two collections can't drift apart
    /// the way they did before the BASH-02 fix.
    private func select(_ summary: PhotosAssetSummary) {
        selectedAssetIDs.insert(summary.id)
        selectedSummaries.append(summary)
    }

    /// Removes one asset from the selection, keeping both collections in sync.
    private func deselect(_ assetID: String) {
        selectedAssetIDs.remove(assetID)
        selectedSummaries.removeAll { $0.id == assetID }
    }

    // MARK: - Import preparation (read-only export into staging)

    /// Exports the current selection's originals into a fresh staging
    /// directory and returns a pinned import context, or nil (with a
    /// `statusMessage`) if there is nothing to import or the export failed.
    /// The Photos library is never modified. A new prepare supersedes any
    /// interrupted import (the UI confirms first).
    public func prepareImport(destination: DestinationCapture?) async -> PhotosImportContext? {
        guard !isPreparingImport else { return nil }
        guard let destination, !destination.path.isEmpty else {
            statusMessage = "Choose an organize destination before importing from Photos."
            return nil
        }

        let plan = PhotosExportPlanner.plan(for: selectedSummaries)
        guard !plan.isEmpty else {
            statusMessage = "Select at least one photo or video to import."
            return nil
        }

        statusMessage = nil

        // A new prepare supersedes whatever an earlier import left behind.
        preparedStagingPaths.removeAll()
        refreshResumableImport(destination: destination)
        if let superseded = resumable {
            try? FileManager.default.removeItem(at: superseded.stagingDirectoryURL)
            resumable = nil
        }

        let importID = UUID()
        let stagingDirectory = stagingParentURL.appendingPathComponent(importID.uuidString, isDirectory: true)
        let checkpoint = PhotosImportCheckpoint(
            importID: importID,
            createdAt: now(),
            destinationPath: destination.path,
            destinationBookmarkKeys: destination.bookmarkKeys,
            plan: plan
        )
        return await runExport(checkpoint: checkpoint, stagingDirectory: stagingDirectory, destination: destination)
    }

    /// Continues the interrupted import from its checkpoint, exporting only
    /// the assets that are not yet completed or failed.
    public func resumeImport(destination: DestinationCapture?) async -> PhotosImportContext? {
        guard resumable != nil, !isPreparingImport else { return nil }
        // Judge the destination and the staged files as they are now, not as
        // they were at the last refresh.
        refreshResumableImport(destination: destination)
        guard let resumable else {
            statusMessage = "Chronoframe couldn't prepare the Photos import. Your Photos library was not changed."
            return nil
        }
        guard authorization.allowsReading else {
            statusMessage = "Chronoframe needs access to Photos to continue this import."
            return nil
        }
        guard resumable.destinationMatches else {
            statusMessage = Self.destinationMismatchMessage
            return nil
        }

        statusMessage = nil
        guard removeUnrecordedFiles(in: resumable.stagingDirectoryURL, checkpoint: resumable.checkpoint) else {
            statusMessage = "Chronoframe couldn't prepare the Photos import. Your Photos library was not changed."
            return nil
        }
        return await runExport(
            checkpoint: resumable.checkpoint,
            stagingDirectory: resumable.stagingDirectoryURL,
            destination: destination
        )
    }

    /// Asks the export in flight to stop after rolling back its current asset.
    /// Completed assets stay in staging with their checkpoint.
    public func cancelPreparation() {
        cancellation.cancel()
    }

    /// Deletes the interrupted import's staging directory.
    public func discardResumableImport() {
        guard !isPreparingImport, let resumable else { return }
        try? FileManager.default.removeItem(at: resumable.stagingDirectoryURL)
        self.resumable = nil
    }

    /// Finds the interrupted import to offer, if any. Looks at the staging
    /// parent's immediate subdirectories: the newest resumable checkpoint
    /// whose completed files are still present at their recorded size wins;
    /// every other subdirectory (no checkpoint, consumed, damaged, or older)
    /// is removed. Sizes are compared, not hashes: the planner re-hashes every
    /// prepared file at preview and aborts on any change.
    public func refreshResumableImport(destination: DestinationCapture?) {
        // The export in flight owns its directory; never judge it mid-run.
        guard !isPreparingImport else { return }

        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: stagingParentURL,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        ) else {
            resumable = nil
            return
        }

        var candidates: [PhotosResumableImport] = []
        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values?.isDirectory == true, values?.isSymbolicLink != true else { continue }
            if preparedStagingPaths.contains(child.standardizedFileURL.path) { continue }

            guard let checkpoint = checkpointStore.load(in: child),
                  checkpoint.isResumable,
                  Self.completedFilesAreIntact(in: checkpoint)
            else {
                try? fileManager.removeItem(at: child)
                continue
            }
            candidates.append(
                PhotosResumableImport(
                    stagingDirectoryURL: child,
                    checkpoint: checkpoint,
                    readyCount: checkpoint.completed.count,
                    totalCount: checkpoint.plan.entries.count,
                    interruptedAt: checkpoint.updatedAt,
                    destinationMatches: Self.pathsMatch(checkpoint.destinationPath, destination?.path)
                )
            )
        }

        // Newest wins; createdAt then importID make a tie deterministic.
        candidates.sort {
            if $0.checkpoint.updatedAt != $1.checkpoint.updatedAt { return $0.checkpoint.updatedAt > $1.checkpoint.updatedAt }
            if $0.checkpoint.createdAt != $1.checkpoint.createdAt { return $0.checkpoint.createdAt > $1.checkpoint.createdAt }
            return $0.checkpoint.importID.uuidString > $1.checkpoint.importID.uuidString
        }
        for older in candidates.dropFirst() {
            try? fileManager.removeItem(at: older.stagingDirectoryURL)
        }
        resumable = candidates.first
    }

    /// Deletes a finished import's staging directory. Safe to call more than
    /// once; a missing directory is not an error.
    public func cleanupStaging(for context: PhotosImportContext) {
        preparedStagingPaths.remove(context.stagingDirectoryURL.standardizedFileURL.path)
        try? FileManager.default.removeItem(at: context.stagingDirectoryURL)
    }

    // MARK: - Export driver

    private func runExport(
        checkpoint initial: PhotosImportCheckpoint,
        stagingDirectory: URL,
        destination: DestinationCapture?
    ) async -> PhotosImportContext? {
        cancellation.reset()
        var checkpoint = initial
        checkpoint.setState(.inProgress, at: now())
        activeCheckpoint = checkpoint
        activeStagingDirectory = stagingDirectory
        preparation = PhotosPreparationProgress(
            total: checkpoint.plan.entries.count,
            completed: checkpoint.completed.count,
            failed: checkpoint.failures.count,
            currentAssetLabel: nil,
            isWaitingForCloud: false
        )
        try? checkpointStore.save(checkpoint, in: stagingDirectory)

        // Events are delivered in order through one stream and applied on the
        // main actor; the stream is drained before the outcome is judged.
        let (events, continuation) = AsyncStream.makeStream(of: PhotosExportEvent.self)
        let consumer = Task { @MainActor [weak self] in
            for await event in events {
                self?.handle(event)
            }
        }
        let flag = cancellation

        do {
            _ = try await exportExecutorFactory(exporter).export(
                plan: PhotosExportPlan(entries: checkpoint.remainingEntries),
                to: stagingDirectory,
                reservedFilenames: checkpoint.reservedFilenames,
                isCancelled: { flag.isCancelled },
                onEvent: { continuation.yield($0) }
            )
            continuation.finish()
            await consumer.value

            var finished = activeCheckpoint ?? checkpoint
            finished.setState(.ready, at: now())
            try? checkpointStore.save(finished, in: stagingDirectory)
            finishExport()
            resumable = nil

            guard !finished.completed.isEmpty else {
                removeEmptyImportDirectory(stagingDirectory)
                statusMessage = "Chronoframe couldn't read the selected items from Photos, so there is nothing to import. Your Photos library was not changed."
                return nil
            }
            if !finished.failures.isEmpty {
                statusMessage = "\(finished.failures.count) item(s) couldn't be read and were skipped. Your Photos library was not changed."
            }
            preparedStagingPaths.insert(stagingDirectory.standardizedFileURL.path)
            return PhotosImportContext(
                importID: finished.importID,
                stagingDirectoryURL: stagingDirectory,
                destinationPath: finished.destinationPath,
                destinationBookmarkKeys: finished.destinationBookmarkKeys,
                assetIDs: finished.exportedAssetIDs,
                sourceDateHints: finished.mergedSourceDateHints
            )
        } catch is CancellationError {
            continuation.finish()
            await consumer.value
            let kept = pauseExport(.stopped, fallback: checkpoint, in: stagingDirectory)
            refreshResumableImport(destination: destination)
            statusMessage = "Import stopped. \(Self.formatted(kept.completed.count)) of \(Self.formatted(kept.plan.entries.count)) items are ready and were kept. Resume whenever you like. Your Photos library was not changed."
            return nil
        } catch is PhotosExportStop {
            continuation.finish()
            await consumer.value
            let kept = pauseExport(.lowSpace, fallback: checkpoint, in: stagingDirectory)
            refreshResumableImport(destination: destination)
            statusMessage = "Chronoframe paused the import because the drive holding its staging folder is almost full. \(Self.formatted(kept.completed.count)) of \(Self.formatted(kept.plan.entries.count)) items are ready and were kept. Free up space, then resume. Your Photos library was not changed."
            return nil
        } catch {
            continuation.finish()
            await consumer.value
            let current = activeCheckpoint ?? checkpoint
            if current.completed.isEmpty {
                finishExport()
                removeEmptyImportDirectory(stagingDirectory)
            } else {
                _ = pauseExport(.stopped, fallback: checkpoint, in: stagingDirectory)
            }
            refreshResumableImport(destination: destination)
            statusMessage = "Chronoframe couldn't prepare the Photos import. Your Photos library was not changed."
            return nil
        }
    }

    /// Marks the in-flight checkpoint `state`, saves it and ends the export.
    private func pauseExport(
        _ state: PhotosImportCheckpointState,
        fallback: PhotosImportCheckpoint,
        in stagingDirectory: URL
    ) -> PhotosImportCheckpoint {
        var paused = activeCheckpoint ?? fallback
        paused.setState(state, at: now())
        try? checkpointStore.save(paused, in: stagingDirectory)
        finishExport()
        return paused
    }

    private func finishExport() {
        activeCheckpoint = nil
        activeStagingDirectory = nil
        preparation = nil
    }

    /// Applies one executor event: progress, and the checkpoint write that
    /// follows every completed or failed asset.
    private func handle(_ event: PhotosExportEvent) {
        guard var checkpoint = activeCheckpoint,
              let stagingDirectory = activeStagingDirectory,
              let progress = preparation
        else { return }

        func updated(
            completed: Int? = nil,
            failed: Int? = nil,
            label: String?,
            waiting: Bool
        ) -> PhotosPreparationProgress {
            PhotosPreparationProgress(
                total: progress.total,
                completed: completed ?? progress.completed,
                failed: failed ?? progress.failed,
                currentAssetLabel: label,
                isWaitingForCloud: waiting
            )
        }

        switch event {
        case .assetStarted(let assetID, _, _):
            let label = selectedSummaries.first { $0.id == assetID }?.originalFilename
            preparation = updated(label: label, waiting: false)
        case .resourceProgress(_, let fraction):
            if fraction < 1, !progress.isWaitingForCloud {
                preparation = updated(label: progress.currentAssetLabel, waiting: true)
            }
        case .assetCompleted(let assetID, let files, let hints):
            checkpoint.recordCompleted(
                PhotosCompletedAssetRecord(assetID: assetID, files: files, sourceDateHints: hints),
                at: now()
            )
            activeCheckpoint = checkpoint
            try? checkpointStore.save(checkpoint, in: stagingDirectory)
            preparation = updated(completed: progress.completed + 1, label: nil, waiting: false)
        case .assetFailed(let assetID, let message):
            checkpoint.recordFailure(PhotosAssetExportFailure(assetID: assetID, message: message), at: now())
            activeCheckpoint = checkpoint
            try? checkpointStore.save(checkpoint, in: stagingDirectory)
            preparation = updated(failed: progress.failed + 1, label: nil, waiting: false)
        }
    }

    /// Before a resume, deletes whatever a crash left in the staging directory
    /// that the checkpoint does not record (a half-written asset, a hidden
    /// temp file), so a partial unit can never reach the transfer pipeline.
    /// The export stages flat, so only immediate children are examined. The
    /// checkpoint file and every recorded file are never removed. Returns
    /// false, having exported nothing, if the directory cannot be listed or
    /// any such entry cannot be removed.
    private func removeUnrecordedFiles(in stagingDirectory: URL, checkpoint: PhotosImportCheckpoint) -> Bool {
        let fileManager = FileManager.default
        guard let children = try? fileManager.contentsOfDirectory(
            at: stagingDirectory, includingPropertiesForKeys: nil, options: []
        ) else { return false }
        let recorded = checkpoint.reservedFilenames
        var allRemoved = true
        for child in children {
            let name = child.lastPathComponent
            if name == PhotosImportCheckpoint.filename || recorded.contains(name) { continue }
            do {
                try fileManager.removeItem(at: child)
            } catch {
                allRemoved = false
            }
        }
        return allRemoved
    }

    /// Removes an import directory that holds nothing worth keeping, then its
    /// parent if that leaves the parent empty. A parent that still holds
    /// anything is never touched.
    private func removeEmptyImportDirectory(_ directory: URL) {
        try? FileManager.default.removeItem(at: directory)
        if let remaining = try? FileManager.default.contentsOfDirectory(atPath: stagingParentURL.path), remaining.isEmpty {
            try? FileManager.default.removeItem(at: stagingParentURL)
        }
    }

    // MARK: - Helpers

    private static let destinationMismatchMessage =
        "This import was prepared for a different destination. Choose that destination again to resume, or discard it."

    private static func formatted(_ count: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: count)) ?? String(count)
    }

    private static func pathsMatch(_ a: String, _ b: String?) -> Bool {
        guard let b else { return false }
        return URL(fileURLWithPath: a).standardizedFileURL.path == URL(fileURLWithPath: b).standardizedFileURL.path
    }

    /// Every completed file is a regular file at its recorded size. A file
    /// without a recorded size cannot be checked and counts as damaged.
    private static func completedFilesAreIntact(in checkpoint: PhotosImportCheckpoint) -> Bool {
        for record in checkpoint.completed {
            for file in record.files {
                guard let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
                      attributes[.type] as? FileAttributeType == .typeRegular,
                      let size = (attributes[.size] as? NSNumber)?.int64Value,
                      let hint = record.sourceDateHints[SourceDateHint.pathKey(for: file.path)],
                      hint.identity.size == size
                else { return false }
            }
        }
        return true
    }
}
