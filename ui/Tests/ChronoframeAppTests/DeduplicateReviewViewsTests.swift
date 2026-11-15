import Foundation
import SwiftUI
import XCTest
@testable import ChronoframeApp
@testable import ChronoframeCore

@MainActor
final class DeduplicateReviewViewsTests: XCTestCase {
    private let savedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private var restoration: DeduplicateReviewRestoration {
        DeduplicateReviewRestoration(
            decisions: DedupeDecisions(byPath: [:]),
            approvedClusterIDs: [],
            focusClusterID: nil,
            restoredDecisionCount: 4,
            droppedDecisionCount: 1,
            restoredGroupCount: 2,
            changedGroupCount: 1,
            settingsChanged: true,
            savedAt: savedAt
        )
    }

    private var snapshot: DeduplicateReviewSnapshot {
        DeduplicateReviewSnapshot(
            folderPath: "/dest",
            savedAt: savedAt,
            configurationFingerprint: "fp",
            decisions: [],
            approvals: [DeduplicateSavedGroupApproval(groupKey: "k", memberCount: 2)],
            focusGroupKey: nil
        )
    }

    func testBannerAndCardExposeIdentifiers() {
        XCTAssertEqual(AccessibilityIdentifiers.dedupeRestoredBanner, "dedupe.restored.banner")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeRestoredBannerDismiss, "dedupe.restored.dismiss")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeSavedReviewResume, "dedupe.saved.resume")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeSavedReviewDiscard, "dedupe.saved.discard")
        for id in [
            AccessibilityIdentifiers.dedupeRestoredBanner,
            AccessibilityIdentifiers.dedupeRestoredBannerDismiss,
            AccessibilityIdentifiers.dedupeSavedReviewResume,
            AccessibilityIdentifiers.dedupeSavedReviewDiscard,
        ] {
            XCTAssertTrue(AccessibilityIdentifiers.all.contains(id), id)
        }

        let banner = DeduplicateRestoredReviewBanner(restoration: restoration, onDismiss: {})
        _ = banner.body
        let card = DeduplicateSavedReviewCard(snapshot: snapshot, resume: {}, discard: {})
        _ = card.body
    }

    func testCardButtonsCallClosures() {
        var resumed = 0
        var discarded = 0
        var dismissed = 0
        let card = DeduplicateSavedReviewCard(
            snapshot: snapshot,
            resume: { resumed += 1 },
            discard: { discarded += 1 }
        )
        let banner = DeduplicateRestoredReviewBanner(restoration: restoration, onDismiss: { dismissed += 1 })

        card.resume()
        XCTAssertEqual(resumed, 1)
        XCTAssertEqual(discarded, 0)
        card.discard()
        XCTAssertEqual(discarded, 1)
        XCTAssertEqual(resumed, 1)

        banner.onDismiss()
        XCTAssertEqual(dismissed, 1)

        // Both views build their bodies with the closures wired in.
        _ = card.body
        _ = banner.body
    }
}
