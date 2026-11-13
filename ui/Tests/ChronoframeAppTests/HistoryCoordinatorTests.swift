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
}
