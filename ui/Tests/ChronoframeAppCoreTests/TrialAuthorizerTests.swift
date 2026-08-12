import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers the seam every metered surface asks before it mutates anything.
///
/// The cases that matter are the ones where a wrong answer either gives the
/// product away or blocks someone who paid.
final class TrialAuthorizerTests: XCTestCase {
    private let account = "app-txn-1"
    private let caps = TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 4)

    private func authorizer(
        ledger: any TrialLedger,
        state: EntitlementState,
        accountKey: String? = "app-txn-1"
    ) -> EntitlementTrialAuthorizer {
        EntitlementTrialAuthorizer(ledger: ledger) {
            TrialEntitlementSnapshot(state: state, accountKey: accountKey)
        }
    }

    private func spentLedger(organize: Int) throws -> InMemoryTrialLedger {
        let ledger = InMemoryTrialLedger(caps: caps)
        let runID = UUID()
        _ = try ledger.reserve(
            runID: runID, accountKey: account, meter: .organize,
            count: organize, destinationRoot: nil
        )
        try ledger.finalize(runID: runID, actualCount: organize)
        return ledger
    }

    // MARK: - Unrestricted

    func testUnrestrictedPermitsEverythingAndRecordsNothing() async throws {
        let authorizer = UnrestrictedTrialAuthorizer()

        let decision = await authorizer.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 10_000, destinationRoot: nil
        )

        XCTAssertEqual(decision, .permitted)
        let unlockOnly = await authorizer.authorizeUnlockOnlyWork()
        XCTAssertEqual(unlockOnly, .permitted)
        // Finalize and release are no-ops rather than failures.
        await authorizer.finalizeMeteredWork(runID: UUID(), actualCount: 5)
        await authorizer.releaseMeteredWork(runID: UUID())
    }

    // MARK: - Unlocked

    func testUnlockedPermitsWithoutTouchingTheLedger() async throws {
        let ledger = ExplodingAuthorizerLedger()
        let authorizer = authorizer(ledger: ledger, state: .unlocked(reason: .inAppPurchase))

        let decision = await authorizer.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 500, destinationRoot: "/dest"
        )

        XCTAssertEqual(decision, .permitted)
        XCTAssertFalse(ledger.wasTouched, "A paid customer must not cause a reservation")
        let unlockOnly = await authorizer.authorizeUnlockOnlyWork()
        XCTAssertEqual(unlockOnly, .permitted)
    }

    // MARK: - Metered

    func testWithinAllowancePermitsAndReserves() async throws {
        let ledger = InMemoryTrialLedger(caps: caps)
        let authorizer = authorizer(ledger: ledger, state: .locked)
        let runID = UUID()

        let decision = await authorizer.authorizeMeteredWork(
            runID: runID, meter: .organize, count: 6, destinationRoot: "/dest"
        )

        XCTAssertEqual(decision, .permitted)
        // The reservation is taken, not merely approved.
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 6)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [runID])

        await authorizer.finalizeMeteredWork(runID: runID, actualCount: 2)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 2)
    }

    func testExceedingTheAllowanceRefusesAsSpent() async throws {
        let authorizer = authorizer(ledger: try spentLedger(organize: 8), state: .locked)

        let decision = await authorizer.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 5, destinationRoot: nil
        )

        XCTAssertEqual(
            decision,
            .refused(.allowanceSpent(TrialRefusal(meter: .organize, requested: 5, remaining: 2)))
        )
    }

    /// A run with nothing to do is never refused, whatever the balance. It would
    /// be an insult with no revenue attached.
    func testEmptyRunIsPermittedEvenWhenExhausted() async throws {
        let authorizer = authorizer(ledger: try spentLedger(organize: 10), state: .locked)

        let decision = await authorizer.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 0, destinationRoot: nil
        )
        XCTAssertEqual(decision, .permitted)
    }

    func testReleaseGivesTheReservationBack() async throws {
        let ledger = InMemoryTrialLedger(caps: caps)
        let authorizer = authorizer(ledger: ledger, state: .locked)
        let runID = UUID()
        _ = await authorizer.authorizeMeteredWork(
            runID: runID, meter: .dedupe, count: 4, destinationRoot: nil
        )
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 0)

        await authorizer.releaseMeteredWork(runID: runID)

        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 4)
    }

    // MARK: - Unverifiable entitlement

    /// Settled policy: these states are metered like the trial, so an exhausted
    /// allowance refuses. But the refusal must NOT claim the trial is spent —
    /// this customer may have paid, and we simply could not confirm it.
    func testUnverifiableStatesAreMeteredButRefuseAsUnconfirmed() async throws {
        for state in [EntitlementState.verificationUnavailable, .unverified] {
            let authorizer = authorizer(ledger: try spentLedger(organize: 10), state: state)

            let decision = await authorizer.authorizeMeteredWork(
                runID: UUID(), meter: .organize, count: 1, destinationRoot: nil
            )

            guard case let .refused(refusal) = decision else {
                return XCTFail("\(state) is metered and must refuse when exhausted")
            }
            guard case .purchaseUnconfirmed = refusal else {
                return XCTFail("\(state) must never be reported as a spent trial, got \(refusal)")
            }
        }
    }

    /// The same states still permit work that fits, so an offline customer with
    /// allowance left is not blocked.
    func testUnverifiableStatesStillPermitWorkWithinTheAllowance() async throws {
        let authorizer = authorizer(
            ledger: InMemoryTrialLedger(caps: caps),
            state: .verificationUnavailable
        )

        let decision = await authorizer.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 3, destinationRoot: nil
        )
        XCTAssertEqual(decision, .permitted)
    }

    /// `.loading` reaching the authorizer means resolution genuinely failed —
    /// the composition root is responsible for awaiting it — so it is metered
    /// exactly like the other unconfirmable states.
    ///
    /// That means permitted while allowance remains, and refused as
    /// `purchaseUnconfirmed` once it does not. It is bounded rather than
    /// blocking: a transient resolution failure cannot hand out unlimited work,
    /// and it also cannot lock out someone who has allowance left.
    func testLoadingIsMeteredLikeAnyUnconfirmedState() async throws {
        let withRoom = authorizer(ledger: InMemoryTrialLedger(caps: caps), state: .loading)
        let permitted = await withRoom.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 3, destinationRoot: nil
        )
        XCTAssertEqual(permitted, .permitted, "Allowance remains, so work is not blocked")

        let exhausted = authorizer(ledger: try spentLedger(organize: 10), state: .loading)
        let refused = await exhausted.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 1, destinationRoot: nil
        )
        guard case .refused(.purchaseUnconfirmed) = refused else {
            return XCTFail("Exhausted and unconfirmed must refuse without claiming a spent trial, got \(refused)")
        }
    }

    func testMissingAccountKeyRefusesAsUnconfirmed() async throws {
        let authorizer = authorizer(
            ledger: InMemoryTrialLedger(caps: caps),
            state: .locked,
            accountKey: nil
        )

        let decision = await authorizer.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 1, destinationRoot: nil
        )

        guard case .refused(.purchaseUnconfirmed) = decision else {
            return XCTFail("No account key means no metering is possible; fail closed, got \(decision)")
        }
    }

    /// A ledger that cannot record the reservation must not let the work run:
    /// mutating media with no record of the charge is the one outcome worse
    /// than refusing.
    func testUnwritableLedgerRefuses() async throws {
        let authorizer = authorizer(ledger: ThrowingReserveLedger(), state: .locked)

        let decision = await authorizer.authorizeMeteredWork(
            runID: UUID(), meter: .organize, count: 3, destinationRoot: nil
        )

        XCTAssertFalse(decision.isPermitted)
    }

    // MARK: - Refusal copy

    /// The refusal a customer reads must say the allowance is short, offer the
    /// unlock, and reassure them nothing was changed on the way to the message.
    func testAllowanceSpentCopyOffersTheUnlockAndSaysNothingWasCopied() throws {
        let error = TrialAuthorizationError(
            refusal: .allowanceSpent(TrialRefusal(meter: .organize, requested: 40, remaining: 12))
        )
        let message = try XCTUnwrap(error.errorDescription)

        XCTAssertTrue(message.contains("12"), message)
        XCTAssertTrue(message.contains("40"), message)
        XCTAssertTrue(message.contains("Unlock Chronoframe"), message)
        XCTAssertTrue(message.contains("originals were left untouched"), message)
    }

    /// The distinction that matters most in this file. A customer whose purchase
    /// could not be confirmed may well have paid, so the copy must not tell them
    /// their trial is spent or push them at the unlock.
    func testPurchaseUnconfirmedCopyNeverClaimsTheTrialIsSpent() throws {
        let error = TrialAuthorizationError(
            refusal: .purchaseUnconfirmed(TrialRefusal(meter: .organize, requested: 40, remaining: 0))
        )
        let message = try XCTUnwrap(error.errorDescription)

        XCTAssertTrue(message.contains("could not confirm your purchase"), message)
        XCTAssertTrue(message.contains("Restore Purchases"), message)
        XCTAssertTrue(message.contains("originals were left untouched"), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("allowance"), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("free"), message)
    }

    /// A dedupe refusal must not promise that originals were left untouched —
    /// that surface trashes duplicates, it does not copy anything.
    func testDedupeRefusalCopyDescribesTheTrashNotCopies() throws {
        let error = TrialAuthorizationError(
            refusal: .allowanceSpent(TrialRefusal(meter: .dedupe, requested: 9, remaining: 0))
        )
        let message = try XCTUnwrap(error.errorDescription)

        XCTAssertTrue(message.contains("Nothing was moved to the Trash."), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("copied"), message)
    }

    /// Routed through `UserFacingErrorMessage`, so the Run workspace shows this
    /// copy rather than the generic "could not finish this run" fallback with a
    /// raw error appended.
    func testRefusalIsFormattedByUserFacingErrorMessageRatherThanFallingBack() {
        let error = TrialAuthorizationError(
            refusal: .allowanceSpent(TrialRefusal(meter: .organize, requested: 40, remaining: 12))
        )

        XCTAssertEqual(
            UserFacingErrorMessage.message(for: error, context: .run),
            error.errorDescription
        )
    }

    func testRequiresUnlockCopyIsPlainAndReassuring() throws {
        let error = TrialAuthorizationError(refusal: .requiresUnlock)
        let message = try XCTUnwrap(error.errorDescription)

        XCTAssertTrue(message.contains("once Chronoframe is unlocked"), message)
        XCTAssertTrue(message.contains("Nothing was changed."), message)
    }

    // MARK: - Unlock-only (reorganize)

    func testUnlockOnlyWorkRequiresTheUnlock() async throws {
        for state in [EntitlementState.locked, .verificationUnavailable, .unverified, .loading] {
            let authorizer = authorizer(ledger: InMemoryTrialLedger(caps: caps), state: state)
            let decision = await authorizer.authorizeUnlockOnlyWork()
            XCTAssertEqual(decision, .refused(.requiresUnlock), "\(state) is not an unlock")
        }

        let unlocked = authorizer(
            ledger: InMemoryTrialLedger(caps: caps),
            state: .unlocked(reason: .legacyPurchase)
        )
        let unlockedDecision = await unlocked.authorizeUnlockOnlyWork()
        XCTAssertEqual(unlockedDecision, .permitted)
    }
}

/// Fails the test if any reservation is attempted.
private final class ExplodingAuthorizerLedger: TrialLedger, @unchecked Sendable {
    private let lock = NSLock()
    private var touched = false
    var wasTouched: Bool {
        lock.lock(); defer { lock.unlock() }
        return touched
    }

    private func markTouched() {
        lock.lock(); touched = true; lock.unlock()
    }

    func balance(accountKey: String) throws -> TrialBalance {
        markTouched()
        return .unspent()
    }

    func reserve(
        runID: UUID, accountKey: String, meter: TrialMeter,
        count: Int, destinationRoot: String?
    ) throws -> ReservationDecision {
        markTouched()
        return .permitted
    }

    func finalize(runID: UUID, actualCount: Int) throws { markTouched() }
    func release(runID: UUID) throws { markTouched() }
    func refund(
        receiptRunID: UUID, accountKey: String,
        meter: TrialMeter, itemPaths: [String]
    ) throws { markTouched() }
    func accountKey(forRunID runID: UUID) throws -> String? { "app-txn-1" }
    func openReservations() throws -> [OpenReservation] { [] }
}

/// A ledger whose writes fail, standing in for a disk that has gone away.
private struct ThrowingReserveLedger: TrialLedger {
    func balance(accountKey: String) throws -> TrialBalance { .unspent() }
    func reserve(
        runID: UUID, accountKey: String, meter: TrialMeter,
        count: Int, destinationRoot: String?
    ) throws -> ReservationDecision {
        throw TrialLedgerError.writeFailed("disk unavailable")
    }
    func finalize(runID: UUID, actualCount: Int) throws {}
    func release(runID: UUID) throws {}
    func refund(
        receiptRunID: UUID, accountKey: String,
        meter: TrialMeter, itemPaths: [String]
    ) throws {}
    func accountKey(forRunID runID: UUID) throws -> String? { "app-txn-1" }
    func openReservations() throws -> [OpenReservation] { [] }
}
