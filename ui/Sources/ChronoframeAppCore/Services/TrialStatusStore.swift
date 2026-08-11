#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Combine
import Foundation

// MARK: - Trial status (free-trial step 3, T6)
//
// Entitlement ("has this customer paid?") and allowance ("how much of the free
// tier is left?") are deliberately separate everywhere below this file. Step 2
// kept the ledger out of `EntitlementStore` so the grandfather rule could be
// verified in isolation, and step 3 kept entitlement out of the ledger so the
// reserve/finalize accounting could be tested without StoreKit.
//
// This is the one place that composes them, and it is the only place that needs
// to know both answers.
//
// SCOPE: reading only. Nothing here reserves, finalizes, or refunds — step 4
// owns enforcement. Wiring this in changes no behaviour.

/// Entitlement and remaining allowance, resolved together.
public struct TrialStatus: Sendable, Equatable {
    public let entitlement: EntitlementState

    /// The remaining free allowance, or nil when the question does not apply.
    ///
    /// Nil in exactly two situations, which callers must not conflate:
    ///
    ///   - **Unlocked.** There is no limit, so there is no balance to show. An
    ///     unlocked customer never causes a ledger read at all.
    ///   - **Unresolved.** Entitlement is still `.loading`, or the ledger could
    ///     not be read. Nothing is known yet, and a UI must not fill the gap
    ///     with a guess in either direction.
    public let balance: TrialBalance?

    public init(entitlement: EntitlementState, balance: TrialBalance?) {
        self.entitlement = entitlement
        self.balance = balance
    }

    public static let loading = TrialStatus(entitlement: .loading, balance: nil)

    public var isUnlocked: Bool { entitlement.isUnlocked }

    /// Remaining units on a meter, or nil when unlimited or unknown.
    ///
    /// Returning nil rather than a number for "unlimited" is deliberate: a
    /// sentinel like `Int.max` reads as a quantity and eventually gets rendered
    /// as one.
    public func remaining(for meter: TrialMeter) -> Int? {
        balance?.remaining(for: meter)
    }

    /// Whether the UI may describe this as a trial that has been used up.
    ///
    /// `verificationUnavailable` and `unverified` are metered like the trial —
    /// see `EntitlementState` — but must never be *reported* as a spent trial.
    /// A customer who paid and opened their laptop on a plane has not run out
    /// of anything, and telling them they have is the worst thing this feature
    /// could do to them.
    public var describesASpentTrial: Bool {
        guard entitlement == .locked, let balance else { return false }
        return TrialMeter.allCases.allSatisfy { balance.remaining(for: $0) == 0 }
    }
}

/// Composes `EntitlementStore`'s answer with the ledger's.
@MainActor
public final class TrialStatusStore: ObservableObject {
    @Published public private(set) var status: TrialStatus = .loading

    private let ledger: any TrialLedger

    public init(ledger: any TrialLedger) {
        self.ledger = ledger
    }

    /// Recompute from the entitlement state and account key an
    /// `EntitlementStore` has settled on.
    ///
    /// Takes them as parameters rather than holding a reference to the store, so
    /// this stays testable without StoreKit and cannot accidentally trigger a
    /// StoreKit round-trip of its own.
    public func refresh(entitlement: EntitlementState, accountKey: String?) {
        status = TrialStatus(
            entitlement: entitlement,
            balance: resolveBalance(entitlement: entitlement, accountKey: accountKey)
        )
    }

    private func resolveBalance(
        entitlement: EntitlementState,
        accountKey: String?
    ) -> TrialBalance? {
        // An unlocked customer never consults the ledger. This is a
        // correctness rule, not an optimization: a paid customer's experience
        // must not depend on trial bookkeeping being readable at all.
        guard !entitlement.isUnlocked else { return nil }

        // Still settling. Reporting a balance now would flash a trial state at
        // a paying customer during launch.
        guard !entitlement.isResolving else { return nil }

        // Without an account key there is no per-account row to read. Report
        // nothing rather than another account's balance.
        //
        // NOTE for step 4: this must never be read as "no limit". A gate needs
        // its own key and must refuse to proceed without one, rather than
        // inheriting this nil.
        guard let accountKey else { return nil }

        return try? ledger.balance(accountKey: accountKey)
    }
}
