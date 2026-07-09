import Foundation
import XCTest
@testable import ChronoframeAppCore

final class WatchedSourcesRepositoryTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var databaseURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchedSourcesRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        databaseURL = temporaryDirectoryURL.appendingPathComponent("watched_sources.db")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        databaseURL = nil
        try super.tearDownWithError()
    }

    private func stamp(size: Int64 = 1, mtime: Int64 = 1, ctime: Int64 = 1) -> WatchedFileStamp {
        WatchedFileStamp(sizeBytes: size, mtimeNanoseconds: mtime, ctimeNanoseconds: ctime)
    }

    func testAddLoadRemoveRoundTripWithSeededCheckpoint() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        let source = WatchedSource(path: "/Volumes/Card/DCIM", label: "SD Card")

        try repository.addSource(source, initialCheckpoint: ["a.jpg": stamp(), "sub/b.mov": stamp(size: 2)])

        let loaded = try repository.loadSources()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, source.id)
        XCTAssertEqual(loaded[0].path, "/Volumes/Card/DCIM")
        XCTAssertEqual(loaded[0].label, "SD Card")
        XCTAssertEqual(loaded[0].changeGeneration, 0)

        let checkpoint = try repository.checkpoint(for: source.id)
        XCTAssertEqual(checkpoint["a.jpg"], stamp())
        XCTAssertEqual(checkpoint["sub/b.mov"], stamp(size: 2))

        try repository.removeSource(id: source.id)
        XCTAssertTrue(try repository.loadSources().isEmpty)
        XCTAssertTrue(try repository.checkpoint(for: source.id).isEmpty,
                      "Removal must drop the checkpoint rows in the same transaction")
    }

    func testStatePersistsAcrossReopen() throws {
        let source = WatchedSource(path: "/Users/me/Downloads", label: "Downloads")
        do {
            let repository = WatchedSourcesRepository(databaseURL: databaseURL)
            try repository.addSource(source, initialCheckpoint: ["x.jpg": stamp(mtime: 42)])
            try repository.bumpChangeGeneration(id: source.id)
        }

        let reopened = WatchedSourcesRepository(databaseURL: databaseURL)
        let loaded = try reopened.loadSources()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].changeGeneration, 1)
        XCTAssertEqual(try reopened.checkpoint(for: source.id)["x.jpg"], stamp(mtime: 42))
    }

    func testReplaceCheckpointRewritesAtomically() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        let source = WatchedSource(path: "/p", label: "p")
        try repository.addSource(source, initialCheckpoint: ["old.jpg": stamp()])

        try repository.replaceCheckpoint(for: source.id, entries: ["new.jpg": stamp(size: 9)])

        let checkpoint = try repository.checkpoint(for: source.id)
        XCTAssertEqual(Array(checkpoint.keys), ["new.jpg"])

        try repository.replaceCheckpoint(for: source.id, entries: [:])
        XCTAssertTrue(try repository.checkpoint(for: source.id).isEmpty)
    }

    func testReplaceSourcePathKeepsOrClearsCheckpoint() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        let source = WatchedSource(path: "/old", label: "folder")
        try repository.addSource(source, initialCheckpoint: ["k.jpg": stamp()])

        // Same tree re-picked at the same path: checkpoint survives.
        try repository.replaceSourcePath(id: source.id, newPath: "/old", clearCheckpoint: false)
        XCTAssertEqual(try repository.checkpoint(for: source.id).count, 1)

        // Genuinely different path: acknowledgments describe another
        // tree and are cleared in the same transaction.
        try repository.replaceSourcePath(id: source.id, newPath: "/new", clearCheckpoint: true)
        XCTAssertEqual(try repository.loadSources()[0].path, "/new")
        XCTAssertTrue(try repository.checkpoint(for: source.id).isEmpty)
    }

    func testReplaceSourcePathForUnknownIDThrowsSourceNotFound() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        XCTAssertThrowsError(
            try repository.replaceSourcePath(id: UUID(), newPath: "/x", clearCheckpoint: false)
        ) { error in
            guard case WatchedSourceDatabaseError.sourceNotFound = error else {
                return XCTFail("Expected sourceNotFound, got \(error)")
            }
        }
    }

    func testBumpChangeGenerationIncrementsMonotonically() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        let source = WatchedSource(path: "/p", label: "p")
        try repository.addSource(source, initialCheckpoint: [:])

        XCTAssertEqual(try repository.bumpChangeGeneration(id: source.id), 1)
        XCTAssertEqual(try repository.bumpChangeGeneration(id: source.id), 2)
        XCTAssertEqual(try repository.loadSources()[0].changeGeneration, 2)
    }

    func testBumpChangeGenerationForUnknownIDThrows() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        XCTAssertThrowsError(try repository.bumpChangeGeneration(id: UUID())) { error in
            guard case WatchedSourceDatabaseError.sourceNotFound = error else {
                return XCTFail("Expected sourceNotFound, got \(error)")
            }
        }
    }

    /// A duplicate-ID insert fails inside the transaction; the registry
    /// row count and the existing checkpoint must be untouched (no
    /// partial rows from the failed transaction's checkpoint seeding).
    func testFailedAddRollsBackWithoutPartialState() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        let source = WatchedSource(path: "/p", label: "p")
        try repository.addSource(source, initialCheckpoint: ["original.jpg": stamp()])

        var duplicate = source
        duplicate.path = "/other"
        XCTAssertThrowsError(
            try repository.addSource(duplicate, initialCheckpoint: ["poison.jpg": stamp()])
        )

        let loaded = try repository.loadSources()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].path, "/p", "Failed add must not mutate the existing row")
        let checkpoint = try repository.checkpoint(for: source.id)
        XCTAssertEqual(Array(checkpoint.keys), ["original.jpg"],
                       "Failed transaction must leave no partial checkpoint rows")
    }

    /// A corrupt store is quarantined aside and surfaced — never
    /// silently treated as empty-and-fine.
    func testCorruptStoreIsQuarantinedAndSurfaced() throws {
        try Data("this is not a sqlite database, not even close".utf8).write(to: databaseURL)

        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        XCTAssertTrue(try repository.loadSources().isEmpty, "Fresh store starts empty")
        XCTAssertTrue(repository.didQuarantineCorruptStore,
                      "Corruption must be surfaced so the UI can tell the user")

        let siblings = try FileManager.default.contentsOfDirectory(atPath: temporaryDirectoryURL.path)
        XCTAssertTrue(
            siblings.contains { $0.hasPrefix("watched_sources.db.corrupt-") },
            "Corrupt store must be preserved aside, not deleted; found: \(siblings)"
        )

        // The fresh store is fully functional.
        let source = WatchedSource(path: "/p", label: "p")
        try repository.addSource(source, initialCheckpoint: [:])
        XCTAssertEqual(try repository.loadSources().count, 1)
    }

    func testHealthyStoreDoesNotReportQuarantine() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        _ = try repository.loadSources()
        XCTAssertFalse(repository.didQuarantineCorruptStore)
    }

    /// Checkpoints hold the 100k-order row counts the design targets;
    /// this smaller pass pins the batched-transaction write path (one
    /// transaction, reused prepared statement) at a size CI can afford.
    func testCheckpointHandlesManyRows() throws {
        let repository = WatchedSourcesRepository(databaseURL: databaseURL)
        let source = WatchedSource(path: "/big", label: "big")
        var entries: [String: WatchedFileStamp] = [:]
        for index in 0..<5_000 {
            entries["dir\(index % 50)/IMG_\(index).jpg"] = stamp(size: Int64(index), mtime: Int64(index))
        }

        try repository.addSource(source, initialCheckpoint: entries)
        XCTAssertEqual(try repository.checkpoint(for: source.id).count, 5_000)

        entries["extra.jpg"] = stamp()
        try repository.replaceCheckpoint(for: source.id, entries: entries)
        XCTAssertEqual(try repository.checkpoint(for: source.id).count, 5_001)
    }
}
