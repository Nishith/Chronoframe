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

    // MARK: - App + CLI concurrent access to the same destination database
    //
    // The app and the CLI can target the same `.organize_cache.db` at the same
    // time. Each opens its own connection; the database runs in WAL mode with a
    // 30s busy timeout so writers serialize instead of failing. These tests pin
    // that contract: committed writes are visible across connections, and
    // concurrent writers don't error or corrupt the queue.

    func testTwoConnectionsToSameDatabaseShareCommittedWrites() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent(".organize_cache.db")
        let appConnection = try OrganizerDatabase(url: databaseURL)
        defer { appConnection.close() }
        let cliConnection = try OrganizerDatabase(url: databaseURL)
        defer { cliConnection.close() }

        // Interleave writes from both connections.
        try appConnection.enqueueQueuedJobs([
            QueuedCopyJob(sourcePath: "/in/a.jpg", destinationPath: "/out/a.jpg", hash: "a", status: .pending),
            QueuedCopyJob(sourcePath: "/in/b.jpg", destinationPath: "/out/b.jpg", hash: "b", status: .pending),
        ])
        try cliConnection.enqueueQueuedJobs([
            QueuedCopyJob(sourcePath: "/in/c.jpg", destinationPath: "/out/c.jpg", hash: "c", status: .pending),
        ])
        try appConnection.enqueueQueuedJobs([
            QueuedCopyJob(sourcePath: "/in/d.jpg", destinationPath: "/out/d.jpg", hash: "d", status: .pending),
        ])

        // Each connection sees every committed row, regardless of who wrote it.
        XCTAssertEqual(try appConnection.queuedJobCount(), 4)
        XCTAssertEqual(try cliConnection.queuedJobCount(), 4)

        // A status change committed by the CLI connection is visible to the app.
        try cliConnection.updateJobStatus(sourcePath: "/in/a.jpg", status: .copied)
        XCTAssertEqual(try appConnection.queuedJobCount(status: .copied), 1)
        XCTAssertEqual(try appConnection.pendingJobCount(), 3)
    }

    func testConcurrentWritesFromTwoConnectionsSerializeWithoutError() throws {
        let databaseURL = temporaryDirectory.appendingPathComponent(".organize_cache.db")
        let connectionA = try OrganizerDatabase(url: databaseURL)
        defer { connectionA.close() }
        let connectionB = try OrganizerDatabase(url: databaseURL)
        defer { connectionB.close() }

        let writesPerConnection = 50
        let errors = ErrorBox()

        DispatchQueue.concurrentPerform(iterations: 2) { worker in
            let connection = worker == 0 ? connectionA : connectionB
            for index in 0..<writesPerConnection {
                let key = "\(worker)-\(index)"
                do {
                    try connection.enqueueQueuedJobs([
                        QueuedCopyJob(
                            sourcePath: "/in/\(key).jpg",
                            destinationPath: "/out/\(key).jpg",
                            hash: key,
                            status: .pending
                        )
                    ])
                } catch {
                    errors.record(error)
                }
            }
        }

        XCTAssertTrue(errors.isEmpty, "Concurrent writers must serialize via the busy timeout, not error: \(errors.messages)")
        // Every row from both connections committed (distinct source paths).
        XCTAssertEqual(try connectionA.queuedJobCount(), writesPerConnection * 2)
    }

    private final class ErrorBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Error] = []
        func record(_ error: Error) {
            lock.lock(); defer { lock.unlock() }
            stored.append(error)
        }
        var isEmpty: Bool {
            lock.lock(); defer { lock.unlock() }
            return stored.isEmpty
        }
        var messages: [String] {
            lock.lock(); defer { lock.unlock() }
            return stored.map { String(describing: $0) }
        }
    }
}
