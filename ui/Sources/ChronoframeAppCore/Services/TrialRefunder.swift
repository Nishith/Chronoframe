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
public struct EntitlementTrialRefunder: TrialRefunding {
    private let ledger: any TrialLedger
    private let accountKey: @Sendable () async -> String?

    /// - Parameter accountKey: resolves the App Store account the original run
    ///   was charged under. A refund has to be attributed to the same account
    ///   that was charged, so an unresolvable one records nothing rather than
    ///   guessing.
    public init(
        ledger: any TrialLedger,
        accountKey: @escaping @Sendable () async -> String?
    ) {
        self.ledger = ledger
        self.accountKey = accountKey
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

        guard let accountKey = await accountKey() else { return }

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
