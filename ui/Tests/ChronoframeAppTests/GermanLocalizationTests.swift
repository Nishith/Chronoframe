import Foundation
import XCTest
@testable import ChronoframeApp

final class GermanLocalizationTests: XCTestCase {
    func testPackagedGermanCoversNavigationAndSharedPresentationKeys() throws {
        let german = try germanAppBundle()
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
        let german = try germanAppBundle()
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
        let german = try germanAppBundle()
        let description = german.localizedString(forKey: "NSPhotoLibraryUsageDescription", value: nil, table: "InfoPlist")
        XCTAssertTrue(description.contains("niemals etwas geändert, verschoben oder gelöscht"))
    }

    /// The Preview & Copy ticker passes these lowercase labels as plain strings,
    /// so each needs its own catalog key (the German capture showed
    /// "ALREADY THERE" in English beside translated neighbours).
    func testRunTickerLabelsResolveInGerman() throws {
        let german = try germanAppBundle()
        for key in ["found", "to copy", "copied", "already there", "exact copies", "problems"] {
            XCTAssertNotEqual(AppLocalization.string(key, bundle: german), key, key)
        }
        XCTAssertEqual(AppLocalization.string("already there", bundle: german), "bereits vorhanden")
    }

    /// The Problems tab's suggested fixes were handed to `Label(String, …)`,
    /// which never consults the catalog, so German users saw English.
    @MainActor
    func testSuggestedFixesAreTranslated() throws {
        let german = try germanAppBundle()
        let entries = ["permission denied", "no disk space", "hash mismatch", "unknown date", "file exists"]
            .enumerated()
            .map { RunIssueLineModel(id: $0.offset, text: $0.element, tone: .danger) }

        let english = RunIssuesPanel.suggestedFixes(for: entries)
        let translated = RunIssuesPanel.suggestedFixes(for: entries, bundle: german)

        XCTAssertEqual(translated.count, english.count)
        XCTAssertGreaterThan(translated.count, 1)
        for (de, en) in zip(translated, english) {
            XCTAssertNotEqual(de, en, en)
        }
    }

    /// Row-menu accessibility labels carry the row's name, so the template
    /// (not the interpolated sentence) has to be what gets looked up.
    func testAccessibilityLabelsThatNameARowAreTranslated() throws {
        let german = try germanAppBundle()
        XCTAssertEqual(
            AppLocalization.format("Actions for %@", "Meridian Travel", bundle: german),
            "Aktionen für Meridian Travel"
        )
    }

    /// The Setup tab is now "Choose Folders" ("Ordner wählen"); two hints still
    /// sent people to "Organize › Setup".
    func testDestinationHintsNameTheCurrentTab() throws {
        let german = try germanAppBundle()
        for key in [
            "Set an organize destination in Organize › Choose Folders first — imports go there.",
            "Choose a destination folder in Organize → Choose Folders first; watched folders import into it.",
        ] {
            XCTAssertTrue(AppLocalization.string(key, bundle: german).contains("Ordner wählen"), key)
        }
    }

    func testSharedCoreDisplayAndNativeButtonKeysResolveInTheAppTable() throws {
        let german = try germanAppBundle()
        for key in [
            "Photos", "Sort into dated folders", "Copy from Apple Photos", "Remove extra copies",
            "Ready to Organize", "Needs destination", "Run Preview",
            "Add Folders…", "Choose Destination…",
        ] {
            XCTAssertNotEqual(AppLocalization.string(key, bundle: german), key, key)
        }
    }
}
