import XCTest

final class ChronoframeUITests: XCTestCase {
    private static let settingsWindowIdentifier = "com_apple_SwiftUI_Settings_window"

    private enum Scenario: String, CaseIterable {
        case setupIncompleteRun
        case setupReady
        case runPreviewReview
        case healthDashboard
        case watchedSources
        case historyPopulated
        case profilesPopulated
        case settingsSections
        case settingsLayout
        case settingsPerformance
        case settingsDeduplicate
        case settingsLicense
        case settingsDiagnostics
        case deduplicateReviewWide
        case deduplicateReviewCompact

        var opensSettingsOnLaunch: Bool {
            switch self {
            case .profilesPopulated, .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsLicense, .settingsDiagnostics:
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
        case decoding(URL, Error)
        case reading(URL, Error)

        var description: String {
            switch self {
            case .missing(let url):
                return "A11yBaseline.json not found at \(url.path)"
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

            for scenario in Self.requestedAuditScenarios {
                let app = Self.launchApp(scenario)
                guard Self.waitForScenarioReady(scenario, in: app) else {
                    XCTFail("Scenario \(scenario.rawValue) did not reach its audit-ready state")
                    app.terminate()
                    continue
                }
                var unmatchedIssues: [String] = []
                var auditThrew = false
                do {
                    try app.performAccessibilityAudit(for: auditTypes) { issue in
                        let logLine = Self.auditLogLine(for: issue, scenario: scenario)
                        NSLog("%@", logLine)
                        if Self.isAllowedAccessibilityAuditIssue(
                            issue,
                            scenario: scenario,
                            baselineEntries: baselineEntries
                        ) {
                            return true
                        }
                        unmatchedIssues.append(logLine)
                        return !auditFailsBuild
                    }
                } catch {
                    auditThrew = true
                    var message = "Accessibility audit threw for \(scenario.rawValue): \(error)"
                    if !unmatchedIssues.isEmpty {
                        message += "\nUnmatched issue(s):\n\(unmatchedIssues.joined(separator: "\n"))"
                    }
                    if auditFailsBuild {
                        XCTFail(message)
                    } else {
                        NSLog("%@ (suppressed in warn mode)", message)
                    }
                }
                if !auditThrew, !unmatchedIssues.isEmpty {
                    let message = """
                    Accessibility audit found \(unmatchedIssues.count) unmatched issue(s) for \(scenario.rawValue):
                    \(unmatchedIssues.joined(separator: "\n"))
                    """
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

    private static var requestedAuditScenarios: [Scenario] {
        let rawValue = ProcessInfo.processInfo.environment["CHRONOFRAME_A11Y_AUDIT_SCENARIOS"] ?? ""
        let names = rawValue
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !names.isEmpty else {
            return Array(Scenario.allCases)
        }
        let scenarios = names.compactMap(Scenario.init(rawValue:))
        return scenarios.isEmpty ? Array(Scenario.allCases) : scenarios
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

    func testAccessibilityAuditBaselineLoadFailsForMissingAndMalformedFilesButAllowsEmptyArray() throws {
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
        XCTAssertEqual(try Self.loadA11yBaselineEntries(from: empty).count, 0)
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

    func testAppOwnedStaticTextContrastFindingsAreNotBypassed() {
        let tickerIssue = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "",
            value: "discovered: 84, planned: 42, copied: 0, already there: 29, duplicates: 7, issues: 1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for discovered: 84, planned: 42, copied: 0, already there: 29, duplicates: 7, issues: 1"
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            tickerIssue,
            scenario: .runPreviewReview,
            baselineEntries: []
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            tickerIssue,
            scenario: .setupReady,
            baselineEntries: []
        ))

        let unrelatedStaticText = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "",
            value: "ready: 1",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for ready: 1"
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            unrelatedStaticText,
            scenario: .runPreviewReview,
            baselineEntries: []
        ))

        let historyHeaderCount = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "",
            value: "2 artifacts · 1 reusable sources.",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for 2 artifacts · 1 reusable sources."
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            historyHeaderCount,
            scenario: .historyPopulated,
            baselineEntries: []
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            historyHeaderCount,
            scenario: .setupReady,
            baselineEntries: []
        ))
    }

    func testBaselineMatchingNormalizesLocalizedTimestampSpacing() {
        let entry = A11yBaselineEntry(
            scenario: Scenario.historyPopulated.rawValue,
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "",
            value: "12:00 AM",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for 12:00 AM"
        )
        let ciIssue = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "",
            value: "12:00\u{202F}AM",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for 12:00\u{202F}AM"
        )

        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            ciIssue,
            scenario: .historyPopulated,
            baselineEntries: [entry]
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            ciIssue,
            scenario: .setupReady,
            baselineEntries: [entry]
        ))
    }

    func testSystemOwnedAccessibilityAuditFindingsAreBypassedNarrowly() {
        let touchBar = A11yAuditFingerprint(
            auditType: "sufficientElementDescription",
            role: "touchBar",
            identifier: "",
            label: "",
            value: "",
            compactDescription: "Element has no description",
            detailedDescription: "This element is missing useful accessibility information."
        )
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            touchBar,
            scenario: .setupReady,
            baselineEntries: []
        ))

        let emojiPicker = A11yAuditFingerprint(
            auditType: "sufficientElementDescription",
            role: "role_14",
            identifier: "",
            label: "emoji & symbols",
            value: "",
            compactDescription: "Element has no description",
            detailedDescription: "This element is missing useful accessibility information."
        )
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            emojiPicker,
            scenario: .profilesPopulated,
            baselineEntries: []
        ))

        let settingsTitlebarText = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "",
            value: "Settings",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for Settings"
        )
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            settingsTitlebarText,
            scenario: .settingsSections,
            baselineEntries: []
        ))

        let settingsTitlebarLabelText = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "Settings",
            value: "",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for Settings"
        )
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            settingsTitlebarLabelText,
            scenario: .settingsSections,
            baselineEntries: []
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            settingsTitlebarLabelText,
            scenario: .setupReady,
            baselineEntries: []
        ))

        let appTitlebarText = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "",
            label: "",
            value: "Chronoframe",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for Chronoframe"
        )
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            appTitlebarText,
            scenario: .deduplicateReviewWide,
            baselineEntries: []
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            appTitlebarText,
            scenario: .setupReady,
            baselineEntries: []
        ))

        let appMenu = A11yAuditFingerprint(
            auditType: "sufficientElementDescription",
            role: "role_14",
            identifier: "",
            label: "Actions for source",
            value: "",
            compactDescription: "Element has no description",
            detailedDescription: "This element is missing useful accessibility information."
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            appMenu,
            scenario: .historyPopulated,
            baselineEntries: []
        ))
    }

    // Regression coverage for BASH-06's review finding: a toolbar-title false
    // positive must be matched exactly, not by substring, so a genuine contrast
    // regression on unrelated app-authored text sharing a word (e.g. "Library
    // Health" / "Healthy" on healthDashboard) is never silently swallowed.
    func testToolbarTitleFalsePositivesAreMatchedExactlyNotBySubstring() {
        func toolbarTitleIssue(_ title: String) -> A11yAuditFingerprint {
            A11yAuditFingerprint(
                auditType: "contrast",
                role: "staticText",
                identifier: "",
                label: "",
                value: title,
                compactDescription: "Contrast failed",
                detailedDescription: "Contrast failed for \(title)"
            )
        }

        let expectations: [(Scenario, String)] = [
            (.setupIncompleteRun, "Run"),
            (.runPreviewReview, "Run"),
            (.setupReady, "Setup"),
            (.healthDashboard, "Health"),
            (.watchedSources, "Organize"),
            (.historyPopulated, "Run History")
        ]
        for (scenario, title) in expectations {
            XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
                toolbarTitleIssue(title),
                scenario: scenario,
                baselineEntries: []
            ), "\(title) toolbar title should be bypassed on \(scenario)")
        }

        // A different scenario's toolbar title must not leak across scenarios.
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            toolbarTitleIssue("Setup"),
            scenario: .healthDashboard,
            baselineEntries: []
        ))

        // The healthDashboard scenario renders "Library Health" (card title) and
        // "Healthy" (legend) as real app-authored text alongside the "Health"
        // toolbar title. A substring match would incorrectly bypass contrast
        // regressions on these — they must still hard-fail.
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            toolbarTitleIssue("Library Health"),
            scenario: .healthDashboard,
            baselineEntries: []
        ))
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            toolbarTitleIssue("Healthy"),
            scenario: .healthDashboard,
            baselineEntries: []
        ))
    }

    // Regression coverage for a second BASH-06 review finding: the setupReady
    // scenario's DetailHeroCard renders a "Setup" title (SetupSectionViews.swift)
    // that is textually identical to the window's ".navigationTitle(\"Setup\")".
    // Matching by exact text alone (rather than substring) does not disambiguate
    // two elements with the *same* text, so the hero card title now carries a
    // non-empty accessibilityIdentifier (AccessibilityIdentifiers.setupHeroTitle
    // in the app target, "setupHeroTitle" here) specifically so its audit
    // fingerprint no longer satisfies the toolbar-title bypass's
    // `identifier.isEmpty` precondition — a genuine contrast regression on that
    // card title must still hard-fail.
    func testSetupHeroCardTitleIsNotBypassedAsToolbarTitleFalsePositive() {
        let heroCardTitleIssue = A11yAuditFingerprint(
            auditType: "contrast",
            role: "staticText",
            identifier: "setupHeroTitle",
            label: "",
            value: "Setup",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for Setup"
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            heroCardTitleIssue,
            scenario: .setupReady,
            baselineEntries: []
        ), "The hero card's \"Setup\" title must not be bypassed by the toolbar-title exception now that it carries its own accessibility identifier")
    }

    func testUnlabeledSwiftUILayoutWrapperFindingsAreBypassedNarrowly() {
        let layoutGroup = A11yAuditFingerprint(
            auditType: "sufficientElementDescription",
            role: "window",
            identifier: "",
            label: "",
            value: "",
            compactDescription: "Element has no description",
            detailedDescription: "This element is missing useful accessibility information."
        )
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            layoutGroup,
            scenario: .runPreviewReview,
            baselineEntries: []
        ))

        let layoutOther = A11yAuditFingerprint(
            auditType: "sufficientElementDescription",
            role: "application",
            identifier: "",
            label: "",
            value: "",
            compactDescription: "Element has no description",
            detailedDescription: "This element is missing useful accessibility information."
        )
        XCTAssertTrue(Self.isAllowedAccessibilityAuditIssue(
            layoutOther,
            scenario: .healthDashboard,
            baselineEntries: []
        ))

        let labeledWindow = A11yAuditFingerprint(
            auditType: "sufficientElementDescription",
            role: "window",
            identifier: "",
            label: "Preferences",
            value: "",
            compactDescription: "Element has no description",
            detailedDescription: "This element is missing useful accessibility information."
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            labeledWindow,
            scenario: .runPreviewReview,
            baselineEntries: []
        ))

        let contrastIssue = A11yAuditFingerprint(
            auditType: "contrast",
            role: "window",
            identifier: "",
            label: "",
            value: "",
            compactDescription: "Contrast failed",
            detailedDescription: "Contrast failed for Setup"
        )
        XCTAssertFalse(Self.isAllowedAccessibilityAuditIssue(
            contrastIssue,
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

            XCTAssertTrue(Self.button(identifier: "startTransferFromPreviewButton", in: app).waitForExistence(timeout: 5))
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

    func testTimelineSelectionUpdatesPreview() async {
        await MainActor.run {
            let app = Self.launchApp(.runPreviewReview)

            let timeline = Self.element(identifier: "InteractiveTimeline", in: app)
            XCTAssertTrue(timeline.waitForExistence(timeout: 5), "Timeline should render in run preview")

            Self.selectTimelineBucket(timeline, atNormalizedX: 0.9)

            let clearButton = Self.button(identifier: "ClearTimelineSelectionButton", in: app)
            XCTAssertTrue(clearButton.waitForExistence(timeout: 5), "Clear Selection button should appear after selecting a bucket")

            // The selection drawer opens below the timeline, which can sit at
            // the bottom of the window; scroll it into view as a user would.
            XCTAssertTrue(
                Self.scrollIntoView(clearButton, in: app),
                "Clear Selection button should be scrollable into view"
            )
            Self.coordinateClick(clearButton)
            XCTAssertFalse(clearButton.exists, "Clear Selection button should disappear after clearing selection")

            app.terminate()
        }
    }

    func testHistoryTimelineSelectionFiltersEntries() async {
        await MainActor.run {
            let app = Self.launchApp(.historyPopulated)

            let timeline = Self.element(identifier: "InteractiveTimeline", in: app)
            XCTAssertTrue(timeline.waitForExistence(timeout: 5), "Timeline should render in run history")

            let clearFilterButton = Self.button(identifier: "ClearTimelineFilterButton", in: app)
            XCTAssertFalse(clearFilterButton.exists, "Clear Timeline Filter button should not be present initially")

            Self.selectTimelineBucket(timeline, atNormalizedX: 0.8)

            XCTAssertTrue(clearFilterButton.waitForExistence(timeout: 5), "Clear Timeline Filter button should appear after selecting a bucket")

            Self.coordinateClick(clearFilterButton)
            XCTAssertFalse(clearFilterButton.exists, "Clear Timeline Filter button should disappear after clearing filter")

            app.terminate()
        }
    }

    func testProfilesScenarioShowsActiveProfileAndUseAction() async {
        await MainActor.run {
            let app = Self.launchApp(.profilesPopulated)

            XCTAssertTrue(app.windows[Self.settingsWindowIdentifier].waitForExistence(timeout: 5))
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

    func testMeteredTrialScenariosExposeLicenseAndWorkspaceIndicators() async {
        await MainActor.run {
            let licenseApp = Self.launchApp(.settingsLicense)
            XCTAssertTrue(Self.element(identifier: "settings.license", in: licenseApp).waitForExistence(timeout: 5))
            XCTAssertTrue(Self.button(identifier: "license.restore", in: licenseApp).waitForExistence(timeout: 5))
            XCTAssertTrue(licenseApp.staticTexts["380 of 500 left"].exists)
            XCTAssertTrue(licenseApp.staticTexts["96 of 100 left"].exists)
            licenseApp.terminate()

            let runApp = Self.launchApp(.runPreviewReview)
            XCTAssertTrue(Self.element(identifier: "trialIndicator.organize", in: runApp).waitForExistence(timeout: 5))
            XCTAssertTrue(runApp.staticTexts["380 of 500 files left"].exists)
            runApp.terminate()

            let dedupeApp = Self.launchApp(.deduplicateReviewWide)
            XCTAssertTrue(Self.element(identifier: "trialIndicator.dedupe", in: dedupeApp).waitForExistence(timeout: 10))
            XCTAssertTrue(dedupeApp.staticTexts["96 of 100 duplicates left"].exists)
            dedupeApp.terminate()
        }
    }

    func testReviewRejectionScreensAvoidKnownOverlapStates() async {
        await MainActor.run {
            let runApp = Self.launchApp(.setupIncompleteRun)
            XCTAssertTrue(runApp.buttons["Return to Setup"].waitForExistence(timeout: 5))
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

    /// Regression guard for the Photos workspace overlapping the titlebar.
    /// Selecting Photos used to lay the whole split view out at roughly 3000pt
    /// tall and centre the overflow, which threw both the sidebar rows and the
    /// workspace header up above the titlebar — the sidebar looked empty and
    /// its rows collided with the traffic-light controls. See the zero
    /// minimums on `PhotosImportView`'s root frame.
    func testPhotosWorkspaceKeepsSidebarAndHeaderBelowTheTitlebar() async {
        await MainActor.run {
            let app = Self.launchApp(.setupReady)
            let photosRow = Self.element(identifier: "sidebarDestination-photos", in: app)
            XCTAssertTrue(photosRow.waitForExistence(timeout: 10))
            photosRow.click()

            let header = app.staticTexts["Import from Photos"]
            XCTAssertTrue(header.waitForExistence(timeout: 10), "Photos workspace did not appear")

            let window = app.windows.firstMatch
            // Clears the traffic-light controls, matching the Organize
            // assertion in testReviewRejectionScreensAvoidKnownOverlapStates.
            let titlebarFloor = window.frame.minY + 72

            for identifier in [
                "sidebarDestination-organize",
                "sidebarDestination-photos",
                "sidebarDestination-deduplicate",
            ] {
                let row = Self.element(identifier: identifier, in: app)
                XCTAssertTrue(row.exists, "\(identifier) disappeared while Photos was selected")
                XCTAssertGreaterThanOrEqual(
                    row.frame.minY,
                    titlebarFloor,
                    "\(identifier) must stay below the titlebar while Photos is selected"
                )
            }

            // Smaller than titlebarFloor above on purpose: the sidebar rows sit
            // behind the traffic-light controls and must clear them by that
            // much, but the detail column (this header) is inset by the
            // toolbar itself, which — once it has something to draw — starts
            // well above the traffic lights. This floor only needs to clear
            // the titlebar's own height, not the full traffic-light band.
            XCTAssertGreaterThanOrEqual(
                header.frame.minY,
                window.frame.minY + 22,
                "The Photos workspace header must stay below the titlebar"
            )
            Self.assertFrame(
                header.frame,
                named: "Photos workspace header",
                isInside: window.frame,
                scenario: Scenario.setupReady.rawValue
            )
            app.terminate()
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
                    Self.assertFrame(
                        element.frame,
                        named: name,
                        isInside: window.frame,
                        scenario: scenario.rawValue,
                        tolerance: 5
                    )
                }
                XCTAssertLessThanOrEqual(
                    acceptCluster.frame.maxY,
                    footer.frame.minY + 1,
                    "Review actions must not overlap the commit footer for \(scenario.rawValue)"
                )

                // BASH-08: the Keep/Delete choice must be reachable in its own
                // region — not drawn over the group list or hidden behind the
                // member strip. Existence alone missed this, since the
                // clipped control stayed in the accessibility tree. The cluster
                // now focused (index 1 in sampleDeduplicateClusters) carries
                // safety warnings, so this also exercises the warning banner:
                // it must not squeeze the scroll view holding Keep/Delete down
                // to nothing at the compact size.
                // Fails loudly if the fixture's warning cluster stops being the
                // focused one, so the banner path can't be skipped silently.
                XCTAssertTrue(
                    app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "These photos may be intentionally different")).firstMatch.exists,
                    "The focused cluster should show its warning banner for \(scenario.rawValue)"
                )
                let decision = Self.element(identifier: "dedupeDecisionControl", in: app)
                let strip = Self.element(identifier: "dedupeMemberStrip", in: app)
                XCTAssertTrue(decision.waitForExistence(timeout: 5), "Keep/Delete should render for \(scenario.rawValue)")
                XCTAssertTrue(strip.exists, "Member strip should render for \(scenario.rawValue)")
                Self.scrollDetailControlIntoView(decision, above: strip, below: clusterList, in: app)
                XCTAssertGreaterThanOrEqual(
                    decision.frame.minY,
                    clusterList.frame.maxY - 1,
                    "Keep/Delete must not overlap the group list for \(scenario.rawValue)"
                )
                XCTAssertLessThanOrEqual(
                    decision.frame.maxY,
                    strip.frame.minY + 1,
                    "Keep/Delete must not be hidden behind the member strip for \(scenario.rawValue)"
                )

                // The free-trial counter must sit clear of the commit actions,
                // not be drawn on top of them.
                let trialCounter = Self.element(identifier: "trialIndicator.dedupe", in: app)
                XCTAssertTrue(trialCounter.waitForExistence(timeout: 5), "Trial counter should render for \(scenario.rawValue)")
                Self.assertFrame(
                    trialCounter.frame,
                    named: "trial counter",
                    isInside: window.frame,
                    scenario: scenario.rawValue,
                    tolerance: 5
                )
                for (name, element) in [("accept all", acceptAll), ("commit", commit)] {
                    XCTAssertFalse(
                        trialCounter.frame.intersects(element.frame),
                        "Trial counter \(trialCounter.frame) must not overlap \(name) \(element.frame) for \(scenario.rawValue)"
                    )
                }

                // The preview region above the member strip must leave room to
                // actually inspect a photo, not a sliver that only scrolls.
                let detail = Self.element(identifier: "dedupeReviewDetail", in: app)
                XCTAssertTrue(detail.exists, "Review detail should render for \(scenario.rawValue)")
                let previewRegionHeight = strip.frame.minY - detail.frame.minY
                XCTAssertGreaterThanOrEqual(
                    previewRegionHeight,
                    160,
                    "Preview region is only \(previewRegionHeight)pt tall for \(scenario.rawValue)"
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
        app.launchEnvironment["TZ"] = "UTC"
        app.launchArguments += ["--chronoframe-ui-test-scenario", scenario.rawValue, "-AppleTimeZone", "UTC", "-TZ", "UTC"]
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
            return app.buttons["Return to Setup"].waitForExistence(timeout: 5)
        case .setupReady:
            return button(identifier: "previewButton", in: app).waitForExistence(timeout: 5)
                && button(identifier: "chooseSourceButton", in: app).waitForExistence(timeout: 5)
                && button(identifier: "chooseDestinationButton", in: app).waitForExistence(timeout: 5)
        case .runPreviewReview:
            return button(identifier: "startTransferFromPreviewButton", in: app).waitForExistence(timeout: 5)
        case .healthDashboard:
            return app.staticTexts["Library Health"].waitForExistence(timeout: 5)
                && button(identifier: "refreshLibraryHealthButton", in: app).waitForExistence(timeout: 5)
        case .watchedSources:
            return app.staticTexts["Watched Folders"].waitForExistence(timeout: 5)
                && button(identifier: "watchedSourcesAddButton", in: app).waitForExistence(timeout: 5)
        case .historyPopulated:
            return button(identifier: "useHistoricalSourceButton", in: app).waitForExistence(timeout: 5)
        case .profilesPopulated:
            return app.windows[settingsWindowIdentifier].waitForExistence(timeout: 5)
                && element(identifier: "profileName-Meridian Travel", in: app).waitForExistence(timeout: 5)
        case .settingsSections, .settingsLayout, .settingsPerformance, .settingsDeduplicate, .settingsLicense, .settingsDiagnostics:
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
        if isSystemOwnedAccessibilityAuditIssue(issue, scenario: scenario) {
            return true
        }

        if isUnlabeledSwiftUILayoutWrapperIssue(issue) {
            return true
        }

        return baselineEntries.contains { entry in
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

    private static func isSystemOwnedAccessibilityAuditIssue(
        _ issue: A11yAuditFingerprint,
        scenario: Scenario
    ) -> Bool {
        if issue.role == "touchBar" || issue.role == "81" || issue.role == "role_81" {
            return true
        }
        if issue.identifier == "InteractiveTimeline",
           issue.compactDescription == "Unknown role" {
            return true
        }
        if isUnidentifiedStaticTextContrastFailure(issue) {
            let target = contrastTarget(for: issue)
            if scenario.opensSettingsOnLaunch, target == "settings" || target == "chronoframe" {
                return true
            }
            if scenario == .deduplicateReviewWide || scenario == .deduplicateReviewCompact || scenario == .historyPopulated,
               target == "chronoframe" {
                return true
            }
            if let expectedToolbarTitle = toolbarTitleFalsePositives[scenario], target == expectedToolbarTitle {
                return true
            }
        }
        return issue.role == "role_14" &&
               issue.label.localizedCaseInsensitiveCompare("emoji & symbols") == .orderedSame &&
               issue.auditType == "sufficientElementDescription"
    }

    /// A contrast-audit failure on an app-rendered label with no accessibility
    /// identifier — the common shape every system-chrome contrast false
    /// positive takes (the Settings/Chronoframe window title, the toolbar
    /// titles). Extracted because these four checks previously repeated
    /// verbatim across three separate bypass rules below.
    private static func isUnidentifiedStaticTextContrastFailure(_ issue: A11yAuditFingerprint) -> Bool {
        issue.auditType == "contrast" &&
            issue.role == "staticText" &&
            issue.identifier.isEmpty &&
            issue.compactDescription == "Contrast failed"
    }

    /// Window toolbar titles the system draws from `.navigationTitle(...)` on
    /// each scenario's primary destination (BASH-06). Matched by *exact*
    /// lowercased target rather than the baseline file's substring matching,
    /// because several of these titles ("Health", "Setup") are single words
    /// that are also substrings of unrelated app-authored text on the same
    /// screen (e.g. healthDashboard's "Library Health" title and "Healthy"
    /// legend) — a substring baseline entry would silently swallow a real
    /// contrast regression on that unrelated text.
    private static let toolbarTitleFalsePositives: [Scenario: String] = [
        .setupIncompleteRun: "run",
        .runPreviewReview: "run",
        .setupReady: "setup",
        .healthDashboard: "health",
        .watchedSources: "organize",
        .historyPopulated: "run history"
    ]

    private static func isUnlabeledSwiftUILayoutWrapperIssue(_ issue: A11yAuditFingerprint) -> Bool {
        // XCTest reports SwiftUI layout scaffolding as Window/Application
        // elements even when the debug line identifies the node as Group/Other.
        // These empty wrappers do not represent app-authored focus stops. Keep
        // this filter narrow so app menus, controls, and all contrast findings
        // still hard-fail.
        guard issue.auditType == "sufficientElementDescription",
              issue.identifier.isEmpty,
              issue.label.isEmpty,
              issue.value.isEmpty,
              issue.compactDescription == "Element has no description" else {
            return false
        }
        if issue.role.isEmpty {
            return true
        }
        return issue.role == "window" || issue.role == "application" || issue.role == "group" || issue.role == "3" || issue.role == "role_3"
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
        return normalizedTextContains(issueLabel, entryLabel)
    }

    private static func valueMatches(_ entryValue: String, _ issueValue: String) -> Bool {
        guard !entryValue.isEmpty else { return true }
        return normalizedTextContains(issueValue, entryValue)
    }

    private static func compactDescriptionMatches(_ entryDescription: String, _ issueDescription: String) -> Bool {
        guard !entryDescription.isEmpty else { return true }
        return normalizedTextContains(issueDescription, entryDescription)
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

    private static func normalizedTextContains(_ issueText: String, _ entryText: String) -> Bool {
        let issueNorm = normalizeDescription(issueText)
        let entryNorm = normalizeDescription(entryText)
        guard !entryNorm.isEmpty else {
            return true
        }
        guard !issueNorm.isEmpty else {
            return false
        }
        return issueNorm.contains(entryNorm) || entryNorm.contains(issueNorm)
    }

    private static func contrastTarget(for issue: A11yAuditFingerprint) -> String {
        for candidate in [issue.value, issue.label, extractContrastTarget(issue.detailedDescription)] where !candidate.isEmpty {
            return candidate.lowercased()
        }
        return ""
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

        result = result
            .replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ")

        let charsToRemove: Set<Character> = [",", ":", ";", ".", "·"]
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
        if app.windows.firstMatch.waitForExistence(timeout: 10) {
            return
        }

        app.typeKey("n", modifierFlags: .command)
        _ = app.windows.firstMatch.waitForExistence(timeout: 10)
    }

    @MainActor
    private static func ensureSettingsWindowExists(in app: XCUIApplication) {
        let settingsWindow = app.windows[settingsWindowIdentifier]
        if settingsWindow.waitForExistence(timeout: 10) {
            return
        }

        app.typeKey(",", modifierFlags: .command)
        _ = settingsWindow.waitForExistence(timeout: 10)
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

    /// Selects the timeline bucket under a point with a click. The timeline's
    /// `DragGesture(minimumDistance: 0)` selects on press, so a click drives
    /// the same selection path as a scrub. XCTest's synthesized
    /// `press(forDuration:thenDragTo:)` never reaches that gesture on
    /// macOS 27 (clicks do, and a real mouse drag selects correctly), so the
    /// tests click rather than drag.
    @MainActor
    private static func selectTimelineBucket(_ timeline: XCUIElement, atNormalizedX x: CGFloat) {
        timeline.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).click()
    }

    /// Scrolls the scroll view containing the button until the button lies
    /// entirely inside the window. `isHittable` is not enough: a button
    /// clipped by the window edge still reports hittable while its centre,
    /// where `coordinateClick` lands, is outside the window.
    @MainActor
    private static func scrollIntoView(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        let window = app.windows.firstMatch
        let scrollView = app.scrollViews.containing(.button, identifier: element.identifier).firstMatch
        func isFullyVisible() -> Bool { window.frame.contains(element.frame) }
        if isFullyVisible() { return true }
        guard scrollView.exists else { return false }

        // Scroll toward the element first: a negative delta reveals content
        // below the fold, a positive delta reveals content above it. Keep
        // scrolling that direction as long as it keeps moving the element
        // (so a correct guess that simply needs more iterations isn't cut
        // off), and only fall back to the other direction once the scroll
        // view stops responding (its frame stops changing), which signals
        // the guess was wrong rather than merely slow.
        let towardDeltaY: CGFloat = element.frame.maxY > window.frame.maxY ? -120 : 120
        for deltaY in [towardDeltaY, -towardDeltaY] {
            var previousFrame = element.frame
            for _ in 0..<20 {
                if isFullyVisible() { return true }
                scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
                let currentFrame = element.frame
                if currentFrame == previousFrame { break }
                previousFrame = currentFrame
            }
        }
        return isFullyVisible()
    }

    /// Scrolls the scroll view holding a review-detail control until the
    /// control sits between the group list and the member strip, as a user
    /// would scroll the detail column. Does nothing if nothing scrolls it.
    @MainActor
    private static func scrollDetailControlIntoView(
        _ control: XCUIElement,
        above strip: XCUIElement,
        below list: XCUIElement,
        in app: XCUIApplication
    ) {
        func isVisible() -> Bool {
            control.frame.minY >= list.frame.maxY - 1 && control.frame.maxY <= strip.frame.minY + 1
        }
        let scrollView = app.scrollViews.containing(.any, identifier: "dedupeDecisionControl").firstMatch
        guard scrollView.exists else { return }
        for deltaY: CGFloat in [-60, 60] {
            for _ in 0..<10 {
                if isVisible() { return }
                scrollView.scroll(byDeltaX: 0, deltaY: deltaY)
            }
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
            return nil
        case .setupReady:
            return "Privacy"
        case .runPreviewReview:
            return nil
        case .healthDashboard:
            return "Library Health"
        case .watchedSources:
            return "Watched Folders"
        case .historyPopulated:
            return nil
        case .profilesPopulated,
             .settingsSections,
             .settingsLayout,
             .settingsPerformance,
             .settingsDeduplicate,
             .settingsLicense,
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
        case .watchedSources:
            return "organizeTab.sources"
        case .historyPopulated:
            return "organizeTab.history"
        case .profilesPopulated,
             .settingsSections,
             .settingsLayout,
             .settingsPerformance,
             .settingsDeduplicate,
             .settingsLicense,
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
        tolerance: CGFloat = 1,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertGreaterThanOrEqual(frame.minX, windowFrame.minX - tolerance, "\(name) should not clip left in \(scenario)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(frame.minY, windowFrame.minY - tolerance, "\(name) should not clip above the window in \(scenario)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxX, windowFrame.maxX + tolerance, "\(name) should not clip right in \(scenario)", file: file, line: line)
        XCTAssertLessThanOrEqual(frame.maxY, windowFrame.maxY + tolerance, "\(name) should not clip below the window in \(scenario)", file: file, line: line)
    }
}
