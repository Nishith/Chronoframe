import Foundation
import SQLite3
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreNASAssessmentStoreTests: XCTestCase {
    private var directory: URL!
    private let libraryUUID = "11111111-2222-3333-4444-555555555555"

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASAssessmentStore-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var storeURL: URL { directory.appendingPathComponent("assessment.sqlite") }

    private func makeStore(uuid: String? = nil) throws -> NASAssessmentStore {
        try NASAssessmentStore(url: storeURL, libraryUUID: uuid ?? libraryUUID)
    }

    private func item(
        _ path: String,
        size: Int64,
        digest: String? = nil,
        state: NASItemHashState = .notCandidate,
        reason: NASUnresolvedReason? = nil,
        fileID: UInt64 = 1,
        kind: NASItemKind = .photo
    ) -> NASItemRow {
        NASItemRow(
            relativePath: path,
            kind: kind,
            size: size,
            modificationTime: 1_700_000_000,
            fileID: fileID,
            digest: digest,
            hashState: state,
            unresolvedReason: reason
        )
    }

    private func rawStrings(_ sql: String) -> [String] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(storeURL.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var values: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let text = sqlite3_column_text(statement, 0) {
                values.append(String(cString: text))
            }
        }
        return values
    }

    func testCreatesSchemaAndMeta() throws {
        let store = try makeStore()
        store.close()

        let tables = rawStrings("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;")
        for expected in ["Directories", "Issues", "Items", "Meta", "ReviewChoices", "ReviewState", "Scans"] {
            XCTAssertTrue(tables.contains(expected), "missing table \(expected)")
        }
        let indexes = rawStrings("SELECT name FROM sqlite_master WHERE type='index';")
        XCTAssertTrue(indexes.contains("ItemsBySize"))
        XCTAssertTrue(indexes.contains("ItemsByDigest"))
        XCTAssertEqual(rawStrings("SELECT value FROM Meta WHERE key='schemaVersion';"), ["1"])
        XCTAssertEqual(rawStrings("SELECT value FROM Meta WHERE key='libraryUUID';"), [libraryUUID])
        XCTAssertEqual(NASAssessmentStore.algorithmVersion, 1)

        // Reopening with the same library is fine and keeps the meta rows.
        let reopened = try makeStore()
        reopened.close()
        XCTAssertEqual(rawStrings("SELECT value FROM Meta WHERE key='libraryUUID';"), [libraryUUID])
    }

    func testRejectsDifferentLibraryUUID() throws {
        let first = try makeStore()
        first.close()

        XCTAssertThrowsError(try makeStore(uuid: "other-library")) { error in
            XCTAssertEqual(
                error as? NASAssessmentError,
                .storeLibraryMismatch(expected: "other-library", found: libraryUUID)
            )
        }
    }

    func testGenerationsIncrementFromOne() throws {
        let store = try makeStore()
        defer { store.close() }
        XCTAssertNil(try store.latestGeneration())

        let first = try store.beginScan(mode: .exactOnly, startedAt: Date(timeIntervalSince1970: 100))
        let second = try store.beginScan(mode: .exactOnly, startedAt: Date(timeIntervalSince1970: 200))
        let third = try store.beginScan(mode: .exactOnly, startedAt: Date(timeIntervalSince1970: 300))
        XCTAssertEqual([first, second, third], [1, 2, 3])
        XCTAssertEqual(try store.latestGeneration(), 3)
        XCTAssertEqual(try store.latestGeneration(excluding: 3), 2)

        let running = try XCTUnwrap(try store.scanSummary(generation: first))
        XCTAssertEqual(running.outcome, .running)
        XCTAssertNil(running.finishedAt)
        XCTAssertEqual(running.startedAt, Date(timeIntervalSince1970: 100))
    }

    func testMarkCandidatesClassifiesUniqueEmptyAndCollidingSizes() throws {
        let store = try makeStore()
        defer { store.close() }
        let generation = try store.beginScan(mode: .exactOnly, startedAt: Date())
        try store.recordItems([
            item("a/one.jpg", size: 100),
            item("b/two.jpg", size: 100),
            item("c/three.jpg", size: 100),
            item("d/four.jpg", size: 250),
            item("e/five.jpg", size: 250),
            item("f/unique.jpg", size: 999),
            item("g/empty1.jpg", size: 0),
            item("h/empty2.jpg", size: 0),
        ], generation: generation)

        let result = try store.markCandidates(generation: generation)
        XCTAssertEqual(result.candidateFiles, 5)
        XCTAssertEqual(result.candidateBytesH, 3 * 100 + 2 * 250)
        XCTAssertEqual(result.emptyFiles, 2)

        let pending = try store.pendingItems(generation: generation)
        XCTAssertEqual(Set(pending.map(\.relativePath)), ["a/one.jpg", "b/two.jpg", "c/three.jpg", "d/four.jpg", "e/five.jpg"])
        XCTAssertTrue(pending.allSatisfy { $0.hashState == .pending })

        let states = rawStrings("SELECT hashState FROM Items WHERE relativePath='f/unique.jpg';")
        XCTAssertEqual(states, ["notCandidate"])
        XCTAssertEqual(
            rawStrings("SELECT hashState FROM Items WHERE size=0 ORDER BY relativePath;"),
            ["emptyFile", "emptyFile"]
        )
    }

    func testPendingItemsOrderedBySizeDescending() throws {
        let store = try makeStore()
        defer { store.close() }
        let generation = try store.beginScan(mode: .exactOnly, startedAt: Date())
        try store.recordItems([
            item("z.jpg", size: 10),
            item("a.jpg", size: 10),
            item("m.mov", size: 5000, kind: .video),
            item("n.mov", size: 5000, kind: .video),
            item("q.jpg", size: 300),
            item("r.jpg", size: 300),
        ], generation: generation)
        _ = try store.markCandidates(generation: generation)

        let pending = try store.pendingItems(generation: generation)
        XCTAssertEqual(pending.map(\.relativePath), ["m.mov", "n.mov", "q.jpg", "r.jpg", "a.jpg", "z.jpg"])
        XCTAssertEqual(pending.first?.kind, .video)
    }

    func testExactGroupsRequireTwoHashedMembersAndSortByRedundantBytes() throws {
        let store = try makeStore()
        defer { store.close() }
        let generation = try store.beginScan(mode: .exactOnly, startedAt: Date())
        try store.recordItems([
            // digest "bbb": 3 members of 100 -> redundant 200
            item("b/2.jpg", size: 100, digest: "bbb", state: .hashed),
            item("b/1.jpg", size: 100, digest: "bbb", state: .hashed),
            item("b/3.jpg", size: 100, digest: "bbb", state: .hashed),
            // digest "aaa": 2 members of 100 -> redundant 100
            item("a/1.jpg", size: 100, digest: "aaa", state: .hashed),
            item("a/2.jpg", size: 100, digest: "aaa", state: .hashed),
            // digest "ccc": 2 members of 100 -> redundant 100, ties with "aaa", digest ASC
            item("c/1.jpg", size: 100, digest: "ccc", state: .hashed),
            item("c/2.jpg", size: 100, digest: "ccc", state: .hashed),
            // digest "big": 2 members of 9000 -> redundant 9000, first
            item("v/1.mov", size: 9000, digest: "big", state: .hashed, kind: .video),
            item("v/2.mov", size: 9000, digest: "big", state: .hashed, kind: .video),
            // single hashed member never forms a group
            item("solo.jpg", size: 100, digest: "solo", state: .hashed),
        ], generation: generation)

        let groups = try store.exactGroups(generation: generation)
        XCTAssertEqual(groups.map(\.digest), ["big", "bbb", "aaa", "ccc"])
        XCTAssertEqual(groups.map(\.redundantLogicalBytes), [9000, 200, 100, 100])
        XCTAssertEqual(groups[0].kind, .video)
        XCTAssertEqual(groups[1].memberRelativePaths, ["b/1.jpg", "b/2.jpg", "b/3.jpg"])
        XCTAssertEqual(groups[1].size, 100)
    }

    func testUnresolvedItemsNeverJoinGroups() throws {
        let store = try makeStore()
        defer { store.close() }
        let generation = try store.beginScan(mode: .exactOnly, startedAt: Date())
        try store.recordItems([
            item("one.jpg", size: 100),
            item("two.jpg", size: 100),
            item("three.jpg", size: 100),
        ], generation: generation)
        _ = try store.markCandidates(generation: generation)
        try store.updateHashResults([
            item("one.jpg", size: 100, digest: "same", state: .hashed),
            item("two.jpg", size: 100, digest: "same", state: .unresolved, reason: .readFailed),
            item("three.jpg", size: 100, digest: nil, state: .unresolved, reason: .sizeChangedDuringRead),
        ], generation: generation)

        XCTAssertTrue(try store.exactGroups(generation: generation).isEmpty)
        XCTAssertTrue(try store.pendingItems(generation: generation).isEmpty)
        XCTAssertEqual(
            rawStrings("SELECT unresolvedReason FROM Items WHERE relativePath='two.jpg';"),
            ["readFailed"]
        )
        XCTAssertEqual(try store.reusableDigests(generation: generation).keys.sorted(), ["one.jpg"])
    }

    func testSummaryRoundTripsCountsLedgerAndRedundantBytes() throws {
        let store = try makeStore()
        defer { store.close() }
        let started = Date(timeIntervalSince1970: 1_000)
        let finished = Date(timeIntervalSince1970: 2_000)
        let generation = try store.beginScan(mode: .exactOnly, startedAt: started)
        try store.recordItems([
            item("a.jpg", size: 400, digest: "d", state: .hashed),
            item("b.jpg", size: 400, digest: "d", state: .hashed),
            item("c.jpg", size: 400, digest: "d", state: .hashed),
        ], generation: generation)
        let counts = NASScanCounts(
            directoriesAssessed: 4, mediaFiles: 3, mediaBytes: 1200, unsupportedFiles: 2,
            emptyFiles: 1, candidateFiles: 3, hashedFiles: 3, unresolvedFiles: 0, issueCount: 5
        )
        let ledger = NASByteLedger(candidateBytesH: 1200, bytesReadClean: 1200, bytesReadUnresolved: 7, cacheHits: 2)
        try store.finishScan(generation: generation, outcome: .complete, counts: counts, ledger: ledger, finishedAt: finished)

        let summary = try XCTUnwrap(try store.scanSummary(generation: generation))
        XCTAssertEqual(summary.generation, generation)
        XCTAssertEqual(summary.mode, .exactOnly)
        XCTAssertEqual(summary.startedAt, started)
        XCTAssertEqual(summary.finishedAt, finished)
        XCTAssertEqual(summary.outcome, .complete)
        XCTAssertEqual(summary.counts, counts)
        XCTAssertEqual(summary.ledger, ledger)
        XCTAssertEqual(summary.exactGroupCount, 1)
        XCTAssertEqual(summary.redundantLogicalBytes, 800)
        XCTAssertNil(try store.scanSummary(generation: 99))

        try store.incrementPreviewRequests(generation: generation)
        try store.incrementPreviewRequests(generation: generation)
        XCTAssertEqual(rawStrings("SELECT previewRequests FROM Scans WHERE generation=\(generation);"), ["2"])

        try store.recordDirectories([
            NASDirectoryRow(relativePath: "z", status: .assessed, mediaFileCount: 2, mediaBytes: 800, unsupportedFileCount: 1),
            NASDirectoryRow(relativePath: "a", status: .unreadable),
        ], generation: generation)
        let directories = try store.directoryRows(generation: generation)
        XCTAssertEqual(directories.map(\.relativePath), ["a", "z"])
        XCTAssertEqual(directories[1], NASDirectoryRow(relativePath: "z", status: .assessed, mediaFileCount: 2, mediaBytes: 800, unsupportedFileCount: 1))

        let issue = NASIssue(category: .unreadableItem, relativePath: "a/x.jpg", detail: "Permission denied")
        try store.recordIssues([issue], generation: generation)
        XCTAssertEqual(try store.issues(generation: generation), [issue])
    }

    func testChoicesAndReviewStateSurvivePruning() throws {
        let store = try makeStore()
        defer { store.close() }
        var generations: [Int64] = []
        for index in 1...3 {
            let generation = try store.beginScan(mode: .exactOnly, startedAt: Date(timeIntervalSince1970: Double(index)))
            try store.recordItems([item("f\(index).jpg", size: 10)], generation: generation)
            try store.recordDirectories([NASDirectoryRow(relativePath: "d\(index)", status: .assessed)], generation: generation)
            try store.recordIssues([NASIssue(category: .skippedLink, relativePath: "l\(index)", detail: "link")], generation: generation)
            generations.append(generation)
        }
        let choice = NASReviewChoice(digest: "abc", size: 10, keeperRelativePath: "f1.jpg", reviewedAt: Date(timeIntervalSince1970: 5))
        try store.saveChoice(choice)
        try store.setReviewState("filter=all", forKey: "ui")
        try store.setReviewState("x", forKey: "gone")
        try store.setReviewState(nil, forKey: "gone")

        try store.pruneGenerations(keepingLatest: 2)

        XCTAssertNil(try store.scanSummary(generation: generations[0]))
        XCTAssertNotNil(try store.scanSummary(generation: generations[1]))
        XCTAssertNotNil(try store.scanSummary(generation: generations[2]))
        XCTAssertEqual(rawStrings("SELECT DISTINCT generation FROM Items ORDER BY generation;"), ["2", "3"])
        XCTAssertEqual(rawStrings("SELECT DISTINCT generation FROM Directories ORDER BY generation;"), ["2", "3"])
        XCTAssertEqual(rawStrings("SELECT DISTINCT generation FROM Issues ORDER BY generation;"), ["2", "3"])

        XCTAssertEqual(try store.choices(), ["abc": choice])
        XCTAssertEqual(try store.reviewState(forKey: "ui"), "filter=all")
        XCTAssertNil(try store.reviewState(forKey: "gone"))

        // A choice may record "not a duplicate" with no keeper.
        let none = NASReviewChoice(digest: "def", size: 20, keeperRelativePath: nil, reviewedAt: Date(timeIntervalSince1970: 6))
        try store.saveChoice(none)
        XCTAssertEqual(try store.choices()["def"], none)
    }

    func testFileIDRoundTripsAboveInt64Max() throws {
        let store = try makeStore()
        defer { store.close() }
        let generation = try store.beginScan(mode: .exactOnly, startedAt: Date())
        try store.recordItems([
            item("max.jpg", size: 5, fileID: UInt64.max),
            item("high.jpg", size: 5, fileID: UInt64(Int64.max) + 1),
            item("low.jpg", size: 6, fileID: 42),
        ], generation: generation)
        _ = try store.markCandidates(generation: generation)

        let pending = try store.pendingItems(generation: generation)
        let byPath = Dictionary(uniqueKeysWithValues: pending.map { ($0.relativePath, $0.fileID) })
        XCTAssertEqual(byPath["max.jpg"], UInt64.max)
        XCTAssertEqual(byPath["high.jpg"], UInt64(Int64.max) + 1)
    }

    func testRefusesSymlinkedStoreFile() throws {
        let other = directory.appendingPathComponent("other.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: other.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: storeURL, withDestinationURL: other)

        XCTAssertThrowsError(try makeStore()) { error in
            XCTAssertEqual(
                error as? DestinationMetadataUnsafeError,
                DestinationMetadataUnsafeError(itemName: "assessment.sqlite")
            )
        }
        XCTAssertEqual(try Data(contentsOf: other).count, 0)
    }

    func testStoreErrorsUseStoreFailedWithoutLeakingInDescription() throws {
        // A file that is not a database makes SQLite fail on first use.
        try Data("this is not a sqlite database, just text padding".utf8).write(to: storeURL)

        XCTAssertThrowsError(try makeStore()) { error in
            guard case let .storeFailed(message)? = error as? NASAssessmentError else {
                return XCTFail("expected storeFailed, got \(error)")
            }
            XCTAssertFalse(message.isEmpty)
            let description = (error as? NASAssessmentError)?.errorDescription ?? ""
            XCTAssertFalse(description.uppercased().contains("SQLITE"))
            XCTAssertFalse(description.contains(message))
            XCTAssertTrue(description.contains("Nothing on the NAS was changed"))
        }
    }
}
