#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import XCTest
@testable import ChronoframeApp

@MainActor
final class GuardianAppStateTests: XCTestCase {
    func testGuardianLibraryPathFollowsTheOrganizeDestination() {
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/Volumes/Photos/Library"
        let appState = harness.makeAppState(performInitialBootstrap: false)

        XCTAssertEqual(appState.guardianLibraryPath, "/Volumes/Photos/Library")
    }

    func testGuardianMirrorPathIsEmptyUntilAMirrorIsChosen() {
        let harness = AppStateHarness()
        let appState = harness.makeAppState(performInitialBootstrap: false)

        XCTAssertTrue(appState.guardianMirrorPath.isEmpty)
    }

    func testGuardianStoreStartsIdleWithNoReport() {
        let harness = AppStateHarness()
        let appState = harness.makeAppState(performInitialBootstrap: false)

        XCTAssertNil(appState.guardianStore.report)
        XCTAssertFalse(appState.guardianStore.isScanning)
    }
}
