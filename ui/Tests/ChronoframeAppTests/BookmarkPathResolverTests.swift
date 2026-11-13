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

    // MARK: - Folder list bookmarks (CLP WP-04)

    @MainActor
    func testPersistSourceItemBookmarksRemovesStaleKeys() async {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        let urls = ["/Volumes/A", "/Volumes/B", "/Volumes/C"].map { URL(fileURLWithPath: $0) }
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.source", path: "/Volumes/Single", data: Data([0x01]))
        )

        await resolver.persistSourceItemBookmarks(for: urls)

        XCTAssertEqual(resolver.sourceItemBookmarkKey(index: 2), "manual.sourceItem.2")
        XCTAssertEqual(
            harness.preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.").sorted(),
            ["manual.sourceItem.0", "manual.sourceItem.1", "manual.sourceItem.2"]
        )
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "manual.sourceItem.1")?.path, "/Volumes/B")

        await resolver.persistSourceItemBookmarks(for: [urls[2]])

        XCTAssertEqual(
            harness.preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem."),
            ["manual.sourceItem.0"],
            "Keys beyond the new list must be removed"
        )
        XCTAssertEqual(harness.preferencesStore.bookmark(for: "manual.sourceItem.0")?.path, "/Volumes/C")
        XCTAssertEqual(
            harness.preferencesStore.bookmark(for: "manual.source")?.path,
            "/Volumes/Single",
            "The single-folder bookmark is not a folder-list key"
        )

        await resolver.persistSourceItemBookmarks(for: [])
        XCTAssertTrue(harness.preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.").isEmpty)
    }

    @MainActor
    func testPersistSourceItemBookmarksClearsAKeyWhoseBookmarkCannotBeMade() async {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "manual.sourceItem.1", path: "/Volumes/Old", data: Data([0x09]))
        )
        harness.folderAccessService.bookmarkCreationFailures["manual.sourceItem.1"] = AppTestFailure.expectedFailure("no")

        await resolver.persistSourceItemBookmarks(
            for: [URL(fileURLWithPath: "/Volumes/A"), URL(fileURLWithPath: "/Volumes/B")]
        )

        XCTAssertEqual(harness.preferencesStore.bookmark(for: "manual.sourceItem.0")?.path, "/Volumes/A")
        XCTAssertNil(
            harness.preferencesStore.bookmark(for: "manual.sourceItem.1"),
            "A stale bookmark must not survive under an index it no longer describes"
        )
    }

    @MainActor
    func testResolveSourceItemURLsKeepsIndexOrder() {
        let harness = AppStateHarness()
        let resolver = BookmarkPathResolver(
            preferencesStore: harness.preferencesStore,
            folderAccessService: harness.folderAccessService
        )
        // Stored out of order, with indexes that sort differently as numbers
        // and as text (2 comes before 10).
        for index in [10, 2, 0, 11, 1, 3] {
            harness.preferencesStore.storeBookmark(
                FolderBookmark(
                    key: "manual.sourceItem.\(index)",
                    path: "/Volumes/Item\(index)",
                    data: Data([UInt8(index)])
                )
            )
        }
        harness.folderAccessService.bookmarkResolutionFailures.insert("manual.sourceItem.3")

        let urls = resolver.resolveSourceItemURLs()

        XCTAssertEqual(
            urls.map(\.path),
            ["/Volumes/Item0", "/Volumes/Item1", "/Volumes/Item2", "/Volumes/Item10", "/Volumes/Item11"]
        )
        XCTAssertNil(
            harness.preferencesStore.bookmark(for: "manual.sourceItem.3"),
            "An item that no longer resolves has its key removed"
        )
    }

    @MainActor
    func testRetainScopedAccessIncludesSourceItems() async {
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
        for index in [1, 0] {
            harness.preferencesStore.storeBookmark(
                FolderBookmark(key: "manual.sourceItem.\(index)", path: "/Volumes/Item\(index)", data: Data([0x10]))
            )
        }

        resolver.restoreManualPaths(into: harness.setupStore)

        XCTAssertEqual(
            harness.folderAccessService.scopedAccessRequests,
            [["manual.source", "manual.destination", "manual.sourceItem.0", "manual.sourceItem.1"]]
        )

        // A profile restore does not hold the folder list's scope.
        harness.folderAccessService.scopedAccessRequests = []
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "profile.Trip.source", path: "/Volumes/Card", data: Data([0x03]))
        )
        harness.preferencesStore.storeBookmark(
            FolderBookmark(key: "profile.Trip.destination", path: "/Volumes/Archive", data: Data([0x04]))
        )
        resolver.restoreProfilePaths(named: "Trip", into: harness.setupStore)
        XCTAssertEqual(
            harness.folderAccessService.scopedAccessRequests,
            [["profile.Trip.source", "profile.Trip.destination"]]
        )

        // Saving the list holds scope for the new items too.
        harness.folderAccessService.scopedAccessRequests = []
        await resolver.persistSourceItemBookmarks(for: [URL(fileURLWithPath: "/Volumes/New")])
        XCTAssertEqual(
            harness.folderAccessService.scopedAccessRequests.last,
            ["manual.source", "manual.destination", "manual.sourceItem.0"]
        )
    }
}
