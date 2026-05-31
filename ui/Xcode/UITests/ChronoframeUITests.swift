import XCTest

final class ChronoframeUITests: XCTestCase {
    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"

    private enum Scenario: String, CaseIterable, Decodable {
        case setupReady
        case runPreviewReview
        case historyPopulated
        case profilesPopulated
        case settingsSections
        case deduplicateReviewWide
        case deduplicateReviewCompact
    }

    private struct AccessibilityAuditBaselineEntry: Decodable {
        let scenario: Scenario
        let auditType: String
        let signature: String
        let severity: String
        let owner: String
        let reason: String
        let expiration: String
        let trackingIssue: String?

        func matches(
            description: String,
            auditType: String,
            scenario: Scenario,
            referenceDate: Date
        ) -> Bool {
            self.scenario == scenario
                && matchesAuditType(auditType)
                && description.localizedCaseInsensitiveContains(signature)
                && !isExpired(referenceDate: referenceDate)
        }

        private func matchesAuditType(_ auditType: String) -> Bool {
            self.auditType == "*" || self.auditType.caseInsensitiveCompare(auditType) == .orderedSame
        }

        private func isExpired(referenceDate: Date) -> Bool {
            guard let expirationDate = Self.expirationFormatter.date(from: expiration) else {
                return true
            }
            return expirationDate < Calendar(identifier: .gregorian).startOfDay(for: referenceDate)
        }

        private static let expirationFormatter: DateFormatter = {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "yyyy-MM-dd"
            return formatter
        }()
    }

    private struct AccessibilityAuditReportEvent: Encodable {
        let scenario: String
        let auditType: String
        let allowedByBaseline: Bool
        let description: String
    }

    /// The accessibility audit is a hard gate by default. Baseline entries are
    /// only for verified platform false positives; local exploratory runs can
    /// opt into warn-only mode with `CHRONOFRAME_A11Y_AUDIT_WARN_ONLY=1`.
    private static var auditFailsBuild: Bool {
        auditFailsBuild(environment: ProcessInfo.processInfo.environment)
    }

    /// Narrow home for unavoidable platform false positives. Keep empty unless
    /// a failure is manually verified as an Apple audit issue rather than app UI.
    private static let accessibilityAuditBaseline: [AccessibilityAuditBaselineEntry] = loadAccessibilityAuditBaseline()

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
            let auditTypes = Self.accessibilityAuditTypes()

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
                        let auditType = Self.auditTypeName(issue)
                        let allowed = Self.isAllowedAccessibilityAuditIssue(
                            description,
                            auditType: auditType,
                            scenario: scenario
                        )
                        Self.writeAccessibilityAuditReport(
                            scenario: scenario,
                            auditType: auditType,
                            allowedByBaseline: allowed,
                            description: description
                        )
                        NSLog("A11y audit [%@/%@]: %@", scenario.rawValue, auditType, description)
                        return allowed || !Self.auditFailsBuild
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
        XCTAssertTrue(Self.auditFailsBuild(environment: [:]))
        XCTAssertTrue(Self.auditFailsBuild(environment: ["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY": "0"]))
        XCTAssertFalse(Self.auditFailsBuild(
            environment: ["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY": "1"]
        ))
    }

    func testAccessibilityAuditGateFailsClosedWithoutBaselineMatch() {
        XCTAssertFalse(Self.shouldAllowAccessibilityAuditIssue(
            "A missing label regression",
            auditType: "sufficientElementDescription",
            scenario: .setupReady,
            baseline: [],
            environment: [:],
            referenceDate: Date(timeIntervalSince1970: 0)
        ))
        XCTAssertTrue(Self.shouldAllowAccessibilityAuditIssue(
            "A missing label regression",
            auditType: "sufficientElementDescription",
            scenario: .setupReady,
            baseline: [],
            environment: ["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY": "1"],
            referenceDate: Date(timeIntervalSince1970: 0)
        ))
    }

    func testAccessibilityAuditBaselineMatchesScenarioAuditTypeSignatureAndExpiration() {
        let baseline = [
            AccessibilityAuditBaselineEntry(
                scenario: .setupReady,
                auditType: "sufficientElementDescription",
                signature: "known platform issue",
                severity: "low",
                owner: "accessibility",
                reason: "Verified XCTest platform false positive.",
                expiration: "2099-01-01",
                trackingIssue: nil
            )
        ]
        XCTAssertTrue(Self.shouldAllowAccessibilityAuditIssue(
            "A known platform issue from XCTest",
            auditType: "sufficientElementDescription",
            scenario: .setupReady,
            baseline: baseline,
            environment: [:],
            referenceDate: Date(timeIntervalSince1970: 0)
        ))
        XCTAssertFalse(Self.shouldAllowAccessibilityAuditIssue(
            "A known platform issue from XCTest",
            auditType: "sufficientElementDescription",
            scenario: .deduplicateReviewWide,
            baseline: baseline,
            environment: [:],
            referenceDate: Date(timeIntervalSince1970: 0)
        ))
        XCTAssertFalse(Self.shouldAllowAccessibilityAuditIssue(
            "A known platform issue from XCTest",
            auditType: "contrast",
            scenario: .setupReady,
            baseline: baseline,
            environment: [:],
            referenceDate: Date(timeIntervalSince1970: 0)
        ))
        XCTAssertFalse(Self.shouldAllowAccessibilityAuditIssue(
            "A missing label regression",
            auditType: "sufficientElementDescription",
            scenario: .setupReady,
            baseline: baseline,
            environment: [:],
            referenceDate: Date(timeIntervalSince1970: 0)
        ))

        let expiredBaseline = [
            AccessibilityAuditBaselineEntry(
                scenario: .setupReady,
                auditType: "*",
                signature: "known platform issue",
                severity: "low",
                owner: "accessibility",
                reason: "Expired false positive.",
                expiration: "1970-01-01",
                trackingIssue: nil
            )
        ]
        XCTAssertFalse(Self.shouldAllowAccessibilityAuditIssue(
            "A known platform issue from XCTest",
            auditType: "contrast",
            scenario: .setupReady,
            baseline: expiredBaseline,
            environment: [:],
            referenceDate: Date(timeIntervalSince1970: 86_400)
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

    @available(macOS 14.0, *)
    private static func accessibilityAuditTypes() -> XCUIAccessibilityAuditType {
        var auditTypes: XCUIAccessibilityAuditType = [
            .contrast,
            .elementDetection,
            .hitRegion,
            .sufficientElementDescription,
        ]
        #if os(macOS)
        auditTypes.insert(.action)
        auditTypes.insert(.parentChild)
        #endif
        return auditTypes
    }

    @available(macOS 14.0, *)
    private static func auditTypeName(_ issue: XCUIAccessibilityAuditIssue) -> String {
        let rawName = String(describing: issue.auditType)
        let knownTypes = [
            "contrast",
            "elementDetection",
            "hitRegion",
            "sufficientElementDescription",
            "action",
            "parentChild",
        ]
        return knownTypes.first { rawName.localizedCaseInsensitiveContains($0) } ?? rawName
    }

    private static func isAllowedAccessibilityAuditIssue(
        _ description: String,
        auditType: String,
        scenario: Scenario
    ) -> Bool {
        shouldAllowAccessibilityAuditIssue(
            description,
            auditType: auditType,
            scenario: scenario,
            baseline: accessibilityAuditBaseline,
            environment: ProcessInfo.processInfo.environment,
            referenceDate: Date()
        )
    }

    private static func auditFailsBuild(environment: [String: String]) -> Bool {
        environment["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY"] != "1"
    }

    private static func shouldAllowAccessibilityAuditIssue(
        _ description: String,
        auditType: String,
        scenario: Scenario,
        baseline: [AccessibilityAuditBaselineEntry],
        environment: [String: String],
        referenceDate: Date
    ) -> Bool {
        if baseline.contains(where: {
            $0.matches(
                description: description,
                auditType: auditType,
                scenario: scenario,
                referenceDate: referenceDate
            )
        }) {
            return true
        }
        return !auditFailsBuild(environment: environment)
    }

    private static func loadAccessibilityAuditBaseline() -> [AccessibilityAuditBaselineEntry] {
        guard let baselineURL = accessibilityAuditBaselineURL() else { return [] }
        do {
            let data = try Data(contentsOf: baselineURL)
            return try JSONDecoder().decode([AccessibilityAuditBaselineEntry].self, from: data)
        } catch {
            NSLog("Could not load accessibility audit baseline at %@: %@", baselineURL.path, "\(error)")
            return []
        }
    }

    private static func accessibilityAuditBaselineURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["CHRONOFRAME_A11Y_AUDIT_BASELINE_PATH"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }

        var directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        while directory.path != "/" {
            let candidate = directory
                .appendingPathComponent("docs")
                .appendingPathComponent("accessibility")
                .appendingPathComponent("audit-baseline.json")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
            directory.deleteLastPathComponent()
        }
        return nil
    }

    private static func writeAccessibilityAuditReport(
        scenario: Scenario,
        auditType: String,
        allowedByBaseline: Bool,
        description: String
    ) {
        guard let directoryPath = ProcessInfo.processInfo.environment["CHRONOFRAME_A11Y_AUDIT_REPORT_DIR"],
              !directoryPath.isEmpty
        else { return }

        do {
            let directoryURL = URL(fileURLWithPath: directoryPath, isDirectory: true)
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let reportURL = directoryURL.appendingPathComponent("accessibility-audit.jsonl")
            let event = AccessibilityAuditReportEvent(
                scenario: scenario.rawValue,
                auditType: auditType,
                allowedByBaseline: allowedByBaseline,
                description: description
            )
            var data = try JSONEncoder().encode(event)
            data.append(0x0A)
            if FileManager.default.fileExists(atPath: reportURL.path) {
                let handle = try FileHandle(forWritingTo: reportURL)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: reportURL)
            }
        } catch {
            NSLog("Could not write accessibility audit report: %@", "\(error)")
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
