import AppKit
import Combine
import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

/// Owns the watched-sources lifecycle: registry activation, FSEvents
/// watching, freshness scans, checkpoint advancement, and the Review &
/// Import handoff into the run pipeline.
///
/// Hard rules this coordinator enforces:
/// - The standing freshness path never touches a destination, its
///   `.organize_cache.db`, or the `DestinationOperationLock` — scans
///   stat the source tree only, and checkpoints live in App Support.
/// - Monitors start BEFORE catch-up scans (FSEvents SinceNow semantics)
///   and every scan is generation-tagged so an older detached scan can
///   never overwrite a newer result.
/// - Checkpoints only advance by merging stamps that were frozen when a
///   transfer was requested; failed or cancelled runs advance nothing.
@MainActor
final class SourceWatchCoordinator {
    private let store: WatchedSourcesStore
    private let preferencesStore: PreferencesStore
    private let setupStore: SetupStore
    private let runSessionStore: RunSessionStore
    private let folderAccessService: any FolderAccessServicing
    private let repository: any WatchedSourcesRepositorying
    private let scheduler: WatchedScanScheduler
    private let makeMonitor: @MainActor (String) -> any FileSystemMonitoring
    private let runScan: @Sendable (URL, Date) throws -> WatchedScanResult
    private let now: () -> Date
    private let deduplicateDestinationPath: @MainActor () -> String
    private let activeDestinationBookmarkKeys: @MainActor () -> [String]
    private let startImportPreview: @MainActor (WatchedImportContext) async -> Void
    private let invalidateImportContext: @MainActor () -> Void
    private let reportTransientError: @MainActor (String) -> Void
    private let workspaceNotificationCenter: NotificationCenter

    /// Per-source runtime state. `revision` invalidates in-flight work
    /// (scans, monitor loops) when a source is removed or re-picked.
    private struct WatchState {
        var monitor: (any FileSystemMonitoring)?
        var monitorTask: Task<Void, Never>?
        var access: SecurityScopedFolderAccess?
        var revision: Int = 0
        var scanGeneration: UInt64 = 0
        /// Live overlay of the source tree: the last complete scan's
        /// entries, updated incrementally by per-file events.
        var liveEntries: [String: WatchedFileStamp]?
        var lastPendingPaths: Set<String> = []
    }

    private var watchStates: [UUID: WatchState] = [:]
    private var started = false
    private var cancellables: Set<AnyCancellable> = []
    private var workspaceObservers: [NSObjectProtocol] = []
    /// Stamps frozen when a transfer was requested, keyed by that run's
    /// token. Only these may be acknowledged when the run finishes —
    /// files that arrive mid-run stay pending.
    private var frozenCapture: (token: UUID, stampsBySource: [UUID: [String: WatchedFileStamp]])?

    /// Above this many dirtied paths per batch (or on any directory
    /// event) the incremental check gives way to a full scan.
    private static let incrementalBatchLimit = 64

    init(
        store: WatchedSourcesStore,
        preferencesStore: PreferencesStore,
        setupStore: SetupStore,
        runSessionStore: RunSessionStore,
        folderAccessService: any FolderAccessServicing,
        repository: any WatchedSourcesRepositorying,
        scheduler: WatchedScanScheduler = WatchedScanScheduler(),
        makeMonitor: @escaping @MainActor (String) -> any FileSystemMonitoring = { path in
            FileSystemMonitor(paths: [path], latency: 2.0)
        },
        runScan: @escaping @Sendable (URL, Date) throws -> WatchedScanResult = { url, now in
            try WatchedSourceFreshness.scan(rootURL: url, now: now)
        },
        now: @escaping () -> Date = Date.init,
        deduplicateDestinationPath: @escaping @MainActor () -> String = { "" },
        activeDestinationBookmarkKeys: @escaping @MainActor () -> [String] = { [] },
        startImportPreview: @escaping @MainActor (WatchedImportContext) async -> Void = { _ in },
        invalidateImportContext: @escaping @MainActor () -> Void = {},
        reportTransientError: @escaping @MainActor (String) -> Void = { _ in },
        workspaceNotificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) {
        self.store = store
        self.preferencesStore = preferencesStore
        self.setupStore = setupStore
        self.runSessionStore = runSessionStore
        self.folderAccessService = folderAccessService
        self.repository = repository
        self.scheduler = scheduler
        self.makeMonitor = makeMonitor
        self.runScan = runScan
        self.now = now
        self.deduplicateDestinationPath = deduplicateDestinationPath
        self.activeDestinationBookmarkKeys = activeDestinationBookmarkKeys
        self.startImportPreview = startImportPreview
        self.invalidateImportContext = invalidateImportContext
        self.reportTransientError = reportTransientError
        self.workspaceNotificationCenter = workspaceNotificationCenter
    }

    static func bookmarkKey(for id: UUID) -> String {
        "watched.\(id.uuidString).source"
    }

    // MARK: - Lifecycle

    /// Idempotent. Called from the app's post-launch async hook — never
    /// from a synchronous initializer, because it does filesystem work.
    func start() async {
        guard !started else { return }
        started = true

        let sources: [WatchedSource]
        do {
            sources = try repository.loadSources()
        } catch {
            store.setStoreNotice(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }
        if repository.didQuarantineCorruptStore {
            store.setStoreNotice(
                "Chronoframe's watched-folders records were damaged and had to be rebuilt. Your folders are still watched, but each needs a fresh check — counts may take a moment to reappear. No photos were touched."
            )
        }
        store.load(sources)
        sweepOrphanedBookmarks(validIDs: Set(sources.map(\.id)))
        subscribeToAppSignals()

        for source in sources {
            activate(sourceID: source.id)
        }
    }

    func stop() {
        for id in Array(watchStates.keys) {
            deactivate(sourceID: id)
        }
        scheduler.cancelAll()
        cancellables.removeAll()
        for observer in workspaceObservers {
            workspaceNotificationCenter.removeObserver(observer)
        }
        workspaceObservers.removeAll()
        started = false
    }

    private func subscribeToAppSignals() {
        // Destination changes re-run conflict checks: watching pauses
        // for sources that now overlap and resumes when the conflict
        // clears.
        setupStore.$destinationPath
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.revalidateConflicts()
                }
            }
            .store(in: &cancellables)

        // Freeze acknowledgment captures the moment a transfer is
        // requested; merge them only when that same run finishes
        // successfully.
        runSessionStore.$status
            .sink { [weak self] status in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if status == .preflighting, self.runSessionStore.currentMode == .transfer {
                        self.freezeCapturesForCurrentRun()
                    }
                }
            }
            .store(in: &cancellables)

        runSessionStore.$lastRunCompletion
            .sink { [weak self] record in
                guard let record else { return }
                Task { @MainActor [weak self] in
                    self?.handleRunCompletion(record)
                }
            }
            .store(in: &cancellables)

        let mountObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.retryUnavailableSources()
            }
        }
        let unmountObserver = workspaceNotificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.deactivateSourcesOnMissingVolumes()
            }
        }
        workspaceObservers = [mountObserver, unmountObserver]
    }

    /// Bookmarks under `watched.` whose source id is no longer in the
    /// registry are leftovers from a crash between the registry delete
    /// and the bookmark delete — drop them.
    private func sweepOrphanedBookmarks(validIDs: Set<UUID>) {
        for key in preferencesStore.bookmarkKeys(withPrefix: "watched.") {
            let components = key.split(separator: ".")
            guard components.count == 3,
                  let id = UUID(uuidString: String(components[1]))
            else { continue }
            if !validIDs.contains(id) {
                preferencesStore.removeBookmark(for: key)
            }
        }
    }

    // MARK: - Activation

    /// Resolves access for one source and, when available, starts its
    /// monitor FIRST and then schedules the catch-up scan — anything
    /// that changes between the two is covered by the scan, anything
    /// after by the stream.
    private func activate(sourceID id: UUID) {
        guard let state = store.state(for: id) else { return }
        deactivate(sourceID: id, keepStoreEntry: true)
        var watchState = watchStates[id] ?? WatchState()
        watchState.revision += 1
        let revision = watchState.revision
        watchStates[id] = watchState

        guard let bookmark = preferencesStore.bookmark(for: Self.bookmarkKey(for: id)) else {
            store.setAvailability(id: id, .accessLost)
            return
        }

        guard let resolved = folderAccessService.resolveBookmark(bookmark) else {
            // Resolution failure alone cannot distinguish an ejected
            // volume from lost access; only claim access is lost when
            // the path is demonstrably present.
            let pathExists = FileManager.default.fileExists(atPath: state.source.path)
            store.setAvailability(id: id, pathExists ? .accessLost : .unavailable)
            return
        }
        if let refreshed = resolved.refreshedBookmark {
            preferencesStore.storeBookmark(refreshed)
        }

        let outcome = folderAccessService.verifiedScopedAccess(for: [bookmark])
        guard outcome.startedKeys.contains(bookmark.key) else {
            outcome.access.close()
            let pathExists = FileManager.default.fileExists(atPath: resolved.url.path)
            store.setAvailability(id: id, pathExists ? .accessLost : .unavailable)
            return
        }

        do {
            try folderAccessService.validateFolder(resolved.url, role: .source)
        } catch {
            outcome.access.close()
            let pathExists = FileManager.default.fileExists(atPath: resolved.url.path)
            store.setAvailability(id: id, pathExists ? .accessLost : .unavailable)
            return
        }

        if registrationConflictForExistingSource(path: resolved.url.path) != nil {
            outcome.access.close()
            store.setAvailability(id: id, .pausedConflict)
            return
        }

        let rootPath = resolved.url.path
        let monitor = makeMonitor(rootPath)
        watchStates[id]?.access = outcome.access
        watchStates[id]?.monitor = monitor

        let stream = monitor.start()
        watchStates[id]?.monitorTask = Task { @MainActor [weak self] in
            for await output in stream {
                guard let self, self.watchStates[id]?.revision == revision else { return }
                self.handleMonitorOutput(output, sourceID: id, rootPath: rootPath)
            }
        }

        store.setAvailability(id: id, .available)
        store.setDegradedWatch(id: id, monitor.isDegraded)
        scheduleScan(sourceID: id, immediate: true)
    }

    private func deactivate(sourceID id: UUID, keepStoreEntry: Bool = false) {
        scheduler.cancel(id: id)
        if var watchState = watchStates[id] {
            watchState.revision += 1
            watchState.monitorTask?.cancel()
            watchState.monitor?.stop()
            watchState.access?.close()
            watchState.monitorTask = nil
            watchState.monitor = nil
            watchState.access = nil
            if keepStoreEntry {
                watchStates[id] = watchState
            } else {
                watchStates[id] = nil
            }
        }
    }

    // MARK: - Monitor events

    private func handleMonitorOutput(_ output: FileSystemMonitorOutput, sourceID id: UUID, rootPath: String) {
        switch output {
        case .reconcileRequired:
            // Dropped events, subtree coalescing, root changes, polling
            // gaps: incremental state is untrustworthy. Full scan.
            watchStates[id]?.scanGeneration &+= 1
            if let monitor = watchStates[id]?.monitor {
                store.setDegradedWatch(id: id, monitor.isDegraded)
            }
            scheduleScan(sourceID: id, immediate: true)

        case .events(let events):
            let standardizedRoot = URL(fileURLWithPath: rootPath, isDirectory: true).standardizedFileURL.path
            if events.contains(where: { $0.isRemoved && URL(fileURLWithPath: $0.path).standardizedFileURL.path == standardizedRoot }) {
                // The watched root itself disappeared (eject, delete).
                deactivate(sourceID: id, keepStoreEntry: true)
                store.setAvailability(id: id, .unavailable)
                return
            }

            let relevant = events.filter { isRelevant($0, standardizedRoot: standardizedRoot) }
            guard !relevant.isEmpty else { return }
            watchStates[id]?.scanGeneration &+= 1

            let filePaths = relevant.filter(\.isFile).map(\.path)
            let hasDirectoryEvents = relevant.contains { !$0.isFile }
            if hasDirectoryEvents || filePaths.count > Self.incrementalBatchLimit || watchStates[id]?.liveEntries == nil {
                scheduleScan(sourceID: id)
            } else {
                applyIncrementalCheck(sourceID: id, dirtyPaths: filePaths, standardizedRoot: standardizedRoot)
            }
        }
    }

    /// Events inside the root, with no hidden path component, that the
    /// organize discovery filters would accept. Directory events stay
    /// relevant regardless of media rules — a new folder can contain
    /// anything, and FSEvents rename flags don't map onto
    /// created/modified, so relevance is deliberately flag-agnostic.
    private func isRelevant(_ event: FileSystemEvent, standardizedRoot: String) -> Bool {
        let path = URL(fileURLWithPath: event.path).standardizedFileURL.path
        guard path.hasPrefix(standardizedRoot + "/") else { return false }
        let relative = String(path.dropFirst(standardizedRoot.count + 1))
        if relative.split(separator: "/").contains(where: { $0.hasPrefix(".") }) {
            return false
        }
        if event.isFile {
            let name = URL(fileURLWithPath: path).lastPathComponent
            return MediaLibraryRules.isSupportedMediaFile(path: path)
                && !MediaLibraryRules.shouldSkipDiscoveredFile(named: name)
        }
        return true
    }

    /// Two-tier freshness, cheap tier: lstat only the dirtied paths and
    /// update the live overlay — no tree walk. Full reconciliation still
    /// happens at launch, refresh, mount, and reconcile signals.
    private func applyIncrementalCheck(sourceID id: UUID, dirtyPaths: [String], standardizedRoot: String) {
        guard var liveEntries = watchStates[id]?.liveEntries else {
            scheduleScan(sourceID: id)
            return
        }
        for path in dirtyPaths {
            let standardized = URL(fileURLWithPath: path).standardizedFileURL.path
            guard standardized.hasPrefix(standardizedRoot + "/") else { continue }
            let relative = String(standardized.dropFirst(standardizedRoot.count + 1))
            if let stamp = WatchedSourceFreshness.stamp(forPath: standardized) {
                liveEntries[relative] = stamp
            } else {
                liveEntries[relative] = nil
            }
        }
        watchStates[id]?.liveEntries = liveEntries
        recomputeEstimate(sourceID: id, entries: liveEntries, capturedAt: now(), fromCompleteScan: false)
    }

    // MARK: - Scans

    private func scheduleScan(sourceID id: UUID, immediate: Bool = false) {
        guard let state = store.state(for: id), state.availability == .available else { return }
        scheduler.schedule(id: id, immediate: immediate) { [weak self] in
            await self?.performScan(sourceID: id)
        }
    }

    private func performScan(sourceID id: UUID) async {
        guard let state = store.state(for: id),
              state.availability == .available,
              let watchState = watchStates[id]
        else { return }
        let revision = watchState.revision
        let generation = watchState.scanGeneration
        let rootURL = URL(fileURLWithPath: state.source.path, isDirectory: true)
        store.setChecking(id: id, true)

        let scanTime = now()
        let runScan = self.runScan
        let result: WatchedScanResult?
        do {
            result = try await Task.detached(priority: .utility) {
                try runScan(rootURL, scanTime)
            }.value
        } catch {
            result = nil
        }

        guard let currentState = watchStates[id], currentState.revision == revision else { return }
        guard let result else {
            // The scan itself failed (tree unreadable / root vanished
            // mid-walk). Never pretend to be caught up: keep the previous
            // estimate and flag the check as incomplete.
            store.markPartialScan(id: id)
            return
        }

        // Generation guard: if events arrived while this scan ran, its
        // result describes a stale tree — discard it, escalate backoff,
        // and let the rescheduled scan win. An older scan can never
        // overwrite a newer result.
        guard currentState.scanGeneration == generation else {
            scheduler.noteChurn(id: id)
            store.setChecking(id: id, false)
            scheduleScan(sourceID: id)
            return
        }

        guard result.completeness.isComplete else {
            store.markPartialScan(id: id)
            return
        }

        scheduler.noteQuiet(id: id)
        watchStates[id]?.liveEntries = result.entries

        // Checkpoint hygiene from complete scans only: drop acknowledged
        // entries for paths that no longer exist.
        if let checkpoint = try? repository.checkpoint(for: id) {
            let pruned = WatchedSourceFreshness.pruned(acknowledged: checkpoint, retainingKeysIn: result.entries)
            if pruned.count != checkpoint.count {
                try? repository.replaceCheckpoint(for: id, entries: pruned)
            }
        }

        recomputeEstimate(sourceID: id, entries: result.entries, capturedAt: result.capturedAt, fromCompleteScan: true)
    }

    private func recomputeEstimate(
        sourceID id: UUID,
        entries: [String: WatchedFileStamp],
        capturedAt: Date,
        fromCompleteScan: Bool
    ) {
        guard let checkpoint = try? repository.checkpoint(for: id) else {
            store.markPartialScan(id: id)
            return
        }
        let settled = WatchedSourceFreshness.settledEntries(entries, now: now())
        let pending = WatchedSourceFreshness.pendingRelativePaths(current: settled, acknowledged: checkpoint)

        // Attention generation: bump when the pending set GAINS entries,
        // so 1 → 0 → 1 re-alerts. The in-memory previous set starts
        // empty each session, which deliberately re-alerts for arrivals
        // that happened while the app was closed.
        let previousPending = watchStates[id]?.lastPendingPaths ?? []
        if !pending.subtracting(previousPending).isEmpty {
            if let newGeneration = try? repository.bumpChangeGeneration(id: id),
               var source = store.state(for: id)?.source {
                source.changeGeneration = newGeneration
                store.updateSource(source)
            }
        }
        watchStates[id]?.lastPendingPaths = pending

        if fromCompleteScan {
            store.applyCompleteScan(id: id, pendingEstimate: pending.count, capturedAt: capturedAt)
        } else {
            // Incremental updates refresh the number without claiming a
            // full check happened.
            if let state = store.state(for: id) {
                store.applyCompleteScan(
                    id: id,
                    pendingEstimate: pending.count,
                    capturedAt: state.lastCompleteScanAt ?? capturedAt
                )
            }
        }
    }

    // MARK: - Checkpoint advancement

    private func freezeCapturesForCurrentRun() {
        var stampsBySource: [UUID: [String: WatchedFileStamp]] = [:]
        for state in store.states where state.availability == .available {
            if let entries = watchStates[state.id]?.liveEntries {
                stampsBySource[state.id] = entries
            }
        }
        frozenCapture = (token: runSessionStore.currentRunToken, stampsBySource: stampsBySource)
    }

    private func handleRunCompletion(_ record: RunCompletionRecord) {
        guard record.mode == .transfer else { return }
        let frozen = frozenCapture
        frozenCapture = nil

        guard record.status == .finished || record.status == .nothingToCopy else {
            // Failure, abort, cancellation: acknowledge nothing —
            // overcounting is safer than hiding work.
            return
        }
        guard let frozen, frozen.token == record.runToken else { return }
        guard let resolvedSource = record.resolvedSourcePath else { return }
        let standardizedSource = URL(fileURLWithPath: resolvedSource, isDirectory: true).standardizedFileURL.path

        for state in store.states {
            let sourcePath = URL(fileURLWithPath: state.source.path, isDirectory: true).standardizedFileURL.path
            guard sourcePath == standardizedSource,
                  let captured = frozen.stampsBySource[state.id]
            else { continue }

            if let checkpoint = try? repository.checkpoint(for: state.id) {
                let merged = WatchedSourceFreshness.merged(acknowledged: checkpoint, acknowledging: captured)
                try? repository.replaceCheckpoint(for: state.id, entries: merged)
            }
            // Recount from the live overlay so mid-run arrivals surface
            // immediately as still-pending.
            if let liveEntries = watchStates[state.id]?.liveEntries {
                recomputeEstimate(sourceID: state.id, entries: liveEntries, capturedAt: now(), fromCompleteScan: false)
            }
            scheduleScan(sourceID: state.id)
        }
    }

    // MARK: - User actions

    func addSourceFolder() async {
        guard let url = folderAccessService.chooseFolder(
            startingAt: nil,
            prompt: "Watch Folder"
        ) else { return }
        await addSource(url: url)
    }

    func addSource(url: URL) async {
        do {
            try folderAccessService.validateFolder(url, role: .source)
        } catch {
            reportTransientError(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }

        if let conflict = WatchedSourcesStore.registrationConflict(
            candidatePath: url.path,
            destinationPaths: [setupStore.destinationPath, deduplicateDestinationPath()],
            existingWatchedPaths: store.states.map(\.source.path)
        ) {
            reportTransientError(conflict.errorDescription ?? "That folder can't be watched.")
            return
        }

        let source = WatchedSource(path: url.path, label: url.lastPathComponent)
        let key = Self.bookmarkKey(for: source.id)
        let bookmark: FolderBookmark
        do {
            bookmark = try folderAccessService.makeBookmark(for: url, key: key)
        } catch {
            reportTransientError(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }

        // Baseline snapshot: the count starts at 0 and signals arrivals
        // from now on; importing current contents stays available via
        // Review & Import.
        let scanTime = now()
        let runScan = self.runScan
        let baseline = (try? await Task.detached(priority: .utility) {
            try runScan(url, scanTime)
        }.value)
        let initialCheckpoint = (baseline?.completeness.isComplete == true) ? (baseline?.entries ?? [:]) : [:]

        // Ordering: bookmark first, registry transaction second, and the
        // bookmark rolls back if the transaction fails. (A crash between
        // the two leaves an orphan bookmark, swept at next launch.)
        preferencesStore.storeBookmark(bookmark)
        do {
            try repository.addSource(source, initialCheckpoint: initialCheckpoint)
        } catch {
            preferencesStore.removeBookmark(for: key)
            reportTransientError(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }

        store.insert(source)
        activate(sourceID: source.id)
    }

    func removeSource(id: UUID) {
        deactivate(sourceID: id)
        do {
            try repository.removeSource(id: id)
        } catch {
            reportTransientError(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }
        preferencesStore.removeBookmark(for: Self.bookmarkKey(for: id))
        store.remove(id: id)
        invalidateImportContext()
    }

    func repickSource(id: UUID) async {
        guard let state = store.state(for: id) else { return }
        guard let url = folderAccessService.chooseFolder(
            startingAt: state.source.path,
            prompt: "Choose Watched Folder"
        ) else { return }

        do {
            try folderAccessService.validateFolder(url, role: .source)
        } catch {
            reportTransientError(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }

        let otherPaths = store.states.filter { $0.id != id }.map(\.source.path)
        if let conflict = WatchedSourcesStore.registrationConflict(
            candidatePath: url.path,
            destinationPaths: [setupStore.destinationPath, deduplicateDestinationPath()],
            existingWatchedPaths: otherPaths
        ) {
            reportTransientError(conflict.errorDescription ?? "That folder can't be watched.")
            return
        }

        let key = Self.bookmarkKey(for: id)
        let bookmark: FolderBookmark
        do {
            bookmark = try folderAccessService.makeBookmark(for: url, key: key)
        } catch {
            reportTransientError(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }

        let pathChanged = URL(fileURLWithPath: state.source.path).standardizedFileURL.path
            != url.standardizedFileURL.path
        preferencesStore.storeBookmark(bookmark)
        do {
            try repository.replaceSourcePath(id: id, newPath: url.path, clearCheckpoint: pathChanged)
        } catch {
            reportTransientError(UserFacingErrorMessage.message(for: error, context: .watchedSources))
            return
        }

        var source = state.source
        source.path = url.path
        source.label = url.lastPathComponent
        store.updateSource(source)
        watchStates[id]?.liveEntries = nil
        watchStates[id]?.lastPendingPaths = []
        activate(sourceID: id)
    }

    /// "Ignore Current Items": acknowledges everything currently in the
    /// folder without importing it. Confirmation happens in the UI.
    func ignoreCurrentItems(id: UUID) async {
        guard let state = store.state(for: id), state.availability == .available else { return }
        let entries: [String: WatchedFileStamp]
        if let live = watchStates[id]?.liveEntries {
            entries = live
        } else {
            let scanTime = now()
            let runScan = self.runScan
            let rootURL = URL(fileURLWithPath: state.source.path, isDirectory: true)
            guard let result = try? await Task.detached(priority: .utility) {
                try runScan(rootURL, scanTime)
            }.value, result.completeness.isComplete else {
                reportTransientError("Chronoframe couldn't fully check this folder, so it can't safely ignore its items yet. Try again once the folder is readable.")
                return
            }
            entries = result.entries
        }

        guard let checkpoint = try? repository.checkpoint(for: id) else { return }
        let merged = WatchedSourceFreshness.merged(acknowledged: checkpoint, acknowledging: entries)
        try? repository.replaceCheckpoint(for: id, entries: merged)
        watchStates[id]?.liveEntries = entries
        recomputeEstimate(sourceID: id, entries: entries, capturedAt: now(), fromCompleteScan: false)
    }

    func refreshAll() {
        retryUnavailableSources()
        for state in store.states where state.availability == .available {
            watchStates[state.id]?.scanGeneration &+= 1
            scheduleScan(sourceID: state.id, immediate: true)
        }
    }

    /// Builds the import context (pinning the active destination and the
    /// source's own bookmark) and hands off to the run pipeline.
    func reviewAndImport(id: UUID) async {
        guard let state = store.state(for: id) else { return }
        guard state.availability == .available else {
            reportTransientError(unavailableImportMessage(for: state.availability))
            return
        }
        let destination = setupStore.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            reportTransientError("Choose a destination folder in Organize → Setup first; watched folders import into it.")
            return
        }
        guard let bookmark = preferencesStore.bookmark(for: Self.bookmarkKey(for: id)) else {
            store.setAvailability(id: id, .accessLost)
            reportTransientError("Chronoframe lost access to this folder. Choose it again to keep watching.")
            return
        }

        let context = WatchedImportContext(
            sourceID: id,
            sourceURL: URL(fileURLWithPath: state.source.path, isDirectory: true),
            sourceBookmark: bookmark,
            destinationPath: destination,
            destinationBookmarkKeys: activeDestinationBookmarkKeys(),
            capturedStamps: watchStates[id]?.liveEntries ?? [:],
            scanGeneration: watchStates[id]?.scanGeneration ?? 0
        )
        await startImportPreview(context)
    }

    private func unavailableImportMessage(for availability: WatchedSourceAvailability) -> String {
        switch availability {
        case .unavailable:
            return "This folder isn't reachable right now. Reconnect the drive, then try again."
        case .accessLost:
            return "Chronoframe lost access to this folder. Choose it again to restore access."
        case .pausedConflict:
            return "This folder overlaps your destination, so it can't be imported. Change the destination or remove the watched folder."
        case .available:
            return ""
        }
    }

    // MARK: - Availability transitions

    private func retryUnavailableSources() {
        for state in store.states where state.availability == .unavailable || state.availability == .accessLost {
            activate(sourceID: state.id)
        }
    }

    private func deactivateSourcesOnMissingVolumes() {
        for state in store.states where state.availability == .available {
            if !FileManager.default.fileExists(atPath: state.source.path) {
                deactivate(sourceID: state.id, keepStoreEntry: true)
                store.setAvailability(id: state.id, .unavailable)
            }
        }
    }

    private func revalidateConflicts() {
        for state in store.states {
            let conflictsNow = registrationConflictForExistingSource(path: state.source.path) != nil
            switch (state.availability, conflictsNow) {
            case (.available, true):
                deactivate(sourceID: state.id, keepStoreEntry: true)
                store.setAvailability(id: state.id, .pausedConflict)
            case (.pausedConflict, false):
                activate(sourceID: state.id)
            default:
                break
            }
        }
    }

    /// Overlap check for a source that is already registered (its own
    /// path is excluded from the watched-nesting comparison).
    private func registrationConflictForExistingSource(path: String) -> WatchedSourceRegistrationError? {
        let standardized = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL.path
        let otherPaths = store.states
            .map(\.source.path)
            .filter { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL.path != standardized }
        return WatchedSourcesStore.registrationConflict(
            candidatePath: path,
            destinationPaths: [setupStore.destinationPath, deduplicateDestinationPath()],
            existingWatchedPaths: otherPaths
        )
    }
}
