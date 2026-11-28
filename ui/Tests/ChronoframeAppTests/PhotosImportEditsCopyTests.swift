import XCTest
@testable import ChronoframeApp

@MainActor
final class PhotosImportEditsCopyTests: XCTestCase {
    func testPhotosImportCaptionStatesOriginalsOnlyByDefault() {
        XCTAssertEqual(
            PhotosImportEditsCaption.text(includeEditedVersions: false),
            "Imports the original photo or video. Edits made in Photos, such as crops and filters, are not included."
        )
        XCTAssertEqual(
            PhotosImportEditsCaption.text(includeEditedVersions: true),
            "Also saves the edited version of each edited photo as a separate file. Edited videos and Live Photos are not included."
        )
    }

    func testFAQMentionsPhotosEditsAreNotImported() throws {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: directory.appendingPathComponent("docs/FAQ.md").path) {
            let parent = directory.deletingLastPathComponent()
            if parent == directory {
                XCTFail("Could not find docs/FAQ.md above \(#filePath)")
                return
            }
            directory = parent
        }
        let faq = try String(contentsOf: directory.appendingPathComponent("docs/FAQ.md"), encoding: .utf8)

        XCTAssertTrue(faq.contains("Does importing from Photos keep my edits?"))
        XCTAssertTrue(faq.contains("edits made in Photos, such as crops and filters, are not included"))
        XCTAssertTrue(faq.contains("Your Photos library is never changed"))
    }
}
