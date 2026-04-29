import SwiftUI
import XCTest
@testable import ChronoframeApp

@MainActor
final class DeduplicateStatusViewTests: XCTestCase {
    /// `Style` controls the icon glyph + tint. The mapping is the
    /// invariant the consolidation relies on — if it drifts, the eight
    /// migrated states drift with it. Pure enum mapping; no rendering.
    func testStyleIconAndTintMappings() {
        XCTAssertNil(DeduplicateStatusView<EmptyView, EmptyView>.Style.progress.systemImage)
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.success.systemImage,
            "checkmark.circle.fill"
        )
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.restored.systemImage,
            "arrow.uturn.backward.circle.fill"
        )
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.warning.systemImage,
            "exclamationmark.triangle.fill"
        )

        // success and restored share the success tint; warning uses
        // the danger tint. Progress uses the action accent.
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.success.tint,
            DeduplicateStatusView<EmptyView, EmptyView>.Style.restored.tint
        )
        XCTAssertNotEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.success.tint,
            DeduplicateStatusView<EmptyView, EmptyView>.Style.warning.tint
        )
    }

    /// Smoke-test: each style renders without crashing for a minimal
    /// configuration. Catches missing required init params or layout
    /// assertions in the shared status surface.
    func testEachStyleRendersWithoutCrashing() {
        let styles: [DeduplicateStatusView<EmptyView, EmptyView>.Style] = [.progress, .success, .restored, .warning]
        for style in styles {
            let view = DeduplicateStatusView<EmptyView, EmptyView>(
                style: style,
                title: "Title",
                message: "Body",
                detail: "12 of 84"
            )
            _ = view.body
        }
    }
}
