import Foundation
import XCTest
import ChronoframeAppCore
@testable import ChronoframeApp

final class LibraryHealthCopyTests: XCTestCase {
    private func germanBundle() throws -> Bundle {
        try localizedTestBundle("de", in: AppLocalization.resourceBundle)
    }

    private func card(_ details: LibraryHealthMessageDetails?) -> LibraryHealthCard {
        LibraryHealthCard(
            id: "test", title: "Test", value: "1", message: "This text is deliberately unrelated to the structured values.",
            severity: .attention, messageDetails: details
        )
    }

    func testUnknownDateBytesAreLocalizedFromStructuredValue() throws {
        let german = try germanBundle()
        let bytes: Int64 = 2_048
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        XCTAssertEqual(
            LibraryHealthCopy.message(card(.unknownDateBytes(bytes)), bundle: german),
            "\(size) an Dateien benötigen ein Datum."
        )
    }

    func testDuplicateBytesAreLocalizedFromStructuredValue() throws {
        let german = try germanBundle()
        let bytes: Int64 = 4_096
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        XCTAssertEqual(
            LibraryHealthCopy.message(card(.duplicateBytes(bytes)), bundle: german),
            "\(size) können nach deiner Prüfung freigegeben werden."
        )
    }

    func testPendingAndFailedCountsAreLocalizedFromStructuredValues() throws {
        let german = try germanBundle()
        XCTAssertEqual(
            LibraryHealthCopy.message(card(.unfinishedCopies(pending: 2, failed: 1)), bundle: german),
            "2 ausstehend, 1 fehlgeschlagen. Öffne „Vorschau & Kopieren“, um sie abzuschließen."
        )
    }

    func testLegacyCardKeepsUnknownMessageVerbatim() throws {
        let german = try germanBundle()
        let legacy = card(nil)
        XCTAssertEqual(LibraryHealthCopy.message(legacy, bundle: german), legacy.message)
    }
}
