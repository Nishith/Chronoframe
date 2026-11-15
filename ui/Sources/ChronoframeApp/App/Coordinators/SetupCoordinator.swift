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
    /// The staging directory this coordinator built for the current folder
    /// list, so it can be removed when the list is rebuilt or shrinks.
    private var stagingDirectory: URL?
    /// Saved folder-list entries whose bookmark did not resolve at launch (an
    /// unmounted drive, say). They are kept in the saved list, never inferred
    /// missing, and are written back after every edit of the visible list.
    private var unreachableSavedItems: [FolderBookmark] = []
    private static let sourceItemKeyPrefix = "manual.sourceItem."

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
            restoreSourceItems()
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
        let startingPath = droppedItemStager.isStagingPath(setupStore.sourcePath) ? nil : setupStore.sourcePath
        let chosen = folderAccessService.chooseFolders(
            startingAt: startingPath,
            prompt: "Add Folders"
        )
        guard !chosen.isEmpty else {
            return
        }

        await addSourceItems(chosen)
    }

    func addSourceItems(_ urls: [URL]) async {
        _ = await addSourceItemsReportingApplied(urls)
    }

    /// Returns true when the new list was applied. A rejected item is reported
    /// and skipped; the rest are still added. Adding while a profile is active
    /// leaves profile mode, but only once the list was applied, so a failed add
    /// doesn't leave the store half-switched.
    private func addSourceItemsReportingApplied(_ urls: [URL]) async -> Bool {
        guard !urls.isEmpty else { return false }

        // Hold security-scoped access across validation, the staging manifest
        // and bookmark creation, then release on return. (Open-panel URLs are
        // already granted via Powerbox, so this is a harmless no-op for them.)
        var accessed: [URL] = []
        defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }

        let leavingProfile = setupStore.usingProfile
        let before = currentSourceItemList()
        var list = before
        var rejections: [String] = []
        for url in urls {
            if url.startAccessingSecurityScopedResource() { accessed.append(url) }

            // A loose file is staged rather than chosen as a folder, so only
            // folders go through folder validation; `list.add` still refuses a
            // path that is not on disk.
            if !Self.isExistingFile(url), let message = await validationMessage(for: url, role: .source) {
                rejections.append(message)
                continue
            }
            do {
                try list.add(url, destinationPath: setupStore.destinationPath)
            } catch {
                rejections.append(error.localizedDescription)
            }
        }
        if !rejections.isEmpty {
            var seen = Set<String>()
            let distinct = rejections.filter { seen.insert($0).inserted }
            setTransientErrorMessage(distinct.joined(separator: "\n"))
        }

        // Leaving a profile applies the list even when it equals the profile's
        // own folder, as long as nothing was rejected.
        guard list != before || (leavingProfile && rejections.isEmpty) else { return false }
        let applied = await applySourceItems(list)
        if applied {
            if leavingProfile {
                setupStore.clearProfileSelection()
            }
            preferencesStore.lastSelectedProfileName = ""
        }
        return applied
    }

    private static func isExistingFile(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }

    func removeSourceItem(_ url: URL) async {
        let before = currentSourceItemList()
        var list = before
        list.remove(url)
        guard list != before else { return }
        let leavingProfile = setupStore.usingProfile
        if await applySourceItems(list), leavingProfile {
            setupStore.clearProfileSelection()
            preferencesStore.lastSelectedProfileName = ""
        }
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

        var list = SourceItemList()
        do {
            try list.add(url, destinationPath: setupStore.destinationPath)
        } catch {
            setTransientErrorMessage(error.localizedDescription)
            return
        }

        // An explicit replacement: it also ends the saved list's unreachable entries.
        unreachableSavedItems = []
        await applySourceItems(list)
        if !setupStore.usingProfile {
            preferencesStore.lastSelectedProfileName = ""
        }
    }

    /// The folder list as the user sees it. With a profile active the list is
    /// seeded from the profile's own folder (what Setup shows), never from the
    /// manual state the profile hides. After a relaunch with one plain folder
    /// the store's list is empty, so that remembered folder seeds it; otherwise
    /// adding a second folder would silently drop the first.
    private func currentSourceItemList() -> SourceItemList {
        var list = SourceItemList()
        if setupStore.usingProfile {
            let path = setupStore.sourcePath
            if !path.isEmpty, !droppedItemStager.isStagingPath(path) {
                try? list.add(URL(fileURLWithPath: path), destinationPath: "")
            }
            return list
        }
        if !setupStore.sourceItems.isEmpty {
            return SourceItemList(items: setupStore.sourceItems)
        }
        let remembered = preferencesStore.lastManualSourcePath
        // A saved list of other folders means the last plain folder was replaced.
        let saved = preferencesStore.manualSourceItemPaths
        if !remembered.isEmpty, !droppedItemStager.isStagingPath(remembered),
           saved.isEmpty || saved == [remembered] {
            try? list.add(URL(fileURLWithPath: remembered), destinationPath: "")
        }
        return list
    }

    /// `persist: false` is for rebuilding the list at launch from what is
    /// already saved: it stages and shows the list but writes no bookmarks or
    /// paths, so entries that could not be reached this session stay saved.
    @discardableResult
    private func applySourceItems(_ list: SourceItemList, persist: Bool = true) async -> Bool {
        let items = list.items
        let previousStagingDirectory = stagingDirectory

        if items.isEmpty {
            removeStagingDirectory(previousStagingDirectory)
            setupStore.sourcePath = ""
            setupStore.sourceURL = nil
            setupStore.clearDroppedSource()
            if persist {
                // Emptying the list is the one way to forget the unreachable entries too.
                unreachableSavedItems = []
                preferencesStore.lastManualSourcePath = ""
                bookmarkPathResolver.removeBookmark(for: .source, profileName: nil)
                await bookmarkPathResolver.persistSourceItemBookmarks(for: [])
                preferencesStore.manualSourceItemPaths = []
            }
        } else if !list.needsStaging {
            let url = items[0]
            removeStagingDirectory(previousStagingDirectory)
            setupStore.sourcePath = url.path
            setupStore.sourceURL = url
            setupStore.clearDroppedSource()
            if persist {
                preferencesStore.lastManualSourcePath = url.path
                await bookmarkPathResolver.persistBookmark(for: url, role: .source, profileName: nil)
                if unreachableSavedItems.isEmpty {
                    await bookmarkPathResolver.persistSourceItemBookmarks(for: [])
                    preferencesStore.manualSourceItemPaths = [url.path]
                } else {
                    await persistSavedList(items)
                }
            }
        } else {
            let staged: StagedDrop
            do {
                staged = try droppedItemStager.stage(urls: items)
            } catch {
                setTransientErrorMessage(UserFacingErrorMessage.message(for: error, context: .droppedItems))
                return false
            }
            removeStagingDirectory(previousStagingDirectory)
            stagingDirectory = staged.sourceDirectory
            setupStore.sourcePath = staged.sourceDirectory.path
            setupStore.sourceURL = staged.sourceDirectory
            setupStore.droppedSourceLabel = SourceItemList.summaryLabel(count: items.count)
            setupStore.droppedSourceItemCount = items.count
            if persist {
                // The saved list, not `lastManualSourcePath` (which never holds
                // a staging path), is what launch restores for a staged list.
                await persistSavedList(items)
            }
        }

        setupStore.setSourceItems(items)
        return true
    }

    /// Saves the visible items and then the unreachable entries after them.
    private func persistSavedList(_ items: [URL]) async {
        await bookmarkPathResolver.persistSourceItemBookmarks(for: items)
        var paths = items.map(\.path)
        for bookmark in unreachableSavedItems {
            let key = bookmarkPathResolver.sourceItemBookmarkKey(index: paths.count)
            preferencesStore.storeBookmark(FolderBookmark(key: key, path: bookmark.path, data: bookmark.data))
            paths.append(bookmark.path)
        }
        preferencesStore.manualSourceItemPaths = paths
    }

    /// Removes a staging directory this coordinator created. Anything outside
    /// the staging root is left alone.
    private func removeStagingDirectory(_ url: URL?) {
        if let url {
            droppedItemStager.cleanup(stagingDirectory: url)
        }
        let current = setupStore.sourceURL
        if let current, droppedItemStager.isStagingPath(current.path) {
            droppedItemStager.cleanup(stagingDirectory: current)
        }
        stagingDirectory = nil
    }

    /// Rebuilds the saved folder list at launch (staging is wiped on every
    /// launch) or after a profile is cleared. Items that do not resolve this
    /// session (an unmounted drive, a deleted file) are skipped but stay in the
    /// saved list; resolving never deletes a bookmark. The list that was last
    /// chosen wins over the older single folder, even when it holds one item.
    private func restoreSourceItems() {
        let saved = resolveSavedSourceItems()
        unreachableSavedItems = saved.filter { $0.url == nil }.map(\.bookmark)
        guard !saved.isEmpty else { return }

        let reachable = saved.compactMap(\.url)
        guard !reachable.isEmpty else {
            // Nothing reachable: do not fall back to an older folder the user replaced.
            if !setupStore.usingProfile, !setupStore.usingDroppedSource {
                setupStore.sourcePath = ""
                setupStore.sourceURL = nil
            }
            clearStaleSourceItems()
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            // Bail unless the manual view is still current: a selected
            // profile owns the source (D-CLP-21), and a different list
            // applied since must not be overwritten.
            guard !setupStore.usingProfile else { return }
            var accessed: [URL] = []
            defer { for url in accessed { url.stopAccessingSecurityScopedResource() } }
            var list = SourceItemList()
            for url in reachable {
                if url.startAccessingSecurityScopedResource() { accessed.append(url) }
                try? list.add(url, destinationPath: setupStore.destinationPath)
            }
            if !setupStore.sourceItems.isEmpty,
               setupStore.sourceItems != list.items || setupStore.usingDroppedSource {
                // A stale list must not outlive the folder a run will use;
                // a newer staged list (or a profile) is left as it is.
                clearStaleSourceItems()
                return
            }
            await self.applySourceItems(list, persist: false)
        }
    }

    private struct SavedSourceItem {
        let bookmark: FolderBookmark
        /// Nil when the bookmark did not resolve this time.
        let url: URL?
    }

    /// Resolves the saved folder list in index order without removing anything:
    /// unlike `BookmarkPathResolver.resolveSourceItemURLs`, a bookmark that does
    /// not resolve is reported, not deleted.
    private func resolveSavedSourceItems() -> [SavedSourceItem] {
        let prefix = Self.sourceItemKeyPrefix
        let keys = preferencesStore.bookmarkKeys(withPrefix: prefix)
            .compactMap { key -> (index: Int, key: String)? in
                Int(key.dropFirst(prefix.count)).map { ($0, key) }
            }
            .sorted { $0.index < $1.index }
            .map(\.key)
        return keys.compactMap { key in
            guard let bookmark = preferencesStore.bookmark(for: key) else { return nil }
            guard let resolved = folderAccessService.resolveBookmark(bookmark) else {
                return SavedSourceItem(bookmark: bookmark, url: nil)
            }
            if let refreshed = resolved.refreshedBookmark {
                preferencesStore.storeBookmark(refreshed)
            }
            return SavedSourceItem(bookmark: resolved.refreshedBookmark ?? bookmark, url: resolved.url)
        }
    }

    private func clearStaleSourceItems() {
        if !setupStore.usingProfile, !setupStore.usingDroppedSource {
            setupStore.setSourceItems([])
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

        // Adding leaves profile mode only once the drop has been applied, so a
        // failed drop doesn't leave the store half-switched, and the window
        // only changes when the drop changed something.
        if await addSourceItemsReportingApplied(urls) {
            navigate(.organize(.setup))
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

        if let conflict = SourceItemList(items: setupStore.sourceItems).firstConflict(withDestination: url.path) {
            setTransientErrorMessage(conflict.localizedDescription)
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
        // The list a profile hid is rebuilt from the saved list, which is the
        // truth; a partly reachable one must not be mistaken for a newer list.
        setupStore.setSourceItems([])
        restoreSourceItems()
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

        guard setupStore.sourceItems.count <= 1 else {
            setTransientErrorMessage("A saved profile holds one folder. Keep this list as it is (Chronoframe remembers it), or remove the extra folders to save a profile.")
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
