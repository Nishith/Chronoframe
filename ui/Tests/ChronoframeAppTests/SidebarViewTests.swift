import ChronoframeAppCore
import XCTest
@testable import ChronoframeApp

@MainActor
final class SidebarViewTests: XCTestCase {
    func testDeduplicateAttentionTokenOnlyExistsForReturnWorthyStates() {
        XCTAssertNil(SidebarView.deduplicateAttentionToken(for: .idle))
        XCTAssertNil(SidebarView.deduplicateAttentionToken(for: .scanning))
        XCTAssertNil(SidebarView.deduplicateAttentionToken(for: .committing))
        XCTAssertNil(SidebarView.deduplicateAttentionToken(for: .reverting))

        XCTAssertEqual(SidebarView.deduplicateAttentionToken(for: .readyToReview), "readyToReview")
        XCTAssertEqual(SidebarView.deduplicateAttentionToken(for: .completed), "completed")
        XCTAssertEqual(SidebarView.deduplicateAttentionToken(for: .reverted), "reverted")
        XCTAssertEqual(SidebarView.deduplicateAttentionToken(for: .failed("Disk full")), "failed")
    }

    func testDeduplicateStatusDotOnlyShowsForUnseenAttentionStates() {
        XCTAssertFalse(SidebarView.shouldShowDeduplicateStatusDot(
            status: .scanning,
            lastSeenToken: ""
        ))

        XCTAssertTrue(SidebarView.shouldShowDeduplicateStatusDot(
            status: .readyToReview,
            lastSeenToken: ""
        ))
        XCTAssertFalse(SidebarView.shouldShowDeduplicateStatusDot(
            status: .readyToReview,
            lastSeenToken: "readyToReview"
        ))

        XCTAssertTrue(SidebarView.shouldShowDeduplicateStatusDot(
            status: .failed("Disk full"),
            lastSeenToken: "completed"
        ))
        XCTAssertFalse(SidebarView.shouldShowDeduplicateStatusDot(
            status: .failed("Disk full"),
            lastSeenToken: "failed"
        ))
    }

    func testDeduplicateSeenTokenResetsWhenWorkRestarts() {
        XCTAssertEqual(SidebarView.nextDeduplicateLastSeenToken(
            status: .scanning,
            isSelected: false,
            currentToken: "completed"
        ), "")
        XCTAssertEqual(SidebarView.nextDeduplicateLastSeenToken(
            status: .completed,
            isSelected: false,
            currentToken: ""
        ), "")
        XCTAssertEqual(SidebarView.nextDeduplicateLastSeenToken(
            status: .completed,
            isSelected: true,
            currentToken: ""
        ), "completed")
    }

    /// The watched-sources token is generation-based: repeated counts
    /// with a bumped generation must re-alert, and an already-seen token
    /// must not.
    func testWatchedSourcesDotShowsOnlyForUnseenTokens() {
        XCTAssertFalse(SidebarView.shouldShowWatchedSourcesDot(token: "", lastSeenToken: ""),
                       "Nothing pending — nothing to point at")
        XCTAssertFalse(SidebarView.shouldShowWatchedSourcesDot(token: "", lastSeenToken: "id:1"))

        XCTAssertTrue(SidebarView.shouldShowWatchedSourcesDot(token: "id:1", lastSeenToken: ""))
        XCTAssertFalse(SidebarView.shouldShowWatchedSourcesDot(token: "id:1", lastSeenToken: "id:1"))
        XCTAssertTrue(SidebarView.shouldShowWatchedSourcesDot(token: "id:2", lastSeenToken: "id:1"),
                      "A bumped generation is new attention even at the same count")
    }
}
