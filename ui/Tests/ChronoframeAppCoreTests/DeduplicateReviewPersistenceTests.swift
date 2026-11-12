import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// In-memory snapshot store: records every save and removal so the session
/// store's persistence timing can be asserted without touching the filesystem.
final class InMemoryDeduplicateReviewSnapshotStore: DeduplicateReviewSnapshotStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [String: DeduplicateReviewSnapshot] = [:]
    private var savedSnapshots: [DeduplicateReviewSnapshot] = []
    private var removedFolders: [String] = []

    var saves: [DeduplicateReviewSnapshot] {
        lock.lock(); defer { lock.unlock() }
        return savedSnapshots
    }

    var removals: [String] {
        lock.lock(); defer { lock.unlock() }
        return removedFolders
    }

    func preload(_ snapshot: DeduplicateReviewSnapshot) {
        lock.lock(); defer { lock.unlock() }
        snapshots[DeduplicateReviewKeys.folderKey(for: snapshot.folderPath)] = snapshot
    }

    func load(folderPath: String) -> DeduplicateReviewSnapshot? {
        lock.lock(); defer { lock.unlock() }
        return snapshots[DeduplicateReviewKeys.folderKey(for: folderPath)]
    }

    func save(_ snapshot: DeduplicateReviewSnapshot) throws {
        lock.lock(); defer { lock.unlock() }
        savedSnapshots.append(snapshot)
        snapshots[DeduplicateReviewKeys.folderKey(for: snapshot.folderPath)] = snapshot
    }

    func remove(folderPath: String) {
        lock.lock(); defer { lock.unlock() }
        removedFolders.append(folderPath)
        snapshots[DeduplicateReviewKeys.folderKey(for: folderPath)] = nil
    }
}

final class DeduplicateReviewPersistenceTests: XCTestCase {
    private let clusterID = UUID()
    private let configuration = DeduplicateConfiguration(destinationPath: "/dest")
    private let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)
    private let longDebounce: UInt64 = 60_000_000_000
    private let shortDebounce: UInt64 = 20_000_000

    private var file1: PhotoCandidate {
        PhotoCandidate(path: "/dest/file1.jpg", size: 100, modificationTime: 0)
    }

    private var file2: PhotoCandidate {
        PhotoCandidate(path: "/dest/file2.jpg", size: 100, modificationTime: 0)
    }

    /// file1 is the suggested keeper, file2 the suggested delete.
    private var cluster: DuplicateCluster {
        DuplicateCluster(
            id: clusterID,
            kind: .exactDuplicate,
            members: [file1, file2],
            suggestedKeeperIDs: [file1.path],
            bytesIfPruned: 100
        )
    }

    @MainActor
    private func makeStore(
        engine: MockDeduplicateEngine,
        snapshotStore: InMemoryDeduplicateReviewSnapshotStore,
        debounce: UInt64
    ) -> DeduplicateSessionStore {
        let suiteName = "DeduplicateReviewPersistenceTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName) ?? .standard
        defaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock { defaults.removePersistentDomain(forName: suiteName) }
        let fixedNow = self.fixedNow
        return DeduplicateSessionStore(
            engine: engine,
            runHistoryStore: UserDefaultsDeduplicateRunHistoryStore(defaults: defaults),
            reviewSnapshotStore: snapshotStore,
            now: { fixedNow },
            saveDebounceNanoseconds: debounce
        )
    }

    @MainActor
    private func scanToReview(_ store: DeduplicateSessionStore) async {
        store.startScan(configuration: configuration)
        let ready = await waitForCondition { store.status == .readyToReview }
        XCTAssertTrue(ready)
    }

    /// A saved review built from live state: file1 kept, file2 flipped to keep,
    /// the group approved and focused.
    private func savedReview(
        decisions: [String: DedupeDecision],
        approved: Bool,
        scanSnapshot: DeduplicateScanSnapshot
    ) -> DeduplicateReviewSnapshot {
        DeduplicateReviewRestorer.capture(
            folderPath: configuration.destinationPath,
            savedAt: fixedNow,
            configuration: configuration,
            decisions: DedupeDecisions(byPath: decisions),
            approvedClusterIDs: approved ? [clusterID] : [],
            clusters: [cluster],
            scanSnapshot: scanSnapshot,
            focusClusterID: clusterID
        )
    }

    @MainActor
    private func pump(timeout: TimeInterval = 3, until condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        return condition()
    }

    // MARK: - Saving

    @MainActor
    func testDecisionChangeSavesAfterDebounce() async throws {
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: shortDebounce
        )
        await scanToReview(store)
        XCTAssertEqual(snapshotStore.saves.count, 0, "Finishing a scan alone must not write a review.")

        store.setDecision(.keep, forPath: file2.path)
        store.approveCluster(clusterID)
        XCTAssertEqual(snapshotStore.saves.count, 0, "Saving is debounced, not synchronous.")

        let saved = await waitForCondition { snapshotStore.saves.count == 1 }
        XCTAssertTrue(saved)

        // Quiet after the burst: the two rapid changes collapsed into one save.
        try await Task.sleep(nanoseconds: 120_000_000)
        XCTAssertEqual(snapshotStore.saves.count, 1)

        let snapshot = try XCTUnwrap(snapshotStore.saves.first)
        XCTAssertEqual(snapshot.folderPath, "/dest")
        XCTAssertEqual(snapshot.savedAt, fixedNow)
        XCTAssertEqual(snapshot.configurationFingerprint, configuration.reviewFingerprint)
        XCTAssertEqual(snapshot.decisions.first { $0.path == file2.path }?.decision, .keep)
        XCTAssertEqual(snapshot.approvals.count, 1)
    }

    @MainActor
    func testPauseSavesImmediately() async throws {
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: longDebounce
        )
        await scanToReview(store)
        store.setDecision(.keep, forPath: file2.path)
        XCTAssertEqual(snapshotStore.saves.count, 0)

        store.pauseReview()

        XCTAssertEqual(snapshotStore.saves.count, 1, "Pausing must save synchronously, without waiting for the debounce.")
        XCTAssertEqual(snapshotStore.saves.first?.decisions.first { $0.path == file2.path }?.decision, .keep)
        XCTAssertEqual(store.status, .idle)
    }

    @MainActor
    func testCancelSavesImmediately() async throws {
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: longDebounce
        )
        await scanToReview(store)
        store.setDecision(.keep, forPath: file2.path)

        store.cancel()

        XCTAssertEqual(snapshotStore.saves.count, 1)
        XCTAssertEqual(snapshotStore.saves.first?.decisions.first { $0.path == file2.path }?.decision, .keep)
    }

    @MainActor
    func testResetSavesBeforeClearing() async throws {
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: longDebounce
        )
        await scanToReview(store)
        store.setDecision(.keep, forPath: file2.path)
        store.reviewFocusClusterID = clusterID

        store.reset()

        XCTAssertEqual(snapshotStore.saves.count, 1, "Abandoning a review must not lose it.")
        let snapshot = try XCTUnwrap(snapshotStore.saves.first)
        XCTAssertEqual(snapshot.decisions.first { $0.path == file2.path }?.decision, .keep)
        XCTAssertEqual(snapshot.approvals.count, 1)
        XCTAssertNotNil(snapshot.focusGroupKey)
        XCTAssertTrue(store.clusters.isEmpty)
        XCTAssertTrue(store.decisions.byPath.isEmpty)
        XCTAssertTrue(store.approvedClusterIDs.isEmpty)
        XCTAssertNil(store.restoredReview)
        XCTAssertNil(store.reviewFocusClusterID)
    }

    @MainActor
    func testFlushPendingSaveWritesImmediately() async throws {
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: 50_000_000
        )

        store.flushPendingReviewSave()
        XCTAssertEqual(snapshotStore.saves.count, 0, "With no review in progress there is nothing to save.")

        await scanToReview(store)
        store.setDecision(.keep, forPath: file2.path)
        XCTAssertEqual(snapshotStore.saves.count, 0)

        store.flushPendingReviewSave()
        XCTAssertEqual(snapshotStore.saves.count, 1)

        // The pending debounce was cancelled, so it does not save a second time.
        try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertEqual(snapshotStore.saves.count, 1)
    }

    @MainActor
    func testUntouchedReviewIsNotSaved() async throws {
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: longDebounce
        )
        await scanToReview(store)

        store.pauseReview()
        XCTAssertEqual(store.status, .idle)
        store.flushPendingReviewSave()
        XCTAssertEqual(snapshotStore.saves.count, 0, "Untouched suggestions are not a review worth saving.")

        store.resumePausedReview()
        store.cancel()
        XCTAssertEqual(snapshotStore.saves.count, 0)

        store.reset()
        XCTAssertEqual(snapshotStore.saves.count, 0)

        // Separately: a scan, then reset, with no user action.
        await scanToReview(store)
        store.reset()
        XCTAssertEqual(snapshotStore.saves.count, 0)
    }

    @MainActor
    func testRestoredReviewIsSavedAgainOnPause() async throws {
        let engine = MockDeduplicateEngine(clusters: [cluster])
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        snapshotStore.preload(savedReview(
            decisions: [file1.path: .keep, file2.path: .keep],
            approved: true,
            scanSnapshot: engine.summary.scanSnapshot
        ))
        let store = makeStore(engine: engine, snapshotStore: snapshotStore, debounce: longDebounce)
        await scanToReview(store)
        XCTAssertNotNil(store.restoredReview)
        XCTAssertEqual(snapshotStore.saves.count, 0)

        store.pauseReview()

        XCTAssertEqual(snapshotStore.saves.count, 1, "Restored work must not be lost when the user leaves again.")
        XCTAssertEqual(snapshotStore.saves.first?.decisions.first { $0.path == file2.path }?.decision, .keep)
        XCTAssertEqual(snapshotStore.saves.first?.approvals.count, 1)
    }

    @MainActor
    func testStartScanFlushesPendingSave() async throws {
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: longDebounce
        )
        await scanToReview(store)
        store.setDecision(.keep, forPath: file2.path)
        XCTAssertEqual(snapshotStore.saves.count, 0)

        store.startScan(configuration: configuration)

        XCTAssertEqual(snapshotStore.saves.count, 1, "A change inside the debounce window must survive a rescan.")
        XCTAssertEqual(snapshotStore.saves.first?.decisions.first { $0.path == file2.path }?.decision, .keep)
    }

    @MainActor
    func testUndoRedoTriggersSave() {
        // Synchronous on purpose: UndoManager inside an async XCTest method
        // crashes the Swift task allocator. The run loop is pumped instead.
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let store = makeStore(
            engine: MockDeduplicateEngine(clusters: [cluster]),
            snapshotStore: snapshotStore,
            debounce: shortDebounce
        )
        let undoManager = UndoManager()
        undoManager.groupsByEvent = false
        store.undoManager = undoManager
        store.startScan(configuration: configuration)
        XCTAssertTrue(pump { store.status == .readyToReview })

        func file2Decision() -> DedupeDecision? {
            snapshotStore.saves.last?.decisions.first { $0.path == file2.path }?.decision
        }

        undoManager.beginUndoGrouping()
        store.setDecision(.keep, forPath: file2.path)
        undoManager.endUndoGrouping()
        XCTAssertTrue(pump { snapshotStore.saves.count == 1 })
        XCTAssertEqual(file2Decision(), .keep)

        undoManager.undo()
        XCTAssertTrue(pump { snapshotStore.saves.count == 2 }, "Undo must schedule a save.")
        XCTAssertEqual(file2Decision(), .delete)
        XCTAssertEqual(snapshotStore.saves.last?.approvals.count, 0)

        undoManager.redo()
        XCTAssertTrue(pump { snapshotStore.saves.count == 3 }, "Redo must schedule a save.")
        XCTAssertEqual(file2Decision(), .keep)
        XCTAssertEqual(snapshotStore.saves.last?.approvals.count, 1)
    }

    // MARK: - Restoring

    // AGENTS-INVARIANT: 29
    @MainActor
    func testCompleteRestoresMatchingDecisionsAndApprovals() async throws {
        let engine = MockDeduplicateEngine(clusters: [cluster])
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        snapshotStore.preload(savedReview(
            decisions: [file1.path: .keep, file2.path: .keep],
            approved: true,
            scanSnapshot: engine.summary.scanSnapshot
        ))
        let store = makeStore(engine: engine, snapshotStore: snapshotStore, debounce: longDebounce)

        await scanToReview(store)

        XCTAssertEqual(store.decisions.byPath[file1.path], .keep)
        XCTAssertEqual(store.decisions.byPath[file2.path], .keep, "The saved choice overrides the suggestion (delete).")
        XCTAssertEqual(store.approvedClusterIDs, [clusterID])
        XCTAssertEqual(store.reviewFocusClusterID, clusterID)
        let restoration = try XCTUnwrap(store.restoredReview)
        XCTAssertEqual(restoration.restoredDecisionCount, 2)
        XCTAssertEqual(restoration.droppedDecisionCount, 0)
        XCTAssertEqual(restoration.restoredGroupCount, 1)
        XCTAssertEqual(restoration.changedGroupCount, 0)
        XCTAssertFalse(restoration.settingsChanged)
        XCTAssertEqual(restoration.savedAt, fixedNow)
        XCTAssertFalse(store.hasRestoredChanges)
        XCTAssertFalse(store.decisions.hardDelete)
        XCTAssertEqual(snapshotStore.saves.count, 0, "Restoring must not itself write a save.")

        // A new scan starts from a clean slate.
        store.startScan(configuration: configuration)
        XCTAssertNil(store.restoredReview)
        XCTAssertNil(store.reviewFocusClusterID)
    }

    // AGENTS-INVARIANT: 29
    @MainActor
    func testCompleteDropsChangedIdentityAndReportsIt() async throws {
        let original = MockDeduplicateEngine(clusters: [cluster])
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        // The user flipped file2 to keep and approved the group.
        snapshotStore.preload(savedReview(
            decisions: [file1.path: .keep, file2.path: .keep],
            approved: true,
            scanSnapshot: original.summary.scanSnapshot
        ))

        // file2's content changed since: its identity differs in the new scan.
        var changedSummary = DeduplicateSummary()
        changedSummary.scanSnapshot = testScanSnapshot(
            for: [cluster],
            additionalIdentities: [file2.path: FileIdentity(size: 100, digest: "edited-after-review")]
        )
        let engine = MockDeduplicateEngine(clusters: [cluster], summary: changedSummary)
        let store = makeStore(engine: engine, snapshotStore: snapshotStore, debounce: longDebounce)

        await scanToReview(store)

        XCTAssertEqual(store.decisions.byPath[file1.path], .keep)
        XCTAssertEqual(
            store.decisions.byPath[file2.path], .delete,
            "A changed file loses its saved choice and falls back to the suggestion."
        )
        XCTAssertTrue(store.approvedClusterIDs.isEmpty, "A group with a changed member needs another look.")
        let restoration = try XCTUnwrap(store.restoredReview)
        XCTAssertEqual(restoration.restoredDecisionCount, 1)
        XCTAssertEqual(restoration.droppedDecisionCount, 1)
        XCTAssertEqual(restoration.restoredGroupCount, 0)
        XCTAssertEqual(restoration.changedGroupCount, 1)
        XCTAssertTrue(store.hasRestoredChanges)
        XCTAssertTrue(store.reviewedDeletionPlan().items.isEmpty)
    }

    // AGENTS-INVARIANT: 17
    @MainActor
    func testRestoredApprovalStillRequiresPrepareAndCommit() async throws {
        let engine = MockDeduplicateEngine(
            clusters: [cluster],
            commitEvents: [
                .complete(DeduplicateCommitSummary(
                    deletedCount: 1,
                    failedCount: 0,
                    bytesReclaimed: 100,
                    receiptPath: "/dest/.organize_logs/dedupe_audit_receipt.json",
                    hardDelete: false
                )),
            ]
        )
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        snapshotStore.preload(savedReview(
            decisions: [file1.path: .keep, file2.path: .delete],
            approved: true,
            scanSnapshot: engine.summary.scanSnapshot
        ))
        let store = makeStore(engine: engine, snapshotStore: snapshotStore, debounce: longDebounce)

        await scanToReview(store)

        // Restoring only repopulates review state: nothing is prepared or committed.
        XCTAssertEqual(store.approvedClusterIDs, [clusterID])
        XCTAssertNil(store.preparedCommitPlan)
        XCTAssertNil(engine.lastCommitPlan)
        XCTAssertEqual(store.status, .readyToReview)

        let expected = DeduplicationPlanner.plan(
            decisions: store.decisions,
            clusters: [cluster],
            configuration: configuration,
            snapshot: engine.summary.scanSnapshot
        )
        XCTAssertEqual(store.reviewedDeletionPlan(), expected)
        XCTAssertEqual(expected.count, 1)

        // The explicit steps still happen, and the executor receives the frozen plan.
        let prepared = store.prepareReviewedCommitPlan()
        XCTAssertEqual(prepared, expected)
        XCTAssertNil(engine.lastCommitPlan)
        store.commitReviewed(configuration: configuration)
        XCTAssertEqual(engine.lastCommitPlan, prepared)
        let completed = await waitForCondition { store.status == .completed }
        XCTAssertTrue(completed)
    }

    // MARK: - Removing

    @MainActor
    func testCommitCompleteRemovesSnapshot() async throws {
        let engine = MockDeduplicateEngine(
            clusters: [cluster],
            commitEvents: [
                .complete(DeduplicateCommitSummary(
                    deletedCount: 1,
                    failedCount: 0,
                    bytesReclaimed: 100,
                    receiptPath: "/dest/.organize_logs/dedupe_audit_receipt.json",
                    hardDelete: false
                )),
            ]
        )
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        snapshotStore.preload(savedReview(
            decisions: [file1.path: .keep, file2.path: .delete],
            approved: true,
            scanSnapshot: engine.summary.scanSnapshot
        ))
        let store = makeStore(engine: engine, snapshotStore: snapshotStore, debounce: longDebounce)
        await scanToReview(store)
        store.refreshSavedReview(folderPath: "/dest")
        XCTAssertNotNil(store.restoredReview)
        XCTAssertNotNil(store.savedReviewForCurrentFolder)
        XCTAssertTrue(snapshotStore.removals.isEmpty)

        store.commitReviewed(configuration: configuration)
        let completed = await waitForCondition { store.status == .completed }
        XCTAssertTrue(completed)

        XCTAssertEqual(snapshotStore.removals, ["/dest"])
        XCTAssertNil(snapshotStore.load(folderPath: "/dest"))
        XCTAssertNil(store.restoredReview)
        XCTAssertNil(store.savedReviewForCurrentFolder)
    }

    @MainActor
    func testDiscardSavedReviewRemovesFile() async throws {
        let engine = MockDeduplicateEngine(clusters: [cluster])
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        snapshotStore.preload(savedReview(
            decisions: [file1.path: .keep, file2.path: .keep],
            approved: true,
            scanSnapshot: engine.summary.scanSnapshot
        ))
        let store = makeStore(engine: engine, snapshotStore: snapshotStore, debounce: longDebounce)
        store.refreshSavedReview(folderPath: "/dest")
        XCTAssertNotNil(store.savedReviewForCurrentFolder)

        store.discardSavedReview(folderPath: "/dest")

        XCTAssertEqual(snapshotStore.removals, ["/dest"])
        XCTAssertNil(snapshotStore.load(folderPath: "/dest"))
        XCTAssertNil(store.savedReviewForCurrentFolder)
    }

    @MainActor
    func testRefreshSavedReviewLoadsForFolder() async throws {
        let engine = MockDeduplicateEngine(clusters: [cluster])
        let snapshotStore = InMemoryDeduplicateReviewSnapshotStore()
        let saved = savedReview(
            decisions: [file1.path: .keep, file2.path: .keep],
            approved: true,
            scanSnapshot: engine.summary.scanSnapshot
        )
        snapshotStore.preload(saved)
        let store = makeStore(engine: engine, snapshotStore: snapshotStore, debounce: longDebounce)
        XCTAssertNil(store.savedReviewForCurrentFolder)

        store.refreshSavedReview(folderPath: "/dest")
        XCTAssertEqual(store.savedReviewForCurrentFolder, saved)

        store.refreshSavedReview(folderPath: "/elsewhere")
        XCTAssertNil(store.savedReviewForCurrentFolder, "A folder with no saved review shows no card.")
        XCTAssertNotNil(snapshotStore.load(folderPath: "/dest"), "Changing folder never removes a saved review.")
    }
}
