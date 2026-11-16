import Foundation
import XCTest
@testable import ChronoframeApp

extension XCTestCase {
    /// Returns a German bundle for the app's `Localizable` table.
    ///
    /// Older SwiftPM toolchains (Xcode 16.4's Swift 6.1) copy `.xcstrings`
    /// without compiling it into `de.lproj`, leaving only `InfoPlist.strings`
    /// there. Compile the catalog here when the packaged table is missing.
    func appGermanTestBundle() throws -> Bundle {
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
}
