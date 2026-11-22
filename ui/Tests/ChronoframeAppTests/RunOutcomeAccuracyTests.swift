#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

/// A run's hero, summary cards and VoiceOver announcement must describe what
/// the engine actually reported: the final summary (not the last progress
/// sample), problems when there were any, and a real "stopping" state.
final class RunOutcomeAccuracyTests: XCTestCase {
    private func model(
        status: RunStatus,
        progressMetrics: RunMetrics = RunMetrics(),
        summaryMetrics: RunMetrics? = nil,
        summaryFailureMessage: String? = nil,
        issueCount: Int = 0,
        isCancelling: Bool = false,
        mode: RunMode = .transfer
    ) -> RunWorkspaceModel {
        RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: status,
                currentMode: mode,
                currentTaskTitle: "",
                currentPhase: nil,
                progress: 0,
                metrics: progressMetrics,
                summary: summaryMetrics.map {
                    RunSummary(
                        status: status,
                        title: "",
                        metrics: $0,
                        artifacts: RunArtifactPaths(),
                        failureMessage: summaryFailureMessage
                    )
                },
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: issueCount,
                logEntries: [],
                historyDestinationRoot: "",
                currentSourceRoot: "",
                canStartRun: true,
                isCancelling: isCancelling
            )
        )
    }

    // MARK: Final totals

    func testOutcomeMetricsPreferTheFinalSummaryOverTheLastProgressSample() {
        let m = model(
            status: .finished,
            progressMetrics: RunMetrics(copiedCount: 9),
            summaryMetrics: RunMetrics(copiedCount: 7, failedCount: 2)
        )
        XCTAssertEqual(m.outcomeMetrics.copiedCount, 7)
        XCTAssertEqual(m.outcomeMetrics.failedCount, 2)
    }

    func testOutcomeMetricsFallBackToProgressWhenThereIsNoSummary() {
        let m = model(status: .running, progressMetrics: RunMetrics(copiedCount: 4))
        XCTAssertEqual(m.outcomeMetrics.copiedCount, 4)
    }

    func testOutcomeIssuesCoverFailedErroredUnreadableAndLoggedProblems() {
        XCTAssertFalse(model(status: .finished, summaryMetrics: RunMetrics(copiedCount: 3)).hasOutcomeIssues)
        XCTAssertTrue(model(status: .finished, summaryMetrics: RunMetrics(copiedCount: 3, failedCount: 1)).hasOutcomeIssues)
        XCTAssertTrue(model(status: .finished, summaryMetrics: RunMetrics(copiedCount: 3, errorCount: 1)).hasOutcomeIssues)
        XCTAssertTrue(model(status: .finished, summaryMetrics: RunMetrics(hashErrorCount: 1, copiedCount: 3)).hasOutcomeIssues)
        XCTAssertTrue(model(status: .finished, summaryMetrics: RunMetrics(copiedCount: 3), issueCount: 1).hasOutcomeIssues)
    }

    // MARK: Finished

    func testCleanFinishStaysACelebration() {
        let hero = model(status: .finished, summaryMetrics: RunMetrics(copiedCount: 3)).heroState
        XCTAssertEqual(hero.title, "Copy complete")
        XCTAssertEqual(hero.tone, .success)
    }

    func testFinishWithFailedFilesIsNotPresentedAsSuccess() {
        let hero = model(
            status: .finished,
            summaryMetrics: RunMetrics(copiedCount: 5, failedCount: 2),
            issueCount: 2
        ).heroState
        XCTAssertNotEqual(hero.title, "Copy complete")
        XCTAssertEqual(hero.tone, .warning)
        XCTAssertTrue(hero.message.contains("5"), hero.message)
        XCTAssertTrue(hero.message.contains("2"), hero.message)
        XCTAssertTrue(hero.message.contains("Your originals were not changed."), hero.message)
    }

    // MARK: Nothing to copy

    func testNothingToCopyClaimsAnUpToDateLibraryOnlyWhenFilesWereFoundThere() {
        let upToDate = model(
            status: .nothingToCopy,
            summaryMetrics: RunMetrics(alreadyInDestinationCount: 12)
        ).heroState
        XCTAssertEqual(upToDate.title, "Already up to date")

        let nothingFound = model(
            status: .nothingToCopy,
            summaryMetrics: RunMetrics(alreadyInDestinationCount: 0)
        ).heroState
        XCTAssertEqual(nothingFound.title, "Nothing was copied")
        XCTAssertFalse(nothingFound.message.contains("already in your organized library"))
        XCTAssertNil(
            try! NSRegularExpression(pattern: "\\b(transfer|run)\\b", options: [.caseInsensitive])
                .firstMatch(in: nothingFound.message, range: NSRange(nothingFound.message.startIndex..., in: nothingFound.message))
        )
    }

    func testNothingToCopyWithProblemsDoesNotClaimAnUpToDateLibrary() {
        // A free test batch whose files moved reports a warning and still
        // finishes as `.nothingToCopy`; the destination counts may be non-zero.
        let hero = model(
            status: .nothingToCopy,
            summaryMetrics: RunMetrics(alreadyInDestinationCount: 12),
            issueCount: 1
        ).heroState
        XCTAssertEqual(hero.title, "Nothing was copied")
        XCTAssertEqual(hero.tone, .warning)
        XCTAssertEqual(hero.primaryAction, .showIssues)
    }

    // MARK: Stopping

    // AGENTS-INVARIANT: 10
    func testRunningHeroSaysStoppingOnceCancellationIsRequested() {
        let hero = model(status: .running, isCancelling: true).heroState
        XCTAssertEqual(hero.title, "Stopping…")
        XCTAssertTrue(hero.message.contains("Your originals are not changed."), hero.message)
        XCTAssertEqual(hero.badgeTitle, "Stopping…")
    }

    func testRunningHeroIsUnchangedWhenNotCancelling() {
        XCTAssertEqual(model(status: .running).heroState.title, "Copying your photos")
    }

    // MARK: VoiceOver

    func testFinishAnnouncementDoesNotSpeakSuccessWhenThereWereProblems() {
        let old = RunAnnouncementPlanner.Snapshot(status: .running, phase: .copy, progress: 1)
        let clean = RunAnnouncementPlanner.Snapshot(status: .finished, phase: nil, progress: 1)
        let problems = RunAnnouncementPlanner.Snapshot(status: .finished, phase: nil, progress: 1, hasOutcomeIssues: true)

        XCTAssertEqual(RunAnnouncementPlanner.announcement(from: old, to: clean), "Copy complete.")
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(from: old, to: problems),
            "Copy finished with problems. Your original files were left untouched."
        )
    }

    func testStoppingIsAnnouncedOnceWhenCancellationBegins() {
        let running = RunAnnouncementPlanner.Snapshot(status: .running, phase: .copy, progress: 0.4)
        let stopping = RunAnnouncementPlanner.Snapshot(status: .running, phase: .copy, progress: 0.4, isCancelling: true)

        let first = RunAnnouncementPlanner.detailedAnnouncement(from: running, to: stopping)
        XCTAssertEqual(first?.message, "Stopping…")
        XCTAssertEqual(first?.priority, .medium)
        XCTAssertNil(RunAnnouncementPlanner.detailedAnnouncement(from: stopping, to: stopping))
    }
}
