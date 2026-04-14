import Foundation
import XCTest
@testable import ChronoframeAppCore

final class RunSessionStoreTests: XCTestCase {
    private var historyStore: HistoryStore!
    private var logStore: RunLogStore!
    private var tempDestinationURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        historyStore = HistoryStore()
        logStore = RunLogStore(capacity: 500)
        tempDestinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunSessionStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDestinationURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempDestinationURL {
            try? FileManager.default.removeItem(at: tempDestinationURL)
        }
        tempDestinationURL = nil
        historyStore = nil
        logStore = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testPreviewRunCompletesAndUpdatesSessionState() async throws {
        let configuration = RunConfiguration(mode: .preview, sourcePath: "/tmp/source", destinationPath: tempDestinationURL.path)
        let preflight = RunPreflight(
            configuration: configuration,
            resolvedSourcePath: configuration.sourcePath,
            resolvedDestinationPath: configuration.destinationPath
        )
        let summary = RunSummary(
            status: .dryRunFinished,
            title: "Preview complete",
            metrics: RunMetrics(discoveredCount: 3, plannedCount: 2, errorCount: 1),
            artifacts: RunArtifactPaths(
                destinationRoot: tempDestinationURL.path,
                reportPath: tempDestinationURL.appendingPathComponent(".organize_logs/report.csv").path,
                logFilePath: tempDestinationURL.appendingPathComponent(".organize_log.txt").path,
                logsDirectoryPath: tempDestinationURL.appendingPathComponent(".organize_logs", isDirectory: true).path
            )
        )
        let engine = MockOrganizerEngine(
            preflightResult: .success(preflight),
            startMode: .events([
                .startup,
                .phaseStarted(phase: .discovery, total: 3),
                .phaseCompleted(phase: .discovery, result: RunPhaseResult(found: 3)),
                .copyPlanReady(count: 2),
                .issue(RunIssue(severity: .error, message: "Checksum mismatch")),
                .complete(summary),
            ])
        )
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .preview, configuration: configuration)
        let finished = await waitForCondition { store.summary != nil }
        XCTAssertTrue(finished)

        XCTAssertEqual(store.status, .dryRunFinished)
        XCTAssertEqual(store.currentMode, .preview)
        XCTAssertEqual(store.metrics.discoveredCount, 3)
        XCTAssertEqual(store.metrics.plannedCount, 2)
        XCTAssertEqual(store.metrics.errorCount, 1)
        XCTAssertEqual(store.summary?.title, "Preview complete")
        XCTAssertEqual(engine.startConfigurations.count, 1)
        XCTAssertTrue(store.logLines.contains("Engine started."))
        XCTAssertTrue(store.logLines.contains("Plan ready: 2 files queued for copy."))
        XCTAssertTrue(store.logLines.contains("ERROR: Checksum mismatch"))
        XCTAssertTrue(store.logLines.contains("Finished: Preview complete"))
    }

    @MainActor
    func testTransferRunShowsResumePromptAndConfirmUsesResumeStream() async throws {
        let configuration = RunConfiguration(mode: .transfer, sourcePath: "/tmp/source", destinationPath: tempDestinationURL.path)
        let preflight = RunPreflight(
            configuration: configuration,
            resolvedSourcePath: configuration.sourcePath,
            resolvedDestinationPath: configuration.destinationPath,
            pendingJobCount: 4
        )
        let engine = MockOrganizerEngine(
            preflightResult: .success(preflight),
            resumeMode: .events([
                .complete(
                    RunSummary(
                        status: .finished,
                        title: "Done",
                        metrics: RunMetrics(copiedCount: 4),
                        artifacts: RunArtifactPaths(destinationRoot: tempDestinationURL.path)
                    )
                )
            ])
        )
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .transfer, configuration: configuration)

        XCTAssertEqual(store.prompt?.kind, .resumePendingJobs)
        XCTAssertEqual(store.prompt?.title, "Resume Pending Transfer")
        XCTAssertEqual(engine.resumeConfigurations.count, 0)

        store.confirmPrompt()
        let resumed = await waitForCondition { store.summary?.status == .finished }
        XCTAssertTrue(resumed)

        XCTAssertEqual(engine.resumeConfigurations.count, 1)
        XCTAssertEqual(store.status, .finished)
        XCTAssertNil(store.prompt)
    }

    @MainActor
    func testMissingDependenciesCreatesBlockingPrompt() async {
        let configuration = RunConfiguration(mode: .preview, sourcePath: "/tmp/source", destinationPath: tempDestinationURL.path)
        let preflight = RunPreflight(
            configuration: configuration,
            resolvedSourcePath: configuration.sourcePath,
            resolvedDestinationPath: configuration.destinationPath,
            missingDependencies: ["rich", "pyyaml"]
        )
        let engine = MockOrganizerEngine(preflightResult: .success(preflight))
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .preview, configuration: configuration)

        XCTAssertEqual(store.status, .preflighting)
        XCTAssertEqual(store.prompt?.kind, .blockingError)
        XCTAssertTrue(store.prompt?.message.contains("rich, pyyaml") ?? false)

        store.dismissPrompt()
        XCTAssertEqual(store.status, .idle)
        XCTAssertEqual(store.currentTaskTitle, "Idle")
    }

    @MainActor
    func testCancelCurrentRunMarksCancelled() async {
        let configuration = RunConfiguration(mode: .preview, sourcePath: "/tmp/source", destinationPath: tempDestinationURL.path)
        let preflight = RunPreflight(
            configuration: configuration,
            resolvedSourcePath: configuration.sourcePath,
            resolvedDestinationPath: configuration.destinationPath
        )
        let engine = MockOrganizerEngine(preflightResult: .success(preflight), startMode: .pending)
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .preview, configuration: configuration)
        let running = await waitForCondition { store.isRunning }
        XCTAssertTrue(running)

        store.cancelCurrentRun()
        let cancelled = await waitForCondition { store.status == .cancelled }
        XCTAssertTrue(cancelled)

        XCTAssertEqual(engine.cancelCallCount, 1)
        XCTAssertEqual(store.summary?.status, .cancelled)
        XCTAssertEqual(store.currentTaskTitle, "Cancelled")
    }

    @MainActor
    func testStartFailureMarksSessionFailed() async {
        let configuration = RunConfiguration(mode: .preview, sourcePath: "/tmp/source", destinationPath: tempDestinationURL.path)
        let preflight = RunPreflight(
            configuration: configuration,
            resolvedSourcePath: configuration.sourcePath,
            resolvedDestinationPath: configuration.destinationPath
        )
        let engine = MockOrganizerEngine(
            preflightResult: .success(preflight),
            startMode: .fails(TestFailure.expectedFailure("backend launch failed"))
        )
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .preview, configuration: configuration)
        let failed = await waitForCondition { store.status == .failed }
        XCTAssertTrue(failed)

        XCTAssertEqual(store.lastErrorMessage, "backend launch failed")
        XCTAssertEqual(store.summary?.status, .failed)
        XCTAssertTrue(store.logLines.contains("ERROR: backend launch failed"))
    }

    @MainActor
    func testBackendPromptEventSurfacesBlockingPrompt() async {
        let configuration = RunConfiguration(mode: .preview, sourcePath: "/tmp/source", destinationPath: tempDestinationURL.path)
        let preflight = RunPreflight(
            configuration: configuration,
            resolvedSourcePath: configuration.sourcePath,
            resolvedDestinationPath: configuration.destinationPath
        )
        let engine = MockOrganizerEngine(
            preflightResult: .success(preflight),
            startMode: .events([.prompt(message: "Need confirmation")])
        )
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .preview, configuration: configuration)
        let prompted = await waitForCondition { store.prompt != nil }
        XCTAssertTrue(prompted)

        XCTAssertEqual(store.prompt?.kind, .blockingError)
        XCTAssertEqual(store.prompt?.title, "Backend Prompt")
        XCTAssertEqual(store.prompt?.message, "Need confirmation")
    }
}
