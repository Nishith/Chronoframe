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
    ///
    /// Owned by the store: a message always describes the attempt in front of
    /// the customer, so it is cleared at the start of every purchase and
    /// restore, whenever the entitlement resolves to unlocked, and when a
    /// surface that shows it appears (`dismissStatusMessage()`). Without that
    /// it outlives its attempt: the unlock sheet renders it unconditionally, so
    /// a customer who hit one transient failure would reopen the sheet later
    /// and be shown a stale "that purchase couldn't be completed" before
    /// touching anything. Same lifecycle as `GuardianStore`.
    @Published public private(set) var statusMessage: String? {
        didSet { if statusMessage == nil { statusMessageSurvivesDismissal = false } }
    }

    /// True for a message about something still outstanding — an Ask to Buy
    /// approval that has not arrived, or a purchase the App Store completed but
    /// this Mac could not verify. `dismissStatusMessage()` leaves these alone:
    /// the unlock sheet has no other place to say so, and wiping "Don't buy
    /// again" on re-presentation would leave a bare Buy button. The customer's
    /// next attempt, or an unlock by any route, still clears them.
    private var statusMessageSurvivesDismissal = false

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
    private let retryInterval: TimeInterval
    private let unconfirmedWaitLimit: TimeInterval
    private let sleep: @Sendable (TimeInterval) async -> Void

    private var updatesTask: Task<Void, Never>?

    /// When the App Store was last asked anything that could settle the
    /// entitlement — every `refresh()`, whoever called it, and restore's
    /// `sync()`. The retry throttle reads this, so a restore or purchase that
    /// just failed offline counts, and the License pane's follow-up read does
    /// not immediately repeat the same failing round-trip.
    private var lastAppStoreAttempt: Date?

    /// The single resolution started by `resolveIfNeeded()`, shared by every
    /// OTHER `resolveIfNeeded()` caller that arrives while it runs.
    ///
    /// This does NOT coalesce every `refresh()` call in the store: `purchase()`,
    /// `restore()`, and the transaction-update observer all call `refresh()`
    /// directly, bypassing this field entirely, so any of them can run
    /// concurrently with a `resolveIfNeeded()`-driven resolution (or with each
    /// other). `refreshGeneration` below keeps the PUBLISHED `state` consistent
    /// across that race, but it also means a caller that needs to describe ITS
    /// OWN outcome — `restore()`'s message — cannot trust `state` right after
    /// `await refresh()`; it must use the value `refresh()` itself returns. See
    /// that method's doc comment.
    ///
    /// Without `resolution`, two `resolveIfNeeded()` callers racing on a cold
    /// store would both call `refresh()`. The generation tag makes the loser
    /// return WITHOUT setting state — so if the loser finished first, its
    /// caller would read `.loading` and refuse a customer who may well have
    /// paid. Coalescing removes that race rather than retrying around it.
    private var resolution: Task<Void, Never>?

    /// Whether an unconfirmed answer re-checks itself in the background. Off
    /// until `startObservingUpdates()`, so tests and the CLI never schedule it.
    private var retriesWhileUnconfirmed = false
    private var unconfirmedRetryTask: Task<Void, Never>?

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
        clock: @escaping @Sendable () -> Date = { Date() },
        retryInterval: TimeInterval = EntitlementRetryPolicy.unconfirmedRetryInterval,
        unconfirmedWaitLimit: TimeInterval = EntitlementStore.defaultUnconfirmedWaitLimit,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = EntitlementStore.taskSleep
    ) {
        self.storeKit = storeKit
        self.appTransactionClient = appTransactionClient
        self.policy = policy
        self.unlockProductID = unlockProductID
        self.defaults = defaults
        self.clock = clock
        self.retryInterval = retryInterval
        self.unconfirmedWaitLimit = unconfirmedWaitLimit
        self.sleep = sleep
    }

    /// How long a gate holding an unconfirmed answer waits on a retry before
    /// going ahead with the answer it has.
    ///
    /// Long enough for a network that has come back to answer; short enough
    /// that an offline Mac does not hold an organize hostage to StoreKit's own
    /// (unbounded) timeout. The retry keeps running after the wait gives up,
    /// and its answer lands for the next caller.
    public static let defaultUnconfirmedWaitLimit: TimeInterval = 3

    public static let taskSleep: @Sendable (TimeInterval) async -> Void = { seconds in
        try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
    }

    // MARK: Resolution

    /// Read entitlements and the app transaction, then resolve.
    ///
    /// Must be called at launch: `Transaction.updates` delivers *subsequent*
    /// changes only and never the initial state, so an app that only observes
    /// updates shows a paywall to every paying customer on every cold start.
    ///
    /// Returns the entitlement THIS call resolved, whether or not it went on to
    /// win the write into the published `state` below. `refresh()` is not
    /// coalesced across direct callers (see `resolution`'s doc comment), so a
    /// concurrent, unrelated refresh can beat this one to `state` and make the
    /// generation guard below discard this call's write. A caller that needs
    /// to describe its OWN round trip — `restore()`'s message — must read the
    /// return value, not `state`, or it can end up reporting an entirely
    /// different call's outcome.
    @discardableResult
    public func refresh() async -> EntitlementState {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        lastAppStoreAttempt = clock()

        // Bind to locals first. Both are Sendable existentials, so lifting them
        // out of `self` keeps the concurrent child tasks from having to reach
        // back into MainActor-isolated storage.
        let storeKit = self.storeKit
        let appTransactionClient = self.appTransactionClient

        async let ownedTask = storeKit.ownedProducts()
        async let appTransactionTask = appTransactionClient.appTransaction()

        let owned = await ownedTask
        let appTransaction = await appTransactionTask
        let now = clock()

        let resolved = EntitlementResolver.resolve(
            ownedProducts: owned,
            appTransaction: appTransaction,
            cachedLegacyGrant: cachedGrant(),
            unlockProductID: unlockProductID,
            policy: policy,
            now: now
        )

        // A newer refresh started and already settled while we were suspended.
        // Its answer is fresher than ours for the PUBLISHED state and the
        // cache, so discard those effects — but `resolved` is still this
        // call's own answer, and is handed back regardless.
        guard generation == refreshGeneration else { return resolved }

        state = resolved

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

        // However the unlock arrived — a purchase, a restore, an Ask to Buy
        // approval through `Transaction.updates`, or a retry after the network
        // came back — an unlocked customer must not be left reading a failure
        // or a "needs approval" note about an attempt that no longer matters.
        if state.isUnlocked {
            statusMessage = nil
        }

        scheduleUnconfirmedRetryIfNeeded()
        return resolved
    }

    /// Resolve on behalf of a gate or a status surface, sharing any resolution
    /// already in flight.
    ///
    /// - `loading`: waits for the answer, however long it takes. A gate must
    ///   never treat "not asked yet" as "not paid".
    /// - `verificationUnavailable` / `unverified`: retries at most once per
    ///   `retryInterval` (`EntitlementRetryPolicy`), and waits on that retry for
    ///   at most `unconfirmedWaitLimit` before returning with the answer it
    ///   already had. The retry itself carries on and lands for the next caller.
    /// - `locked` / `unlocked`: settled, so returns at once unless a resolution
    ///   is already running, which it joins on the same bounded wait.
    public func resolveIfNeeded() async {
        let hasAnswer = !state.isResolving
        guard let task = startOrJoinResolution() else { return }
        if hasAnswer {
            await wait(for: task, upTo: unconfirmedWaitLimit)
        } else {
            await task.value
        }
    }

    private func startOrJoinResolution() -> Task<Void, Never>? {
        if let resolution { return resolution }
        guard EntitlementRetryPolicy.shouldResolve(
            state: state,
            lastAttempt: lastAppStoreAttempt,
            now: clock(),
            retryInterval: retryInterval
        ) else { return nil }

        let task = Task { [self] in
            await refresh()
            resolution = nil
        }
        resolution = task
        return task
    }

    /// Wait for `task`, or `limit` seconds, whichever comes first. The shared
    /// `task` is not cancelled on timeout — only this caller stops waiting for
    /// it. Cancelling the CALLING task (e.g. a `.task` view modifier whose view
    /// disappeared) also ends the wait immediately, rather than sitting out
    /// `limit` for no one — same `withTaskCancellationHandler` + resume-once
    /// gate shape as `BoundedLivePhotoMetadataLoader`'s `OutcomeGate`.
    private func wait(for task: Task<Void, Never>, upTo limit: TimeInterval) async {
        let sleep = self.sleep
        let resume = ResumeOnce()
        let timer = Task {
            await sleep(limit)
            resume()
        }
        let waiter = Task {
            await task.value
            timer.cancel()
            resume()
        }
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                resume.install(continuation)
            }
        } onCancel: {
            timer.cancel()
            waiter.cancel()
            resume()
        }
    }

    /// While the answer is unconfirmed, ask again in the background.
    ///
    /// Gates and the License pane retry on demand, but nothing else asks: a
    /// paying customer who launched offline would keep seeing a metered
    /// allowance in the workspace until they happened to start a run or open
    /// Settings. This re-checks every `retryInterval` until the answer settles,
    /// and never before the first resolution — launch stays StoreKit-free.
    private func scheduleUnconfirmedRetryIfNeeded() {
        guard retriesWhileUnconfirmed, state.isUnconfirmed, unconfirmedRetryTask == nil else { return }
        let sleep = self.sleep
        let interval = retryInterval
        unconfirmedRetryTask = Task { [weak self] in
            await sleep(interval)
            guard !Task.isCancelled, let self else { return }
            self.unconfirmedRetryTask = nil
            if let task = self.startOrJoinResolution() {
                await task.value
            }
            // A resolution that landed schedules the next check itself; one the
            // throttle declined (a gate asked moments ago) must not end the
            // chain, or an offline Mac would stop re-checking for good.
            self.scheduleUnconfirmedRetryIfNeeded()
        }
    }

    /// Clear a message left over from an earlier attempt.
    ///
    /// Called when a surface that shows the message appears, so reopening the
    /// unlock sheet does not greet the customer with a failure from last time.
    /// Safe mid-attempt: a running purchase or restore writes its message only
    /// as it finishes, so its outcome still lands after this. A message about
    /// something still outstanding (`statusMessageSurvivesDismissal`) stays.
    public func dismissStatusMessage() {
        guard !statusMessageSurvivesDismissal else { return }
        statusMessage = nil
    }

    /// Fetch display metadata for the unlock. Safe to call repeatedly; the UI
    /// offers Retry when this leaves `product` nil.
    public func loadProduct() async {
        product = await storeKit.product(for: unlockProductID)
    }

    // MARK: Purchase

    public func purchase() async {
        // Purchase and restore are mutually exclusive: each ends by writing
        // `statusMessage`, and whichever finished second would silently
        // replace what the first needed to say — a restore reporting "no
        // previous purchase" over "don't buy again" is the dangerous one.
        guard !isPurchasing, !isRestoring else { return }
        isPurchasing = true
        defer { isPurchasing = false }
        // Cleared after the re-entrancy guard, not before: a concurrent call
        // must not wipe the message the in-flight attempt is about to set.
        statusMessage = nil

        switch await storeKit.purchase(productID: unlockProductID) {
        case .purchased:
            await refresh()
        case .pending:
            setStatusMessageUnlessUnlocked(
                "Your purchase needs approval before it can finish. "
                    + "Chronoframe will unlock automatically once it's approved.",
                survivesDismissal: true
            )
        case .userCancelled:
            break
        case .unverified:
            // The App Store completed this purchase; only local verification
            // failed. Saying "nothing was charged" would be false, and would
            // push someone toward paying a second time.
            setStatusMessageUnlessUnlocked(
                "Chronoframe couldn't verify that purchase on this Mac. "
                    + "Don't buy again — choose Restore Purchases first, and contact support if it still doesn't unlock.",
                survivesDismissal: true
            )
        case .productUnavailable:
            setStatusMessageUnlessUnlocked(
                "Chronoframe couldn't load the unlock from the App Store. "
                    + "Check your connection and try again."
            )
        case .failed:
            // The diagnostic stays out of the UI by design; raw StoreKit and
            // NSError wording is never shown to the user.
            setStatusMessageUnlessUnlocked(
                "That purchase couldn't be completed. "
                    + "Check your connection and try again, or use Restore Purchases if you've already bought the unlock."
            )
        }
    }

    /// Skips setting a pending/failure message if a concurrent, unrelated
    /// refresh already unlocked the store while `storeKit.purchase(productID:)`
    /// was in flight — the same rule `refresh()` applies to its own message
    /// clearing (`if state.isUnlocked { statusMessage = nil }`). Without this,
    /// an outcome that lost its race with an unrelated unlock (a second
    /// device's Ask to Buy approval arriving through `Transaction.updates`
    /// mid-purchase, say) would leave a stale "needs approval" or failure note
    /// next to an entitlement that is, in fact, already unlocked.
    private func setStatusMessageUnlessUnlocked(_ message: String, survivesDismissal: Bool = false) {
        guard !state.isUnlocked else { return }
        statusMessage = message
        statusMessageSurvivesDismissal = survivesDismissal
    }

    /// Restore. Must only be called from an explicit user action — `sync()` can
    /// prompt for App Store authentication, which is hostile on launch.
    public func restore() async {
        // See `purchase()`: the two never overlap.
        guard !isRestoring, !isPurchasing else { return }
        isRestoring = true
        defer { isRestoring = false }
        statusMessage = nil

        // A failed sync is an App Store round-trip too, for the throttle.
        lastAppStoreAttempt = clock()
        do {
            try await storeKit.sync()
        } catch {
            setStatusMessageUnlessUnlocked(
                "Chronoframe couldn't reach the App Store to restore your purchase. "
                    + "Check your connection and try again."
            )
            return
        }
        // Switch on what THIS round trip found, not the published `state`:
        // `refresh()` is not coalesced across direct callers (see
        // `resolution`'s doc comment), so an unrelated concurrent refresh can
        // win the generation tag and leave `state` describing a different
        // call entirely. See
        // `testRestoreReportsItsOwnOutcomeDespiteAConcurrentRefreshRace`.
        let result = await refresh()

        switch result {
        case .locked:
            // Said plainly: restore only recovers an existing purchase. It is
            // not a repair path for someone who has never bought the unlock,
            // and implying otherwise sends people round in circles.
            setStatusMessageUnlessUnlocked(
                "No previous purchase was found for this Apple Account. "
                    + "If you bought Chronoframe with a different account, sign in with that one."
            )
        case .verificationUnavailable:
            // Emphatically not the same as "you never paid". Diagnosing a
            // missing account to someone who did pay is the worse error.
            setStatusMessageUnlessUnlocked(
                "Chronoframe couldn't reach the App Store to check your purchase. "
                    + "Your access is unchanged — try again once you're back online."
            )
        case .unverified:
            setStatusMessageUnlessUnlocked(
                "The App Store's response couldn't be verified on this Mac. "
                    + "Try again, and contact support if it keeps happening."
            )
        case .unlocked, .loading:
            break
        }
    }

    // MARK: Updates

    /// Observe entitlement changes for the process lifetime. Refunds and Family
    /// Sharing revocations arrive here, so access is withdrawn without a relaunch.
    ///
    /// Also arms the background re-check for an unconfirmed answer
    /// (`scheduleUnconfirmedRetryIfNeeded`): a network coming back is the other
    /// entitlement change nothing else would notice.
    public func startObservingUpdates() {
        retriesWhileUnconfirmed = true
        scheduleUnconfirmedRetryIfNeeded()
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
        retriesWhileUnconfirmed = false
        unconfirmedRetryTask?.cancel()
        unconfirmedRetryTask = nil
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

/// Resumes a continuation exactly once, from whichever of several racing
/// tasks — or the wait itself being cancelled — gets there first.
private final class ResumeOnce: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var resolved = false

    /// Installs the continuation to resume later, or resumes it immediately
    /// if `callAsFunction()` already ran before this was installed (e.g. the
    /// wait was already cancelled before `withCheckedContinuation` set up).
    func install(_ continuation: CheckedContinuation<Void, Never>) {
        lock.lock()
        if resolved {
            lock.unlock()
            continuation.resume()
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func callAsFunction() {
        lock.lock()
        resolved = true
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume()
    }
}
