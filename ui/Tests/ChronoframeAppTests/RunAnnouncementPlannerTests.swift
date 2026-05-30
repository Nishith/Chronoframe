#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

/// Unit tests for the VoiceOver run-announcement decision logic. The view simply
/// posts whatever string the planner returns, so all the throttling and wording
/// rules live here where they can be tested deterministically.
final class RunAnnouncementPlannerTests: XCTestCase {

    private typealias Snapshot = RunAnnouncementPlanner.Snapshot

    private func snapshot(_ status: RunStatus, _ phase: RunPhase?, _ progress: Double) -> Snapshot {
        Snapshot(status: status, phase: phase, progress: progress)
    }

    func testNoAnnouncementWhenNothingChanges() {
        let s = snapshot(.running, .copy, 0.4)
        XCTAssertNil(RunAnnouncementPlanner.announcement(from: s, to: s))
    }

    func testTerminalStatusChangesAreAnnounced() {
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.99),
                to: snapshot(.finished, nil, 1.0)
            ),
            "Transfer complete."
        )
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.5),
                to: snapshot(.failed, .copy, 0.5)
            ),
            "Run failed. Your original files were left untouched."
        )
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.preflighting, nil, 0),
                to: snapshot(.dryRunFinished, nil, 1.0)
            ),
            "Preview ready for review."
        )
    }

    func testCancelledRunReassuresOriginalsAreSafe() {
        let message = RunAnnouncementPlanner.announcement(
            from: snapshot(.running, .copy, 0.3),
            to: snapshot(.cancelled, .copy, 0.3)
        )
        XCTAssertEqual(message, "Run cancelled. Your original files were left untouched.")
    }

    func testPhaseChangeIsAnnouncedDuringActiveRun() {
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .discovery, 0),
                to: snapshot(.running, .sourceHashing, 0)
            ),
            RunPhase.sourceHashing.title
        )
    }

    func testProgressBucketsAnnounceWhileCopyingAndThrottle() {
        // Crossing into the 50% bucket announces.
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.49),
                to: snapshot(.running, .copy, 0.51)
            ),
            "50 percent copied"
        )
        // Moving within the same bucket stays silent (throttling).
        XCTAssertNil(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.51),
                to: snapshot(.running, .copy, 0.74)
            )
        )
        // The 100% bucket is suppressed — completion is covered by the
        // terminal status announcement instead.
        XCTAssertNil(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.99),
                to: snapshot(.running, .copy, 1.0)
            )
        )
    }

    func testProgressIsSilentOutsideCopyPhase() {
        XCTAssertNil(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .discovery, 0.2),
                to: snapshot(.running, .discovery, 0.6)
            )
        )
    }

    func testAllTerminalStatusesHaveDistinctReassuringMessages() {
        let cases: [(RunStatus, String)] = [
            (.finished, "Transfer complete."),
            (.dryRunFinished, "Preview ready for review."),
            (.nothingToCopy, "Nothing new to copy."),
            (.failed, "Run failed. Your original files were left untouched."),
            (.cancelled, "Run cancelled. Your original files were left untouched."),
            (.reverted, "Revert complete."),
            (.revertEmpty, "Nothing to revert."),
            (.reorganized, "Reorganize complete."),
            (.nothingToReorganize, "Nothing to reorganize."),
        ]
        for (status, expected) in cases {
            XCTAssertEqual(
                RunAnnouncementPlanner.announcement(
                    from: snapshot(.running, .copy, 0.5),
                    to: snapshot(status, nil, 0.5)
                ),
                expected,
                "Wrong announcement for \(status)"
            )
        }
        // Every terminal message is unique so users can tell outcomes apart.
        let messages = cases.map(\.1)
        XCTAssertEqual(Set(messages).count, messages.count)
    }

    func testNonTerminalStatusTransitionsAreSilent() {
        // Entering preflighting/running/idle is not, by itself, announced.
        XCTAssertNil(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.idle, nil, 0),
                to: snapshot(.preflighting, nil, 0)
            )
        )
        XCTAssertNil(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.preflighting, nil, 0),
                to: snapshot(.running, nil, 0)
            )
        )
    }

    func testPhaseChangeIsSilentWhenNotRunning() {
        // A phase value that changes while the run isn't active should not speak.
        XCTAssertNil(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.preflighting, nil, 0),
                to: snapshot(.preflighting, .discovery, 0)
            )
        )
    }

    func testProgressBucketsAnnounceAt25And75() {
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.20),
                to: snapshot(.running, .copy, 0.26)
            ),
            "25 percent copied"
        )
        XCTAssertEqual(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.70),
                to: snapshot(.running, .copy, 0.76)
            ),
            "75 percent copied"
        )
    }

    func testProgressGoingBackwardsIsSilent() {
        XCTAssertNil(
            RunAnnouncementPlanner.announcement(
                from: snapshot(.running, .copy, 0.80),
                to: snapshot(.running, .copy, 0.40)
            )
        )
    }
}
