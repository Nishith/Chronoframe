#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// One original resource of a Photos asset, described without any PhotoKit
/// type so the export executor is testable off-device. The concrete
/// `PhotosResourceExportService` builds these from `PHAssetResource`s of
/// original (unedited) type only.
public struct PhotosExportableResource: Equatable, Sendable {
    public let assetID: String
    /// Index among the asset's original resources, used only to disambiguate
    /// the rare case of two same-extension resources on one asset.
    public let resourceIndex: Int
    /// Lower-cased file extension without a leading dot (e.g. `heic`, `mov`).
    public let fileExtension: String
    public let originalFilename: String
    /// Size in bytes of the original resource when Photos reports it; nil when unknown.
    public let fileSize: Int64?
    /// Which resource of the asset this is. Defaults to `.original`.
    public let role: Role

    public enum Role: String, Equatable, Sendable {
        case original
        case editedRender
    }

    public init(
        assetID: String,
        resourceIndex: Int,
        fileExtension: String,
        originalFilename: String,
        fileSize: Int64? = nil,
        role: Role = .original
    ) {
        self.assetID = assetID
        self.resourceIndex = resourceIndex
        self.fileExtension = fileExtension
        self.originalFilename = originalFilename
        self.fileSize = fileSize
        self.role = role
    }
}

/// Read-only export gateway to the Apple Photos library.
///
/// The seam surface is deliberately read-only: it can *list* an asset's
/// original resources and *copy* their bytes out to a Chronoframe-owned
/// staging URL — there is no method that mutates the library. This is how
/// the "Photos import is strictly read-only" safety invariant is enforced by
/// construction; the executor literally cannot reach a mutating PhotoKit API.
public protocol PhotosResourceExporting: Sendable {
    /// The original (unedited) importable resources for an asset, in the
    /// order they should be written. Read-only: implemented with
    /// `PHAssetResource.assetResources(for:)`.
    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource]
    /// The asset's current edited still render (`.fullSizePhoto`), or nil when
    /// the asset has none. Read-only, like `originalResources(forAssetID:)`.
    func editedStillResource(forAssetID id: String) async throws -> PhotosExportableResource?
    /// True when the asset has an edit this import does not export: an edited
    /// video, or an edited Live Photo. Read-only, implemented with
    /// `PHAssetResource.assetResources(for:)` only.
    func hasUnsupportedEditedRender(forAssetID id: String) async throws -> Bool
    /// Copies one resource's original bytes to `destinationURL`. Read-only
    /// against the library: implemented with `PHAssetResourceManager`, which
    /// only reads. Never calls `PHPhotoLibrary.performChanges`.
    /// `destinationURL` is an empty file the executor just created exclusively
    /// to claim the name; the implementation replaces it.
    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws
    /// Same as `writeResource(_:to:)`, additionally reporting 0...1 progress.
    func writeResource(
        _ resource: PhotosExportableResource,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}

public extension PhotosResourceExporting {
    /// Default keeps every existing test double compiling: no edited render.
    func editedStillResource(forAssetID id: String) async throws -> PhotosExportableResource? {
        nil
    }

    /// Default keeps every existing test double compiling: no unsupported edit.
    func hasUnsupportedEditedRender(forAssetID id: String) async throws -> Bool {
        false
    }

    /// Default keeps every existing test double compiling: ignores progress.
    func writeResource(
        _ resource: PhotosExportableResource,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await writeResource(resource, to: destinationURL)
    }
}

/// A single file written into the staging directory during export.
public struct PhotosExportedFile: Equatable, Codable, Sendable {
    public let assetID: String
    public let stagingStem: String
    public let path: String

    public init(assetID: String, stagingStem: String, path: String) {
        self.assetID = assetID
        self.stagingStem = stagingStem
        self.path = path
    }
}

/// An asset that could not be exported. The library is never changed, so a
/// failure only means that asset is absent from the import.
public struct PhotosAssetExportFailure: Equatable, Codable, Sendable {
    public let assetID: String
    public let message: String

    public init(assetID: String, message: String) {
        self.assetID = assetID
        self.message = message
    }
}

/// Outcome of exporting a plan into staging.
public struct PhotosExportReceipt: Equatable, Sendable {
    public let exportedFiles: [PhotosExportedFile]
    public let failures: [PhotosAssetExportFailure]
    public let sourceDateHints: [String: SourceDateHint]
    /// The edited renders staged (also present in `exportedFiles`).
    public let editedFiles: [PhotosExportedFile]
    /// Assets whose edited render could not be saved; their originals were exported.
    public let variantFailures: [PhotosVariantFailure]
    /// Assets with an edited video or Live Photo, which are not exported.
    public let editedNotIncludedCount: Int

    public init(
        exportedFiles: [PhotosExportedFile],
        failures: [PhotosAssetExportFailure],
        sourceDateHints: [String: SourceDateHint] = [:],
        editedFiles: [PhotosExportedFile] = [],
        variantFailures: [PhotosVariantFailure] = [],
        editedNotIncludedCount: Int = 0
    ) {
        self.exportedFiles = exportedFiles
        self.failures = failures
        self.sourceDateHints = sourceDateHints
        self.editedFiles = editedFiles
        self.variantFailures = variantFailures
        self.editedNotIncludedCount = editedNotIncludedCount
    }

    public var stagedFileCount: Int { exportedFiles.count }
    public var isEmpty: Bool { exportedFiles.isEmpty }
    /// Distinct assets that contributed at least one staged file.
    public var exportedAssetIDs: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for file in exportedFiles where seen.insert(file.assetID).inserted {
            order.append(file.assetID)
        }
        return order
    }
}

/// Per-asset progress of an export, in the order the executor produces it.
public enum PhotosExportEvent: Equatable, Sendable {
    /// `index` is 0-based within this export call.
    case assetStarted(assetID: String, index: Int, total: Int)
    /// 0...1 from the exporter, forwarded unchanged.
    case resourceProgress(assetID: String, fraction: Double)
    case assetCompleted(assetID: String, files: [PhotosExportedFile], sourceDateHints: [String: SourceDateHint])
    case assetFailed(assetID: String, message: String)
    /// The asset's edited still was staged; sent just before its `.assetCompleted`.
    case editedVersionSaved(assetID: String, file: PhotosExportedFile)
    /// The edited still could not be saved; the originals still complete.
    case editedVersionFailed(assetID: String)
    /// The asset's edit (video or Live Photo) is not exported.
    case editedVersionNotIncluded(assetID: String)
}

/// Thrown before any write of the next asset when staging space is below the floor.
public enum PhotosExportStop: Error, Equatable, Sendable {
    case lowStagingSpace(freeBytes: Int64, floorBytes: Int64)
}

/// Copies selected Photos originals into a Chronoframe-owned staging
/// directory, read-only. The staging directory is later handed to the
/// existing verified-transfer pipeline as the run source; the Photos library
/// itself is never modified regardless of success, failure, or cancellation.
public struct PhotosExportExecutor {
    private let exporter: any PhotosResourceExporting
    private let timeZone: TimeZone
    private let freeSpaceFloorBytes: Int64
    private let freeSpaceProvider: @Sendable (URL) -> Int64?
    /// Upper bound on candidate names tried per resource. Internal so a test
    /// can exhaust it without ten thousand files.
    var maxNameAttempts = 10_000

    public static let defaultFreeSpaceFloorBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// `timeZone` picks the calendar day for items whose only date is Photos'
    /// own capture instant, which carries no timezone of its own.
    public init(
        exporter: any PhotosResourceExporting,
        timeZone: TimeZone = .current,
        freeSpaceFloorBytes: Int64 = PhotosExportExecutor.defaultFreeSpaceFloorBytes,
        freeSpaceProvider: @escaping @Sendable (URL) -> Int64? = PhotosExportExecutor.liveFreeSpace
    ) {
        self.exporter = exporter
        self.timeZone = timeZone
        self.freeSpaceFloorBytes = freeSpaceFloorBytes
        self.freeSpaceProvider = freeSpaceProvider
    }

    /// Available capacity for important usage on `url`'s volume; nil on error.
    public static func liveFreeSpace(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }

    public func export(
        plan: PhotosExportPlan,
        to stagingDirectory: URL,
        reservedFilenames: Set<String> = [],
        includeEditedVersions: Bool = false,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onEvent: @escaping @Sendable (PhotosExportEvent) -> Void = { _ in }
    ) async throws -> PhotosExportReceipt {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        // Discovery returns canonical URLs (notably /private/var for /var).
        let stagingRoot = stagingDirectory.resolvingSymlinksInPath()

        var exported: [PhotosExportedFile] = []
        var failures: [PhotosAssetExportFailure] = []
        // Compared by filesystem-style key (see `nameKey`): staging is usually
        // a case-insensitive, normalization-insensitive APFS volume.
        var usedFilenames = Set(reservedFilenames.map(Self.nameKey))
        var sourceDateHints: [String: SourceDateHint] = [:]
        var editedFiles: [PhotosExportedFile] = []
        var variantFailures: [PhotosVariantFailure] = []
        var editedNotIncludedCount = 0

        for (entryIndex, entry) in plan.entries.enumerated() {
            try throwIfCancelled(isCancelled)

            // Stop before anything of this asset is written, so no rollback is
            // needed and every completed asset's files stay in place. An
            // unknown free-space value never stops the export.
            if let free = freeSpaceProvider(stagingDirectory), free < freeSpaceFloorBytes {
                throw PhotosExportStop.lowStagingSpace(freeBytes: free, floorBytes: freeSpaceFloorBytes)
            }
            onEvent(.assetStarted(assetID: entry.assetID, index: entryIndex, total: plan.entries.count))

            // Export all of an asset's resources as a unit. Files are buffered
            // and only published once every resource succeeds, so a partial
            // failure — a Live Photo whose still writes but whose paired movie
            // fails — rolls back the asset's files instead of handing the
            // transfer pipeline an incomplete pair.
            var assetFiles: [PhotosExportedFile] = []
            var writtenURLs: [URL] = []
            do {
                let resources = try await exporter.originalResources(forAssetID: entry.assetID)
                guard !resources.isEmpty else {
                    let message = CoreL10n.text("No original photo or video was available to import for this item.")
                    failures.append(PhotosAssetExportFailure(assetID: entry.assetID, message: message))
                    onEvent(.assetFailed(assetID: entry.assetID, message: message))
                    continue
                }
                // Now the asset's size is known: a large original must fit
                // above the floor too, or it would fail with a disk-full error
                // instead of pausing. Unknown sizes and an unknown free-space
                // value never stop the export.
                let knownSize = resources.reduce(Int64(0)) { $0 &+ max(0, $1.fileSize ?? 0) }
                if knownSize > 0, let free = freeSpaceProvider(stagingDirectory) {
                    let (needed, overflow) = freeSpaceFloorBytes.addingReportingOverflow(knownSize)
                    let threshold = overflow ? Int64.max : needed
                    if free < threshold {
                        throw PhotosExportStop.lowStagingSpace(freeBytes: free, floorBytes: threshold)
                    }
                }
                for resource in resources {
                    try throwIfCancelled(isCancelled)
                    // The name is claimed with an exclusive create, so nothing
                    // already in staging is ever replaced. Only a file this
                    // call created reaches the rollback list.
                    let destination = try claimDestination(
                        in: stagingRoot,
                        stem: entry.stagingStem,
                        fileExtension: resource.fileExtension,
                        resourceIndex: resource.resourceIndex,
                        used: &usedFilenames
                    )
                    // Include the current resource in rollback even if the
                    // exporter fails after creating a partial staging file.
                    writtenURLs.append(destination)
                    try await exporter.writeResource(resource, to: destination) { fraction in
                        onEvent(.resourceProgress(assetID: entry.assetID, fraction: fraction))
                    }
                    assetFiles.append(
                        PhotosExportedFile(
                            assetID: entry.assetID,
                            stagingStem: entry.stagingStem,
                            path: destination.path
                        )
                    )
                }
                // Edited still, only when the user opted in. Every failure here
                // costs just the edited file; the originals above still complete.
                var editedURL: URL?
                var editedNotIncluded = false
                var editedFailed = false
                if includeEditedVersions {
                    try throwIfCancelled(isCancelled)
                    if (try? await exporter.hasUnsupportedEditedRender(forAssetID: entry.assetID)) == true {
                        editedNotIncluded = true
                    } else {
                        do {
                            if let edited = try await exporter.editedStillResource(forAssetID: entry.assetID) {
                                let ext = edited.fileExtension.isEmpty
                                    ? (edited.originalFilename as NSString).pathExtension
                                    : edited.fileExtension
                                let destination = try claimDestination(
                                    in: stagingRoot,
                                    stem: "\(entry.stagingStem)-edited",
                                    fileExtension: ext,
                                    resourceIndex: edited.resourceIndex,
                                    used: &usedFilenames
                                )
                                writtenURLs.append(destination)
                                editedURL = destination
                                try await exporter.writeResource(edited, to: destination) { fraction in
                                    onEvent(.resourceProgress(assetID: entry.assetID, fraction: fraction))
                                }
                            }
                        } catch is CancellationError {
                            throw CancellationError()
                        } catch {
                            discardEditedFile(&editedURL, from: &writtenURLs)
                            editedFailed = true
                        }
                    }
                }
                try throwIfCancelled(isCancelled)
                let captureDate = resolveAssetDate(entry: entry, paths: assetFiles.map(\.path), isCancelled: { isCancelled() || Task.isCancelled })
                var assetHints: [String: SourceDateHint] = [:]
                for file in assetFiles {
                    try throwIfCancelled(isCancelled)
                    assetHints[SourceDateHint.pathKey(for: file.path)] = SourceDateHint(
                        identity: try FileIdentityHasher().hashIdentity(at: URL(fileURLWithPath: file.path)),
                        resolvedDate: captureDate
                    )
                }
                // The edited file shares the capture date resolved from the
                // originals, so both land in the same date folder.
                var editedFile: PhotosExportedFile?
                if let url = editedURL {
                    do {
                        assetHints[SourceDateHint.pathKey(for: url.path)] = SourceDateHint(
                            identity: try FileIdentityHasher().hashIdentity(at: url),
                            resolvedDate: captureDate
                        )
                        editedFile = PhotosExportedFile(assetID: entry.assetID, stagingStem: entry.stagingStem, path: url.path)
                    } catch {
                        discardEditedFile(&editedURL, from: &writtenURLs)
                        editedFailed = true
                    }
                }
                try throwIfCancelled(isCancelled)
                if let editedFile { assetFiles.append(editedFile) }
                exported.append(contentsOf: assetFiles)
                sourceDateHints.merge(assetHints) { _, new in new }
                if let editedFile {
                    editedFiles.append(editedFile)
                    onEvent(.editedVersionSaved(assetID: entry.assetID, file: editedFile))
                } else if editedFailed {
                    variantFailures.append(PhotosVariantFailure(assetID: entry.assetID, reason: .editedRenderUnavailable))
                    onEvent(.editedVersionFailed(assetID: entry.assetID))
                } else if editedNotIncluded {
                    editedNotIncludedCount += 1
                    onEvent(.editedVersionNotIncluded(assetID: entry.assetID))
                }
                onEvent(.assetCompleted(assetID: entry.assetID, files: assetFiles, sourceDateHints: assetHints))
            } catch is CancellationError {
                rollBack(writtenURLs)
                throw CancellationError()
            } catch is PhotosExportNameExhausted {
                rollBack(writtenURLs)
                let message = CoreL10n.text("Chronoframe couldn't find a free file name for this item, so it was skipped. Your Photos library was not changed.")
                failures.append(PhotosAssetExportFailure(assetID: entry.assetID, message: message))
                onEvent(.assetFailed(assetID: entry.assetID, message: message))
            } catch let stop as PhotosExportStop {
                // Nothing of this asset was written; stop without recording a failure.
                throw stop
            } catch {
                // A resource failed mid-asset: roll back what was written so an
                // incomplete unit never reaches the transfer pipeline.
                rollBack(writtenURLs)
                let message = CoreL10n.text("Chronoframe couldn't read this item from Photos, so it was skipped. Your Photos library was not changed.")
                failures.append(PhotosAssetExportFailure(assetID: entry.assetID, message: message))
                onEvent(.assetFailed(assetID: entry.assetID, message: message))
            }
        }

        return PhotosExportReceipt(
            exportedFiles: exported,
            failures: failures,
            sourceDateHints: sourceDateHints,
            editedFiles: editedFiles,
            variantFailures: variantFailures,
            editedNotIncludedCount: editedNotIncludedCount
        )
    }

    /// One date per asset: still metadata wins over the paired movie (whose
    /// recording may start before midnight), then movie metadata, filename,
    /// and Photos' asset instant, filed under its day in the import timezone.
    /// No metadata means Unknown, never import day.
    private func resolveAssetDate(entry: PhotosAssetExportEntry, paths: [String], isCancelled: @escaping @Sendable () -> Bool) -> ResolvedMediaDate {
        let ordered = paths.filter { MediaLibraryRules.isPhotoFile(path: $0) }
            + paths.filter { !MediaLibraryRules.isPhotoFile(path: $0) }
        var dates: [ResolvedMediaDate] = []
        for path in ordered {
            let date = FileDateResolver().resolveCaptureDate(for: path, isCancelled: isCancelled)
            if date.source == .photoMetadata || date.source == .videoMetadata { return date }
            dates.append(date)
        }
        if let filename = dates.first(where: { $0.source == .filename }) { return filename }
        if let date = entry.creationDate, date.timeIntervalSince1970.isFinite, !DateClassification.isUnknown(date) {
            return ResolvedMediaDate(
                date: date,
                source: .photosAsset,
                confidence: .medium,
                bucketTimeZoneOffsetSeconds: timeZone.secondsFromGMT(for: date)
            )
        }
        return .unknown
    }

    /// Removes a partially-exported asset's staged files so an incomplete unit
    /// never reaches the transfer pipeline.
    private func rollBack(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// Removes only the edited file (a failed edit never costs the originals)
    /// and forgets it, so a later rollback does not list it again.
    private func discardEditedFile(_ editedURL: inout URL?, from writtenURLs: inout [URL]) {
        guard let url = editedURL else { return }
        rollBack([url])
        writtenURLs.removeAll { $0 == url }
        editedURL = nil
    }

    private func throwIfCancelled(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// Picks a free staging name for one resource and claims it by creating
    /// the file exclusively (`O_CREAT | O_EXCL`), returning its URL. The file
    /// is left empty for the exporter to replace with the resource's bytes.
    ///
    /// Candidates are `<stem>.<ext>`, then `<stem>-<resourceIndex>.<ext>`, then
    /// `<stem>-<resourceIndex>-<n>.<ext>` for n = 2, 3, ... A candidate is
    /// skipped when:
    /// - its name key is already in `used`: a reserved name (a file an
    ///   earlier, resumed export published), another asset's name in this
    ///   export, or an earlier resource of the same asset. The key folds case
    ///   and Unicode normalization (`nameKey`), so names APFS would treat as
    ///   one file collide here. A fallback name can itself equal another
    ///   asset's name, hence a loop rather than a single fallback.
    /// - the exclusive create finds the name already on disk (an unrecorded
    ///   leftover, or a variant the key does not foresee). The existing file
    ///   is never touched; the next candidate is tried.
    ///
    /// The search stops after `maxNameAttempts` candidates and throws
    /// `PhotosExportNameExhausted`, which fails only this asset.
    private func claimDestination(
        in directory: URL,
        stem: String,
        fileExtension: String,
        resourceIndex: Int,
        used: inout Set<String>
    ) throws -> URL {
        let ext = Self.normalizedExtension(fileExtension)
        for attempt in 0..<maxNameAttempts {
            let name = Self.candidateFilename(stem: stem, ext: ext, resourceIndex: resourceIndex, attempt: attempt)
            guard used.insert(Self.nameKey(name)).inserted else { continue }
            let url = directory.appendingPathComponent(name)
            if try Self.createExclusively(at: url) { return url }
        }
        throw PhotosExportNameExhausted()
    }

    private static func candidateFilename(stem: String, ext: String, resourceIndex: Int, attempt: Int) -> String {
        let base: String
        switch attempt {
        case 0: base = stem
        case 1: base = "\(stem)-\(resourceIndex)"
        default: base = "\(stem)-\(resourceIndex)-\(attempt)"
        }
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// Canonically decomposed, case-folded form of a filename. Diacritics are
    /// kept: "Cafe" and "Caf\u{E9}" are distinct files on APFS. Full case
    /// folding can merge a few names APFS keeps apart (ß and SS); the cost is
    /// a harmless extra rename, never an overwrite.
    static func nameKey(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Creates an empty file at `url` without replacing or following anything.
    /// Returns false when the name is already taken.
    private static func createExclusively(at url: URL) throws -> Bool {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }
        if errno == EEXIST { return false }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    static func normalizedExtension(_ raw: String) -> String {
        var ext = raw.lowercased()
        while ext.hasPrefix(".") { ext.removeFirst() }
        return ext.filter { $0.isLetter || $0.isNumber }
    }
}

/// No free staging name was found for a resource within the attempt limit.
struct PhotosExportNameExhausted: Error {}
