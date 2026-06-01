import Foundation
import XCTest
@testable import ChronoframeAppCore

/// Covers `TransferredSourcesLog` — the JSON-backed record of which source
/// paths have been transferred into a destination. The type is pure file I/O
/// (no AppKit) but had no dedicated unit test; the load → record → merge →
/// remove round trip and its guard clauses were unexercised.
final class TransferredSourcesLogTests: XCTestCase {
    private var destinationRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        destinationRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("TransferredSourcesLogTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let destinationRoot {
            try? FileManager.default.removeItem(at: destinationRoot)
        }
        destinationRoot = nil
        try super.tearDownWithError()
    }

    func testLoadReturnsEmptyWhenNoFileExists() {
        let log = TransferredSourcesLog()
        XCTAssertTrue(log.load(destinationRoot: destinationRoot.path).isEmpty)
    }

    func testFileURLIsNilForBlankDestinationRoot() {
        let log = TransferredSourcesLog()
        XCTAssertNil(log.fileURL(forDestinationRoot: ""))
        XCTAssertNil(log.fileURL(forDestinationRoot: "   "))
    }

    func testFileURLUsesWellKnownFileName() throws {
        let log = TransferredSourcesLog()
        let url = try XCTUnwrap(log.fileURL(forDestinationRoot: destinationRoot.path))
        XCTAssertEqual(url.lastPathComponent, TransferredSourcesLog.fileName)
    }

    func testRecordTransferPersistsAndRoundTrips() {
        let log = TransferredSourcesLog()
        let when = Date(timeIntervalSince1970: 1_700_000_000)
        log.recordTransfer(
            sourcePath: "/Volumes/Card",
            destinationRoot: destinationRoot.path,
            copiedCount: 12,
            at: when
        )

        // Persisted to disk: a fresh log instance reads it back.
        let reloaded = TransferredSourcesLog().load(destinationRoot: destinationRoot.path)
        XCTAssertEqual(reloaded.count, 1)
        let record = reloaded[0]
        XCTAssertEqual(record.sourcePath, "/Volumes/Card")
        XCTAssertEqual(record.runCount, 1)
        XCTAssertEqual(record.lastCopiedCount, 12)
        XCTAssertEqual(record.totalCopiedCount, 12)
        XCTAssertEqual(record.firstTransferredAt, when)
        XCTAssertEqual(record.lastTransferredAt, when)
    }

    func testRecordTransferMergesExistingSourceAccumulatingCounts() {
        let log = TransferredSourcesLog()
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(3_600)

        log.recordTransfer(sourcePath: "/Volumes/Card", destinationRoot: destinationRoot.path, copiedCount: 10, at: first)
        let merged = log.recordTransfer(sourcePath: "/Volumes/Card", destinationRoot: destinationRoot.path, copiedCount: 5, at: second)

        XCTAssertEqual(merged.count, 1, "Re-transferring the same source updates one record rather than appending")
        let record = merged[0]
        XCTAssertEqual(record.runCount, 2)
        XCTAssertEqual(record.lastCopiedCount, 5)
        XCTAssertEqual(record.totalCopiedCount, 15)
        XCTAssertEqual(record.firstTransferredAt, first, "First-seen timestamp is preserved across merges")
        XCTAssertEqual(record.lastTransferredAt, second)
    }

    func testLoadSortsMostRecentlyTransferredFirst() {
        let log = TransferredSourcesLog()
        let older = Date(timeIntervalSince1970: 1_700_000_000)
        let newer = older.addingTimeInterval(86_400)

        log.recordTransfer(sourcePath: "/Volumes/Old", destinationRoot: destinationRoot.path, copiedCount: 1, at: older)
        log.recordTransfer(sourcePath: "/Volumes/New", destinationRoot: destinationRoot.path, copiedCount: 1, at: newer)

        let records = log.load(destinationRoot: destinationRoot.path)
        XCTAssertEqual(records.map(\.sourcePath), ["/Volumes/New", "/Volumes/Old"])
    }

    func testRecordTransferTrimsSourcePathWhitespace() {
        let log = TransferredSourcesLog()
        log.recordTransfer(sourcePath: "  /Volumes/Card  ", destinationRoot: destinationRoot.path, copiedCount: 1)
        let records = log.load(destinationRoot: destinationRoot.path)
        XCTAssertEqual(records.first?.sourcePath, "/Volumes/Card")
    }

    func testRecordTransferIgnoresBlankSourcePath() {
        let log = TransferredSourcesLog()
        let result = log.recordTransfer(sourcePath: "   ", destinationRoot: destinationRoot.path, copiedCount: 3)
        XCTAssertTrue(result.isEmpty)
        XCTAssertTrue(log.load(destinationRoot: destinationRoot.path).isEmpty, "A blank source writes nothing to disk")
    }

    func testRemoveRecordDropsOnlyTheNamedSource() {
        let log = TransferredSourcesLog()
        log.recordTransfer(sourcePath: "/Volumes/Keep", destinationRoot: destinationRoot.path, copiedCount: 1)
        log.recordTransfer(sourcePath: "/Volumes/Forget", destinationRoot: destinationRoot.path, copiedCount: 1)

        let remaining = log.removeRecord(sourcePath: "/Volumes/Forget", destinationRoot: destinationRoot.path)
        XCTAssertEqual(remaining.map(\.sourcePath), ["/Volumes/Keep"])

        // The removal is persisted, not just returned.
        XCTAssertEqual(
            TransferredSourcesLog().load(destinationRoot: destinationRoot.path).map(\.sourcePath),
            ["/Volumes/Keep"]
        )
    }

    func testRemoveRecordForUnknownSourceLeavesListIntact() {
        let log = TransferredSourcesLog()
        log.recordTransfer(sourcePath: "/Volumes/Card", destinationRoot: destinationRoot.path, copiedCount: 1)
        let remaining = log.removeRecord(sourcePath: "/Volumes/NeverSeen", destinationRoot: destinationRoot.path)
        XCTAssertEqual(remaining.map(\.sourcePath), ["/Volumes/Card"])
    }

    func testLoadReturnsEmptyForCorruptJSON() throws {
        let log = TransferredSourcesLog()
        let url = try XCTUnwrap(log.fileURL(forDestinationRoot: destinationRoot.path))
        try Data("not valid json".utf8).write(to: url)
        XCTAssertTrue(log.load(destinationRoot: destinationRoot.path).isEmpty)
    }
}
