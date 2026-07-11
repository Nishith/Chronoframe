#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

final class GuardianAccessibilityTextTests: XCTestCase {
    private func summary(
        verified: Int = 0,
        corrupt: Int = 0,
        modified: Int = 0,
        missing: Int = 0,
        newFiles: Int = 0,
        partialScan: Bool = false
    ) -> GuardianStore.ScanSummary {
        GuardianStore.ScanSummary(
            verified: verified,
            corrupt: corrupt,
            modified: modified,
            missing: missing,
            newFiles: newFiles,
            partialScan: partialScan,
            generatedAt: Date(timeIntervalSince1970: 0)
        )
    }

    func testHealthyScanReadsAsHealthy() {
        let text = GuardianAccessibilityText.scanSummary(summary(verified: 42))
        XCTAssertTrue(text.contains("healthy"))
        XCTAssertTrue(text.contains("42 files verified"))
    }

    func testSingularVerifiedFileIsNotPluralized() {
        let text = GuardianAccessibilityText.scanSummary(summary(verified: 1))
        XCTAssertTrue(text.contains("1 file verified"))
        XCTAssertFalse(text.contains("1 files"))
    }

    func testCorruptionIsSpokenAsBitRotAndAsksForReview() {
        let text = GuardianAccessibilityText.scanSummary(summary(verified: 10, corrupt: 2, missing: 1))
        XCTAssertTrue(text.contains("2 files with suspected bit rot"))
        XCTAssertTrue(text.contains("1 missing"))
        XCTAssertTrue(text.contains("Review needed"))
    }

    func testPartialScanIsFlaggedAsIncomplete() {
        let text = GuardianAccessibilityText.scanSummary(summary(verified: 5, partialScan: true))
        XCTAssertTrue(text.contains("incomplete"))
    }

    func testCorruptFindingExplainsBitRotAndTheChoice() {
        let finding = GuardianIntegrityFinding(
            relativePath: "2024/05/a.jpg",
            status: .corrupt,
            trustState: .changedPendingReview,
            expectedIdentity: FileIdentity(size: 10, digest: "good"),
            observedIdentity: FileIdentity(size: 10, digest: "rot")
        )
        let text = GuardianAccessibilityText.finding(finding)
        XCTAssertTrue(text.contains("a.jpg"))
        XCTAssertTrue(text.contains("bit rot"))
        XCTAssertTrue(text.contains("Restore") || text.contains("restore"))
    }

    func testMissingFindingMentionsRestoreOrAcknowledge() {
        let finding = GuardianIntegrityFinding(relativePath: "gone.jpg", status: .missing, trustState: .changedPendingReview)
        let text = GuardianAccessibilityText.finding(finding)
        XCTAssertTrue(text.contains("missing"))
    }

    func testRestoreActionSpeaksReasonAndSelectionState() {
        let action = GuardianRestoreAction(
            relativePath: "b.jpg",
            trustedIdentity: FileIdentity(size: 1, digest: "d"),
            reason: .primaryCorrupt,
            expectedCurrentPrimaryIdentity: FileIdentity(size: 1, digest: "e")
        )
        let selected = GuardianAccessibilityText.restoreAction(action, isSelected: true)
        XCTAssertTrue(selected.contains("b.jpg"))
        XCTAssertTrue(selected.contains("bit rot"))
        XCTAssertTrue(selected.contains("selected for restore"))

        let unselected = GuardianAccessibilityText.restoreAction(action, isSelected: false)
        XCTAssertTrue(unselected.contains("not selected"))
    }
}
