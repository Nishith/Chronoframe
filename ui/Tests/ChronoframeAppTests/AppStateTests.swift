#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Combine
import Foundation
import XCTest
@testable import ChronoframeApp

final class AppStateTests: XCTestCase {
    @MainActor
    func testUITestScenarioParsesEnvironmentAndMarksSettingsLaunches() {
        XCTAssertEqual(
            UITestScenario.current(environment: ["CHRONOFRAME_UI_TEST_SCENARIO": "historyPopulated"]),
            .historyPopulated
        )
        XCTAssertEqual(
            UITestScenario.current(environment: [:], arguments: ["Chronoframe", "--chronoframe-ui-test-scenario", "setupReady"]),
            .setupReady
        )
        XCTAssertTrue(
            UITestScenario.isRunningScenario(
                environment: [:],
                arguments: ["Chronoframe", "--chronoframe-ui-test-scenario", "setupReady"]
            )
        )
        XCTAssertNil(UITestScenario.current(environment: [:], arguments: []))
        XCTAssertNil(UITestScenario.current(environment: ["CHRONOFRAME_UI_TEST_SCENARIO": "unknown"]))
        XCTAssertTrue(UITestScenario.settingsSections.opensSettingsOnLaunch)
        XCTAssertTrue(UITestScenario.settingsLayout.opensSettingsOnLaunch)
        XCTAssertTrue(UITestScenario.settingsPerformance.opensSettingsOnLaunch)
        XCTAssertTrue(UITestScenario.settingsDeduplicate.opensSettingsOnLaunch)
        XCTAssertTrue(UITestScenario.settingsDiagnostics.opensSettingsOnLaunch)
        XCTAssertTrue(UITestScenario.profilesPopulated.opensSettingsOnLaunch)
        XCTAssertFalse(UITestScenario.setupIncompleteRun.opensSettingsOnLaunch)
        XCTAssertFalse(UITestScenario.setupReady.opensSettingsOnLaunch)
        XCTAssertFalse(UITestScenario.healthDashboard.opensSettingsOnLaunch)
    }

    @MainActor
    func testOpenProfilesSettingsSelectsProfilesTabAndOpensSettingsWindow() {
        let harness = AppStateHarness()
        var settingsOpenCount = 0
        let appState = harness.makeAppState(
            performInitialBootstrap: false,
            showSettingsWindowAction: { settingsOpenCount += 1 }
        )

        XCTAssertEqual(appState.settingsSelection, .general)

        appState.openProfilesSettings()

        XCTAssertEqual(appState.settingsSelection, .profiles)
        XCTAssertEqual(settingsOpenCount, 1)
        XCTAssertEqual(appState.selection, .organize)
    }

    @MainActor
    func testUITestAppStateFactorySeedsHistoryAndProfilesScenarios() {
        let historyState = UITestAppStateFactory.make(scenario: .historyPopulated)

        XCTAssertEqual(historyState.selection, .organize)
        XCTAssertEqual(historyState.organizeSubSelection, .history)
        XCTAssertEqual(historyState.historyStore.destinationRoot, "/Volumes/Archive/Chronoframe Library")
        XCTAssertEqual(historyState.historyStore.entries.map(\.title), ["Dry Run Report", "Transfer Receipt"])
        XCTAssertEqual(historyState.historyStore.transferredSources.count, 1)
        XCTAssertEqual(historyState.historyStore.transferredSources.first?.sourcePath, "/Volumes/Card/April Session")

        let profilesState = UITestAppStateFactory.make(scenario: .profilesPopulated)

        XCTAssertEqual(profilesState.selection, .organize)
        XCTAssertEqual(profilesState.settingsSelection, .profiles)
        XCTAssertTrue(profilesState.setupStore.usingProfile)
        XCTAssertEqual(profilesState.setupStore.selectedProfileName, "Meridian Travel")
        XCTAssertEqual(profilesState.setupStore.newProfileName, "Weekend Archive")
        XCTAssertEqual(profilesState.setupStore.profiles.map(\.name), ["Meridian Travel", "Studio Imports"])

        let incompleteRunState = UITestAppStateFactory.make(scenario: .setupIncompleteRun)

        XCTAssertEqual(incompleteRunState.selection, .organize)
        XCTAssertEqual(incompleteRunState.organizeSubSelection, .run)
        XCTAssertTrue(incompleteRunState.setupStore.sourcePath.isEmpty)
        XCTAssertTrue(incompleteRunState.setupStore.destinationPath.isEmpty)

        let healthState = UITestAppStateFactory.make(scenario: .healthDashboard)

        XCTAssertEqual(healthState.selection, .organize)
        XCTAssertEqual(healthState.organizeSubSelection, .health)
        XCTAssertEqual(healthState.setupStore.destinationPath, "/Volumes/Archive/Chronoframe Library")

        XCTAssertEqual(UITestAppStateFactory.make(scenario: .settingsSections).settingsSelection, .general)
        XCTAssertEqual(UITestAppStateFactory.make(scenario: .settingsLayout).settingsSelection, .layout)
        XCTAssertEqual(UITestAppStateFactory.make(scenario: .settingsPerformance).settingsSelection, .performance)
        XCTAssertEqual(UITestAppStateFactory.make(scenario: .settingsDeduplicate).settingsSelection, .deduplicate)
        XCTAssertEqual(UITestAppStateFactory.make(scenario: .settingsDiagnostics).settingsSelection, .diagnostics)
    }

    @MainActor
    func testUITestAppStateFactoryStartsPreviewForRunScenario() async {
        let appState = UITestAppStateFactory.make(scenario: .runPreviewReview)

        let finished = await waitForCondition(timeoutNanoseconds: 2_000_000_000) {
            appState.runSessionStore.summary?.status == .dryRunFinished
        }

        XCTAssertTrue(finished)
        XCTAssertEqual(appState.selection, .organize)
        XCTAssertEqual(appState.organizeSubSelection, .run)
        XCTAssertEqual(appState.runSessionStore.summary?.metrics.plannedCount, 42)
        XCTAssertEqual(
            appState.runSessionStore.summary?.artifacts.reportPath,
            "/Volumes/Archive/Chronoframe Library/.organize_logs/dry_run_report.csv"
        )
    }

    @MainActor
    func testBootstrapRestoresManualBookmarksAndRefreshesHistory() {
        let harness = AppStateHarness()
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.source", path: "/Volumes/OldCard", data: Data([0x01]))
        )
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.destination", path: "/Volumes/OldArchive", data: Data([0x02]))
        )
        harness.folderAccessService.resolvedBookmarks["manual.source"] = ResolvedFolderBookmark(
            url: URL(fileURLWithPath: "/Volumes/NewCard"),
            refreshedBookmark: FolderBookmark(key: "manual.source", path: "/Volumes/NewCard", data: Data([0x11]))
        )
        harness.folderAccessService.resolvedBookmarks["manual.destination"] = ResolvedFolderBookmark(
            url: URL(fileURLWithPath: "/Volumes/NewArchive"),
            refreshedBookmark: FolderBookmark(key: "manual.destination", path: "/Volumes/NewArchive", data: Data([0x22]))
        )

        let appState = harness.makeAppState()

        XCTAssertEqual(appState.setupStore.sourcePath, "/Volumes/NewCard")
        XCTAssertEqual(appState.setupStore.destinationPath, "/Volumes/NewArchive")
        XCTAssertEqual(appState.preferencesStore.lastManualSourcePath, "/Volumes/NewCard")
        XCTAssertEqual(appState.preferencesStore.lastManualDestinationPath, "/Volumes/NewArchive")
        XCTAssertEqual(appState.preferencesStore.bookmark(for: "manual.source")?.path, "/Volumes/NewCard")
        XCTAssertEqual(appState.preferencesStore.bookmark(for: "manual.destination")?.path, "/Volumes/NewArchive")
        XCTAssertEqual(appState.historyStore.destinationRoot, "/Volumes/NewArchive")
    }

    @MainActor
    func testBootstrapRestoresDeduplicateFolderBookmark() {
        let harness = AppStateHarness()
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "deduplicate.destination", path: "/Volumes/OldDedupe", data: Data([0x03]))
        )
        harness.folderAccessService.resolvedBookmarks["deduplicate.destination"] = ResolvedFolderBookmark(
            url: URL(fileURLWithPath: "/Volumes/NewDedupe"),
            refreshedBookmark: FolderBookmark(key: "deduplicate.destination", path: "/Volumes/NewDedupe", data: Data([0x33]))
        )

        let appState = harness.makeAppState()

        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/NewDedupe")
        XCTAssertEqual(harness.preferencesStore.lastDeduplicateDestinationPath, "/Volumes/NewDedupe")
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "deduplicate.destination")?.path, "/Volumes/NewDedupe")
    }

    @MainActor
    func testDeduplicateFolderPickerStoresIndependentPathAndBookmark() async {
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/Volumes/Organize"
        harness.folderAccessService.nextChosenFolder = URL(fileURLWithPath: "/Volumes/Dedupe")
        let appState = harness.makeAppState(performInitialBootstrap: false)

        await appState.chooseDeduplicateDestinationFolder()

        XCTAssertEqual(harness.setupStore.destinationPath, "/Volumes/Organize")
        XCTAssertEqual(harness.preferencesStore.lastDeduplicateDestinationPath, "/Volumes/Dedupe")
        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/Dedupe")
        XCTAssertEqual(harness.folderAccessService.chooseFolderCalls.count, 1, "Picker must not double-prompt")
        XCTAssertEqual(harness.folderAccessService.chooseFolderCalls.last?.startingAt, "/Volumes/Organize")
        XCTAssertEqual(harness.folderAccessService.chooseFolderCalls.last?.prompt, "Choose Deduplicate Folder")
        XCTAssertEqual(harness.folderAccessService.bookmarkURLs, [URL(fileURLWithPath: "/Volumes/Dedupe")])
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "deduplicate.destination")?.path, "/Volumes/Dedupe")
    }

    /// Regression for review rec #2: bookmark-creation failure used to be
    /// swallowed via `try?`, leaving the path persisted with no bookmark.
    /// The picker must now leave the path unchanged and surface a
    /// transient error so the user knows the folder didn't take.
    @MainActor
    func testChooseDeduplicateDestinationSurfacesBookmarkCreationFailure() async {
        let harness = AppStateHarness()
        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Existing"
        harness.folderAccessService.nextChosenFolder = URL(fileURLWithPath: "/Volumes/NewFolder")
        harness.folderAccessService.bookmarkCreationFailures["deduplicate.destination"] = AppTestFailure.expectedFailure("disk full")
        let appState = harness.makeAppState(performInitialBootstrap: false)

        await appState.chooseDeduplicateDestinationFolder()

        XCTAssertNotNil(appState.transientErrorMessage, "Bookmark failure must surface a transient error")
        XCTAssertEqual(
            harness.preferencesStore.lastDeduplicateDestinationPath,
            "/Volumes/Existing",
            "Path must remain unchanged when the bookmark could not be created"
        )
        XCTAssertNil(harness.preferencesStore.bookmark(for: "deduplicate.destination"))
    }

    /// Regression for review rec #1: when the stored bookmark no longer
    /// resolves (folder deleted, volume unmounted), bootstrap must drop
    /// both the bookmark and the path so future scans fall back to the
    /// Organize destination instead of silently scanning a dead path.
    @MainActor
    func testBootstrapClearsDeduplicateDestinationWhenBookmarkResolutionFails() {
        let harness = AppStateHarness()
        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Gone"
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "deduplicate.destination", path: "/Volumes/Gone", data: Data([0x09]))
        )
        harness.folderAccessService.bookmarkResolutionFailures.insert("deduplicate.destination")

        let appState = harness.makeAppState()

        XCTAssertEqual(harness.preferencesStore.lastDeduplicateDestinationPath, "")
        XCTAssertNil(harness.preferencesStore.bookmark(for: "deduplicate.destination"))
        XCTAssertFalse(appState.hasDedicatedDeduplicateDestinationPath)
    }

    /// Production-realistic version of the above: `FolderAccessService`
    /// returns a fallback URL even when the bookmark data is invalid,
    /// so `resolveBookmark` is non-nil and the prior nil-only guard
    /// would have silently kept the dead path. The new liveness check
    /// hits `validateFolder`, which throws for a missing folder, and
    /// that path must be cleared.
    @MainActor
    func testBootstrapClearsDeduplicateDestinationWhenFolderNoLongerExists() {
        let harness = AppStateHarness()
        let deadPath = "/Volumes/Vanished"
        harness.preferencesStore.lastDeduplicateDestinationPath = deadPath
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "deduplicate.destination", path: deadPath, data: Data([0x11]))
        )
        // Mock matches production: resolveBookmark returns a fallback
        // ResolvedFolderBookmark; only validateFolder reveals the
        // folder is gone.
        harness.folderAccessService.validationFailures[deadPath] = FolderValidationError.pathDoesNotExist(
            role: .destination,
            path: deadPath
        )

        let appState = harness.makeAppState()

        XCTAssertEqual(
            harness.preferencesStore.lastDeduplicateDestinationPath,
            "",
            "Stale path must clear when validateFolder reports the folder is gone"
        )
        XCTAssertNil(harness.preferencesStore.bookmark(for: "deduplicate.destination"))
        XCTAssertFalse(appState.hasDedicatedDeduplicateDestinationPath)
    }

    /// Review rec #4: explicit "Use Organize Destination" affordance
    /// drops the dedicated dedupe folder and reverts to the fallback.
    @MainActor
    func testClearDeduplicateDestinationFolderRevertsToOrganizeFallback() {
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/Volumes/Organize"
        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Dedupe"
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "deduplicate.destination", path: "/Volumes/Dedupe", data: Data([0x10]))
        )
        let appState = harness.makeAppState(performInitialBootstrap: false)

        XCTAssertTrue(appState.hasDedicatedDeduplicateDestinationPath)

        appState.clearDeduplicateDestinationFolder()

        XCTAssertFalse(appState.hasDedicatedDeduplicateDestinationPath)
        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/Organize")
        XCTAssertNil(harness.preferencesStore.bookmark(for: "deduplicate.destination"))
    }

    /// Review rec #14: Reveal in Finder for the dedupe folder.
    @MainActor
    func testRevealDeduplicateDestinationCallsFinderService() {
        let harness = AppStateHarness()
        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Dedupe"
        let appState = harness.makeAppState(performInitialBootstrap: false)

        appState.revealDeduplicateDestinationInFinder()

        XCTAssertEqual(harness.finderService.revealedPaths, ["/Volumes/Dedupe"])
    }

    @MainActor
    func testOpenDeduplicateRunHistoryLoadsDedupeReceipts() async throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DedupeHistory-\(UUID().uuidString)", isDirectory: true)
        let logsDirectory = temporaryDirectory.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let receipt = logsDirectory.appendingPathComponent("dedupe_audit_receipt_20260525_070101_FA24.json")
        try "{}".write(to: receipt, atomically: true, encoding: .utf8)

        let harness = AppStateHarness()
        harness.preferencesStore.lastDeduplicateDestinationPath = temporaryDirectory.path
        let appState = harness.makeAppState(performInitialBootstrap: false)

        await appState.openDeduplicateRunHistory()

        XCTAssertEqual(appState.selection, .organize)
        XCTAssertEqual(appState.organizeSubSelection, .history)
        XCTAssertEqual(harness.historyStore.destinationRoot, temporaryDirectory.path)
        XCTAssertEqual(harness.historyStore.entries.map(\.kind), [.dedupeAuditReceipt])
        XCTAssertEqual(
            harness.historyStore.entries.first.map { URL(fileURLWithPath: $0.path).standardizedFileURL.path },
            receipt.standardizedFileURL.path
        )
    }

    @MainActor
    func testUseDeduplicateHistoryFolderSelectsAvailableFolderAndStoresBookmark() throws {
        let temporaryDirectory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("HistoryFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }

        let harness = AppStateHarness()
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "deduplicate.destination",
            path: "/Volumes/Old",
            data: Data([0x01])
        ))
        let appState = harness.makeAppState(performInitialBootstrap: false)

        appState.useDeduplicateHistoryFolder(DeduplicateFolderHistoryRecord(
            folderPath: temporaryDirectory.path,
            lastRunAt: Date(),
            runCount: 1,
            lastDeletedCount: 2,
            lastFailedCount: 0,
            lastBytesReclaimed: 1_024,
            totalDeletedCount: 2,
            totalFailedCount: 0,
            totalBytesReclaimed: 1_024,
            lastReceiptPath: nil,
            lastHardDelete: false
        ))

        XCTAssertEqual(appState.deduplicateDestinationPath, temporaryDirectory.path)
        XCTAssertEqual(harness.folderAccessService.bookmarkURLs.map(\.path), [temporaryDirectory.path])
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "deduplicate.destination")?.path, temporaryDirectory.path)
        XCTAssertNil(appState.transientErrorMessage)
    }

    @MainActor
    func testUseDeduplicateHistoryFolderPreservesExistingFolderWhenBookmarkCreationFails() {
        let harness = AppStateHarness()
        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/ExistingDedupe"
        harness.folderAccessService.bookmarkCreationFailures["deduplicate.destination"] =
            AppTestFailure.expectedFailure("bookmark denied")
        let appState = harness.makeAppState(performInitialBootstrap: false)

        appState.useDeduplicateHistoryFolder(DeduplicateFolderHistoryRecord(
            folderPath: "/Volumes/HistoryDedupe",
            lastRunAt: Date(),
            runCount: 1,
            lastDeletedCount: 2,
            lastFailedCount: 0,
            lastBytesReclaimed: 1_024,
            totalDeletedCount: 2,
            totalFailedCount: 0,
            totalBytesReclaimed: 1_024,
            lastReceiptPath: nil,
            lastHardDelete: false
        ))

        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/ExistingDedupe")
        XCTAssertEqual(harness.preferencesStore.lastDeduplicateDestinationPath, "/Volumes/ExistingDedupe")
        XCTAssertNil(harness.preferencesStore.bookmark(for: "deduplicate.destination"))
        XCTAssertNotNil(appState.transientErrorMessage)
    }

    @MainActor
    func testUseDeduplicateHistoryFolderReportsMissingFolder() {
        let harness = AppStateHarness()
        let appState = harness.makeAppState(performInitialBootstrap: false)
        let missingPath = "/Volumes/Missing-\(UUID().uuidString)"
        harness.folderAccessService.validationFailures[missingPath] =
            FolderValidationError.pathDoesNotExist(role: .destination, path: missingPath)

        appState.useDeduplicateHistoryFolder(DeduplicateFolderHistoryRecord(
            folderPath: missingPath,
            lastRunAt: Date(),
            runCount: 1,
            lastDeletedCount: 2,
            lastFailedCount: 0,
            lastBytesReclaimed: 1_024,
            totalDeletedCount: 2,
            totalFailedCount: 0,
            totalBytesReclaimed: 1_024,
            lastReceiptPath: nil,
            lastHardDelete: false
        ))

        XCTAssertEqual(
            appState.transientErrorMessage,
            "That Deduplicate folder is no longer available. Choose it again to continue."
        )
    }

    @MainActor
    func testOrganizeRunRejectedWhileDeduplicateWorking() async {
        // Finding #7: organize and deduplicate touch the same destination and
        // must not run concurrently.
        let harness = AppStateHarness()
        harness.setupStore.sourcePath = "/tmp/source"
        harness.setupStore.destinationPath = "/Volumes/Organize"
        harness.deduplicateEngine.holdScanOpen = true
        let appState = harness.makeAppState(performInitialBootstrap: false)

        appState.startDeduplicateScan()
        let working = await waitForCondition { harness.deduplicateSessionStore.isWorking }
        XCTAssertTrue(working)

        await appState.startPreview()

        XCTAssertEqual(harness.engine.startConfigurations.count, 0, "Organize must not start while dedupe is working")
        XCTAssertNotNil(appState.transientErrorMessage)

        harness.deduplicateEngine.finishHeldScan()
    }

    @MainActor
    func testDeduplicateScanRejectedWhileOrganizeRunning() async {
        let harness = AppStateHarness()
        harness.setupStore.sourcePath = "/tmp/source"
        harness.setupStore.destinationPath = "/Volumes/Organize"
        harness.engine.startMode = .pending
        let appState = harness.makeAppState(performInitialBootstrap: false)

        await appState.startPreview()
        let running = await waitForCondition { appState.runSessionStore.isRunning }
        XCTAssertTrue(running)

        appState.startDeduplicateScan()

        XCTAssertNil(harness.deduplicateEngine.lastScanConfiguration, "Dedupe must not scan while an organize run is active")
        XCTAssertNotNil(appState.transientErrorMessage)

        appState.cancelRun()
    }

    @MainActor
    func testDeduplicateScanUsesDedicatedFolderWhenSetAndFallsBackOtherwise() {
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/Volumes/Organize"
        let appState = harness.makeAppState(performInitialBootstrap: false)

        appState.startDeduplicateScan()
        XCTAssertEqual(harness.deduplicateEngine.lastScanConfiguration?.destinationPath, "/Volumes/Organize")

        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Dedupe"
        appState.startDeduplicateScan()

        XCTAssertEqual(harness.deduplicateEngine.lastScanConfiguration?.destinationPath, "/Volumes/Dedupe")
    }

    // MARK: - Deduplicate "Scan Folder" card display contract
    //
    // The Deduplicate Scan Folder card shows `deduplicateDestinationPath` and
    // `deduplicateDestinationHelper`, both resolved from three stores in a
    // fallback chain: preferencesStore (dedicated dedupe folder) → setupStore
    // (Organize destination) → historyStore (last organized root). A reactivity
    // bug shipped where the card observed only `appState` and never re-rendered
    // when those stores changed — the resolved value was correct, but stale on
    // screen. These tests pin the two halves the fix depends on: the resolved
    // value/helper tracks every fallback transition, and each source property
    // stays observable so a view bound to it re-renders.
    //
    // That the card itself observes all three stores is not unit-testable here
    // without a SwiftUI view-inspection harness — the check_app_layer_changes
    // guard and code review cover the wiring.

    @MainActor
    func testDeduplicateDestinationPathFollowsFullFallbackChain() {
        let harness = AppStateHarness()
        let appState = harness.makeAppState(performInitialBootstrap: false)

        // Only the last organized root is known.
        harness.historyStore.setDestinationRoot("/Volumes/History")
        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/History")

        // The Organize destination outranks history.
        harness.setupStore.destinationPath = "/Volumes/Organize"
        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/Organize")

        // A dedicated dedupe folder outranks everything.
        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Dedupe"
        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/Dedupe")

        // Clearing the dedicated folder falls back to the Organize destination.
        harness.preferencesStore.lastDeduplicateDestinationPath = ""
        XCTAssertEqual(appState.deduplicateDestinationPath, "/Volumes/Organize")
    }

    @MainActor
    func testDeduplicateDestinationHelperReflectsEachState() {
        let harness = AppStateHarness()
        let appState = harness.makeAppState(performInitialBootstrap: false)

        // Nothing set anywhere.
        XCTAssertTrue(appState.deduplicateDestinationPath.isEmpty)
        XCTAssertEqual(
            appState.deduplicateDestinationHelper,
            "Choose the folder to scan for duplicate photos."
        )

        // Falling back to the Organize destination.
        harness.setupStore.destinationPath = "/Volumes/Organize"
        XCTAssertFalse(appState.hasDedicatedDeduplicateDestinationPath)
        XCTAssertEqual(
            appState.deduplicateDestinationHelper,
            "Using the Organize destination until you choose a Deduplicate folder."
        )

        // A dedicated dedupe folder is set.
        harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Dedupe"
        XCTAssertTrue(appState.hasDedicatedDeduplicateDestinationPath)
        XCTAssertEqual(
            appState.deduplicateDestinationHelper,
            "Only this folder is scanned for duplicates."
        )
    }

    @MainActor
    func testDeduplicateDestinationSourcesStayObservable() {
        let harness = AppStateHarness()
        _ = harness.makeAppState(performInitialBootstrap: false)

        // The card observes these three stores so it re-renders when the
        // resolved Scan Folder path changes. If any property stops being
        // @Published, a correctly-wired view goes stale — the reactivity
        // regression this guards against.
        assertEmitsObjectWillChange(harness.preferencesStore) {
            harness.preferencesStore.lastDeduplicateDestinationPath = "/Volumes/Dedupe"
        }
        assertEmitsObjectWillChange(harness.setupStore) {
            harness.setupStore.destinationPath = "/Volumes/Organize"
        }
        assertEmitsObjectWillChange(harness.historyStore) {
            harness.historyStore.setDestinationRoot("/Volumes/History")
        }
    }

    private func assertEmitsObjectWillChange<T: ObservableObject>(
        _ object: T,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ mutate: () -> Void
    ) where T.ObjectWillChangePublisher == ObservableObjectPublisher {
        var emitted = false
        let cancellable = object.objectWillChange.sink { _ in emitted = true }
        mutate()
        cancellable.cancel()
        XCTAssertTrue(emitted, "Expected objectWillChange to fire after mutation", file: file, line: line)
    }

    /// AGENTS-INVARIANT: 6
    /// The prominent Deduplicate "Move to Trash" button must commit only the
    /// clusters the user has actually reviewed/approved. Scan completion
    /// preselects a Delete decision for every cluster's non-keeper (including
    /// low/medium-confidence, dHash-only weak matches) so the per-cluster UI
    /// can preview them — but those weak preselects must stay review-only
    /// until explicitly confirmed. Regression: the primary commit used to
    /// route through the full-plan commit path, trashing unreviewed weak
    /// matches and deleting more files than the confirmation dialog (which
    /// shows the reviewed count) stated.
    @MainActor
    func testPrimaryDeduplicateCommitOnlyTrashesReviewedClusters() async throws {
        let harness = AppStateHarness()
        harness.setupStore.destinationPath = "/dest"

        let highCluster = DuplicateCluster(
            kind: .exactDuplicate,
            members: [
                PhotoCandidate(path: "/dest/high-keep.jpg", size: 100, modificationTime: 0, qualityScore: 0.9),
                PhotoCandidate(path: "/dest/high-delete.jpg", size: 100, modificationTime: 0, qualityScore: 0.4),
            ],
            suggestedKeeperIDs: ["/dest/high-keep.jpg"],
            bytesIfPruned: 100,
            annotation: ClusterAnnotation(confidence: .high, matchReason: MatchReason(kind: .exactDuplicate))
        )
        let weakCluster = DuplicateCluster(
            kind: .nearDuplicate,
            members: [
                PhotoCandidate(path: "/dest/weak-keep.jpg", size: 100, modificationTime: 0, qualityScore: 0.9),
                PhotoCandidate(path: "/dest/weak-delete.jpg", size: 100, modificationTime: 0, qualityScore: 0.4),
            ],
            suggestedKeeperIDs: ["/dest/weak-keep.jpg"],
            bytesIfPruned: 100,
            annotation: ClusterAnnotation(confidence: .medium, matchReason: MatchReason(kind: .nearDuplicate))
        )
        harness.deduplicateEngine.clustersToEmit = [highCluster, weakCluster]
        harness.deduplicateEngine.commitEvents = [
            .started(totalToDelete: 1),
            .complete(DeduplicateCommitSummary(
                deletedCount: 1, failedCount: 0, bytesReclaimed: 100,
                receiptPath: nil, hardDelete: false
            )),
        ]

        let appState = harness.makeAppState(performInitialBootstrap: false)
        appState.startDeduplicateScan()
        let scanned = await waitForCondition { harness.deduplicateSessionStore.status == .readyToReview }
        XCTAssertTrue(scanned)

        // User approves only the high-confidence cluster; the weak cluster is
        // left unreviewed (its non-keeper sits at a scan-time Delete preselect).
        harness.deduplicateSessionStore.acceptAllHighConfidence()
        XCTAssertTrue(harness.deduplicateSessionStore.approvedClusterIDs.contains(highCluster.id))
        XCTAssertFalse(harness.deduplicateSessionStore.approvedClusterIDs.contains(weakCluster.id))

        appState.commitDeduplicateDecisions()
        let committed = await waitForCondition { harness.deduplicateSessionStore.status == .completed }
        XCTAssertTrue(committed)

        // The executor must only ever see the reviewed cluster.
        let committedPlan = try XCTUnwrap(harness.deduplicateEngine.lastCommitPlan)
        let committedClusterIDs = Set(committedPlan.items.map(\.owningClusterID))
        XCTAssertEqual(committedClusterIDs, [highCluster.id],
            "Primary commit must scope the executor to reviewed clusters only.")

        let pathsToDelete = Set(committedPlan.pathsToDelete)
        XCTAssertTrue(pathsToDelete.contains("/dest/high-delete.jpg"),
            "Reviewed high-confidence non-keeper should be trashed.")
        XCTAssertFalse(pathsToDelete.contains("/dest/weak-delete.jpg"),
            "Unreviewed weak-match non-keeper must NOT be trashed.")
    }

    @MainActor
    func testFacadeForwardsPreviewAndTransferFlows() async {
        let harness = AppStateHarness()
        harness.setupStore.sourcePath = "/tmp/source"
        harness.setupStore.destinationPath = "/tmp/destination"
        harness.engine.startMode = .events([
            .complete(
                RunSummary(
                    status: .dryRunFinished,
                    title: "Preview complete",
                    metrics: RunMetrics(plannedCount: 1),
                    artifacts: RunArtifactPaths(
                        destinationRoot: "/tmp/destination",
                        reportPath: "/tmp/destination/.organize_logs/dry_run_report.csv",
                        logFilePath: "/tmp/destination/.organize_log.txt",
                        logsDirectoryPath: "/tmp/destination/.organize_logs"
                    )
                )
            )
        ])
        let appState = harness.makeAppState()
        appState.setupStore.sourcePath = "/tmp/source"
        appState.setupStore.destinationPath = "/tmp/destination"

        await appState.startPreview()
        let finished = await waitForCondition { appState.runSessionStore.summary != nil }

        XCTAssertTrue(finished)
        XCTAssertEqual(appState.selection, .organize)
        XCTAssertEqual(appState.organizeSubSelection, .run)
        XCTAssertEqual(harness.engine.startConfigurations.count, 1)
        harness.engine.preflightResult = .success(
            RunPreflight(
                configuration: RunConfiguration(mode: .transfer, sourcePath: "/tmp/source", destinationPath: "/tmp/destination"),
                resolvedSourcePath: "/tmp/source",
                resolvedDestinationPath: "/tmp/destination",
                pendingJobCount: 2
            )
        )
        harness.engine.resumeMode = .events([
            .complete(
                RunSummary(
                    status: .finished,
                    title: "Transfer complete",
                    metrics: RunMetrics(copiedCount: 3),
                    artifacts: RunArtifactPaths(destinationRoot: "/tmp/destination")
                )
            )
        ])

        await appState.startTransfer()

        XCTAssertEqual(appState.selection, .organize)
        XCTAssertEqual(appState.organizeSubSelection, .run)
        XCTAssertEqual(appState.runSessionStore.prompt?.kind, .resumePendingJobs)

        appState.confirmRunPrompt()
        let transferFinished = await waitForCondition { appState.runSessionStore.summary?.status == .finished }

        XCTAssertTrue(transferFinished)
        XCTAssertEqual(harness.engine.resumeConfigurations.count, 1)
    }

    @MainActor
    func testFacadeRoutesProfileAndHistoryActionsAcrossCollaborators() async {
        let harness = AppStateHarness()
        harness.repository.profiles = [
            Profile(name: "travel", sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")
        ]
        harness.preferencesStore.storeBookmark(FolderBookmark(key: "manual.source", path: "/Volumes/Card", data: Data([0x01])))
        harness.preferencesStore.storeBookmark(FolderBookmark(key: "manual.destination", path: "/Volumes/Trips", data: Data([0x02])))
        let appState = harness.makeAppState()

        appState.refreshProfiles()
        appState.useProfile(named: "travel")
        appState.setupStore.newProfileName = "archive"
        appState.saveCurrentPathsAsProfile()

        let record = TransferredSourceRecord(
            sourcePath: "/Volumes/Card",
            firstTransferredAt: Date(),
            lastTransferredAt: Date(),
            runCount: 1,
            lastCopiedCount: 10,
            totalCopiedCount: 10
        )
        appState.useHistoricalSource(record)

        XCTAssertEqual(appState.selection, .organize)
        XCTAssertEqual(appState.organizeSubSelection, .setup)
        XCTAssertEqual(appState.setupStore.selectedProfileName, "")
        XCTAssertEqual(appState.setupStore.sourcePath, "/Volumes/Card")
        XCTAssertEqual(harness.repository.savedProfiles.last?.name, "archive")
    }
}
