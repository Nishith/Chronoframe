#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

final class RunCoordinatorTests: XCTestCase {
    @MainActor
    func testStartPreviewSelectsRunAndFinderActionsUseArtifacts() async {
        let harness = AppStateHarness()
        harness.setupStore.sourcePath = "/tmp/source"
        harness.setupStore.destinationPath = "/tmp/destination"
        harness.engine.startMode = .events([
            .complete(
                RunSummary(
                    status: .dryRunFinished,
                    title: "Preview complete",
                    metrics: RunMetrics(plannedCount: 1),
                    artifacts: RunArtifactPaths(
                        destinationRoot: "/tmp/destination",
                        reportPath: "/tmp/destination/.organize_logs/dry_run_report.csv",
                        logFilePath: "/tmp/destination/.organize_log.txt",
                        logsDirectoryPath: "/tmp/destination/.organize_logs"
                    )
                )
            )
        ])
        var route: AppRoute?
        let coordinator = RunCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            runSessionStore: harness.runSessionStore,
            finderService: harness.finderService,
            showSettingsWindowAction: {},
            navigate: { route = $0 },
            canStartRun: { true }
        )

        await coordinator.startPreview()
        let finished = await waitForCondition { harness.runSessionStore.summary != nil }

        XCTAssertTrue(finished)
        XCTAssertEqual(route, .organize(.run))
        XCTAssertEqual(harness.engine.startConfigurations.count, 1)

        coordinator.openDestination()
        coordinator.openReport()
        coordinator.openLogsDirectory()

        XCTAssertEqual(harness.finderService.openedPaths, [
            "/tmp/destination",
            "/tmp/destination/.organize_logs/dry_run_report.csv",
            "/tmp/destination/.organize_logs",
        ])
    }

    @MainActor
    func testStartTransferPromptRoutingDismissalAndSettingsStayWired() async {
        let harness = AppStateHarness()
        harness.setupStore.sourcePath = "/tmp/source"
        harness.setupStore.destinationPath = "/tmp/destination"
        harness.engine.preflightResult = .success(
            RunPreflight(
                configuration: RunConfiguration(mode: .transfer, sourcePath: "/tmp/source", destinationPath: "/tmp/destination"),
                resolvedSourcePath: "/tmp/source",
                resolvedDestinationPath: "/tmp/destination",
                pendingJobCount: 2
            )
        )
        harness.engine.resumeMode = .events([
            .complete(
                RunSummary(
                    status: .finished,
                    title: "Transfer complete",
                    metrics: RunMetrics(copiedCount: 3),
                    artifacts: RunArtifactPaths(destinationRoot: "/tmp/destination")
                )
            )
        ])
        var route: AppRoute?
        var settingsOpened = 0
        let coordinator = RunCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            runSessionStore: harness.runSessionStore,
            finderService: harness.finderService,
            showSettingsWindowAction: { settingsOpened += 1 },
            navigate: { route = $0 },
            canStartRun: { true }
        )

        await coordinator.startTransfer()
        XCTAssertEqual(route, .organize(.run))
        XCTAssertEqual(harness.runSessionStore.prompt?.kind, .resumePendingJobs)

        coordinator.confirmRunPrompt()
        let finished = await waitForCondition { harness.runSessionStore.summary?.status == .finished }
        XCTAssertTrue(finished)
        XCTAssertEqual(harness.engine.resumeConfigurations.count, 1)

        coordinator.openSettingsWindow()
        XCTAssertEqual(settingsOpened, 1)

        harness.engine.preflightResult = .success(
            RunPreflight(
                configuration: RunConfiguration(mode: .transfer, sourcePath: "/tmp/source", destinationPath: "/tmp/destination"),
                resolvedSourcePath: "/tmp/source",
                resolvedDestinationPath: "/tmp/destination"
            )
        )

        await coordinator.startTransfer()
        XCTAssertEqual(harness.runSessionStore.prompt?.kind, .confirmTransfer)
        coordinator.dismissRunPrompt()
        XCTAssertNil(harness.runSessionStore.prompt)
        XCTAssertEqual(harness.runSessionStore.status, .idle)
    }

    // MARK: - Watched-source import context

    @MainActor
    private func makeCoordinator(
        harness: AppStateHarness,
        reportTransientError: @escaping @MainActor (String) -> Void = { _ in }
    ) -> RunCoordinator {
        RunCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            runSessionStore: harness.runSessionStore,
            finderService: harness.finderService,
            showSettingsWindowAction: {},
            navigate: { _ in },
            canStartRun: { true },
            reportTransientError: reportTransientError
        )
    }

    private func makeWatchedContext(
        sourcePath: String = "/tmp/watched-src",
        destinationPath: String
    ) -> WatchedImportContext {
        let id = UUID()
        return WatchedImportContext(
            sourceID: id,
            sourceURL: URL(fileURLWithPath: sourcePath, isDirectory: true),
            sourceBookmark: FolderBookmark(key: "watched.\(id.uuidString).source", path: sourcePath, data: Data()),
            destinationPath: destinationPath,
            destinationBookmarkKeys: ["manual.destination"],
            capturedStamps: [:],
            scanGeneration: 1
        )
    }

    /// Regression for the profile-destination hazard: a watched import
    /// requested while a profile is active must run against the context's
    /// pinned paths with no profile name (so profile resolution cannot
    /// rewrite them) and must leave Setup and the profile selection
    /// untouched — the old clear-profile approach restored the manual
    /// destination and could retarget the import.
    @MainActor
    func testWatchedImportPreviewPinsContextPathsAndLeavesProfileSetupUntouched() async {
        let harness = AppStateHarness()
        harness.setupStore.sourcePath = "/tmp/profile-src"
        harness.setupStore.destinationPath = "/tmp/profile-dest"
        harness.setupStore.selectedProfileName = "camera"

        let coordinator = makeCoordinator(harness: harness)
        // The active destination at click time is the profile's.
        let context = makeWatchedContext(destinationPath: "/tmp/profile-dest")

        await coordinator.startPreview(importContext: context)
        let finished = await waitForCondition { harness.runSessionStore.summary != nil }
        XCTAssertTrue(finished)

        let requested = harness.engine.preflightConfigurations.last
        XCTAssertEqual(requested?.sourcePath, "/tmp/watched-src")
        XCTAssertEqual(requested?.destinationPath, "/tmp/profile-dest")
        XCTAssertNil(requested?.profileName, "Watched imports never carry a profile name")

        XCTAssertEqual(harness.setupStore.sourcePath, "/tmp/profile-src", "Setup source untouched")
        XCTAssertEqual(harness.setupStore.destinationPath, "/tmp/profile-dest", "Setup destination untouched")
        XCTAssertEqual(harness.setupStore.selectedProfileName, "camera", "Profile selection untouched")
        XCTAssertNotNil(coordinator.activeWatchedImportContext,
                        "A successful preview keeps the context alive for the transfer")
    }

    @MainActor
    func testWatchedTransferUsesContextAndClearsItAfterCompletion() async {
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/tmp/watched-dest"
        let coordinator = makeCoordinator(harness: harness)
        let context = makeWatchedContext(destinationPath: "/tmp/watched-dest")

        await coordinator.startPreview(importContext: context)
        _ = await waitForCondition { harness.runSessionStore.summary != nil }

        harness.engine.preflightResult = .success(
            RunPreflight(
                configuration: RunConfiguration(mode: .transfer, sourcePath: "/tmp/watched-src", destinationPath: "/tmp/watched-dest"),
                resolvedSourcePath: "/tmp/watched-src",
                resolvedDestinationPath: "/tmp/watched-dest"
            )
        )
        harness.engine.startMode = .events([
            .complete(
                RunSummary(
                    status: .finished,
                    title: "Transfer complete",
                    metrics: RunMetrics(copiedCount: 2),
                    artifacts: RunArtifactPaths(destinationRoot: "/tmp/watched-dest")
                )
            )
        ])

        await coordinator.startTransfer()
        XCTAssertEqual(harness.runSessionStore.prompt?.kind, .confirmTransfer)
        coordinator.confirmRunPrompt()
        let finished = await waitForCondition { harness.runSessionStore.summary?.status == .finished }
        XCTAssertTrue(finished)

        let requested = harness.engine.preflightConfigurations.last
        XCTAssertEqual(requested?.mode, .transfer)
        XCTAssertEqual(requested?.sourcePath, "/tmp/watched-src")
        XCTAssertEqual(requested?.destinationPath, "/tmp/watched-dest")

        let cleared = await waitForCondition { coordinator.activeWatchedImportContext == nil }
        XCTAssertTrue(cleared, "A finished transfer consumes the import context")
    }

    /// Revalidation before mutation: if the active destination changed
    /// between the watched preview and the transfer click, the transfer
    /// cancels with a clear message — it never retargets in either
    /// direction.
    @MainActor
    func testWatchedTransferCancelsWhenDestinationChangedSincePreview() async {
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/tmp/watched-dest"
        var reportedErrors: [String] = []
        let coordinator = makeCoordinator(harness: harness) { reportedErrors.append($0) }
        let context = makeWatchedContext(destinationPath: "/tmp/watched-dest")

        await coordinator.startPreview(importContext: context)
        _ = await waitForCondition { harness.runSessionStore.summary != nil }
        let preflightCountAfterPreview = harness.engine.preflightConfigurations.count

        harness.setupStore.destinationPath = "/tmp/somewhere-else"

        await coordinator.startTransfer()

        XCTAssertEqual(harness.engine.preflightConfigurations.count, preflightCountAfterPreview,
                       "No run may start against a stale context")
        XCTAssertNil(harness.runSessionStore.prompt)
        XCTAssertNil(coordinator.activeWatchedImportContext)
        XCTAssertEqual(reportedErrors.count, 1)
        XCTAssertTrue(reportedErrors[0].contains("destination changed"),
                      "Message must explain why the import did not start: \(reportedErrors)")
    }

    @MainActor
    func testManualPreviewReplacesWatchedImportContext() async {
        let harness = AppStateHarness()
        harness.setupStore.sourcePath = "/tmp/source"
        harness.setupStore.destinationPath = "/tmp/destination"
        let coordinator = makeCoordinator(harness: harness)
        let context = makeWatchedContext(destinationPath: "/tmp/destination")

        await coordinator.startPreview(importContext: context)
        _ = await waitForCondition { harness.runSessionStore.summary != nil }
        XCTAssertNotNil(coordinator.activeWatchedImportContext)

        await coordinator.startPreview()
        XCTAssertNil(coordinator.activeWatchedImportContext,
                     "A Setup-driven preview replaces any pending watched import")
    }

    @MainActor
    func testFailedWatchedPreviewInvalidatesContext() async {
        struct TestError: Error {}
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/tmp/watched-dest"
        harness.engine.startMode = .fails(TestError())
        let coordinator = makeCoordinator(harness: harness)
        let context = makeWatchedContext(destinationPath: "/tmp/watched-dest")

        await coordinator.startPreview(importContext: context)
        _ = await waitForCondition { harness.runSessionStore.status == .failed }

        let cleared = await waitForCondition { coordinator.activeWatchedImportContext == nil }
        XCTAssertTrue(cleared, "A failed preview invalidates the context")
    }
}
