import Foundation
import XCTest
@testable import ChronoframeAppCore

@MainActor
final class HistoryStoreTests: XCTestCase {
    func testPermissionFailurePreservesSnapshotAndReconnectRefreshClearsError() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let entry = RunHistoryEntry(kind: .runLog, title: "Run Log", path: root.appendingPathComponent("old.log").path, createdAt: .now)
        let source = TransferredSourceRecord(sourcePath: "/Card", firstTransferredAt: .now, lastTransferredAt: .now, runCount: 1, lastCopiedCount: 344, totalCopiedCount: 344)
        let indexer = RetryingHistoryIndexer(entries: [entry])
        let store = HistoryStore(entries: [entry], transferredSources: [source], destinationRoot: root.path, indexer: indexer)
        let tracker = SecurityScopeCloseTracker()
        var requestedRoots: [String] = []
        store.setDestinationScopeProvider { path in
            requestedRoots.append(path)
            return tracker.makeScope()
        }
        await store.refresh(destinationRoot: root.path)
        XCTAssertEqual(store.entries, [entry])
        XCTAssertEqual(store.transferredSources, [source])
        XCTAssertTrue(store.needsFolderAccess)
        XCTAssertNotNil(store.lastRefreshError)
        XCTAssertEqual(tracker.closeCount, 1)

        await store.refresh(destinationRoot: root.path)
        XCTAssertEqual(store.entries, [entry])
        XCTAssertFalse(store.needsFolderAccess)
        XCTAssertNil(store.lastRefreshError)
        XCTAssertEqual(requestedRoots, [root.path, root.path])
        XCTAssertEqual(tracker.closeCount, 2)
    }

    func testChangingArchiveClearsPreviousSnapshot() {
        let entry = RunHistoryEntry(kind: .runLog, title: "Old", path: "/old/log", createdAt: .now)
        let store = HistoryStore(entries: [entry], destinationRoot: "/old")
        store.setDestinationRoot("/new")
        XCTAssertTrue(store.entries.isEmpty)
        XCTAssertEqual(store.destinationRoot, "/new")
    }

    func testRefreshUsesIndexerResults() async {
        let entries = [
            RunHistoryEntry(
                kind: .queueDatabase,
                title: "Queue Database",
                path: "/tmp/run/.organize_cache.db",
                relativePath: ".organize_cache.db",
                fileSizeBytes: 4_096,
                createdAt: Date(timeIntervalSince1970: 30)
            ),
            RunHistoryEntry(
                kind: .auditReceipt,
                title: "Audit Receipt",
                path: "/tmp/run/.organize_logs/audit_receipt.json",
                relativePath: ".organize_logs/audit_receipt.json",
                fileSizeBytes: 512,
                createdAt: Date(timeIntervalSince1970: 20)
            ),
        ]
        let indexer = MockRunHistoryIndexer(result: .success(entries))

        let store = HistoryStore(indexer: indexer)
        await store.refresh(destinationRoot: "/tmp/run")

        XCTAssertEqual(store.entries, entries)
        XCTAssertEqual(store.destinationRoot, "/tmp/run")
        XCTAssertNil(store.lastRefreshError)
    }

    func testRemoveEntryTrashesFileAndRemovesFromList() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("audit_receipt.json")
        try Data("{}".utf8).write(to: fileURL)

        let entry = RunHistoryEntry(
            kind: .auditReceipt,
            title: "Audit Receipt",
            path: fileURL.path,
            relativePath: "audit_receipt.json",
            fileSizeBytes: 2,
            createdAt: .now
        )
        let store = HistoryStore(entries: [entry], trashItem: { url in
            try FileManager.default.removeItem(at: url)
        })
        store.remove(entry: entry)

        XCTAssertTrue(store.entries.isEmpty, "Entry should be removed from the in-memory list")
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path),
                       "File should no longer exist at its original path after trashing")
    }

    func testRemoveNonexistentEntryIsIdempotent() {
        let entry = RunHistoryEntry(
            kind: .runLog, title: "Gone", path: "/nonexistent/file.log", createdAt: .now
        )
        let store = HistoryStore(entries: [entry])
        // Should not throw even if file doesn't exist.
        store.remove(entry: entry)
        XCTAssertTrue(store.entries.isEmpty)
    }

    func testRemoveEntryKeepsItemAndReportsFriendlyErrorWhenTrashFails() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("audit_receipt.json")
        try Data("{}".utf8).write(to: fileURL)
        let entry = RunHistoryEntry(
            kind: .auditReceipt,
            title: "Audit Receipt",
            path: fileURL.path,
            relativePath: "audit_receipt.json",
            fileSizeBytes: 2,
            createdAt: .now
        )
        let store = HistoryStore(
            entries: [entry],
            trashItem: { _ in throw TestFailure.expectedFailure("Trash is unavailable") }
        )

        store.remove(entry: entry)

        XCTAssertEqual(store.entries, [entry])
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path))
        XCTAssertEqual(
            store.lastRefreshError,
            "Chronoframe could not move this history item to Trash. Open it in Finder and remove it manually. Details: Trash is unavailable"
        )
    }

    func testRemoveAllTrashesAllFilesAndClearsList() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var entries: [RunHistoryEntry] = []
        for i in 1...3 {
            let url = tempDir.appendingPathComponent("file_\(i).json")
            try Data("{}".utf8).write(to: url)
            entries.append(RunHistoryEntry(kind: .auditReceipt, title: "Entry \(i)", path: url.path, createdAt: .now))
        }
        let store = HistoryStore(entries: entries, trashItem: { url in
            try FileManager.default.removeItem(at: url)
        })
        store.removeAll()

        XCTAssertTrue(store.entries.isEmpty, "All entries should be removed")
        for entry in entries {
            XCTAssertFalse(FileManager.default.fileExists(atPath: entry.path),
                           "File should no longer exist: \(entry.path)")
        }
    }

    func testRemoveAllKeepsFailedItemsAndReportsCount() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let failedURL = tempDir.appendingPathComponent("failed.json")
        let removedURL = tempDir.appendingPathComponent("removed.json")
        try Data("{}".utf8).write(to: failedURL)
        try Data("{}".utf8).write(to: removedURL)

        let failedEntry = RunHistoryEntry(kind: .auditReceipt, title: "Failed", path: failedURL.path, createdAt: .now)
        let removedEntry = RunHistoryEntry(kind: .auditReceipt, title: "Removed", path: removedURL.path, createdAt: .now)
        let store = HistoryStore(
            entries: [failedEntry, removedEntry],
            trashItem: { url in
                if url.lastPathComponent == failedURL.lastPathComponent {
                    throw TestFailure.expectedFailure("Trash is unavailable")
                }
                try FileManager.default.removeItem(at: url)
            }
        )

        store.removeAll()

        XCTAssertEqual(store.entries, [failedEntry])
        XCTAssertTrue(FileManager.default.fileExists(atPath: failedURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))
        XCTAssertEqual(
            store.lastRefreshError,
            "Chronoframe could not move 1 history item to Trash. Open the destination in Finder and remove them manually."
        )
    }

    /// Phase 1 finding #4 regression: `refresh("")` (called on
    /// profile-clear and similar setup-clearing flows) must NOT wipe a
    /// previously-loaded valid `destinationRoot`. Downstream callers
    /// (revert, transferred-sources log) treat
    /// `historyStore.destinationRoot` as the implicit "where receipts
    /// live" handle and break when it's silently zeroed.
    func testRefreshDoesNotWipePreviouslyLoadedDestinationRootForEmptyInput() async {
        let indexer = MockRunHistoryIndexer(result: .success([
            RunHistoryEntry(kind: .runLog, title: "Run Log", path: "/tmp/run.log", createdAt: .distantPast)
        ]))
        let store = HistoryStore(indexer: indexer)
        await store.refresh(destinationRoot: "/Volumes/Archive")
        XCTAssertEqual(store.destinationRoot, "/Volumes/Archive")

        // Both empty and whitespace-only inputs must be no-ops.
        await store.refresh(destinationRoot: "")
        XCTAssertEqual(store.destinationRoot, "/Volumes/Archive")
        await store.refresh(destinationRoot: "   ")
        XCTAssertEqual(store.destinationRoot, "/Volumes/Archive")
    }

    func testRefreshRecordsIndexerFailures() async {
        let indexer = MockRunHistoryIndexer(result: .failure(MockRunHistoryIndexer.Error.sample))
        let store = HistoryStore(
            entries: [
                RunHistoryEntry(kind: .runLog, title: "Run Log", path: "/tmp/old.log", createdAt: .distantPast)
            ],
            indexer: indexer
        )

        await store.refresh(destinationRoot: "/tmp/run")

        XCTAssertEqual(store.entries, [])
        XCTAssertEqual(store.destinationRoot, "/tmp/run")
        XCTAssertEqual(
            store.lastRefreshError,
            "Chronoframe could not refresh Run History. Check that the destination drive is connected, then try again. Details: History index failed"
        )
    }
}

private final class RetryingHistoryIndexer: RunHistoryIndexing, @unchecked Sendable {
    private let lock = NSLock()
    private var attempts = 0
    let entries: [RunHistoryEntry]
    init(entries: [RunHistoryEntry]) { self.entries = entries }
    func index(destinationRoot: String) throws -> [RunHistoryEntry] {
        lock.lock()
        defer { lock.unlock() }
        attempts += 1
        if attempts == 1 { throw NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES)) }
        return entries
    }
}

private struct MockRunHistoryIndexer: RunHistoryIndexing, @unchecked Sendable {
    enum Error: LocalizedError {
        case sample

        var errorDescription: String? {
            "History index failed"
        }
    }

    let result: Result<[RunHistoryEntry], Swift.Error>

    func index(destinationRoot: String) throws -> [RunHistoryEntry] {
        try result.get()
    }
}
