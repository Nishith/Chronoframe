import Foundation
import XCTest

/// Returns the compiled `<language>.lproj` bundle inside `resources`.
///
/// SwiftPM compiles `.xcstrings` catalogs into `.lproj` tables only on newer
/// toolchains; older ones (CI's Xcode 16 lane) copy the raw catalog instead.
/// When the raw catalog is present but no `.lproj` was produced, the test is
/// skipped rather than failed, because the toolchain, not the catalog, is at
/// fault. Any other missing table is still a failure.
func localizedTestBundle(_ language: String, in resources: Bundle) throws -> Bundle {
    if let path = resources.path(forResource: language, ofType: "lproj") {
        return try XCTUnwrap(Bundle(path: path))
    }
    let rawCatalogs = resources.urls(forResourcesWithExtension: "xcstrings", subdirectory: nil) ?? []
    if !rawCatalogs.isEmpty {
        throw XCTSkip("This toolchain copied the string catalogs without compiling them, so there is no \(language).lproj to test.")
    }
    return try XCTUnwrap(nil as Bundle?, "No \(language).lproj in \(resources.bundlePath)")
}
