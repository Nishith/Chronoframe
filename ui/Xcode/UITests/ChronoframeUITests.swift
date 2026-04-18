import XCTest

final class ChronoframeUITests: XCTestCase {
    private enum Scenario: String {
        case setupReady
        case runPreviewReview
        case historyPopulated
        case profilesPopulated
        case settingsSections
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSetupReadyScenarioRendersHeroReadinessAndPrimaryCta() async {
        await MainActor.run {
            let app = Self.launchApp(.setupReady)

            XCTAssertTrue(app.staticTexts["Set Up Your Library"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Preview First, Transfer When Confident"].exists)
            XCTAssertTrue(app.buttons["previewButton"].exists)
            XCTAssertTrue(app.staticTexts["1. Choose Your Source"].exists)
            XCTAssertTrue(app.staticTexts["2. Choose Your Destination"].exists)
        }
    }

    func testRunPreviewReviewScenarioShowsTransferArtifactsAndTabs() async {
        await MainActor.run {
            let app = Self.launchApp(.runPreviewReview)

            XCTAssertTrue(app.staticTexts["Preview Ready for Review"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["startTransferFromPreviewButton"].exists)
            XCTAssertTrue(app.buttons["openDestinationButton"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["runWorkspaceTabs"].exists)
            XCTAssertTrue(app.staticTexts["Artifacts"].exists)
        }
    }

    func testHistoryScenarioShowsArchiveSearchAndArtifactActions() async {
        await MainActor.run {
            let app = Self.launchApp(.historyPopulated)

            XCTAssertTrue(app.staticTexts["Inspect Reports, Receipts, and Logs"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.searchFields.firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any)["historyFilterControl"].exists)
            XCTAssertTrue(app.buttons["useHistoricalSourceButton"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open")).firstMatch.exists)
        }
    }

    func testProfilesScenarioShowsActiveProfileAndUseAction() async {
        await MainActor.run {
            let app = Self.launchApp(.profilesPopulated)

            XCTAssertTrue(app.staticTexts["Reuse the Same Library Configuration"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["profileName-Meridian Travel"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["activeProfileBadge"].exists)
            XCTAssertTrue(app.buttons["Use"].exists)
            XCTAssertTrue(app.buttons["Save Current Paths"].exists)
        }
    }

    func testSettingsScenarioOpensSectionedSettingsWindow() async {
        await MainActor.run {
            let app = Self.launchApp(.settingsSections)

            XCTAssertTrue(app.staticTexts["Performance"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Safety"].exists)
            Self.revealDiagnosticsSection(in: app)
            XCTAssertTrue(app.staticTexts["In-Memory Log Buffer"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    private static func launchApp(_ scenario: Scenario) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["CHRONOFRAME_UI_TEST_SCENARIO"] = scenario.rawValue
        app.launchEnvironment["CHRONOFRAME_UI_TEST_DISABLE_NOTIFICATIONS"] = "1"
        app.launch()
        app.activate()
        ensurePrimaryWindowExists(in: app)
        if scenario == .settingsSections {
            ensureSettingsWindowExists(in: app)
        }
        return app
    }

    @MainActor
    private static func ensurePrimaryWindowExists(in app: XCUIApplication) {
        if app.windows.firstMatch.waitForExistence(timeout: 2) {
            return
        }

        app.typeKey("n", modifierFlags: .command)
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
    }

    @MainActor
    private static func ensureSettingsWindowExists(in app: XCUIApplication) {
        if app.staticTexts["Performance"].waitForExistence(timeout: 2) {
            return
        }

        app.typeKey(",", modifierFlags: .command)
        _ = app.staticTexts["Performance"].waitForExistence(timeout: 5)
    }

    @MainActor
    private static func revealDiagnosticsSection(in app: XCUIApplication) {
        guard !app.staticTexts["In-Memory Log Buffer"].exists else { return }

        app.typeKey(.pageDown, modifierFlags: [])
        if app.staticTexts["In-Memory Log Buffer"].waitForExistence(timeout: 2) {
            return
        }

        app.typeKey(.pageDown, modifierFlags: [])
        _ = app.staticTexts["In-Memory Log Buffer"].waitForExistence(timeout: 2)
    }
}
