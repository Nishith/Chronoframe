import Foundation
import XCTest
@testable import ChronoframeApp
@testable import ChronoframeCore

final class DeduplicateReviewCopyTests: XCTestCase {
    private let locale = Locale(identifier: "en_GB")
    private let timeZone = TimeZone(identifier: "UTC") ?? .gmt
    /// 2023-11-14 22:13:20 UTC.
    private let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private func restoration(
        decisions: Int = 12,
        dropped: Int = 0,
        groups: Int = 5,
        changed: Int = 0,
        settingsChanged: Bool = false
    ) -> DeduplicateReviewRestoration {
        DeduplicateReviewRestoration(
            decisions: DedupeDecisions(byPath: [:]),
            approvedClusterIDs: [],
            focusClusterID: nil,
            restoredDecisionCount: decisions,
            droppedDecisionCount: dropped,
            restoredGroupCount: groups,
            changedGroupCount: changed,
            settingsChanged: settingsChanged,
            savedAt: savedAt
        )
    }

    func testRestoredBodyWithNoChanges() {
        let body = DeduplicateReviewCopy.restoredBody(restoration(), locale: locale, timeZone: timeZone)

        XCTAssertTrue(body.hasPrefix("12 choices across 5 groups from "), body)
        XCTAssertTrue(body.contains("14"), body)
        XCTAssertTrue(body.contains("Nov"), body)
        XCTAssertTrue(body.contains("22:13"), body)
        XCTAssertTrue(body.hasSuffix("."), body)
        XCTAssertFalse(body.contains("changed"), body)
        XCTAssertEqual(DeduplicateReviewCopy.restoredTitle, "Your earlier review was restored.")
    }

    func testRestoredBodyMentionsChangedGroupsAndClearedFiles() {
        let body = DeduplicateReviewCopy.restoredBody(
            restoration(dropped: 3, changed: 2),
            locale: locale,
            timeZone: timeZone
        )

        XCTAssertTrue(body.contains(" 2 groups changed since then and need another look."), body)
        XCTAssertTrue(body.hasSuffix(" 3 files changed, so their choices were cleared."), body)

        let onlyDropped = DeduplicateReviewCopy.restoredBody(
            restoration(dropped: 4),
            locale: locale,
            timeZone: timeZone
        )
        XCTAssertFalse(onlyDropped.contains("groups changed"), onlyDropped)
        XCTAssertTrue(onlyDropped.hasSuffix(" 4 files changed, so their choices were cleared."), onlyDropped)

        XCTAssertEqual(
            DeduplicateReviewCopy.settingsChanged,
            "Deduplicate settings changed since that review; groups may differ."
        )
    }

    func testSavedBodySaysNothingIsTrashedUntilConfirmed() {
        let snapshot = DeduplicateReviewSnapshot(
            folderPath: "/dest",
            savedAt: savedAt,
            configurationFingerprint: "fp",
            decisions: [
                DeduplicateSavedDecision(
                    path: "/dest/a.jpg",
                    identity: FileIdentity(size: 1, digest: "a"),
                    decision: .keep
                ),
                DeduplicateSavedDecision(
                    path: "/dest/b.jpg",
                    identity: FileIdentity(size: 1, digest: "b"),
                    decision: .delete
                ),
            ],
            approvals: [DeduplicateSavedGroupApproval(groupKey: "k", memberCount: 2)],
            focusGroupKey: nil
        )

        let body = DeduplicateReviewCopy.savedBody(snapshot, locale: locale, timeZone: timeZone)

        XCTAssertTrue(body.hasPrefix("2 choices and 1 reviewed group saved "), body)
        XCTAssertTrue(body.contains("22:13"), body)
        XCTAssertTrue(
            body.hasSuffix(
                ". Scanning again restores them for files that haven't changed. "
                    + "Nothing is moved to the Trash until you review and confirm."
            ),
            body
        )
    }

    func testRestoredBodyUsesSingularForOne() {
        func body(decisions: Int, groups: Int, dropped: Int = 0, changed: Int = 0) -> String {
            DeduplicateReviewCopy.restoredBody(
                restoration(decisions: decisions, dropped: dropped, groups: groups, changed: changed),
                locale: locale,
                timeZone: timeZone
            )
        }

        XCTAssertTrue(body(decisions: 1, groups: 1).hasPrefix("1 choice across 1 group from "))
        XCTAssertTrue(body(decisions: 3, groups: 1).hasPrefix("3 choices across 1 group from "))
        XCTAssertTrue(body(decisions: 3, groups: 2).hasPrefix("3 choices across 2 groups from "))
        XCTAssertTrue(body(decisions: 1, groups: 2).hasPrefix("1 choice across 2 groups from "))

        XCTAssertTrue(
            body(decisions: 2, groups: 1, changed: 1)
                .contains(" 1 group changed since then and needs another look.")
        )
        XCTAssertTrue(
            body(decisions: 2, groups: 1, dropped: 1)
                .hasSuffix(" 1 file changed, so its choice was cleared.")
        )
        XCTAssertTrue(
            body(decisions: 2, groups: 1, dropped: 2, changed: 2)
                .contains(" 2 groups changed since then and need another look. 2 files changed, so their choices were cleared.")
        )
    }

    func testSavedBodyUsesSingularForOne() {
        func body(decisions: Int, approvals: Int) -> String {
            let snapshot = DeduplicateReviewSnapshot(
                folderPath: "/dest",
                savedAt: savedAt,
                configurationFingerprint: "fp",
                decisions: (0..<decisions).map {
                    DeduplicateSavedDecision(
                        path: "/dest/\($0).jpg",
                        identity: FileIdentity(size: 1, digest: "d\($0)"),
                        decision: .keep
                    )
                },
                approvals: (0..<approvals).map { DeduplicateSavedGroupApproval(groupKey: "k\($0)", memberCount: 2) },
                focusGroupKey: nil
            )
            return DeduplicateReviewCopy.savedBody(snapshot, locale: locale, timeZone: timeZone)
        }

        XCTAssertTrue(body(decisions: 1, approvals: 1).hasPrefix("1 choice and 1 reviewed group saved "))
        XCTAssertTrue(body(decisions: 1, approvals: 2).hasPrefix("1 choice and 2 reviewed groups saved "))
        XCTAssertTrue(body(decisions: 5, approvals: 1).hasPrefix("5 choices and 1 reviewed group saved "))
        XCTAssertTrue(body(decisions: 0, approvals: 0).hasPrefix("0 choices and 0 reviewed groups saved "))
        XCTAssertTrue(
            body(decisions: 1, approvals: 1).hasSuffix(
                ". Scanning again restores them for files that haven't changed. "
                    + "Nothing is moved to the Trash until you review and confirm."
            )
        )
    }

    func testSavedBodyCountsOnlyReviewedChoices() {
        let snapshot = DeduplicateReviewSnapshot(
            folderPath: "/dest",
            savedAt: savedAt,
            configurationFingerprint: "fp",
            decisions: (0..<6).map {
                DeduplicateSavedDecision(
                    path: "/dest/\($0).jpg",
                    identity: FileIdentity(size: 1, digest: "d\($0)"),
                    decision: .keep,
                    inReviewedGroup: $0 < 2
                )
            },
            approvals: [DeduplicateSavedGroupApproval(groupKey: "k", memberCount: 2)],
            focusGroupKey: nil
        )

        let body = DeduplicateReviewCopy.savedBody(snapshot, locale: locale, timeZone: timeZone)

        XCTAssertTrue(body.hasPrefix("2 choices and 1 reviewed group saved "), body)
    }
}
