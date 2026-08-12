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

    /// Whether this binary is the Mac App Store build.
    ///
    /// `MAS_BUILD` is defined only by `ui/archive-mas.sh`; `ui/archive.sh`
    /// produces the Developer ID build without it.
    #if MAS_BUILD
    static let isMacAppStoreBuild = true
    #else
    static let isMacAppStoreBuild = false
    #endif

    /// The authorizer for this channel.
    ///
    /// Mac App Store: metered. Developer ID: explicitly unrestricted, per
    /// settled policy — that channel is an internal and testing build, and it
    /// cannot obtain an App Store transaction at all, so metering it would
    /// refuse every non-empty organize and dedupe once the gates land.
    ///
    /// The CHOICE is conditional; the code is not. Both authorizers are built
    /// unconditionally and only a boolean is `#if`-ed, because `MAS_BUILD` is
    /// currently compiled by zero CI lanes (T17 adds one). Putting the
    /// production gating path inside `#if MAS_BUILD` would mean shipping a
    /// paywall that nothing had ever type-checked.
    static let authorizer: any TrialAuthorizing =
        isMacAppStoreBuild ? entitlementBackedAuthorizer : UnrestrictedTrialAuthorizer()

    /// Unlocked customers pass; everyone else is metered against the ledger.
    static let entitlementBackedAuthorizer: any TrialAuthorizing = EntitlementTrialAuthorizer(
        ledger: ledger,
        snapshot: { await currentEntitlement() }
    )

    /// A single in-flight resolution, shared by every caller that arrives while
    /// it runs.
    ///
    /// Without this, two gates racing on a cold store both call `refresh()`.
    /// `EntitlementStore` generation-tags concurrent refreshes and makes the
    /// loser return WITHOUT setting state — so if the loser finishes first, its
    /// caller reads `.loading` and refuses a customer who may well have paid.
    /// Coalescing removes the race rather than retrying around it.
    @MainActor
    private static var inFlightResolution: Task<Void, Never>?

    /// Resolve entitlement, waiting if it has not settled.
    ///
    /// `EntitlementState.loading` must make a gate WAIT rather than refuse — a
    /// slow App Store response should never look like a paywall. Doing that here
    /// rather than in the authorizer is what lets the authorizer stay a pure
    /// decision, and means a `.loading` state reaching it signals a genuine
    /// resolution failure rather than a race — at which point it is metered like
    /// any other unconfirmable state rather than blocked outright.
    @MainActor
    private static func currentEntitlement() async -> TrialEntitlementSnapshot {
        if entitlementStore.state.isResolving {
            await resolveOnce()
        }
        return TrialEntitlementSnapshot(
            state: entitlementStore.state,
            accountKey: entitlementStore.ledgerAccountKey
        )
    }

    @MainActor
    private static func resolveOnce() async {
        if let existing = inFlightResolution {
            await existing.value
            return
        }
        let task = Task { @MainActor in
            await entitlementStore.refresh()
        }
        inFlightResolution = task
        await task.value
        inFlightResolution = nil
    }

    /// Pair ledger reconciliation with destination recovery.
    ///
    /// Idempotent: `AppState` is built once in the app but repeatedly in tests,
    /// and re-assigning the provider is harmless.
    static func installReconciler() {
        DestinationRecovery.reconcilerProvider = { TrialLedgerReconciler(ledger: ledger) }
    }
}
