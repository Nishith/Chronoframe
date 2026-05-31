import XCTest

final class ChronoframeUITests: XCTestCase {
    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"

    private enum Scenario: String, CaseIterable {
        case setupReady
        case runPreviewReview
        case historyPopulated
        case profilesPopulated
        case settingsSections
        case deduplicateReviewWide
        case deduplicateReviewCompact
    }

    private struct AccessibilityAuditAllowlistEntry {
        let scenario: Scenario
        let signature: String
    }

    /// The accessibility audit is a hard gate by default. Local exploratory runs
    /// can opt into warn-only mode with `CHRONOFRAME_A11Y_AUDIT_WARN_ONLY=1`.
    ///
    /// Enforcement is deliberately decoupled from `accessibilityAuditAllowlist`:
    /// the allowlist exists only to absorb individually verified platform false
    /// positives, not to act as the on-switch. An empty allowlist therefore means
    /// "every audit issue fails the build", not "discovery sweep".
    private static var auditFailsBuild: Bool {
        auditFailsBuild(environment: ProcessInfo.processInfo.environment)
    }

    /// Narrow home for unavoidable platform false positives. Keep empty unless a
    /// failure is manually verified as an Apple audit issue rather than app UI.
    /// Entries here are subtracted from the audit; they do not change *whether*
    /// the gate enforces — it always does, outside the warn-only escape hatch.
    private static let accessibilityAuditAllowlist: [AccessibilityAuditAllowlistEntry] = []

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Runs Apple's built-in accessibility audit against every UI scenario,
    /// catching issues like insufficient contrast, undetectable elements,
    /// too-small hit regions, and missing element descriptions.
    ///
    /// Hard-fails by default; see `accessibilityAuditAllowlist` for verified
    /// platform false positives and `CHRONOFRAME_A11Y_AUDIT_WARN_ONLY` for local
    /// exploratory runs.
    @available(macOS 14.0, *)
    func testAccessibilityAuditAcrossScenarios() async {
        await MainActor.run {
            let auditTypes: XCUIAccessibilityAuditType = [
                .contrast,
                .elementDetection,
                .hitRegion,
                .sufficientElementDescription,
            ]

            for scenario in Scenario.allCases {
                let app = Self.launchApp(scenario)
                guard Self.waitForScenarioReady(scenario, in: app) else {
                    XCTFail("Scenario \(scenario.rawValue) did not reach its audit-ready state")
                    app.terminate()
                    continue
                }
                do {
                    try app.performAccessibilityAudit(for: auditTypes) { issue in
                        let description = issue.compactDescription
                        NSLog("A11y audit [%@]: %@", scenario.rawValue, description)
                        if Self.isAllowedAccessibilityAuditIssue(description, scenario: scenario) {
                            return true
                        }
                        return !Self.auditFailsBuild
                    }
                } catch {
                    let message = "Accessibility audit threw for \(scenario.rawValue): \(error)"
                    if Self.auditFailsBuild {
                        XCTFail(message)
                    } else {
                        NSLog("%@ (suppressed in warn mode)", message)
                    }
                }
                app.terminate()
            }
        }
    }

    func testKeyboardTraversalReachesSetupAndDedupePrimaryActions() async {
        await MainActor.run {
            let setupApp = Self.launchApp(.setupReady)
            setupApp.typeKey(.tab, modifierFlags: [])
            setupApp.typeKey(.tab, modifierFlags: [])
            XCTAssertTrue(Self.hittableButton(identifier: "chooseSourceButton", in: setupApp).exists)
            XCTAssertTrue(Self.hittableButton(identifier: "chooseDestinationButton", in: setupApp).exists)
            XCTAssertTrue(Self.button(identifier: "previewButton", in: setupApp).exists)
            setupApp.terminate()

            let dedupeApp = Self.launchApp(.deduplicateReviewWide)
            XCTAssertTrue(Self.element(identifier: "dedupeReviewClusterList", in: dedupeApp).waitForExistence(timeout: 5))
            dedupeApp.typeKey(.downArrow, modifierFlags: [])
            dedupeApp.typeKey(.rightArrow, modifierFlags: [])
            dedupeApp.typeKey("k", modifierFlags: [])
            dedupeApp.typeKey("d", modifierFlags: [])
            XCTAssertTrue(Self.hittableButton(identifier: "dedupeAcceptClusterSuggestionButton", in: dedupeApp).exists)
            XCTAssertTrue(Self.button(identifier: "dedupeCommitButton", in: dedupeApp).exists)
            dedupeApp.terminate()
        }
    }

    func testAccessibilityAuditGateDefaultsToHardFailAndSupportsWarnOnlyEscapeHatch() {
        // Hard-fail by default — independent of whether the allowlist has entries.
        XCTAssertTrue(Self.auditFailsBuild(environment: [:]))
        XCTAssertTrue(Self.auditFailsBuild(
            environment: ["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY": "0"]
        ))
        // The only way to downgrade to warn-only is the explicit escape hatch.
        XCTAssertFalse(Self.auditFailsBuild(
            environment: ["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY": "1"]
        ))
    }

    func testAccessibilityAuditAllowlistMatchesScenarioAndSignatureOnly() {
        let allowlist = [
            AccessibilityAuditAllowlistEntry(
                scenario: .setupReady,
                signature: "known platform issue"
            )
        ]
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            "A known platform issue from XCTest",
            scenario: .setupReady,
            allowlist: allowlist
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            "A known platform issue from XCTest",
            scenario: .deduplicateReviewWide,
            allowlist: allowlist
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            "A missing label regression",
            scenario: .setupReady,
            allowlist: allowlist
        ))
    }

    func testSetupReadyScenarioRendersHeroReadinessAndPrimaryCta() async {
        await MainActor.run {
            let app = Self.launchApp(.setupReady)

            XCTAssertTrue(app.staticTexts["Profiles for Repeatable Runs"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.buttons["previewButton"].exists)
            XCTAssertTrue(app.staticTexts["1. Source"].exists)
            XCTAssertTrue(app.staticTexts["2. Destination"].exists)
            XCTAssertTrue(Self.hittableButton(identifier: "chooseSourceButton", in: app).isHittable)
            XCTAssertTrue(Self.hittableButton(identifier: "chooseDestinationButton", in: app).isHittable)
            XCTAssertTrue(app.staticTexts["Run"].exists)
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

            XCTAssertTrue(app.staticTexts["Reusable Sources"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.searchFields.firstMatch.exists)
            XCTAssertTrue(app.descendants(matching: .any)["historyFilterControl"].exists)
            XCTAssertTrue(app.buttons["useHistoricalSourceButton"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Artifacts"].exists)
            XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Open")).firstMatch.exists)
        }
    }

    func testProfilesScenarioShowsActiveProfileAndUseAction() async {
        await MainActor.run {
            let app = Self.launchApp(.profilesPopulated)

            XCTAssertTrue(app.staticTexts["Save Current Paths"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["profileName-Meridian Travel"].exists)
            XCTAssertTrue(app.descendants(matching: .any)["activeProfileBadge"].exists)
            XCTAssertTrue(app.buttons["Open in Setup"].exists)
            XCTAssertTrue(app.staticTexts["Saved Profiles"].exists)
            XCTAssertTrue(app.buttons["Save"].exists)
        }
    }

    func testSettingsScenarioOpensSectionedSettingsWindow() async {
        await MainActor.run {
            let app = Self.launchApp(.settingsSections)

            XCTAssertTrue(app.windows[Self.settingsWindowIdentifier].waitForExistence(timeout: 5))
            Self.selectSettingsTab(named: "Performance", in: app)
            XCTAssertTrue(app.staticTexts["Safety"].waitForExistence(timeout: 5))
            Self.selectSettingsTab(named: "Diagnostics", in: app)
            XCTAssertTrue(app.staticTexts["Log Buffer"].waitForExistence(timeout: 5))
        }
    }

    func testDeduplicateReviewKeepsActionsVisibleAtWideAndCompactSizes() async {
        await MainActor.run {
            for scenario in [Scenario.deduplicateReviewWide, .deduplicateReviewCompact] {
                let app = Self.launchApp(scenario)

                let clusterList = Self.element(identifier: "dedupeReviewClusterList", in: app)
                XCTAssertTrue(clusterList.waitForExistence(timeout: 5), "Cluster list should render for \(scenario.rawValue)")

                let footer = Self.element(identifier: "dedupeCommitFooter", in: app)
                XCTAssertTrue(footer.waitForExistence(timeout: 10), "Commit footer should render for \(scenario.rawValue)")

                let acceptCluster = Self.hittableButton(identifier: "dedupeAcceptClusterSuggestionButton", in: app)
                let acceptAll = Self.button(identifier: "dedupeAcceptAllSuggestionsButton", in: app)
                let commit = Self.button(identifier: "dedupeCommitButton", in: app)

                XCTAssertTrue(acceptCluster.isHittable, "Accept Suggestion should stay hittable for \(scenario.rawValue)")
                Self.coordinateClick(acceptCluster)
                XCTAssertTrue(acceptAll.waitForExistence(timeout: 5), "Accept All Suggestions should stay visible for \(scenario.rawValue)")
                XCTAssertTrue(acceptAll.isEnabled, "Accept All Suggestions should stay enabled for \(scenario.rawValue)")
                XCTAssertTrue(commit.waitForExistence(timeout: 5), "Commit should stay visible for \(scenario.rawValue)")
                XCTAssertTrue(Self.waitUntilEnabled(commit), "Commit should become enabled after accepting a suggestion for \(scenario.rawValue)")

                let window = app.windows.firstMatch
                XCTAssertTrue(window.exists)
                let framedElements = [
                    ("cluster list", clusterList),
                    ("commit footer", footer),
                    ("accept cluster", acceptCluster),
                    ("accept all", acceptAll),
                    ("commit", commit),
                ]
                for (name, element) in framedElements {
                    Self.assertFrame(element.frame, named: name, isInside: window.frame, scenario: scenario.rawValue)
                }
                XCTAssertLessThanOrEqual(
                    acceptCluster.frame.maxY,
                    footer.frame.minY + 1,
                    "Review actions must not overlap the commit footer for \(scenario.rawValue)"
                )

                app.terminate()
            }
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
    private static func waitForScenarioReady(_ scenario: Scenario, in app: XCUIApplication) -> Bool {
        switch scenario {
        case .setupReady:
            return app.staticTexts["Profiles for Repeatable Runs"].waitForExistence(timeout: 5)
                && button(identifier: "previewButton", in: app).waitForExistence(timeout: 5)
        case .runPreviewReview:
            return app.staticTexts["Preview Ready for Review"].waitForExistence(timeout: 5)
                && button(identifier: "startTransferFromPreviewButton", in: app).waitForExistence(timeout: 5)
        case .historyPopulated:
            return app.staticTexts["Reusable Sources"].waitForExistence(timeout: 5)
                && button(identifier: "useHistoricalSourceButton", in: app).waitForExistence(timeout: 5)
        case .profilesPopulated:
            return app.staticTexts["Save Current Paths"].waitForExistence(timeout: 5)
                && element(identifier: "profileName-Meridian Travel", in: app).waitForExistence(timeout: 5)
        case .settingsSections:
            return app.windows[settingsWindowIdentifier].waitForExistence(timeout: 5)
        case .deduplicateReviewWide, .deduplicateReviewCompact:
            return element(identifier: "dedupeReviewClusterList", in: app).waitForExistence(timeout: 5)
                && element(identifier: "dedupeCommitFooter", in: app).waitForExistence(timeout: 10)
        }
    }

    private static func isAllowedAccessibilityAuditIssue(_ description: String, scenario: Scenario) -> Bool {
        isAllowedAccessibilityAuditIssue(
            description,
            scenario: scenario,
            allowlist: accessibilityAuditAllowlist
        )
    }

    private static func auditFailsBuild(environment: [String: String]) -> Bool {
        environment["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY"] != "1"
    }

    private static func isAllowedAccessibilityAuditIssue(
        _ description: String,
        scenario: Scenario,
        allowlist: [AccessibilityAuditAllowlistEntry]
    ) -> Bool {
        allowlist.contains { entry in
            entry.scenario == scenario && description.localizedCaseInsensitiveContains(entry.signature)
        }
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
        let settingsWindow = app.windows[settingsWindowIdentifier]
        if settingsWindow.waitForExistence(timeout: 2) {
            return
        }

        app.typeKey(",", modifierFlags: .command)
        _ = settingsWindow.waitForExistence(timeout: 5)
    }

    @MainActor
    private static func selectSettingsTab(named title: String, in app: XCUIApplication) {
        let tab = matchingElement(named: title, in: app, type: .tab)
        if tab.waitForExistence(timeout: 1) {
            click(tab)
            return
        }

        let radioButton = matchingElement(named: title, in: app, type: .radioButton)
        if radioButton.waitForExistence(timeout: 1) {
            click(radioButton)
            return
        }

        let button = matchingElement(named: title, in: app, type: .button)
        if button.waitForExistence(timeout: 1) {
            click(button)
            return
        }

        let staticText = matchingElement(named: title, in: app, type: .staticText)
        if staticText.waitForExistence(timeout: 1) {
            click(staticText)
            return
        }

        XCTFail("Could not find settings tab named \(title)")
    }

    @MainActor
    private static func matchingElement(
        named title: String,
        in root: XCUIElement,
        type: XCUIElement.ElementType
    ) -> XCUIElement {
        let predicate = NSPredicate(format: "label == %@", title)
        return root.descendants(matching: type).matching(predicate).firstMatch
    }

    @MainActor
    private static func click(_ element: XCUIElement) {
        if element.isHittable {
            element.click()
        } else {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        }
    }

    @MainActor
    private static func coordinateClick(_ element: XCUIElement) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    @MainActor
    private static func element(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private static func hittableButton(identifier: String, in app: XCUIApplication) -> XCUIElement {
        let query = app.buttons.matching(identifier: identifier)
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if let hittable = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return hittable
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return query.firstMatch
    }

    @MainActor
    private static func button(identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.buttons.matching(identifier: identifier).firstMatch
    }

    @MainActor
    private static func waitUntilEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isEnabled {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return element.exists && element.isEnabled
    }

    private static func assertFrame(
        _ frame: CGRect,
        named name: String,
        isInside windowFrame: CGRect,
        scenario: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let tolerance: CGFloat = 1
        XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX - tolerance, "\(name) should not clip left in \(scenario)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY - tolerance, "\(name) should not clip above the window in \(scenario)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX + tolerance, "\(name) should not clip right in \(scenario)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, windowFrame.maxY + tolerance, "\(name) should not clip below the window in \(scenario)", file: file, line: line)
    }
}
