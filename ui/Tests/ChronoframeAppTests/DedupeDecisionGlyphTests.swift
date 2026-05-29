import XCTest
@testable import ChronoframeApp

/// Ensures every deduplication decision maps to both a symbol and a text label,
/// so keep/delete state is conveyed by more than color (WCAG 1.4.1).
final class DedupeDecisionGlyphTests: XCTestCase {

    func testEveryDecisionHasASymbolAndLabel() {
        for glyph in DedupeDecisionGlyph.all {
            XCTAssertFalse(glyph.symbolName.isEmpty, "\(glyph) must have a symbol")
            XCTAssertFalse(glyph.symbolName.contains(" "), "SF Symbol names have no spaces: \(glyph.symbolName)")
            XCTAssertFalse(glyph.label.isEmpty, "\(glyph) must have a label")
        }
    }

    func testSymbolsAndLabelsAreDistinctPerDecision() {
        let symbols = Set(DedupeDecisionGlyph.all.map(\.symbolName))
        let labels = Set(DedupeDecisionGlyph.all.map(\.label))
        XCTAssertEqual(symbols.count, DedupeDecisionGlyph.all.count, "Each decision needs a distinct symbol")
        XCTAssertEqual(labels.count, DedupeDecisionGlyph.all.count, "Each decision needs a distinct label")
    }

    func testKeepAndDeleteUseSemanticSymbols() {
        XCTAssertEqual(DedupeDecisionGlyph.keep.label, "Keep")
        XCTAssertEqual(DedupeDecisionGlyph.delete.label, "Delete")
        XCTAssertTrue(DedupeDecisionGlyph.keep.symbolName.contains("checkmark"))
        XCTAssertTrue(DedupeDecisionGlyph.delete.symbolName.contains("trash"))
    }
}
