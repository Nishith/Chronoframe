#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Durable reservation ledger (free-trial step 3)
//
// Recording usage AFTER the filesystem work finishes is exploitable: cancel at
// 499 copies and the meter never moves, forever. Recording it in a completion
// handler additionally loses usage on crash, on cancel-after-partial-success,
// on partial failure, on a stream that ends without a final event, and when an
// App Intent races the app.
//
// So the shape is not check → mutate → record. It is:
//
//     reserve → mutate → finalize → reconcile
//
//   1. Reserve the full requested count BEFORE enqueueing jobs, writing a
//      receipt, or touching media.
//   2. Persist the reservation against work that already survives a crash.
//   3. Finalize with the actual successful mutation count.
//   4. Reconcile on cancellation, failure, and at startup.
//
// A crash therefore leaves the reservation charged AT ITS FULL RESERVED AMOUNT
// until recovery proves how many mutations actually occurred. That falls out of
// the usage query rather than out of special-case code — see
// `TrialLedgerDatabase`. It is the same fail-closed posture as the rest of the
// codebase: never infer that an unfinished operation did nothing.
//
// SCOPE: step 3 builds the ledger and gates nothing. Nothing calls `reserve`
// yet; enforcement is step 4.

/// An open (not yet finalized or released) reservation.
public struct OpenReservation: Sendable, Equatable {
    public let runID: UUID
    public let accountKey: String
    public let meter: TrialMeter
    public let reservedCount: Int
    /// Where the run was writing, when known. Reconciliation uses it to find the
    /// `CopyJobs` rows and receipts that prove what actually happened.
    public let destinationRoot: String?
    public let createdAt: Date

    public init(
        runID: UUID,
        accountKey: String,
        meter: TrialMeter,
        reservedCount: Int,
        destinationRoot: String?,
        createdAt: Date
    ) {
        self.runID = runID
        self.accountKey = accountKey
        self.meter = meter
        self.reservedCount = reservedCount
        self.destinationRoot = destinationRoot
        self.createdAt = createdAt
    }
}

/// Failures the ledger can report.
///
/// Per the project rule on user-facing text, these carry plain descriptions and
/// never surface a raw SQLite message on its own.
public enum TrialLedgerError: LocalizedError, Sendable, Equatable {
    /// The ledger file could not be opened or created.
    case openFailed(String)
    /// The ledger opened but its contents could not be read or written. Treated
    /// as fail-closed: zero remaining, not a fresh allowance.
    case unreadable(String)
    /// A write could not be completed.
    case writeFailed(String)
    case databaseClosed

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "Chronoframe could not open its trial records. Check that your startup disk is available, then try again. Details: \(message)"
        case let .unreadable(message):
            return "Chronoframe could not read its trial records, so it cannot confirm how much of the free allowance is left. Purchasing the unlock removes the limit entirely. Details: \(message)"
        case let .writeFailed(message):
            return "Chronoframe could not update its trial records. Details: \(message)"
        case .databaseClosed:
            return "Chronoframe lost access to its trial records. Try again."
        }
    }
}

public protocol TrialLedger: Sendable {
    /// Cumulative usage measured against the caps, for one Apple Account.
    func balance(accountKey: String) throws -> TrialBalance

    /// Atomic check-and-insert in ONE `BEGIN IMMEDIATE` transaction. Returns
    /// `.refused` WITHOUT writing anything when the meter cannot cover `count`.
    ///
    /// Re-reserving an existing `runID` returns the stored decision unchanged
    /// rather than stacking a second charge, so a retried reservation — a resumed
    /// transfer, a duplicated completion path — cannot double-charge.
    func reserve(
        runID: UUID,
        accountKey: String,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) throws -> ReservationDecision

    /// Idempotent: transitions `open → finalized` only. A second call is a no-op,
    /// so duplicate completion handling cannot double-charge, and a finalize that
    /// arrives after a release cannot resurrect a charge.
    func finalize(runID: UUID, actualCount: Int) throws

    /// Idempotent `open → released`. ONLY for reservations that provably never
    /// mutated anything. Never call this on an ambiguous outcome — an ambiguous
    /// outcome stays open and fully charged until reconciliation resolves it.
    func release(runID: UUID) throws

    /// Records the items a revert actually restored or removed. Idempotent per
    /// `(receiptRunID, itemPath)`, so a partial revert followed later by a fuller
    /// one refunds exactly the newly restored items — and re-running the same
    /// revert refunds nothing extra.
    ///
    /// Takes paths, not a count, on purpose: a count cannot distinguish "two more
    /// items restored" from "the same two items reported twice". Reverts are
    /// routinely partial, because a destination file whose hash no longer matches
    /// the receipt is preserved and skipped by design.
    ///
    /// A refund only ever gives back what its OWN reservation was charged.
    /// Refunding a receipt with no charged reservation — a run from before
    /// enforcement shipped, a released reservation, a receipt from another
    /// machine — is recorded but credits nothing, and refunding more items than
    /// a reservation was charged for stops at that charge. Neither can enlarge a
    /// later run's allowance.
    func refund(
        receiptRunID: UUID,
        accountKey: String,
        meter: TrialMeter,
        itemPaths: [String]
    ) throws

    /// The account a reservation was charged to, or nil when no such
    /// reservation exists.
    ///
    /// A refund MUST be attributed to the account that was charged, not to
    /// whoever is signed in when the revert happens. `RefundedItems` is
    /// `INSERT OR IGNORE` on `(receipt_run_id, item_path)` and usage only nets
    /// refunds whose account matches the reservation — so a refund recorded
    /// under the wrong account credits nothing AND permanently blocks the
    /// correct record for that item. Asking the ledger who was charged is the
    /// only way to get it right offline, or after an Apple Account switch.
    func accountKey(forRunID runID: UUID) throws -> String?

    /// Every reservation still in the `open` state, for reconciliation.
    func openReservations() throws -> [OpenReservation]
}

// MARK: - Opening

/// The result of trying to open the on-disk ledger.
///
/// A corrupt or unopenable ledger deliberately does NOT read as a fresh balance.
/// This is the inverse of `GuardianFileSchedulePersistence`, whose "corrupt reads
/// as fresh" default is right for scheduling state and would here hand out a free
/// allowance reset to anyone who deletes a file.
public enum TrialLedgerOpenOutcome: Sendable {
    case ready(any TrialLedger)
    /// The ledger could not be opened. The associated ledger is fail-closed:
    /// zero remaining on every meter.
    case unreadable(any TrialLedger, TrialLedgerError)

    public var ledger: any TrialLedger {
        switch self {
        case let .ready(ledger): return ledger
        case let .unreadable(ledger, _): return ledger
        }
    }

    public var failure: TrialLedgerError? {
        if case let .unreadable(_, error) = self { return error }
        return nil
    }
}

public enum TrialLedgerOpener {
    /// Open the ledger at `url`, falling back to a fail-closed stand-in when it
    /// cannot be opened.
    ///
    /// The result is wrapped in a `WitnessedTrialLedger` so that deleting
    /// `ledger.db` — or the whole Application Support folder — does not hand
    /// back a fresh allowance. See `TrialUsageWitness` for what that does and,
    /// just as importantly, what it does not do.
    public static func open(
        url: URL,
        caps: TrialAllowanceCaps = .standard,
        witness: any TrialUsageWitness = KeychainTrialUsageWitness()
    ) -> TrialLedgerOpenOutcome {
        do {
            let database = try TrialLedgerDatabase(url: url, caps: caps)
            return .ready(WitnessedTrialLedger(base: database, witness: witness))
        } catch let error as TrialLedgerError {
            return .unreadable(UnreadableTrialLedger(caps: caps), error)
        } catch {
            return .unreadable(
                UnreadableTrialLedger(caps: caps),
                .openFailed(error.localizedDescription)
            )
        }
    }

    /// Open the ledger at its standard Application Support location.
    public static func openDefault(caps: TrialAllowanceCaps = .standard) -> TrialLedgerOpenOutcome {
        open(url: TrialLedgerPaths.ledgerURL(), caps: caps)
    }
}

/// The fail-closed stand-in used when the real ledger cannot be opened.
///
/// Reports zero remaining and refuses every reservation. Finalize, release, and
/// refund are no-ops: there is no row to update, and — importantly — `refund`
/// must not throw, because it is called from revert, and revert is never allowed
/// to fail or change behaviour because of trial bookkeeping.
public struct UnreadableTrialLedger: TrialLedger {
    private let caps: TrialAllowanceCaps

    public init(caps: TrialAllowanceCaps = .standard) {
        self.caps = caps
    }

    public func balance(accountKey: String) throws -> TrialBalance {
        .exhausted(caps: caps)
    }

    public func reserve(
        runID: UUID,
        accountKey: String,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) throws -> ReservationDecision {
        TrialAllowancePolicy.decide(requested: count, meter: meter, balance: .exhausted(caps: caps))
    }

    public func finalize(runID: UUID, actualCount: Int) throws {}
    public func release(runID: UUID) throws {}
    public func refund(
        receiptRunID: UUID,
        accountKey: String,
        meter: TrialMeter,
        itemPaths: [String]
    ) throws {}

    /// Unknown, not "nobody". An unreadable ledger cannot say who was charged,
    /// and the refunder records nothing rather than guessing.
    public func accountKey(forRunID runID: UUID) throws -> String? { nil }
    public func openReservations() throws -> [OpenReservation] { [] }
}

// MARK: - In-memory double

/// In-memory `TrialLedger` for tests and previews.
///
/// It reproduces the database's semantics deliberately, including the one that
/// matters most: an open reservation counts at its FULL reserved amount, so a
/// test that simulates a crash sees the same charged balance the app would.
public final class InMemoryTrialLedger: TrialLedger, @unchecked Sendable {
    private struct Row {
        var accountKey: String
        var meter: TrialMeter
        var reservedCount: Int
        var finalizedCount: Int?
        var state: ReservationState
        var destinationRoot: String?
        var createdAt: Date
    }

    private enum ReservationState: String {
        case open, finalized, released
    }

    private let caps: TrialAllowanceCaps
    private let lock = NSLock()
    private var rows: [UUID: Row] = [:]
    /// Insertion order, so `openReservations()` is deterministic.
    private var order: [UUID] = []
    /// Mirrors `RefundedItems`, whose primary key is `(receipt_run_id, item_path)`
    /// — the account and meter ride along as recorded, not as part of identity.
    private var refunded: [RefundKey: RefundOrigin] = [:]

    private struct RefundKey: Hashable {
        let receiptRunID: UUID
        let itemPath: String
    }

    private struct RefundOrigin {
        let accountKey: String
        let meter: TrialMeter
    }

    public init(caps: TrialAllowanceCaps = .standard) {
        self.caps = caps
    }

    public func balance(accountKey: String) throws -> TrialBalance {
        lock.lock()
        defer { lock.unlock() }
        return TrialBalance(
            caps: caps,
            usage: TrialUsage(
                organizeUsed: usedLocked(accountKey: accountKey, meter: .organize),
                dedupeUsed: usedLocked(accountKey: accountKey, meter: .dedupe)
            )
        )
    }

    public func reserve(
        runID: UUID,
        accountKey: String,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) throws -> ReservationDecision {
        lock.lock()
        defer { lock.unlock() }

        if rows[runID] != nil { return .permitted }

        let balance = TrialBalance(
            caps: caps,
            usage: TrialUsage(
                organizeUsed: usedLocked(accountKey: accountKey, meter: .organize),
                dedupeUsed: usedLocked(accountKey: accountKey, meter: .dedupe)
            )
        )
        let decision = TrialAllowancePolicy.decide(requested: count, meter: meter, balance: balance)
        guard decision.isPermitted else { return decision }

        rows[runID] = Row(
            accountKey: accountKey,
            meter: meter,
            reservedCount: max(0, count),
            finalizedCount: nil,
            state: .open,
            destinationRoot: destinationRoot,
            createdAt: Date()
        )
        order.append(runID)
        return .permitted
    }

    public func finalize(runID: UUID, actualCount: Int) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var row = rows[runID], row.state == .open else { return }
        row.finalizedCount = min(max(0, actualCount), row.reservedCount)
        row.state = .finalized
        rows[runID] = row
    }

    public func release(runID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }
        guard var row = rows[runID], row.state == .open else { return }
        row.finalizedCount = 0
        row.state = .released
        rows[runID] = row
    }

    public func refund(
        receiptRunID: UUID,
        accountKey: String,
        meter: TrialMeter,
        itemPaths: [String]
    ) throws {
        lock.lock()
        defer { lock.unlock() }
        for path in itemPaths {
            let key = RefundKey(receiptRunID: receiptRunID, itemPath: path)
            // INSERT OR IGNORE: the first record of an item wins.
            guard refunded[key] == nil else { continue }
            refunded[key] = RefundOrigin(accountKey: accountKey, meter: meter)
        }
    }

    public func accountKey(forRunID runID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        return rows[runID]?.accountKey
    }

    public func openReservations() throws -> [OpenReservation] {
        lock.lock()
        defer { lock.unlock() }
        return order.compactMap { runID in
            guard let row = rows[runID], row.state == .open else { return nil }
            return OpenReservation(
                runID: runID,
                accountKey: row.accountKey,
                meter: row.meter,
                reservedCount: row.reservedCount,
                destinationRoot: row.destinationRoot,
                createdAt: row.createdAt
            )
        }
    }

    /// Mirrors `TrialLedgerDatabase.usedLocked`, including the part that matters
    /// most: refunds net against their OWN reservation and are floored there, so
    /// a refund with no charged reservation behind it can never become a credit
    /// against a later run.
    private func usedLocked(accountKey: String, meter: TrialMeter) -> Int {
        rows.reduce(0) { total, entry in
            let (runID, row) = entry
            guard row.accountKey == accountKey, row.meter == meter, row.state != .released else {
                return total
            }
            let charged = row.finalizedCount ?? row.reservedCount
            let refunds = refunded.reduce(0) { count, refund in
                guard refund.key.receiptRunID == runID,
                      refund.value.accountKey == row.accountKey,
                      refund.value.meter == row.meter
                else { return count }
                return count + 1
            }
            return total + max(0, charged - refunds)
        }
    }
}
