import Foundation
import XCTest
@testable import ChronoframeApp

final class GermanLocalizationTests: XCTestCase {
    private func germanBundle() throws -> Bundle {
        try appGermanTestBundle()
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
