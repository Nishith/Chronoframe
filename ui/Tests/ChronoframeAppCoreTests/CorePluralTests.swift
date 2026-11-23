import Foundation
import XCTest
@testable import ChronoframeAppCore

/// A count of 1 chooses a complete singular phrase ("1 file", not "1 files"),
/// and German gets the matching case and number ("von 1 Datei"). Zero stays plural.
final class CorePluralTests: XCTestCase {
    private func germanBundle() throws -> Bundle {
        if let path = Bundle.module.path(forResource: "de", ofType: "lproj") {
            return try XCTUnwrap(Bundle(path: path))
        }
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ChronoframeAppCore/Resources/LocalizableCore.xcstrings")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("CorePluralTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcstringstool", "compile", "-o", output.path, catalog.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try XCTUnwrap(Bundle(path: output.appendingPathComponent("de.lproj").path))
    }

    func testRunningFileCountTitle() {
        XCTAssertEqual(CorePlurals.runningFileCount(phaseTitle: "Scanning", completed: 1), "Scanning 1 file…")
        XCTAssertEqual(CorePlurals.runningFileCount(phaseTitle: "Scanning", completed: 0), "Scanning 0 files…")
        XCTAssertEqual(CorePlurals.runningFileCount(phaseTitle: "Scanning", completed: 1_200), "Scanning \(1_200.formatted()) files…")
    }

    func testFileProgressFollowsTheTotal() {
        XCTAssertEqual(CorePlurals.fileProgress(completed: 0, total: 1), "0 of 1 file")
        XCTAssertEqual(CorePlurals.fileProgress(completed: 1, total: 1), "1 of 1 file")
        XCTAssertEqual(CorePlurals.fileProgress(completed: 1, total: 4), "1 of 4 files")
        XCTAssertEqual(CorePlurals.fileProgress(completed: 0, total: 0), "0 of 0 files")
    }

    func testCleanedTemporaryFilesIssue() {
        XCTAssertEqual(CorePlurals.cleanedTemporaryFiles(1), "Cleaned 1 orphaned .tmp file")
        XCTAssertEqual(CorePlurals.cleanedTemporaryFiles(2), "Cleaned 2 orphaned .tmp files")
    }

    func testUnreadableSourceFilesFailure() {
        XCTAssertEqual(
            CorePlurals.unreadableSourceFiles(1),
            "Chronoframe could not read 1 source file, so nothing was copied. Originals were left untouched; check file access and try again."
        )
        XCTAssertEqual(
            CorePlurals.unreadableSourceFiles(3),
            "Chronoframe could not read 3 source files, so nothing was copied. Originals were left untouched; check file access and try again."
        )
    }

    func testPhotosItemsUnreadable() {
        XCTAssertEqual(
            CorePlurals.photosItemsUnreadable(1),
            "1 item couldn't be read and was skipped. Your Photos library was not changed."
        )
        XCTAssertEqual(
            CorePlurals.photosItemsUnreadable(2),
            "2 items couldn't be read and were skipped. Your Photos library was not changed."
        )
    }

    func testPhotosImportKeptStatusFollowsTheTotal() {
        XCTAssertEqual(
            CorePlurals.importStopped(completed: 1, total: 1),
            "Import stopped. 1 of 1 item is ready and was kept. Resume whenever you like. Your Photos library was not changed."
        )
        XCTAssertEqual(
            CorePlurals.importStopped(completed: 1, total: 5),
            "Import stopped. 1 of 5 items are ready and were kept. Resume whenever you like. Your Photos library was not changed."
        )
        XCTAssertEqual(
            CorePlurals.importPausedLowSpace(completed: 0, total: 1),
            "Chronoframe paused the import because the drive holding its staging folder is almost full. 0 of 1 item is ready and was kept. Free up space, then resume. Your Photos library was not changed."
        )
        XCTAssertEqual(
            CorePlurals.importProgressNotSaved(completed: 2, total: 3),
            "Chronoframe stopped the import because it couldn't save its progress. The drive holding its staging folder may be full. 2 of 3 items are ready and were kept. Free up space, then resume. Your Photos library was not changed."
        )
    }

    func testGermanSingularPhrasesAgreeInCaseAndNumber() throws {
        let de = try germanBundle()
        XCTAssertEqual(CorePlurals.runningFileCount(phaseTitle: "Durchsuche", completed: 1, bundle: de), "Durchsuche 1 Datei…")
        XCTAssertEqual(CorePlurals.runningFileCount(phaseTitle: "Durchsuche", completed: 3, bundle: de), "Durchsuche 3 Dateien…")
        XCTAssertEqual(CorePlurals.fileProgress(completed: 1, total: 1, bundle: de), "1 von 1 Datei")
        XCTAssertEqual(CorePlurals.fileProgress(completed: 1, total: 4, bundle: de), "1 von 4 Dateien")
        XCTAssertEqual(CorePlurals.cleanedTemporaryFiles(1, bundle: de), "1 verwaiste .tmp-Datei bereinigt")
        XCTAssertEqual(CorePlurals.cleanedTemporaryFiles(2, bundle: de), "2 verwaiste .tmp-Dateien bereinigt")
        XCTAssertTrue(CorePlurals.unreadableSourceFiles(1, bundle: de).hasPrefix("Chronoframe konnte 1 Quelldatei nicht lesen."))
        XCTAssertTrue(CorePlurals.unreadableSourceFiles(3, bundle: de).hasPrefix("Chronoframe konnte 3 Quelldateien nicht lesen."))
        XCTAssertTrue(CorePlurals.photosItemsUnreadable(1, bundle: de).hasPrefix("1 Objekt konnte nicht gelesen werden und wurde übersprungen."))
        XCTAssertTrue(CorePlurals.photosItemsUnreadable(2, bundle: de).hasPrefix("2 Objekte konnten nicht gelesen werden und wurden übersprungen."))
        XCTAssertTrue(CorePlurals.importStopped(completed: 1, total: 1, bundle: de).hasPrefix("Import gestoppt. 1 von 1 Objekt ist bereit und wurde aufbewahrt."))
        XCTAssertTrue(CorePlurals.importStopped(completed: 1, total: 5, bundle: de).hasPrefix("Import gestoppt. 1 von 5 Objekten sind bereit und wurden aufbewahrt."))
        XCTAssertTrue(CorePlurals.importPausedLowSpace(completed: 0, total: 1, bundle: de).contains("0 von 1 Objekt ist bereit und wurde aufbewahrt."))
        XCTAssertTrue(CorePlurals.importProgressNotSaved(completed: 0, total: 1, bundle: de).contains("0 von 1 Objekt ist bereit und wurde aufbewahrt."))
    }
}
