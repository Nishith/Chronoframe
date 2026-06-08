import XCTest

final class ChronoframeUITests: XCTestCase {
    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"

    private enum Scenario: String, CaseIterable {
        case setupIncompleteRun
        case setupReady
        case runPreviewReview
        case healthDashboard
        case historyPopulated
        case profilesPopulated
        case settingsSections
        case settingsLayout
        case settingsPerformance
        case settingsDeduplicate
        case settingsDiagnostics
        case deduplicateReviewWide
        case deduplicateReviewCompact

        var opensSettingsOnLaunch: Bool {
            switch self {
            case .profilesPopulated, .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsDiagnostics:
                return true
            default:
                return false
            }
        }
    }

    private struct A11yBaselineEntry: Codable, Sendable {
        let scenario: String
        let auditType: String
        let role: String
        let identifier: String
        let label: String
        let value: String
        let compactDescription: String
        let detailedDescription: String
    }

    private struct A11yAuditFingerprint: Sendable {
        let auditType: String
        let role: String
        let identifier: String
        let label: String
        let value: String
        let compactDescription: String
        let detailedDescription: String
    }

    private enum A11yBaselineLoadError: Error, CustomStringConvertible {
        case missing(URL)
        case empty(URL)
        case decoding(URL, Error)
        case reading(URL, Error)

        var description: String {
            switch self {
            case .missing(let url):
                return "A11yBaseline.json not found at \(url.path)"
            case .empty(let url):
                return "A11yBaseline.json at \(url.path) decoded to zero entries"
            case .decoding(let url, let error):
                return "A11yBaseline.json at \(url.path) could not be decoded: \(error)"
            case .reading(let url, let error):
                return "A11yBaseline.json at \(url.path) could not be read: \(error)"
            }
        }
    }

    private static func baselineURL() -> URL {
        let thisFile = URL(fileURLWithPath: #filePath)
        let uiTestsDir = thisFile.deletingLastPathComponent()
        return uiTestsDir.appendingPathComponent("A11yBaseline.json")
    }

    private static func loadA11yBaselineEntries() throws -> [A11yBaselineEntry] {
        try loadA11yBaselineEntries(from: baselineURL())
    }

    private static func loadA11yBaselineEntries(from baselineURL: URL) throws -> [A11yBaselineEntry] {
        guard FileManager.default.fileExists(atPath: baselineURL.path) else {
            throw A11yBaselineLoadError.missing(baselineURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: baselineURL)
        } catch {
            throw A11yBaselineLoadError.reading(baselineURL, error)
        }

        do {
            let entries = try JSONDecoder().decode([A11yBaselineEntry].self, from: data)
            guard !entries.isEmpty else {
                throw A11yBaselineLoadError.empty(baselineURL)
            }
            NSLog("Successfully loaded %d entries from A11yBaseline.json", entries.count)
            return entries
        } catch let error as A11yBaselineLoadError {
            throw error
        } catch {
            throw A11yBaselineLoadError.decoding(baselineURL, error)
        }
    }

    private struct AccessibilityAuditAllowlistEntry {
        let scenario: Scenario
        let signature: String
    }

    /// The accessibility audit is a hard gate by default. Local exploratory runs
    /// can opt into warn-only mode with
    /// `CHRONOFRAME_A11Y_AUDIT_WARN_ONLY=1`.
    private static var auditFailsBuild: Bool {
        auditFailsBuild(environment: ProcessInfo.processInfo.environment)
    }

    /// Narrow home for unavoidable platform false positives. Keep empty unless a
    /// failure is manually verified as an Apple audit issue rather than app UI.
    /// While this is empty the audit runs as a discovery sweep; adding the first
    /// entry flips the CI path to hard-fail on every non-baselined issue.
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
            let auditFailsBuild = Self.auditFailsBuild
            let baselineEntries: [A11yBaselineEntry]
            do {
                baselineEntries = try Self.loadA11yBaselineEntries()
            } catch {
                let message = "Accessibility audit baseline is unavailable: \(error)"
                if auditFailsBuild {
                    XCTFail(message)
                    return
                }
                NSLog("%@ (continuing in warn-only mode)", message)
                baselineEntries = []
            }

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
                        NSLog("%@", Self.auditLogLine(for: issue, scenario: scenario))
                        if Self.isAllowedAccessibilityAuditIssue(
                            issue,
                            scenario: scenario,
                            baselineEntries: baselineEntries
                        ) {
                            return true
                        }
                        return !auditFailsBuild
                    }
                } catch {
                    let message = "Accessibility audit threw for \(scenario.rawValue): \(error)"
                    if auditFailsBuild {
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
        XCTAssertTrue(Self.auditFailsBuild(
            environment: ["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY": "0"]
        ))
        XCTAssertFalse(Self.auditFailsBuild(
            environment: ["CHRONOFRAME_A11Y_AUDIT_WARN_ONLY": "1"]
        ))
    }

    func testAccessibilityAuditBaselineLoadFailsForMissingMalformedAndEmptyFiles() throws {
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeA11yBaseline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let missing = temporaryDirectory.appendingPathComponent("Missing.json")
        XCTAssertThrowsError(try Self.loadA11yBaselineEntries(from: missing))

        let malformed = temporaryDirectory.appendingPathComponent("Malformed.json")
        try Data("not json".utf8).write(to: malformed)
        XCTAssertThrowsError(try Self.loadA11yBaselineEntries(from: malformed))

        let empty = temporaryDirectory.appendingPathComponent("Empty.json")
        try Data("[]".utf8).write(to: empty)
        XCTAssertThrowsError(try Self.loadA11yBaselineEntries(from: empty))
    }

    func testAccessibilityAuditBaselineRequiresExactScenarioAndSpecificFingerprint() {
        let entry = A11yBaselineEntry(
            scenario: Scenario.setupReady.rawValue,
            auditType: "contrast",
            role: "staticText",
            identifier: "runIdleOnboardingCard",
            label: "",
            value: "",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for HOW IT WORKS"
        )
        let matching = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "runIdleOnboardingCard",
            label: "",
            value: "",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for HOW IT WORKS"
        )

        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            matching,
            scenario: .setupReady,
            baselineEntries: [entry]
        ))

        let sameIdentifierDifferentIssue = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "runIdleOnboardingCard",
            label: "",
            value: "",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for A different label"
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            sameIdentifierDifferentIssue,
            scenario: .setupReady,
            baselineEntries: [entry]
        ))

        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            matching,
            scenario: .setupIncompleteRun,
            baselineEntries: [entry]
        ))
    }

    func testStaticTextContrastIsNotAutoAllowedWithoutMatchingBaseline() {
        let issue = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "newLabel",
            label: "New label",
            value: "",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for New label"
        )

        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            issue,
            scenario: .setupReady,
            baselineEntries: []
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

            XCTAssertTrue(app.staticTexts["1. Source"].waitForExistence(timeout: 5))
            XCTAssertFalse(
                Self.element(identifier: "organizeNextActionBanner", in: app).exists,
                "Setup-ready top chrome must not show the next-action banner"
            )
            XCTAssertTrue(app.buttons["previewButton"].exists)
            XCTAssertTrue(app.staticTexts["2. Destination"].exists)
            XCTAssertTrue(Self.hittableButton(identifier: "chooseSourceButton", in: app).isHittable)
            XCTAssertTrue(Self.hittableButton(identifier: "chooseDestinationButton", in: app).isHittable)
            XCTAssertTrue(app.staticTexts["Start"].exists)
            // Profiles are earned complexity: the scenario seeds none, so the
            // saved-setup section must stay hidden for this first-run state.
            XCTAssertFalse(app.staticTexts["Profiles"].exists)
            // The trust details live behind a single collapsed disclosure.
            XCTAssertTrue(Self.element(identifier: "setupSafetyDetailsDisclosure", in: app).exists)
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

    func testReviewRejectionScreensAvoidKnownOverlapStates() async {
        await MainActor.run {
            let runApp = Self.launchApp(.setupIncompleteRun)
            XCTAssertTrue(runApp.staticTexts["This Workspace Activates After Setup"].waitForExistence(timeout: 5))
            XCTAssertFalse(runApp.buttons["Go to Setup"].exists, "Incomplete Run should not show the top next-action banner")
            XCTAssertTrue(runApp.buttons["Return to Setup"].exists)

            let window = runApp.windows.firstMatch
            let organizeRow = Self.element(identifier: "sidebarDestination-organize", in: runApp)
            XCTAssertTrue(organizeRow.exists)
            XCTAssertGreaterThanOrEqual(
                organizeRow.frame.minY,
                window.frame.minY + 72,
                "Selected sidebar item must stay below the titlebar traffic-light controls"
            )
            runApp.terminate()

            let healthApp = Self.launchApp(.healthDashboard)
            XCTAssertTrue(healthApp.staticTexts["Library Health"].waitForExistence(timeout: 5))
            let refreshButton = Self.button(identifier: "refreshLibraryHealthButton", in: healthApp)
            XCTAssertTrue(refreshButton.waitForExistence(timeout: 5))
            Self.assertFrame(
                refreshButton.frame,
                named: "health refresh button",
                isInside: healthApp.windows.firstMatch.frame,
                scenario: Scenario.healthDashboard.rawValue
            )
            healthApp.terminate()
        }
    }

    func testOrganizeTopChromeNeverShowsNextActionBannerAcrossScreens() async {
        await MainActor.run {
            for scenario in [
                Scenario.setupIncompleteRun,
                .setupReady,
                .runPreviewReview,
                .healthDashboard,
                .historyPopulated,
            ] {
                let app = Self.launchApp(scenario)
                XCTAssertTrue(
                    Self.waitForScenarioReady(scenario, in: app),
                    "\(scenario.rawValue) did not reach ready state"
                )
                XCTAssertFalse(
                    Self.element(identifier: "organizeNextActionBanner", in: app).exists,
                    "Organize top chrome must not show the next-action banner for \(scenario.rawValue)"
                )
                if let anchorLabel = Self.contentAnchorLabel(for: scenario) {
                    let contentAnchor = app.staticTexts[anchorLabel]
                    XCTAssertTrue(contentAnchor.waitForExistence(timeout: 5), "Content anchor should render for \(scenario.rawValue)")

                    let activeTab = Self.element(identifier: Self.organizeTabIdentifier(for: scenario), in: app)
                    XCTAssertTrue(activeTab.waitForExistence(timeout: 5), "Active organize tab should render for \(scenario.rawValue)")
                    XCTAssertLessThanOrEqual(
                        activeTab.frame.maxY,
                        contentAnchor.frame.minY,
                        "Organize top chrome must stay above the content header for \(scenario.rawValue)"
                    )
                }
                app.terminate()
            }
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
        if scenario.opensSettingsOnLaunch {
            ensureSettingsWindowExists(in: app)
        }
        return app
    }

    @MainActor
    private static func waitForScenarioReady(_ scenario: Scenario, in app: XCUIApplication) -> Bool {
        switch scenario {
        case .setupIncompleteRun:
            return app.staticTexts["This Workspace Activates After Setup"].waitForExistence(timeout: 5)
        case .setupReady:
            return app.staticTexts["1. Source"].waitForExistence(timeout: 5)
                && button(identifier: "previewButton", in: app).waitForExistence(timeout: 5)
        case .runPreviewReview:
            return app.staticTexts["Preview Ready for Review"].waitForExistence(timeout: 5)
                && button(identifier: "startTransferFromPreviewButton", in: app).waitForExistence(timeout: 5)
        case .healthDashboard:
            return app.staticTexts["Library Health"].waitForExistence(timeout: 5)
                && button(identifier: "refreshLibraryHealthButton", in: app).waitForExistence(timeout: 5)
        case .historyPopulated:
            return app.staticTexts["Reusable Sources"].waitForExistence(timeout: 5)
                && button(identifier: "useHistoricalSourceButton", in: app).waitForExistence(timeout: 5)
        case .profilesPopulated:
            return app.staticTexts["Save Current Paths"].waitForExistence(timeout: 5)
                && element(identifier: "profileName-Meridian Travel", in: app).waitForExistence(timeout: 5)
        case .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsDiagnostics:
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

    @available(macOS 14.0, *)
    @MainActor
    private static func isAllowedAccessibilityAuditIssue(
        _ issue: XCUIAccessibilityAuditIssue,
        scenario: Scenario,
        baselineEntries: [A11yBaselineEntry]
    ) -> Bool {
        let fingerprint = auditFingerprint(for: issue)
        let matched = isAllowedAccessibilityAuditIssue(
            fingerprint,
            scenario: scenario,
            baselineEntries: baselineEntries
        )

        if !matched {
            NSLog("A11y audit mismatch: scenario=%@, auditType=%@, id=%@, label=%@, role=%@, value=%@, desc=%@, compactDesc=%@",
                  scenario.rawValue,
                  fingerprint.auditType,
                  fingerprint.identifier,
                  fingerprint.label,
                  fingerprint.role,
                  fingerprint.value,
                  fingerprint.detailedDescription,
                  fingerprint.compactDescription)
        }

        return matched
    }

    @available(macOS 14.0, *)
    @MainActor
    private static func auditFingerprint(for issue: XCUIAccessibilityAuditIssue) -> A11yAuditFingerprint {
        let auditTypeString: String
        if issue.auditType.contains(.contrast) {
            auditTypeString = "contrast"
        } else if issue.auditType.contains(.elementDetection) {
            auditTypeString = "elementDetection"
        } else if issue.auditType.contains(.hitRegion) {
            auditTypeString = "hitRegion"
        } else if issue.auditType.contains(.sufficientElementDescription) {
            auditTypeString = "sufficientElementDescription"
        } else {
            auditTypeString = "unknown"
        }

        let elementId = issue.element?.identifier ?? ""
        let elementLabel = issue.element?.label ?? ""

        let roleVal = issue.element?.elementType.rawValue ?? 0
        let elementRole: String
        switch roleVal {
        case 1: elementRole = "application"
        case 3: elementRole = "window"
        case 9: elementRole = "button"
        case 12: elementRole = "menuButton"
        case 14: elementRole = "role_14"
        case 48: elementRole = "staticText"
        case 70: elementRole = "tab"
        case 81: elementRole = "touchBar"
        default: elementRole = roleVal == 0 ? "" : "role_\(roleVal)"
        }

        var elementValue = ""
        if let val = issue.element?.value {
            elementValue = String(describing: val)
        }

        return A11yAuditFingerprint(
            auditType: auditTypeString,
            role: elementRole,
            identifier: elementId,
            label: elementLabel,
            value: elementValue,
            compactDescription: issue.compactDescription,
            detailedDescription: issue.detailedDescription
        )
    }

    private static func isAllowedAccessibilityAuditIssue(
        _ issue: A11yAuditFingerprint,
        scenario: Scenario,
        baselineEntries: [A11yBaselineEntry]
    ) -> Bool {
        baselineEntries.contains { entry in
            guard entry.scenario == scenario.rawValue,
                  entry.auditType == issue.auditType,
                  roleMatches(entry.role, issue.role) else {
                return false
            }

            if !entry.identifier.isEmpty || !issue.identifier.isEmpty {
                guard entry.identifier == issue.identifier else {
                    return false
                }
                return hasStableTextualFingerprint(entry: entry, issue: issue)
            }

            return labelMatches(entry.label, issue.label) &&
                   valueMatches(entry.value, issue.value) &&
                   descriptionMatches(entry: entry, issue: issue)
        }
    }

    private static func hasStableTextualFingerprint(
        entry: A11yBaselineEntry,
        issue: A11yAuditFingerprint
    ) -> Bool {
        if !entry.detailedDescription.isEmpty {
            return detailedDescriptionMatches(entry.detailedDescription, issue.detailedDescription)
        }
        return (!entry.label.isEmpty && labelMatches(entry.label, issue.label)) ||
               (!entry.value.isEmpty && valueMatches(entry.value, issue.value)) ||
               (!entry.compactDescription.isEmpty && compactDescriptionMatches(entry.compactDescription, issue.compactDescription))
    }

    private static func roleMatches(_ entryRole: String, _ issueRole: String) -> Bool {
        entryRole.isEmpty ||
        issueRole.localizedCaseInsensitiveContains(entryRole) ||
        entryRole.localizedCaseInsensitiveContains(issueRole)
    }

    private static func labelMatches(_ entryLabel: String, _ issueLabel: String) -> Bool {
        guard !entryLabel.isEmpty else { return true }
        return issueLabel.localizedCaseInsensitiveContains(entryLabel) ||
               entryLabel.localizedCaseInsensitiveContains(issueLabel)
    }

    private static func valueMatches(_ entryValue: String, _ issueValue: String) -> Bool {
        guard !entryValue.isEmpty else { return true }
        return issueValue.localizedCaseInsensitiveContains(entryValue) ||
               entryValue.localizedCaseInsensitiveContains(issueValue)
    }

    private static func compactDescriptionMatches(_ entryDescription: String, _ issueDescription: String) -> Bool {
        guard !entryDescription.isEmpty else { return true }
        return issueDescription.localizedCaseInsensitiveContains(entryDescription) ||
               entryDescription.localizedCaseInsensitiveContains(issueDescription)
    }

    private static func detailedDescriptionMatches(_ entryDescription: String, _ issueDescription: String) -> Bool {
        guard !entryDescription.isEmpty else { return true }
        let entryTarget = Self.extractContrastTarget(entryDescription)
        let issueTarget = Self.extractContrastTarget(issueDescription)
        let entryNorm = Self.normalizeDescription(entryTarget)
        let issueNorm = Self.normalizeDescription(issueTarget)
        guard !entryNorm.isEmpty else {
            return true
        }
        return issueNorm.contains(entryNorm) || entryNorm.contains(issueNorm)
    }

    private static func descriptionMatches(
        entry: A11yBaselineEntry,
        issue: A11yAuditFingerprint
    ) -> Bool {
        if !entry.detailedDescription.isEmpty {
            return detailedDescriptionMatches(entry.detailedDescription, issue.detailedDescription)
        }
        if !entry.compactDescription.isEmpty {
            return compactDescriptionMatches(entry.compactDescription, issue.compactDescription)
        }
        return true
    }

    private static func extractContrastTarget(_ desc: String) -> String {
        var target = desc
        if target.hasPrefix("Contrast failed for ") {
            target = String(target.dropFirst("Contrast failed for ".count))
        } else if target.hasPrefix("Contrast is not high enough for ") {
            target = String(target.dropFirst("Contrast is not high enough for ".count))
            if target.hasSuffix(" unless font size is larger.") {
                target = String(target.dropLast(" unless font size is larger.".count))
            }
        }
        return target
    }

    private static func normalizeDescription(_ desc: String) -> String {
        var result = desc.lowercased()

        let months = [
            "january", "february", "march", "april", "may", "june",
            "july", "august", "september", "october", "november", "december",
            "jan", "feb", "mar", "apr", "jun", "jul", "aug", "sep", "oct", "nov", "dec"
        ]
        for month in months {
            result = result.replacingOccurrences(of: month, with: "[month]")
        }

        result = result.replacingOccurrences(of: "am", with: "[ampm]")
        result = result.replacingOccurrences(of: "pm", with: "[ampm]")
        result = result.replacingOccurrences(of: "at", with: "")

        var normalizedWithNums = ""
        var inDigitSequence = false
        for char in result {
            if char.isNumber {
                if !inDigitSequence {
                    normalizedWithNums += "[num]"
                    inDigitSequence = true
                }
            } else {
                normalizedWithNums.append(char)
                inDigitSequence = false
            }
        }
        result = normalizedWithNums

        let charsToRemove: Set<Character> = [",", ":", ";", ".", "·", " "]
        result = String(result.filter { !charsToRemove.contains($0) })

        result = result.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return result
    }

    /// Builds one grep-friendly log line per audit issue carrying the offending
    /// element's identity — identifier, label, role, frame — and Apple's
    /// `detailedDescription`, not just the generic `compactDescription`. This
    /// makes the CI log alone enough to locate and fix each finding (which view,
    /// which control), so the backlog can be cleared without a local GUI audit
    /// run. Newlines in the detail are flattened to keep it a single line.
    @available(macOS 14.0, *)
    @MainActor
    private static func auditLogLine(for issue: XCUIAccessibilityAuditIssue, scenario: Scenario) -> String {
        let elementInfo: String
        if let element = issue.element {
            let frame = element.frame
            let frameDesc = "{\(Int(frame.minX)),\(Int(frame.minY)),\(Int(frame.width)),\(Int(frame.height))}"
            elementInfo = "id=\"\(element.identifier)\" label=\"\(element.label)\" role=\(element.elementType.rawValue) frame=\(frameDesc)"
        } else {
            elementInfo = "element=nil"
        }
        let detail = issue.detailedDescription.replacingOccurrences(of: "\n", with: " ")
        return "A11y audit [\(scenario.rawValue)]: \(issue.compactDescription) | \(elementInfo) | \(detail)"
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

    private static func contentAnchorLabel(for scenario: Scenario) -> String? {
        switch scenario {
        case .setupIncompleteRun:
            return "This Workspace Activates After Setup"
        case .setupReady:
            return "Privacy"
        case .runPreviewReview:
            return "Preview Ready for Review"
        case .healthDashboard:
            return "Library Health"
        case .historyPopulated:
            return nil
        case .profilesPopulated,
             .settingsSections,
             .settingsLayout,
             .settingsPerformance,
             .settingsDeduplicate,
             .settingsDiagnostics,
             .deduplicateReviewWide,
             .deduplicateReviewCompact:
            return nil
        }
    }

    private static func organizeTabIdentifier(for scenario: Scenario) -> String {
        switch scenario {
        case .setupReady:
            return "organizeTab.setup"
        case .setupIncompleteRun, .runPreviewReview:
            return "organizeTab.run"
        case .healthDashboard:
            return "organizeTab.health"
        case .historyPopulated:
            return "organizeTab.history"
        case .profilesPopulated,
             .settingsSections,
             .settingsLayout,
             .settingsPerformance,
             .settingsDeduplicate,
             .settingsDiagnostics,
             .deduplicateReviewWide,
             .deduplicateReviewCompact:
            return "organizeTab.setup"
        }
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
