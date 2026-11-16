import Foundation
import XCTest
import ChronoframeAppCore
@testable import ChronoframeApp

final class LibraryHealthCopyTests: XCTestCase {
    private func card(_ details: LibraryHealthMessageDetails?) -> LibraryHealthCard {
        LibraryHealthCard(
            id: "test", title: "Test", value: "1", message: "This text is deliberately unrelated to the structured values.",
            severity: .attention, messageDetails: details
        )
    }

    func testUnknownDateBytesAreLocalizedFromStructuredValue() throws {
        let bytes: Int64 = 2_048
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        XCTAssertEqual(
            LibraryHealthCopy.message(card(.unknownDateBytes(bytes)), bundle: try germanAppBundle()),
            "\(size) an Dateien benötigen ein Datum."
        )
    }

    func testDuplicateBytesAreLocalizedFromStructuredValue() throws {
        let bytes: Int64 = 4_096
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        XCTAssertEqual(
            LibraryHealthCopy.message(card(.duplicateBytes(bytes)), bundle: try germanAppBundle()),
            "\(size) können nach deiner Prüfung freigegeben werden."
        )
    }

    func testPendingAndFailedCountsAreLocalizedFromStructuredValues() throws {
        XCTAssertEqual(
            LibraryHealthCopy.message(card(.unfinishedCopies(pending: 2, failed: 1)), bundle: try germanAppBundle()),
            "2 ausstehend, 1 fehlgeschlagen. Öffne „Vorschau & Kopieren“, um sie abzuschließen."
        )
    }

    func testLegacyCardKeepsUnknownMessageVerbatim() throws {
        let legacy = card(nil)
        XCTAssertEqual(LibraryHealthCopy.message(legacy, bundle: try germanAppBundle()), legacy.message)
    }
}
