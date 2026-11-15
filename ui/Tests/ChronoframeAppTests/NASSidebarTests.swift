#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import XCTest
@testable import ChronoframeApp

final class NASSidebarTests: XCTestCase {
    override func tearDown() {
        #if DEBUG
        NASCapability.isEnabledOverride = nil
        #endif
        super.tearDown()
    }

    func testSidebarHidesNASWhenDisabled() {
        #if DEBUG
        NASCapability.isEnabledOverride = false
        #endif
        XCTAssertFalse(SidebarDestination.primaryNavigationCases.contains(.nasLibrary))
        XCTAssertTrue(SidebarDestination.allCases.contains(.nasLibrary), "The case exists; only the sidebar entry is gated")
    }

    func testSidebarShowsNASAfterDeduplicateWhenEnabled() throws {
        #if DEBUG
        NASCapability.isEnabledOverride = true
        let cases = SidebarDestination.primaryNavigationCases
        let dedupe = try XCTUnwrap(cases.firstIndex(of: .deduplicate))
        let nas = try XCTUnwrap(cases.firstIndex(of: .nasLibrary))
        XCTAssertEqual(nas, dedupe + 1)
        XCTAssertEqual(Array(cases.prefix(3)), [.organize, .photos, .deduplicate])
        #else
        throw XCTSkip("The override exists only in DEBUG builds")
        #endif
    }

    func testNASDestinationMetadata() {
        let destination = SidebarDestination.nasLibrary
        XCTAssertEqual(destination.rawValue, "nasLibrary")
        XCTAssertEqual(destination.title, "NAS Library")
        XCTAssertEqual(destination.systemImage, "externaldrive.connected.to.line.below")
        XCTAssertEqual(destination.section, .library)
        XCTAssertFalse(destination.subtitle.isEmpty)
    }
}
