import Foundation
import XCTest
@testable import ChronoframeAppCore

final class GermanLocalizationTests: XCTestCase {
    private func germanBundle() throws -> Bundle {
        try localizedBundle("de")
    }

    /// Older SwiftPM toolchains (Xcode 16.4's Swift 6.1) copy `.xcstrings` into
    /// the resource bundle without compiling per-language `.lproj` folders, so
    /// compile the catalog here when the folder is missing.
    private func localizedBundle(_ language: String) throws -> Bundle {
        if let path = Bundle.module.path(forResource: language, ofType: "lproj") {
            return try XCTUnwrap(Bundle(path: path))
        }
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ChronoframeAppCore/Resources/LocalizableCore.xcstrings")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("GermanLocalizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcstringstool", "compile", "-o", output.path, catalog.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try XCTUnwrap(Bundle(path: output.appendingPathComponent("\(language).lproj").path))
    }

    func testCoreCatalogResolvesGermanInsteadOfFallingBackToEnglish() throws {
        let bundle = try germanBundle()
        XCTAssertEqual(CoreL10n.text("Find Files", bundle: bundle), "Dateien suchen")
        XCTAssertEqual(CoreL10n.text("Copy complete", bundle: bundle), "Kopieren abgeschlossen")
        XCTAssertEqual(CoreL10n.text("Needs Attention", bundle: bundle), "Benötigt Aufmerksamkeit")
    }

    func testFolderPickerPromptsResolveInTheCoreTable() throws {
        let bundle = try germanBundle()
        for key in [
            "Add Folders", "Choose Destination Folder", "Watch Folder", "Choose Watched Folder",
            "Choose Deduplicate Folder", "Reconnect Archive Folder", "Choose Mirror Folder",
        ] {
            XCTAssertNotEqual(CoreL10n.text(String.LocalizationValue(key), bundle: bundle), key, key)
        }
    }

    func testGermanCountPhrasesUseSingularAndPluralWithoutEnglishSuffixes() throws {
        let bundle = try germanBundle()
        XCTAssertEqual(CoreL10n.files(1, bundle: bundle), "1 Datei")
        XCTAssertEqual(CoreL10n.files(3, bundle: bundle), "3 Dateien")
        XCTAssertEqual(CoreL10n.duplicates(1, bundle: bundle), "1 Duplikat")
        XCTAssertEqual(CoreL10n.duplicates(3, bundle: bundle), "3 Duplikate")
    }

    func testGermanAllowanceInterpolationPreservesBothCounts() throws {
        let bundle = try germanBundle()
        let remaining = 380
        let cap = 500
        let noun = CoreL10n.text("files", bundle: bundle)
        XCTAssertEqual(
            CoreL10n.text("\(remaining) of \(cap) \(noun) left", bundle: bundle),
            "380 von 500 Dateien übrig"
        )
        XCTAssertEqual(
            CoreL10n.text("\(remaining) of \(cap) left", bundle: bundle),
            "380 von 500 übrig"
        )
    }

    func testInterruptedFreeBatchPromptIsGermanAndSaysNothingChanged() throws {
        let bundle = try germanBundle()
        let singular = RunSessionStore.pendingCopyMessage(count: 1, forFreeTestBatch: true, bundle: bundle)
        let plural = RunSessionStore.pendingCopyMessage(count: 3, forFreeTestBatch: true, bundle: bundle)
        XCTAssertTrue(singular.hasPrefix("1 Datei aus einem früheren"))
        XCTAssertTrue(plural.hasPrefix("3 Dateien aus einem früheren"))
        XCTAssertTrue(plural.contains("kostenlosen Testlauf"))
        XCTAssertTrue(plural.hasSuffix("Es wurde nichts kopiert und deine Originale wurden nicht verändert."))
        XCTAssertFalse(plural.contains("files"))
    }

    func testInterruptedResumePromptIsGermanForBothCounts() throws {
        let bundle = try germanBundle()
        XCTAssertTrue(RunSessionStore.pendingCopyMessage(count: 1, forFreeTestBatch: false, bundle: bundle)
            .hasPrefix("1 Datei aus einem früheren Kopiervorgang wartet noch."))
        XCTAssertTrue(RunSessionStore.pendingCopyMessage(count: 3, forFreeTestBatch: false, bundle: bundle)
            .hasPrefix("3 Dateien aus einem früheren Kopiervorgang warten noch."))
    }

    func testGermanMessagesKeepUserPathsAndSafetyGuarantees() throws {
        let path = "/Volumes/Fotos/Urlaub 2026"
        let text = CoreL10n.text(
            "A folder you chose to organize is no longer available. Reconnect the drive or choose the folder again. Path: \(path).",
            bundle: try germanBundle()
        )
        XCTAssertTrue(text.contains("nicht mehr verfügbar"))
        XCTAssertTrue(text.hasSuffix("Pfad: \(path)."))
        XCTAssertEqual(
            CoreL10n.text("Nothing was moved to the Trash.", bundle: try germanBundle()),
            "Es wurde nichts in den Papierkorb gelegt."
        )
    }

    func testEnglishPendingPromptRemainsUnchanged() throws {
        let bundle = try localizedBundle("en")
        XCTAssertEqual(
            RunSessionStore.pendingCopyMessage(count: 1, forFreeTestBatch: false, bundle: bundle),
            "1 file from an earlier copy is still waiting. Resume to finish them, or start over with the current plan."
        )
    }
}
