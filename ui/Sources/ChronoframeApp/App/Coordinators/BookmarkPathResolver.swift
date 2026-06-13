import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

@MainActor
final class BookmarkPathResolver {
    private let preferencesStore: PreferencesStore
    private let folderAccessService: any FolderAccessServicing

    /// Session-long security-scope access for the folders restored from
    /// bookmarks. Resolving a bookmark alone does not grant sandbox read
    /// access — without starting the scope, surfaces that read the restored
    /// path directly (the Setup contact sheet) see an unreadable folder until
    /// a run acquires its own per-run scope. Replaced wholesale on each
    /// restore; the superseded token stops access when it deinitializes.
    private var restoredPathAccess: SecurityScopedFolderAccess?

    init(
        preferencesStore: PreferencesStore,
        folderAccessService: any FolderAccessServicing
    ) {
        self.preferencesStore = preferencesStore
        self.folderAccessService = folderAccessService
    }

    func bookmarkKey(for role: FolderRole, profileName: String?) -> String {
        if let profileName {
            return "profile.\(profileName).\(role.rawValue)"
        }
        return "manual.\(role.rawValue)"
    }

    func persistBookmark(for url: URL, role: FolderRole, profileName: String?) async {
        let key = bookmarkKey(for: role, profileName: profileName)
        let service = folderAccessService
        let bookmark = await Task.detached(priority: .userInitiated) {
            try? service.makeBookmark(for: url, key: key)
        }.value
        guard let bookmark else { return }
        preferencesStore.storeBookmark(bookmark)
    }

    func removeBookmark(for role: FolderRole, profileName: String?) {
        preferencesStore.removeBookmark(for: bookmarkKey(for: role, profileName: profileName))
    }

    func restoreManualPaths(into setupStore: SetupStore) {
        setupStore.sourcePath = preferencesStore.lastManualSourcePath
        setupStore.destinationPath = preferencesStore.lastManualDestinationPath

        if let sourcePath = resolveBookmarkedPath(for: .source, profileName: nil) {
            setupStore.sourcePath = sourcePath
            preferencesStore.lastManualSourcePath = sourcePath
        }

        if let destinationPath = resolveBookmarkedPath(for: .destination, profileName: nil) {
            setupStore.destinationPath = destinationPath
            preferencesStore.lastManualDestinationPath = destinationPath
        }

        retainScopedAccess(forProfileName: nil)
    }

    func restoreProfilePaths(named profileName: String, into setupStore: SetupStore) {
        if let sourcePath = resolveBookmarkedPath(for: .source, profileName: profileName) {
            setupStore.sourcePath = sourcePath
        }

        if let destinationPath = resolveBookmarkedPath(for: .destination, profileName: profileName) {
            setupStore.destinationPath = destinationPath
        }

        retainScopedAccess(forProfileName: profileName)
    }

    private func retainScopedAccess(forProfileName profileName: String?) {
        let keys = [
            bookmarkKey(for: .source, profileName: profileName),
            bookmarkKey(for: .destination, profileName: profileName),
        ]
        var bookmarks = keys.compactMap { preferencesStore.bookmark(for: $0) }

        // When profile-specific bookmarks are absent or partial (e.g. a profile
        // imported via CLI with YAML paths but no Finder-picked bookmark blobs),
        // supplement with manual bookmarks so that sandbox access acquired at
        // launch is not dropped. Without this, the contact sheet and other
        // sandboxed reads lose access to the same folders the manual scope covers.
        if profileName != nil, bookmarks.count < keys.count {
            let manualKeys = [
                bookmarkKey(for: .source, profileName: nil),
                bookmarkKey(for: .destination, profileName: nil),
            ]
            bookmarks += manualKeys.compactMap { preferencesStore.bookmark(for: $0) }
        }

        restoredPathAccess = bookmarks.isEmpty ? nil : folderAccessService.scopedAccess(for: bookmarks)
    }

    func resolveBookmarkedPath(for role: FolderRole, profileName: String?) -> String? {
        let key = bookmarkKey(for: role, profileName: profileName)
        guard let bookmark = preferencesStore.bookmark(for: key) else {
            return nil
        }
        // Phase 1 finding #5: when the cached bookmark no longer
        // resolves (volume gone, app re-installed, sandbox metadata
        // wiped), drop it from preferences instead of leaving it to
        // re-fail every launch. Mirrors the AppState dedupe-destination
        // bootstrap behavior.
        guard let resolvedBookmark = folderAccessService.resolveBookmark(bookmark) else {
            preferencesStore.removeBookmark(for: key)
            return nil
        }

        if let refreshedBookmark = resolvedBookmark.refreshedBookmark {
            preferencesStore.storeBookmark(refreshedBookmark)
        }

        return resolvedBookmark.url.path
    }
}
