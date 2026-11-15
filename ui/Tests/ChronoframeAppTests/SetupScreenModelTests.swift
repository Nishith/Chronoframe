#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import XCTest
@testable import ChronoframeApp

final class SetupScreenModelTests: XCTestCase {
    private var temporaryRoots: [URL] = []
    private var suiteNames: [String] = []

    override func tearDown() {
        for root in temporaryRoots {
            try? FileManager.default.removeItem(at: root)
        }
        temporaryRoots.removeAll()
        for name in suiteNames {
            UserDefaults().removePersistentDomain(forName: name)
        }
        suiteNames.removeAll()
        super.tearDown()
    }

    private func makeTemporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SetupScreenModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        temporaryRoots.append(root)
        return root
    }

    @MainActor
    private func makePreferences() -> PreferencesStore {
        let name = "SetupScreenModelTests-\(UUID().uuidString)"
        suiteNames.append(name)
        return PreferencesStore(defaults: UserDefaults(suiteName: name)!)
    }

    private func row(_ path: String, isFolder: Bool = true) -> SetupSourceItemRow {
        SetupSourceItemRow(
            id: path,
            name: URL(fileURLWithPath: path).lastPathComponent,
            parent: URL(fileURLWithPath: path).deletingLastPathComponent().path,
            isFolder: isFolder
        )
    }

    private func context(
        sourcePath: String = "",
        destinationPath: String = "",
        profile: Profile? = nil,
        dropped: Bool = false,
        rows: [SetupSourceItemRow] = [],
        verify: Bool = true,
        running: Bool = false
    ) -> SetupScreenContext {
        SetupScreenContext(
            sourcePath: sourcePath,
            destinationPath: destinationPath,
            selectedProfileName: profile?.name ?? "",
            activeProfile: profile,
            usingDroppedSource: dropped,
            droppedSourceLabel: dropped ? "2 items" : nil,
            droppedSourceItemCount: dropped ? 2 : 0,
            verifyCopies: verify,
            isRunInProgress: running,
            sourceItems: rows
        )
    }

    // MARK: - WP-05 / C-06

    @MainActor
    func testRowsComeFromSourceItems() throws {
        let root = try makeTemporaryRoot()
        let folderA = root.appendingPathComponent("Camera", isDirectory: true)
        let folderB = root.appendingPathComponent("Phone", isDirectory: true)
        let file = root.appendingPathComponent("IMG_0001.jpg")
        try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
        try Data([0x01]).write(to: file)

        let store = SetupStore()
        store.setSourceItems([folderA, folderB, file])
        let model = SetupScreenModel(setupStore: store, preferencesStore: makePreferences(), isRunInProgress: false)

        let rows = model.context.sourceItems
        XCTAssertEqual(rows.map(\.id), [folderA.path, folderB.path, file.path])
        XCTAssertEqual(rows.map(\.name), ["Camera", "Phone", "IMG_0001.jpg"])
        XCTAssertEqual(rows.map(\.isFolder), [true, true, false])
        let expectedParent = (root.path as NSString).abbreviatingWithTildeInPath
        XCTAssertEqual(rows.map(\.parent), [expectedParent, expectedParent, expectedParent])
    }

    @MainActor
    func testSinglePlainSourcePathYieldsOneRowWithoutItems() {
        let store = SetupStore(sourcePath: "/Volumes/Card/DCIM")
        let model = SetupScreenModel(setupStore: store, preferencesStore: makePreferences(), isRunInProgress: false)

        XCTAssertEqual(model.context.sourceItems.count, 1)
        XCTAssertEqual(model.context.sourceItems.first?.id, "/Volumes/Card/DCIM")
        XCTAssertEqual(model.context.sourceItems.first?.name, "DCIM")
        XCTAssertEqual(model.context.sourceItems.first?.parent, "/Volumes/Card")
        XCTAssertEqual(model.context.sourceItems.first?.isFolder, true)
    }

    @MainActor
    func testStagingPathAloneYieldsNoRow() {
        let stagingPath = DroppedItemStager.stagingRoot
            .appendingPathComponent(UUID().uuidString, isDirectory: true).path
        let store = SetupStore(sourcePath: stagingPath)
        let model = SetupScreenModel(setupStore: store, preferencesStore: makePreferences(), isRunInProgress: false)

        XCTAssertTrue(model.context.sourceItems.isEmpty)
    }

    func testHeroBadgeTitlesMatchContract() {
        let profile = Profile(name: "Travel", sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips", profile: profile)).heroBadgeTitle,
            "Profile ready"
        )
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")).heroBadgeTitle,
            "Ready to preview"
        )
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card")).heroBadgeTitle,
            "One more step"
        )
        XCTAssertEqual(SetupScreenModel(context: context()).heroBadgeTitle, "Start here")
    }

    func testNextStepSummariesMatchContract() {
        XCTAssertEqual(SetupScreenModel(context: context()).nextStepSummary, "Add the folders to organize")
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card")).nextStepSummary,
            "Choose where the copies go"
        )
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")).nextStepSummary,
            "Preview the plan"
        )
    }

    func testStepStatesHaveNoBadgeTextWhenReady() {
        let ready = SetupScreenModel(context: context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips"))
        XCTAssertEqual(ready.sourceStepState, .ready("", .success))
        XCTAssertEqual(ready.destinationStepState, .ready("", .success))

        let empty = SetupScreenModel(context: context())
        XCTAssertEqual(empty.sourceStepState, .needed("Add a folder", .warning))
        XCTAssertEqual(empty.destinationStepState, .needed("Choose a destination", .warning))

        let dropped = SetupScreenModel(context: context(dropped: true))
        XCTAssertEqual(dropped.sourceStepState, .ready("", .success))
    }

    func testSourceSummaryValueCountsFolders() {
        XCTAssertEqual(SetupScreenModel(context: context()).sourceSummaryValue, "Needed")
        XCTAssertEqual(
            SetupScreenModel(context: context(rows: [row("/a/One")])).sourceSummaryValue,
            "Ready"
        )
        XCTAssertEqual(
            SetupScreenModel(context: context(rows: [row("/a/One"), row("/a/Two"), row("/a/Three")])).sourceSummaryValue,
            SourceItemList.summaryLabel(count: 3)
        )
        XCTAssertEqual(
            SetupScreenModel(context: context(rows: [row("/a/One"), row("/a/Two")])).sourceSummaryValue,
            "2 folders"
        )

        let profile = Profile(name: "Travel", sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card", profile: profile, rows: [row("/Volumes/Card")])).sourceSummaryValue,
            "/Volumes/Card"
        )
    }

    func testHelpersForOneAndSeveralFolders() {
        XCTAssertEqual(SetupScreenModel(context: context()).sourcePathHelper, "")
        XCTAssertEqual(
            SetupScreenModel(context: context(rows: [row("/a/One")])).sourcePathHelper,
            "Chronoframe reads this folder and never changes what is in it."
        )
        XCTAssertEqual(
            SetupScreenModel(context: context(rows: [row("/a/One"), row("/a/Two"), row("/a/Three")])).sourcePathHelper,
            "Chronoframe reads these 3 folders together and never changes what is in them."
        )
        XCTAssertEqual(
            SetupScreenModel(context: context()).destinationPathHelper,
            "Chronoframe creates dated folders here and keeps a receipt of each copy so you can undo it from History."
        )
    }

    func testReadinessMessagesMatchContract() {
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")).readinessMessage,
            "A preview copies nothing. It shows where every file would go, and you decide after that."
        )
        XCTAssertEqual(
            SetupScreenModel(context: context(sourcePath: "/Volumes/Card")).readinessMessage,
            "Add a folder and choose a destination to see a preview."
        )
    }

    func testPrimaryActionTitles() {
        XCTAssertEqual(SetupPrimaryAction.chooseSource.title, "Add Folders")
        XCTAssertEqual(SetupPrimaryAction.chooseDestination.title, "Choose Destination")
        XCTAssertEqual(SetupPrimaryAction.preview.title, "Preview Plan")
    }

    func testModeAndConfigurationSummariesUseFolderWording() {
        let model = SetupScreenModel(context: context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips"))
        XCTAssertEqual(model.modeSummaryValue, "Folders you chose")
        XCTAssertEqual(model.configurationSummary, "Folders you chose")
        let dropped = SetupScreenModel(context: context(sourcePath: "/Volumes/Card", dropped: true))
        XCTAssertEqual(dropped.modeSummaryValue, "Folders you chose")
        XCTAssertEqual(dropped.configurationSummary, "Folders you chose")
    }

    func testNoUserVisibleSetupStringContainsBannedWord() {
        let profile = Profile(name: "Travel", sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")
        let contexts: [SetupScreenContext] = [
            context(),
            context(sourcePath: "/Volumes/Card"),
            context(destinationPath: "/Volumes/Trips"),
            context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips"),
            context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips", rows: [row("/Volumes/Card")]),
            context(
                sourcePath: "/Volumes/Card",
                destinationPath: "/Volumes/Trips",
                rows: [row("/a/One"), row("/a/Two"), row("/a/Three")]
            ),
            context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips", profile: profile),
            context(sourcePath: "/Volumes/Card", dropped: true, rows: [row("/a/One"), row("/a/Two")]),
            context(sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips", verify: false, running: true),
        ]
        let banned = ["source", "transfer", "mutat", "artifact", "non-destructive", "manual"]

        for context in contexts {
            let model = SetupScreenModel(context: context)
            var strings: [String] = [
                model.heroBadgeTitle,
                model.nextStepSummary,
                model.sourceStepState.title,
                model.destinationStepState.title,
                model.destinationSummaryValue,
                model.modeSummaryValue,
                model.configurationSummary,
                model.safetySummary,
                model.readinessMessage,
                model.sourcePathHelper,
                model.destinationPathHelper,
                model.savedSetupBadgeTitle,
                model.primaryAction.title,
            ]
            if context.activeProfile == nil {
                // With a profile the summary is the profile's own path.
                strings.append(model.sourceSummaryValue)
            }
            for action in [SetupPrimaryAction.chooseSource, .chooseDestination, .preview] {
                strings.append(action.title)
            }
            for string in strings {
                for word in banned {
                    XCTAssertFalse(
                        string.localizedCaseInsensitiveContains(word),
                        "\"\(string)\" contains banned word \"\(word)\""
                    )
                }
            }
        }
    }

    // MARK: - Existing behavior
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
        XCTAssertEqual(model.heroBadgeTitle, "Start here")
        XCTAssertEqual(
            model.readinessMessage,
            "Add a folder and choose a destination to see a preview."
        )
        XCTAssertEqual(model.nextStepSummary, "Add the folders to organize")
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
        XCTAssertEqual(model.heroBadgeTitle, "Profile ready")
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

    /// Profiles are earned complexity: the saved-setup section stays hidden
    /// for a first-time user (no profiles, nothing selected) and appears once
    /// any profile exists or one is active/selected.
    func testSavedSetupSectionVisibilityIsEarned() {
        func context(
            profileCount: Int = 0,
            selectedProfileName: String = "",
            activeProfile: Profile? = nil
        ) -> SetupScreenContext {
            SetupScreenContext(
                sourcePath: "/Volumes/Card",
                destinationPath: "/Volumes/Archive",
                selectedProfileName: selectedProfileName,
                activeProfile: activeProfile,
                availableProfileCount: profileCount
            )
        }

        XCTAssertFalse(SetupScreenModel(context: context()).showsSavedSetupSection)
        XCTAssertTrue(SetupScreenModel(context: context(profileCount: 1)).showsSavedSetupSection)
        XCTAssertTrue(
            SetupScreenModel(context: context(selectedProfileName: "Travel")).showsSavedSetupSection
        )
        XCTAssertTrue(
            SetupScreenModel(
                context: context(
                    activeProfile: Profile(name: "Travel", sourcePath: "/a", destinationPath: "/b")
                )
            ).showsSavedSetupSection
        )
    }
}
