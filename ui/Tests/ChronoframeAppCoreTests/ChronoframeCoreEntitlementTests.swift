import Foundation
import XCTest
@testable import ChronoframeCore

/// Covers the paid-to-free migration rule and entitlement resolution.
///
/// These tests carry the weight for the whole feature: none of the live
/// StoreKit code can be unit-tested, so the policy is deliberately pure and
/// every branch of it is pinned here.
final class ChronoframeCoreEntitlementTests: XCTestCase {
    private let unlockID = "com.nishith.chronoframe.unlock"
    private let cutover = Date(timeIntervalSince1970: 1_800_000_000) // 2027-01-15T08:00:00Z
    private let now = Date(timeIntervalSince1970: 1_800_100_000)

    private func policy(maximumCacheAge: TimeInterval = GrandfatherPolicy.defaultMaximumCacheAge) -> GrandfatherPolicy {
        GrandfatherPolicy(cutover: cutover, maximumCacheAge: maximumCacheAge)
    }

    private func appTransaction(
        purchasedAt offset: TimeInterval,
        revokedAt: Date? = nil,
        id: String? = "app-txn-1"
    ) -> AppTransactionInfo {
        AppTransactionInfo(
            originalPurchaseDate: cutover.addingTimeInterval(offset),
            originalAppVersion: "1.2",
            appTransactionID: id,
            revocationDate: revokedAt
        )
    }

    private func resolve(
        owned: Result<[OwnedProduct], EntitlementLookupFailure>,
        appTransaction: Result<AppTransactionInfo, EntitlementLookupFailure>,
        cached: CachedLegacyGrant? = nil,
        policy overridePolicy: GrandfatherPolicy? = nil
    ) -> EntitlementState {
        EntitlementResolver.resolve(
            ownedProducts: owned,
            appTransaction: appTransaction,
            cachedLegacyGrant: cached,
            unlockProductID: unlockID,
            policy: overridePolicy ?? policy(),
            now: now
        )
    }

    private var ownedUnlock: Result<[OwnedProduct], EntitlementLookupFailure> {
        .success([OwnedProduct(productID: unlockID, purchaseDate: now)])
    }

    // MARK: Purchased the unlock

    func testOwningTheUnlockResolvesToInAppPurchase() {
        let state = resolve(owned: ownedUnlock, appTransaction: .success(appTransaction(purchasedAt: 60)))
        XCTAssertEqual(state, .unlocked(reason: .inAppPurchase))
    }

    /// A customer who bought the IAP must stay unlocked even when the app
    /// transaction lookup is failing, which is the ordinary offline case.
    func testOwningTheUnlockWinsOverAppTransactionFailure() {
        XCTAssertEqual(resolve(owned: ownedUnlock, appTransaction: .failure(.unavailable)), .unlocked(reason: .inAppPurchase))
        XCTAssertEqual(resolve(owned: ownedUnlock, appTransaction: .failure(.unverified)), .unlocked(reason: .inAppPurchase))
    }

    func testUnrelatedProductDoesNotUnlock() {
        let owned = Result<[OwnedProduct], EntitlementLookupFailure>.success(
            [OwnedProduct(productID: "com.nishith.chronoframe.somethingelse", purchaseDate: now)]
        )
        XCTAssertEqual(resolve(owned: owned, appTransaction: .success(appTransaction(purchasedAt: 60))), .locked)
    }

    // MARK: Grandfathering

    func testPurchaseBeforeCutoverIsGrandfathered() {
        let state = resolve(owned: .success([]), appTransaction: .success(appTransaction(purchasedAt: -1)))
        XCTAssertEqual(state, .unlocked(reason: .legacyPurchase))
    }

    func testDownloadAfterCutoverIsLocked() {
        let state = resolve(owned: .success([]), appTransaction: .success(appTransaction(purchasedAt: 1)))
        XCTAssertEqual(state, .locked)
    }

    /// The boundary is exclusive: an acquisition exactly at the cutover instant
    /// is the moment the app became free, so it does not grandfather.
    func testCutoverBoundaryIsExclusive() {
        let state = resolve(owned: .success([]), appTransaction: .success(appTransaction(purchasedAt: 0)))
        XCTAssertEqual(state, .locked)
    }

    func testRevokedAppTransactionDoesNotGrandfather() {
        let revoked = appTransaction(purchasedAt: -5000, revokedAt: now.addingTimeInterval(-1))
        XCTAssertEqual(resolve(owned: .success([]), appTransaction: .success(revoked)), .locked)
    }

    /// A revocation dated in the future has not taken effect yet.
    func testFutureRevocationStillGrandfathers() {
        let revoked = appTransaction(purchasedAt: -5000, revokedAt: now.addingTimeInterval(60))
        XCTAssertEqual(resolve(owned: .success([]), appTransaction: .success(revoked)), .unlocked(reason: .legacyPurchase))
    }

    /// Until the price actually drops, every customer is a paying customer, so
    /// the shipped default must grandfather everyone. This is what makes the
    /// unedited constant safe to release.
    func testDefaultPolicyGrandfathersEveryoneBeforeTheCutoverIsSet() {
        let state = EntitlementResolver.resolve(
            ownedProducts: .success([]),
            appTransaction: .success(
                AppTransactionInfo(originalPurchaseDate: now, originalAppVersion: "2.0", appTransactionID: nil)
            ),
            cachedLegacyGrant: nil,
            unlockProductID: ChronoframeUnlock.productID,
            policy: ChronoframeUnlock.defaultPolicy(),
            now: now
        )
        XCTAssertEqual(state, .unlocked(reason: .legacyPurchase))
    }

    // MARK: Verification failures must not read as "did not pay"

    func testAppTransactionUnavailableWithoutCacheIsNotLocked() {
        let state = resolve(owned: .success([]), appTransaction: .failure(.unavailable))
        XCTAssertEqual(state, .verificationUnavailable)
        XCTAssertNotEqual(state, .locked)
    }

    func testUnverifiedAppTransactionIsReportedDistinctly() {
        XCTAssertEqual(resolve(owned: .success([]), appTransaction: .failure(.unverified)), .unverified)
    }

    /// A verified app transaction proves they are not a legacy purchaser, but a
    /// failed entitlement read leaves open that they own the unlock. Reporting
    /// `.locked` here would paywall a paying customer.
    func testVerifiedNonLegacyWithFailedEntitlementLookupIsNotLocked() {
        let appTx = Result<AppTransactionInfo, EntitlementLookupFailure>.success(appTransaction(purchasedAt: 60))
        XCTAssertEqual(resolve(owned: .failure(.unavailable), appTransaction: appTx), .verificationUnavailable)
        XCTAssertEqual(resolve(owned: .failure(.unverified), appTransaction: appTx), .unverified)
    }

    /// When both sources fail, the more serious failure wins.
    func testUnverifiedOutranksUnavailable() {
        XCTAssertEqual(resolve(owned: .failure(.unverified), appTransaction: .failure(.unavailable)), .unverified)
        XCTAssertEqual(resolve(owned: .failure(.unavailable), appTransaction: .failure(.unverified)), .unverified)
    }

    // MARK: Offline cache

    func testCachedGrantKeepsOfflineLegacyCustomerUnlocked() {
        let cached = CachedLegacyGrant(
            originalPurchaseDate: cutover.addingTimeInterval(-5000),
            appTransactionID: "app-txn-1",
            recordedAt: now.addingTimeInterval(-60)
        )
        let state = resolve(owned: .failure(.unavailable), appTransaction: .failure(.unavailable), cached: cached)
        XCTAssertEqual(state, .unlocked(reason: .legacyPurchase))
    }

    func testExpiredCachedGrantIsRejected() {
        let cached = CachedLegacyGrant(
            originalPurchaseDate: cutover.addingTimeInterval(-5000),
            appTransactionID: nil,
            recordedAt: now.addingTimeInterval(-10_000)
        )
        let state = resolve(
            owned: .failure(.unavailable),
            appTransaction: .failure(.unavailable),
            cached: cached,
            policy: policy(maximumCacheAge: 5_000)
        )
        XCTAssertEqual(state, .verificationUnavailable)
    }

    /// A cache written for a post-cutover acquisition must never unlock, even
    /// if it somehow survives on disk.
    func testCachedGrantAfterCutoverIsRejected() {
        let cached = CachedLegacyGrant(
            originalPurchaseDate: cutover.addingTimeInterval(5000),
            appTransactionID: nil,
            recordedAt: now
        )
        let state = resolve(owned: .failure(.unavailable), appTransaction: .failure(.unavailable), cached: cached)
        XCTAssertEqual(state, .verificationUnavailable)
    }

    /// A clock that has jumped backwards yields a negative age. Locking someone
    /// out over an NTP correction would be absurd.
    func testCachedGrantSurvivesBackwardsClock() {
        let cached = CachedLegacyGrant(
            originalPurchaseDate: cutover.addingTimeInterval(-5000),
            appTransactionID: nil,
            recordedAt: now.addingTimeInterval(10_000)
        )
        let state = resolve(owned: .failure(.unavailable), appTransaction: .failure(.unavailable), cached: cached)
        XCTAssertEqual(state, .unlocked(reason: .legacyPurchase))
    }

    /// A verified app transaction is authoritative: it must not be overridden
    /// by a stale cache claiming legacy status.
    func testVerifiedNonLegacyBeatsStaleCache() {
        let cached = CachedLegacyGrant(
            originalPurchaseDate: cutover.addingTimeInterval(-5000),
            appTransactionID: nil,
            recordedAt: now
        )
        let state = resolve(
            owned: .success([]),
            appTransaction: .success(appTransaction(purchasedAt: 60)),
            cached: cached
        )
        XCTAssertEqual(state, .locked)
    }

    // MARK: State helpers

    func testStateHelpers() {
        XCTAssertTrue(EntitlementState.unlocked(reason: .inAppPurchase).isUnlocked)
        XCTAssertTrue(EntitlementState.unlocked(reason: .legacyPurchase).isUnlocked)
        XCTAssertFalse(EntitlementState.locked.isUnlocked)
        XCTAssertFalse(EntitlementState.verificationUnavailable.isUnlocked)
        XCTAssertFalse(EntitlementState.unverified.isUnlocked)
        XCTAssertFalse(EntitlementState.loading.isUnlocked)

        XCTAssertTrue(EntitlementState.loading.isResolving)
        XCTAssertFalse(EntitlementState.locked.isResolving)
    }

    func testCachedGrantRoundTripsThroughCoding() throws {
        let grant = CachedLegacyGrant(originalPurchaseDate: cutover, appTransactionID: "abc", recordedAt: now)
        let data = try JSONEncoder().encode(grant)
        XCTAssertEqual(try JSONDecoder().decode(CachedLegacyGrant.self, from: data), grant)
    }
}
