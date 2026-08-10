import Foundation
import SQLite3
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers the durable reservation ledger.
///
/// The properties under test are the ones the whole metered tier rests on: a
/// refusal writes nothing, a duplicate finalize cannot double-charge, an open
/// reservation stays charged at its full reserved amount, and a partial revert
/// refunds exactly the items it actually restored.
final class TrialLedgerDatabaseTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private let account = "app-txn-1"
    private let otherAccount = "app-txn-2"
    private let caps = TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 4)

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("TrialLedgerDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private func ledgerURL(_ name: String = "ledger.db") -> URL {
        temporaryDirectoryURL.appendingPathComponent(name)
    }

    private func makeLedger(_ name: String = "ledger.db") throws -> TrialLedgerDatabase {
        try TrialLedgerDatabase(url: ledgerURL(name), caps: caps)
    }

    private func reservationRowCount(_ url: URL) throws -> Int {
        try rawCount(url, sql: "SELECT COUNT(*) FROM Reservations;")
    }

    private func rawCount(_ url: URL, sql: String) throws -> Int {
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, sql, -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        return Int(sqlite3_column_int64(statement, 0))
    }

    // MARK: - Schema and location

    func testLedgerLivesOutsideAnyDestinationInApplicationSupport() {
        let url = TrialLedgerPaths.ledgerURL()
        XCTAssertEqual(url.lastPathComponent, "ledger.db")
        XCTAssertEqual(url.deletingLastPathComponent().lastPathComponent, "trial")
        XCTAssertEqual(
            url.deletingLastPathComponent().deletingLastPathComponent(),
            RuntimePaths.applicationSupportDirectory()
        )
        // The allowance spans destinations, so the ledger must not sit inside one.
        XCTAssertFalse(url.path.contains(".organize_logs"))
    }

    func testFreshLedgerUsesWalAndStampsTheSchemaVersion() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }

        XCTAssertEqual(
            try rawCount(ledgerURL(), sql: "PRAGMA user_version;"),
            Int(TrialLedgerDatabase.schemaVersion)
        )
        var handle: OpaquePointer?
        XCTAssertEqual(sqlite3_open_v2(ledgerURL().path, &handle, SQLITE_OPEN_READONLY, nil), SQLITE_OK)
        defer { sqlite3_close(handle) }
        var statement: OpaquePointer?
        XCTAssertEqual(sqlite3_prepare_v2(handle, "PRAGMA journal_mode;", -1, &statement, nil), SQLITE_OK)
        defer { sqlite3_finalize(statement) }
        XCTAssertEqual(sqlite3_step(statement), SQLITE_ROW)
        XCTAssertEqual(String(cString: sqlite3_column_text(statement, 0)).lowercased(), "wal")
    }

    func testFreshLedgerStartsUnspent() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let balance = try ledger.balance(accountKey: account)
        XCTAssertEqual(balance.remaining(for: .organize), 10)
        XCTAssertEqual(balance.remaining(for: .dedupe), 4)
        XCTAssertEqual(try ledger.openReservations(), [])
    }

    // MARK: - Reserve / finalize

    func testReserveThenFinalizeWithFewerThanReservedChargesTheActualCount() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let runID = UUID()

        XCTAssertEqual(
            try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: "/dest"),
            .permitted
        )
        // While open, the whole reservation is charged.
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 4)

        try ledger.finalize(runID: runID, actualCount: 2)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 8)
        XCTAssertEqual(try ledger.openReservations(), [])
    }

    func testDuplicateFinalizeDoesNotDoubleCharge() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 5, destinationRoot: nil)

        try ledger.finalize(runID: runID, actualCount: 5)
        try ledger.finalize(runID: runID, actualCount: 5)
        try ledger.finalize(runID: runID, actualCount: 5)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 5)
        XCTAssertEqual(try reservationRowCount(ledgerURL()), 1)
    }

    func testFinalizeOnAReleasedOrAlreadyFinalizedRowIsANoOp() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }

        let released = UUID()
        _ = try ledger.reserve(runID: released, accountKey: account, meter: .organize, count: 3, destinationRoot: nil)
        try ledger.release(runID: released)
        try ledger.finalize(runID: released, actualCount: 3)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 0)

        let finalized = UUID()
        _ = try ledger.reserve(runID: finalized, accountKey: account, meter: .organize, count: 4, destinationRoot: nil)
        try ledger.finalize(runID: finalized, actualCount: 1)
        try ledger.finalize(runID: finalized, actualCount: 4)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 1)
    }

    func testFinalizeCannotChargeMoreThanWasReserved() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 3, destinationRoot: nil)

        try ledger.finalize(runID: runID, actualCount: 99)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 3)
    }

    func testFinalizeOnAnUnknownRunIsHarmless() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        try ledger.finalize(runID: UUID(), actualCount: 4)
        try ledger.release(runID: UUID())
        XCTAssertEqual(try reservationRowCount(ledgerURL()), 0)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 0)
    }

    func testReReservingAnExistingRunIDDoesNotStack() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let runID = UUID()

        XCTAssertEqual(
            try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: "/dest"),
            .permitted
        )
        // A resumed transfer re-enters the gate with the same run ID.
        XCTAssertEqual(
            try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: "/dest"),
            .permitted
        )

        XCTAssertEqual(try reservationRowCount(ledgerURL()), 1)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 6)
    }

    // MARK: - Refusal

    func testARefusalWritesNothing() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        _ = try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 8, destinationRoot: nil)
        let rowsBefore = try reservationRowCount(ledgerURL())

        let decision = try ledger.reserve(
            runID: UUID(),
            accountKey: account,
            meter: .organize,
            count: 3,
            destinationRoot: nil
        )

        XCTAssertEqual(decision, .refused(TrialRefusal(meter: .organize, requested: 3, remaining: 2)))
        XCTAssertEqual(try reservationRowCount(ledgerURL()), rowsBefore)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 8)
    }

    func testTwoReservationsOnOneMeterCannotJointlyExceedTheCap() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }

        XCTAssertEqual(
            try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 7, destinationRoot: nil),
            .permitted
        )
        XCTAssertEqual(
            try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 4, destinationRoot: nil),
            .refused(TrialRefusal(meter: .organize, requested: 4, remaining: 3))
        )
        XCTAssertEqual(
            try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 3, destinationRoot: nil),
            .permitted
        )
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 0)
    }

    func testConcurrentOrganizeAndDedupeReservationsDoNotInterfere() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let organizeRun = UUID()
        let dedupeRun = UUID()

        XCTAssertEqual(
            try ledger.reserve(runID: organizeRun, accountKey: account, meter: .organize, count: 10, destinationRoot: "/a"),
            .permitted
        )
        XCTAssertEqual(
            try ledger.reserve(runID: dedupeRun, accountKey: account, meter: .dedupe, count: 4, destinationRoot: "/b"),
            .permitted
        )

        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 0)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 0)
        XCTAssertEqual(try ledger.openReservations().count, 2)

        try ledger.finalize(runID: organizeRun, actualCount: 3)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 7)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 0)
    }

    func testAllowanceIsScopedPerAccount() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        _ = try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 10, destinationRoot: nil)

        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 0)
        XCTAssertEqual(try ledger.balance(accountKey: otherAccount).remaining(for: .organize), 10)
    }

    // MARK: - Crash posture

    func testAnOpenReservationStaysFullyChargedAcrossReopen() throws {
        let runID = UUID()
        do {
            let ledger = try makeLedger()
            _ = try ledger.reserve(
                runID: runID,
                accountKey: account,
                meter: .organize,
                count: 9,
                destinationRoot: "/dest"
            )
            // No finalize: this is the crash case.
            ledger.close()
        }

        let reopened = try makeLedger()
        defer { reopened.close() }
        XCTAssertEqual(try reopened.balance(accountKey: account).remaining(for: .organize), 1)

        let open = try reopened.openReservations()
        XCTAssertEqual(open.count, 1)
        XCTAssertEqual(open.first?.runID, runID)
        XCTAssertEqual(open.first?.reservedCount, 9)
        XCTAssertEqual(open.first?.meter, .organize)
        XCTAssertEqual(open.first?.accountKey, account)
        XCTAssertEqual(open.first?.destinationRoot, "/dest")
    }

    func testOpenReservationsReturnsOnlyOpenRows() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let stillOpen = UUID()
        let finalized = UUID()
        let released = UUID()

        _ = try ledger.reserve(runID: finalized, accountKey: account, meter: .organize, count: 1, destinationRoot: nil)
        _ = try ledger.reserve(runID: released, accountKey: account, meter: .organize, count: 1, destinationRoot: nil)
        _ = try ledger.reserve(runID: stillOpen, accountKey: account, meter: .dedupe, count: 1, destinationRoot: nil)
        try ledger.finalize(runID: finalized, actualCount: 1)
        try ledger.release(runID: released)

        XCTAssertEqual(try ledger.openReservations().map(\.runID), [stillOpen])
    }

    func testReleaseRefundsTheWholeReservation() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .dedupe, count: 4, destinationRoot: nil)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 0)

        try ledger.release(runID: runID)
        try ledger.release(runID: runID)

        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 4)
    }

    // MARK: - Refunds

    func testPartialRefundThenFullerRefundRefundsOnlyTheNewlyRestoredItems() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 4, destinationRoot: nil)
        try ledger.finalize(runID: runID, actualCount: 4)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 4)

        // First revert: two files matched their receipt hash, two did not.
        try ledger.refund(
            receiptRunID: runID,
            accountKey: account,
            meter: .organize,
            itemPaths: ["/dest/a.jpg", "/dest/b.jpg"]
        )
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 2)

        // Second revert after the conflicts are resolved: reports all four.
        try ledger.refund(
            receiptRunID: runID,
            accountKey: account,
            meter: .organize,
            itemPaths: ["/dest/a.jpg", "/dest/b.jpg", "/dest/c.jpg", "/dest/d.jpg"]
        )
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 0)
        XCTAssertEqual(try rawCount(ledgerURL(), sql: "SELECT COUNT(*) FROM RefundedItems;"), 4)
    }

    func testReRunningAnIdenticalRefundAddsNothing() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 3, destinationRoot: nil)
        try ledger.finalize(runID: runID, actualCount: 3)

        for _ in 0..<3 {
            try ledger.refund(
                receiptRunID: runID,
                accountKey: account,
                meter: .organize,
                itemPaths: ["/dest/a.jpg", "/dest/b.jpg"]
            )
        }

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 1)
        XCTAssertEqual(try rawCount(ledgerURL(), sql: "SELECT COUNT(*) FROM RefundedItems;"), 2)
    }

    func testTheSamePathUnderTwoReceiptsRefundsTwice() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let first = UUID()
        let second = UUID()
        _ = try ledger.reserve(runID: first, accountKey: account, meter: .organize, count: 1, destinationRoot: nil)
        try ledger.finalize(runID: first, actualCount: 1)
        _ = try ledger.reserve(runID: second, accountKey: account, meter: .organize, count: 1, destinationRoot: nil)
        try ledger.finalize(runID: second, actualCount: 1)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 2)

        // Organize, revert, organize the same file again, revert again: two
        // distinct charges, so two distinct refunds.
        try ledger.refund(receiptRunID: first, accountKey: account, meter: .organize, itemPaths: ["/dest/a.jpg"])
        try ledger.refund(receiptRunID: second, accountKey: account, meter: .organize, itemPaths: ["/dest/a.jpg"])

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 0)
    }

    func testRefundForAnUnknownReceiptIsHarmless() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }

        try ledger.refund(
            receiptRunID: UUID(),
            accountKey: account,
            meter: .organize,
            itemPaths: ["/dest/ghost.jpg", "/dest/ghost2.jpg"]
        )

        let balance = try ledger.balance(accountKey: account)
        XCTAssertEqual(balance.usage.organizeUsed, 0)
        XCTAssertEqual(balance.remaining(for: .organize), 10)
    }

    /// Reverting work that was never charged must not bank a credit.
    ///
    /// The scenario is real rather than hypothetical: run IDs ship before
    /// enforcement does, so a receipt can exist with no reservation behind it.
    /// If refunds were summed across the account and subtracted at the end,
    /// reverting that run would quietly enlarge the next real run's allowance.
    func testRefundForAnUnchargedReceiptCannotCreditALaterReservation() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }

        // A revert of a run that predates enforcement: a receipt, no reservation.
        try ledger.refund(
            receiptRunID: UUID(),
            accountKey: account,
            meter: .organize,
            itemPaths: ["/dest/old1.jpg", "/dest/old2.jpg", "/dest/old3.jpg"]
        )

        // A later, properly reserved run must be charged in full.
        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: nil)
        try ledger.finalize(runID: runID, actualCount: 6)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 6)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 4)
    }

    /// A refund is capped by the charge on its own reservation, so an
    /// over-reported revert cannot borrow headroom from a sibling run.
    func testRefundCannotExceedTheChargeOnItsOwnReservation() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }

        let small = UUID()
        _ = try ledger.reserve(runID: small, accountKey: account, meter: .organize, count: 2, destinationRoot: nil)
        try ledger.finalize(runID: small, actualCount: 2)
        let other = UUID()
        _ = try ledger.reserve(runID: other, accountKey: account, meter: .organize, count: 5, destinationRoot: nil)
        try ledger.finalize(runID: other, actualCount: 5)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 7)

        // Six items reported against a run that was only charged two.
        try ledger.refund(
            receiptRunID: small,
            accountKey: account,
            meter: .organize,
            itemPaths: (0..<6).map { "/dest/\($0).jpg" }
        )

        // Its own two come back; the other reservation's five are untouched.
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 5)
    }

    /// A released reservation was never charged, so its refunds credit nothing.
    func testRefundAgainstAReleasedReservationCreditsNothing() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }

        let released = UUID()
        _ = try ledger.reserve(runID: released, accountKey: account, meter: .organize, count: 4, destinationRoot: nil)
        try ledger.release(runID: released)
        try ledger.refund(
            receiptRunID: released,
            accountKey: account,
            meter: .organize,
            itemPaths: ["/dest/a.jpg", "/dest/b.jpg"]
        )

        let charged = UUID()
        _ = try ledger.reserve(runID: charged, accountKey: account, meter: .organize, count: 3, destinationRoot: nil)
        try ledger.finalize(runID: charged, actualCount: 3)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 3)
    }

    func testRefundWithNoPathsWritesNothing() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        try ledger.refund(receiptRunID: UUID(), accountKey: account, meter: .organize, itemPaths: [])
        XCTAssertEqual(try rawCount(ledgerURL(), sql: "SELECT COUNT(*) FROM RefundedItems;"), 0)
    }

    func testRefundsAreScopedPerMeter() throws {
        let ledger = try makeLedger()
        defer { ledger.close() }
        let organizeRun = UUID()
        _ = try ledger.reserve(runID: organizeRun, accountKey: account, meter: .organize, count: 2, destinationRoot: nil)
        try ledger.finalize(runID: organizeRun, actualCount: 2)
        let dedupeRun = UUID()
        _ = try ledger.reserve(runID: dedupeRun, accountKey: account, meter: .dedupe, count: 2, destinationRoot: nil)
        try ledger.finalize(runID: dedupeRun, actualCount: 2)

        try ledger.refund(receiptRunID: dedupeRun, accountKey: account, meter: .dedupe, itemPaths: ["/dest/x.jpg"])

        let balance = try ledger.balance(accountKey: account)
        XCTAssertEqual(balance.usage.organizeUsed, 2)
        XCTAssertEqual(balance.usage.dedupeUsed, 1)
    }

    // MARK: - Fail-closed

    func testCorruptLedgerReportsZeroRemainingRatherThanAFreshAllowance() throws {
        let url = ledgerURL("corrupt.db")
        try Data("this is not a SQLite database, it is a text file".utf8).write(to: url)

        let outcome = TrialLedgerOpener.open(url: url, caps: caps)

        guard case let .unreadable(ledger, error) = outcome else {
            return XCTFail("A corrupt ledger must not open as ready")
        }
        XCTAssertNotNil(error.errorDescription)
        // Never a raw SQLite message on its own.
        XCTAssertTrue(error.errorDescription?.hasPrefix("Chronoframe") == true)

        let balance = try ledger.balance(accountKey: account)
        XCTAssertEqual(balance.remaining(for: .organize), 0)
        XCTAssertEqual(balance.remaining(for: .dedupe), 0)

        // And it refuses work rather than handing out a free reset.
        XCTAssertEqual(
            try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 1, destinationRoot: nil),
            .refused(TrialRefusal(meter: .organize, requested: 1, remaining: 0))
        )
        // A no-op run is still allowed through, as everywhere else.
        XCTAssertEqual(
            try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 0, destinationRoot: nil),
            .permitted
        )
        // Revert bookkeeping must never throw, whatever the ledger's state.
        XCTAssertNoThrow(
            try ledger.refund(receiptRunID: UUID(), accountKey: account, meter: .organize, itemPaths: ["/x"])
        )
        XCTAssertNoThrow(try ledger.finalize(runID: UUID(), actualCount: 1))
        XCTAssertNoThrow(try ledger.release(runID: UUID()))
        XCTAssertEqual(try ledger.openReservations(), [])
    }

    func testOpeningAHealthyLedgerReportsReady() throws {
        let outcome = TrialLedgerOpener.open(url: ledgerURL(), caps: caps)
        guard case let .ready(ledger) = outcome else {
            return XCTFail("A fresh ledger must open as ready")
        }
        XCTAssertNil(outcome.failure)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 10)
        (ledger as? TrialLedgerDatabase)?.close()
    }

    // MARK: - In-memory double

    /// The double is what the higher layers test against, so it has to agree
    /// with the database on the behaviours those layers depend on.
    func testInMemoryDoubleMatchesTheDatabaseSemantics() throws {
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()

        XCTAssertEqual(
            try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: "/dest"),
            .permitted
        )
        // Open reservations charge in full.
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 4)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [runID])
        // Re-reserving does not stack.
        XCTAssertEqual(
            try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: "/dest"),
            .permitted
        )
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 6)
        // Refusals do not write.
        XCTAssertEqual(
            try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 5, destinationRoot: nil),
            .refused(TrialRefusal(meter: .organize, requested: 5, remaining: 4))
        )
        XCTAssertEqual(try ledger.openReservations().count, 1)
        // Duplicate finalize does not double-charge, and clamps to the reservation.
        try ledger.finalize(runID: runID, actualCount: 2)
        try ledger.finalize(runID: runID, actualCount: 6)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 2)
        XCTAssertEqual(try ledger.openReservations(), [])
        // Item-level refunds are idempotent, and capped by their own charge.
        try ledger.refund(receiptRunID: runID, accountKey: account, meter: .organize, itemPaths: ["/a"])
        try ledger.refund(receiptRunID: runID, accountKey: account, meter: .organize, itemPaths: ["/a", "/b"])
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 0)
        try ledger.refund(receiptRunID: runID, accountKey: account, meter: .organize, itemPaths: ["/c", "/d"])
        // An uncharged refund credits nothing, now or against a later run.
        try ledger.refund(receiptRunID: UUID(), accountKey: account, meter: .organize, itemPaths: ["/ghost"])
        let laterRun = UUID()
        _ = try ledger.reserve(runID: laterRun, accountKey: account, meter: .organize, count: 3, destinationRoot: nil)
        try ledger.finalize(runID: laterRun, actualCount: 3)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 3)
        // Release frees the whole reservation.
        let released = UUID()
        _ = try ledger.reserve(runID: released, accountKey: account, meter: .dedupe, count: 4, destinationRoot: nil)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 0)
        try ledger.release(runID: released)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 4)
        // Accounts are independent.
        XCTAssertEqual(try ledger.balance(accountKey: otherAccount).remaining(for: .organize), 10)
    }
}
