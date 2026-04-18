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
}
