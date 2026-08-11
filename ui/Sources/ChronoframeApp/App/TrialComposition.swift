#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

// MARK: - Trial composition root (free-trial step 4, T7)
//
// The Mac App Store app's answer to "who is allowed to do metered work?".
//
// Deliberately NOT inside `AppState`: the reconciler provider is a `@Sendable`,
// non-isolated closure, the App Intent builds its own engine without an
// `AppState` at all, and both need the same ledger and the same policy. One
// place, so those two surfaces cannot drift into different answers.

enum TrialComposition {
    /// Kept as the whole outcome, not just `.ledger`. The fail-closed stand-in
    /// for an unreadable ledger answers "zero remaining" rather than throwing —
    /// correct for a gate, and indistinguishable from a spent trial by the time
    /// it reaches the UI. `TrialStatus` needs to be told which one it is.
    static let openOutcome: TrialLedgerOpenOutcome = TrialLedgerOpener.openDefault()

    static var ledger: any TrialLedger { openOutcome.ledger }
    static var isReadable: Bool { openOutcome.failure == nil }

    /// Created eagerly but **never refreshed at launch**. Refreshing calls
    /// StoreKit; resolution happens the first time a gate actually needs an
    /// answer, so a cold start does no store round-trip.
    @MainActor
    static let entitlementStore = EntitlementStore(
        storeKit: LiveStoreKitClient(),
        appTransactionClient: LiveAppTransactionClient()
    )

    /// The Mac App Store policy: unlocked customers pass, everyone else is
    /// metered against the ledger.
    static let authorizer: any TrialAuthorizing = EntitlementTrialAuthorizer(
        ledger: ledger,
        snapshot: { await currentEntitlement() }
    )

    /// Resolve entitlement, waiting if it has not settled.
    ///
    /// `EntitlementState.loading` must make a gate WAIT rather than refuse — a
    /// slow App Store response should never look like a paywall. Doing that here
    /// rather than in the authorizer is what lets the authorizer stay a pure
    /// decision, and means a `.loading` state reaching it signals a genuine
    /// resolution failure rather than a race.
    @MainActor
    private static func currentEntitlement() async -> TrialEntitlementSnapshot {
        if entitlementStore.state.isResolving {
            await entitlementStore.refresh()
        }
        return TrialEntitlementSnapshot(
            state: entitlementStore.state,
            accountKey: entitlementStore.ledgerAccountKey
        )
    }

    /// Pair ledger reconciliation with destination recovery.
    ///
    /// Idempotent: `AppState` is built once in the app but repeatedly in tests,
    /// and re-assigning the provider is harmless.
    static func installReconciler() {
        DestinationRecovery.reconcilerProvider = { TrialLedgerReconciler(ledger: ledger) }
    }
}
