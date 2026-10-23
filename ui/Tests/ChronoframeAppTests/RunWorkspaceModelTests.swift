#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

final class RunWorkspaceModelTests: XCTestCase {
    // AGENTS-INVARIANT: 10
    func testCancelledRunReportsActualCopiesAndUntouchedSources() {
        var context = makeModel(status: .cancelled).context
        context.currentMode = .transfer
        context.metrics = RunMetrics(plannedCount: 200, copiedCount: 99)
        context.summary = RunSummary(status: .cancelled, title: "Cancelled", metrics: RunMetrics(plannedCount: 200, copiedCount: 190), artifacts: RunArtifactPaths())
        let model = RunWorkspaceModel(context: context)
        XCTAssertTrue(model.heroState.message.contains("190 files copied"))
        XCTAssertTrue(model.heroState.message.contains("Source files were left untouched."))
        XCTAssertTrue(model.showsOutcomeSummary)
    }

    func testZeroCopyDoesNotClaimWholeDestinationIsUpToDate() {
        let model = makeModel(status: .nothingToCopy)
        XCTAssertEqual(model.heroState.title, "No Files Copied")
        XCTAssertEqual(model.heroState.message, "No files were copied in this run. Review the preview or Run History before starting another run.")
        XCTAssertFalse(model.previewReviewMessage.contains("everything needed"))
        XCTAssertEqual(model.currentFocusSummaryValue, "No files copied in this run")
    }

    // AGENTS-INVARIANT: 3
    // AGENTS-INVARIANT: 7
    // AGENTS-INVARIANT: 10
    func testVerificationClaimsRequireCapturedSettingAndFinalizedCopies() {
        var context = makeModel(status: .running).context
        context.currentMode = .transfer
        context.verifyCopies = true
        context.metrics = RunMetrics(plannedCount: 200, copiedCount: 100)
        XCTAssertEqual(RunWorkspaceModel(context: context).verificationMessage, "Copies will be hash-checked against the source. A copy that fails verification is removed.")
        context.verifyCopies = false
        XCTAssertEqual(RunWorkspaceModel(context: context).verificationMessage, "Copy verification is off; copies will not be hash-checked.")
        context.verifyCopies = true

        context.status = .finished
        context.summary = RunSummary(status: .finished, title: "Finished", metrics: RunMetrics(plannedCount: 190, copiedCount: 190), artifacts: RunArtifactPaths())
        let finished = RunWorkspaceModel(context: context)
        XCTAssertEqual(finished.heroState.title, "190 files copied")
        XCTAssertEqual(finished.verificationMessage, "Copied files were hash-verified.")
        XCTAssertTrue(finished.heroState.message.contains("Source files were left untouched."))

        context.verifyCopies = false
        XCTAssertEqual(RunWorkspaceModel(context: context).verificationMessage, "Copy verification was skipped.")
        context.verifyCopies = nil
        XCTAssertEqual(RunWorkspaceModel(context: context).verificationMessage, "Copy verification status is unavailable.")
        context.verifyCopies = true
        context.summary?.metrics.copiedCount = 0
        XCTAssertEqual(RunWorkspaceModel(context: context).verificationMessage, "No verified copies are reported for this run.")
        context.summary = nil
        XCTAssertEqual(RunWorkspaceModel(context: context).verificationMessage, "No verified copies are reported for this run.")
    }

    // AGENTS-INVARIANT: 10
    func testStoppingKeepsActiveStateUntilFinalOutcomeAndPartialIsVisible() {
        var context = makeModel(status: .running).context
        context.isCancelling = true
        context.currentMode = .transfer
        context.metrics = RunMetrics(plannedCount: 200, copiedCount: 189)
        let stopping = RunWorkspaceModel(context: context)
        XCTAssertEqual(stopping.heroState.title, "Stopping…")
        XCTAssertEqual(stopping.heroState.message, "Waiting for the run to stop and finalize its receipt. Source files stay untouched. Completed copies remain in the destination.")
        XCTAssertFalse(stopping.showsOutcomeSummary)

        context.isCancelling = false
        context.status = .finished
        context.summary = RunSummary(status: .finished, title: "Finished", metrics: RunMetrics(plannedCount: 200, copiedCount: 190, failedCount: 10), artifacts: RunArtifactPaths())
        let partial = RunWorkspaceModel(context: context)
        XCTAssertEqual(partial.heroState.title, "190 files copied")
        XCTAssertEqual(partial.heroState.tone, .warning)
        XCTAssertEqual(partial.heroState.badgeTitle, "Finished with Issues")
        XCTAssertTrue(partial.heroState.message.contains("10 files failed to copy."))
        XCTAssertTrue(partial.heroState.message.contains("Source files were left untouched."))
    }

    func testTimelineScopeDoesNotClaimWholeSourceOrCompletedMonths() {
        for status in [RunStatus.running, .dryRunFinished, .finished, .nothingToCopy, .cancelled, .failed, .reverted] {
            let model = makeModel(status: status)
            XCTAssertEqual(model.timelineSubtitle, "Date distribution of files planned for this run. A resumed run may show only queued files.")
            XCTAssertEqual(model.timelineEmptyMessage, "No planned date distribution is available for this run.")
        }
    }

    // AGENTS-INVARIANT: 3
    // AGENTS-INVARIANT: 7
    @MainActor
    func testRunVerificationEvidenceSurvivesSetupEditsAndCompletion() async {
        let harness = AppStateHarness()
        let configuration = RunConfiguration(mode: .transfer, sourcePath: "/tmp/source", destinationPath: "/tmp/destination", verifyCopies: false)
        harness.engine.preflightResult = .success(RunPreflight(configuration: configuration, resolvedSourcePath: configuration.sourcePath, resolvedDestinationPath: configuration.destinationPath))
        harness.engine.startMode = .events([
            .complete(RunSummary(status: .finished, title: "Finished", metrics: RunMetrics(copiedCount: 190), artifacts: RunArtifactPaths(destinationRoot: configuration.destinationPath)))
        ])
        await harness.runSessionStore.requestRun(mode: .transfer, configuration: configuration)
        harness.runSessionStore.confirmPrompt()
        let completed = await waitForCondition { harness.runSessionStore.status == .finished }
        XCTAssertTrue(completed)
        harness.preferencesStore.verifyCopies = true
        harness.setupStore.destinationPath = "/tmp/unrelated"
        let model = RunWorkspaceModel(runSessionStore: harness.runSessionStore, runLogStore: harness.runLogStore, historyStore: harness.historyStore, canStartRun: true)
        XCTAssertEqual(model.verificationMessage, "Copy verification was skipped.")
        XCTAssertEqual(model.heroState.title, "190 files copied")
        XCTAssertEqual(model.destinationRoot, configuration.destinationPath)
    }

    func testPreviewReviewStateComputesTransferReadinessAndIssueSummary() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .dryRunFinished,
                currentMode: .preview,
                currentTaskTitle: "Preview complete",
                currentPhase: .classification,
                progress: 1,
                metrics: RunMetrics(
                    discoveredCount: 84,
                    plannedCount: 42,
                    alreadyInDestinationCount: 29,
                    duplicateCount: 7,
                    hashErrorCount: 1,
                    copiedCount: 0,
                    failedCount: 0,
                    errorCount: 1
                ),
                summary: RunSummary(
                    status: .dryRunFinished,
                    title: "Preview complete",
                    metrics: RunMetrics(plannedCount: 42),
                    artifacts: RunArtifactPaths(destinationRoot: "/Volumes/Archive")
                ),
                lastErrorMessage: nil,
                warningCount: 1,
                errorCount: 1,
                issueCount: 1,
                logEntries: [
                    RunWorkspaceLogLine(id: 1, text: "WARNING: review metadata"),
                    RunWorkspaceLogLine(id: 2, text: "ERROR: hashing failed"),
                ],
                historyDestinationRoot: "/Volumes/Archive",
                currentSourceRoot: "/Volumes/Ingest",
                canStartRun: true
            )
        )

        XCTAssertEqual(model.heroState.badgeTitle, "Preview Complete")
        XCTAssertTrue(model.showsPreviewReview)
        XCTAssertTrue(model.canStartTransferFromPreview)
        XCTAssertEqual(model.issueSummaryValue, "1 warning, 1 error, 1 engine issue")
        XCTAssertEqual(model.tabTitle(.issues), "Issues (2)")
        XCTAssertEqual(model.sourceSummaryValue, "/Volumes/Ingest")
    }

    func testFailedStateRoutesToIssuesAndFormatsArtifactsFallback() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .failed,
                currentMode: .transfer,
                currentTaskTitle: "Failed",
                currentPhase: .copy,
                progress: 0.5,
                metrics: RunMetrics(failedCount: 3, errorCount: 2),
                summary: nil,
                lastErrorMessage: "Disk became unavailable",
                warningCount: 0,
                errorCount: 2,
                issueCount: 3,
                logEntries: [
                    RunWorkspaceLogLine(id: 1, text: "ERROR: disk unavailable"),
                ],
                historyDestinationRoot: "/Volumes/Fallback",
                currentSourceRoot: "",
                canStartRun: true
            )
        )

        XCTAssertEqual(model.heroState.primaryAction, .showIssues)
        XCTAssertTrue(model.heroState.message.hasPrefix("Disk became unavailable"))
        XCTAssertTrue(model.heroState.message.contains("Source files were left untouched."))
        XCTAssertEqual(model.destinationSummaryValue, "/Volumes/Fallback")
        XCTAssertEqual(model.sourceSummaryValue, "Source will appear here once a run is configured")
        XCTAssertEqual(model.issueEntries.count, 1)
        XCTAssertEqual(model.issueTone, .danger)
    }

    func testRunningTransferFormatsVisibleProgressDetails() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .running,
                currentMode: .transfer,
                currentTaskTitle: "Copying files...",
                currentPhase: .copy,
                progress: 0.85,
                metrics: RunMetrics(
                    plannedCount: 8_271,
                    copiedCount: 7_064,
                    bytesCopied: 1_500_000,
                    bytesTotal: 3_000_000,
                    speedMBps: 12.3,
                    etaSeconds: 95
                ),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "/Volumes/Archive",
                currentSourceRoot: "/Volumes/Ingest",
                canStartRun: true
            )
        )

        XCTAssertTrue(model.showsCopyProgressDetails)
        XCTAssertEqual(model.fileProgressSummaryValue, "7,064 of 8,271 files · 85%")
        XCTAssertEqual(model.throughputSummaryValue, "12.3 MB/s · 1m 35s")
        XCTAssertNotEqual(model.byteProgressSummaryValue, "Measuring")
    }

    func testStalePreviewReviewDisablesTransfer() {
        let model = RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .dryRunFinished,
                currentMode: .preview,
                currentTaskTitle: "Preview complete",
                currentPhase: .classification,
                progress: 1,
                metrics: RunMetrics(plannedCount: 3),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "/Volumes/Archive",
                currentSourceRoot: "/Volumes/Ingest",
                canStartRun: true,
                previewReviewIsStale: true,
                previewReviewSummary: PreviewReviewSummary(totalCount: 3, readyCount: 3),
                previewReviewPath: "/Volumes/Archive/.organize_logs/preview_review.jsonl"
            )
        )

        XCTAssertFalse(model.canStartTransferFromPreview)
        XCTAssertTrue(model.previewReviewMessage.contains("Rebuild the preview"))
        XCTAssertEqual(model.tabTitle(.review), "Review")
    }

    // MARK: - isBlankIdle (design-critique fix #7)

    func testIsBlankIdleRequiresBothIdleStatusAndZeroDiscoveredFiles() {
        // Idle with nothing discovered → blank idle (show onboarding card, not empty sections)
        XCTAssertTrue(makeModel(status: .idle, discoveredCount: 0).isBlankIdle)

        // Idle but files were already discovered in this session → not blank
        XCTAssertFalse(makeModel(status: .idle, discoveredCount: 1).isBlankIdle)
        XCTAssertFalse(makeModel(status: .idle, discoveredCount: 200).isBlankIdle)

        // Active/terminal states are never blank idle regardless of count
        XCTAssertFalse(makeModel(status: .running, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .preflighting, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .finished, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .dryRunFinished, discoveredCount: 0).isBlankIdle)
        XCTAssertFalse(makeModel(status: .failed, discoveredCount: 0).isBlankIdle)
    }

    // MARK: - Helpers

    private func makeModel(status: RunStatus, discoveredCount: Int = 0) -> RunWorkspaceModel {
        RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: status,
                currentMode: nil,
                currentTaskTitle: "",
                currentPhase: nil,
                progress: 0,
                metrics: RunMetrics(discoveredCount: discoveredCount),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "",
                currentSourceRoot: "",
                canStartRun: false
            )
        )
    }
}
