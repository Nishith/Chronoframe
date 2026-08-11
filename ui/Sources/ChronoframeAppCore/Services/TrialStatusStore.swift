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

/// What is known about the free allowance.
///
/// An enum rather than an optional `TrialBalance`, because "unlimited",
/// "not resolved yet" and "the records could not be read" are three different
/// answers that must not collapse into one. They did collapse once: the
/// fail-closed stand-in for an unreadable ledger reports zero remaining — which
/// is right for a GATE, and disastrous as a DESCRIPTION, because it made a
/// corrupt ledger indistinguishable from a genuinely spent trial.
public enum TrialAllowance: Sendable, Equatable {
    /// Unlocked. There is no limit and the ledger is never consulted.
    case unlimited
    /// Entitlement has not settled yet. Nothing is known.
    case unknown
    /// The ledger could not be read. Gates still refuse — the stand-in reports
    /// zero remaining — but the UI must say Chronoframe cannot confirm the
    /// allowance and that purchasing removes the limit, NOT that the trial is
    /// used up.
    case unavailable
    /// A real, readable balance.
    case remaining(TrialBalance)
}

/// Entitlement and remaining allowance, resolved together.
public struct TrialStatus: Sendable, Equatable {
    public let entitlement: EntitlementState
    public let allowance: TrialAllowance

    public init(entitlement: EntitlementState, allowance: TrialAllowance) {
        self.entitlement = entitlement
        self.allowance = allowance
    }

    public static let loading = TrialStatus(entitlement: .loading, allowance: .unknown)

    public var isUnlocked: Bool { entitlement.isUnlocked }

    /// The readable balance, or nil for every answer that is not one.
    public var balance: TrialBalance? {
        if case let .remaining(balance) = allowance { return balance }
        return nil
    }

    /// Remaining units on a meter, or nil when unlimited or unknown.
    ///
    /// Returning nil rather than a number for "unlimited" is deliberate: a
    /// sentinel like `Int.max` reads as a quantity and eventually gets rendered
    /// as one.
    public func remaining(for meter: TrialMeter) -> Int? {
        balance?.remaining(for: meter)
    }

    /// The ledger could not be read, so the UI owes the customer the distinct
    /// corrupt-records explanation rather than a number.
    public var bookkeepingUnavailable: Bool { allowance == .unavailable }

    /// Whether the UI may describe this as a trial that has been used up.
    ///
    /// Three things must all hold, and each has bitten this feature:
    ///
    ///   - The entitlement is `.locked`. `verificationUnavailable` and
    ///     `unverified` are metered like the trial but must never be reported
    ///     as a spent one — a customer who paid and opened their laptop on a
    ///     plane has not run out of anything.
    ///   - The allowance is a REAL balance. An unreadable ledger reports zero
    ///     remaining so that gates fail closed; saying "spent" on the strength
    ///     of that would be a lie about the customer's own usage.
    ///   - Every meter is actually at zero.
    public var describesASpentTrial: Bool {
        guard entitlement == .locked, case let .remaining(balance) = allowance else { return false }
        return TrialMeter.allCases.allSatisfy { balance.remaining(for: $0) == 0 }
    }
}

/// Composes `EntitlementStore`'s answer with the ledger's.
@MainActor
public final class TrialStatusStore: ObservableObject {
    @Published public private(set) var status: TrialStatus = .loading

    private let ledger: any TrialLedger
    private let bookkeepingAvailable: Bool

    /// - Parameter bookkeepingAvailable: false when the ledger failed to open.
    ///   The caller has to say so, because the fail-closed stand-in deliberately
    ///   answers "zero remaining" rather than throwing, and that answer is
    ///   indistinguishable from a spent trial once it reaches this layer.
    public init(ledger: any TrialLedger, bookkeepingAvailable: Bool = true) {
        self.ledger = ledger
        self.bookkeepingAvailable = bookkeepingAvailable
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
            allowance: resolveAllowance(entitlement: entitlement, accountKey: accountKey)
        )
    }

    private func resolveAllowance(
        entitlement: EntitlementState,
        accountKey: String?
    ) -> TrialAllowance {
        // An unlocked customer never consults the ledger. This is a
        // correctness rule, not an optimization: a paid customer's experience
        // must not depend on trial bookkeeping being readable at all.
        guard !entitlement.isUnlocked else { return .unlimited }

        // Still settling. Reporting a balance now would flash a trial state at
        // a paying customer during launch.
        guard !entitlement.isResolving else { return .unknown }

        // The ledger failed to open. Gates still refuse, because the stand-in
        // answers zero remaining — but this layer must not call that a spent
        // trial.
        guard bookkeepingAvailable else { return .unavailable }

        // Without an account key there is no per-account row to read. Report
        // unknown rather than another account's balance.
        //
        // NOTE for step 4: this must never be read as "no limit". A gate needs
        // its own key and must refuse to proceed without one, rather than
        // inheriting this.
        guard let accountKey else { return .unknown }

        guard let balance = try? ledger.balance(accountKey: accountKey) else { return .unavailable }
        return .remaining(balance)
    }
}
