import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

// MARK: - Fakes

/// `@unchecked Sendable` because XCTest drives each test serially on the main
/// thread, so the mutable recording state below is never touched concurrently.
/// Same reasoning as the `nonisolated(unsafe)` fixtures in `PreferencesStoreTests`.
private final class FakeStoreKitClient: StoreKitClient, @unchecked Sendable {
    var productResult: StoreProductInfo?
    var ownedResult: Result<[OwnedProduct], EntitlementLookupFailure> = .success([])
    var purchaseResult: PurchaseOutcome = .userCancelled
    var syncError: Error?

    private(set) var purchaseCallCount = 0
    private(set) var syncCallCount = 0
    private(set) var ownedCallCount = 0

    private var updatesContinuation: AsyncStream<Void>.Continuation?

    /// Runs while `ownedProducts()` is suspended, after it has captured its
    /// result. Lets a test interleave a second refresh inside the first one.
    var whileOwnedProductsSuspended: (() async -> Void)?

    func product(for productID: String) async -> StoreProductInfo? { productResult }

    func ownedProducts() async -> Result<[OwnedProduct], EntitlementLookupFailure> {
        ownedCallCount += 1
        // Capture before suspending, so this call returns the value that was
        // current when it started — which is what makes it the stale one.
        let captured = ownedResult
        if let hook = whileOwnedProductsSuspended {
            await hook()
        }
        return captured
    }

    /// Runs while `purchase(productID:)` is suspended, before it returns.
    var whilePurchaseSuspended: (() async -> Void)?
    /// Runs while `sync()` is suspended, before it returns or throws.
    var whileSyncSuspended: (() async -> Void)?

    func purchase(productID: String) async -> PurchaseOutcome {
        purchaseCallCount += 1
        if let hook = whilePurchaseSuspended {
            await hook()
        }
        return purchaseResult
    }

    func sync() async throws {
        syncCallCount += 1
        if let hook = whileSyncSuspended {
            await hook()
        }
        if let syncError { throw syncError }
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.updatesContinuation = continuation
        }
    }

    /// Whether the store has subscribed yet — an update emitted before that is
    /// dropped, exactly as a real `Transaction.updates` would drop it.
    var isObservingUpdates: Bool { updatesContinuation != nil }

    func emitTransactionUpdate() {
        updatesContinuation?.yield(())
    }
}

private final class FakeAppTransactionClient: AppTransactionClient, @unchecked Sendable {
    var result: Result<AppTransactionInfo, EntitlementLookupFailure> = .failure(.unavailable)

    func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure> { result }
}

private struct FakeError: Error {}

/// A one-shot latch a fake can suspend on until the test opens it.
private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            if isOpen {
                lock.unlock()
                continuation.resume()
            } else {
                waiters.append(continuation)
                lock.unlock()
            }
        }
    }

    func open() {
        lock.lock()
        isOpen = true
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

@MainActor
private final class Flag {
    var value = false
}

/// A clock the test moves by hand, for the retry throttle.
private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date

    init(_ start: Date) { current = start }

    var now: Date {
        lock.lock(); defer { lock.unlock() }
        return current
    }

    func advance(by interval: TimeInterval) {
        lock.lock(); current = current.addingTimeInterval(interval); lock.unlock()
    }
}

/// A sleep that only returns when the test says so, and records what was asked
/// for — so the background re-check can be stepped deterministically.
private final class ManualSleeper: @unchecked Sendable {
    private let lock = NSLock()
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var durations: [TimeInterval] = []

    var pendingCount: Int {
        lock.lock(); defer { lock.unlock() }
        return waiters.count
    }

    var requestedDurations: [TimeInterval] {
        lock.lock(); defer { lock.unlock() }
        return durations
    }

    func sleep(_ seconds: TimeInterval) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lock.lock()
            durations.append(seconds)
            waiters.append(continuation)
            lock.unlock()
        }
    }

    func wakeAll() {
        lock.lock()
        let pending = waiters
        waiters = []
        lock.unlock()
        pending.forEach { $0.resume() }
    }
}

// MARK: - Tests

final class EntitlementStoreTests: XCTestCase {
    private nonisolated(unsafe) var suiteName: String!
    private nonisolated(unsafe) var defaults: UserDefaults!

    private let cutover = Date(timeIntervalSince1970: 1_800_000_000)
    private let now = Date(timeIntervalSince1970: 1_800_100_000)

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "EntitlementStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    @MainActor
    private func makeStore(
        storeKit: FakeStoreKitClient,
        appTransaction: FakeAppTransactionClient,
        maximumCacheAge: TimeInterval = GrandfatherPolicy.defaultMaximumCacheAge,
        clock: TestClock? = nil,
        unconfirmedWaitLimit: TimeInterval = EntitlementStore.defaultUnconfirmedWaitLimit,
        sleep: @escaping @Sendable (TimeInterval) async -> Void = EntitlementStore.taskSleep
    ) -> EntitlementStore {
        let clock = clock ?? TestClock(now)
        return EntitlementStore(
            storeKit: storeKit,
            appTransactionClient: appTransaction,
            policy: GrandfatherPolicy(cutover: cutover, maximumCacheAge: maximumCacheAge),
            unlockProductID: ChronoframeUnlock.productID,
            defaults: defaults,
            clock: { clock.now },
            unconfirmedWaitLimit: unconfirmedWaitLimit,
            sleep: sleep
        )
    }

    /// Poll until `condition` holds, for work running on other tasks. Fails the
    /// test rather than hanging if it never does.
    @MainActor
    private func eventually(
        _ message: String,
        timeout: TimeInterval = 5,
        _ condition: @MainActor () -> Bool
    ) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() > deadline {
                XCTFail("Timed out waiting: \(message)")
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    /// Give other tasks a real chance to run, for asserting something did NOT
    /// happen.
    @MainActor
    private func settle() async {
        for _ in 0..<20 {
            try? await Task.sleep(nanoseconds: 2_000_000)
        }
    }

    private func ownedUnlock() -> Result<[OwnedProduct], EntitlementLookupFailure> {
        .success([OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: now)])
    }

    private func legacyInfo(id: String? = "app-txn-1") -> AppTransactionInfo {
        AppTransactionInfo(
            originalPurchaseDate: cutover.addingTimeInterval(-5000),
            originalAppVersion: "1.2",
            appTransactionID: id
        )
    }

    private func newInfo() -> AppTransactionInfo {
        AppTransactionInfo(
            originalPurchaseDate: cutover.addingTimeInterval(5000),
            originalAppVersion: "2.0",
            appTransactionID: "app-txn-2"
        )
    }

    // MARK: Initial state

    @MainActor
    func testStartsLoadingSoGatesDoNotPaywallOnLaunch() {
        let store = makeStore(storeKit: FakeStoreKitClient(), appTransaction: FakeAppTransactionClient())
        XCTAssertEqual(store.state, .loading)
        XCTAssertTrue(store.state.isResolving)
        XCTAssertFalse(store.state.isUnlocked)
    }

    // MARK: Refresh

    @MainActor
    func testRefreshUnlocksLegacyPurchaserAndCachesTheGrant() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(legacyInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.refresh()

        XCTAssertEqual(store.state, .unlocked(reason: .legacyPurchase))
        XCTAssertEqual(store.ledgerAccountKey, "app-txn-1")
        XCTAssertNotNil(defaults.data(forKey: "entitlement.cachedLegacyGrant"))
    }

    /// The cached grant is what keeps an offline legacy customer working.
    @MainActor
    func testCachedGrantSurvivesLaterUnavailableLookup() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(legacyInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        appTransaction.result = .failure(.unavailable)
        storeKit.ownedResult = .failure(.unavailable)
        await store.refresh()

        XCTAssertEqual(store.state, .unlocked(reason: .legacyPurchase))
    }

    /// An unavailable lookup must leave an existing cache alone — clearing it
    /// would lock out the customer it exists to protect.
    @MainActor
    func testUnavailableLookupDoesNotClearTheCache() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(legacyInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        appTransaction.result = .failure(.unavailable)
        await store.refresh()

        XCTAssertNotNil(defaults.data(forKey: "entitlement.cachedLegacyGrant"))
    }

    /// A verified non-legacy transaction is authoritative and must clear any
    /// stale grant, so a refunded or transferred install cannot coast on it.
    @MainActor
    func testVerifiedNonLegacyTransactionClearsTheCache() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(legacyInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        XCTAssertNotNil(defaults.data(forKey: "entitlement.cachedLegacyGrant"))

        appTransaction.result = .success(newInfo())
        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertNil(defaults.data(forKey: "entitlement.cachedLegacyGrant"))
    }

    @MainActor
    func testRefreshUnlocksOnOwnedProduct() async {
        let storeKit = FakeStoreKitClient()
        storeKit.ownedResult = .success([OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: now)])
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.refresh()

        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
    }

    // MARK: Purchase

    @MainActor
    func testSuccessfulPurchaseRefreshesAndUnlocks() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        XCTAssertEqual(store.state, .locked)

        storeKit.purchaseResult = .purchased
        storeKit.ownedResult = .success([OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: now)])
        await store.purchase()

        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
        XCTAssertFalse(store.isPurchasing)
    }

    @MainActor
    func testPendingPurchaseExplainsItselfAndDoesNotUnlock() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .pending
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()

        XCTAssertEqual(store.state, .locked)
        XCTAssertNotNil(store.statusMessage)
    }

    /// Regression: `purchase()`'s outcome and any concurrent, unrelated
    /// refresh (the transaction-update observer picking up a different
    /// already-approved transaction, a background retry, another
    /// `resolveIfNeeded()` caller) are not coalesced — both call `refresh()`
    /// independently. If that concurrent refresh unlocks the store WHILE
    /// `storeKit.purchase(productID:)` is still suspended, the `.pending`
    /// branch must not paper over the now-current "Unlocked" status with a
    /// stale "needs approval" note.
    @MainActor
    func testPendingOutcomeDoesNotOverwriteAConcurrentUnlock() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .pending
        let appTransaction = FakeAppTransactionClient()
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        storeKit.whilePurchaseSuspended = { [weak storeKit, weak store] in
            guard let storeKit, let store else { return }
            // A second, unrelated device's approval lands through
            // `Transaction.updates` and unlocks the store before this
            // purchase's own `.pending` outcome comes back.
            storeKit.ownedResult = .success([
                OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: Date())
            ])
            await store.refresh()
        }

        await store.purchase()

        XCTAssertTrue(store.state.isUnlocked, "Precondition: the concurrent refresh unlocked it")
        XCTAssertNil(
            store.statusMessage,
            "Already unlocked by the time .pending came back; must not show a stale approval note"
        )
    }

    /// A message must describe the attempt in front of the customer, not an
    /// earlier one. The unlock sheet renders `statusMessage` unconditionally,
    /// so a message that outlived its attempt greets the next sheet with a
    /// failure the customer has not had yet.
    @MainActor
    func testPurchaseClearsAStaleMessageFromAnEarlierAttempt() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .productUnavailable
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()
        XCTAssertNotNil(store.statusMessage, "The failing attempt should say so")

        // A later attempt the customer cancels says nothing of its own, so the
        // earlier failure must not still be on screen.
        storeKit.purchaseResult = .userCancelled
        await store.purchase()

        XCTAssertNil(store.statusMessage)
    }

    /// The same for restore, whose success path also sets no message.
    @MainActor
    func testRestoreClearsAStaleMessageFromAnEarlierAttempt() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .productUnavailable
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()
        XCTAssertNotNil(store.statusMessage)

        // Now the unlock is owned and restore succeeds outright.
        storeKit.ownedResult = .success([
            OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: Date())
        ])
        await store.restore()

        XCTAssertTrue(store.state.isUnlocked)
        XCTAssertNil(
            store.statusMessage,
            "An unlocked customer must not be left reading a purchase failure"
        )
    }

    /// HIGH regression: `restore()` calls `refresh()` and then picked its
    /// message from the PUBLISHED `state`. `refresh()` is not coalesced across
    /// direct callers (see the `resolution` doc comment) — a concurrent,
    /// unrelated `refresh()` (the background unconfirmed-retry, the
    /// transaction-update observer, or another `resolveIfNeeded()` caller) can
    /// enter and finish writing `state` while restore's own `refresh()` is
    /// still suspended on the network. `refreshGeneration` then discards
    /// restore's own (correct) answer as "stale", and restore reports the
    /// OTHER call's state instead of its own. Fixed by having `restore()`
    /// switch on the value `refresh()` itself returns.
    @MainActor
    func testRestoreReportsItsOwnOutcomeDespiteAConcurrentRefreshRace() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient() // no legacy transaction
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        // What restore's own sync()+refresh() round trip should find: the
        // purchase really is there.
        storeKit.ownedResult = ownedUnlock()

        var hasInterleaved = false
        storeKit.whileOwnedProductsSuspended = { [weak storeKit, weak store] in
            guard !hasInterleaved, let storeKit, let store else { return }
            hasInterleaved = true
            // A second, unrelated refresh races in and reads DIFFERENT
            // (stale) data — standing in for a background retry or the
            // transaction-update observer, neither of which is coalesced
            // with restore's own direct `refresh()` call. It enters after
            // restore's own call and so wins the generation tag, but it must
            // not get to speak for restore's own outcome.
            storeKit.ownedResult = .success([])
            await store.refresh()
        }

        await store.restore()

        XCTAssertNil(
            store.statusMessage,
            "Restore's own round trip found the purchase; it must not report " +
                "\"No previous purchase was found\" because an unrelated concurrent " +
                "refresh raced it and won the generation tag: \(store.statusMessage ?? "nil")"
        )
    }

    /// Cancelling is a normal choice, not an error. It must stay silent.
    @MainActor
    func testCancelledPurchaseSaysNothing() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .userCancelled
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()

        XCTAssertNil(store.statusMessage)
        XCTAssertEqual(store.state, .locked)
    }

    /// `.unverified` comes from a purchase the App Store *completed*; only local
    /// verification failed. Claiming no charge was taken would be false, and
    /// would nudge someone into paying twice.
    @MainActor
    func testUnverifiedPurchaseNeverClaimsNothingWasCharged() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .unverified
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()

        XCTAssertEqual(store.state, .locked)
        let message = try? XCTUnwrap(store.statusMessage)
        XCTAssertEqual(message?.lowercased().contains("charged"), false)
        XCTAssertEqual(message?.contains("Restore Purchases"), true)
        XCTAssertEqual(message?.contains("Don't buy again"), true)
    }

    /// Raw StoreKit/NSError wording must never reach the UI.
    @MainActor
    func testFailedPurchaseHidesTheTechnicalDiagnostic() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .failed(diagnostic: "SKErrorDomain Code=2 \"Cannot connect to iTunes Store\"")
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()

        let message = try? XCTUnwrap(store.statusMessage)
        XCTAssertEqual(message?.contains("SKErrorDomain"), false)
        XCTAssertEqual(message?.contains("couldn't be completed"), true)
    }

    @MainActor
    func testProductUnavailablePurchaseExplainsItself() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .productUnavailable
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()

        XCTAssertEqual(store.statusMessage?.contains("couldn't load the unlock"), true)
    }

    // MARK: Restore

    @MainActor
    func testRestoreSyncsThenRefreshes() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        storeKit.ownedResult = .success([OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: now)])
        await store.restore()

        XCTAssertEqual(storeKit.syncCallCount, 1)
        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
        XCTAssertFalse(store.isRestoring)
    }

    @MainActor
    func testRestoreFailureDoesNotClaimTheUserHasNotPaid() async {
        let storeKit = FakeStoreKitClient()
        storeKit.syncError = FakeError()
        let appTransaction = FakeAppTransactionClient()
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.restore()

        XCTAssertEqual(store.statusMessage?.contains("couldn't reach the App Store"), true)
        XCTAssertEqual(store.state, .loading, "A failed restore must not resolve the entitlement at all")
    }

    /// Restore is not a repair path for someone who never bought the unlock.
    /// The copy has to say so plainly or people loop on it forever.
    @MainActor
    func testRestoreWithNoPurchaseSaysSoPlainly() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.restore()

        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(store.statusMessage?.contains("No previous purchase was found"), true)
    }

    /// A transient lookup failure is not evidence the customer never paid, so
    /// restore must not hand them a false account diagnosis.
    @MainActor
    func testRestoreWithUnavailableVerificationDoesNotClaimNoPurchase() async {
        let storeKit = FakeStoreKitClient()
        storeKit.ownedResult = .failure(.unavailable)
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .failure(.unavailable)
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.restore()

        XCTAssertEqual(store.state, .verificationUnavailable)
        let message = try? XCTUnwrap(store.statusMessage)
        XCTAssertEqual(message?.contains("No previous purchase"), false)
        XCTAssertEqual(message?.contains("couldn't reach the App Store"), true)
    }

    @MainActor
    func testRestoreWithUnverifiedResponseDoesNotClaimNoPurchase() async {
        let storeKit = FakeStoreKitClient()
        storeKit.ownedResult = .failure(.unverified)
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .failure(.unverified)
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.restore()

        XCTAssertEqual(store.state, .unverified)
        XCTAssertEqual(store.statusMessage?.contains("No previous purchase"), false)
    }

    // MARK: Concurrency

    /// Two refreshes overlap routinely — `purchase()` refreshes while the update
    /// observer refreshes for the same transaction. The older one must not
    /// resume last and clobber the newer answer.
    @MainActor
    func testStaleRefreshDoesNotOverwriteNewerResult() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        storeKit.ownedResult = .success([])
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        let purchaseDate = now
        storeKit.whileOwnedProductsSuspended = { [weak store, weak storeKit] in
            guard let store, let storeKit else { return }
            // Only interleave once, or this recurses forever.
            storeKit.whileOwnedProductsSuspended = nil
            storeKit.ownedResult = .success(
                [OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: purchaseDate)]
            )
            await store.refresh()
        }

        // The outer refresh captured the locked snapshot, then suspended while a
        // newer refresh resolved to unlocked. The newer answer must survive.
        await store.refresh()

        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
    }

    /// The ledger key stays account-scoped even without `appTransactionID`,
    /// which the current build SDK does not expose.
    @MainActor
    func testLedgerKeyFallsBackToPurchaseInstant() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(
            AppTransactionInfo(
                originalPurchaseDate: cutover.addingTimeInterval(-5000),
                originalAppVersion: "1.2",
                appTransactionID: nil
            )
        )
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.refresh()

        XCTAssertEqual(store.ledgerAccountKey, "purchased-at-\(Int(cutover.addingTimeInterval(-5000).timeIntervalSince1970))")
    }

    // MARK: Product metadata

    @MainActor
    func testLoadProductUsesApplesLocalizedPrice() async {
        let storeKit = FakeStoreKitClient()
        storeKit.productResult = StoreProductInfo(
            productID: ChronoframeUnlock.productID,
            displayName: "Chronoframe Unlock",
            displayPrice: "£14.99"
        )
        let store = makeStore(storeKit: storeKit, appTransaction: FakeAppTransactionClient())

        await store.loadProduct()

        XCTAssertEqual(store.product?.displayPrice, "£14.99")
    }

    @MainActor
    func testLoadProductToleratesFailure() async {
        let store = makeStore(storeKit: FakeStoreKitClient(), appTransaction: FakeAppTransactionClient())
        await store.loadProduct()
        XCTAssertNil(store.product)
    }

    // MARK: Updates

    /// Refunds and Family Sharing revocations reach us as the product simply
    /// vanishing from `currentEntitlements`, so a re-read must withdraw access.
    /// (The delivery mechanism — `Transaction.updates` — is covered by the
    /// live client, which no unit test can reach.)
    @MainActor
    func testRefreshWithdrawsRevokedAccess() async {
        let storeKit = FakeStoreKitClient()
        storeKit.ownedResult = .success([OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: now)])
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        await store.refresh()
        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))

        // Simulate the refund landing, then a delivered update.
        storeKit.ownedResult = .success([])
        await store.refresh()

        XCTAssertEqual(store.state, .locked)
    }

    @MainActor
    func testStopObservingUpdatesIsIdempotent() {
        let store = makeStore(storeKit: FakeStoreKitClient(), appTransaction: FakeAppTransactionClient())
        store.startObservingUpdates()
        store.stopObservingUpdates()
        store.stopObservingUpdates()
    }

    // MARK: Status message lifecycle

    /// Reopening the unlock sheet (or the License pane) must not greet the
    /// customer with a failure from an earlier attempt before they have done
    /// anything. The surfaces call this on appear.
    @MainActor
    func testDismissStatusMessageClearsALeftoverFailure() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .failed(diagnostic: "boom")
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        await store.purchase()
        XCTAssertNotNil(store.statusMessage, "Precondition: the failed attempt said so")

        store.dismissStatusMessage()

        XCTAssertNil(store.statusMessage)
        XCTAssertEqual(store.state, .locked, "Dismissing a message changes nothing else")
    }

    /// Negative: a sheet appearing while a purchase is still running must not
    /// swallow what that purchase goes on to say.
    @MainActor
    func testDismissingMidPurchaseDoesNotSwallowThePurchaseOutcome() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .unverified
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        let gate = Gate()
        storeKit.whilePurchaseSuspended = { await gate.wait() }
        let purchase = Task { await store.purchase() }
        await eventually("purchase in flight") { store.isPurchasing }

        store.dismissStatusMessage()
        gate.open()
        await purchase.value

        XCTAssertEqual(store.statusMessage?.contains("Don't buy again"), true, store.statusMessage ?? "nil")
    }

    /// The Ask to Buy note and the "verification failed, don't buy again"
    /// warning describe something still outstanding — an approval that has not
    /// arrived, or a charge the App Store already took. The unlock sheet has no
    /// other place to say so, so re-presenting it or opening Settings must not
    /// wipe them and leave a bare Buy button.
    @MainActor
    func testDismissKeepsAnUnverifiedPurchaseWarning() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .unverified
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        await store.purchase()

        store.dismissStatusMessage()

        XCTAssertEqual(store.statusMessage?.contains("Don't buy again"), true, store.statusMessage ?? "nil")
    }

    @MainActor
    func testDismissKeepsThePendingApprovalNote() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .pending
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        await store.purchase()

        store.dismissStatusMessage()

        XCTAssertNotNil(store.statusMessage, "An approval still outstanding must stay visible")
    }

    /// The outstanding note is still cleared by the customer's next attempt,
    /// and dismissing does not make a later failure sticky.
    @MainActor
    func testNextAttemptStillReplacesAnOutstandingNote() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .unverified
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        await store.purchase()

        storeKit.purchaseResult = .failed(diagnostic: "boom")
        await store.purchase()
        store.dismissStatusMessage()

        XCTAssertNil(store.statusMessage, "A plain failure is not outstanding; dismissal clears it")
    }

    /// restore() must apply the same rule as purchase(): an outcome that lost
    /// its race with an unrelated unlock is not shown beside "Unlocked".
    @MainActor
    func testRestoreLockedOutcomeDoesNotOverwriteAConcurrentUnlock() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        var hasInterleaved = false
        storeKit.whileOwnedProductsSuspended = { [weak storeKit, weak store] in
            guard !hasInterleaved, let storeKit, let store else { return }
            hasInterleaved = true
            // Restore's own read already captured "nothing owned"; an approval
            // then lands through an unrelated refresh and unlocks the store.
            storeKit.ownedResult = .success([
                OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: Date())
            ])
            await store.refresh()
        }

        await store.restore()

        XCTAssertTrue(store.state.isUnlocked, "Precondition: the concurrent refresh unlocked it")
        XCTAssertNil(
            store.statusMessage,
            "No previous purchase was found is untrue beside Unlocked: \(store.statusMessage ?? "nil")"
        )
    }

    @MainActor
    func testRestoreSyncFailureDoesNotOverwriteAConcurrentUnlock() async {
        let storeKit = FakeStoreKitClient()
        storeKit.syncError = FakeError()
        let appTransaction = FakeAppTransactionClient()
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)

        storeKit.whileSyncSuspended = { [weak storeKit, weak store] in
            guard let storeKit, let store else { return }
            storeKit.ownedResult = .success([
                OwnedProduct(productID: ChronoframeUnlock.productID, purchaseDate: Date())
            ])
            await store.refresh()
        }

        await store.restore()

        XCTAssertTrue(store.state.isUnlocked, "Precondition: the concurrent refresh unlocked it")
        XCTAssertNil(store.statusMessage, store.statusMessage ?? "nil")
    }

    /// However the unlock arrives — here an Ask to Buy approval delivered
    /// through `Transaction.updates` after `purchase()` returned `.pending` —
    /// the "needs approval" note must not sit beside an unlocked entitlement.
    @MainActor
    func testUnlockArrivingThroughAnUpdateClearsThePendingMessage() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .pending
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        await store.purchase()
        XCTAssertNotNil(store.statusMessage, "Precondition: pending explains itself")

        store.startObservingUpdates()
        defer { store.stopObservingUpdates() }
        await eventually("the observer subscribed") { storeKit.isObservingUpdates }
        storeKit.ownedResult = ownedUnlock()
        storeKit.emitTransactionUpdate()

        await eventually("the approval unlocks") { store.state.isUnlocked }
        XCTAssertNil(store.statusMessage)
    }

    /// The same for an unlock reached by a retry once the network came back,
    /// after an offline restore had reported that it couldn't reach the store.
    @MainActor
    func testUnlockReachedByARetryClearsAnEarlierRestoreFailure() async {
        let storeKit = FakeStoreKitClient()
        storeKit.syncError = FakeError()
        let clock = TestClock(now)
        let store = makeStore(storeKit: storeKit, appTransaction: FakeAppTransactionClient(), clock: clock)
        await store.refresh()
        await store.restore()
        XCTAssertNotNil(store.statusMessage, "Precondition: the offline restore said so")

        storeKit.ownedResult = ownedUnlock()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)
        await store.resolveIfNeeded()

        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
        XCTAssertNil(store.statusMessage)
    }

    /// Negative: a refresh that does NOT unlock leaves the message alone. The
    /// pending note is still true until the approval actually lands.
    @MainActor
    func testRefreshThatDoesNotUnlockKeepsThePendingMessage() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .pending
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()
        await store.purchase()
        let pending = store.statusMessage
        XCTAssertNotNil(pending)

        await store.refresh()

        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(store.statusMessage, pending)
    }

    // MARK: Purchase and restore never overlap

    /// A Restore tapped in Settings while the sheet's purchase is running must
    /// not wipe or overwrite what the purchase is about to say — above all the
    /// "don't buy again" warning.
    @MainActor
    func testRestoreIsRefusedWhileAPurchaseIsInFlight() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .unverified
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        let gate = Gate()
        storeKit.whilePurchaseSuspended = { await gate.wait() }
        let purchase = Task { await store.purchase() }
        await eventually("purchase in flight") { store.isPurchasing }

        await store.restore()

        XCTAssertEqual(storeKit.syncCallCount, 0, "The overlapping restore must not run")
        XCTAssertFalse(store.isRestoring)

        gate.open()
        await purchase.value
        XCTAssertEqual(store.statusMessage?.contains("Don't buy again"), true, store.statusMessage ?? "nil")
    }

    /// The mirror image: a purchase while a restore is running is refused, and
    /// the restore's own outcome is what the customer reads.
    @MainActor
    func testPurchaseIsRefusedWhileARestoreIsInFlight() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .failed(diagnostic: "boom")
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        let gate = Gate()
        storeKit.whileSyncSuspended = { await gate.wait() }
        let restore = Task { await store.restore() }
        await eventually("restore in flight") { store.isRestoring }

        await store.purchase()

        XCTAssertEqual(storeKit.purchaseCallCount, 0, "The overlapping purchase must not run")
        XCTAssertFalse(store.isPurchasing)

        gate.open()
        await restore.value
        XCTAssertEqual(store.statusMessage?.contains("No previous purchase was found"), true, store.statusMessage ?? "nil")
    }

    /// Negative: the exclusion is only while one is running. Once it finishes
    /// the other goes ahead normally.
    @MainActor
    func testRestoreRunsNormallyOnceThePurchaseHasFinished() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .userCancelled
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()
        await store.restore()
        await store.purchase()

        XCTAssertEqual(storeKit.purchaseCallCount, 2)
        XCTAssertEqual(storeKit.syncCallCount, 1)
    }

    // MARK: Resolution on demand

    /// Two gates racing on a cold store share one resolution, and both see its
    /// answer — the loser of a raw refresh race would otherwise read `.loading`.
    @MainActor
    func testConcurrentColdCallersShareOneResolution() async {
        let storeKit = FakeStoreKitClient()
        storeKit.ownedResult = ownedUnlock()
        let gate = Gate()
        storeKit.whileOwnedProductsSuspended = { await gate.wait() }
        let store = makeStore(storeKit: storeKit, appTransaction: FakeAppTransactionClient())

        let first = Task { await store.resolveIfNeeded(); return store.state }
        let second = Task { await store.resolveIfNeeded(); return store.state }
        await eventually("one resolution started") { storeKit.ownedCallCount == 1 }
        await settle()
        gate.open()

        let firstState = await first.value
        let secondState = await second.value
        XCTAssertEqual(storeKit.ownedCallCount, 1)
        XCTAssertEqual(firstState, .unlocked(reason: .inAppPurchase))
        XCTAssertEqual(secondState, .unlocked(reason: .inAppPurchase))
    }

    /// Negative: a cold store is waited on however long StoreKit takes — the
    /// bounded wait is for callers that already hold an answer. Returning early
    /// here would hand a gate `.loading` and paywall someone who paid.
    @MainActor
    func testColdCallerWaitsForTheAnswerPastTheWaitLimit() async {
        let storeKit = FakeStoreKitClient()
        storeKit.ownedResult = ownedUnlock()
        let gate = Gate()
        storeKit.whileOwnedProductsSuspended = { await gate.wait() }
        // A wait limit that has already elapsed the moment anyone asks.
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            unconfirmedWaitLimit: 0,
            sleep: { _ in }
        )

        let finished = Flag()
        let caller = Task { await store.resolveIfNeeded(); finished.value = true }
        await eventually("resolution started") { storeKit.ownedCallCount == 1 }
        await settle()
        XCTAssertFalse(finished.value, "A cold caller must not give up on the answer")

        gate.open()
        await caller.value
        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
    }

    /// Offline, a gate that already holds an unconfirmed answer must not sit
    /// on StoreKit's own timeout: it waits on the retry for at most the limit,
    /// then goes ahead with the answer it had. The retry keeps running and its
    /// answer lands for the next caller.
    @MainActor
    func testUnconfirmedCallerDoesNotWaitOutASlowRetry() async {
        let storeKit = FakeStoreKitClient()
        let clock = TestClock(now)
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            clock: clock,
            unconfirmedWaitLimit: 0,
            sleep: { _ in }
        )
        await store.refresh()
        XCTAssertEqual(store.state, .verificationUnavailable)

        let gate = Gate()
        storeKit.whileOwnedProductsSuspended = { await gate.wait() }
        storeKit.ownedResult = ownedUnlock()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)

        // Driven from a task and polled, so a regression FAILS here rather than
        // hanging the suite on a gate nothing would open.
        let returned = Flag()
        let caller = Task { await store.resolveIfNeeded(); returned.value = true }
        await eventually("the caller went ahead without the retry's answer") { returned.value }

        XCTAssertEqual(storeKit.ownedCallCount, 2, "The retry was started")
        XCTAssertEqual(store.state, .verificationUnavailable, "…and not waited out")

        gate.open()
        await caller.value
        await eventually("the retry lands for the next caller") { store.state.isUnlocked }
    }

    /// Negative: a retry that answers inside the limit IS returned to the
    /// caller that started it — a network that came back unlocks this run, not
    /// the next one.
    @MainActor
    func testRetryAnsweringInsideTheLimitIsReturnedToItsCaller() async {
        let storeKit = FakeStoreKitClient()
        let clock = TestClock(now)
        // The real sleep with a long limit, so only the answer can end the wait.
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            clock: clock,
            unconfirmedWaitLimit: 60
        )
        await store.refresh()

        storeKit.ownedResult = ownedUnlock()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)
        await store.resolveIfNeeded()

        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
    }

    /// A caller arriving behind a retry joins it even though the retry's own
    /// attempt stamp puts it inside the throttle window — the throttle spaces
    /// out new attempts, it never hands back a stale answer beside a fresh one.
    @MainActor
    func testCallerBehindARetryJoinsItDespiteTheThrottle() async {
        let storeKit = FakeStoreKitClient()
        let clock = TestClock(now)
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            clock: clock,
            unconfirmedWaitLimit: 60
        )
        await store.refresh()

        let gate = Gate()
        storeKit.whileOwnedProductsSuspended = { await gate.wait() }
        storeKit.ownedResult = ownedUnlock()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)

        let first = Task { await store.resolveIfNeeded(); return store.state }
        await eventually("retry started") { storeKit.ownedCallCount == 2 }
        let second = Task { await store.resolveIfNeeded(); return store.state }
        await settle()
        gate.open()

        let firstState = await first.value
        let secondState = await second.value
        XCTAssertEqual(storeKit.ownedCallCount, 2, "Joined, not restarted")
        XCTAssertEqual(firstState, .unlocked(reason: .inAppPurchase))
        XCTAssertEqual(secondState, .unlocked(reason: .inAppPurchase))
    }

    // MARK: Retry throttle counts every App Store attempt

    /// A refresh from anywhere — purchase, restore, the update observer —
    /// counts toward the throttle, not only ones started by a gate.
    @MainActor
    func testAnyRefreshCountsTowardTheThrottle() async {
        let storeKit = FakeStoreKitClient()
        let store = makeStore(storeKit: storeKit, appTransaction: FakeAppTransactionClient())
        await store.refresh()
        XCTAssertEqual(store.state, .verificationUnavailable)

        await store.resolveIfNeeded()

        XCTAssertEqual(storeKit.ownedCallCount, 1, "A second failing round-trip right behind the first")
    }

    /// An offline restore fails at `sync()` before it ever refreshes. That is
    /// still an App Store round-trip, so the License pane's follow-up read must
    /// not immediately repeat it.
    @MainActor
    func testFailedRestoreSyncCountsTowardTheThrottle() async {
        let storeKit = FakeStoreKitClient()
        storeKit.syncError = FakeError()
        let clock = TestClock(now)
        let store = makeStore(storeKit: storeKit, appTransaction: FakeAppTransactionClient(), clock: clock)
        await store.refresh()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)

        await store.restore()
        await store.resolveIfNeeded()

        XCTAssertEqual(storeKit.ownedCallCount, 1)
    }

    /// Negative: the throttle is a spacing, not a lockout. Once the interval
    /// has passed, the next caller retries — and a network that came back
    /// unlocks a customer who launched offline, without a relaunch.
    @MainActor
    func testRetryHappensOnceTheIntervalHasPassed() async {
        let storeKit = FakeStoreKitClient()
        let clock = TestClock(now)
        let store = makeStore(storeKit: storeKit, appTransaction: FakeAppTransactionClient(), clock: clock)
        await store.refresh()

        storeKit.ownedResult = ownedUnlock()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)
        await store.resolveIfNeeded()

        XCTAssertEqual(storeKit.ownedCallCount, 2)
        XCTAssertEqual(store.state, .unlocked(reason: .inAppPurchase))
    }

    /// Negative: a settled answer is never re-asked on demand, however long
    /// ago it was reached. Revocation arrives through `Transaction.updates`.
    @MainActor
    func testSettledAnswerIsNotReaskedOnDemand() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let clock = TestClock(now)
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction, clock: clock)
        await store.refresh()
        XCTAssertEqual(store.state, .locked)

        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval * 100)
        await store.resolveIfNeeded()

        XCTAssertEqual(storeKit.ownedCallCount, 1)
    }

    // MARK: Background re-check while unconfirmed

    /// Nothing else asks while the customer only browses, so a paying customer
    /// who launched offline would keep seeing a metered allowance after the
    /// network came back. The store re-checks on its own until it settles.
    @MainActor
    func testUnconfirmedAnswerRechecksInTheBackgroundUntilItSettles() async {
        let storeKit = FakeStoreKitClient()
        let clock = TestClock(now)
        let sleeper = ManualSleeper()
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            clock: clock,
            sleep: { await sleeper.sleep($0) }
        )
        store.startObservingUpdates()
        defer { store.stopObservingUpdates() }

        await store.refresh()
        XCTAssertEqual(store.state, .verificationUnavailable)
        await eventually("a re-check is scheduled") { sleeper.pendingCount == 1 }
        XCTAssertEqual(sleeper.requestedDurations.last, EntitlementRetryPolicy.unconfirmedRetryInterval)

        // Still offline: it re-checks, stays unconfirmed, and schedules again.
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)
        sleeper.wakeAll()
        await eventually("second attempt") { storeKit.ownedCallCount == 2 }
        await eventually("the next re-check is scheduled") { sleeper.pendingCount == 1 }

        // The network comes back.
        storeKit.ownedResult = ownedUnlock()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)
        sleeper.wakeAll()
        await eventually("unlocked in the background") { store.state.isUnlocked }

        // Settled: the chain stops.
        await settle()
        XCTAssertEqual(sleeper.pendingCount, 0)
        XCTAssertEqual(storeKit.ownedCallCount, 3)
    }

    /// A re-check that wakes inside the throttle window (a gate asked moments
    /// ago) makes no call — but must not end the chain, or an offline Mac would
    /// stop re-checking for good.
    @MainActor
    func testThrottledBackgroundRecheckKeepsTheChainAlive() async {
        let storeKit = FakeStoreKitClient()
        let sleeper = ManualSleeper()
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            sleep: { await sleeper.sleep($0) }
        )
        store.startObservingUpdates()
        defer { store.stopObservingUpdates() }
        await store.refresh()
        await eventually("a re-check is scheduled") { sleeper.pendingCount == 1 }

        // The clock never moves, so the throttle declines.
        sleeper.wakeAll()
        await eventually("rescheduled") { sleeper.requestedDurations.count == 2 && sleeper.pendingCount == 1 }
        XCTAssertEqual(storeKit.ownedCallCount, 1, "Throttled: no App Store call")
    }

    /// Negative: launch stays StoreKit-free. Arming the observer resolves
    /// nothing and schedules nothing until something has actually asked.
    @MainActor
    func testStartingObservationAtLaunchResolvesNothing() async {
        let storeKit = FakeStoreKitClient()
        let sleeper = ManualSleeper()
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            sleep: { await sleeper.sleep($0) }
        )

        store.startObservingUpdates()
        defer { store.stopObservingUpdates() }
        await settle()

        XCTAssertEqual(store.state, .loading)
        XCTAssertEqual(storeKit.ownedCallCount, 0)
        XCTAssertEqual(sleeper.pendingCount, 0)
    }

    /// Negative: a settled answer schedules no background re-check.
    @MainActor
    func testSettledAnswerSchedulesNoBackgroundRecheck() async {
        let storeKit = FakeStoreKitClient()
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let sleeper = ManualSleeper()
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction, sleep: { await sleeper.sleep($0) })
        store.startObservingUpdates()
        defer { store.stopObservingUpdates() }

        await store.refresh()
        await settle()

        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(sleeper.pendingCount, 0)
    }

    /// Negative: without the observer (tests, the CLI) an unconfirmed answer
    /// schedules nothing in the background.
    @MainActor
    func testNoBackgroundRecheckWithoutObservation() async {
        let sleeper = ManualSleeper()
        let store = makeStore(
            storeKit: FakeStoreKitClient(),
            appTransaction: FakeAppTransactionClient(),
            sleep: { await sleeper.sleep($0) }
        )

        await store.refresh()
        await settle()

        XCTAssertEqual(store.state, .verificationUnavailable)
        XCTAssertEqual(sleeper.pendingCount, 0)
    }

    /// Stopping observation cancels a scheduled re-check: when its sleep ends
    /// it must not call the App Store.
    @MainActor
    func testStopObservingCancelsTheBackgroundRecheck() async {
        let storeKit = FakeStoreKitClient()
        let clock = TestClock(now)
        let sleeper = ManualSleeper()
        let store = makeStore(
            storeKit: storeKit,
            appTransaction: FakeAppTransactionClient(),
            clock: clock,
            sleep: { await sleeper.sleep($0) }
        )
        store.startObservingUpdates()
        await store.refresh()
        await eventually("a re-check is scheduled") { sleeper.pendingCount == 1 }

        store.stopObservingUpdates()
        clock.advance(by: EntitlementRetryPolicy.unconfirmedRetryInterval)
        sleeper.wakeAll()
        await settle()

        XCTAssertEqual(storeKit.ownedCallCount, 1)
        XCTAssertEqual(sleeper.pendingCount, 0)
    }

    // MARK: Unrestricted channel

    /// The CLI and Developer ID builds run unrestricted by explicit choice.
    @MainActor
    func testUnrestrictedClientResolvesUnlocked() async {
        let clockValue = now
        let store = EntitlementStore(
            storeKit: FakeStoreKitClient(),
            appTransactionClient: UnrestrictedAppTransactionClient(),
            policy: GrandfatherPolicy(cutover: cutover),
            unlockProductID: ChronoframeUnlock.productID,
            defaults: defaults,
            clock: { clockValue }
        )

        await store.refresh()

        XCTAssertEqual(store.state, .unlocked(reason: .legacyPurchase))
    }
}
