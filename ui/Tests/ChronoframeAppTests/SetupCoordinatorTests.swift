#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

final class SetupCoordinatorTests: XCTestCase {
    @MainActor
    func testChooseFoldersUpdatesManualPathsBookmarksAndHistory() async throws {
        // The picker now feeds the folder list, which checks that each folder
        // exists, so this uses real temporary folders.
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let sourceURL = try fixture.makeFolder("Card")
        let destinationURL = URL(fileURLWithPath: "/Volumes/Archive")
        let harness = fixture.harness

        harness.folderAccessService.nextChosenFolders = [sourceURL]
        await fixture.coordinator.chooseSourceFolder()

        XCTAssertNil(fixture.errors.last)
        XCTAssertEqual(harness.setupStore.sourcePath, sourceURL.path)
        XCTAssertEqual(harness.preferencesStore.lastManualSourcePath, sourceURL.path)
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "manual.source")?.path, sourceURL.path)

        harness.folderAccessService.nextChosenFolder = destinationURL
        await fixture.coordinator.chooseDestinationFolder()

        XCTAssertEqual(harness.setupStore.destinationPath, destinationURL.path)
        XCTAssertEqual(harness.preferencesStore.lastManualDestinationPath, destinationURL.path)
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "manual.destination")?.path, destinationURL.path)
        XCTAssertEqual(harness.historyStore.destinationRoot, destinationURL.path)
    }

    @MainActor
    func testChooseFolderValidationFailureSurfacesErrorWithoutChangingState() async {
        let sourceURL = URL(fileURLWithPath: "/Volumes/Locked")
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        harness.folderAccessService.nextChosenFolders = [sourceURL]
        harness.folderAccessService.validationFailures[sourceURL.path] = FolderValidationError.unreadable(
            role: .source,
            path: sourceURL.path
        )
        var transientError: String?
        let coordinator = SetupCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            folderAccessService: harness.folderAccessService,
            profilesRepository: harness.repository,
            droppedItemStager: DroppedItemStager(),
            bookmarkPathResolver: resolver,
            navigate: { _ in },
            setTransientErrorMessage: { transientError = $0 }
        )

        await coordinator.chooseSourceFolder()

        XCTAssertEqual(
            transientError,
            "Chronoframe cannot read the source folder. Choose it again to grant access, or pick a folder you have permission to open. Path: /Volumes/Locked."
        )
        XCTAssertEqual(harness.setupStore.sourcePath, "")
        XCTAssertNil(harness.preferencesStore.bookmark(for: "manual.source"))
    }

    @MainActor
    func testProfileLifecyclePreservesBookmarksAndSelection() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        var route: AppRoute?
        let coordinator = SetupCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            folderAccessService: harness.folderAccessService,
            profilesRepository: harness.repository,
            droppedItemStager: DroppedItemStager(),
            bookmarkPathResolver: resolver,
            navigate: { route = $0 },
            setTransientErrorMessage: { _ in }
        )

        harness.repository.profiles = [
            Profile(name: "travel", sourcePath: "/Volumes/Card", destinationPath: "/Volumes/Trips")
        ]
        harness.preferencesStore.storeBookmark(FolderBookmark(key: "manual.source", path: "/Volumes/Card", data: Data([0x01])))
        harness.preferencesStore.storeBookmark(FolderBookmark(key: "manual.destination", path: "/Volumes/Trips", data: Data([0x02])))

        coordinator.refreshProfiles()
        coordinator.useProfile(named: "travel")

        XCTAssertEqual(harness.setupStore.selectedProfileName, "travel")
        XCTAssertEqual(harness.historyStore.destinationRoot, "/Volumes/Trips")

        harness.setupStore.newProfileName = "archive"
        coordinator.saveCurrentPathsAsProfile()

        XCTAssertNil(route)
        XCTAssertEqual(harness.repository.savedProfiles.last?.name, "archive")
        XCTAssertEqual(harness.setupStore.selectedProfileName, "archive")
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "profile.archive.source")?.path, "/Volumes/Card")
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "profile.archive.destination")?.path, "/Volumes/Trips")

        coordinator.deleteProfile(named: "travel")
        XCTAssertEqual(harness.repository.deletedProfileNames, ["travel"])
    }

    @MainActor
    func testUseAndClearProfileRestoreBookmarkedPathsAndHistory() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        let coordinator = SetupCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            folderAccessService: harness.folderAccessService,
            profilesRepository: harness.repository,
            droppedItemStager: DroppedItemStager(),
            bookmarkPathResolver: resolver,
            navigate: { _ in },
            setTransientErrorMessage: { _ in }
        )

        harness.repository.profiles = [
            Profile(name: "travel", sourcePath: "/Volumes/YAML-Card", destinationPath: "/Volumes/YAML-Trips")
        ]
        harness.preferencesStore.lastManualSourcePath = "/Volumes/ManualCard"
        harness.preferencesStore.lastManualDestinationPath = "/Volumes/ManualArchive"
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "profile.travel.source", path: "/Volumes/Bookmark-Card", data: Data([0x03]))
        )
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "profile.travel.destination", path: "/Volumes/Bookmark-Trips", data: Data([0x04]))
        )
        harness.folderAccessService.resolvedBookmarks["profile.travel.source"] = ResolvedFolderBookmark(
            url: URL(fileURLWithPath: "/Volumes/Resolved-Card")
        )
        harness.folderAccessService.resolvedBookmarks["profile.travel.destination"] = ResolvedFolderBookmark(
            url: URL(fileURLWithPath: "/Volumes/Resolved-Trips"),
            refreshedBookmark: FolderBookmark(key: "profile.travel.destination", path: "/Volumes/Resolved-Trips", data: Data([0x44]))
        )

        coordinator.refreshProfiles()
        coordinator.useProfile(named: "travel")

        XCTAssertEqual(harness.setupStore.sourcePath, "/Volumes/Resolved-Card")
        XCTAssertEqual(harness.setupStore.destinationPath, "/Volumes/Resolved-Trips")
        XCTAssertEqual(harness.historyStore.destinationRoot, "/Volumes/Resolved-Trips")

        coordinator.clearSelectedProfile()

        XCTAssertEqual(harness.setupStore.selectedProfileName, "")
        XCTAssertEqual(harness.historyStore.destinationRoot, "/Volumes/ManualArchive")
        XCTAssertEqual(harness.preferencesStore.lastSelectedProfileName, "")
    }

    @MainActor
    func testSaveCurrentPathsAsProfileValidatesInputs() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        var transientError: String?
        let coordinator = SetupCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            folderAccessService: harness.folderAccessService,
            profilesRepository: harness.repository,
            droppedItemStager: DroppedItemStager(),
            bookmarkPathResolver: resolver,
            navigate: { _ in },
            setTransientErrorMessage: { transientError = $0 }
        )

        coordinator.saveCurrentPathsAsProfile()
        XCTAssertEqual(transientError, "Enter a profile name before saving.")

        transientError = nil
        harness.setupStore.newProfileName = "travel"
        coordinator.saveCurrentPathsAsProfile()
        XCTAssertEqual(transientError, "Choose both a source and destination before saving a profile.")
    }

    // MARK: - Folder list (CLP WP-04)

    @MainActor
    func testAddOneFolderBehavesLikeSelectSource() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let folder = try fixture.makeFolder("Alpha")
        let setup = fixture.harness.setupStore
        let preferences = fixture.harness.preferencesStore

        await fixture.coordinator.addSourceItems([folder])

        XCTAssertNil(fixture.errors.last)
        XCTAssertEqual(setup.sourcePath, folder.path)
        XCTAssertEqual(setup.sourceURL, folder)
        XCTAssertFalse(setup.usingDroppedSource)
        XCTAssertEqual(setup.sourceItems, [folder])
        XCTAssertEqual(preferences.lastManualSourcePath, folder.path)
        XCTAssertEqual(preferences.bookmark(for: "manual.source")?.path, folder.path)
        XCTAssertEqual(preferences.manualSourceItemPaths, [folder.path])
        XCTAssertTrue(preferences.bookmarkKeys(withPrefix: "manual.sourceItem.").isEmpty)
        XCTAssertFalse(fixture.stagingDirectoryExists, "One folder must not be staged")
    }

    @MainActor
    func testAddSecondFolderStagesBothAndLabelsCount() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let setup = fixture.harness.setupStore
        let preferences = fixture.harness.preferencesStore

        await fixture.coordinator.addSourceItems([first])
        await fixture.coordinator.addSourceItems([second])

        XCTAssertNil(fixture.errors.last)
        XCTAssertTrue(fixture.stager.isStagingPath(setup.sourcePath))
        XCTAssertEqual(setup.droppedSourceLabel, "2 folders")
        XCTAssertEqual(setup.droppedSourceItemCount, 2)
        XCTAssertEqual(setup.sourceItems, [first, second])
        XCTAssertEqual(
            MediaDiscovery.dropManifestLookup(inSourceRoot: setup.sourcePath),
            .items([first.path, second.path])
        )
        XCTAssertEqual(preferences.manualSourceItemPaths, [first.path, second.path])
        XCTAssertEqual(preferences.bookmark(for: "manual.sourceItem.0")?.path, first.path)
        XCTAssertEqual(preferences.bookmark(for: "manual.sourceItem.1")?.path, second.path)
        XCTAssertEqual(
            preferences.lastManualSourcePath,
            first.path,
            "A staging path must never be remembered as the last manual folder"
        )
    }

    @MainActor
    func testRemoveBackToOneFolderDropsStaging() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let setup = fixture.harness.setupStore
        let preferences = fixture.harness.preferencesStore

        await fixture.coordinator.addSourceItems([first, second])
        let stagingDirectory = setup.sourcePath
        XCTAssertTrue(FileManager.default.fileExists(atPath: stagingDirectory))

        await fixture.coordinator.removeSourceItem(second)

        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory), "The old staging directory must be removed")
        XCTAssertEqual(setup.sourcePath, first.path)
        XCTAssertFalse(setup.usingDroppedSource)
        XCTAssertEqual(setup.sourceItems, [first])
        XCTAssertEqual(preferences.manualSourceItemPaths, [first.path])
        XCTAssertTrue(preferences.bookmarkKeys(withPrefix: "manual.sourceItem.").isEmpty)
        XCTAssertEqual(preferences.lastManualSourcePath, first.path)
    }

    @MainActor
    func testRemoveLastFolderClearsSource() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let folder = try fixture.makeFolder("Alpha")
        let setup = fixture.harness.setupStore
        let preferences = fixture.harness.preferencesStore

        await fixture.coordinator.addSourceItems([folder])
        await fixture.coordinator.removeSourceItem(folder)

        XCTAssertEqual(setup.sourcePath, "")
        XCTAssertNil(setup.sourceURL)
        XCTAssertFalse(setup.usingDroppedSource)
        XCTAssertTrue(setup.sourceItems.isEmpty)
        XCTAssertEqual(preferences.lastManualSourcePath, "")
        XCTAssertNil(preferences.bookmark(for: "manual.source"))
        XCTAssertTrue(preferences.bookmarkKeys(withPrefix: "manual.sourceItem.").isEmpty)
        XCTAssertEqual(preferences.manualSourceItemPaths, [])
    }

    @MainActor
    func testAddNestedFolderShowsMessageAndKeepsList() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let parent = try fixture.makeFolder("Alpha")
        let nested = try fixture.makeFolder("Alpha/Inner")
        let setup = fixture.harness.setupStore

        await fixture.coordinator.addSourceItems([parent])
        await fixture.coordinator.addSourceItems([nested])

        XCTAssertEqual(
            fixture.errors.last,
            "\u{201C}Inner\u{201D} is already covered because it is inside \u{201C}Alpha\u{201D}."
        )
        XCTAssertEqual(setup.sourceItems, [parent])
        XCTAssertEqual(setup.sourcePath, parent.path)
    }

    @MainActor
    func testDropAppendsToExistingList() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let setup = fixture.harness.setupStore

        await fixture.coordinator.addSourceItems([first])
        await fixture.coordinator.applyDrop(urls: [second])

        XCTAssertEqual(setup.sourceItems, [first, second], "A drop appends to the list instead of replacing it")
        XCTAssertEqual(setup.droppedSourceLabel, "2 folders")
        XCTAssertTrue(fixture.stager.isStagingPath(setup.sourcePath))
        XCTAssertEqual(fixture.routes, [.organize(.setup)])
    }

    @MainActor
    func testChooseSourceFolderUsesMultiPicker() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let decoy = try fixture.makeFolder("Decoy")
        let setup = fixture.harness.setupStore

        // The single-folder picker would return the decoy; only the
        // multi-picker returns both folders.
        fixture.harness.folderAccessService.nextChosenFolder = decoy
        fixture.harness.folderAccessService.nextChosenFolders = [first, second]

        await fixture.coordinator.chooseSourceFolder()

        XCTAssertEqual(setup.sourceItems, [first, second])
        XCTAssertFalse(setup.sourceItems.contains(decoy))
        XCTAssertEqual(fixture.harness.folderAccessService.chooseFolderCalls.last?.prompt, "Add Folders")
    }

    @MainActor
    func testSelectSourceFolderReplacesTheList() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let third = try fixture.makeFolder("Gamma")
        let setup = fixture.harness.setupStore

        await fixture.coordinator.addSourceItems([first, second])
        let stagingDirectory = setup.sourcePath
        await fixture.coordinator.selectSourceFolder(third)

        XCTAssertEqual(setup.sourceItems, [third])
        XCTAssertEqual(setup.sourcePath, third.path)
        XCTAssertFalse(setup.usingDroppedSource)
        XCTAssertFalse(FileManager.default.fileExists(atPath: stagingDirectory))
        XCTAssertEqual(fixture.harness.preferencesStore.manualSourceItemPaths, [third.path])
    }

    @MainActor
    func testAddAfterRelaunchKeepsThePlainSingleFolder() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")

        await fixture.coordinator.addSourceItems([first])
        let relaunched = fixture.relaunch()
        relaunched.coordinator.bootstrap()
        XCTAssertEqual(relaunched.setupStore.sourcePath, first.path)

        await relaunched.coordinator.addSourceItems([second])

        XCTAssertEqual(relaunched.setupStore.sourceItems, [first, second])
    }

    @MainActor
    func testSelectDestinationOverlappingListedFolderIsRefused() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let folder = try fixture.makeFolder("Alpha")
        let inside = try fixture.makeFolder("Alpha/Out")
        let safe = try fixture.makeFolder("Safe")
        let setup = fixture.harness.setupStore
        let preferences = fixture.harness.preferencesStore

        await fixture.coordinator.selectDestinationFolder(safe)
        XCTAssertEqual(setup.destinationPath, safe.path)
        await fixture.coordinator.addSourceItems([folder])

        await fixture.coordinator.selectDestinationFolder(inside)

        XCTAssertEqual(
            fixture.errors.last,
            "\u{201C}Alpha\u{201D} and the destination overlap. Choose a destination outside the folders you are organizing; nothing was changed."
        )
        XCTAssertEqual(setup.destinationPath, safe.path, "The destination must stay as it was")
        XCTAssertEqual(preferences.lastManualDestinationPath, safe.path)
    }

    @MainActor
    func testSaveProfileRefusedWithSeveralFolders() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let setup = fixture.harness.setupStore

        await fixture.coordinator.addSourceItems([first, second])
        setup.destinationPath = "/Volumes/Archive"
        setup.newProfileName = "trip"

        fixture.coordinator.saveCurrentPathsAsProfile()

        XCTAssertEqual(
            fixture.errors.last,
            "A saved profile holds one folder. Keep this list as it is (Chronoframe remembers it), or remove the extra folders to save a profile."
        )
        XCTAssertTrue(fixture.harness.repository.savedProfiles.isEmpty)
        XCTAssertEqual(setup.newProfileName, "trip")
    }

    @MainActor
    func testBootstrapRestoresListAndRestages() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")

        await fixture.coordinator.addSourceItems([first, second])
        let previousStaging = fixture.harness.setupStore.sourcePath

        let relaunched = fixture.relaunch()
        relaunched.coordinator.bootstrap()
        let restored = await waitForCondition { relaunched.setupStore.sourceItems.count == 2 }

        XCTAssertTrue(restored, "The saved folder list must come back at launch")
        XCTAssertEqual(relaunched.setupStore.sourceItems, [first, second])
        let stagingDirectory = relaunched.setupStore.sourcePath
        XCTAssertTrue(fixture.stager.isStagingPath(stagingDirectory))
        XCTAssertNotEqual(stagingDirectory, previousStaging, "Launch builds a fresh staging directory")
        XCTAssertFalse(FileManager.default.fileExists(atPath: previousStaging))
        XCTAssertEqual(relaunched.setupStore.droppedSourceLabel, "2 folders")
        XCTAssertEqual(
            MediaDiscovery.dropManifestLookup(inSourceRoot: stagingDirectory),
            .items([first.path, second.path])
        )
    }

    @MainActor
    func testBootstrapDropsUnresolvableItem() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let third = try fixture.makeFolder("Gamma")

        await fixture.coordinator.addSourceItems([first, second, third])
        fixture.harness.folderAccessService.bookmarkResolutionFailures.insert("manual.sourceItem.1")

        let relaunched = fixture.relaunch()
        relaunched.coordinator.bootstrap()
        let restored = await waitForCondition { relaunched.setupStore.sourceItems.count == 2 }

        XCTAssertTrue(restored)
        XCTAssertEqual(relaunched.setupStore.sourceItems, [first, third])
        XCTAssertEqual(fixture.harness.preferencesStore.manualSourceItemPaths, [first.path, third.path])
        let keys = fixture.harness.preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.").sorted()
        XCTAssertEqual(keys, ["manual.sourceItem.0", "manual.sourceItem.1"], "The dropped item's key must not linger")
        XCTAssertEqual(fixture.harness.preferencesStore.bookmark(for: "manual.sourceItem.1")?.path, third.path)
    }

    @MainActor
    func testBootstrapFallsBackToTheSingleFolderWhenTooFewResolve() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")

        await fixture.coordinator.addSourceItems([first])
        await fixture.coordinator.addSourceItems([second])
        fixture.harness.folderAccessService.bookmarkResolutionFailures.insert("manual.sourceItem.1")

        let relaunched = fixture.relaunch()
        relaunched.coordinator.bootstrap()

        XCTAssertEqual(relaunched.setupStore.sourcePath, first.path, "The remembered single folder is used")
        XCTAssertFalse(relaunched.setupStore.usingDroppedSource)
        XCTAssertEqual(fixture.harness.preferencesStore.manualSourceItemPaths, [])
        XCTAssertTrue(fixture.harness.preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.").isEmpty)
    }

    @MainActor
    func testBootstrapWithProfileKeepsProfileSource() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")

        await fixture.coordinator.addSourceItems([first, second])
        fixture.harness.repository.profiles = [
            Profile(name: "travel", sourcePath: "/Volumes/YAML-Card", destinationPath: "/Volumes/YAML-Trips")
        ]
        fixture.harness.preferencesStore.lastSelectedProfileName = "travel"

        let relaunched = fixture.relaunch()
        relaunched.setupStore.selectedProfileName = "travel"
        relaunched.coordinator.bootstrap()

        let restagedEarly = await waitForCondition(timeoutNanoseconds: 300_000_000) {
            relaunched.setupStore.sourceItems.count == 2
        }
        XCTAssertFalse(restagedEarly, "A selected profile hides the folder list; launch must not restage it")
        XCTAssertTrue(relaunched.setupStore.usingProfile)
        XCTAssertEqual(relaunched.setupStore.sourcePath, "/Volumes/YAML-Card")
        XCTAssertFalse(relaunched.setupStore.usingDroppedSource)

        relaunched.coordinator.clearSelectedProfile()
        let restored = await waitForCondition { fixture.stager.isStagingPath(relaunched.setupStore.sourcePath) }

        XCTAssertTrue(restored, "Clearing the profile brings the folder list back")
        XCTAssertEqual(relaunched.setupStore.sourceItems, [first, second])
        XCTAssertEqual(relaunched.setupStore.droppedSourceLabel, "2 folders")
    }

    @MainActor
    func testDropLooseFileIsStaged() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let file = fixture.root.appendingPathComponent("loose.jpg")
        try Data("x".utf8).write(to: file)
        // The real service rejects a file as a "folder to organize"; a dropped file is staged instead.
        fixture.harness.folderAccessService.validationFailures[file.path] =
            FolderValidationError.notDirectory(role: .source, path: file.path)
        let setup = fixture.harness.setupStore

        await fixture.coordinator.applyDrop(urls: [file])

        XCTAssertNil(fixture.errors.last)
        XCTAssertEqual(setup.sourceItems, [file.resolvingSymlinksInPath()])
        XCTAssertTrue(setup.usingDroppedSource)
        XCTAssertTrue(fixture.stager.isStagingPath(setup.sourcePath))
        XCTAssertEqual(
            MediaDiscovery.dropManifestLookup(inSourceRoot: setup.sourcePath),
            .items([file.resolvingSymlinksInPath().path])
        )
    }

    @MainActor
    func testDropFileAndFolderTogetherStagesBoth() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let folder = try fixture.makeFolder("Alpha")
        let file = fixture.root.appendingPathComponent("loose.jpg")
        try Data("x".utf8).write(to: file)
        let resolvedFile = file.resolvingSymlinksInPath()
        fixture.harness.folderAccessService.validationFailures[file.path] =
            FolderValidationError.notDirectory(role: .source, path: file.path)
        let setup = fixture.harness.setupStore

        await fixture.coordinator.applyDrop(urls: [folder, file])

        XCTAssertNil(fixture.errors.last)
        XCTAssertEqual(setup.sourceItems, [folder, resolvedFile])
        XCTAssertTrue(setup.usingDroppedSource)
        XCTAssertEqual(
            MediaDiscovery.dropManifestLookup(inSourceRoot: setup.sourcePath),
            .items([folder.path, resolvedFile.path])
        )
    }

    @MainActor
    func testRestoreWithFewerResolvedItemsClearsStaleRows() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let third = try fixture.makeFolder("Gamma")
        let setup = fixture.harness.setupStore

        fixture.harness.repository.profiles = [
            Profile(name: "travel", sourcePath: "/Volumes/YAML-Card", destinationPath: "/Volumes/YAML-Trips")
        ]
        await fixture.coordinator.addSourceItems([first])
        await fixture.coordinator.addSourceItems([second, third])
        fixture.coordinator.refreshProfiles()
        fixture.coordinator.useProfile(named: "travel")
        XCTAssertEqual(setup.sourceItems, [first, second, third], "Setup for the test: the list is hidden, not deleted")

        fixture.harness.folderAccessService.bookmarkResolutionFailures.insert("manual.sourceItem.1")
        fixture.harness.folderAccessService.bookmarkResolutionFailures.insert("manual.sourceItem.2")
        fixture.coordinator.clearSelectedProfile()

        XCTAssertFalse(fixture.stager.isStagingPath(setup.sourcePath))
        XCTAssertEqual(setup.sourcePath, first.path, "The remembered single folder is used")
        XCTAssertTrue(
            setup.sourceItems.isEmpty || setup.sourceItems == [first],
            "Setup must not list folders a run will not use"
        )
        XCTAssertFalse(setup.usingDroppedSource)
    }

    @MainActor
    func testClearProfileRestoresList() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        let setup = fixture.harness.setupStore

        fixture.harness.repository.profiles = [
            Profile(name: "travel", sourcePath: "/Volumes/YAML-Card", destinationPath: "/Volumes/YAML-Trips")
        ]
        await fixture.coordinator.addSourceItems([first, second])
        let previousStaging = setup.sourcePath
        fixture.coordinator.refreshProfiles()

        fixture.coordinator.useProfile(named: "travel")
        XCTAssertEqual(setup.sourcePath, "/Volumes/YAML-Card")
        XCTAssertEqual(setup.sourceItems, [first, second], "Selecting a profile hides the list without deleting it")

        fixture.coordinator.clearSelectedProfile()
        let restored = await waitForCondition { fixture.stager.isStagingPath(setup.sourcePath) }

        XCTAssertTrue(restored, "Clearing the profile must bring the folder list back")
        XCTAssertEqual(setup.sourceItems, [first, second])
        XCTAssertEqual(setup.droppedSourceLabel, "2 folders")
        XCTAssertNotEqual(setup.sourcePath, previousStaging)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: previousStaging),
            "The staging directory left behind by the profile switch must be removed"
        )
        XCTAssertEqual(
            MediaDiscovery.dropManifestLookup(inSourceRoot: setup.sourcePath),
            .items([first.path, second.path])
        )
    }

    // AGENTS-INVARIANT: 1
    @MainActor
    func testStagingNeverLivesInsideAListedFolder() async throws {
        let fixture = try SetupCoordinatorFixture()
        defer { fixture.tearDown() }
        let first = try fixture.makeFolder("Alpha")
        let second = try fixture.makeFolder("Beta")
        try Data("a".utf8).write(to: first.appendingPathComponent("a.jpg"))
        try Data("b".utf8).write(to: second.appendingPathComponent("b.jpg"))
        let before = [fixture.listing(of: first), fixture.listing(of: second)]

        await fixture.coordinator.addSourceItems([first])
        await fixture.coordinator.addSourceItems([second])

        let staging = fixture.harness.setupStore.sourcePath
        XCTAssertTrue(fixture.stager.isStagingPath(staging))
        for folder in [first, second] {
            XCTAssertFalse(
                URL(fileURLWithPath: staging).path.hasPrefix(folder.path + "/"),
                "The staging directory must not be inside a listed folder"
            )
        }
        XCTAssertEqual([fixture.listing(of: first), fixture.listing(of: second)], before, "Staging must create nothing under a listed folder")
    }
}

@MainActor
private final class SetupCoordinatorFixture {
    final class Errors {
        var all: [String?] = []
        var last: String? { all.last ?? nil }
    }

    struct Relaunched {
        let setupStore: SetupStore
        let coordinator: SetupCoordinator
    }

    let root: URL
    let stagingRoot: URL
    let harness = AppStateHarness()
    let stager: DroppedItemStager
    let errors = Errors()
    private let routeBox = RouteBox()
    private(set) var coordinator: SetupCoordinator!

    final class RouteBox { var routes: [AppRoute] = [] }

    init() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("setup-coordinator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath()
        stagingRoot = root.appendingPathComponent("drops", isDirectory: true)
        stager = DroppedItemStager(stagingRoot: stagingRoot)
        coordinator = makeCoordinator(setupStore: harness.setupStore)
    }

    var stagingDirectoryExists: Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: stagingRoot.path)) ?? []
        return !contents.isEmpty
    }

    var routes: [AppRoute] { routeBox.routes }

    func makeCoordinator(setupStore: SetupStore) -> SetupCoordinator {
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        let errors = self.errors
        let routeBox = self.routeBox
        return SetupCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: setupStore,
            historyStore: harness.historyStore,
            folderAccessService: harness.folderAccessService,
            profilesRepository: harness.repository,
            droppedItemStager: stager,
            bookmarkPathResolver: resolver,
            navigate: { routeBox.routes.append($0) },
            setTransientErrorMessage: { errors.all.append($0) }
        )
    }

    /// A second coordinator over the same stored preferences and a blank
    /// `SetupStore`, as after quitting and reopening the app.
    func relaunch() -> Relaunched {
        let store = SetupStore()
        return Relaunched(setupStore: store, coordinator: makeCoordinator(setupStore: store))
    }

    func makeFolder(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }

    func listing(of folder: URL) -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: folder.path)
        return (enumerator?.allObjects as? [String] ?? []).sorted()
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }
}
