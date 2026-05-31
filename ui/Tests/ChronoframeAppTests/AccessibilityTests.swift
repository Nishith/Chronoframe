#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import ChronoframeCore
import Foundation
import SwiftUI
import XCTest
@testable import ChronoframeApp

/// Validates that accessibility identifiers referenced from XCUITest lookup code are stable
/// string constants, and documents how to run the full VoiceOver / accessibility audit.
///
/// ## Full accessibility audit (automated):
/// `ChronoframeUITests.testAccessibilityAuditAcrossScenarios` runs Apple's
/// `performAccessibilityAudit()` against every UI scenario on a GUI runner
/// (macOS 14+). It is warn-only until the initial backlog is cleared (see
/// `auditFailsBuild` in that file), then becomes a hard gate.
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

    // MARK: - Accessibility labels

    /// Centralized spoken labels must be present and non-trivial — an empty
    /// drop-zone label or hint would leave a VoiceOver user with no description.
    func testAccessibilityLabelsAreNonEmpty() {
        let labels = [
            AccessibilityLabels.dropZone,
            AccessibilityLabels.dropZoneHint,
        ]
        for label in labels {
            XCTAssertFalse(label.trimmingCharacters(in: .whitespaces).isEmpty, "Accessibility label must be non-empty")
        }
        // The hint should point keyboard users at the equivalent control.
        XCTAssertTrue(AccessibilityLabels.dropZoneHint.localizedCaseInsensitiveContains("choose source"))
    }

    func testAccessibleDesignStrengthensHighContrastSurfaces() {
        XCTAssertFalse(AccessibleDesign.isIncreasedContrast(.standard))
        XCTAssertTrue(AccessibleDesign.isIncreasedContrast(.increased))

        XCTAssertEqual(AccessibleDesign.hairlineWidth(contrast: .standard), 0.5)
        XCTAssertEqual(AccessibleDesign.hairlineWidth(contrast: .increased), 1)

        XCTAssertEqual(AccessibleDesign.tintOverlayOpacity(style: .standard, contrast: .increased), 0)
        XCTAssertEqual(AccessibleDesign.tintOverlayOpacity(style: .section, contrast: .increased), 0)
        XCTAssertLessThan(
            AccessibleDesign.tintOverlayOpacity(style: .inner, contrast: .standard),
            AccessibleDesign.tintOverlayOpacity(style: .inner, contrast: .increased)
        )
        XCTAssertLessThan(
            AccessibleDesign.tintOverlayOpacity(style: .hero, contrast: .standard),
            AccessibleDesign.tintOverlayOpacity(style: .hero, contrast: .increased)
        )
        XCTAssertLessThan(
            AccessibleDesign.neutralOverlayOpacity(contrast: .standard),
            AccessibleDesign.neutralOverlayOpacity(contrast: .increased)
        )
    }

    func testAccessibleFocusRingIsVisibleAndStrongerInHighContrast() {
        XCTAssertEqual(AccessibleFocusRing.lineWidth(isFocused: false, contrast: .standard), 0)
        XCTAssertEqual(AccessibleFocusRing.opacity(isFocused: false, contrast: .standard), 0)
        XCTAssertGreaterThan(
            AccessibleFocusRing.lineWidth(isFocused: true, contrast: .increased),
            AccessibleFocusRing.lineWidth(isFocused: true, contrast: .standard)
        )
        XCTAssertGreaterThan(
            AccessibleFocusRing.opacity(isFocused: true, contrast: .increased),
            AccessibleFocusRing.opacity(isFocused: true, contrast: .standard)
        )
    }

    @MainActor
    func testPathControlKeepsNativeFocusRingAndAccessibilityContext() {
        let nsView = NSPathControl()
        nsView.focusRingType = .default
        PathControl.configure(
            nsView,
            path: "/Users/example/Pictures",
            placeholder: "Choose a folder",
            isInteractive: true
        )

        XCTAssertEqual(nsView.focusRingType, .default)
        XCTAssertEqual(nsView.accessibilityLabel(), "Folder path")
        XCTAssertEqual(nsView.accessibilityValue() as? String, "/Users/example/Pictures")
        XCTAssertEqual(nsView.accessibilityHelp(), "Current folder path. Press to choose a folder.")

        PathControl.configure(
            nsView,
            path: "",
            placeholder: "Choose a source folder",
            isInteractive: false
        )
        XCTAssertEqual(nsView.accessibilityValue() as? String, "Choose a source folder")
        XCTAssertEqual(nsView.accessibilityHelp(), "Current folder path.")
    }

    func testDecisionVisualsDoNotDependOnDimmingWhenDifferentiatingWithoutColor() {
        XCTAssertEqual(
            AccessibleDecisionVisuals.thumbnailOpacity(decision: .delete, differentiateWithoutColor: true),
            1
        )
        XCTAssertEqual(
            AccessibleDecisionVisuals.compactThumbnailOpacity(decision: .delete, differentiateWithoutColor: true),
            1
        )
        XCTAssertLessThan(
            AccessibleDecisionVisuals.thumbnailOpacity(decision: .delete, differentiateWithoutColor: false),
            AccessibleDecisionVisuals.thumbnailOpacity(decision: .keep, differentiateWithoutColor: false)
        )
        XCTAssertLessThan(
            AccessibleDecisionVisuals.compactThumbnailOpacity(decision: .delete, differentiateWithoutColor: false),
            AccessibleDecisionVisuals.compactThumbnailOpacity(decision: .keep, differentiateWithoutColor: false)
        )
    }

    func testDedupeCoreViewsUseAccessibleMaterialAndScaledFonts() throws {
        let checkedFiles = [
            "ClusterDetailPane.swift",
            "ClusterListPane.swift",
            "ComparisonOverlayView.swift",
            "DeduplicateStatusView.swift",
            "DeduplicateView.swift",
            "RapidTriageView.swift",
        ]

        let sourceRoot = try appSourceRoot()
        for filename in checkedFiles {
            let url = sourceRoot
                .appendingPathComponent("Views")
                .appendingPathComponent("Deduplicate")
                .appendingPathComponent(filename)
            let source = try String(contentsOf: url)

            XCTAssertFalse(
                source.contains(".thinMaterial") || source.contains(".regularMaterial") || source.contains(".ultraThinMaterial"),
                "\(filename) should route translucent surfaces through accessibleMaterialBackground(_:fallback:)."
            )
            XCTAssertFalse(
                source.contains(".font(.caption") ||
                source.contains(".font(.caption2") ||
                source.contains(".font(.headline") ||
                source.contains(".font(.subheadline") ||
                source.contains(".font(.title3") ||
                source.contains(".font(.system"),
                "\(filename) should use scaledFont roles for visible text and icon labels."
            )
        }
    }

    private func appSourceRoot() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.last != "ui" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        if url.pathComponents.last == "ui" {
            return url.appendingPathComponent("Sources").appendingPathComponent("ChronoframeApp")
        }
        throw XCTSkip("Could not locate ui/Sources/ChronoframeApp from \(#filePath)")
    }

}
