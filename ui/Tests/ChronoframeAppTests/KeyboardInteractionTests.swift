import CoreGraphics
import XCTest
@testable import ChronoframeApp

/// Unit tests for the pure math behind keyboard- and VoiceOver-driven controls.
/// The view wiring (arrow keys, adjustable actions, drag) all routes through
/// these helpers, so testing them locks the increment/clamp/threshold behavior
/// without needing a running UI.
final class KeyboardInteractionTests: XCTestCase {

    // MARK: - ComparisonSlider

    func testSliderClampsToUnitRange() {
        XCTAssertEqual(ComparisonSlider.clamped(-0.4), 0)
        XCTAssertEqual(ComparisonSlider.clamped(1.7), 1)
        XCTAssertEqual(ComparisonSlider.clamped(0.42), 0.42, accuracy: 0.0001)
    }

    func testSliderAdjustStepsAndClamps() {
        XCTAssertEqual(ComparisonSlider.adjusted(0.5, by: ComparisonSlider.step), 0.55, accuracy: 0.0001)
        XCTAssertEqual(ComparisonSlider.adjusted(0.5, by: -ComparisonSlider.step), 0.45, accuracy: 0.0001)
        // Cannot move past the ends.
        XCTAssertEqual(ComparisonSlider.adjusted(0.98, by: ComparisonSlider.step), 1)
        XCTAssertEqual(ComparisonSlider.adjusted(0.02, by: -ComparisonSlider.step), 0)
    }

    func testSliderFractionFromDragLocation() {
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: 50, width: 200), 0.25, accuracy: 0.0001)
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: -10, width: 200), 0)
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: 300, width: 200), 1)
        // Degenerate width must not divide by zero.
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: 50, width: 0), 0)
    }

    func testSliderAccessibilityValueIsAPercentage() {
        XCTAssertEqual(ComparisonSlider.accessibilityValue(0), "0% keeper")
        XCTAssertEqual(ComparisonSlider.accessibilityValue(0.5), "50% keeper")
        XCTAssertEqual(ComparisonSlider.accessibilityValue(1), "100% keeper")
    }

    // MARK: - RapidTriageSwipe

    func testSwipeOutcomeRespectsThreshold() {
        let t = RapidTriageSwipe.threshold
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: t + 1), .accept)
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: -(t + 1)), .skip)
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: 0), .none)
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: t), .none, "Exactly at threshold should not commit")
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: -t), .none)
    }
}
