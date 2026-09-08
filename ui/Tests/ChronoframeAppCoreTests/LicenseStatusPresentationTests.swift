import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers what the Settings License tab says (free-trial step 5, T14).
///
/// The rule worth protecting: "the ledger could not be read" and "your trial is
/// used up" both produce zero remaining, and must never produce the same
/// sentence.
final class LicenseStatusPresentationTests: XCTestCase {
    private let caps = TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100)

    /// The paid window: `grandfatherCutover` sits far in the future, so "now" is
    /// always before it. This is the shipping v2.0 configuration.
    private let beforePriceDrop = Date(timeIntervalSince1970: 1_780_000_000)
    private let priceDrop = Date(timeIntervalSince1970: 1_790_000_000)

    private func model(
        entitlement: EntitlementState,
        allowance: TrialAllowance,
        cutover: Date? = nil,
        now: Date? = nil
    ) -> LicenseStatusModel {
        LicenseStatusModel.make(
            status: TrialStatus(entitlement: entitlement, allowance: allowance),
            cutover: cutover ?? priceDrop,
            now: now ?? beforePriceDrop
        )
    }

    private func balance(organizeUsed: Int, dedupeUsed: Int) -> TrialBalance {
        TrialBalance(
            caps: caps,
            usage: TrialUsage(organizeUsed: organizeUsed, dedupeUsed: dedupeUsed)
        )
    }

    // MARK: - Unlocked

    func testPurchasedCustomerSeesNoAllowanceAndNoRestore() {
        let model = model(entitlement: .unlocked(reason: .inAppPurchase), allowance: .unlimited)

        XCTAssertEqual(model.headline, "Unlocked")
        XCTAssertTrue(model.allowanceRows.isEmpty, "An unlocked customer has no allowance to report")
        XCTAssertFalse(model.showsRestore, "Nothing to restore when already unlocked")
        XCTAssertTrue(model.detail.contains("no limits"), model.detail)
    }

    /// Once the price has actually dropped, someone who bought earlier is
    /// unlocked for a different reason, and the pane should say which.
    func testGrandfatheredCustomerIsToldWhyAfterThePriceDrops() {
        let model = model(
            entitlement: .unlocked(reason: .legacyPurchase),
            allowance: .unlimited,
            now: priceDrop
        )

        XCTAssertEqual(model.headline, "Unlocked")
        XCTAssertTrue(model.detail.contains("before it moved to a free download"), model.detail)
    }

    /// Regression: during the paid window `grandfatherCutover` is far in the
    /// future, so EVERY paying customer resolves to `.legacyPurchase`. The pane
    /// must not announce a price drop that has not happened to someone who has
    /// just paid full price — the store listing makes no pricing claim before
    /// the cutover, and neither may this.
    func testPaidWindowCustomerIsNotToldTheAppBecameFree() {
        let model = model(
            entitlement: .unlocked(reason: .legacyPurchase),
            allowance: .unlimited,
            now: beforePriceDrop
        )

        XCTAssertEqual(model.headline, "Unlocked")
        XCTAssertFalse(
            model.detail.localizedCaseInsensitiveContains("free download"),
            "The paid window must make no claim about a free price: \(model.detail)"
        )
        XCTAssertTrue(model.detail.contains("unlocked permanently"), model.detail)
    }

    /// The boundary itself counts as dropped, so the two branches cannot both
    /// be silent at the exact cutover instant.
    func testCutoverInstantCountsAsDropped() {
        let model = model(
            entitlement: .unlocked(reason: .legacyPurchase),
            allowance: .unlimited,
            now: priceDrop
        )

        XCTAssertTrue(model.detail.contains("before it moved to a free download"), model.detail)
    }

    /// An in-app purchase says the same thing on both sides of the cutover —
    /// that customer bought the unlock, not the app.
    func testInAppPurchaseCopyIsUnaffectedByTheCutover() {
        for now in [beforePriceDrop, priceDrop] {
            let model = model(
                entitlement: .unlocked(reason: .inAppPurchase),
                allowance: .unlimited,
                now: now
            )
            XCTAssertTrue(model.detail.contains("no limits"), model.detail)
            XCTAssertFalse(
                model.detail.localizedCaseInsensitiveContains("free download"),
                model.detail
            )
        }
    }

    // MARK: - The distinction that matters

    /// An unreadable ledger must NOT be reported as a spent trial. Gates refuse
    /// either way — the fail-closed stand-in answers zero remaining — but zero
    /// because-unreadable is not a fact about the customer.
    func testUnreadableLedgerIsNeverReportedAsASpentTrial() {
        let model = model(entitlement: .locked, allowance: .unavailable)

        XCTAssertEqual(model.headline, "Free trial")
        XCTAssertFalse(model.detail.localizedCaseInsensitiveContains("used up"), model.detail)
        XCTAssertTrue(model.detail.contains("could not read its record"), model.detail)
        XCTAssertTrue(
            model.allowanceRows.isEmpty,
            "No numbers may be shown when the numbers could not be read"
        )
        XCTAssertTrue(model.showsRestore)
    }

    /// A genuinely spent trial says so.
    func testSpentTrialSaysUsedUp() {
        let model = model(
            entitlement: .locked,
            allowance: .remaining(balance(organizeUsed: 500, dedupeUsed: 100))
        )

        XCTAssertTrue(model.detail.contains("used up"), model.detail)
        XCTAssertEqual(model.allowanceRows.map(\.value), ["0 of 500 left", "0 of 100 left"])
    }

    /// A partly-used trial reports both meters, and does not claim to be spent.
    func testPartlyUsedTrialReportsBothMeters() {
        let model = model(
            entitlement: .locked,
            allowance: .remaining(balance(organizeUsed: 120, dedupeUsed: 4))
        )

        XCTAssertEqual(model.headline, "Free trial")
        XCTAssertFalse(model.detail.localizedCaseInsensitiveContains("used up"), model.detail)
        XCTAssertEqual(
            model.allowanceRows,
            [
                LicenseStatusModel.Row(label: "Files organized", value: "380 of 500 left"),
                LicenseStatusModel.Row(label: "Duplicates removed", value: "96 of 100 left"),
            ]
        )
    }

    /// One meter empty is not a spent trial — the other still has room.
    func testOneEmptyMeterIsNotASpentTrial() {
        let model = model(
            entitlement: .locked,
            allowance: .remaining(balance(organizeUsed: 500, dedupeUsed: 0))
        )

        XCTAssertFalse(model.detail.localizedCaseInsensitiveContains("used up"), model.detail)
        XCTAssertEqual(model.allowanceRows.map(\.value), ["0 of 500 left", "100 of 100 left"])
    }

    // MARK: - Unconfirmed entitlement

    /// A customer who may have paid but could not be verified is metered, so
    /// their balance is shown — but they are never told the trial is theirs.
    func testOfflineCustomerIsToldAccessIsUnchanged() {
        let model = model(
            entitlement: .verificationUnavailable,
            allowance: .remaining(balance(organizeUsed: 500, dedupeUsed: 100))
        )

        XCTAssertTrue(model.detail.contains("could not reach the App Store"), model.detail)
        XCTAssertTrue(model.detail.contains("Your access is unchanged"), model.detail)
        XCTAssertFalse(
            model.detail.localizedCaseInsensitiveContains("used up"),
            "An unverified customer at zero has not necessarily spent anything: \(model.detail)"
        )
    }

    func testUnverifiedCustomerIsPointedAtRestore() {
        let model = model(
            entitlement: .unverified,
            allowance: .remaining(balance(organizeUsed: 10, dedupeUsed: 0))
        )

        XCTAssertTrue(model.detail.contains("could not verify your purchase"), model.detail)
        XCTAssertTrue(model.showsRestore)
    }

    // MARK: - Unrestricted channel

    /// The Developer ID build has no App Store licence to describe. Showing
    /// "Checking your purchase…" and a Restore button there would invite the
    /// customer to fix a problem that cannot exist in that channel.
    func testUnrestrictedChannelDescribesItselfAndOffersNoRestore() {
        let model = LicenseStatusModel.make(status: .loading, isAppStoreChannel: false)

        XCTAssertEqual(model.headline, "Unlocked")
        XCTAssertTrue(model.detail.contains("not distributed through the App Store"), model.detail)
        XCTAssertFalse(model.showsRestore, "There is nothing to restore in this channel")
        XCTAssertTrue(model.allowanceRows.isEmpty)
    }

    /// It says the same thing whatever the ledger happens to hold, because the
    /// ledger is not what governs that channel.
    func testUnrestrictedChannelIgnoresTheLedgerEntirely() {
        let spent = TrialStatus(
            entitlement: .locked,
            allowance: .remaining(balance(organizeUsed: 500, dedupeUsed: 100))
        )

        let model = LicenseStatusModel.make(status: spent, isAppStoreChannel: false)

        XCTAssertEqual(model.headline, "Unlocked")
        XCTAssertFalse(model.detail.localizedCaseInsensitiveContains("used up"), model.detail)
        XCTAssertTrue(model.allowanceRows.isEmpty)
    }

    // MARK: - Still resolving

    func testLoadingShowsNoNumbersAndClaimsNothing() {
        let model = LicenseStatusModel.make(status: .loading)

        XCTAssertEqual(model.headline, "Checking your purchase…")
        XCTAssertTrue(model.allowanceRows.isEmpty)
        XCTAssertTrue(model.detail.isEmpty)
    }

    /// Restore is reachable from Settings for everyone who is not unlocked,
    /// which is what App Review looks for outside a purchase flow.
    func testRestoreIsOfferedToEveryoneNotYetUnlocked() {
        let states: [(EntitlementState, TrialAllowance)] = [
            (.locked, .remaining(balance(organizeUsed: 0, dedupeUsed: 0))),
            (.locked, .unavailable),
            (.verificationUnavailable, .remaining(balance(organizeUsed: 0, dedupeUsed: 0))),
            (.unverified, .unavailable),
            (.loading, .unknown),
        ]

        for (entitlement, allowance) in states {
            XCTAssertTrue(
                model(entitlement: entitlement, allowance: allowance).showsRestore,
                "\(entitlement) must be able to restore"
            )
        }
    }
}
