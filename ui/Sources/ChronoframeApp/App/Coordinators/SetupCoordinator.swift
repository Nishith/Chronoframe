import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

@MainActor
final class SetupCoordinator {
    private let preferencesStore: PreferencesStore
    private let setupStore: SetupStore
    private let historyStore: HistoryStore
    private let folderAccessService: any FolderAccessServicing
    private let profilesRepository: any ProfilesRepositorying
    private let droppedItemStager: DroppedItemStager
    private let bookmarkPathResolver: BookmarkPathResolver
    private let navigate: @MainActor (AppRoute) -> Void
    private let setTransientErrorMessage: @MainActor (String?) -> Void

    init(
        preferencesStore: PreferencesStore,
        setupStore: SetupStore,
        historyStore: HistoryStore,
        folderAccessService: any FolderAccessServicing,
        profilesRepository: any ProfilesRepositorying,
        droppedItemStager: DroppedItemStager,
        bookmarkPathResolver: BookmarkPathResolver,
        navigate: @escaping @MainActor (AppRoute) -> Void,
        setTransientErrorMessage: @escaping @MainActor (String?) -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.setupStore = setupStore
        self.historyStore = historyStore
        self.folderAccessService = folderAccessService
        self.profilesRepository = profilesRepository
        self.droppedItemStager = droppedItemStager
        self.bookmarkPathResolver = bookmarkPathResolver
        self.navigate = navigate
        self.setTransientErrorMessage = setTransientErrorMessage
    }

    func bootstrap(restoreBookmarks: Bool = true) {
        droppedItemStager.cleanupAllStagingDirectories()
        if restoreBookmarks {
            bookmarkPathResolver.restoreManualPaths(into: setupStore)
        }
        refreshProfiles()
        reloadHistory(destinationRoot: setupStore.destinationPath)
    }

    /// Records the destination synchronously (so the UI reflects it at once)
    /// and offloads the run-history disk scan so a slow/network destination
    /// can't freeze the main thread.
    private func reloadHistory(destinationRoot: String) {
        historyStore.setDestinationRoot(destinationRoot)
        let store = historyStore
        Task { await store.loadEntries() }
    }

    func chooseSourceFolder() async {
        let chosen = folderAccessService.chooseFolder(
            startingAt: setupStore.sourcePath,
            prompt: "Choose Source Folder"
        )
        guard let url = chosen else {
            return
        }

        await selectSourceFolder(url)
    }

    func selectSourceFolder(_ url: URL) async {
        // Hold security-scoped access across the off-main validation and
        // bookmark creation below, then release on return. (Open-panel URLs are
        // already granted via Powerbox, so this is a harmless no-op for them.)
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        if let message = await validationMessage(for: url, role: .source) {
            setTransientErrorMessage(message)
            return
        }

        setupStore.sourcePath = url.path
        setupStore.clearDroppedSource()
        preferencesStore.lastManualSourcePath = url.path
        await bookmarkPathResolver.persistBookmark(for: url, role: .source, profileName: nil)
        if !setupStore.usingProfile {
            preferencesStore.lastSelectedProfileName = ""
        }
    }

    /// Runs the blocking filesystem validation off the main actor and returns
    /// a user-facing message when the folder is unusable, or nil when valid.
    private func validationMessage(for url: URL, role: FolderRole) async -> String? {
        let service = folderAccessService
        return await Task.detached(priority: .userInitiated) { () -> String? in
            do {
                try service.validateFolder(url, role: role)
                return nil
            } catch {
                return UserFacingErrorMessage.message(for: error, context: .setup)
            }
        }.value
    }

    func applyDrop(urls: [URL]) async {
        guard !urls.isEmpty else { return }

        do {
            let staged = try droppedItemStager.stage(urls: urls)
            if setupStore.usingProfile {
                setupStore.clearProfileSelection()
                preferencesStore.lastSelectedProfileName = ""
            }

            setupStore.sourcePath = staged.sourceDirectory.path
            if staged.wasSingleFolder {
                setupStore.clearDroppedSource()
                preferencesStore.lastManualSourcePath = staged.sourceDirectory.path
            } else {
                setupStore.droppedSourceLabel = staged.displayLabel
                setupStore.droppedSourceItemCount = staged.itemCount
            }

            navigate(.organize(.setup))
        } catch {
            setTransientErrorMessage(UserFacingErrorMessage.message(for: error, context: .droppedItems))
        }
    }

    func chooseDestinationFolder() async {
        guard let url = folderAccessService.chooseFolder(
            startingAt: setupStore.destinationPath,
            prompt: "Choose Destination Folder"
        ) else {
            return
        }

        await selectDestinationFolder(url)
    }

    func selectDestinationFolder(_ url: URL) async {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }

        if let message = await validationMessage(for: url, role: .destination) {
            setTransientErrorMessage(message)
            return
        }

        setupStore.destinationPath = url.path
        preferencesStore.lastManualDestinationPath = url.path
        await bookmarkPathResolver.persistBookmark(for: url, role: .destination, profileName: nil)
        // Scope is still held here, so the destination scan can read it.
        await historyStore.refresh(destinationRoot: url.path)
        if !setupStore.usingProfile {
            preferencesStore.lastSelectedProfileName = ""
        }
    }

    func useProfile(named name: String) {
        setupStore.selectProfile(named: name)
        preferencesStore.lastSelectedProfileName = setupStore.selectedProfileName

        if let activeProfile = setupStore.activeProfile {
            bookmarkPathResolver.restoreProfilePaths(named: activeProfile.name, into: setupStore)
            reloadHistory(destinationRoot: setupStore.destinationPath)
        } else if !setupStore.usingProfile {
            reloadHistory(destinationRoot: setupStore.destinationPath)
        }
    }

    func clearSelectedProfile() {
        setupStore.clearProfileSelection()
        preferencesStore.lastSelectedProfileName = ""
        bookmarkPathResolver.restoreManualPaths(into: setupStore)
        reloadHistory(destinationRoot: setupStore.destinationPath)
    }

    func refreshProfiles() {
        do {
            let profiles = try profilesRepository.loadProfiles()
            setupStore.updateProfiles(profiles)
            if setupStore.usingProfile {
                setupStore.selectProfile(named: setupStore.selectedProfileName)
            }
        } catch {
            setTransientErrorMessage(UserFacingErrorMessage.message(for: error, context: .profiles))
        }
    }

    func saveCurrentPathsAsProfile() {
        let name = setupStore.newProfileName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            setTransientErrorMessage("Enter a profile name before saving.")
            return
        }

        guard !setupStore.sourcePath.isEmpty, !setupStore.destinationPath.isEmpty else {
            setTransientErrorMessage("Choose both a source and destination before saving a profile.")
            return
        }

        let profile = Profile(
            name: name,
            sourcePath: setupStore.sourcePath,
            destinationPath: setupStore.destinationPath
        )

        do {
            try profilesRepository.save(profile: profile)

            let manualSourceKey = bookmarkPathResolver.bookmarkKey(for: .source, profileName: nil)
            let manualDestinationKey = bookmarkPathResolver.bookmarkKey(for: .destination, profileName: nil)
            let profileSourceKey = bookmarkPathResolver.bookmarkKey(for: .source, profileName: name)
            let profileDestinationKey = bookmarkPathResolver.bookmarkKey(for: .destination, profileName: name)

            if let sourceBookmark = preferencesStore.bookmark(for: manualSourceKey) {
                preferencesStore.storeBookmark(
                    FolderBookmark(key: profileSourceKey, path: sourceBookmark.path, data: sourceBookmark.data)
                )
            }

            if let destinationBookmark = preferencesStore.bookmark(for: manualDestinationKey) {
                preferencesStore.storeBookmark(
                    FolderBookmark(key: profileDestinationKey, path: destinationBookmark.path, data: destinationBookmark.data)
                )
            }

            setupStore.newProfileName = ""
            refreshProfiles()
            useProfile(named: name)
        } catch {
            setTransientErrorMessage(UserFacingErrorMessage.message(for: error, context: .profiles))
        }
    }

    func overwriteProfile(named name: String) {
        setupStore.newProfileName = name
        saveCurrentPathsAsProfile()
    }

    func deleteProfile(named name: String) {
        do {
            try profilesRepository.deleteProfile(named: name)
            bookmarkPathResolver.removeBookmark(for: .source, profileName: name)
            bookmarkPathResolver.removeBookmark(for: .destination, profileName: name)
            if setupStore.selectedProfileName == name {
                clearSelectedProfile()
            }
            refreshProfiles()
        } catch {
            setTransientErrorMessage(UserFacingErrorMessage.message(for: error, context: .profiles))
        }
    }
}
