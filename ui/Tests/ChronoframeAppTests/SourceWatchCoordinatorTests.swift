#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

@MainActor
final class SourceWatchCoordinatorTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SourceWatchCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try await super.tearDown()
    }

    // MARK: - Test doubles

    /// Thread-safe ordered event log shared between MainActor code and
    /// the detached scan closure.
    private final class LogBox: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []
        func append(_ entry: String) {
            lock.lock(); defer { lock.unlock() }
            entries.append(entry)
        }
        var log: [String] {
            lock.lock(); defer { lock.unlock() }
            return entries
        }
    }

    private final class ScriptedMonitor: FileSystemMonitoring, @unchecked Sendable {
        private let lock = NSLock()
        private var continuation: AsyncStream<FileSystemMonitorOutput>.Continuation?
        private var startCountStorage = 0
        private var stoppedStorage = false
        var isDegraded = false
        let logBox: LogBox?

        init(logBox: LogBox? = nil) {
            self.logBox = logBox
        }

        func start() -> AsyncStream<FileSystemMonitorOutput> {
            lock.lock(); startCountStorage += 1; stoppedStorage = false; lock.unlock()
            logBox?.append("monitor-start")
            return AsyncStream { continuation in
                self.lock.lock()
                self.continuation = continuation
                self.lock.unlock()
            }
        }

        func stop() {
            lock.lock()
            stoppedStorage = true
            let continuation = self.continuation
            self.continuation = nil
            lock.unlock()
            continuation?.finish()
        }

        func send(_ output: FileSystemMonitorOutput) {
            lock.lock(); let continuation = self.continuation; lock.unlock()
            continuation?.yield(output)
        }

        var startCount: Int {
            lock.lock(); defer { lock.unlock() }
            return startCountStorage
        }
        var stopped: Bool {
            lock.lock(); defer { lock.unlock() }
            return stoppedStorage
        }
    }

    private final class InMemoryWatchedSourcesRepository: WatchedSourcesRepositorying {
        var sources: [WatchedSource] = []
        var checkpoints: [UUID: [String: WatchedFileStamp]] = [:]
        var didQuarantineCorruptStore = false
        var addFailure: Error?

        func loadSources() throws -> [WatchedSource] { sources }

        func addSource(_ source: WatchedSource, initialCheckpoint: [String: WatchedFileStamp]) throws {
            if let addFailure { throw addFailure }
            sources.append(source)
            checkpoints[source.id] = initialCheckpoint
        }

        func removeSource(id: UUID) throws {
            sources.removeAll { $0.id == id }
            checkpoints[id] = nil
        }

        var replacePathFailure: Error?

        func replaceSourcePath(id: UUID, newPath: String, clearCheckpoint: Bool) throws {
            if let replacePathFailure { throw replacePathFailure }
            guard let index = sources.firstIndex(where: { $0.id == id }) else {
                throw WatchedSourceDatabaseError.sourceNotFound(id)
            }
            sources[index].path = newPath
            if clearCheckpoint { checkpoints[id] = [:] }
        }

        func checkpoint(for id: UUID) throws -> [String: WatchedFileStamp] {
            checkpoints[id] ?? [:]
        }

        func replaceCheckpoint(for id: UUID, entries: [String: WatchedFileStamp]) throws {
            checkpoints[id] = entries
        }

        @discardableResult
        func bumpChangeGeneration(id: UUID) throws -> Int64 {
            guard let index = sources.firstIndex(where: { $0.id == id }) else {
                throw WatchedSourceDatabaseError.sourceNotFound(id)
            }
            sources[index].changeGeneration += 1
            return sources[index].changeGeneration
        }
    }

    /// FIFO-scripted scan results; the last result repeats. Optionally
    /// blocks each scan on a semaphore so tests can interleave events.
    private final class ScanScript: @unchecked Sendable {
        private let lock = NSLock()
        private var queue: [WatchedScanResult]
        private var startedStorage = 0
        var gate: DispatchSemaphore?
        let logBox: LogBox?

        init(results: [WatchedScanResult], logBox: LogBox? = nil) {
            self.queue = results
            self.logBox = logBox
        }

        func run(url: URL, now: Date) throws -> WatchedScanResult {
            lock.lock()
            startedStorage += 1
            let result = queue.count > 1 ? queue.removeFirst() : queue[0]
            let gate = self.gate
            lock.unlock()
            logBox?.append("scan")
            gate?.wait()
            return result
        }

        var started: Int {
            lock.lock(); defer { lock.unlock() }
            return startedStorage
        }
    }

    /// Old-enough stamp: mtime far in the past so the settling-window
    /// holdout never interferes with assertions.
    private func settledStamp(_ marker: Int64 = 1) -> WatchedFileStamp {
        WatchedFileStamp(sizeBytes: marker, mtimeNanoseconds: marker * 1_000, ctimeNanoseconds: marker * 1_000)
    }

    private func completeScan(_ entries: [String: WatchedFileStamp]) -> WatchedScanResult {
        WatchedScanResult(entries: entries, issues: [], completeness: .complete, capturedAt: Date())
    }

    private func partialScan(_ entries: [String: WatchedFileStamp]) -> WatchedScanResult {
        WatchedScanResult(
            entries: entries,
            issues: [MediaDiscovery.DirectoryIssue(path: "/locked", message: "unreadable")],
            completeness: .partial(unreadableSubtrees: 1),
            capturedAt: Date()
        )
    }

    // MARK: - Harness

    @MainActor
    private final class Harness {
        let appHarness: AppStateHarness
        let store: WatchedSourcesStore
        let repository: InMemoryWatchedSourcesRepository
        let monitor: ScriptedMonitor
        let logBox: LogBox
        let reportedErrors: ErrorLog
        let importedContexts: ContextLog
        let coordinator: SourceWatchCoordinator
        let sourceURL: URL
        let source: WatchedSource
        let workspaceCenter: NotificationCenter

        @MainActor final class ErrorLog {
            var messages: [String] = []
        }
        @MainActor final class ContextLog {
            var contexts: [WatchedImportContext] = []
            var invalidations = 0
        }

        init(
            testDirectory: URL,
            scanScript: ScanScript,
            registerSource: Bool = true,
            destinationPath: String = "",
            dedupeDestinationPath: String = "",
            logBox: LogBox = LogBox()
        ) {
            let appHarness = AppStateHarness()
            let store = WatchedSourcesStore()
            let repository = InMemoryWatchedSourcesRepository()
            let monitor = ScriptedMonitor(logBox: logBox)
            let errors = ErrorLog()
            let contexts = ContextLog()
            let workspaceCenter = NotificationCenter()

            let sourceURL = testDirectory.appendingPathComponent("watched-src", isDirectory: true)
            try? FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
            let source = WatchedSource(path: sourceURL.path, label: "watched-src")

            appHarness.setupStore.destinationPath = destinationPath
            appHarness.preferencesStore.lastDeduplicateDestinationPath = dedupeDestinationPath
            if registerSource {
                repository.sources = [source]
                repository.checkpoints[source.id] = [:]
                let key = SourceWatchCoordinator.bookmarkKey(for: source.id)
                appHarness.preferencesStore.storeBookmark(
                    FolderBookmark(key: key, path: sourceURL.path, data: Data(sourceURL.path.utf8))
                )
            }

            self.appHarness = appHarness
            self.store = store
            self.repository = repository
            self.logBox = logBox
            self.monitor = monitor
            self.reportedErrors = errors
            self.importedContexts = contexts
            self.workspaceCenter = workspaceCenter
            self.sourceURL = sourceURL
            self.source = source

            // Closures as separate locals: Swift 6.0.3 SILGen crashes on
            // one giant call expression with this many inline closures
            // (same workaround as AppState.makeSourceWatchCoordinator).
            let scheduler = WatchedScanScheduler(
                configuration: .init(maxConcurrent: 1, debounce: 0, backoffSteps: []),
                sleeper: { _ in }
            )
            let preferencesStore = appHarness.preferencesStore
            let makeMonitor: @MainActor (String) -> any FileSystemMonitoring = { _ in monitor }
            let runScan: @Sendable (URL, Date) throws -> WatchedScanResult = { url, now in
                try scanScript.run(url: url, now: now)
            }
            let deduplicateDestinationPath: @MainActor () -> String = {
                preferencesStore.lastDeduplicateDestinationPath
            }
            let activeDestinationBookmarkKeys: @MainActor () -> [String] = { ["manual.destination"] }
            let startImportPreview: @MainActor (WatchedImportContext) async -> Void = { context in
                contexts.contexts.append(context)
            }
            let invalidateImportContext: @MainActor () -> Void = {
                contexts.invalidations += 1
            }
            let reportTransientError: @MainActor (String) -> Void = { message in
                errors.messages.append(message)
            }

            self.coordinator = SourceWatchCoordinator(
                store: store,
                preferencesStore: appHarness.preferencesStore,
                setupStore: appHarness.setupStore,
                runSessionStore: appHarness.runSessionStore,
                folderAccessService: appHarness.folderAccessService,
                repository: repository,
                scheduler: scheduler,
                makeMonitor: makeMonitor,
                runScan: runScan,
                deduplicateDestinationPath: deduplicateDestinationPath,
                activeDestinationBookmarkKeys: activeDestinationBookmarkKeys,
                startImportPreview: startImportPreview,
                invalidateImportContext: invalidateImportContext,
                reportTransientError: reportTransientError,
                workspaceNotificationCenter: workspaceCenter
            )
        }
    }

    // MARK: - Activation and catch-up

    func testStartActivatesSourceStartsMonitorBeforeCatchUpScan() async {
        let orderLog = LogBox()
        let script = ScanScript(results: [completeScan(["a.jpg": settledStamp()])], logBox: orderLog)
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script, logBox: orderLog)

        await harness.coordinator.start()

        let counted = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 1 }
        XCTAssertTrue(counted, "Catch-up scan must produce the arrived-while-closed estimate")
        XCTAssertEqual(harness.store.state(for: harness.source.id)?.availability, .available)

        // Ordering contract: the monitor was live before the scan ran.
        let log = harness.logBox.log
        XCTAssertEqual(log.first, "monitor-start")
        XCTAssertTrue(log.contains("scan"))
        XCTAssertLessThan(
            log.firstIndex(of: "monitor-start") ?? .max,
            log.firstIndex(of: "scan") ?? .min,
            "Monitor must start BEFORE the catch-up scan (SinceNow semantics)"
        )
        harness.coordinator.stop()
    }

    func testStartWithoutBookmarkMarksAccessLost() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)
        harness.appHarness.preferencesStore.removeBookmark(
            for: SourceWatchCoordinator.bookmarkKey(for: harness.source.id)
        )

        await harness.coordinator.start()

        XCTAssertEqual(harness.store.state(for: harness.source.id)?.availability, .accessLost)
        XCTAssertEqual(harness.monitor.startCount, 0)
        harness.coordinator.stop()
    }

    /// Bookmark resolution failure with the path absent is an ejected
    /// volume, not lost access — the registry entry is kept and the
    /// state is retryable.
    func testUnresolvableBookmarkWithMissingPathIsUnavailableNotAccessLost() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)
        let key = SourceWatchCoordinator.bookmarkKey(for: harness.source.id)
        harness.appHarness.folderAccessService.bookmarkResolutionFailures.insert(key)
        try? FileManager.default.removeItem(at: harness.sourceURL)

        await harness.coordinator.start()

        XCTAssertEqual(harness.store.state(for: harness.source.id)?.availability, .unavailable)
        XCTAssertEqual(harness.repository.sources.count, 1, "Registry entry must be kept — an absent SD card is normal")
        harness.coordinator.stop()
    }

    func testUnresolvableBookmarkWithPresentPathIsAccessLost() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)
        let key = SourceWatchCoordinator.bookmarkKey(for: harness.source.id)
        harness.appHarness.folderAccessService.bookmarkResolutionFailures.insert(key)

        await harness.coordinator.start()

        XCTAssertEqual(harness.store.state(for: harness.source.id)?.availability, .accessLost)
        harness.coordinator.stop()
    }

    func testScopeStartFailureWithPresentPathIsAccessLost() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)
        let key = SourceWatchCoordinator.bookmarkKey(for: harness.source.id)
        harness.appHarness.folderAccessService.scopeStartFailures.insert(key)

        await harness.coordinator.start()

        XCTAssertEqual(harness.store.state(for: harness.source.id)?.availability, .accessLost)
        harness.coordinator.stop()
    }

    func testQuarantinedStoreSurfacesNotice() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)
        harness.repository.didQuarantineCorruptStore = true

        await harness.coordinator.start()

        XCTAssertNotNil(harness.store.storeNotice)
        XCTAssertTrue(harness.store.storeNotice?.contains("No photos were touched") == true)
        harness.coordinator.stop()
    }

    func testOrphanedWatchedBookmarksAreSweptAtStart() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)
        let orphanID = UUID()
        let orphanKey = SourceWatchCoordinator.bookmarkKey(for: orphanID)
        harness.appHarness.preferencesStore.storeBookmark(
            FolderBookmark(key: orphanKey, path: "/gone", data: Data())
        )

        await harness.coordinator.start()

        XCTAssertNil(harness.appHarness.preferencesStore.bookmark(for: orphanKey),
                     "Bookmarks whose registry row is gone must be swept")
        XCTAssertNotNil(
            harness.appHarness.preferencesStore.bookmark(
                for: SourceWatchCoordinator.bookmarkKey(for: harness.source.id)
            ),
            "Live bookmarks stay"
        )
        harness.coordinator.stop()
    }

    // MARK: - Events

    func testRootRemovalMarksUnavailableAndMountNotificationRecovers() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate != nil }

        harness.monitor.send(.events([
            FileSystemEvent(path: harness.sourceURL.path, isRemoved: true)
        ]))

        let offline = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .unavailable
        }
        XCTAssertTrue(offline)
        XCTAssertTrue(harness.monitor.stopped)

        harness.workspaceCenter.post(name: NSWorkspace.didMountNotification, object: nil)
        let recovered = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .available
        }
        XCTAssertTrue(recovered, "Mount notifications retry unavailable sources")
        harness.coordinator.stop()
    }

    func testIncrementalFileEventUpdatesEstimateWithoutFullScan() async throws {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 0 }
        let scansAfterCatchUp = script.started

        // A real file so the incremental lstat path works; mtime pushed
        // outside the settling window.
        let fileURL = harness.sourceURL.appendingPathComponent("IMG_0001.jpg")
        try Data("jpg".utf8).write(to: fileURL)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)],
            ofItemAtPath: fileURL.path
        )

        harness.monitor.send(.events([
            FileSystemEvent(path: fileURL.path, isFile: true, isCreated: true)
        ]))

        let counted = await waitForCondition {
            harness.store.state(for: harness.source.id)?.pendingEstimate == 1
        }
        XCTAssertTrue(counted)
        XCTAssertEqual(script.started, scansAfterCatchUp,
                       "A small file batch takes the incremental path — no tree walk")
        harness.coordinator.stop()
    }

    func testIrrelevantEventsDoNotTriggerWork() async throws {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 0 }
        let scansAfterCatchUp = script.started
        let estimateBefore = harness.store.state(for: harness.source.id)?.pendingEstimate

        harness.monitor.send(.events([
            FileSystemEvent(path: harness.sourceURL.appendingPathComponent(".DS_Store").path, isFile: true, isModified: true),
            FileSystemEvent(path: harness.sourceURL.appendingPathComponent("notes.txt").path, isFile: true, isCreated: true),
            FileSystemEvent(path: harness.sourceURL.appendingPathComponent(".hidden/IMG.jpg").path, isFile: true, isCreated: true),
            FileSystemEvent(path: "/outside/IMG.jpg", isFile: true, isCreated: true)
        ]))

        try await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(script.started, scansAfterCatchUp)
        XCTAssertEqual(harness.store.state(for: harness.source.id)?.pendingEstimate, estimateBefore)
        harness.coordinator.stop()
    }

    func testDirectoryEventTriggersFullScan() async {
        let script = ScanScript(results: [
            completeScan([:]),
            completeScan(["new-dir/IMG_0002.jpg": settledStamp(2)])
        ])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 0 }

        harness.monitor.send(.events([
            FileSystemEvent(path: harness.sourceURL.appendingPathComponent("new-dir").path, isFile: false, isCreated: true)
        ]))

        let counted = await waitForCondition {
            harness.store.state(for: harness.source.id)?.pendingEstimate == 1
        }
        XCTAssertTrue(counted, "Directory events reconcile with a full scan")
        harness.coordinator.stop()
    }

    func testReconcileSignalForcesFullScan() async {
        let script = ScanScript(results: [
            completeScan([:]),
            completeScan(["dropped/IMG_0003.jpg": settledStamp(3)])
        ])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 0 }

        harness.monitor.send(.reconcileRequired(.droppedEvents))

        let counted = await waitForCondition {
            harness.store.state(for: harness.source.id)?.pendingEstimate == 1
        }
        XCTAssertTrue(counted, "Dropped-events signals must force reconciliation")
        harness.coordinator.stop()
    }

    /// Partial scans never update counts or checkpoints: the previous
    /// complete estimate stays, and the state is flagged.
    func testPartialScanPreservesPreviousEstimate() async {
        let script = ScanScript(results: [
            completeScan(["a.jpg": settledStamp()]),
            partialScan([:])
        ])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 1 }

        harness.monitor.send(.reconcileRequired(.mustScanSubDirs))

        let flagged = await waitForCondition {
            harness.store.state(for: harness.source.id)?.lastScanWasPartial == true
        }
        XCTAssertTrue(flagged)
        XCTAssertEqual(harness.store.state(for: harness.source.id)?.pendingEstimate, 1,
                       "An unreadable scan must not pretend to be caught up")
        harness.coordinator.stop()
    }

    /// Generation guard: a scan whose tree changed while it ran is
    /// discarded — an older scan can never overwrite a newer result.
    func testStaleScanResultIsDiscardedAndRescanWins() async {
        let script = ScanScript(results: [
            completeScan(["stale.jpg": settledStamp(1)]),
            completeScan(["fresh-dir/a.jpg": settledStamp(2), "fresh-dir/b.jpg": settledStamp(3)])
        ])
        let gate = DispatchSemaphore(value: 0)
        script.gate = gate
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        let firstScanStarted = await waitForCondition { script.started == 1 }
        XCTAssertTrue(firstScanStarted)

        // The tree changes while the first scan is still walking.
        harness.monitor.send(.events([
            FileSystemEvent(path: harness.sourceURL.appendingPathComponent("fresh-dir").path, isFile: false, isCreated: true)
        ]))
        try? await Task.sleep(nanoseconds: 100_000_000)

        gate.signal()  // first (now stale) scan returns
        let secondScanStarted = await waitForCondition(timeoutNanoseconds: 3_000_000_000) { script.started == 2 }
        XCTAssertTrue(secondScanStarted, "The stale result must trigger a rescan")
        XCTAssertNotEqual(harness.store.state(for: harness.source.id)?.pendingEstimate, 1,
                          "The stale scan's count must never be shown")

        gate.signal()  // second scan returns
        let counted = await waitForCondition(timeoutNanoseconds: 3_000_000_000) {
            harness.store.state(for: harness.source.id)?.pendingEstimate == 2
        }
        XCTAssertTrue(counted)
        harness.coordinator.stop()
    }

    // MARK: - Checkpoint advancement

    func testSuccessfulWatchedTransferAcknowledgesOnlyFrozenStampsSoMidRunArrivalsStayPending() async throws {
        // Second scripted result mirrors the live tree after the mid-run
        // arrival, so the post-merge reconciliation scan agrees with the
        // incremental overlay instead of overwriting it.
        let script = ScanScript(results: [
            completeScan(["a.jpg": settledStamp(1)]),
            completeScan(["a.jpg": settledStamp(1), "mid-run.jpg": settledStamp(2)])
        ])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script, destinationPath: "/tmp/library")

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 1 }

        // Engine canned preflight resolves to the watched source path.
        harness.appHarness.engine.preflightResult = .success(RunPreflight(
            configuration: RunConfiguration(mode: .transfer, sourcePath: harness.sourceURL.path, destinationPath: "/tmp/library"),
            resolvedSourcePath: harness.sourceURL.path,
            resolvedDestinationPath: "/tmp/library"
        ))
        harness.appHarness.engine.startMode = .events([
            .complete(RunSummary(
                status: .finished,
                title: "Transfer complete",
                metrics: RunMetrics(copiedCount: 1),
                artifacts: RunArtifactPaths(destinationRoot: "/tmp/library")
            ))
        ])

        // Request the transfer; the freeze happens at request time.
        await harness.appHarness.runSessionStore.requestRun(
            mode: .transfer,
            configuration: RunConfiguration(mode: .transfer, sourcePath: harness.sourceURL.path, destinationPath: "/tmp/library")
        )
        let promptShown = await waitForCondition { harness.appHarness.runSessionStore.prompt != nil }
        XCTAssertTrue(promptShown)

        // A file lands MID-RUN (after the freeze) — a real file so the
        // incremental path stamps it.
        let midRunFile = harness.sourceURL.appendingPathComponent("mid-run.jpg")
        try Data("late".utf8).write(to: midRunFile)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(-60)],
            ofItemAtPath: midRunFile.path
        )
        harness.monitor.send(.events([
            FileSystemEvent(path: midRunFile.path, isFile: true, isCreated: true)
        ]))
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 2 }

        harness.appHarness.runSessionStore.confirmPrompt()
        let finished = await waitForCondition {
            harness.appHarness.runSessionStore.summary?.status == .finished
        }
        XCTAssertTrue(finished)

        let acknowledged = await waitForCondition {
            (try? harness.repository.checkpoint(for: harness.source.id))?.keys.contains("a.jpg") == true
        }
        XCTAssertTrue(acknowledged, "Frozen stamps merge on success")
        let stillPending = await waitForCondition {
            harness.store.state(for: harness.source.id)?.pendingEstimate == 1
        }
        XCTAssertTrue(stillPending, "The mid-run arrival was never reviewed — it must stay pending")
        XCTAssertNil(try harness.repository.checkpoint(for: harness.source.id)["mid-run.jpg"],
                     "Mid-run arrivals are never acknowledged")
        harness.coordinator.stop()
    }

    func testFailedTransferAcknowledgesNothing() async {
        struct TestError: Error {}
        let script = ScanScript(results: [completeScan(["a.jpg": settledStamp(1)])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script, destinationPath: "/tmp/library")

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 1 }

        harness.appHarness.engine.preflightResult = .success(RunPreflight(
            configuration: RunConfiguration(mode: .transfer, sourcePath: harness.sourceURL.path, destinationPath: "/tmp/library"),
            resolvedSourcePath: harness.sourceURL.path,
            resolvedDestinationPath: "/tmp/library"
        ))
        harness.appHarness.engine.startMode = .fails(TestError())

        await harness.appHarness.runSessionStore.requestRun(
            mode: .transfer,
            configuration: RunConfiguration(mode: .transfer, sourcePath: harness.sourceURL.path, destinationPath: "/tmp/library")
        )
        harness.appHarness.runSessionStore.confirmPrompt()
        let failed = await waitForCondition {
            harness.appHarness.runSessionStore.status == .failed
        }
        XCTAssertTrue(failed)

        try? await Task.sleep(nanoseconds: 150_000_000)
        XCTAssertEqual(try? harness.repository.checkpoint(for: harness.source.id), [:],
                       "Failure acknowledges nothing — overcounting over hiding")
        XCTAssertEqual(harness.store.state(for: harness.source.id)?.pendingEstimate, 1)
        harness.coordinator.stop()
    }

    // MARK: - Conflicts

    func testDestinationChangeSuspendsConflictingSourceAndRestores() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.availability == .available }

        // The destination moves INSIDE the watched folder.
        harness.appHarness.setupStore.destinationPath = harness.sourceURL.appendingPathComponent("organized").path
        let paused = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .pausedConflict
        }
        XCTAssertTrue(paused)
        XCTAssertTrue(harness.monitor.stopped)

        // Conflict clears.
        harness.appHarness.setupStore.destinationPath = temporaryDirectoryURL.appendingPathComponent("library").path
        let restored = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .available
        }
        XCTAssertTrue(restored)
        harness.coordinator.stop()
    }

    // MARK: - User actions

    func testIgnoreCurrentItemsAcknowledgesLiveEntries() async {
        let script = ScanScript(results: [completeScan(["a.jpg": settledStamp(1), "b.jpg": settledStamp(2)])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 2 }

        await harness.coordinator.ignoreCurrentItems(id: harness.source.id)

        XCTAssertEqual(harness.store.state(for: harness.source.id)?.pendingEstimate, 0)
        XCTAssertEqual((try? harness.repository.checkpoint(for: harness.source.id))?.count, 2)
        harness.coordinator.stop()
    }

    func testReviewAndImportBuildsPinnedContext() async {
        let script = ScanScript(results: [completeScan(["a.jpg": settledStamp(1)])])
        let harness = Harness(
            testDirectory: temporaryDirectoryURL,
            scanScript: script,
            destinationPath: "/tmp/library"
        )

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 1 }

        await harness.coordinator.reviewAndImport(id: harness.source.id)

        XCTAssertEqual(harness.importedContexts.contexts.count, 1)
        let context = harness.importedContexts.contexts[0]
        XCTAssertEqual(context.sourceID, harness.source.id)
        XCTAssertEqual(context.sourceURL.path, harness.sourceURL.path)
        XCTAssertEqual(context.destinationPath, "/tmp/library")
        XCTAssertEqual(context.destinationBookmarkKeys, ["manual.destination"])
        XCTAssertEqual(context.sourceBookmark.key, SourceWatchCoordinator.bookmarkKey(for: harness.source.id))
        XCTAssertEqual(context.capturedStamps.keys.sorted(), ["a.jpg"])
        harness.coordinator.stop()
    }

    func testReviewAndImportRequiresDestinationAndAvailability() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script, destinationPath: "")

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.availability == .available }

        await harness.coordinator.reviewAndImport(id: harness.source.id)
        XCTAssertTrue(harness.importedContexts.contexts.isEmpty)
        XCTAssertEqual(harness.reportedErrors.messages.count, 1)
        XCTAssertTrue(harness.reportedErrors.messages[0].contains("destination"))

        harness.store.setAvailability(id: harness.source.id, .unavailable)
        await harness.coordinator.reviewAndImport(id: harness.source.id)
        XCTAssertTrue(harness.importedContexts.contexts.isEmpty)
        XCTAssertEqual(harness.reportedErrors.messages.count, 2)
        harness.coordinator.stop()
    }

    func testAddSourceRejectsOverlapAndRollsBackBookmarkOnRepositoryFailure() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(
            testDirectory: temporaryDirectoryURL,
            scanScript: script,
            registerSource: false,
            destinationPath: temporaryDirectoryURL.appendingPathComponent("library").path
        )

        // Overlap: candidate inside the destination.
        let insideDestination = temporaryDirectoryURL.appendingPathComponent("library/incoming", isDirectory: true)
        try? FileManager.default.createDirectory(at: insideDestination, withIntermediateDirectories: true)
        await harness.coordinator.addSource(url: insideDestination)
        XCTAssertTrue(harness.repository.sources.isEmpty)
        XCTAssertEqual(harness.reportedErrors.messages.count, 1)

        // Repository failure: the just-stored bookmark rolls back.
        struct DBError: Error {}
        harness.repository.addFailure = DBError()
        let goodFolder = temporaryDirectoryURL.appendingPathComponent("inbox", isDirectory: true)
        try? FileManager.default.createDirectory(at: goodFolder, withIntermediateDirectories: true)
        await harness.coordinator.addSource(url: goodFolder)

        XCTAssertTrue(harness.repository.sources.isEmpty)
        XCTAssertEqual(harness.appHarness.preferencesStore.bookmarkKeys(withPrefix: "watched."), [],
                       "A failed registry write must roll the bookmark back")
        harness.coordinator.stop()
    }

    /// Re-alert semantics: a pending set that regains an entry after
    /// being acknowledged bumps the persisted generation, so the sidebar
    /// token differs even though the count (1) repeats.
    func testRegainedPendingItemBumpsGenerationForNewAttention() async {
        let script = ScanScript(results: [
            completeScan(["first.jpg": settledStamp(1)]),
            completeScan(["first.jpg": settledStamp(1), "second.jpg": settledStamp(2)])
        ])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 1 }
        let firstToken = harness.store.attentionToken
        XCTAssertFalse(firstToken.isEmpty)

        await harness.coordinator.ignoreCurrentItems(id: harness.source.id)
        XCTAssertEqual(harness.store.state(for: harness.source.id)?.pendingEstimate, 0)
        XCTAssertTrue(harness.store.attentionToken.isEmpty)

        harness.monitor.send(.reconcileRequired(.mustScanSubDirs))
        let regained = await waitForCondition {
            harness.store.state(for: harness.source.id)?.pendingEstimate == 1
        }
        XCTAssertTrue(regained)
        XCTAssertNotEqual(harness.store.attentionToken, firstToken,
                          "1 → 0 → 1 must produce NEW attention")
        harness.coordinator.stop()
    }

    /// A quarantined (corrupt) store must not lose the user's watched
    /// folders: registry rows are rebuilt from the surviving bookmarks,
    /// and the orphan sweep must not delete them.
    func testQuarantineRebuildsRegistryFromBookmarksInsteadOfSweepingThem() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)
        // Simulate the post-quarantine state: bookmarks survive, the
        // replacement database is empty.
        harness.repository.didQuarantineCorruptStore = true
        harness.repository.sources = []
        harness.repository.checkpoints = [:]

        await harness.coordinator.start()

        let key = SourceWatchCoordinator.bookmarkKey(for: harness.source.id)
        XCTAssertNotNil(harness.appHarness.preferencesStore.bookmark(for: key),
                        "The surviving bookmark must not be swept as an orphan")
        XCTAssertEqual(harness.repository.sources.map(\.id), [harness.source.id],
                       "The registry row is rebuilt from the bookmark")
        XCTAssertEqual(harness.store.states.map(\.id), [harness.source.id])
        let watching = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .available
        }
        XCTAssertTrue(watching, "The rebuilt source resumes watching")
        harness.coordinator.stop()
    }

    /// A WatchRoot root-change whose path no longer exists is an eject
    /// or delete — the source must go .unavailable (retryable), not stay
    /// .available behind a "couldn't fully check" flag.
    func testRootChangedWithMissingPathMarksUnavailable() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate == 0 }

        try? FileManager.default.removeItem(at: harness.sourceURL)
        harness.monitor.send(.reconcileRequired(.rootChanged))

        let offline = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .unavailable
        }
        XCTAssertTrue(offline)
        XCTAssertTrue(harness.monitor.stopped)
        harness.coordinator.stop()
    }

    /// If the registry update fails during re-pick, the just-stored
    /// bookmark must roll back so bookmark and registry never diverge.
    func testRepickRollsBackBookmarkWhenRegistryUpdateFails() async {
        struct DBError: Error {}
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.availability == .available }

        let newFolder = temporaryDirectoryURL.appendingPathComponent("repicked", isDirectory: true)
        try? FileManager.default.createDirectory(at: newFolder, withIntermediateDirectories: true)
        harness.appHarness.folderAccessService.nextChosenFolder = newFolder
        harness.repository.replacePathFailure = DBError()

        await harness.coordinator.repickSource(id: harness.source.id)

        let key = SourceWatchCoordinator.bookmarkKey(for: harness.source.id)
        XCTAssertEqual(
            harness.appHarness.preferencesStore.bookmark(for: key)?.path,
            harness.sourceURL.path,
            "The old bookmark must be restored when the registry write fails"
        )
        XCTAssertEqual(harness.repository.sources.first?.path, harness.sourceURL.path)
        XCTAssertEqual(harness.reportedErrors.messages.count, 1)
        harness.coordinator.stop()
    }

    /// Choosing a dedicated Deduplicate folder that overlaps a watched
    /// source must pause it, exactly like an Organize destination change.
    func testDedupeDestinationChangeSuspendsConflictingSource() async {
        let script = ScanScript(results: [completeScan([:])])
        let harness = Harness(testDirectory: temporaryDirectoryURL, scanScript: script)

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.availability == .available }

        harness.appHarness.preferencesStore.lastDeduplicateDestinationPath =
            harness.sourceURL.appendingPathComponent("dedupe-workspace").path

        let paused = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .pausedConflict
        }
        XCTAssertTrue(paused)

        harness.appHarness.preferencesStore.lastDeduplicateDestinationPath = ""
        let restored = await waitForCondition {
            harness.store.state(for: harness.source.id)?.availability == .available
        }
        XCTAssertTrue(restored)
        harness.coordinator.stop()
    }

    /// Locked behavior: the standing watch/catch-up cycle must never
    /// touch the destination — no cache database, no logs directory, no
    /// lock file, byte-identical listing.
    func testWatchCycleNeverTouchesDestination() async throws {
        let destination = temporaryDirectoryURL.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("existing".utf8).write(to: destination.appendingPathComponent("existing.jpg"))

        // Real scans (default pipeline) against a real source tree.
        let script = ScanScript(results: [completeScan(["real.jpg": settledStamp(1)])])
        let harness = Harness(
            testDirectory: temporaryDirectoryURL,
            scanScript: script,
            destinationPath: destination.path
        )
        try Data("real".utf8).write(to: harness.sourceURL.appendingPathComponent("real.jpg"))

        let listingBefore = try FileManager.default
            .contentsOfDirectory(atPath: destination.path).sorted()

        await harness.coordinator.start()
        _ = await waitForCondition { harness.store.state(for: harness.source.id)?.pendingEstimate != nil }
        harness.monitor.send(.reconcileRequired(.droppedEvents))
        _ = await waitForCondition { script.started >= 2 }
        await harness.coordinator.ignoreCurrentItems(id: harness.source.id)

        let listingAfter = try FileManager.default
            .contentsOfDirectory(atPath: destination.path).sorted()
        XCTAssertEqual(listingAfter, listingBefore, "The standing path must never write to the destination")
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(".organize_cache.db").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destination.appendingPathComponent(".organize_logs").path
        ), "No lock or logs directory may appear — the watch path never takes the destination lock")
        harness.coordinator.stop()
    }
}
