import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// The property everything downstream of the trial gate depends on: one run ID,
/// minted once at the reservation point and carried unchanged into the queued
/// rows and the receipt.
///
/// Before this, three different UUIDs described a single organize run — the
/// `CopyJobs` rows had a NULL `run_id`, the execution context minted one, and
/// the streaming receipt writer minted a second. A reservation taken at the gate
/// could therefore never be matched to the rows or the receipt that prove what
/// the run actually did, so crash reconciliation and revert refunds would both
/// have failed silently rather than loudly.
final class TrialRunIdentityTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrialRunIdentityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Organize

    /// For a completed organize run, the ledger's `run_id`, every
    /// `CopyJobs.run_id` for that run, and the audit receipt's run ID are the
    /// same value.
    func testOrganizeRunIDIsIdenticalAcrossLedgerQueuedJobsAndReceipt() throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let database = try OrganizerDatabase(url: destinationRoot.appendingPathComponent(".organize_cache.db"))
        defer { database.close() }

        var transfers: [PlannedTransfer] = []
        for index in 0..<3 {
            let sourceURL = sourceRoot.appendingPathComponent("photo_\(index).jpg")
            try Data("payload-\(index)".utf8).write(to: sourceURL)
            transfers.append(
                PlannedTransfer(
                    sourcePath: sourceURL.path,
                    destinationPath: destinationRoot
                        .appendingPathComponent("2024/01/01/photo_\(index).jpg").path,
                    identity: testFileIdentity(at: sourceURL),
                    dateBucket: "2024/01/01",
                    isDuplicate: false
                )
            )
        }

        // 1. The gate mints the ID and reserves against it, before anything is
        //    enqueued and before any media is touched.
        let runID = UUID()
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100))
        XCTAssertEqual(
            try ledger.reserve(
                runID: runID,
                accountKey: "app-txn-1",
                meter: .organize,
                count: transfers.count,
                destinationRoot: destinationRoot.path
            ),
            .permitted
        )

        // 2. The same ID goes down through enqueueing and execution.
        try database.enqueuePlannedTransfers(transfers, runID: runID)

        let logger = PersistentRunLogger(logURL: destinationRoot.appendingPathComponent(".organize_log.txt"))
        try logger.open()
        let result = try TransferExecutor().executeQueuedJobs(
            database: database,
            destinationRoot: destinationRoot,
            verifyCopies: false,
            runLogger: logger,
            runID: runID
        )
        XCTAssertEqual(result.copiedCount, 3)

        // 3. The ledger row, every CopyJobs row, and the receipt agree.
        let ledgerRunIDs = try ledger.openReservations().map(\.runID)
        XCTAssertEqual(ledgerRunIDs, [runID])

        let jobs = try database.loadQueuedJobs()
        XCTAssertEqual(jobs.count, 3)
        XCTAssertFalse(jobs.isEmpty, "The run must leave rows behind to attribute")
        for job in jobs {
            XCTAssertEqual(
                job.runID,
                runID,
                "Every CopyJobs row for this run must carry the reservation's run ID"
            )
        }

        XCTAssertEqual(try organizeReceiptRunID(in: destinationRoot), runID)

        // And the reservation finalizes against the count the executor reported.
        try ledger.finalize(runID: runID, actualCount: result.copiedCount)
        XCTAssertEqual(try ledger.balance(accountKey: "app-txn-1").usage.organizeUsed, 3)
        XCTAssertEqual(try ledger.openReservations(), [])
    }

    /// Exactly one receipt run ID is written — the streaming writer must use the
    /// injected value rather than minting a second one of its own.
    func testOrganizeReceiptDoesNotMintItsOwnRunID() throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("src2", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dst2", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let database = try OrganizerDatabase(url: destinationRoot.appendingPathComponent(".organize_cache.db"))
        defer { database.close() }
        let sourceURL = sourceRoot.appendingPathComponent("only.jpg")
        try Data("only".utf8).write(to: sourceURL)

        let runID = UUID()
        try database.enqueuePlannedTransfers(
            [
                PlannedTransfer(
                    sourcePath: sourceURL.path,
                    destinationPath: destinationRoot.appendingPathComponent("2024/01/01/only.jpg").path,
                    identity: testFileIdentity(at: sourceURL),
                    dateBucket: "2024/01/01",
                    isDuplicate: false
                )
            ],
            runID: runID
        )

        let logger = PersistentRunLogger(logURL: destinationRoot.appendingPathComponent(".organize_log.txt"))
        try logger.open()
        _ = try TransferExecutor().executeQueuedJobs(
            database: database,
            destinationRoot: destinationRoot,
            verifyCopies: false,
            runLogger: logger,
            runID: runID
        )

        // The receipt filename embeds the run ID, so a second minted UUID would
        // show up here as a name that does not match.
        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        let receipts = try FileManager.default
            .contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("audit_receipt_") && $0.pathExtension == "json" }
        XCTAssertEqual(receipts.count, 1)
        XCTAssertTrue(
            try XCTUnwrap(receipts.first).lastPathComponent.contains(runID.uuidString),
            "The receipt filename must carry the injected run ID, not a freshly minted one"
        )
        XCTAssertEqual(try organizeReceiptRunID(in: destinationRoot), runID)
    }

    /// A resumed transfer continues the run it is resuming rather than starting
    /// a new identity, so it reconciles against the reservation already taken.
    func testQueuedRunIDRecoversTheRunIDForAResume() throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("src3", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dst3", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let database = try OrganizerDatabase(url: destinationRoot.appendingPathComponent(".organize_cache.db"))
        defer { database.close() }

        XCTAssertNil(try database.queuedRunID(), "An empty queue has no run to resume")

        let runID = UUID()
        var transfers: [PlannedTransfer] = []
        for index in 0..<2 {
            let sourceURL = sourceRoot.appendingPathComponent("p\(index).jpg")
            try Data("p\(index)".utf8).write(to: sourceURL)
            transfers.append(
                PlannedTransfer(
                    sourcePath: sourceURL.path,
                    destinationPath: destinationRoot.appendingPathComponent("2024/01/01/p\(index).jpg").path,
                    identity: testFileIdentity(at: sourceURL),
                    dateBucket: "2024/01/01",
                    isDuplicate: false
                )
            )
        }
        try database.enqueuePlannedTransfers(transfers, runID: runID)

        XCTAssertEqual(try database.queuedRunID(), runID)
    }

    /// Legacy rows carry no run ID, and a queue that mixes two runs cannot be
    /// attributed to either. Both must read as "no run to resume" so the caller
    /// falls back to a fresh ID rather than adopting an arbitrary one.
    func testQueuedRunIDIsNilForLegacyOrMixedRows() throws {
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dst4", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let database = try OrganizerDatabase(url: destinationRoot.appendingPathComponent(".organize_cache.db"))
        defer { database.close() }

        // Legacy: enqueued without a run ID at all.
        try database.enqueueQueuedJobs([
            QueuedCopyJob(sourcePath: "/a.jpg", destinationPath: "/d/a.jpg", hash: "h1", status: .pending),
        ])
        XCTAssertNil(try database.queuedRunID())

        // Mixed: two different runs in one pending queue.
        try database.enqueueQueuedJobs([
            QueuedCopyJob(
                sourcePath: "/b.jpg", destinationPath: "/d/b.jpg", hash: "h2",
                status: .pending, runID: UUID()
            ),
            QueuedCopyJob(
                sourcePath: "/c.jpg", destinationPath: "/d/c.jpg", hash: "h3",
                status: .pending, runID: UUID()
            ),
        ])
        XCTAssertNil(try database.queuedRunID())
    }

    // MARK: - Dedupe

    /// A dedupe commit writes its receipt under the injected run ID, so the
    /// reservation taken before the commit matches the receipt afterwards.
    func testDedupeCommitReceiptCarriesTheInjectedRunID() async throws {
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dedupe", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let keep = destinationRoot.appendingPathComponent("keep.jpg")
        let duplicate = destinationRoot.appendingPathComponent("dupe.jpg")
        try Data(repeating: 0x42, count: 512).write(to: keep)
        try Data(repeating: 0x42, count: 512).write(to: duplicate)

        let plan = DeduplicationPlan(items: [
            DeduplicationPlan.Item(
                path: duplicate.path,
                sizeBytes: 512,
                owningClusterID: UUID(),
                owningClusterKind: .exactDuplicate,
                pairOrigin: nil,
                expectedIdentity: testFileIdentity(at: duplicate)
            )
        ])

        // The reservation is taken before the commit starts, keyed by this ID.
        let runID = UUID()
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100))
        XCTAssertEqual(
            try ledger.reserve(
                runID: runID,
                accountKey: "app-txn-1",
                meter: .dedupe,
                count: plan.items.count,
                destinationRoot: destinationRoot.path
            ),
            .permitted
        )

        let trashRoot = temporaryDirectoryURL.appendingPathComponent("FakeTrash", isDirectory: true)
        let executor = DeduplicateExecutor(
            fileOperations: TrialRunIdentityFileOperations(trashRoot: trashRoot)
        )
        var summary: DeduplicateCommitSummary?
        for try await event in executor.commit(
            plan: plan,
            destinationRoot: destinationRoot.path,
            hardDelete: false,
            runID: runID
        ) {
            if case let .complete(commitSummary) = event { summary = commitSummary }
        }
        XCTAssertEqual(try XCTUnwrap(summary).deletedCount, 1)

        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        let receipts = try FileManager.default
            .contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("dedupe_audit_receipt_") && $0.pathExtension == "json" }
        XCTAssertEqual(receipts.count, 1)
        let receiptURL = try XCTUnwrap(receipts.first)
        XCTAssertTrue(receiptURL.lastPathComponent.contains(runID.uuidString))

        let receipt = try JSONDecoder().decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.runID, runID)

        try ledger.finalize(runID: runID, actualCount: 1)
        XCTAssertEqual(try ledger.balance(accountKey: "app-txn-1").usage.dedupeUsed, 1)
    }

    // MARK: - Helpers

    private func organizeReceiptRunID(in destinationRoot: URL) throws -> UUID? {
        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        let receiptURL = try FileManager.default
            .contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("audit_receipt_") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .last
        let url = try XCTUnwrap(receiptURL)
        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        )
        return (payload["runID"] as? String).flatMap(UUID.init(uuidString:))
    }
}

/// Minimal `DeduplicateFileOperations` double: trashing moves the file into a
/// scratch directory so the test does not depend on `FileManager.trashItem`,
/// which sandboxed CI can reject for entitlement reasons unrelated to run IDs.
/// `quarantineItem` deliberately uses the protocol's real `rename` default, so
/// the quarantine-and-verify step still exercises production behaviour.
private struct TrialRunIdentityFileOperations: DeduplicateFileOperations {
    let trashRoot: URL

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func trashItem(at url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let destination = trashRoot.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(
            at: url,
            withIntermediateDirectories: createIntermediates
        )
    }
}
