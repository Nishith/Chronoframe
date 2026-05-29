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
}
