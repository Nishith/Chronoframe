import ChronoframeCore
import XCTest
@testable import ChronoframeApp

@MainActor
final class DeduplicateEditedVersionsFooterTests: XCTestCase {
    // AGENTS-INVARIANT: 31
    func testFooterShowsEditedVersionsKeptOnlyWhenPositive() {
        XCTAssertNil(DeduplicateView.editedVersionsKeptLine(count: 0))
        XCTAssertEqual(DeduplicateView.editedVersionsKeptLine(count: 1), "1 edited version kept")
        XCTAssertEqual(DeduplicateView.editedVersionsKeptLine(count: 2), "2 edited versions kept")
        XCTAssertEqual(DeduplicateView.editedVersionsKeptLine(count: 12), "12 edited versions kept")
    }

    // AGENTS-INVARIANT: 31
    func testFooterLineIsDrivenByThePlanCount() {
        let plan = DeduplicationPlan(items: [], editedVariantsKeptCount: 3)
        XCTAssertEqual(
            DeduplicateView.editedVersionsKeptLine(count: plan.editedVariantsKeptCount),
            "3 edited versions kept"
        )
        XCTAssertEqual(DeduplicationPlan(items: []).editedVariantsKeptCount, 0)
    }
}
