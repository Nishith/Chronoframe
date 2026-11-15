#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

final class HistoryCoordinatorTests: XCTestCase {
    @MainActor
    func testHistoryActionsOpenRevealReuseAndForgetRecords() {
        let harness = AppStateHarness()
        var route: AppRoute?
        let coordinator = HistoryCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            runSessionStore: harness.runSessionStore,
            deduplicateSessionStore: harness.deduplicateSessionStore,
            finderService: harness.finderService,
            navigate: { route = $0 }
        )

        let entry = RunHistoryEntry(
            kind: .runLog,
            title: "Run Log",
            path: "/tmp/destination/.organize_log.txt",
            createdAt: Date()
        )
        let record = TransferredSourceRecord(
            sourcePath: "/Volumes/Card",
            firstTransferredAt: Date(),
            lastTransferredAt: Date(),
            runCount: 1,
            lastCopiedCount: 10,
            totalCopiedCount: 10
        )

        coordinator.openHistoryEntry(entry)
        coordinator.revealHistoryEntry(entry)
        coordinator.useHistoricalSource(record)
        coordinator.revealTransferredSource(record)
        coordinator.forgetTransferredSource(record)

        XCTAssertEqual(harness.finderService.openedPaths, ["/tmp/destination/.organize_log.txt"])
        XCTAssertEqual(harness.finderService.revealedPaths, [
            "/tmp/destination/.organize_log.txt",
            "/Volumes/Card",
        ])
        XCTAssertEqual(route, .organize(.setup))
        XCTAssertEqual(harness.setupStore.sourcePath, "/Volumes/Card")
    }

    @MainActor
    func testUseHistoricalSourceReplacesAStaleFolderList() {
        let harness = AppStateHarness()
        let coordinator = HistoryCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            runSessionStore: harness.runSessionStore,
            deduplicateSessionStore: harness.deduplicateSessionStore,
            finderService: harness.finderService,
            navigate: { _ in }
        )

        harness.setupStore.setSourceItems([
            URL(fileURLWithPath: "/Volumes/Old/A"),
            URL(fileURLWithPath: "/Volumes/Old/B"),
        ])
        harness.setupStore.droppedSourceLabel = "2 folders"
        harness.setupStore.droppedSourceItemCount = 2
        harness.preferencesStore.manualSourceItemPaths = ["/Volumes/Old/A", "/Volumes/Old/B"]
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.sourceItem.0", path: "/Volumes/Old/A", data: Data([1])
        ))
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.sourceItem.1", path: "/Volumes/Old/B", data: Data([2])
        ))

        let record = TransferredSourceRecord(
            sourcePath: "/Volumes/Card",
            firstTransferredAt: Date(),
            lastTransferredAt: Date(),
            runCount: 1,
            lastCopiedCount: 10,
            totalCopiedCount: 10
        )
        coordinator.useHistoricalSource(record)

        XCTAssertEqual(harness.setupStore.sourceItems.map(\.path), ["/Volumes/Card"])
        XCTAssertFalse(harness.setupStore.usingDroppedSource)
        XCTAssertEqual(harness.setupStore.droppedSourceItemCount, 0)
        XCTAssertEqual(harness.preferencesStore.manualSourceItemPaths, ["/Volumes/Card"])
        XCTAssertTrue(harness.preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.").isEmpty)
    }

    /// The chosen folder's only saved authorization can be a folder-list
    /// bookmark. It must become `manual.source` before the list keys go, or
    /// the folder cannot be reopened after the session scope is dropped.
    @MainActor
    func testUseHistoricalSourceKeepsTheListBookmarkOfTheChosenFolder() {
        let harness = AppStateHarness()
        let coordinator = HistoryCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            runSessionStore: harness.runSessionStore,
            deduplicateSessionStore: harness.deduplicateSessionStore,
            finderService: harness.finderService,
            navigate: { _ in }
        )

        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.source", path: "/Volumes/Old/A", data: Data([9])
        ))
        harness.preferencesStore.manualSourceItemPaths = ["/Volumes/Old/A", "/Volumes/Old/B"]
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.sourceItem.0", path: "/Volumes/Old/A", data: Data([1])
        ))
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.sourceItem.1", path: "/Volumes/Old/B", data: Data([2])
        ))

        let record = TransferredSourceRecord(
            sourcePath: "/Volumes/Old/B",
            firstTransferredAt: Date(),
            lastTransferredAt: Date(),
            runCount: 1,
            lastCopiedCount: 10,
            totalCopiedCount: 10
        )
        coordinator.useHistoricalSource(record)

        let manual = harness.preferencesStore.bookmark(for: "manual.source")
        XCTAssertEqual(manual?.path, "/Volumes/Old/B")
        XCTAssertEqual(manual?.data, Data([2]), "The list bookmark carries the folder's authorization")
        XCTAssertTrue(harness.preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.").isEmpty)
        XCTAssertEqual(harness.setupStore.sourceItems.map(\.path), ["/Volumes/Old/B"])
    }

    /// Replacing the list from History tells Setup to drop the saved list's
    /// unreachable entries too, or its next edit would write them back.
    @MainActor
    func testUseHistoricalSourceReportsTheReplacedList() {
        let harness = AppStateHarness()
        var replacements = 0
        let coordinator = HistoryCoordinator(
            preferencesStore: harness.preferencesStore,
            setupStore: harness.setupStore,
            historyStore: harness.historyStore,
            runSessionStore: harness.runSessionStore,
            deduplicateSessionStore: harness.deduplicateSessionStore,
            finderService: harness.finderService,
            navigate: { _ in },
            didReplaceSourceList: { replacements += 1 }
        )
        let record = TransferredSourceRecord(
            sourcePath: "/Volumes/Card",
            firstTransferredAt: Date(),
            lastTransferredAt: Date(),
            runCount: 1,
            lastCopiedCount: 10,
            totalCopiedCount: 10
        )

        coordinator.useHistoricalSource(record)

        XCTAssertEqual(replacements, 1)
    }
}
