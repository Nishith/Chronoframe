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

        // The receipt writes dates as ISO8601 strings, so the decoder needs the
        // matching strategy — the same one `RunHistoryIndexer` uses.
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let receipt = try decoder.decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.runID, runID)

        try ledger.finalize(runID: runID, actualCount: 1)
        XCTAssertEqual(try ledger.balance(accountKey: "app-txn-1").usage.dedupeUsed, 1)
    }

    /// End to end, the property T12's refunds rest on: a real organize run's
    /// receipt loads through `RevertExecutor` and hands back the *same* run ID
    /// the reservation was taken under, as a usable refund key.
    ///
    /// This is what ties T3 (one run ID) to T4 (the receipt exposes it). Either
    /// half alone looks fine and refunds silently never fire.
    func testARealRunsReceiptYieldsTheReservationRunIDAsARefundKey() throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("src5", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dst5", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        let database = try OrganizerDatabase(url: destinationRoot.appendingPathComponent(".organize_cache.db"))
        defer { database.close() }
        let sourceURL = sourceRoot.appendingPathComponent("shot.jpg")
        try Data("shot".utf8).write(to: sourceURL)

        let runID = UUID()
        try database.enqueuePlannedTransfers(
            [
                PlannedTransfer(
                    sourcePath: sourceURL.path,
                    destinationPath: destinationRoot.appendingPathComponent("2024/01/01/shot.jpg").path,
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

        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        let receiptURL = try XCTUnwrap(
            try FileManager.default
                .contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)
                .first { $0.lastPathComponent.hasPrefix("audit_receipt_") && $0.pathExtension == "json" }
        )

        let receipt = try RevertExecutor().loadReceipt(at: receiptURL)
        XCTAssertEqual(receipt.schemaVersion, 3, "The writer must stamp the version that marks the run ID trustworthy")
        XCTAssertEqual(receipt.reservationRunID, runID)
        XCTAssertFalse(receipt.transfers.isEmpty)
    }

    // MARK: - Receipt filename collision

    /// Sharing a run ID must not let one receipt overwrite another.
    ///
    /// A resumed run reuses the run ID of the run it resumes, on purpose, and
    /// the receipt filename's timestamp only has one-second precision. Without
    /// collision resolution a resume starting in the same second would pick the
    /// identical stem, and `createFile` truncates — destroying the earlier
    /// PENDING/ABORTED receipt covering files already copied, which would leave
    /// them absent from Run History and no longer revertable.
    func testReceiptStemIsUniqueWhenARunIDAndSecondAreShared() throws {
        let logsDirectory = temporaryDirectoryURL.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let runID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

        let first = TransferExecutor.uniqueReceiptStem(
            in: logsDirectory,
            createdAt: createdAt,
            runID: runID,
            fileManager: .default
        )
        // Nothing exists yet, so the ordinary format is preserved exactly.
        XCTAssertTrue(first.hasPrefix("audit_receipt_"))
        XCTAssertTrue(first.hasSuffix(runID.uuidString))

        // The first run's receipt now exists, as it would after an abort.
        let firstReceipt = logsDirectory.appendingPathComponent("\(first).json")
        try Data(#"{"status":"ABORTED"}"#.utf8).write(to: firstReceipt)

        // Same run ID, same wall-clock second: the resume must not reuse it.
        let second = TransferExecutor.uniqueReceiptStem(
            in: logsDirectory,
            createdAt: createdAt,
            runID: runID,
            fileManager: .default
        )
        XCTAssertNotEqual(second, first)
        XCTAssertTrue(second.contains(runID.uuidString), "The run ID must still identify the run")
        XCTAssertEqual(
            try String(contentsOf: firstReceipt, encoding: .utf8),
            #"{"status":"ABORTED"}"#,
            "The earlier receipt must survive untouched"
        )

        // A spool alone also blocks the stem — the pair has to move together.
        let thirdBlocker = logsDirectory.appendingPathComponent("\(second).transfers.tmp")
        try Data().write(to: thirdBlocker)
        let third = TransferExecutor.uniqueReceiptStem(
            in: logsDirectory,
            createdAt: createdAt,
            runID: runID,
            fileManager: .default
        )
        XCTAssertNotEqual(third, first)
        XCTAssertNotEqual(third, second)
    }

    /// The collision suffix must not break the two things that read these names:
    /// Run History parses the leading `yyyyMMdd_HHmmss`, and crash recovery
    /// derives the spool path from whatever stem the receipt has.
    func testCollisionSuffixKeepsTheParsableTimestampPrefix() throws {
        let logsDirectory = temporaryDirectoryURL.appendingPathComponent("logs2", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let runID = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)

        let base = TransferExecutor.uniqueReceiptStem(
            in: logsDirectory, createdAt: createdAt, runID: runID, fileManager: .default
        )
        try Data("{}".utf8).write(to: logsDirectory.appendingPathComponent("\(base).json"))
        let suffixed = TransferExecutor.uniqueReceiptStem(
            in: logsDirectory, createdAt: createdAt, runID: runID, fileManager: .default
        )

        for stem in [base, suffixed] {
            let remainder = stem.dropFirst("audit_receipt_".count)
            let timestamp = String(remainder.prefix(15))
            XCTAssertNotNil(
                timestamp.range(of: #"^\d{8}_\d{6}$"#, options: .regularExpression),
                "Run History reads the first 15 characters after the prefix: \(stem)"
            )
        }
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
