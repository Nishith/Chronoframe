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

    // MARK: - heroTone (design-critique fix #8)
    //
    // heroTone drives the contextual hero icon: idle → brand mark,
    // warning → folder.badge.plus, ready → checkmark.circle.fill.

    func testHeroToneTransitionsAcrossSetupStates() {
        // Neither path → idle (brand mark shown, not a spinner-like icon)
        XCTAssertEqual(makeModel(sourcePath: "", destinationPath: "").heroTone, .idle)

        // Only source set → warning (partially configured)
        XCTAssertEqual(makeModel(sourcePath: "/Volumes/Card", destinationPath: "").heroTone, .warning)

        // Only destination set → warning
        XCTAssertEqual(makeModel(sourcePath: "", destinationPath: "/Volumes/Archive").heroTone, .warning)

        // Both set → ready
        XCTAssertEqual(makeModel(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Archive").heroTone, .ready)
    }

    // MARK: - Helpers

    private func makeModel(sourcePath: String, destinationPath: String) -> SetupScreenModel {
        SetupScreenModel(
            context: SetupScreenContext(
                sourcePath: sourcePath,
                destinationPath: destinationPath,
                selectedProfileName: "",
                activeProfile: nil,
                usingDroppedSource: false,
                droppedSourceLabel: nil,
                droppedSourceItemCount: 0,
                workerCount: 4,
                verifyCopies: true,
                isRunInProgress: false
            )
        )
    }

    func testTrustProofModelSetupSummary() {
        let items = TrustProofModel.setupSafetySummary(source: "/Volumes/Card", destination: "/Volumes/Archive", verifyCopies: true)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].id, "local_only")
        XCTAssertEqual(items[1].id, "source_safe")
        XCTAssertEqual(items[2].id, "verification")
        XCTAssertEqual(items[2].tone, .success)

        let itemsNoVerify = TrustProofModel.setupSafetySummary(source: "/Volumes/Card", destination: "/Volumes/Archive", verifyCopies: false)
        XCTAssertEqual(itemsNoVerify[2].tone, .warning)
    }

    func testTrustProofModelDeduplicateSummary() {
        let items = TrustProofModel.deduplicateSafetySummary(reviewedGroups: 5, unreviewedGroups: 2, willDeleteCount: 10)
        XCTAssertEqual(items.count, 3)
        XCTAssertEqual(items[0].id, "trash_only")
        XCTAssertEqual(items[1].id, "reviewed_only")
        XCTAssertEqual(items[1].tone, .warning)
        XCTAssertEqual(items[2].id, "receipt_write")

        let itemsAllReviewed = TrustProofModel.deduplicateSafetySummary(reviewedGroups: 5, unreviewedGroups: 0, willDeleteCount: 0)
        XCTAssertEqual(itemsAllReviewed.count, 2)
        XCTAssertEqual(itemsAllReviewed[1].tone, .success)
    }
}
