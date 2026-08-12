import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers refunding allowance for work a revert undid (free-trial step 4, T12).
///
/// The cases that matter are the ones where a wrong answer either charges a
/// customer for work they undid, or hands out allowance nobody paid for.
final class TrialRevertRefundTests: XCTestCase {
    private let account = "app-txn-1"

    // MARK: - Fixtures

    /// A ledger with `organizeCharged` files already charged to one run, and
    /// the run ID they were charged under.
    private func chargedLedger(
        organizeCharged: Int,
        caps: TrialAllowanceCaps = TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100)
    ) throws -> (ledger: InMemoryTrialLedger, runID: UUID) {
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: organizeCharged, destinationRoot: nil
        )
        try ledger.finalize(runID: runID, actualCount: organizeCharged)
        return (ledger, runID)
    }

    private func refunder(_ ledger: any TrialLedger) -> EntitlementTrialRefunder {
        EntitlementTrialRefunder(ledger: ledger) { [account] in account }
    }

    private func organizeUsed(_ ledger: InMemoryTrialLedger) throws -> Int {
        try ledger.balance(accountKey: account).usage.organizeUsed
    }

    // MARK: - Refunding

    /// A full revert gives back everything the run was charged for.
    func testFullRevertRefundsEveryItem() async throws {
        let (ledger, runID) = try chargedLedger(organizeCharged: 3)
        XCTAssertEqual(try organizeUsed(ledger), 3)

        await refunder(ledger).refundUndoneWork(
            receiptRunID: runID,
            meter: .organize,
            itemPaths: ["/dest/a.jpg", "/dest/b.jpg", "/dest/c.jpg"]
        )

        XCTAssertEqual(try organizeUsed(ledger), 0, "Everything was undone, so nothing stays charged")
    }

    /// Reverts are routinely partial — a destination file the user edited is
    /// preserved by design — so only the restored subset comes back.
    func testPartialRevertRefundsOnlyTheRestoredSubset() async throws {
        let (ledger, runID) = try chargedLedger(organizeCharged: 3)

        await refunder(ledger).refundUndoneWork(
            receiptRunID: runID, meter: .organize, itemPaths: ["/dest/a.jpg"]
        )

        XCTAssertEqual(try organizeUsed(ledger), 2, "Two files are still in the destination, so two stay charged")
    }

    /// The user fixes the conflict and reverts again. The second pass refunds
    /// the newly restored items and re-records the ones it already credited,
    /// which must not double-count.
    func testSecondRevertRefundsOnlyTheNewItems() async throws {
        let (ledger, runID) = try chargedLedger(organizeCharged: 3)
        let refunder = refunder(ledger)

        await refunder.refundUndoneWork(
            receiptRunID: runID, meter: .organize, itemPaths: ["/dest/a.jpg"]
        )
        XCTAssertEqual(try organizeUsed(ledger), 2)

        // The receipt still lists all three, and this pass removes the other
        // two — so it reports one already-credited path alongside them.
        await refunder.refundUndoneWork(
            receiptRunID: runID, meter: .organize, itemPaths: ["/dest/a.jpg", "/dest/b.jpg", "/dest/c.jpg"]
        )

        XCTAssertEqual(try organizeUsed(ledger), 0)
    }

    /// Re-running an identical revert refunds nothing further. The ledger is
    /// keyed by `(receiptRunID, itemPath)`, so an item can only be credited
    /// once however many times a revert reports it.
    func testIdenticalRevertRefundsNothingFurther() async throws {
        let (ledger, runID) = try chargedLedger(organizeCharged: 3)
        let refunder = refunder(ledger)
        let paths = ["/dest/a.jpg", "/dest/b.jpg"]

        await refunder.refundUndoneWork(receiptRunID: runID, meter: .organize, itemPaths: paths)
        XCTAssertEqual(try organizeUsed(ledger), 1)

        await refunder.refundUndoneWork(receiptRunID: runID, meter: .organize, itemPaths: paths)
        XCTAssertEqual(try organizeUsed(ledger), 1, "The same items cannot be credited twice")
    }

    /// A refund can never become a credit against a later run. It nets against
    /// its own reservation and is floored there — otherwise reverting an old
    /// run would buy allowance for a new one.
    func testRefundNeverCreditsBeyondItsOwnReservation() async throws {
        let (ledger, runID) = try chargedLedger(organizeCharged: 2)

        // Five paths against a two-file reservation: the extra three have no
        // charge behind them.
        await refunder(ledger).refundUndoneWork(
            receiptRunID: runID,
            meter: .organize,
            itemPaths: (0..<5).map { "/dest/\($0).jpg" }
        )

        XCTAssertEqual(try organizeUsed(ledger), 0, "Floored at zero, never negative")

        // And a later run is charged in full, not discounted by the overage.
        let laterRunID = UUID()
        _ = try ledger.reserve(
            runID: laterRunID, accountKey: account, meter: .organize,
            count: 4, destinationRoot: nil
        )
        XCTAssertEqual(try organizeUsed(ledger), 4)
    }

    // MARK: - When not to refund

    /// A receipt with no trustworthy run ID refunds nothing and does not throw.
    ///
    /// Refunds are keyed by run ID, so guessing one would credit the wrong run.
    /// Not refunding leaves the customer charged for what they already agreed
    /// to; refunding wrongly hands out allowance nobody paid for.
    func testLegacyReceiptWithNoRunIDRefundsNothing() async throws {
        let (ledger, _) = try chargedLedger(organizeCharged: 3)

        await refunder(ledger).refundUndoneWork(
            receiptRunID: nil, meter: .organize, itemPaths: ["/dest/a.jpg", "/dest/b.jpg"]
        )

        XCTAssertEqual(try organizeUsed(ledger), 3)
    }

    /// A revert that undid nothing records nothing — and must not need a
    /// ledger at all to say so.
    func testRevertThatUndidNothingNeverTouchesTheLedger() async throws {
        let ledger = ExplodingRefundLedger()

        await EntitlementTrialRefunder(ledger: ledger) { "app-txn-1" }
            .refundUndoneWork(receiptRunID: UUID(), meter: .organize, itemPaths: [])

        XCTAssertFalse(ledger.wasTouched, "An empty revert must not cost a ledger write")
    }

    /// Without an account key there is nothing to attribute the credit to, so
    /// it records nothing rather than guessing.
    func testMissingAccountKeyRefundsNothing() async throws {
        let (ledger, runID) = try chargedLedger(organizeCharged: 3)

        await EntitlementTrialRefunder(ledger: ledger) { nil }
            .refundUndoneWork(receiptRunID: runID, meter: .organize, itemPaths: ["/dest/a.jpg"])

        XCTAssertEqual(try organizeUsed(ledger), 3)
    }

    /// A ledger that cannot record the refund must not fail the revert. The
    /// files are already back; reporting an error now would tell the customer
    /// their revert broke when it did not.
    func testUnwritableLedgerDoesNotFailTheRefund() async throws {
        await refunder(ThrowingRefundLedger()).refundUndoneWork(
            receiptRunID: UUID(), meter: .organize, itemPaths: ["/dest/a.jpg"]
        )
        // Reaching here without throwing is the assertion.
    }

    /// The unmetered channels credit nothing, because they charged nothing.
    func testNoOpRefunderRecordsNothing() async throws {
        await NoOpTrialRefunder().refundUndoneWork(
            receiptRunID: UUID(), meter: .dedupe, itemPaths: ["/dest/a.jpg"]
        )
        // Reaching here without throwing is the assertion.
    }

    // MARK: - Meters are separate

    /// A dedupe refund does not credit organize allowance.
    func testRefundAppliesOnlyToItsOwnMeter() async throws {
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100))
        let organizeRun = UUID()
        _ = try ledger.reserve(
            runID: organizeRun, accountKey: account, meter: .organize,
            count: 3, destinationRoot: nil
        )
        try ledger.finalize(runID: organizeRun, actualCount: 3)

        // A dedupe refund quoting the organize run's ID credits nothing: the
        // reservation's meter does not match.
        await refunder(ledger).refundUndoneWork(
            receiptRunID: organizeRun, meter: .dedupe, itemPaths: ["/dest/a.jpg", "/dest/b.jpg"]
        )

        XCTAssertEqual(try organizeUsed(ledger), 3)
    }
}

/// Fails the test if the ledger is touched at all.
private final class ExplodingRefundLedger: TrialLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var touched = false
    var wasTouched: Bool {
        lock.lock(); defer { lock.unlock() }
        return touched
    }

    private func markTouched() {
        lock.lock(); touched = true; lock.unlock()
    }

    func balance(accountKey: String) throws -> TrialBalance {
        markTouched()
        return .unspent()
    }

    func reserve(
        runID: UUID, accountKey: String, meter: TrialMeter,
        count: Int, destinationRoot: String?
    ) throws -> ReservationDecision {
        markTouched()
        return .permitted
    }

    func finalize(runID: UUID, actualCount: Int) throws { markTouched() }
    func release(runID: UUID) throws { markTouched() }
    func refund(
        receiptRunID: UUID, accountKey: String,
        meter: TrialMeter, itemPaths: [String]
    ) throws { markTouched() }
    func openReservations() throws -> [OpenReservation] { [] }
}

/// A ledger whose refund write fails, standing in for a disk that has gone away.
private struct ThrowingRefundLedger: TrialLedger {
    func balance(accountKey: String) throws -> TrialBalance { .unspent() }
    func reserve(
        runID: UUID, accountKey: String, meter: TrialMeter,
        count: Int, destinationRoot: String?
    ) throws -> ReservationDecision { .permitted }
    func finalize(runID: UUID, actualCount: Int) throws {}
    func release(runID: UUID) throws {}
    func refund(
        receiptRunID: UUID, accountKey: String,
        meter: TrialMeter, itemPaths: [String]
    ) throws {
        throw TrialLedgerError.writeFailed("disk unavailable")
    }
    func openReservations() throws -> [OpenReservation] { [] }
}
