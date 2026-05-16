import ChronoframeCore
import XCTest

final class OrganizerDatabaseCLITests: XCTestCase {
    private var temporaryDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrganizerDatabaseCLITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    func testClearCacheRemovesOnlyFileCacheRows() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent(".organize_cache.db")
        let database = try OrganizerDatabase(url: databaseURL)
        defer { database.close() }

        try database.saveRawCacheRecords([
            RawFileCacheRecord(
                namespace: .source,
                path: "/in/a.jpg",
                hash: "1_hash",
                size: 1,
                modificationTime: 2
            ),
            RawFileCacheRecord(
                namespace: .destination,
                path: "/out/a.jpg",
                hash: "1_hash",
                size: 1,
                modificationTime: 2
            ),
        ])
        try database.enqueueQueuedJobs([
            QueuedCopyJob(sourcePath: "/in/a.jpg", destinationPath: "/out/a.jpg", hash: "1_hash", status: .pending)
        ])

        try database.clearCache()

        XCTAssertEqual(try database.cacheRecordCount(namespace: .source), 0)
        XCTAssertEqual(try database.cacheRecordCount(namespace: .destination), 0)
        XCTAssertEqual(try database.pendingJobCount(), 1)
    }
}
