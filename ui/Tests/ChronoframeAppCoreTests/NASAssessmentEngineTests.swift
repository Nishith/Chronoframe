import Foundation
import SQLite3
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class NASAssessmentEngineTests: XCTestCase {
    private var fixture: NASFixtureBuilder!
    private var engine: SwiftNASAssessmentEngine!
    private var record: NASLibraryRecord!

    override func setUpWithError() throws {
        // Two identical files in different folders, one unique file.
        let same = Data(repeating: 0x41, count: 4096)
        fixture = try NASFixtureBuilder([
            .file("2020/IMG_0001.jpg", same),
            .file("Backup/IMG_0001.jpg", same),
            .file("2021/IMG_0002.jpg", Data(repeating: 0x42, count: 3000)),
        ])
        let storeURL = fixture.stateDirectoryURL.appendingPathComponent("assessment.db")
        engine = SwiftNASAssessmentEngine(storeURL: { _ in storeURL })
        record = nasTestRecord(uuid: "LIB-1")
    }

    override func tearDown() {
        engine = nil
        fixture?.tearDown()
        fixture = nil
    }

    private func runAssessment() async throws -> [NASAssessmentEvent] {
        var events: [NASAssessmentEvent] = []
        for try await event in try engine.assess(record, rootURL: fixture.rootURL) {
            events.append(event)
        }
        return events
    }

    // AGENTS-INVARIANT: 27
    func testAssessStreamsScannerEventsAndPersistsSnapshot() async throws {
        let before = try fixture.snapshot()
        XCTAssertNil(try engine.latestSnapshot(for: record), "No scan has run yet")

        let events = try await runAssessment()

        guard case let .started(generation)? = events.first else {
            return XCTFail("The first event must be .started, got \(String(describing: events.first))")
        }
        XCTAssertEqual(generation, 1)
        XCTAssertTrue(events.contains(.phaseStarted(.enumerating)))
        guard case let .finished(summary)? = events.last else {
            return XCTFail("The last event must be .finished")
        }
        XCTAssertEqual(summary.outcome, .complete)
        XCTAssertEqual(summary.exactGroupCount, 1)

        let snapshot = try XCTUnwrap(try engine.latestSnapshot(for: record))
        XCTAssertEqual(snapshot.summary, summary)
        XCTAssertEqual(snapshot.groups.count, 1)
        XCTAssertEqual(snapshot.groups.first?.memberRelativePaths, ["2020/IMG_0001.jpg", "Backup/IMG_0001.jpg"])
        XCTAssertFalse(snapshot.directories.isEmpty)
        XCTAssertTrue(snapshot.choices.isEmpty)
        XCTAssertNil(snapshot.selectedDigest)

        XCTAssertEqual(try fixture.snapshot(), before, "Assessment must not change anything in the library")
    }

    func testSaveChoiceAndSelectedDigestRoundTrip() async throws {
        _ = try await runAssessment()
        let group = try XCTUnwrap(try engine.latestSnapshot(for: record)?.groups.first)

        let choice = NASReviewChoice(
            digest: group.digest,
            size: group.size,
            keeperRelativePath: "2020/IMG_0001.jpg",
            reviewedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        try engine.saveChoice(choice, for: record)
        try engine.saveSelectedDigest(group.digest, for: record)

        var snapshot = try XCTUnwrap(try engine.latestSnapshot(for: record))
        XCTAssertEqual(snapshot.choices[group.digest], choice)
        XCTAssertEqual(snapshot.selectedDigest, group.digest)

        try engine.saveSelectedDigest(nil, for: record)
        snapshot = try XCTUnwrap(try engine.latestSnapshot(for: record))
        XCTAssertNil(snapshot.selectedDigest)
        XCTAssertEqual(snapshot.choices[group.digest], choice, "Clearing the selection keeps the saved choice")

        // A choice survives a second assessment because choices are keyed by digest.
        _ = try await runAssessment()
        XCTAssertEqual(try engine.latestSnapshot(for: record)?.choices[group.digest], choice)
    }

    func testRecordPreviewRequestIncrementsCounter() async throws {
        _ = try await runAssessment()
        try engine.recordPreviewRequest(for: record)
        try engine.recordPreviewRequest(for: record)

        let storeURL = fixture.stateDirectoryURL.appendingPathComponent("assessment.db")
        XCTAssertEqual(try previewRequests(at: storeURL), 2)
    }

    private func previewRequests(at url: URL) throws -> Int {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            sqlite3_close(handle)
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT previewRequests FROM Scans ORDER BY generation DESC LIMIT 1;", -1, &statement, nil) == SQLITE_OK else {
            throw CocoaError(.fileReadUnknown)
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { throw CocoaError(.fileReadUnknown) }
        return Int(sqlite3_column_int64(statement, 0))
    }
}
