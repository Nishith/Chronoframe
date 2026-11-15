import Foundation
import SQLite3
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreNASJournalPolicyTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeCoreNASJournalPolicyTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private var databaseURL: URL {
        temporaryDirectoryURL.appendingPathComponent(".organize_cache.db")
    }

    private func sidecarExists(_ suffix: String) -> Bool {
        FileManager.default.fileExists(atPath: databaseURL.path + suffix)
    }

    // AGENTS-INVARIANT: 28
    func testRollbackDeletePolicyReadsBackDeleteAndFull() throws {
        let database = try OrganizerDatabase(url: databaseURL, journalPolicy: .rollbackDelete)
        defer { database.close() }

        XCTAssertEqual(try database.journalMode().lowercased(), "delete")
        XCTAssertEqual(try database.synchronousMode(), 2)
    }

    // AGENTS-INVARIANT: 28
    func testRollbackDeleteLeavesNoWALOrSHMAfterWrites() throws {
        let database = try OrganizerDatabase(url: databaseURL, journalPolicy: .rollbackDelete)
        defer { database.close() }

        try database.execute("CREATE TABLE IF NOT EXISTS JournalProbe (id INTEGER PRIMARY KEY, value TEXT);")
        for index in 0..<50 {
            try database.execute("INSERT INTO JournalProbe (value) VALUES ('row-\(index)');")
        }

        XCTAssertFalse(sidecarExists("-wal"))
        XCTAssertFalse(sidecarExists("-shm"))
        XCTAssertFalse(sidecarExists("-journal"), "the rollback journal is removed after each committed write")
    }

    // AGENTS-INVARIANT: 28
    func testRollbackDeleteConvertsIdleWALDatabase() throws {
        let walDatabase = try OrganizerDatabase(url: databaseURL, journalPolicy: .writeAheadLog)
        XCTAssertEqual(try walDatabase.journalMode().lowercased(), "wal")
        walDatabase.close()

        let database = try OrganizerDatabase(url: databaseURL, journalPolicy: .rollbackDelete)
        defer { database.close() }

        XCTAssertEqual(try database.journalMode().lowercased(), "delete")
        XCTAssertEqual(try database.synchronousMode(), 2)
        // SQLite may leave an empty -shm behind after leaving WAL; it is never
        // deleted by Chronoframe, so only the -wal is required to be gone.
        XCTAssertFalse(sidecarExists("-wal"))
    }

    // AGENTS-INVARIANT: 28
    func testRollbackDeleteRefusesWhileAnotherConnectionHoldsWAL() throws {
        let holder = try OrganizerDatabase(url: databaseURL, journalPolicy: .writeAheadLog)
        defer { holder.close() }
        try holder.execute("CREATE TABLE IF NOT EXISTS JournalProbe (id INTEGER PRIMARY KEY, value TEXT);")
        try holder.execute("INSERT INTO JournalProbe (value) VALUES ('held');")
        XCTAssertTrue(sidecarExists("-wal"))

        XCTAssertThrowsError(try OrganizerDatabase(url: databaseURL, journalPolicy: .rollbackDelete)) { error in
            guard case let OrganizerDatabaseError.journalModeUnavailable(mode) = error else {
                XCTFail("Expected journalModeUnavailable, got \(error)")
                return
            }
            XCTAssertEqual(mode.lowercased(), "wal")
        }

        XCTAssertTrue(sidecarExists("-wal"), "a refused open must not delete the WAL")
        XCTAssertTrue(sidecarExists("-shm"), "a refused open must not delete the shared-memory file")
        XCTAssertEqual(try holder.journalMode().lowercased(), "wal")
    }

    // AGENTS-INVARIANT: 28
    func testAutomaticPolicyUsesWALOnLocalVolume() throws {
        let database = try OrganizerDatabase(url: databaseURL)
        defer { database.close() }

        XCTAssertEqual(try database.journalMode().lowercased(), "wal")
        XCTAssertEqual(try database.synchronousMode(), 2)
    }

    // AGENTS-INVARIANT: 28
    func testReadOnlyOpenIgnoresPolicy() throws {
        let writer = try OrganizerDatabase(url: databaseURL, journalPolicy: .writeAheadLog)
        defer { writer.close() }

        let reader = try OrganizerDatabase(url: databaseURL, readOnly: true, journalPolicy: .rollbackDelete)
        defer { reader.close() }

        XCTAssertEqual(try writer.journalMode().lowercased(), "wal", "a read-only open must not switch the journal mode")
        XCTAssertEqual(try reader.journalMode().lowercased(), "wal")
        XCTAssertTrue(sidecarExists("-wal"))
    }

    // AGENTS-INVARIANT: 28
    func testJournalModeUnavailableDescriptionIsPlain() {
        let description = OrganizerDatabaseError.journalModeUnavailable("wal").errorDescription

        XCTAssertEqual(
            description,
            "Chronoframe couldn't open its copy records on this network folder safely, so it didn't copy anything. Another app or Chronoframe window may be using them. Your originals were untouched."
        )
        XCTAssertFalse(description?.localizedCaseInsensitiveContains("SQLite") ?? true)
        XCTAssertFalse(description?.contains("wal") ?? true)
    }
}
