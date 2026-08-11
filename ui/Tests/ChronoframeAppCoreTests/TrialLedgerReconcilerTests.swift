import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers step 4 of reserve → mutate → finalize → reconcile.
///
/// The cases that matter are the ones where reconciliation could get it wrong
/// in the customer's disfavour: an unreachable destination must never be read
/// as "nothing happened", and a second pass must never move a settled row.
final class TrialLedgerReconcilerTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private let account = "app-txn-1"
    private let caps = TrialAllowanceCaps(organizeFiles: 100, dedupeFiles: 20)

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrialLedgerReconcilerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    /// Evidence stub, so the reconciler's decisions are pinned without a disk.
    private struct StubEvidence: TrialReconciliationEvidence {
        let outcomes: [UUID: TrialReconciliationOutcome]
        func outcome(
            for reservation: OpenReservation,
            destinationRoot: URL
        ) -> TrialReconciliationOutcome {
            outcomes[reservation.runID] ?? .notApplicable
        }
    }

    private func destination(_ name: String) throws -> URL {
        let url = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    // MARK: - Decisions

    func testOpenReservationFinalizesAtTheProvenCount() throws {
        let root = try destination("dest")
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: 10, destinationRoot: root.path
        )
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 10)

        TrialLedgerReconciler(
            ledger: ledger,
            evidence: StubEvidence(outcomes: [runID: .completed(count: 4)])
        ).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 4)
        XCTAssertEqual(try ledger.openReservations(), [])
    }

    /// The rule the whole fail-closed posture rests on. An inaccessible path is
    /// not evidence of an empty run.
    func testUnreachableDestinationLeavesTheReservationOpenAndFullyCharged() throws {
        let root = try destination("dest")
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: 12, destinationRoot: root.path
        )

        TrialLedgerReconciler(
            ledger: ledger,
            evidence: StubEvidence(outcomes: [runID: .unreachable])
        ).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 12)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [runID])
    }

    func testReconcilingTwiceIsIdempotent() throws {
        let root = try destination("dest")
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: 9, destinationRoot: root.path
        )
        let reconciler = TrialLedgerReconciler(
            ledger: ledger,
            evidence: StubEvidence(outcomes: [runID: .completed(count: 3)])
        )

        reconciler.reconcile(destinationRoot: root)
        reconciler.reconcile(destinationRoot: root)
        reconciler.reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 3)
    }

    /// A pass for one destination must not settle another destination's run,
    /// whose evidence it has not looked at.
    func testAReservationForAnotherDestinationIsLeftAlone() throws {
        let mine = try destination("mine")
        let theirs = try destination("theirs")
        let ledger = InMemoryTrialLedger(caps: caps)
        let otherRun = UUID()
        _ = try ledger.reserve(
            runID: otherRun, accountKey: account, meter: .organize,
            count: 7, destinationRoot: theirs.path
        )

        TrialLedgerReconciler(
            ledger: ledger,
            evidence: StubEvidence(outcomes: [otherRun: .completed(count: 0)])
        ).reconcile(destinationRoot: mine)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 7)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [otherRun])
    }

    func testAReservationWithNoDestinationIsLeftOpen() throws {
        let root = try destination("dest")
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .dedupe,
            count: 5, destinationRoot: nil
        )

        TrialLedgerReconciler(
            ledger: ledger,
            evidence: StubEvidence(outcomes: [runID: .completed(count: 0)])
        ).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 5)
    }

    // MARK: - Filesystem evidence: organize

    func testOrganizeEvidenceCountsOnlyProvenCompletedCopies() throws {
        let root = try destination("organize")
        let database = try OrganizerDatabase(url: root.appendingPathComponent(".organize_cache.db"))
        let runID = UUID()

        try database.enqueueQueuedJobs([
            QueuedCopyJob(
                sourcePath: "/a.jpg", destinationPath: "/d/a.jpg", hash: "h1",
                status: .copied, runID: runID, mutationState: .finalized
            ),
            QueuedCopyJob(
                sourcePath: "/b.jpg", destinationPath: "/d/b.jpg", hash: "h2",
                status: .copied, runID: runID, mutationState: .finalized
            ),
            // Attempted and terminally failed: not resumable, and not charged.
            QueuedCopyJob(
                sourcePath: "/c.jpg", destinationPath: "/d/c.jpg", hash: "h3",
                status: .failed, runID: runID, mutationState: .intended
            ),
            // A different run entirely.
            QueuedCopyJob(
                sourcePath: "/d.jpg", destinationPath: "/d/d.jpg", hash: "h4",
                status: .copied, runID: UUID(), mutationState: .finalized
            ),
        ])
        XCTAssertEqual(try database.completedJobCount(runID: runID), 2)
        database.close()

        let ledger = InMemoryTrialLedger(caps: caps)
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: 3, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 2)
    }

    /// Crash after some copies landed, with the rest terminally failed: nothing
    /// more can happen under this reservation, so it settles at the true count.
    func testCrashAfterMutationBeforeFinalizeReconcilesToTheTrueCount() throws {
        let root = try destination("crash")
        let database = try OrganizerDatabase(url: root.appendingPathComponent(".organize_cache.db"))
        let runID = UUID()
        try database.enqueueQueuedJobs((0..<5).map { index in
            QueuedCopyJob(
                sourcePath: "/s\(index).jpg", destinationPath: "/d/s\(index).jpg", hash: "h\(index)",
                status: index < 3 ? .copied : .failed,
                runID: runID,
                mutationState: index < 3 ? .finalized : .intended
            )
        })
        database.close()

        let ledger = InMemoryTrialLedger(caps: caps)
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: 5, destinationRoot: root.path
        )
        // Before reconciliation the crash costs the full reservation.
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 5)

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 3)
    }

    /// A crash that leaves jobs PENDING leaves a resumable run, and a resumable
    /// run is not over.
    ///
    /// Settling here would charge the partial count and then let the resumed
    /// files copy for free, because `finalize` only ever acts on an open
    /// reservation — a second finalize after the resume is a no-op.
    func testCrashLeavingResumableJobsKeepsTheReservationOpen() throws {
        let root = try destination("resumable")
        let databaseURL = root.appendingPathComponent(".organize_cache.db")
        let database = try OrganizerDatabase(url: databaseURL)
        let runID = UUID()
        try database.enqueueQueuedJobs((0..<5).map { index in
            QueuedCopyJob(
                sourcePath: "/s\(index).jpg", destinationPath: "/d/s\(index).jpg", hash: "h\(index)",
                status: index < 3 ? .copied : .pending,
                runID: runID,
                mutationState: index < 3 ? .finalized : .intended
            )
        })
        XCTAssertEqual(try database.resumableJobCount(runID: runID), 2)
        database.close()

        let ledger = InMemoryTrialLedger(caps: caps)
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: 5, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 5)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [runID])

        // "Start Fresh" clears the queue, so the charge is not stranded forever:
        // once nothing is resumable the run settles at what actually landed.
        let reopened = try OrganizerDatabase(url: databaseURL)
        try reopened.clearAllJobs()
        try reopened.enqueueQueuedJobs((0..<3).map { index in
            QueuedCopyJob(
                sourcePath: "/s\(index).jpg", destinationPath: "/d/s\(index).jpg", hash: "h\(index)",
                status: .copied, runID: runID, mutationState: .finalized
            )
        })
        reopened.close()

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 3)
    }

    /// No queue database means no evidence either way, so the reservation must
    /// stay charged rather than be settled at zero.
    func testOrganizeWithNoQueueDatabaseStaysOpen() throws {
        let root = try destination("empty")
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: 6, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 6)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [runID])
    }

    // MARK: - Filesystem evidence: dedupe

    func testDedupeEvidenceCountsTrashedItemsFromTheReceipt() throws {
        let root = try destination("dedupe")
        let runID = UUID()
        try writeDedupeReceipt(
            in: root,
            runID: runID,
            items: [("/dest/a.jpg", "file:///Trash/a.jpg"), ("/dest/b.jpg", "file:///Trash/b.jpg"), ("/dest/c.jpg", nil)]
        )

        let ledger = InMemoryTrialLedger(caps: caps)
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .dedupe,
            count: 3, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        // Only the two with a trash URL actually moved.
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 2)
    }

    /// A crashed commit whose journal has not been folded into the receipt yet:
    /// the spool records the trash moves that did happen.
    func testDedupeEvidenceUnionsTheReceiptAndItsJournal() throws {
        let root = try destination("dedupe-spool")
        let runID = UUID()
        let receiptURL = try writeDedupeReceipt(
            in: root,
            runID: runID,
            items: [("/dest/a.jpg", "file:///Trash/a.jpg"), ("/dest/b.jpg", nil), ("/dest/c.jpg", nil)]
        )
        // The journal knows about b, which the receipt has not recorded yet, and
        // repeats a, which must not be double-counted.
        try writeSpool(
            at: receiptURL.appendingPathExtension("spool"),
            trashed: [
                (path: "/dest/b.jpg", trashURL: "file:///Trash/b.jpg"),
                (path: "/dest/a.jpg", trashURL: "file:///Trash/a.jpg"),
            ]
        )

        let ledger = InMemoryTrialLedger(caps: caps)
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .dedupe,
            count: 3, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 2)
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: receiptURL.appendingPathExtension("spool").path),
            "Reconciliation reads the journal; it must never delete it"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptURL.path))
    }

    func testDedupeWithNoReceiptForTheRunStaysOpen() throws {
        let root = try destination("dedupe-none")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(".organize_logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .dedupe,
            count: 4, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 4)
    }

    /// Recovery leaves a receipt PENDING when it could not settle the journal.
    /// The visible count is provisional, so settling now would lock in a charge
    /// a later pass could never correct.
    func testDedupePendingReceiptKeepsTheReservationOpen() throws {
        let root = try destination("dedupe-pending")
        let runID = UUID()
        try writeDedupeReceipt(
            in: root,
            runID: runID,
            status: "PENDING",
            items: [("/dest/a.jpg", "file:///Trash/a.jpg"), ("/dest/b.jpg", nil)]
        )

        let ledger = InMemoryTrialLedger(caps: caps)
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .dedupe,
            count: 2, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 2)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [runID])
    }

    /// A receipt that exists but cannot be decoded proves nothing. Counting the
    /// zero items we managed to read would settle the reservation on the
    /// strength of evidence we failed to read.
    func testDedupeUndecodableReceiptKeepsTheReservationOpen() throws {
        let root = try destination("dedupe-corrupt")
        let runID = UUID()
        let logs = root.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("this is not a receipt".utf8).write(
            to: logs.appendingPathComponent("dedupe_audit_receipt_20260810_120000_\(runID.uuidString).json")
        )

        let ledger = InMemoryTrialLedger(caps: caps)
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .dedupe,
            count: 6, destinationRoot: root.path
        )

        TrialLedgerReconciler(ledger: ledger).reconcile(destinationRoot: root)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 6)
    }

    // MARK: - Entry point

    func testRecoverAndReconcileRunsRecoveryEvenWithNoReconcilerWired() throws {
        let previous = DestinationRecovery.reconcilerProvider
        defer { DestinationRecovery.reconcilerProvider = previous }
        DestinationRecovery.reconcilerProvider = nil

        let root = try destination("entry")
        // Recovery on a clean destination is a no-op that must not throw.
        let report = DestinationRecovery.recoverAndReconcile(destinationRoot: root)
        XCTAssertEqual(report.recoveredItemCount, 0)
    }

    func testRecoverAndReconcileInvokesTheWiredReconciler() throws {
        final class SpyReconciler: TrialLedgerReconciling, @unchecked Sendable {
            let lock = NSLock()
            var roots: [URL] = []
            func reconcile(destinationRoot: URL) {
                lock.lock(); defer { lock.unlock() }
                roots.append(destinationRoot)
            }
        }

        let previous = DestinationRecovery.reconcilerProvider
        defer { DestinationRecovery.reconcilerProvider = previous }
        let spy = SpyReconciler()
        DestinationRecovery.reconcilerProvider = { spy }

        let root = try destination("entry2")
        _ = DestinationRecovery.recoverAndReconcile(destinationRoot: root)

        XCTAssertEqual(spy.roots, [root])
    }

    // MARK: - Helpers

    /// Built by encoding the real model rather than hand-writing JSON.
    ///
    /// `ReceiptClusterKind` has an associated-value case and therefore a custom
    /// `Codable`, so a hand-written fixture would be guessing at an encoding the
    /// production writer owns — and a guess that decoded to nothing would make
    /// these tests pass for the wrong reason.
    @discardableResult
    private func writeDedupeReceipt(
        in destinationRoot: URL,
        runID: UUID,
        status: String = "COMPLETED",
        items: [(path: String, trashURL: String?)]
    ) throws -> URL {
        let logs = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let receiptURL = logs.appendingPathComponent(
            "dedupe_audit_receipt_20260810_120000_\(runID.uuidString).json"
        )

        let receipt = DeduplicateAuditReceipt(
            runID: runID,
            status: status,
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            destinationRoot: destinationRoot.path,
            items: items.map { item in
                DeduplicateAuditReceipt.Item(
                    originalPath: item.path,
                    sizeBytes: 1024,
                    trashURL: item.trashURL,
                    method: .trash,
                    clusterID: UUID(),
                    clusterKind: .exactDuplicate
                )
            },
            bytesReclaimed: 2048
        )
        try JSONEncoder.dedupe.encode(receipt).write(to: receiptURL)
        return receiptURL
    }

    /// Likewise: real `DeduplicateSpoolRecord` values, one JSON object per line,
    /// which is the journal format the executor appends.
    private func writeSpool(
        at spoolURL: URL,
        trashed: [(path: String, trashURL: String)]
    ) throws {
        let lines = try trashed.map { entry -> String in
            let record = DeduplicateSpoolRecord(
                state: .trashed,
                originalPath: entry.path,
                actualTrashURL: entry.trashURL
            )
            // `JSONEncoder.dedupe` is prettyPrinted; the journal is one JSON
            // object PER LINE and `loadSpoolRecords` decodes line by line, so a
            // pretty-printed record decodes as nothing at all. The executor
            // appends with `dedupeSpool` for exactly this reason.
            let data = try JSONEncoder.dedupeSpool.encode(record)
            return String(data: data, encoding: .utf8) ?? ""
        }
        try Data(lines.joined(separator: "\n").utf8).write(to: spoolURL)
    }
}
