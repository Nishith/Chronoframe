import Foundation
import XCTest

/// Returns the compiled `<language>.lproj` bundle inside `resources`.
///
/// Only SwiftPM's Swift Build engine (the default from Swift 6.4) compiles
/// `.xcstrings` catalogs into `.lproj` tables; the native build system that
/// CI's Swift 6.1 uses copies the raw catalog instead. A raw catalog in the
/// bundle therefore means the strings were not compiled, even when an
/// `.lproj` exists for other resources such as `InfoPlist.strings`, so the
/// test is skipped: the toolchain, not the catalog, is at fault. A missing
/// `.lproj` in a compiled bundle is still a failure. Setting
/// `CHRONOFRAME_REQUIRE_COMPILED_STRING_CATALOGS=1` turns the skip into a
/// failure.
func localizedTestBundle(_ language: String, in resources: Bundle) throws -> Bundle {
    let rawCatalogs = resources.urls(forResourcesWithExtension: "xcstrings", subdirectory: nil) ?? []
    let required = ProcessInfo.processInfo.environment["CHRONOFRAME_REQUIRE_COMPILED_STRING_CATALOGS"] == "1"
    if !rawCatalogs.isEmpty && !required {
        throw XCTSkip("This toolchain copied the string catalogs without compiling them, so there are no \(language) tables to test.")
    }
    let path = try XCTUnwrap(
        resources.path(forResource: language, ofType: "lproj"),
        "No \(language).lproj in \(resources.bundlePath)"
    )
    return try XCTUnwrap(Bundle(path: path))
}
