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

    private func model(
        entitlement: EntitlementState,
        allowance: TrialAllowance
    ) -> LicenseStatusModel {
        LicenseStatusModel.make(
            status: TrialStatus(entitlement: entitlement, allowance: allowance)
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

    /// Someone who bought before the move to a free download is unlocked for a
    /// different reason, and the pane should say which.
    func testGrandfatheredCustomerIsToldWhy() {
        let model = model(entitlement: .unlocked(reason: .legacyPurchase), allowance: .unlimited)

        XCTAssertEqual(model.headline, "Unlocked")
        XCTAssertTrue(model.detail.contains("before it moved to a free download"), model.detail)
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
