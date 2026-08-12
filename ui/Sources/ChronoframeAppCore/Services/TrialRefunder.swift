#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Refunding allowance for undone work (free-trial step 4, T12)
//
// `TrialLedger.refund` has existed since step 3 with nothing calling it. This is
// what calls it: revert gives back the allowance for the mutations it actually
// undid, which is the whole reason revert is ungated in the first place. A
// customer who undoes a run and stays charged for it has been charged for
// nothing.
//
// A SEPARATE SEAM FROM `TrialAuthorizing`, ON PURPOSE.
//
// The non-negotiable is that revert takes no authorizer — structurally, not by
// convention — because a paywall must never be able to strand a library
// mid-migration. Folding `refund` into `TrialAuthorizing` would put a type that
// can say "no" on every revert path, and the next person to add a guard there
// would find the object already in scope. `TrialRefunding` has no `authorize`
// method and no failable return: there is nothing on it to gate with.
//
// Every method is non-throwing for the same reason. Trial bookkeeping must never
// be able to fail a revert.

/// Credits back the allowance for mutations a revert undid.
///
/// Item-level rather than count-level. Partial reverts are routine — a
/// destination file the user has edited is preserved by design — so a customer
/// can revert, fix the conflict, and revert again. Passing paths lets the second
/// pass refund exactly the newly undone items; `TrialLedger.refund` is keyed by
/// `(receiptRunID, itemPath)`, so re-recording an item is a no-op and an
/// identical revert refunds nothing further.
public protocol TrialRefunding: Sendable {
    /// - Parameters:
    ///   - receiptRunID: the reservation the original run was charged under.
    ///     Callers must pass `nil` when the receipt cannot supply a trustworthy
    ///     one; see `RevertReceipt.reservationRunID`.
    ///   - itemPaths: the mutations actually undone by THIS pass. Empty is
    ///     normal and must be cheap.
    func refundUndoneWork(receiptRunID: UUID?, meter: TrialMeter, itemPaths: [String]) async
}

// MARK: - No-op

/// Records nothing.
///
/// For the CLI and Developer ID builds, which never charged anything in the
/// first place, and for tests that are not exercising refunds. Refunding
/// against an unmetered channel would be crediting work that was free.
public struct NoOpTrialRefunder: TrialRefunding {
    public init() {}

    public func refundUndoneWork(receiptRunID: UUID?, meter: TrialMeter, itemPaths: [String]) async {}
}

// MARK: - Ledger-backed

/// Records the undone items against the ledger.
///
/// Deliberately has no entitlement dependency. The account a refund belongs to
/// is the account that was CHARGED, which the ledger already knows — reading it
/// from the current entitlement instead would be wrong in two ways that cannot
/// be repaired afterwards:
///
/// - **Offline.** An unresolved account key would skip the refund, and the
///   revert has already removed the files, so a later pass reports them as
///   missing rather than newly reverted and there is nothing left to refund.
/// - **After an Apple Account switch.** The item would be recorded under the
///   wrong account. Usage only nets refunds whose account matches the
///   reservation, so it credits nothing — and because `RefundedItems` ignores a
///   second record for the same `(receipt_run_id, item_path)`, the correct
///   record can never be written.
public struct EntitlementTrialRefunder: TrialRefunding {
    private let ledger: any TrialLedger

    public init(ledger: any TrialLedger) {
        self.ledger = ledger
    }

    public func refundUndoneWork(receiptRunID: UUID?, meter: TrialMeter, itemPaths: [String]) async {
        // Nothing was undone. Common — a revert that finds every file already
        // missing does no work — and must not cost a ledger write.
        guard !itemPaths.isEmpty else { return }

        // No trustworthy reservation key. Refunds are keyed by run ID, so a
        // guessed key would credit the wrong run or double-credit this one.
        // Not refunding leaves the customer charged for what they already
        // agreed to; refunding wrongly hands out allowance nobody paid for.
        guard let receiptRunID else { return }

        // The account that was charged, not whoever is signed in now. A nil
        // here means no such reservation exists — a receipt from a run this
        // ledger never charged — so there is nothing to credit.
        guard let accountKey = try? ledger.accountKey(forRunID: receiptRunID),
              let accountKey
        else { return }

        // Swallowed on purpose. The revert has already happened — the files are
        // back — and failing the stream now would tell the customer their revert
        // broke when it did not. An unrecorded refund leaves them over-charged,
        // which is visible and correctable; a failed revert is neither.
        try? ledger.refund(
            receiptRunID: receiptRunID,
            accountKey: accountKey,
            meter: meter,
            itemPaths: itemPaths
        )
    }
}
