import Foundation
import XCTest
@testable import ChronoframeCore

/// Covers when an unsettled entitlement is asked about again.
///
/// The bug this exists to prevent: `EntitlementStore` is held for the process
/// lifetime, so a customer who launched with the App Store unreachable resolved
/// to `verificationUnavailable` and was then metered for as long as the app
/// stayed open — reconnecting the network changed nothing, because nothing ever
/// asked a second time. A desktop app runs for days.
final class EntitlementRetryPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_780_000_000)
    private let interval = EntitlementRetryPolicy.unconfirmedRetryInterval

    private func shouldResolve(
        _ state: EntitlementState,
        lastAttempt: Date?,
        now: Date? = nil
    ) -> Bool {
        EntitlementRetryPolicy.shouldResolve(
            state: state,
            lastAttempt: lastAttempt,
            now: now ?? self.now,
            retryInterval: interval
        )
    }

    // MARK: - Unresolved

    func testLoadingAlwaysResolves() {
        XCTAssertTrue(shouldResolve(.loading, lastAttempt: nil))
        // Even inside the throttle window: there is no answer at all yet, and
        // waiting would show a paywall to someone who may well have paid.
        XCTAssertTrue(shouldResolve(.loading, lastAttempt: now))
    }

    // MARK: - Settled answers are never re-asked

    func testSettledAnswersAreNotRetried() {
        for state: EntitlementState in [
            .locked,
            .unlocked(reason: .inAppPurchase),
            .unlocked(reason: .legacyPurchase),
        ] {
            XCTAssertFalse(
                shouldResolve(state, lastAttempt: nil),
                "\(state) is a settled answer; revocation arrives through Transaction.updates"
            )
        }
    }

    // MARK: - Unconfirmed states retry, throttled

    func testUnconfirmedStatesRetryWhenNeverAttempted() {
        XCTAssertTrue(shouldResolve(.verificationUnavailable, lastAttempt: nil))
        XCTAssertTrue(shouldResolve(.unverified, lastAttempt: nil))
    }

    func testUnconfirmedStateIsThrottledInsideTheWindow() {
        let recent = now.addingTimeInterval(-(interval / 2))
        XCTAssertFalse(shouldResolve(.verificationUnavailable, lastAttempt: recent))
        XCTAssertFalse(shouldResolve(.unverified, lastAttempt: recent))
    }

    /// The regression: a network that came back must be picked up without a
    /// relaunch, a purchase, or a manual Restore Purchases.
    func testUnconfirmedStateRetriesOnceTheWindowElapses() {
        let stale = now.addingTimeInterval(-interval)
        XCTAssertTrue(shouldResolve(.verificationUnavailable, lastAttempt: stale))
        XCTAssertTrue(
            shouldResolve(.verificationUnavailable, lastAttempt: now.addingTimeInterval(-interval * 10))
        )
    }

    func testBoundaryInstantRetries() {
        XCTAssertTrue(
            shouldResolve(.verificationUnavailable, lastAttempt: now.addingTimeInterval(-interval)),
            "Elapsed exactly equal to the interval counts as elapsed"
        )
    }

    /// A clock corrected backwards must not strand someone until it catches up
    /// — the same posture `GrandfatherPolicy.acceptsCachedGrant` takes.
    func testClockMovedBackwardsStillRetries() {
        let future = now.addingTimeInterval(interval * 100)
        XCTAssertTrue(shouldResolve(.verificationUnavailable, lastAttempt: future))
    }

    /// Settled answers stay settled however long ago they were reached —
    /// the throttle is not a periodic refresh of a known answer.
    func testSettledAnswersAreNotRetriedEvenLongAfterTheLastAttempt() {
        let longAgo = now.addingTimeInterval(-interval * 1_000)
        XCTAssertFalse(shouldResolve(.locked, lastAttempt: longAgo))
        XCTAssertFalse(shouldResolve(.unlocked(reason: .inAppPurchase), lastAttempt: longAgo))
    }

    /// One tick short of the interval is still inside the window.
    func testJustInsideTheWindowIsThrottled() {
        XCTAssertFalse(
            shouldResolve(.verificationUnavailable, lastAttempt: now.addingTimeInterval(-(interval - 0.001)))
        )
    }

    // Joining a resolution already in flight is not this policy's decision —
    // it is covered by `EntitlementStoreTests`, where the coalescing lives.

    // MARK: - The flags the policy reads

    func testIsUnconfirmedNamesOnlyTheUnsettledStates() {
        XCTAssertTrue(EntitlementState.verificationUnavailable.isUnconfirmed)
        XCTAssertTrue(EntitlementState.unverified.isUnconfirmed)

        XCTAssertFalse(EntitlementState.loading.isUnconfirmed)
        XCTAssertFalse(EntitlementState.locked.isUnconfirmed)
        XCTAssertFalse(EntitlementState.unlocked(reason: .inAppPurchase).isUnconfirmed)
        XCTAssertFalse(EntitlementState.unlocked(reason: .legacyPurchase).isUnconfirmed)
    }
}
