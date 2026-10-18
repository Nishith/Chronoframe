#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

/// The Run timeline is a distribution of *planned* transfers by month. The
/// engine reports `copiedCount` for the run as a whole and never per month,
/// so no bar may claim a month is finished, and the surrounding labels must
/// not describe the chart as the whole source library.
final class RunTimelinePresentationTests: XCTestCase {
    private func makeView(
        status: RunStatus,
        phase: RunPhase? = nil,
        planned: Int,
        copied: Int,
        buckets: [DateHistogramBucket]
    ) -> RunTimelineView {
        RunTimelineView(
            model: RunWorkspaceModel(
                context: RunWorkspaceContext(
                    status: status,
                    currentMode: status == .dryRunFinished ? .preview : .transfer,
                    currentTaskTitle: "Timeline",
                    currentPhase: phase,
                    progress: 0.5,
                    metrics: RunMetrics(
                        plannedCount: planned,
                        copiedCount: copied,
                        dateHistogram: buckets
                    ),
                    summary: nil,
                    lastErrorMessage: nil,
                    warningCount: 0,
                    errorCount: 0,
                    issueCount: 0,
                    logEntries: [],
                    historyDestinationRoot: "/Volumes/Archive",
                    currentSourceRoot: "/Volumes/Ingest",
                    canStartRun: false
                )
            )
        )
    }

    private var sampleBuckets: [DateHistogramBucket] {
        [
            DateHistogramBucket(key: "2021-04", plannedCount: 40),
            DateHistogramBucket(key: "2021-05", plannedCount: 30),
            DateHistogramBucket(key: "2022-01", plannedCount: 30),
        ]
    }

    func testPartwayThroughACopyNoBarClaimsItsMonthIsDone() {
        let view = makeView(status: .running, phase: .copy, planned: 100, copied: 55, buckets: sampleBuckets)

        // 55 copied would previously have drained left-to-right and filled the
        // first two months completely. Aggregate copies prove nothing about
        // which months those files belonged to.
        XCTAssertEqual(view.barFills, [0, 0, 0])
    }

    func testFinishedRunDoesNotForceEveryBarToComplete() {
        let finished = makeView(status: .finished, planned: 100, copied: 100, buckets: sampleBuckets)
        XCTAssertEqual(finished.barFills, [0, 0, 0])

        let nothingToCopy = makeView(status: .nothingToCopy, planned: 0, copied: 0, buckets: sampleBuckets)
        XCTAssertEqual(nothingToCopy.barFills, [0, 0, 0])
    }

    func testAggregateProgressIsReportedSeparatelyFromTheChart() {
        let running = makeView(status: .running, phase: .copy, planned: 100, copied: 55, buckets: sampleBuckets)
        XCTAssertEqual(running.progressCaption, "55 of 100 planned files copied so far")

        let finished = makeView(status: .finished, planned: 100, copied: 98, buckets: sampleBuckets)
        XCTAssertEqual(finished.progressCaption, "98 of 100 planned files copied")

        let stopped = makeView(status: .failed, planned: 100, copied: 12, buckets: sampleBuckets)
        XCTAssertEqual(stopped.progressCaption, "12 of 100 planned files copied before the run stopped")

        // A preview has planned nothing yet to copy: no aggregate claim.
        let preview = makeView(status: .dryRunFinished, planned: 100, copied: 0, buckets: sampleBuckets)
        XCTAssertNil(preview.progressCaption)
    }

    func testLabelsScopeTheDistributionToPlannedTransfers() {
        let preview = makeView(status: .dryRunFinished, planned: 100, copied: 0, buckets: sampleBuckets)

        XCTAssertEqual(preview.rangeCaption, "2021–2022 · 100 planned files")
        XCTAssertFalse(preview.subtitle.contains("your source"))
        XCTAssertTrue(preview.subtitle.contains("planned"))

        let single = makeView(
            status: .dryRunFinished,
            planned: 40,
            copied: 0,
            buckets: [DateHistogramBucket(key: "2021-04", plannedCount: 40)]
        )
        XCTAssertEqual(single.rangeCaption, "2021 · 40 planned files")
    }

    func testAccessibilityValueSeparatesPlannedDistributionFromAggregateProgress() {
        let running = makeView(status: .running, phase: .copy, planned: 100, copied: 55, buckets: sampleBuckets)
        XCTAssertEqual(
            running.accessibilityValue(selectedKey: nil),
            "100 planned files across 3 months. 55 copied so far for the run as a whole. Unselected."
        )
        XCTAssertEqual(
            running.accessibilityValue(selectedKey: "2021-05"),
            "Selected month: 2021-05. 100 planned files across 3 months. 55 copied so far for the run as a whole."
        )
    }
}
