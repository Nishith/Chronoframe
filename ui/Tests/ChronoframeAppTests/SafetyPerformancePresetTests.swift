#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

/// BASH-04: clicking Balanced left Safest selected, because the two presets
/// overlapped for 4–8 workers and their summaries promised a destination-scan
/// difference no setting provides. Presets are now exact and distinct,
/// Standard is the app's default configuration, and settings that match
/// none show as Custom.
@MainActor
final class SafetyPerformancePresetTests: XCTestCase {
    // `nonisolated(unsafe)` per the RunSessionStoreTests precedent:
    // XCTest runs setUp/tearDown and the @MainActor test bodies
    // serially, so there is no concurrent access in practice.
    private nonisolated(unsafe) var suiteNames: [String] = []

    override func tearDown() {
        for name in suiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        suiteNames = []
        super.tearDown()
    }

    private func makeDefaults() -> UserDefaults {
        let name = "SafetyPerformancePresetTests-\(UUID().uuidString)"
        suiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    func testDefaultPreferencesMatchStandard() {
        let preferences = PreferencesStore(defaults: makeDefaults())
        XCTAssertEqual(SafetyPerformancePreset.matching(preferences), .standard)
    }

    func testEachPresetIsSelectedAfterApplyingItFromAnyStartingPoint() {
        let preferences = PreferencesStore(defaults: makeDefaults())
        for workers in [1, 4, 8, 9, 12, 32] {
            for parallel in [false, true] {
                for verify in [false, true] {
                    for preset in SafetyPerformancePreset.allCases {
                        preferences.workerCount = workers
                        preferences.parallelTransferEnabled = parallel
                        preferences.verifyCopies = verify

                        preset.apply(to: preferences)

                        let start = "from workers=\(workers) parallel=\(parallel) verify=\(verify)"
                        XCTAssertEqual(SafetyPerformancePreset.matching(preferences), preset, "\(preset) \(start)")
                        XCTAssertTrue(preferences.verifyCopies, "Presets never turn verification off (\(start))")
                    }
                }
            }
        }
    }

    func testPresetsApplyExactDistinctValues() {
        let preferences = PreferencesStore(defaults: makeDefaults())

        SafetyPerformancePreset.oneAtATime.apply(to: preferences)
        XCTAssertEqual(preferences.workerCount, 8)
        XCTAssertFalse(preferences.parallelTransferEnabled)

        SafetyPerformancePreset.standard.apply(to: preferences)
        XCTAssertEqual(preferences.workerCount, 8)
        XCTAssertTrue(preferences.parallelTransferEnabled)
    }

    func testSettingsThatMatchNoPresetAreCustom() {
        let preferences = PreferencesStore(defaults: makeDefaults())
        SafetyPerformancePreset.standard.apply(to: preferences)

        preferences.workerCount = 10
        XCTAssertNil(SafetyPerformancePreset.matching(preferences), "Worker count between presets")

        SafetyPerformancePreset.standard.apply(to: preferences)
        preferences.verifyCopies = false
        XCTAssertNil(SafetyPerformancePreset.matching(preferences), "Verification off is never a preset")

        SafetyPerformancePreset.oneAtATime.apply(to: preferences)
        preferences.workerCount = 12
        XCTAssertNil(SafetyPerformancePreset.matching(preferences), "12 serial workers is neither preset")
    }

    func testSelectedPresetSurvivesRelaunch() {
        let defaults = makeDefaults()
        SafetyPerformancePreset.oneAtATime.apply(to: PreferencesStore(defaults: defaults))

        let relaunched = PreferencesStore(defaults: defaults)
        XCTAssertEqual(SafetyPerformancePreset.matching(relaunched), .oneAtATime)
    }

    func testSummariesDescribeOnlyWhatThePresetSets() {
        for preset in SafetyPerformancePreset.allCases {
            let summary = preset.summary.lowercased()
            XCTAssertFalse(summary.contains("scan"), "\(preset): no preset changes destination scanning")
            XCTAssertFalse(summary.contains("cache"), "\(preset): no preset changes caching")
            XCTAssertTrue(summary.contains("verified"), "\(preset): every preset keeps verification on")
        }
    }
}
