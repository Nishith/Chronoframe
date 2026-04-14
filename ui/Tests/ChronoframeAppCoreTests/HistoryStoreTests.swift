import Foundation
import XCTest
@testable import ChronoframeAppCore

final class HistoryStoreTests: XCTestCase {
    func testRefreshUsesIndexerResults() {
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
        store.refresh(destinationRoot: "/tmp/run")

        XCTAssertEqual(store.entries, entries)
        XCTAssertEqual(store.destinationRoot, "/tmp/run")
        XCTAssertNil(store.lastRefreshError)
    }

    func testRefreshRecordsIndexerFailures() {
        let indexer = MockRunHistoryIndexer(result: .failure(MockRunHistoryIndexer.Error.sample))
        let store = HistoryStore(
            entries: [
                RunHistoryEntry(kind: .runLog, title: "Run Log", path: "/tmp/old.log", createdAt: .distantPast)
            ],
            indexer: indexer
        )

        store.refresh(destinationRoot: "/tmp/run")

        XCTAssertEqual(store.entries, [])
        XCTAssertEqual(store.destinationRoot, "/tmp/run")
        XCTAssertEqual(store.lastRefreshError, MockRunHistoryIndexer.Error.sample.localizedDescription)
    }
}

private struct MockRunHistoryIndexer: RunHistoryIndexing {
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
