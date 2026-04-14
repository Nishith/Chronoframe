import Foundation
import XCTest
@testable import ChronoframeAppCore

final class SetupStoreTests: XCTestCase {
    func testUpdateProfilesSortsAndClearsMissingSelection() {
        let store = SetupStore(
            sourcePath: "/tmp/src",
            destinationPath: "/tmp/dst",
            selectedProfileName: "missing",
            profiles: [Profile(name: "missing", sourcePath: "/tmp/src", destinationPath: "/tmp/dst")]
        )

        store.updateProfiles([
            Profile(name: "zulu", sourcePath: "/tmp/z-src", destinationPath: "/tmp/z-dst"),
            Profile(name: "alpha", sourcePath: "/tmp/a-src", destinationPath: "/tmp/a-dst"),
        ])

        XCTAssertEqual(store.profiles.map(\.name), ["alpha", "zulu"])
        XCTAssertEqual(store.selectedProfileName, "")
        XCTAssertFalse(store.usingProfile)
    }

    func testSelectProfileCopiesPathsAndClearRemovesSelection() {
        let store = SetupStore(profiles: [
            Profile(name: "travel", sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")
        ])

        store.selectProfile(named: "  travel  ")

        XCTAssertEqual(store.selectedProfileName, "travel")
        XCTAssertEqual(store.sourcePath, "/Volumes/Card")
        XCTAssertEqual(store.destinationPath, "/Volumes/Trips")
        XCTAssertEqual(store.activeProfile?.name, "travel")

        store.clearProfileSelection()
        XCTAssertEqual(store.selectedProfileName, "")
        XCTAssertNil(store.activeProfile)
    }

    func testMakeConfigurationUsesTrimmedPathsAndPreferenceFlags() {
        let suiteName = "SetupStoreTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)

        let preferences = PreferencesStore(defaults: defaults)
        preferences.workerCount = 0
        preferences.useFastDestinationScan = true
        preferences.verifyCopies = true

        let store = SetupStore(
            sourcePath: " /tmp/source ",
            destinationPath: " /tmp/destination ",
            selectedProfileName: "saved"
        )

        let configuration = store.makeConfiguration(preferences: preferences, mode: .transfer)

        XCTAssertEqual(configuration.mode, .transfer)
        XCTAssertEqual(configuration.sourcePath, "/tmp/source")
        XCTAssertEqual(configuration.destinationPath, "/tmp/destination")
        XCTAssertEqual(configuration.profileName, "saved")
        XCTAssertTrue(configuration.useFastDestinationScan)
        XCTAssertTrue(configuration.verifyCopies)
        XCTAssertEqual(configuration.workerCount, 1)
        defaults.removePersistentDomain(forName: suiteName)
    }
}
