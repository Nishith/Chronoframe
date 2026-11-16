import Foundation
import XCTest
@testable import ChronoframeApp

final class GermanLocalizationTests: XCTestCase {
    /// Older SwiftPM toolchains (Xcode 16.4's Swift 6.1) copy `.xcstrings`
    /// without compiling it into `de.lproj`, leaving only `InfoPlist.strings`
    /// there. Compile the catalog here when the packaged table is missing.
    private func germanBundle() throws -> Bundle {
        let resources = AppLocalization.resourceBundle
        let packaged = try XCTUnwrap(resources.path(forResource: "de", ofType: "lproj"))
        if FileManager.default.fileExists(atPath: packaged + "/Localizable.strings") {
            return try XCTUnwrap(Bundle(path: packaged))
        }
        let catalog = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ChronoframeApp/Resources/Localizable.xcstrings")
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppGermanLocalizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: output) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcstringstool", "compile", "-o", output.path, catalog.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        let german = output.appendingPathComponent("de.lproj", isDirectory: true)
        let infoPlist = german.appendingPathComponent("InfoPlist.strings")
        if !FileManager.default.fileExists(atPath: infoPlist.path) {
            try FileManager.default.copyItem(atPath: packaged + "/InfoPlist.strings", toPath: infoPlist.path)
        }
        return try XCTUnwrap(Bundle(path: german.path))
    }

    func testPackagedGermanCoversNavigationAndSharedPresentationKeys() throws {
        let german = try germanBundle()
        let expected = [
            "Choose Folders": "Ordner wählen",
            "Privacy": "Datenschutz",
            "Not selected": "Nicht ausgewählt",
            "Nothing to deduplicate": "Nichts zu bereinigen",
        ]
        for (key, value) in expected {
            XCTAssertEqual(AppLocalization.string(key, bundle: german), value, key)
        }
    }

    func testUnknownRuntimeContentFallsBackVerbatim() throws {
        let german = try germanBundle()
        let pathValue = "/Volumes/Photos/Keep/IMG_0001.HEIC"
        XCTAssertEqual(AppLocalization.string(pathValue, bundle: german), pathValue)
    }

    func testEveryTranslatableCatalogEntryHasGerman() throws {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        for relative in [
            "Sources/ChronoframeApp/Resources/Localizable.xcstrings",
            "Sources/ChronoframeAppCore/Resources/LocalizableCore.xcstrings",
        ] {
            let data = try Data(contentsOf: package.appendingPathComponent(relative))
            let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
            for (key, entry) in strings where entry["shouldTranslate"] as? Bool != false {
                let languages = entry["localizations"] as? [String: Any]
                XCTAssertNotNil(languages?["de"], "Missing German: \(relative): \(key)")
            }
        }
    }

    func testPhotosPermissionDescriptionIsPackagedInGerman() throws {
        let german = try germanBundle()
        let description = german.localizedString(forKey: "NSPhotoLibraryUsageDescription", value: nil, table: "InfoPlist")
        XCTAssertTrue(description.contains("niemals etwas geändert, verschoben oder gelöscht"))
    }

    func testSharedCoreDisplayAndNativeButtonKeysResolveInTheAppTable() throws {
        let german = try germanBundle()
        for key in [
            "Photos", "Sort into dated folders", "Copy from Apple Photos", "Remove extra copies",
            "Ready to Organize", "Needs destination", "Run Preview",
            "Add Folders…", "Choose Destination…",
        ] {
            XCTAssertNotEqual(AppLocalization.string(key, bundle: german), key, key)
        }
    }
}
