import ChronoframeCore
import Foundation
import XCTest
@testable import ChronoframeApp

final class SettingsAccessibilityTests: XCTestCase {
    func testReorganizeConfirmationCopyExplainsScopeAndSafety() {
        XCTAssertEqual(ReorganizeConfirmationCopy.title(), "Reorganize destination?")
        XCTAssertEqual(ReorganizeConfirmationCopy.actionLabel(), "Reorganize")

        let message = ReorganizeConfirmationCopy.message(for: .yyyyMonEvent)
        XCTAssertTrue(message.contains("YYYY/Mon/Event"))
        XCTAssertTrue(message.contains("destination"))
        XCTAssertTrue(message.contains("Originals are not deleted"))
        XCTAssertTrue(message.contains("Run workspace"))
    }

    func testReorganizeButtonHintNamesConfirmationAndOriginalSafety() {
        let hint = ReorganizeConfirmationCopy.accessibilityHint(for: .flat)

        XCTAssertTrue(hint.contains("confirmation"))
        XCTAssertTrue(hint.contains("Flat"))
        XCTAssertTrue(hint.contains("Originals are never deleted"))
    }

    func testSettingsReorganizeControlUsesSharedConfirmationCopy() throws {
        let source = try String(contentsOf: settingsSourceURL())

        XCTAssertTrue(source.contains("ReorganizeConfirmationCopy.title()"))
        XCTAssertTrue(source.contains("ReorganizeConfirmationCopy.actionLabel()"))
        XCTAssertTrue(source.contains("ReorganizeConfirmationCopy.message(for: preferencesStore.folderStructure)"))
        XCTAssertTrue(source.contains("ReorganizeConfirmationCopy.accessibilityHint(for: preferencesStore.folderStructure)"))
    }

    private func settingsSourceURL() throws -> URL {
        var url = URL(fileURLWithPath: #filePath)
        while url.pathComponents.last != "ui" && url.path != "/" {
            url.deleteLastPathComponent()
        }
        if url.pathComponents.last == "ui" {
            return url
                .appendingPathComponent("Sources")
                .appendingPathComponent("ChronoframeApp")
                .appendingPathComponent("Views")
                .appendingPathComponent("SettingsView.swift")
        }
        throw XCTSkip("Could not locate ui/Sources/ChronoframeApp from \(#filePath)")
    }
}
