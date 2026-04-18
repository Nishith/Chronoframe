import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

@MainActor
final class BookmarkPathResolver {
    private let preferencesStore: PreferencesStore
    private let folderAccessService: any FolderAccessServicing

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

    func persistBookmark(for url: URL, role: FolderRole, profileName: String?) {
        let key = bookmarkKey(for: role, profileName: profileName)
        guard let bookmark = try? folderAccessService.makeBookmark(for: url, key: key) else { return }
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
    }

    func restoreProfilePaths(named profileName: String, into setupStore: SetupStore) {
        if let sourcePath = resolveBookmarkedPath(for: .source, profileName: profileName) {
            setupStore.sourcePath = sourcePath
        }

        if let destinationPath = resolveBookmarkedPath(for: .destination, profileName: profileName) {
            setupStore.destinationPath = destinationPath
        }
    }

    func resolveBookmarkedPath(for role: FolderRole, profileName: String?) -> String? {
        let key = bookmarkKey(for: role, profileName: profileName)
        guard let bookmark = preferencesStore.bookmark(for: key),
              let resolvedBookmark = folderAccessService.resolveBookmark(bookmark)
        else {
            return nil
        }

        if let refreshedBookmark = resolvedBookmark.refreshedBookmark {
            preferencesStore.storeBookmark(refreshedBookmark)
        }

        return resolvedBookmark.url.path
    }
}
