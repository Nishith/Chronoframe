import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// The remaining-allowance indicator (free-trial step 5, T16).
///
/// Two rules carry the weight: it is absent for anyone who paid, and it never
/// shows a number it does not actually have.
final class TrialIndicatorPresentationTests: XCTestCase {
    private let caps = TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100)

    private func status(
        _ entitlement: EntitlementState,
        organizeUsed: Int = 0,
        dedupeUsed: Int = 0
    ) -> TrialStatus {
        TrialStatus(
            entitlement: entitlement,
            allowance: .remaining(
                TrialBalance(
                    caps: caps,
                    usage: TrialUsage(organizeUsed: organizeUsed, dedupeUsed: dedupeUsed)
                )
            )
        )
    }

    // MARK: - Shown

    func testOrganizeCountsFiles() {
        let model = TrialIndicatorModel.make(status: status(.locked, organizeUsed: 120), meter: .organize)

        XCTAssertEqual(model?.text, "380 of 500 files left")
        XCTAssertEqual(model?.isSpent, false)
    }

    func testDedupeCountsDuplicates() {
        let model = TrialIndicatorModel.make(status: status(.locked, dedupeUsed: 4), meter: .dedupe)

        XCTAssertEqual(model?.text, "96 of 100 duplicates left")
    }

    /// Each meter reports its own number; spending one does not touch the
    /// other's indicator.
    func testTheTwoMetersAreIndependent() {
        let spentOrganize = status(.locked, organizeUsed: 500, dedupeUsed: 0)

        XCTAssertEqual(
            TrialIndicatorModel.make(status: spentOrganize, meter: .organize)?.text,
            "0 of 500 files left"
        )
        XCTAssertEqual(
            TrialIndicatorModel.make(status: spentOrganize, meter: .dedupe)?.text,
            "100 of 100 duplicates left"
        )
    }

    func testAnEmptyMeterIsMarkedSpent() {
        let model = TrialIndicatorModel.make(status: status(.locked, dedupeUsed: 100), meter: .dedupe)

        XCTAssertEqual(model?.text, "0 of 100 duplicates left")
        XCTAssertEqual(model?.isSpent, true)
    }

    /// A customer who may have paid but could not be verified is metered, so
    /// the number they are running against is the one to show.
    func testAnUnverifiedCustomerStillSeesWhatTheGateWillUse() {
        for entitlement in [EntitlementState.unverified, .verificationUnavailable] {
            XCTAssertEqual(
                TrialIndicatorModel.make(status: status(entitlement, organizeUsed: 1), meter: .organize)?.text,
                "499 of 500 files left",
                "\(entitlement)"
            )
        }
    }

    /// Plural agrees with the cap, so the phrase never reads "1 of 500 file
    /// left" as the allowance runs down.
    func testPluralAgreesWithTheCapNotTheRemainder() {
        let almostGone = status(.locked, organizeUsed: 499)

        XCTAssertEqual(
            TrialIndicatorModel.make(status: almostGone, meter: .organize)?.text,
            "1 of 500 files left"
        )
    }

    func testASingleFileCapReadsSingular() {
        let tiny = TrialStatus(
            entitlement: .locked,
            allowance: .remaining(
                TrialBalance(
                    caps: TrialAllowanceCaps(organizeFiles: 1, dedupeFiles: 1),
                    usage: TrialUsage(organizeUsed: 0, dedupeUsed: 0)
                )
            )
        )

        XCTAssertEqual(TrialIndicatorModel.make(status: tiny, meter: .organize)?.text, "1 of 1 file left")
        XCTAssertEqual(TrialIndicatorModel.make(status: tiny, meter: .dedupe)?.text, "1 of 1 duplicate left")
    }

    // MARK: - Absent

    /// Settled policy: no trial furniture for someone who paid.
    func testAnUnlockedCustomerSeesNoIndicator() {
        for reason in [UnlockReason.inAppPurchase, .legacyPurchase] {
            let unlocked = TrialStatus(entitlement: .unlocked(reason: reason), allowance: .unlimited)

            XCTAssertNil(TrialIndicatorModel.make(status: unlocked, meter: .organize), "\(reason)")
            XCTAssertNil(TrialIndicatorModel.make(status: unlocked, meter: .dedupe), "\(reason)")
        }
    }

    /// Defensive: unlimited means no limit even if the entitlement somehow
    /// disagrees, and a limit is the only thing this indicator reports.
    func testUnlimitedShowsNothingWhateverTheEntitlementSays() {
        let odd = TrialStatus(entitlement: .locked, allowance: .unlimited)

        XCTAssertNil(TrialIndicatorModel.make(status: odd, meter: .organize))
    }

    /// A workspace that flashed "checking…" on every launch would be noise.
    func testNothingIsShownBeforeTheStatusResolves() {
        XCTAssertNil(TrialIndicatorModel.make(status: .loading, meter: .organize))
    }

    /// The Developer ID build meters nothing, so a remaining count there would
    /// describe a limit that does not exist.
    func testTheUnrestrictedChannelShowsNoIndicator() {
        let metered = status(.locked, organizeUsed: 120)

        XCTAssertNil(
            TrialIndicatorModel.make(status: metered, meter: .organize, isAppStoreChannel: false)
        )
        XCTAssertNotNil(
            TrialIndicatorModel.make(status: metered, meter: .organize),
            "…but the App Store channel still shows it"
        )
    }

    /// The one that matters most. Zero-because-unreadable is not
    /// zero-because-spent, and a one-line indicator has no room to say which —
    /// so it says nothing rather than showing a number it does not have. The
    /// License tab explains it properly, and the gate still refuses.
    func testAnUnreadableLedgerShowsNoNumbersAtAll() {
        let unreadable = TrialStatus(entitlement: .locked, allowance: .unavailable)

        XCTAssertNil(TrialIndicatorModel.make(status: unreadable, meter: .organize))
        XCTAssertNil(TrialIndicatorModel.make(status: unreadable, meter: .dedupe))
    }
}
