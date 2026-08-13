#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Trial authorization (free-trial step 4, T7)
//
// The seam every metered surface asks before it mutates anything, and the one
// place entitlement and allowance turn into a yes or a no.
//
// It is introduced ahead of the gates that use it (T8–T11) so that adding those
// gates is a pure behavioural change rather than behaviour plus plumbing, and so
// the compiler — not a reviewer's memory — enumerates the composition roots.
//
// NO DEFAULT ARGUMENT. `SwiftOrganizerEngine` and `NativeDeduplicateEngine`
// require an authorizer. A default would make every forgotten or future
// constructor a silent licensing bypass, and "silent" is the operative word: a
// missing gate does not crash, log, or fail a test. It just quietly gives the
// product away. Requiring the argument turns that into a compile error.

/// Why metered work was refused.
///
/// The distinction is not cosmetic — it decides what the customer is told, and
/// telling them the wrong one is a lie about their own account.
public enum TrialAuthorizationRefusal: Sendable, Equatable {
    /// The free allowance really is spent. Safe to say so.
    case allowanceSpent(TrialRefusal)

    /// Metered like the trial, but the purchase could not be confirmed —
    /// StoreKit unreachable, a signature that did not verify, or no account key.
    ///
    /// Settled policy is to meter these states, so this refuses. The copy must
    /// say Chronoframe could not confirm the purchase, and must NEVER say the
    /// trial is spent: this customer may well have paid.
    case purchaseUnconfirmed(TrialRefusal)

    /// The surface requires the unlock outright and is not metered at all —
    /// reorganize.
    case requiresUnlock
}

/// A refusal in a form that travels through the engines' event streams.
///
/// Thrown rather than reported as a run status, because a refused run is not a
/// run outcome. `RunStatus` is `String, Codable` and is persisted into audit
/// receipts and Run History, so a new case there would let a refusal masquerade
/// as a completed run inside files that already exist on customers' disks — and
/// every one of the nine switch sites over it would have to guess what a
/// refusal means.
///
/// Carrying `refusal` rather than a formatted string is what lets the UI branch:
/// `allowanceSpent` is the one that may offer the unlock, and
/// `purchaseUnconfirmed` must not, because that customer may already have paid.
public struct TrialAuthorizationError: LocalizedError, Sendable, Equatable {
    public let refusal: TrialAuthorizationRefusal

    /// A smaller run the remaining allowance does cover, when one can honestly
    /// be offered (free-trial step 5, T15).
    ///
    /// Nil is the norm: a refusal offers nothing unless the allowance has room
    /// left and this run is the kind that can be split.
    public let offeredBatch: FreeTestBatch?

    public init(refusal: TrialAuthorizationRefusal, offeredBatch: FreeTestBatch? = nil) {
        self.refusal = refusal
        self.offeredBatch = offeredBatch
    }

    /// Attach a free test batch to a refusal, when the refusal is one that may
    /// honestly carry an offer.
    ///
    /// Pure, so the rules below are testable without a StoreKit round-trip.
    /// Three conditions, each of which would be a real mistake to drop:
    ///
    ///   - **Only `allowanceSpent`.** `purchaseUnconfirmed` is metered, so it
    ///     refuses the same way — but that customer may already have paid, and
    ///     offering them a *free sample of what they bought* would be insulting
    ///     as well as wrong. `requiresUnlock` is not metered at all.
    ///   - **Only with allowance left.** At zero remaining the batch is empty,
    ///     and an offer to copy nothing is worse than no offer.
    ///   - **Only when it is genuinely smaller.** A batch covering the whole
    ///     plan means the refusal came from somewhere other than size, and
    ///     re-offering the same run would loop.
    public static func offeringFreeTestBatch(
        _ error: TrialAuthorizationError,
        plannedTransfers: [PlannedTransfer]
    ) -> TrialAuthorizationError {
        guard case let .allowanceSpent(details) = error.refusal,
              details.meter == .organize,
              details.remaining > 0 else { return error }

        let batch = FreeTestBatchPlanner.batch(from: plannedTransfers, limit: details.remaining)
        guard !batch.included.isEmpty, !batch.coversWholePlan else { return error }

        return TrialAuthorizationError(refusal: error.refusal, offeredBatch: batch)
    }

    public var errorDescription: String? {
        switch refusal {
        case let .allowanceSpent(details):
            return Self.allowanceSpentMessage(details)
        case let .purchaseUnconfirmed(details):
            return "Chronoframe could not confirm your purchase, so this run was not started. "
                + "Check your internet connection and try again, or use Restore Purchases in Settings. "
                + Self.nothingHappened(details.meter)
        case .requiresUnlock:
            return "This action is available once Chronoframe is unlocked. Nothing was changed."
        }
    }

    private static func allowanceSpentMessage(_ refusal: TrialRefusal) -> String {
        let noun = refusal.meter == .organize ? "file" : "duplicate"
        let action = refusal.meter == .organize
            ? "this run would copy \(refusal.requested)"
            : "this cleanup would remove \(refusal.requested)"
        let left = refusal.remaining == 0
            ? "no \(noun)s left"
            : "\(refusal.remaining) \(noun)\(refusal.remaining == 1 ? "" : "s") left"

        return "Your free allowance has \(left), and \(action). "
            + "Unlock Chronoframe to finish the job. \(nothingHappened(refusal.meter))"
    }

    /// Every refusal ends by saying nothing happened. A customer who is being
    /// told they cannot proceed needs to know their library was not left
    /// half-changed on the way to the message.
    private static func nothingHappened(_ meter: TrialMeter) -> String {
        switch meter {
        case .organize:
            return "Nothing was copied and your originals were left untouched."
        case .dedupe:
            return "Nothing was moved to the Trash."
        }
    }
}

public enum TrialAuthorization: Sendable, Equatable {
    case permitted
    case refused(TrialAuthorizationRefusal)

    public var isPermitted: Bool {
        if case .permitted = self { return true }
        return false
    }

    public var refusal: TrialAuthorizationRefusal? {
        if case let .refused(refusal) = self { return refusal }
        return nil
    }
}

/// A snapshot of what the entitlement layer currently knows.
public struct TrialEntitlementSnapshot: Sendable, Equatable {
    public let state: EntitlementState
    public let accountKey: String?

    public init(state: EntitlementState, accountKey: String?) {
        self.state = state
        self.accountKey = accountKey
    }

    public static let unresolved = TrialEntitlementSnapshot(state: .loading, accountKey: nil)
}

/// Asked before any metered mutation, and told afterwards what actually
/// happened.
///
/// Async on purpose. `EntitlementState.loading` must make a gate WAIT rather
/// than refuse — a slow App Store response should never look like a paywall —
/// and that waiting belongs to whoever supplies the snapshot.
public protocol TrialAuthorizing: Sendable {
    /// Reserve `count` units of `meter` before anything is enqueued, written, or
    /// moved. `runID` is the reservation key threaded through the run.
    func authorizeMeteredWork(
        runID: UUID,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) async -> TrialAuthorization

    /// Settle the reservation with the count that actually landed.
    func finalizeMeteredWork(runID: UUID, actualCount: Int) async

    /// Give a reservation back. ONLY when nothing was mutated; an ambiguous
    /// outcome stays open and charged until reconciliation resolves it.
    func releaseMeteredWork(runID: UUID) async

    /// For surfaces that require the unlock and are not metered — reorganize.
    func authorizeUnlockOnlyWork() async -> TrialAuthorization
}

// MARK: - Unrestricted

/// Permits everything and records nothing.
///
/// For the CLI and Developer ID builds, which are internal and testing tools
/// that never ship to a paying customer — the CLI is not embedded in the app
/// bundle or the Mac App Store archive. Also the honest choice for tests that
/// are not exercising gating.
///
/// Named for what it does. A composition root choosing this is making a visible
/// decision, which is the entire point of removing the default argument.
public struct UnrestrictedTrialAuthorizer: TrialAuthorizing {
    public init() {}

    public func authorizeMeteredWork(
        runID: UUID,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) async -> TrialAuthorization { .permitted }

    public func finalizeMeteredWork(runID: UUID, actualCount: Int) async {}
    public func releaseMeteredWork(runID: UUID) async {}
    public func authorizeUnlockOnlyWork() async -> TrialAuthorization { .permitted }
}

// MARK: - Entitlement-backed

/// The Mac App Store policy: unlocked customers pass, everyone else is metered
/// against the ledger.
public struct EntitlementTrialAuthorizer: TrialAuthorizing {
    private let ledger: any TrialLedger
    private let snapshot: @Sendable () async -> TrialEntitlementSnapshot

    /// - Parameter snapshot: resolves the current entitlement. It is
    ///   responsible for AWAITING resolution — a `.loading` state arriving here
    ///   means resolution genuinely failed, not that it is still in flight, and
    ///   is metered exactly like the other unconfirmable states: permitted while
    ///   allowance remains, refused as `purchaseUnconfirmed` once it does not.
    ///   Bounded rather than blocking, so a transient failure neither hands out
    ///   unlimited work nor locks out someone with allowance left.
    public init(
        ledger: any TrialLedger,
        snapshot: @escaping @Sendable () async -> TrialEntitlementSnapshot
    ) {
        self.ledger = ledger
        self.snapshot = snapshot
    }

    public func authorizeMeteredWork(
        runID: UUID,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) async -> TrialAuthorization {
        let entitlement = await snapshot()

        // A paid customer is never metered and never causes a ledger read.
        if entitlement.state.isUnlocked { return .permitted }

        // A run with nothing to do is never refused, whatever the balance or
        // the entitlement. Refusing an empty run would be an insult with no
        // revenue attached.
        guard count > 0 else { return .permitted }

        // Settled policy: `verificationUnavailable` and `unverified` are
        // metered like the trial. Without an account key there is no row to
        // meter against, so this fails closed — but as "could not confirm",
        // never as "spent".
        guard let accountKey = entitlement.accountKey else {
            return .refused(
                .purchaseUnconfirmed(TrialRefusal(meter: meter, requested: count, remaining: 0))
            )
        }

        let decision: ReservationDecision
        do {
            decision = try ledger.reserve(
                runID: runID,
                accountKey: accountKey,
                meter: meter,
                count: count,
                destinationRoot: destinationRoot
            )
        } catch {
            // The ledger could not be written. Fail closed: proceeding would
            // mutate media with no record that the allowance was consumed.
            return .refused(
                .purchaseUnconfirmed(TrialRefusal(meter: meter, requested: count, remaining: 0))
            )
        }

        switch decision {
        case .permitted:
            return .permitted
        case let .refused(refusal):
            return .refused(Self.refusal(refusal, for: entitlement.state))
        }
    }

    public func finalizeMeteredWork(runID: UUID, actualCount: Int) async {
        try? ledger.finalize(runID: runID, actualCount: actualCount)
    }

    public func releaseMeteredWork(runID: UUID) async {
        try? ledger.release(runID: runID)
    }

    public func authorizeUnlockOnlyWork() async -> TrialAuthorization {
        let entitlement = await snapshot()
        return entitlement.state.isUnlocked ? .permitted : .refused(.requiresUnlock)
    }

    /// Only a resolved `.locked` customer may be told their trial is spent.
    private static func refusal(
        _ refusal: TrialRefusal,
        for state: EntitlementState
    ) -> TrialAuthorizationRefusal {
        state == .locked ? .allowanceSpent(refusal) : .purchaseUnconfirmed(refusal)
    }
}
