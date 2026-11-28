#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

/// English summary text for sidecar companions (EPR WP-04b, C-03.9).
@MainActor
final class CompanionSummaryTextTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")

    private func headline(_ metrics: RunMetrics) -> RunPreviewHeadline {
        RunPreviewHeadline(metrics: metrics, review: PreviewReviewSummary(), isStale: false, locale: enUS)
    }

    private func finishedModel(copied: Int, copiedCompanions: Int) -> RunWorkspaceModel {
        RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: .finished,
                currentMode: .transfer,
                currentTaskTitle: "",
                currentPhase: nil,
                progress: 1,
                metrics: RunMetrics(copiedCount: copied, copiedCompanionCount: copiedCompanions),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "",
                currentSourceRoot: "",
                canStartRun: true
            )
        )
    }

    func testPreviewHeadlineSplitsPhotosAndSidecars() {
        let split = headline(RunMetrics(
            plannedCount: 5,
            dateHistogram: [DateHistogramBucket(key: "2024-03", plannedCount: 5)],
            plannedCompanionCount: 2,
            unresolvedCompanionCount: 3
        ))
        XCTAssertEqual(
            split.sentence,
            "3 photos and videos, 2 sidecar files will be copied, all from Mar 2024. Nothing has been copied yet."
        )
        XCTAssertEqual(
            split.exceptions.first { $0.id == "sidecarsNotCopied" }?.text,
            "3 sidecar files not copied"
        )

        let singular = headline(RunMetrics(plannedCount: 2, plannedCompanionCount: 1, unresolvedCompanionCount: 1))
        XCTAssertEqual(
            singular.sentence,
            "1 photo or video, 1 sidecar file will be copied. Nothing has been copied yet."
        )
        XCTAssertEqual(singular.exceptions.first { $0.id == "sidecarsNotCopied" }?.text, "1 sidecar file not copied")

        // No companions: the existing sentence and exceptions are unchanged.
        let plain = headline(RunMetrics(plannedCount: 4))
        XCTAssertEqual(plain.sentence, "4 photos and videos will be copied. Nothing has been copied yet.")
        XCTAssertNil(plain.exceptions.first { $0.id == "sidecarsNotCopied" })

        // Unresolved sidecars alone still show, with the unchanged sentence.
        let onlyUnresolved = headline(RunMetrics(plannedCount: 4, unresolvedCompanionCount: 2))
        XCTAssertEqual(onlyUnresolved.sentence, "4 photos and videos will be copied. Nothing has been copied yet.")
        XCTAssertEqual(onlyUnresolved.exceptions.first { $0.id == "sidecarsNotCopied" }?.text, "2 sidecar files not copied")
    }

    func testCompletionHeroSplitsPhotosAndSidecars() {
        XCTAssertEqual(
            finishedModel(copied: 5, copiedCompanions: 2).heroState.message,
            "3 photos and videos, 2 sidecar files are in your organized library. Your originals were not changed."
        )
        XCTAssertEqual(
            finishedModel(copied: 2, copiedCompanions: 1).heroState.message,
            "1 photo or video, 1 sidecar file are in your organized library. Your originals were not changed."
        )
        XCTAssertEqual(
            finishedModel(copied: 3, copiedCompanions: 0).heroState.message,
            "3 photos and videos are in your organized library. Your originals were not changed."
        )
    }
}
