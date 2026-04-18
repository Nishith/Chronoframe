#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

final class SetupScreenModelTests: XCTestCase {
    func testPrimaryActionAndReadinessTrackManualSetupState() {
        let model = SetupScreenModel(
            context: SetupScreenContext(
                sourcePath: "",
                destinationPath: "",
                selectedProfileName: "",
                activeProfile: nil,
                usingDroppedSource: false,
                droppedSourceLabel: nil,
                droppedSourceItemCount: 0,
                workerCount: 4,
                useFastDestinationScan: false,
                verifyCopies: true,
                isRunInProgress: false
            )
        )

        XCTAssertEqual(model.primaryAction, .chooseSource)
        XCTAssertEqual(model.heroBadgeTitle, "Start Here")
        XCTAssertEqual(model.readinessBadgeTitle, "Needs Setup")
        XCTAssertEqual(model.nextStepSummary, "Choose or drop a source")
        XCTAssertFalse(model.canStartRun)
    }

    func testProfileContextProducesPreviewReadySummary() {
        let profile = Profile(name: "Travel", sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")
        let model = SetupScreenModel(
            context: SetupScreenContext(
                sourcePath: profile.sourcePath,
                destinationPath: profile.destinationPath,
                selectedProfileName: profile.name,
                activeProfile: profile,
                usingDroppedSource: false,
                droppedSourceLabel: nil,
                droppedSourceItemCount: 0,
                workerCount: 8,
                useFastDestinationScan: true,
                verifyCopies: false,
                isRunInProgress: false
            )
        )

        XCTAssertEqual(model.primaryAction, .preview)
        XCTAssertEqual(model.heroBadgeTitle, "Profile Ready")
        XCTAssertEqual(model.modeSummaryValue, "Saved profile: Travel")
        XCTAssertEqual(model.configurationSummary, "Using the saved profile Travel")
        XCTAssertTrue(model.canStartRun)
    }
}
