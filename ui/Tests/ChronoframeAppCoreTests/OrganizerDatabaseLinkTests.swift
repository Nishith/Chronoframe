import Foundation
import SQLite3
import XCTest
@testable import ChronoframeCore

/// `.organize_cache.db` sits at a fixed name in the user-selected destination.
/// SQLite already refuses a link to a non-database file, but a link or hard
/// link to an empty file or another SQLite database would have Chronoframe
/// create its tables inside that file.
final class OrganizerDatabaseLinkTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("OrganizerDatabaseLink-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func cacheURL(in destination: URL) -> URL {
        destination.appendingPathComponent(".organize_cache.db")
    }

    /// A separate SQLite database with one table, standing in for another
    /// app's data.
    private func makeOtherDatabase(in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent("other-\(UUID().uuidString).sqlite")
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &handle), SQLITE_OK)
        XCTAssertEqual(sqlite3_exec(handle, "CREATE TABLE notes(body TEXT);", nil, nil, nil), SQLITE_OK)
        sqlite3_close(handle)
        return url
    }

    private func tableNames(in url: URL) throws -> [String] {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name;", -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        var names: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            names.append(String(cString: sqlite3_column_text(statement, 0)))
        }
        return names
    }

    private func assertRejected(_ url: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try OrganizerDatabase(url: url), file: file, line: line) { error in
            XCTAssertEqual(
                error as? DestinationMetadataUnsafeError,
                DestinationMetadataUnsafeError(itemName: ".organize_cache.db"),
                "expected DestinationMetadataUnsafeError, got \(error)",
                file: file,
                line: line
            )
        }
    }

    func testSymlinkToAnotherDatabaseIsRejectedAndThatDatabaseIsUntouched() throws {
        let destination = try makeDirectory()
        let other = try makeOtherDatabase(in: try makeDirectory())
        try FileManager.default.createSymbolicLink(at: cacheURL(in: destination), withDestinationURL: other)

        assertRejected(cacheURL(in: destination))

        XCTAssertEqual(try tableNames(in: other), ["notes"])
    }

    func testSymlinkToAnEmptyFileIsRejectedAndTheFileStaysEmpty() throws {
        let destination = try makeDirectory()
        let empty = try makeDirectory().appendingPathComponent("empty.txt")
        XCTAssertTrue(FileManager.default.createFile(atPath: empty.path, contents: Data()))
        try FileManager.default.createSymbolicLink(at: cacheURL(in: destination), withDestinationURL: empty)

        assertRejected(cacheURL(in: destination))

        XCTAssertEqual(try Data(contentsOf: empty).count, 0)
    }

    func testHardLinkToAnotherDatabaseIsRejectedAndThatDatabaseIsUntouched() throws {
        let destination = try makeDirectory()
        let other = try makeOtherDatabase(in: destination)
        try FileManager.default.linkItem(at: other, to: cacheURL(in: destination))

        assertRejected(cacheURL(in: destination))

        XCTAssertEqual(try tableNames(in: other), ["notes"])
    }

    func testDanglingSymlinkIsRejectedAndItsTargetIsNotCreated() throws {
        let destination = try makeDirectory()
        let target = try makeDirectory().appendingPathComponent("not-yet.db")
        try FileManager.default.createSymbolicLink(at: cacheURL(in: destination), withDestinationURL: target)

        assertRejected(cacheURL(in: destination))

        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))
    }

    func testAnchorDetectsThePathBeingSwappedForALinkAfterItWasOpened() throws {
        let destination = try makeDirectory()
        let other = try makeOtherDatabase(in: try makeDirectory())
        let anchor = try DestinationMetadataFile.openAnchor(at: cacheURL(in: destination))
        XCTAssertNoThrow(try anchor.confirmPathStillRefersToFile())

        try FileManager.default.removeItem(at: cacheURL(in: destination))
        try FileManager.default.createSymbolicLink(at: cacheURL(in: destination), withDestinationURL: other)

        XCTAssertThrowsError(try anchor.confirmPathStillRefersToFile()) { error in
            XCTAssertEqual(error as? DestinationMetadataUnsafeError, DestinationMetadataUnsafeError(itemName: ".organize_cache.db"))
        }
    }

    func testAnchorDetectsADifferentRegularFileAtThePathAndAHardLinkToTheSameFile() throws {
        let destination = try makeDirectory()
        let anchor = try DestinationMetadataFile.openAnchor(at: cacheURL(in: destination))

        try FileManager.default.linkItem(at: cacheURL(in: destination), to: destination.appendingPathComponent("second-name"))
        XCTAssertThrowsError(try anchor.confirmPathStillRefersToFile())
        try FileManager.default.removeItem(at: destination.appendingPathComponent("second-name"))
        XCTAssertNoThrow(try anchor.confirmPathStillRefersToFile())

        try FileManager.default.removeItem(at: cacheURL(in: destination))
        XCTAssertTrue(FileManager.default.createFile(atPath: cacheURL(in: destination).path, contents: Data()))
        XCTAssertThrowsError(try anchor.confirmPathStillRefersToFile())
    }

    func testDirectoryAtTheCachePathIsRejected() throws {
        let destination = try makeDirectory()
        try FileManager.default.createDirectory(at: cacheURL(in: destination), withIntermediateDirectories: false)

        assertRejected(cacheURL(in: destination))
    }

    func testFIFOAtTheCachePathIsRejectedWithoutBlocking() throws {
        let destination = try makeDirectory()
        XCTAssertEqual(mkfifo(cacheURL(in: destination).path, 0o600), 0)

        assertRejected(cacheURL(in: destination))
    }

    func testSymlinksAtSQLiteSidecarNamesAreNotFollowed() throws {
        let destination = try makeDirectory()
        let victims = try makeDirectory()
        let walTarget = victims.appendingPathComponent("wal-target")
        let shmTarget = victims.appendingPathComponent("shm-target")
        for target in [walTarget, shmTarget] {
            XCTAssertTrue(FileManager.default.createFile(atPath: target.path, contents: Data()))
        }
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent(".organize_cache.db-wal"), withDestinationURL: walTarget
        )
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent(".organize_cache.db-shm"), withDestinationURL: shmTarget
        )

        if let database = try? OrganizerDatabase(url: cacheURL(in: destination)) {
            database.close()
        }

        XCTAssertEqual(try Data(contentsOf: walTarget).count, 0)
        XCTAssertEqual(try Data(contentsOf: shmTarget).count, 0)
    }

    func testCacheIsCreatedAndReopened() throws {
        let destination = try makeDirectory()

        let first = try OrganizerDatabase(url: cacheURL(in: destination))
        first.close()
        let second = try OrganizerDatabase(url: cacheURL(in: destination))
        second.close()

        XCTAssertTrue(try tableNames(in: cacheURL(in: destination)).contains("CopyJobs"))
    }
}
