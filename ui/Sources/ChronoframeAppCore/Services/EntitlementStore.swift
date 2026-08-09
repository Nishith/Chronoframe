#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Combine
import Foundation

// MARK: - Entitlement store (free-trial step 2)
//
// Owns the answer to "has this customer paid?" for the app's lifetime, and
// nothing else. It holds no trial allowance and no mutation bookkeeping — the
// durable ledger (step 3) is a separate object, and the UI composes the two.
//
// All policy lives in `ChronoframeCore/Entitlement.swift`; this type is the
// I/O and observation shell around it.

@MainActor
public final class EntitlementStore: ObservableObject {
    /// The resolved entitlement. Starts `.loading` — gates must wait for it to
    /// settle rather than treating the initial value as "not paid".
    @Published public private(set) var state: EntitlementState = .loading

    /// Display metadata for the unlock, including Apple's localized price.
    /// Nil until loaded, or when the product could not be fetched.
    @Published public private(set) var product: StoreProductInfo?

    @Published public private(set) var isPurchasing = false
    @Published public private(set) var isRestoring = false

    /// Set when a purchase or restore needs to say something to the user.
    /// Cleared by the UI once shown.
    @Published public var statusMessage: String?

    /// Stable key for the trial ledger, so switching Apple Accounts cannot
    /// reuse another account's spent allowance. Nil on macOS below 15.4, where
    /// the ledger falls back to a per-Mac record.
    @Published public private(set) var ledgerAccountKey: String?

    private let storeKit: any StoreKitClient
    private let appTransactionClient: any AppTransactionClient
    private let policy: GrandfatherPolicy
    private let unlockProductID: String
    private let defaults: UserDefaults
    private let clock: @Sendable () -> Date

    private var updatesTask: Task<Void, Never>?

    /// Guards against a stale refresh landing last.
    ///
    /// `refresh()` suspends across the StoreKit calls, and two can be in flight
    /// at once — `purchase()` refreshes while the update observer independently
    /// refreshes for the same transaction. Without this, an older invocation can
    /// resume after a newer one and overwrite a just-unlocked or just-revoked
    /// state with its stale snapshot. Same epoch pattern as `RunSessionStore`.
    private var refreshGeneration: UInt64 = 0

    private static let cachedGrantKey = "entitlement.cachedLegacyGrant"

    public init(
        storeKit: any StoreKitClient,
        appTransactionClient: any AppTransactionClient,
        policy: GrandfatherPolicy = ChronoframeUnlock.defaultPolicy(),
        unlockProductID: String = ChronoframeUnlock.productID,
        defaults: UserDefaults = .standard,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.storeKit = storeKit
        self.appTransactionClient = appTransactionClient
        self.policy = policy
        self.unlockProductID = unlockProductID
        self.defaults = defaults
        self.clock = clock
    }

    // MARK: Resolution

    /// Read entitlements and the app transaction, then resolve.
    ///
    /// Must be called at launch: `Transaction.updates` delivers *subsequent*
    /// changes only and never the initial state, so an app that only observes
    /// updates shows a paywall to every paying customer on every cold start.
    public func refresh() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration

        // Bind to locals first. Both are Sendable existentials, so lifting them
        // out of `self` keeps the concurrent child tasks from having to reach
        // back into MainActor-isolated storage.
        let storeKit = self.storeKit
        let appTransactionClient = self.appTransactionClient

        async let ownedTask = storeKit.ownedProducts()
        async let appTransactionTask = appTransactionClient.appTransaction()

        let owned = await ownedTask
        let appTransaction = await appTransactionTask

        // A newer refresh started and already settled while we were suspended.
        // Its answer is fresher than ours; discard this one entirely, including
        // the cache write below.
        guard generation == refreshGeneration else { return }

        let now = clock()

        state = EntitlementResolver.resolve(
            ownedProducts: owned,
            appTransaction: appTransaction,
            cachedLegacyGrant: cachedGrant(),
            unlockProductID: unlockProductID,
            policy: policy,
            now: now
        )

        if case .success(let info) = appTransaction {
            ledgerAccountKey = info.ledgerAccountKey
            // Only a *verified* app transaction may write or clear the cache.
            // An unavailable lookup must leave an existing grant alone, which
            // is the whole point of keeping it.
            if policy.grantsLegacyUnlock(info, now: now) {
                storeCachedGrant(
                    CachedLegacyGrant(
                        originalPurchaseDate: info.originalPurchaseDate,
                        appTransactionID: info.appTransactionID,
                        recordedAt: now
                    )
                )
            } else {
                clearCachedGrant()
            }
        }
    }

    /// Fetch display metadata for the unlock. Safe to call repeatedly; the UI
    /// offers Retry when this leaves `product` nil.
    public func loadProduct() async {
        product = await storeKit.product(for: unlockProductID)
    }

    // MARK: Purchase

    public func purchase() async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        switch await storeKit.purchase(productID: unlockProductID) {
        case .purchased:
            await refresh()
        case .pending:
            statusMessage = "Your purchase needs approval before it can finish. "
                + "Chronoframe will unlock automatically once it's approved."
        case .userCancelled:
            break
        case .unverified:
            // The App Store completed this purchase; only local verification
            // failed. Saying "nothing was charged" would be false, and would
            // push someone toward paying a second time.
            statusMessage = "Chronoframe couldn't verify that purchase on this Mac. "
                + "Don't buy again — choose Restore Purchases first, and contact support if it still doesn't unlock."
        case .productUnavailable:
            statusMessage = "Chronoframe couldn't load the unlock from the App Store. "
                + "Check your connection and try again."
        case .failed:
            // The diagnostic stays out of the UI by design; raw StoreKit and
            // NSError wording is never shown to the user.
            statusMessage = "That purchase couldn't be completed. "
                + "Check your connection and try again, or use Restore Purchases if you've already bought the unlock."
        }
    }

    /// Restore. Must only be called from an explicit user action — `sync()` can
    /// prompt for App Store authentication, which is hostile on launch.
    public func restore() async {
        guard !isRestoring else { return }
        isRestoring = true
        defer { isRestoring = false }

        do {
            try await storeKit.sync()
        } catch {
            statusMessage = "Chronoframe couldn't reach the App Store to restore your purchase. "
                + "Check your connection and try again."
            return
        }
        await refresh()

        switch state {
        case .locked:
            // Said plainly: restore only recovers an existing purchase. It is
            // not a repair path for someone who has never bought the unlock,
            // and implying otherwise sends people round in circles.
            statusMessage = "No previous purchase was found for this Apple Account. "
                + "If you bought Chronoframe with a different account, sign in with that one."
        case .verificationUnavailable:
            // Emphatically not the same as "you never paid". Diagnosing a
            // missing account to someone who did pay is the worse error.
            statusMessage = "Chronoframe couldn't reach the App Store to check your purchase. "
                + "Your access is unchanged — try again once you're back online."
        case .unverified:
            statusMessage = "The App Store's response couldn't be verified on this Mac. "
                + "Try again, and contact support if it keeps happening."
        case .unlocked, .loading:
            break
        }
    }

    // MARK: Updates

    /// Observe entitlement changes for the process lifetime. Refunds and Family
    /// Sharing revocations arrive here, so access is withdrawn without a relaunch.
    public func startObservingUpdates() {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.storeKit.transactionUpdates() {
                await self.refresh()
            }
        }
    }

    /// Explicit teardown. Deliberately not a `deinit` — touching actor-isolated
    /// state from `deinit` is not expressible under Swift 6 strict concurrency.
    public func stopObservingUpdates() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: Cache

    private func cachedGrant() -> CachedLegacyGrant? {
        guard let data = defaults.data(forKey: Self.cachedGrantKey) else { return nil }
        return try? Self.decoder.decode(CachedLegacyGrant.self, from: data)
    }

    private func storeCachedGrant(_ grant: CachedLegacyGrant) {
        guard let data = try? Self.encoder.encode(grant) else { return }
        defaults.set(data, forKey: Self.cachedGrantKey)
    }

    private func clearCachedGrant() {
        defaults.removeObject(forKey: Self.cachedGrantKey)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
