import SwiftUI
import XCTest
@testable import ChronoframeApp

/// Validates the Dynamic Type typography descriptor table. The actual scaling is
/// performed by `@ScaledMetric` inside `ScaledFontModifier` and exercised by the
/// XCUITest accessibility audit; these tests lock down the design intent — the
/// baseline sizes and the text style each role scales relative to — so a future
/// edit cannot silently break the scale's shape.
final class TypographyTests: XCTestCase {

    private typealias Style = DesignTokens.Typography.TypeStyle

    func testEveryRoleHasAPositiveBaseSize() {
        XCTAssertFalse(Style.all.isEmpty)
        for (name, style) in Style.all {
            XCTAssertGreaterThan(style.baseSize, 0, "\(name) must have a positive base size")
        }
    }

    func testScaleOrderingIsSane() {
        // The display/metric roles must remain the largest; body must remain
        // larger than the caption-relative label.
        XCTAssertGreaterThanOrEqual(Style.display.baseSize, Style.title.baseSize)
        XCTAssertGreaterThanOrEqual(Style.title.baseSize, Style.cardTitle.baseSize)
        XCTAssertGreaterThanOrEqual(Style.cardTitle.baseSize, Style.subtitle.baseSize)
        XCTAssertGreaterThanOrEqual(Style.subtitle.baseSize, Style.body.baseSize)
        XCTAssertGreaterThanOrEqual(Style.body.baseSize, Style.label.baseSize)
        XCTAssertGreaterThanOrEqual(Style.metric.baseSize, Style.body.baseSize)
    }

    func testBaselineSizesMatchTheDesignScale() {
        XCTAssertEqual(Style.display.baseSize, 40)
        XCTAssertEqual(Style.title.baseSize, 22)
        XCTAssertEqual(Style.cardTitle.baseSize, 20)
        XCTAssertEqual(Style.subtitle.baseSize, 15)
        XCTAssertEqual(Style.body.baseSize, 13)
        XCTAssertEqual(Style.label.baseSize, 12)
        XCTAssertEqual(Style.metric.baseSize, 32)
        XCTAssertEqual(Style.mono.baseSize, 12)
    }

    func testMonoUsesMonospacedDesign() {
        XCTAssertEqual(Style.mono.design, .monospaced)
    }

    func testRelativeTextStylesAreAssignedForScaling() {
        // Body text scales relative to .body; the largest roles relative to a
        // large title so they grow proportionally under Dynamic Type.
        XCTAssertEqual(Style.body.relativeTo, .body)
        XCTAssertEqual(Style.display.relativeTo, .largeTitle)
        XCTAssertEqual(Style.metric.relativeTo, .largeTitle)
        XCTAssertEqual(Style.label.relativeTo, .caption)
    }

    func testDynamicTypeClampIsAnAccessibilitySize() {
        // The clamp must still allow at least one accessibility size so text can
        // grow for low-vision users, while bounding layout breakage.
        XCTAssertGreaterThanOrEqual(DesignTokens.maxDynamicType, .accessibility1)
    }

    func testCoreWorkflowChromeUsesScaledTypographyRoles() throws {
        let sourceRoot = try appSourceRoot()
        let checkedFiles = [
            "Views/SidebarView.swift",
            "Views/Setup/SetupSectionViews.swift",
            "Views/RunHistoryView.swift",
            "Views/Components/OnboardingCard.swift",
            "Views/Components/WorkspaceTabStrip.swift",
        ]

        for path in checkedFiles {
            let source = try String(contentsOf: sourceRoot.appendingPathComponent(path))
            XCTAssertFalse(
                source.contains(".font("),
                "\(path) should use scaledFont roles so core workflow chrome can grow with text-size accommodations."
            )
        }
    }

    func testScaledCoreChromeIconsDoNotUseFixedFrames() throws {
        let sourceRoot = try appSourceRoot()
        let sidebar = try String(contentsOf: sourceRoot.appendingPathComponent("Views/SidebarView.swift"))
        XCTAssertTrue(sidebar.contains("@ScaledMetric(relativeTo: .callout) private var destinationIconWidth"))
        XCTAssertTrue(sidebar.contains(".frame(width: destinationIconWidth, height: destinationIconHeight)"))
        XCTAssertFalse(sidebar.contains(".frame(width: 20, height: 22)"))
        XCTAssertFalse(sidebar.contains(".monospacedDigit()"))

        let onboarding = try String(contentsOf: sourceRoot.appendingPathComponent("Views/Components/OnboardingCard.swift"))
        XCTAssertTrue(onboarding.contains("@ScaledMetric(relativeTo: .caption) private var dismissButtonSize"))
        XCTAssertTrue(onboarding.contains(".frame(width: dismissButtonSize, height: dismissButtonSize)"))
        XCTAssertFalse(onboarding.contains(".frame(width: 22, height: 22)"))

        let history = try String(contentsOf: sourceRoot.appendingPathComponent("Views/RunHistoryView.swift"))
        XCTAssertTrue(history.contains("@ScaledMetric(relativeTo: .caption) private var actionsMenuIconSize"))
        XCTAssertTrue(history.contains(".frame(width: actionsMenuIconSize, height: actionsMenuIconSize)"))
        XCTAssertFalse(history.contains(".frame(width: 22, height: 22)"))
    }

    func testSettingsAndProfilesUseScaledTypographyRoles() throws {
        let sourceRoot = try appSourceRoot()
        let checkedFiles = [
            "Views/SettingsView.swift",
            "Views/ProfilesView.swift",
        ]

        for path in checkedFiles {
            let source = try String(contentsOf: sourceRoot.appendingPathComponent(path))
            XCTAssertFalse(
                source.contains(".font("),
                "\(path) should use scaledFont roles so preferences and profile controls can grow with text-size accommodations."
            )
        }
    }

    func testSettingsAndProfilesScaledIconsDoNotUseFixedFrames() throws {
        let sourceRoot = try appSourceRoot()
        let profiles = try String(contentsOf: sourceRoot.appendingPathComponent("Views/ProfilesView.swift"))

        XCTAssertTrue(profiles.contains("@ScaledMetric(relativeTo: .body) private var actionsMenuIconSize"))
        XCTAssertTrue(profiles.contains("@ScaledMetric(relativeTo: .caption) private var pathIconWidth"))
        XCTAssertTrue(profiles.contains(".frame(width: actionsMenuIconSize, height: actionsMenuIconSize)"))
        XCTAssertTrue(profiles.contains(".frame(width: pathIconWidth)"))
        XCTAssertFalse(profiles.contains(".frame(width: 22, height: 22)"))
        XCTAssertFalse(profiles.contains(".frame(width: 14)"))
    }

    func testRunAndOrganizeStatusSurfacesUseScaledTypographyRoles() throws {
        let sourceRoot = try appSourceRoot()
        let checkedFiles = [
            "Views/Run/CurrentRunView.swift",
            "Views/Run/PreviewReviewPanel.swift",
            "Views/Run/RunTimelineView.swift",
            "Views/Organize/OrganizeContainerView.swift",
            "Views/Organize/HealthDashboardView.swift",
        ]

        for path in checkedFiles {
            let source = try String(contentsOf: sourceRoot.appendingPathComponent(path))
            XCTAssertFalse(
                source.contains(".font("),
                "\(path) should use scaledFont roles for visible status text."
            )
        }

        let runSections = try String(contentsOf: sourceRoot
            .appendingPathComponent("Views/Run/RunSectionViews.swift"))
        XCTAssertFalse(runSections.contains(".font(.caption"))
        XCTAssertFalse(runSections.contains(".font(.subheadline"))
        XCTAssertEqual(
            runSections.components(separatedBy: ".font(.system(size: DesignTokens.Layout.consoleFontSize").count - 1,
            2,
            "RunSectionViews should reserve fixed monospaced fonts for console/issue log surfaces only."
        )
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
