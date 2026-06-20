import Foundation
import XCTest
import os
@testable import ChronoframeCore

final class IssueCollector: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [RunIssue]())

    func append(_ issue: RunIssue) {
        lock.withLock { issues in
            issues.append(issue)
        }
    }

    var issues: [RunIssue] {
        lock.withLock { $0 }
    }
}

final class Phase1ModernizationTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Phase1ModernizationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        // Reset global static mock providers to avoid cross-test interference
        MediaDiscovery.isICloudDatalessProvider = { _ in false }
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.setUpWithError()
    }

    // MARK: - 1. Receipt Safety Tests

    func testReceiptDurabilityWritesAtomicallyAndFsyncs() throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("test_receipt.json")
        let data = try JSONEncoder().encode(["status": "COMPLETED"])

        XCTAssertNoThrow(try ReceiptDurability.durablyWrite(data: data, to: destinationURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: destinationURL.path))

        let readData = try Data(contentsOf: destinationURL)
        let dict = try JSONDecoder().decode([String: String].self, from: readData)
        XCTAssertEqual(dict["status"], "COMPLETED")
    }

    func testReceiptDurabilityFsyncHelpers() throws {
        let fileURL = temporaryDirectoryURL.appendingPathComponent("dummy.txt")
        try Data("dummy".utf8).write(to: fileURL)

        XCTAssertNoThrow(try ReceiptDurability.fsyncFile(atPath: fileURL.path))
        XCTAssertNoThrow(try ReceiptDurability.fsyncDirectory(atPath: temporaryDirectoryURL.path))
    }

    // MARK: - 2. Citizen Throttling Tests

    func testConcurrencyThrottlingOnLowPowerMode() throws {
        let dbURL = temporaryDirectoryURL.appendingPathComponent("queue.db")
        let database = try OrganizerDatabase(url: dbURL)

        let sourceDir = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destDir = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        // Write 3 source files
        let src1 = sourceDir.appendingPathComponent("file1.jpg")
        let src2 = sourceDir.appendingPathComponent("file2.jpg")
        let src3 = sourceDir.appendingPathComponent("file3.jpg")
        try Data("data".utf8).write(to: src1)
        try Data("data".utf8).write(to: src2)
        try Data("data".utf8).write(to: src3)

        // Queue 3 copy jobs
        let jobs = [
            QueuedCopyJob(sourcePath: src1.path, destinationPath: destDir.appendingPathComponent("file1.jpg").path, hash: "h1", status: .pending),
            QueuedCopyJob(sourcePath: src2.path, destinationPath: destDir.appendingPathComponent("file2.jpg").path, hash: "h2", status: .pending),
            QueuedCopyJob(sourcePath: src3.path, destinationPath: destDir.appendingPathComponent("file3.jpg").path, hash: "h3", status: .pending)
        ]
        try database.enqueueQueuedJobs(jobs)

        let logger = PersistentRunLogger(logURL: destDir.appendingPathComponent(".organize_log.txt"))
        try logger.open()
        defer { logger.close() }

        let collector = IssueCollector()
        let observer = TransferExecutionObserver(onIssue: { issue in
            collector.append(issue)
        })

        var executor = TransferExecutor()
        executor.isLowPowerModeEnabledProvider = { true } // Mock Low Power Mode

        _ = try executor.executeQueuedJobs(
            database: database,
            destinationRoot: destDir,
            verifyCopies: false,
            runLogger: logger,
            status: .pending,
            maxConcurrentCopies: 3, // parallel execution
            observer: observer
        )

        // Verify that it throttled to single concurrency and logged the appropriate warning
        XCTAssertTrue(collector.issues.contains { $0.severity == .warning && $0.message.contains("Low Power Mode is on") })
    }

    func testConcurrencyThrottlingOnElevatedThermalState() throws {
        let dbURL = temporaryDirectoryURL.appendingPathComponent("queue.db")
        let database = try OrganizerDatabase(url: dbURL)

        let sourceDir = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destDir = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let src1 = sourceDir.appendingPathComponent("file1.jpg")
        try Data("data".utf8).write(to: src1)

        let jobs = [
            QueuedCopyJob(sourcePath: src1.path, destinationPath: destDir.appendingPathComponent("file1.jpg").path, hash: "h1", status: .pending)
        ]
        try database.enqueueQueuedJobs(jobs)

        let logger = PersistentRunLogger(logURL: destDir.appendingPathComponent(".organize_log.txt"))
        try logger.open()
        defer { logger.close() }

        let collector = IssueCollector()
        let observer = TransferExecutionObserver(onIssue: { issue in
            collector.append(issue)
        })

        var executor = TransferExecutor()
        executor.thermalStateProvider = { .serious } // Mock serious thermal state

        _ = try executor.executeQueuedJobs(
            database: database,
            destinationRoot: destDir,
            verifyCopies: false,
            runLogger: logger,
            status: .pending,
            maxConcurrentCopies: 2, // parallel execution
            observer: observer
        )

        XCTAssertTrue(collector.issues.contains { $0.severity == .warning && $0.message.contains("Device thermal state is elevated") })
    }

    // MARK: - 3. iCloud Dataless Tests

    func testICloudDatalessSkippedInMediaDiscovery() throws {
        let sourceDir = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)

        let normalFile = sourceDir.appendingPathComponent("normal.jpg")
        let datalessFile = sourceDir.appendingPathComponent("dataless.jpg")
        try Data("normal".utf8).write(to: normalFile)
        try Data("dataless".utf8).write(to: datalessFile)

        // Mock dataless check
        MediaDiscovery.isICloudDatalessProvider = { url in
            return url.lastPathComponent == "dataless.jpg"
        }

        let discovered = try MediaDiscovery.discoverMediaFiles(at: sourceDir)
        let standardizedDiscovered = discovered.map { URL(fileURLWithPath: $0).standardizedFileURL.path }
        XCTAssertTrue(standardizedDiscovered.contains(normalFile.standardizedFileURL.path))
        XCTAssertFalse(standardizedDiscovered.contains(datalessFile.standardizedFileURL.path))
    }

    func testICloudDatalessSkippedInFileIdentityHasher() throws {
        let fileURL = temporaryDirectoryURL.appendingPathComponent("dataless.jpg")
        try Data("dataless".utf8).write(to: fileURL)

        var hasher = FileIdentityHasher()
        hasher.isICloudDatalessProvider = { _ in true } // Mock as dataless

        let result = hasher.processFile(at: fileURL.path, cachedRecord: nil)
        XCTAssertNil(result.identity)
        XCTAssertEqual(result.size, 0)
        XCTAssertFalse(result.wasHashed)
    }

    // MARK: - 4. Pause/Resume Disk Check Tests

    func testDiskCheckPausesAndResumes() throws {
        let dbURL = temporaryDirectoryURL.appendingPathComponent("queue.db")
        let database = try OrganizerDatabase(url: dbURL)

        let sourceDir = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destDir = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)

        let src1 = sourceDir.appendingPathComponent("file1.jpg")
        try Data("data".utf8).write(to: src1)

        let jobs = [
            QueuedCopyJob(sourcePath: src1.path, destinationPath: destDir.appendingPathComponent("file1.jpg").path, hash: "h1", status: .pending)
        ]
        try database.enqueueQueuedJobs(jobs)

        let logger = PersistentRunLogger(logURL: destDir.appendingPathComponent(".organize_log.txt"))
        try logger.open()
        defer { logger.close() }

        let collector = IssueCollector()
        let observer = TransferExecutionObserver(onIssue: { issue in
            collector.append(issue)
        })

        var executor = TransferExecutor()

        // Configure a mock disk space provider that:
        // 1. Returns 0 bytes free on the first check (insufficient space).
        // 2. Returns 1 GB free on the second check (sufficient space).
        let checkCount = OSAllocatedUnfairLock<Int>(initialState: 0)
        executor.freeDiskSpaceProvider = { _ in
            let current = checkCount.withLock { count -> Int in
                let orig = count
                count += 1
                return orig
            }
            if current == 0 {
                return 0 // low space
            } else {
                return 1024 * 1024 * 1024 // 1 GB free
            }
        }

        _ = try executor.executeQueuedJobs(
            database: database,
            destinationRoot: destDir,
            verifyCopies: false,
            runLogger: logger,
            status: .pending,
            maxConcurrentCopies: 1,
            observer: observer
        )

        // Verify that it paused (emitted Insufficient disk space issue)
        XCTAssertTrue(collector.issues.contains { $0.severity == .warning && $0.message.contains("Paused: Insufficient disk space") })
        // Verify that it resumed (emitted Disk space check passed issue)
        XCTAssertTrue(collector.issues.contains { $0.severity == .warning && $0.message.contains("Disk space check passed") })
     }

    // MARK: - 5. Phase 2 Concurrency & Cache Tests

    func testSingleRecordCacheLookup() throws {
        let dbURL = temporaryDirectoryURL.appendingPathComponent("queue.db")
        let database = try OrganizerDatabase(url: dbURL)
        defer { database.close() }

        let record = RawFileCacheRecord(
            namespace: .source,
            path: "/path/to/file.jpg",
            hash: "1234_testhash",
            size: 1234,
            modificationTime: 5678.0
        )
        try database.saveRawCacheRecords([record])

        let loadedRaw = try database.loadRawCacheRecord(namespace: .source, path: "/path/to/file.jpg")
        XCTAssertNotNil(loadedRaw)
        XCTAssertEqual(loadedRaw?.hash, "1234_testhash")
        XCTAssertEqual(loadedRaw?.size, 1234)
        XCTAssertEqual(loadedRaw?.modificationTime, 5678.0)

        let loadedTyped = try database.loadCacheRecord(namespace: .source, path: "/path/to/file.jpg")
        XCTAssertNotNil(loadedTyped)
        XCTAssertEqual(loadedTyped?.identity, FileIdentity(rawValue: "1234_testhash"))

        let missing = try database.loadRawCacheRecord(namespace: .source, path: "/missing.jpg")
        XCTAssertNil(missing)
    }

    func testDryRunPlannerStructuredCancellation() async throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("cancel-source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("cancel-dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        // Write a few media files
        for index in 1...10 {
            let fileURL = sourceRoot.appendingPathComponent("IMG_\(index).jpg")
            try Data("test".utf8).write(to: fileURL)
        }

        let isCancelledFlag = ManagedAtomicBool()
        let planner = DryRunPlanner()

        // We run planning asynchronously and cancel it midway
        let task = Task {
            try await planner.planAsync(
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot,
                isCancelled: { isCancelledFlag.get() }
            )
        }

        isCancelledFlag.set(true) // Immediately cancel

        do {
            _ = try await task.value
            XCTFail("Should have thrown CancellationError")
        } catch is CancellationError {
            // Success!
        } catch {
            XCTFail("Expected CancellationError, got: \(error)")
        }
    }

    func testDynamicConcurrencyScaling() throws {
        var executor = TransferExecutor()

        // 1. Standard conditions: Should scale based on activeProcessorCount capped at 4-6
        executor.isLowPowerModeEnabledProvider = { false }
        executor.thermalStateProvider = { .nominal }

        let (concurrencyNominal, reasonNominal) = executor.determineConcurrency(requested: 8)
        XCTAssertNil(reasonNominal)
        XCTAssertEqual(concurrencyNominal, min(max(4, ProcessInfo.processInfo.activeProcessorCount), 6))

        // 2. Low Power Mode: Should throttle to 1
        executor.isLowPowerModeEnabledProvider = { true }
        let (concurrencyLPM, reasonLPM) = executor.determineConcurrency(requested: 4)
        XCTAssertEqual(concurrencyLPM, 1)
        XCTAssertEqual(reasonLPM, "Low Power Mode is on")

        // 3. Serious Thermal State: Should throttle to 1
        executor.isLowPowerModeEnabledProvider = { false }
        executor.thermalStateProvider = { .serious }
        let (concurrencySerious, reasonSerious) = executor.determineConcurrency(requested: 4)
        XCTAssertEqual(concurrencySerious, 1)
        XCTAssertEqual(reasonSerious, "Device thermal state is elevated")

        // 4. Critical Thermal State: Should throttle to 1
        executor.thermalStateProvider = { .critical }
        let (concurrencyCritical, reasonCritical) = executor.determineConcurrency(requested: 4)
        XCTAssertEqual(concurrencyCritical, 1)
        XCTAssertEqual(reasonCritical, "Device thermal state is elevated")
    }
}
