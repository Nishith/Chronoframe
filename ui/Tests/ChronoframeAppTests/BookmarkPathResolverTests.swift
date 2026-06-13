#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

final class BookmarkPathResolverTests: XCTestCase {
    @MainActor
    func testRestoreManualPathsRefreshesResolvedBookmarks() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )

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

        resolver.restoreManualPaths(into: harness.setupStore)

        XCTAssertEqual(harness.setupStore.sourcePath, "/Volumes/NewCard")
        XCTAssertEqual(harness.setupStore.destinationPath, "/Volumes/NewArchive")
        XCTAssertEqual(harness.preferencesStore.lastManualSourcePath, "/Volumes/NewCard")
        XCTAssertEqual(harness.preferencesStore.lastManualDestinationPath, "/Volumes/NewArchive")
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "manual.source")?.path, "/Volumes/NewCard")
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "manual.destination")?.path, "/Volumes/NewArchive")
    }

    /// Restoring a bookmarked path must also start session-long
    /// security-scope access. Resolving alone returns a bare path the sandbox
    /// won't let the app read — the Setup contact sheet then shows
    /// "No previewable frames" for a folder full of photos, because only
    /// in-run engine work acquired scope.
    @MainActor
    func testRestoreManualPathsAcquiresSessionScopedAccess() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )

        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.source", path: "/Volumes/Card", data: Data([0x01]))
        )
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.destination", path: "/Volumes/Archive", data: Data([0x02]))
        )

        resolver.restoreManualPaths(into: harness.setupStore)

        XCTAssertEqual(
            harness.folderAccessService.scopedAccessRequests,
            [["manual.source", "manual.destination"]]
        )
    }

    /// When a profile has no profile-specific bookmarks but manual bookmarks
    /// exist (e.g. a profile imported via CLI with YAML paths), the manual
    /// bookmarks are used as a fallback so the sandbox scope is not dropped.
    @MainActor
    func testRestoreProfilePathsFallsBackToManualBookmarksWhenProfileBookmarksAbsent() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )

        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.source", path: "/Volumes/Card", data: Data([0x01]))
        )
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.destination", path: "/Volumes/Archive", data: Data([0x02]))
        )

        // Profile "Trip" has paths stored in SetupStore but no bookmark blobs.
        resolver.restoreProfilePaths(named: "Trip", into: harness.setupStore)

        XCTAssertEqual(
            harness.folderAccessService.scopedAccessRequests,
            [["manual.source", "manual.destination"]],
            "Should fall back to manual bookmarks when profile bookmarks are absent"
        )
    }

    /// Profile restores acquire scope under the profile's bookmark keys, and
    /// a restore with no stored bookmarks must not request scope at all.
    @MainActor
    func testRestoreProfilePathsAcquiresScopeOnlyForStoredBookmarks() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )

        resolver.restoreProfilePaths(named: "Trip", into: harness.setupStore)
        XCTAssertTrue(harness.folderAccessService.scopedAccessRequests.isEmpty)

        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "profile.Trip.source", path: "/Volumes/Card", data: Data([0x01]))
        )
        resolver.restoreProfilePaths(named: "Trip", into: harness.setupStore)
        XCTAssertEqual(
            harness.folderAccessService.scopedAccessRequests,
            [["profile.Trip.source"]]
        )
    }
}
