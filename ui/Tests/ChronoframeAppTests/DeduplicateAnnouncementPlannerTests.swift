#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import ChronoframeCore
import XCTest
@testable import ChronoframeApp

final class DeduplicateAnnouncementPlannerTests: XCTestCase {
    private typealias Snapshot = DeduplicateAnnouncementPlanner.Snapshot

    private func snapshot(
        _ status: DeduplicateSessionStore.Status,
        phase: DeduplicatePhase? = nil,
        clusterCount: Int = 0,
        commitSummary: DeduplicateCommitSummary? = nil
    ) -> Snapshot {
        Snapshot(
            status: status,
            phase: phase,
            clusterCount: clusterCount,
            commitSummary: commitSummary
        )
    }

    func testScanCompletionAnnouncesReviewCount() {
        XCTAssertEqual(
            DeduplicateAnnouncementPlanner.announcement(
                from: snapshot(.scanning, phase: .clustering, clusterCount: 3),
                to: snapshot(.readyToReview, clusterCount: 3)
            ),
            "Deduplicate scan complete. 3 groups ready for review."
        )
        XCTAssertEqual(
            DeduplicateAnnouncementPlanner.announcement(
                from: snapshot(.scanning, phase: .clustering, clusterCount: 1),
                to: snapshot(.readyToReview, clusterCount: 1)
            ),
            "Deduplicate scan complete. 1 group ready for review."
        )
    }

    func testScanPhaseChangesAnnounceButProgressDoesNot() {
        XCTAssertEqual(
            DeduplicateAnnouncementPlanner.announcement(
                from: snapshot(.scanning, phase: .discovery),
                to: snapshot(.scanning, phase: .identityHashing)
            ),
            DeduplicatePhase.identityHashing.title
        )
        XCTAssertNil(
            DeduplicateAnnouncementPlanner.announcement(
                from: snapshot(.scanning, phase: .identityHashing, clusterCount: 0),
                to: snapshot(.scanning, phase: .identityHashing, clusterCount: 2)
            )
        )
    }

    func testCommitAndRestoreTerminalStatesAnnounceCounts() {
        XCTAssertEqual(
            DeduplicateAnnouncementPlanner.announcement(
                from: snapshot(.committing),
                to: snapshot(.completed, commitSummary: Self.summary(deleted: 2))
            ),
            "Deduplicate complete. 2 files moved to Trash."
        )
        XCTAssertEqual(
            DeduplicateAnnouncementPlanner.announcement(
                from: snapshot(.reverting),
                to: snapshot(.reverted, commitSummary: Self.summary(deleted: 1))
            ),
            "Restore complete. 1 file restored from Trash."
        )
    }

    func testFailureAnnouncementReassuresOriginalsAreSafe() {
        XCTAssertEqual(
            DeduplicateAnnouncementPlanner.announcement(
                from: snapshot(.scanning, phase: .featureExtraction),
                to: snapshot(.failed("Disk full"), phase: .featureExtraction)
            ),
            "Deduplicate failed. Your original files were left untouched."
        )
    }

    func testNonTerminalTransitionsAreSilent() {
        XCTAssertNil(DeduplicateAnnouncementPlanner.announcement(from: snapshot(.idle), to: snapshot(.scanning)))
        XCTAssertNil(DeduplicateAnnouncementPlanner.announcement(from: snapshot(.readyToReview), to: snapshot(.committing)))
        XCTAssertNil(DeduplicateAnnouncementPlanner.announcement(from: snapshot(.completed), to: snapshot(.idle)))
    }

    private static func summary(deleted: Int) -> DeduplicateCommitSummary {
        DeduplicateCommitSummary(
            deletedCount: deleted,
            failedCount: 0,
            bytesReclaimed: 1024,
            receiptPath: nil,
            hardDelete: false
        )
    }
}
