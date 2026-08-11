import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// A ledger that fails loudly if it is consulted at all.
///
/// Used to prove the unlocked path never touches trial bookkeeping, rather
/// than merely producing the right answer by another route.
private final class ExplodingLedger: TrialLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var _wasRead = false
    var wasRead: Bool {
        lock.lock(); defer { lock.unlock() }
        return _wasRead
    }

    func balance(accountKey: String) throws -> TrialBalance {
        lock.lock(); _wasRead = true; lock.unlock()
        throw TrialLedgerError.unreadable("the ledger must not be consulted")
    }

    func reserve(
        runID: UUID, accountKey: String, meter: TrialMeter,
        count: Int, destinationRoot: String?
    ) throws -> ReservationDecision { .permitted }
    func finalize(runID: UUID, actualCount: Int) throws {}
    func release(runID: UUID) throws {}
    func refund(
        receiptRunID: UUID, accountKey: String,
        meter: TrialMeter, itemPaths: [String]
    ) throws {}
    func openReservations() throws -> [OpenReservation] { [] }
}

/// Covers the one place entitlement and allowance are composed.
///
/// The cases that matter are the ones where composing them wrongly would say
/// something false to a paying customer.
@MainActor
final class TrialStatusStoreTests: XCTestCase {
    private let account = "app-txn-1"
    private let caps = TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 4)

    private func spentLedger(organize: Int = 0, dedupe: Int = 0) throws -> InMemoryTrialLedger {
        let ledger = InMemoryTrialLedger(caps: caps)
        if organize > 0 {
            let runID = UUID()
            _ = try ledger.reserve(
                runID: runID, accountKey: account, meter: .organize,
                count: organize, destinationRoot: nil
            )
            try ledger.finalize(runID: runID, actualCount: organize)
        }
        if dedupe > 0 {
            let runID = UUID()
            _ = try ledger.reserve(
                runID: runID, accountKey: account, meter: .dedupe,
                count: dedupe, destinationRoot: nil
            )
            try ledger.finalize(runID: runID, actualCount: dedupe)
        }
        return ledger
    }

    func testStartsLoadingWithNoBalance() {
        let store = TrialStatusStore(ledger: InMemoryTrialLedger(caps: caps))
        XCTAssertEqual(store.status, .loading)
        XCTAssertNil(store.status.balance)
        XCTAssertNil(store.status.remaining(for: .organize))
        XCTAssertFalse(store.status.isUnlocked)
    }

    func testLockedCustomerSeesTheRemainingAllowance() throws {
        let store = TrialStatusStore(ledger: try spentLedger(organize: 4, dedupe: 1))

        store.refresh(entitlement: .locked, accountKey: account)

        XCTAssertEqual(store.status.remaining(for: .organize), 6)
        XCTAssertEqual(store.status.remaining(for: .dedupe), 3)
        XCTAssertFalse(store.status.isUnlocked)
        XCTAssertFalse(store.status.describesASpentTrial)
    }

    /// An unlocked customer must never depend on trial bookkeeping — not for
    /// correctness, and not for whether the app works at all.
    func testUnlockedShortCircuitsAndNeverReadsTheLedger() {
        let ledger = ExplodingLedger()
        let store = TrialStatusStore(ledger: ledger)

        store.refresh(entitlement: .unlocked(reason: .inAppPurchase), accountKey: account)

        XCTAssertFalse(ledger.wasRead, "An unlocked customer must not cause a ledger read")
        XCTAssertTrue(store.status.isUnlocked)
        XCTAssertNil(store.status.balance)
        XCTAssertNil(store.status.remaining(for: .organize), "Unlimited is nil, never a sentinel number")
        XCTAssertFalse(store.status.describesASpentTrial)
    }

    func testLegacyPurchaseIsAlsoUnlocked() throws {
        let store = TrialStatusStore(ledger: try spentLedger(organize: 10, dedupe: 4))

        store.refresh(entitlement: .unlocked(reason: .legacyPurchase), accountKey: account)

        XCTAssertTrue(store.status.isUnlocked)
        XCTAssertNil(store.status.balance)
        XCTAssertFalse(
            store.status.describesASpentTrial,
            "A grandfathered customer with a spent ledger is not out of anything"
        )
    }

    /// Reporting a balance mid-launch would flash a trial state at a customer
    /// who has in fact paid.
    func testLoadingReportsNoBalanceEvenWithAnAccountKey() throws {
        let store = TrialStatusStore(ledger: try spentLedger(organize: 4))

        store.refresh(entitlement: .loading, accountKey: account)

        XCTAssertEqual(store.status.allowance, .unknown)
        XCTAssertFalse(store.status.describesASpentTrial)
    }

    func testMissingAccountKeyReportsNoBalance() throws {
        let store = TrialStatusStore(ledger: try spentLedger(organize: 4))

        store.refresh(entitlement: .locked, accountKey: nil)

        XCTAssertNil(store.status.balance, "Better nothing than another account's balance")
    }

    /// The distinction the whole type exists to protect: these states are
    /// metered like the trial, but must never be described as a spent one.
    func testUnverifiableStatesAreMeteredButNeverCalledASpentTrial() throws {
        for entitlement in [EntitlementState.verificationUnavailable, .unverified] {
            let store = TrialStatusStore(ledger: try spentLedger(organize: 10, dedupe: 4))

            store.refresh(entitlement: entitlement, accountKey: account)

            XCTAssertEqual(store.status.remaining(for: .organize), 0, "\(entitlement) still meters")
            XCTAssertFalse(
                store.status.describesASpentTrial,
                "\(entitlement) must never be reported as a spent trial — the customer may have paid"
            )
        }
    }

    func testSpentTrialIsReportedOnlyWhenBothMetersAreEmptyAndTheStateIsLocked() throws {
        let partiallySpent = TrialStatusStore(ledger: try spentLedger(organize: 10, dedupe: 1))
        partiallySpent.refresh(entitlement: .locked, accountKey: account)
        XCTAssertFalse(
            partiallySpent.status.describesASpentTrial,
            "Dedupe still has room, so the trial is not spent"
        )

        let fullySpent = TrialStatusStore(ledger: try spentLedger(organize: 10, dedupe: 4))
        fullySpent.refresh(entitlement: .locked, accountKey: account)
        XCTAssertTrue(fullySpent.status.describesASpentTrial)
    }

    func testRefreshReplacesThePreviousStatus() throws {
        let store = TrialStatusStore(ledger: try spentLedger(organize: 4))

        store.refresh(entitlement: .locked, accountKey: account)
        XCTAssertEqual(store.status.remaining(for: .organize), 6)

        // Buying the unlock clears the balance rather than leaving a stale one.
        store.refresh(entitlement: .unlocked(reason: .inAppPurchase), accountKey: account)
        XCTAssertNil(store.status.balance)
    }

    /// A ledger that failed to open is NOT a spent trial.
    ///
    /// The fail-closed stand-in answers zero remaining so that gates refuse,
    /// which is right — but saying "your trial is used up" on the strength of
    /// records we could not read is a lie about the customer's own usage, and
    /// it sends them to the wrong remedy.
    func testUnreadableLedgerIsReportedAsUnavailableNotAsASpentTrial() {
        let store = TrialStatusStore(
            ledger: UnreadableTrialLedger(caps: caps),
            bookkeepingAvailable: false
        )

        store.refresh(entitlement: .locked, accountKey: account)

        XCTAssertEqual(store.status.allowance, .unavailable)
        XCTAssertTrue(store.status.bookkeepingUnavailable)
        XCTAssertFalse(
            store.status.describesASpentTrial,
            "A corrupt ledger must never be described as a consumed trial"
        )
        XCTAssertNil(store.status.remaining(for: .organize))
        XCTAssertNil(store.status.balance)
    }

    /// Even with the outcome reported as readable, a ledger that throws on read
    /// resolves to `.unavailable` rather than to a balance.
    func testALedgerThatThrowsOnReadResolvesToUnavailable() {
        let store = TrialStatusStore(ledger: ExplodingLedger())

        store.refresh(entitlement: .locked, accountKey: account)

        XCTAssertEqual(store.status.allowance, .unavailable)
        XCTAssertFalse(store.status.describesASpentTrial)
    }

    /// Unlocked still short-circuits ahead of the unreadable check, so a broken
    /// ledger cannot degrade a paid customer's status.
    func testUnlockedIsUnlimitedEvenWhenBookkeepingIsUnavailable() {
        let store = TrialStatusStore(
            ledger: UnreadableTrialLedger(caps: caps),
            bookkeepingAvailable: false
        )

        store.refresh(entitlement: .unlocked(reason: .inAppPurchase), accountKey: account)

        XCTAssertEqual(store.status.allowance, .unlimited)
        XCTAssertFalse(store.status.bookkeepingUnavailable)
    }
}
