import Foundation

// MARK: - Entitlement resolution (free-trial step 2)
//
// This file answers exactly one question — "has this customer paid?" — and
// answers it with pure, StoreKit-free value types so the rule is unit-testable
// without a StoreKit configuration file, a sandbox account, or a Mac.
//
// It deliberately does NOT know how much trial allowance remains. That is the
// ledger's job (step 3). Composing the two into the user-facing "trial with N
// files left" state happens above both, in the UI layer. Keeping them apart is
// what lets the grandfather rule be verified in isolation, and it keeps this
// type free of any dependency on mutation bookkeeping.

// MARK: Inputs

/// Snapshot of the app-level transaction Apple signs for every install.
///
/// Mirrors the fields of StoreKit's `AppTransaction` that the grandfather rule
/// needs, as a plain value type the live adapter maps into.
public struct AppTransactionInfo: Equatable, Sendable, Codable {
    /// When this customer first obtained the app. Apple-signed, survives
    /// reinstalls and machine transfers, and cannot be reset by clearing local
    /// state — which is why it, and not a local timer, anchors grandfathering.
    public let originalPurchaseDate: Date

    /// The app version this customer originally downloaded. Retained for
    /// diagnostics only: the cutover rule is date-based, because a version
    /// boundary misclassifies customers in both rollout windows.
    public let originalAppVersion: String

    /// Apple's stable per-account identifier for this app transaction.
    ///
    /// Optional because older build SDKs do not expose
    /// `AppTransaction.appTransactionID`. `LiveAppTransactionClient` supplies
    /// it when compiled with the newer StoreKit surface and preserves the
    /// original-purchase-date fallback for older CI toolchains.
    public let appTransactionID: String?

    /// Set when the app-level transaction has been revoked.
    ///
    /// StoreKit's `AppTransaction` API does not expose a revocation date (the
    /// similarly named property belongs to product `Transaction`). The live
    /// adapter therefore supplies `nil`; the resolver retains this input for
    /// test or future signed evidence that can provide it.
    public let revocationDate: Date?

    public init(
        originalPurchaseDate: Date,
        originalAppVersion: String,
        appTransactionID: String? = nil,
        revocationDate: Date? = nil
    ) {
        self.originalPurchaseDate = originalPurchaseDate
        self.originalAppVersion = originalAppVersion
        self.appTransactionID = appTransactionID
        self.revocationDate = revocationDate
    }

    /// Stable key for the trial ledger, scoping the allowance per Apple Account
    /// so a second person on the same Mac gets their own allowance instead of
    /// inheriting a spent one.
    ///
    /// Prefers Apple's `appTransactionID`. Until that SDK is available it falls
    /// back to the original purchase instant, which is also account-scoped and
    /// Apple-signed — two accounts acquire the app at different moments, and the
    /// value survives reinstalls. Collisions are possible in principle but need
    /// two accounts to have acquired the app in the same second on one Mac,
    /// which costs at most one shared trial allowance.
    public var ledgerAccountKey: String {
        if let appTransactionID, !appTransactionID.isEmpty { return appTransactionID }
        return "purchased-at-\(Int(originalPurchaseDate.timeIntervalSince1970))"
    }
}

/// A verified, currently-owned non-consumable.
///
/// Only ever built from a *verified* StoreKit transaction. Refunded and
/// Family-Sharing-revoked products simply stop appearing in
/// `Transaction.currentEntitlements`, so absence is how revocation reaches us.
public struct OwnedProduct: Equatable, Sendable, Codable {
    public let productID: String
    public let purchaseDate: Date

    public init(productID: String, purchaseDate: Date) {
        self.productID = productID
        self.purchaseDate = purchaseDate
    }
}

/// Display metadata for the unlock product. `displayPrice` is always Apple's
/// localized string — never a hardcoded price.
public struct StoreProductInfo: Equatable, Sendable {
    public let productID: String
    public let displayName: String
    public let displayPrice: String

    public init(productID: String, displayName: String, displayPrice: String) {
        self.productID = productID
        self.displayName = displayName
        self.displayPrice = displayPrice
    }
}

/// Why a lookup failed. The distinction matters: `unavailable` is transient and
/// must not lock a paying customer out, whereas `unverified` means a signature
/// did not check out and must never be treated as proof of purchase.
public enum EntitlementLookupFailure: Error, Equatable, Sendable {
    /// Network down, no App Store account, StoreKit unreachable.
    case unavailable
    /// A signature failed verification. Untrustworthy input.
    case unverified
}

/// A previously-verified legacy grant, retained so a customer who paid before
/// the cutover keeps working offline.
public struct CachedLegacyGrant: Equatable, Sendable, Codable {
    public let originalPurchaseDate: Date
    public let appTransactionID: String?
    /// When this grant was last confirmed against a verified app transaction.
    public let recordedAt: Date

    public init(originalPurchaseDate: Date, appTransactionID: String?, recordedAt: Date) {
        self.originalPurchaseDate = originalPurchaseDate
        self.appTransactionID = appTransactionID
        self.recordedAt = recordedAt
    }
}

// MARK: Output

public enum UnlockReason: String, Equatable, Sendable, Codable {
    /// Bought the app before it became free.
    case legacyPurchase
    /// Bought the in-app unlock.
    case inAppPurchase
}

/// The resolved entitlement.
///
/// `verificationUnavailable` is deliberately distinct from `locked`: treating a
/// flight-mode launch as "not paid" would strand paying customers, and treating
/// it as "paid" would hand the app to everyone whose network happens to be off.
/// Callers meter it like the trial but must never report it as a spent trial.
public enum EntitlementState: Equatable, Sendable {
    /// No resolution attempted yet. Never gate on this — wait for it to settle.
    case loading
    /// Resolved, and this customer has not paid. Trial rules apply.
    case locked
    /// Resolved, and this customer has paid.
    case unlocked(reason: UnlockReason)
    /// Could not reach StoreKit and there is no cached grant to fall back on.
    case verificationUnavailable
    /// StoreKit answered, but a signature failed verification.
    case unverified

    public var isUnlocked: Bool {
        if case .unlocked = self { return true }
        return false
    }

    /// True while the answer is still settling. Gates should wait rather than
    /// refuse, so a slow App Store response never looks like a paywall.
    public var isResolving: Bool { self == .loading }

    /// True when resolution finished without establishing whether this customer
    /// paid, and a later attempt could still settle it.
    ///
    /// `locked` and `unlocked` are settled answers and never retried. These two
    /// are not answers about the customer at all — they are answers about the
    /// App Store's reachability at one instant — so treating them as final for
    /// the process lifetime strands a paying customer who happened to launch
    /// offline.
    public var isUnconfirmed: Bool {
        switch self {
        case .verificationUnavailable, .unverified:
            return true
        case .loading, .locked, .unlocked:
            return false
        }
    }
}

// MARK: Retry

/// When an unsettled entitlement is worth asking the App Store about again.
///
/// `EntitlementStore` resolves lazily and keeps its answer for the process
/// lifetime, which is right for a settled answer and wrong for an unsettled
/// one. A customer who launches in a tunnel resolves to
/// `verificationUnavailable`, is metered from then on, and — before this — got
/// no second attempt however long the app stayed open or how soon the network
/// came back. A desktop app runs for days; that is not an acceptable ceiling on
/// "check again".
///
/// Pure and injectable so the throttle is unit-tested rather than observed in a
/// running app against a real network.
public enum EntitlementRetryPolicy {
    /// Minimum spacing between re-resolution attempts while unconfirmed.
    ///
    /// Gates are user-initiated and infrequent, but the License pane and the
    /// trial indicators also ask, and several of those fire from `onChange`.
    /// A floor keeps a genuinely offline Mac from making a StoreKit call per
    /// redraw without making a recovered network wait meaningfully longer.
    public static let unconfirmedRetryInterval: TimeInterval = 60

    /// Whether a caller asking now should start a new resolution.
    ///
    /// Only decides about NEW attempts. Joining one that is already running is
    /// the caller's business (`EntitlementStore.resolveIfNeeded`), and must not
    /// be gated by this: the throttle spaces out App Store round-trips, it never
    /// makes a caller return a stale answer beside a fresher one in flight.
    public static func shouldResolve(
        state: EntitlementState,
        lastAttempt: Date?,
        now: Date,
        retryInterval: TimeInterval = unconfirmedRetryInterval
    ) -> Bool {
        // Never resolved. Always resolve, whatever the clock says.
        if state.isResolving { return true }
        // A settled answer is not re-asked; revocation arrives through
        // `Transaction.updates` instead.
        guard state.isUnconfirmed else { return false }
        guard let lastAttempt else { return true }

        let elapsed = now.timeIntervalSince(lastAttempt)
        // A clock corrected backwards yields a negative interval. Retry rather
        // than stranding someone until the clock catches up — the same posture
        // `GrandfatherPolicy.acceptsCachedGrant` takes.
        return elapsed < 0 || elapsed >= retryInterval
    }
}

// MARK: Policy

/// The paid-to-free migration rule.
///
/// Grandfathering is anchored to Apple's signed `originalPurchaseDate` compared
/// against the moment the listing price actually dropped to free. A version-only
/// boundary (`originalAppVersion < 2.0`) has two failure windows: customers who
/// download the old paid version before v2 finishes propagating are grandfathered
/// forever, and customers who buy v2 before the price drops get asked to pay
/// twice. A timestamp has neither.
///
/// Set `cutover` a few hours LATER than the real price change. Erring late
/// grandfathers a handful of free downloaders; erring early charges paying
/// customers twice. The asymmetry is not close.
public struct GrandfatherPolicy: Equatable, Sendable {
    public let cutover: Date

    /// How long a cached legacy grant is honoured without re-verification.
    ///
    /// Trade-off, stated plainly: a legacy customer who obtains an Apple refund
    /// keeps access until this elapses (or until they next come online). The
    /// alternative — a short window — locks out genuinely offline paying
    /// customers, which is far worse and far more likely. Refunds of a pre-free
    /// purchase are rare; laptops without network are not.
    public let maximumCacheAge: TimeInterval

    public static let defaultMaximumCacheAge: TimeInterval = 90 * 24 * 60 * 60

    public init(cutover: Date, maximumCacheAge: TimeInterval = GrandfatherPolicy.defaultMaximumCacheAge) {
        self.cutover = cutover
        self.maximumCacheAge = maximumCacheAge
    }

    /// Whether a verified app transaction earns a legacy unlock.
    public func grantsLegacyUnlock(_ info: AppTransactionInfo, now: Date) -> Bool {
        if let revocationDate = info.revocationDate, revocationDate <= now { return false }
        return info.originalPurchaseDate < cutover
    }

    /// Whether a cached grant may still stand in for a live check.
    public func acceptsCachedGrant(_ grant: CachedLegacyGrant, now: Date) -> Bool {
        guard grant.originalPurchaseDate < cutover else { return false }
        let age = now.timeIntervalSince(grant.recordedAt)
        // A clock that has moved backwards yields a negative age. Accept it
        // rather than locking someone out over a timezone or NTP correction.
        return age <= maximumCacheAge
    }
}

// MARK: Resolver

/// Pure resolution of the entitlement state from the three inputs the store
/// gathers. Deterministic and side-effect free, so every branch below is
/// reachable from a unit test without StoreKit.
public enum EntitlementResolver {
    public static func resolve(
        ownedProducts: Result<[OwnedProduct], EntitlementLookupFailure>,
        appTransaction: Result<AppTransactionInfo, EntitlementLookupFailure>,
        cachedLegacyGrant: CachedLegacyGrant?,
        unlockProductID: String,
        policy: GrandfatherPolicy,
        now: Date
    ) -> EntitlementState {
        // 1. A verified, currently-owned unlock settles it. This is checked
        //    first so a customer who bought the IAP is unlocked even when the
        //    app transaction lookup is failing.
        if case .success(let owned) = ownedProducts,
           owned.contains(where: { $0.productID == unlockProductID }) {
            return .unlocked(reason: .inAppPurchase)
        }

        // 2. A verified app transaction from before the cutover means they paid
        //    for the app itself.
        if case .success(let info) = appTransaction {
            if policy.grantsLegacyUnlock(info, now: now) {
                return .unlocked(reason: .legacyPurchase)
            }
            // Verified, and they are not a legacy purchaser. If the entitlement
            // lookup ALSO succeeded we have a complete picture: locked. If it
            // failed we cannot rule out an unlock they already own.
            switch ownedProducts {
            case .success:
                return .locked
            case .failure(let failure):
                return state(for: failure)
            }
        }

        // 3. The app transaction is unusable. Fall back to a cached grant before
        //    giving up, so offline legacy customers keep working.
        if let grant = cachedLegacyGrant, policy.acceptsCachedGrant(grant, now: now) {
            return .unlocked(reason: .legacyPurchase)
        }

        // 4. No cache to lean on. Report why, preferring the more serious
        //    failure when both sources failed.
        let appTransactionFailure: EntitlementLookupFailure? = {
            if case .failure(let failure) = appTransaction { return failure }
            return nil
        }()
        let ownedFailure: EntitlementLookupFailure? = {
            if case .failure(let failure) = ownedProducts { return failure }
            return nil
        }()

        if appTransactionFailure == .unverified || ownedFailure == .unverified {
            return .unverified
        }
        return .verificationUnavailable
    }

    private static func state(for failure: EntitlementLookupFailure) -> EntitlementState {
        switch failure {
        case .unavailable: return .verificationUnavailable
        case .unverified: return .unverified
        }
    }
}

// MARK: Product identity

/// Single source of truth for the unlock product and the migration cutover.
public enum ChronoframeUnlock {
    /// The one non-consumable. Family Sharing is enabled on it in App Store
    /// Connect — that switch is irreversible, so it is set at product creation.
    public static let productID = "com.nishith.chronoframe.unlock"

    /// Acquisition cutoff for the planned October 26, 2026 free-price transition.
    /// Apple's regional schedule ends at 03:00 UTC; the four-hour margin protects
    /// paid customers during storefront propagation. This is midnight PDT.
    ///
    /// Release v2 while paid, hold at least seven days, and verify grandfathering
    /// against real purchaser data before scheduling the price change. If the
    /// transition is postponed, ship a later cutoff before this instant; never
    /// continue charging up front past the cutoff in the installed binary.
    public static let grandfatherCutover = Date(timeIntervalSince1970: 1_792_998_000) // 2026-10-26T07:00:00Z

    public static func defaultPolicy() -> GrandfatherPolicy {
        GrandfatherPolicy(cutover: grandfatherCutover)
    }
}
