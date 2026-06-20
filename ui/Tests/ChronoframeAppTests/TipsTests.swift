import XCTest
@testable import ChronoframeApp

/// Regression coverage for the TipKit discoverability tips (PR E). The tip copy
/// lives in `TipCopy` as plain strings precisely so it can be asserted without
/// rendering SwiftUI `Text`; these tests lock the wording in and confirm the
/// `Tip` types are constructible.
final class TipsTests: XCTestCase {
    func testTipCopyIsPresentAndDistinct() {
        let titles = [
            TipCopy.TimelineScrubbing.title,
            TipCopy.AcceptSafeSuggestions.title,
            TipCopy.DeduplicateWorkspace.title,
        ]
        let messages = [
            TipCopy.TimelineScrubbing.message,
            TipCopy.AcceptSafeSuggestions.message,
            TipCopy.DeduplicateWorkspace.message,
        ]
        for piece in titles + messages {
            XCTAssertFalse(piece.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        XCTAssertEqual(Set(titles).count, titles.count, "Tip titles must be distinct")
    }

    func testAcceptSafeCopyReinforcesTheSafetyInvariant() {
        // The Accept-All-Safe affordance must not imply uncertain matches are
        // auto-selected; the copy explicitly says they are not.
        XCTAssertTrue(
            TipCopy.AcceptSafeSuggestions.message.lowercased().contains("never auto-selects")
        )
    }

    func testTipsAreConstructible() {
        _ = TimelineScrubbingTip()
        _ = AcceptSafeSuggestionsTip()
        _ = DeduplicateWorkspaceTip()
    }

    func testConfigureIsANoOpUnderUITests() {
        // Must not throw or block; tips are suppressed during automation.
        TipConfiguration.configureIfNeeded(isUITest: true)
    }
}
