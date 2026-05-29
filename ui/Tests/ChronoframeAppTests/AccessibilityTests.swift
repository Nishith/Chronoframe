#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

/// Validates that accessibility identifiers referenced from XCUITest lookup code are stable
/// string constants, and documents how to run the full VoiceOver / accessibility audit.
///
/// ## Full accessibility audit (manual / CI with Display):
/// On macOS 14+ with an XCUITest target, add:
/// ```swift
/// let app = XCUIApplication()
/// app.launch()
/// try app.performAccessibilityAudit()
/// ```
///
/// ## VoiceOver smoke test (manual):
/// 1. Build and launch Chronoframe.
/// 2. Enable VoiceOver (Cmd+F5).
/// 3. Navigate with Tab and VO+arrow keys through Setup → Preview → Run History.
/// 4. Confirm all interactive elements are announced with meaningful labels.
final class AccessibilityTests: XCTestCase {

    // MARK: - Identifier stability

    /// Ensures every centralized accessibility identifier is non-empty and free of
    /// spaces. A typo or stray space here would cause XCUITest queries to silently
    /// miss elements.
    func testAccessibilityIdentifiersAreNonEmptyAndSpaceFree() {
        XCTAssertFalse(AccessibilityIdentifiers.all.isEmpty, "Expected a non-empty identifier table")
        for id in AccessibilityIdentifiers.all {
            XCTAssertFalse(id.isEmpty, "Accessibility identifier must be non-empty")
            XCTAssertFalse(id.contains(" "), "Accessibility identifier must not contain spaces: \(id)")
        }
    }

    /// Catches copy-paste collisions: two distinct constants resolving to the same
    /// string would make XCUITest queries ambiguous.
    func testAccessibilityIdentifiersAreUnique() {
        let all = AccessibilityIdentifiers.all
        XCTAssertEqual(Set(all).count, all.count, "Accessibility identifiers must be unique")
    }

    /// Contract test binding the App target to the XCUITest target: the identifiers
    /// `ChronoframeUITests` looks up by literal must keep resolving to those literals.
    /// If a constant value changes, update the UI test (or this assertion) deliberately.
    func testAccessibilityIdentifierContractWithUITests() {
        XCTAssertEqual(AccessibilityIdentifiers.previewButton, "previewButton")
        XCTAssertEqual(AccessibilityIdentifiers.transferButton, "transferButton")
        XCTAssertEqual(AccessibilityIdentifiers.startTransferFromPreviewButton, "startTransferFromPreviewButton")
        XCTAssertEqual(AccessibilityIdentifiers.openDestinationButton, "openDestinationButton")
        XCTAssertEqual(AccessibilityIdentifiers.chooseSourceButton, "chooseSourceButton")
        XCTAssertEqual(AccessibilityIdentifiers.chooseDestinationButton, "chooseDestinationButton")
        XCTAssertEqual(AccessibilityIdentifiers.dropZone, "dropZone")
        XCTAssertEqual(AccessibilityIdentifiers.runWorkspaceTabs, "runWorkspaceTabs")
        XCTAssertEqual(AccessibilityIdentifiers.historyFilterControl, "historyFilterControl")
        XCTAssertEqual(AccessibilityIdentifiers.activeProfileBadge, "activeProfileBadge")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeReviewClusterList, "dedupeReviewClusterList")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeCommitFooter, "dedupeCommitFooter")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeAcceptClusterSuggestionButton, "dedupeAcceptClusterSuggestionButton")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeAcceptAllSuggestionsButton, "dedupeAcceptAllSuggestionsButton")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeCommitButton, "dedupeCommitButton")
        // Parameterized identifiers must keep their prefix shape.
        XCTAssertEqual(AccessibilityIdentifiers.profileName("Meridian Travel"), "profileName-Meridian Travel")
        XCTAssertEqual(AccessibilityIdentifiers.openArtifact("abc"), "openArtifact_abc")
        XCTAssertEqual(AccessibilityIdentifiers.revealArtifact("abc"), "revealArtifact_abc")
        XCTAssertEqual(AccessibilityIdentifiers.revertArtifact("abc"), "revertArtifact_abc")
    }

    // MARK: - DesignTokens sanity

    /// Verifies that layout constants are positive values so the views render with non-zero frames.
    func testDesignTokensArePositive() {
        XCTAssertGreaterThan(DesignTokens.Layout.contentMaxWidth, 0)
        XCTAssertGreaterThan(DesignTokens.Layout.setupMaxWidth, 0)
        XCTAssertGreaterThan(DesignTokens.Layout.contentPadding, 0)
        XCTAssertGreaterThan(DesignTokens.Layout.cardPadding, 0)
        XCTAssertGreaterThan(DesignTokens.Layout.consoleFontSize, 0)
        XCTAssertGreaterThan(DesignTokens.Layout.consoleMinHeight, 0)
        XCTAssertGreaterThan(DesignTokens.Layout.consoleIdealHeight, DesignTokens.Layout.consoleMinHeight)
        XCTAssertGreaterThan(DesignTokens.Layout.phaseIndicatorSize, 0)
        XCTAssertGreaterThan(DesignTokens.Layout.phaseConnectorHeight, 0)

        XCTAssertGreaterThan(DesignTokens.Window.mainMinWidth, 0)
        XCTAssertGreaterThan(DesignTokens.Window.mainIdealWidth, DesignTokens.Window.mainMinWidth)
        XCTAssertGreaterThan(DesignTokens.Window.mainMinHeight, 0)
        XCTAssertGreaterThan(DesignTokens.Window.settingsMinWidth, 0)
        XCTAssertGreaterThan(DesignTokens.Window.settingsMinHeight, 0)

        XCTAssertGreaterThan(DesignTokens.Sidebar.minWidth, 0)
        XCTAssertGreaterThan(DesignTokens.Sidebar.maxWidth, DesignTokens.Sidebar.idealWidth)
    }
}
