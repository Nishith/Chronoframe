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

    func product(for productID: String) async -> StoreProductInfo? { productResult }

    func ownedProducts() async -> Result<[OwnedProduct], EntitlementLookupFailure> {
        ownedCallCount += 1
        return ownedResult
    }

    func purchase(productID: String) async -> PurchaseOutcome {
        purchaseCallCount += 1
        return purchaseResult
    }

    func sync() async throws {
        syncCallCount += 1
        if let syncError { throw syncError }
    }

    func transactionUpdates() -> AsyncStream<Void> {
        AsyncStream { continuation in
            self.updatesContinuation = continuation
        }
    }

    func emitTransactionUpdate() {
        updatesContinuation?.yield(())
    }
}

private final class FakeAppTransactionClient: AppTransactionClient, @unchecked Sendable {
    var result: Result<AppTransactionInfo, EntitlementLookupFailure> = .failure(.unavailable)

    func appTransaction() async -> Result<AppTransactionInfo, EntitlementLookupFailure> { result }
}

private struct FakeError: Error {}

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
        maximumCacheAge: TimeInterval = GrandfatherPolicy.defaultMaximumCacheAge
    ) -> EntitlementStore {
        let clockValue = now
        return EntitlementStore(
            storeKit: storeKit,
            appTransactionClient: appTransaction,
            policy: GrandfatherPolicy(cutover: cutover, maximumCacheAge: maximumCacheAge),
            unlockProductID: ChronoframeUnlock.productID,
            defaults: defaults,
            clock: { clockValue }
        )
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

    @MainActor
    func testUnverifiedPurchaseReassuresThatNothingWasCharged() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .unverified
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()

        XCTAssertEqual(store.state, .locked)
        XCTAssertEqual(store.statusMessage?.contains("Nothing was charged"), true)
    }

    @MainActor
    func testFailedPurchaseSurfacesItsMessage() async {
        let storeKit = FakeStoreKitClient()
        storeKit.purchaseResult = .failed(message: "The unlock could not be loaded from the App Store.")
        let appTransaction = FakeAppTransactionClient()
        appTransaction.result = .success(newInfo())
        let store = makeStore(storeKit: storeKit, appTransaction: appTransaction)
        await store.refresh()

        await store.purchase()

        XCTAssertEqual(store.statusMessage, "The unlock could not be loaded from the App Store.")
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
