import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers what the unlock sheet offers (free-trial step 5, T13).
///
/// The cases that matter are the ones where a wrong answer either charges
/// someone twice or shows a price that is not Apple's.
final class UnlockPresentationTests: XCTestCase {
    private let product = StoreProductInfo(
        productID: "com.nishith.chronoframe.unlock",
        displayName: "Chronoframe Unlock",
        displayPrice: "£14.99"
    )

    private func model(
        refusal: TrialAuthorizationRefusal,
        product: StoreProductInfo? = nil,
        isLoadingProduct: Bool = false,
        isPurchasing: Bool = false,
        isRestoring: Bool = false
    ) -> UnlockSheetModel {
        UnlockSheetModel.make(
            refusal: refusal,
            product: product,
            isLoadingProduct: isLoadingProduct,
            isPurchasing: isPurchasing,
            isRestoring: isRestoring
        )
    }

    private func spent(remaining: Int = 0, requested: Int = 40) -> TrialAuthorizationRefusal {
        .allowanceSpent(TrialRefusal(meter: .organize, requested: requested, remaining: remaining))
    }

    // MARK: - The price is Apple's

    /// The only price ever shown comes from `StoreProductInfo.displayPrice`. A
    /// hardcoded one goes stale on every storefront, currency and price change,
    /// and App Review rejects it.
    func testBuyButtonCarriesTheStoreSuppliedPrice() {
        let actions = model(refusal: spent(), product: product).actions

        XCTAssertEqual(
            actions.first,
            .buy(displayName: "Chronoframe Unlock", displayPrice: "£14.99")
        )
    }

    /// Until the product loads there is no price, so there is no Buy button.
    /// A button labelled with a guess is exactly what must never ship.
    func testNoBuyButtonUntilThePriceIsKnown() {
        let loading = model(refusal: spent(), product: nil, isLoadingProduct: true)

        XCTAssertFalse(loading.actions.contains { if case .buy = $0 { return true } else { return false } })
        XCTAssertTrue(loading.isBusy)
        XCTAssertEqual(loading.actions, [.dismiss])
    }

    /// A failed load offers Retry, and Restore for someone who already owns it
    /// and does not need the product looked up at all.
    func testFailedProductLoadOffersRetryAndRestore() {
        let failed = model(refusal: spent(), product: nil, isLoadingProduct: false)

        XCTAssertEqual(failed.actions, [.retryProductLoad, .restore, .dismiss])
        XCTAssertTrue(failed.message.contains("could not reach the App Store"), failed.message)
    }

    // MARK: - Never sell to someone who may already own it

    /// `purchaseUnconfirmed` means Chronoframe could not verify an entitlement
    /// that may well exist. Offering Buy there invites a second purchase of a
    /// non-consumable the customer might already own.
    func testUnconfirmedPurchaseOffersRestoreAndNeverBuy() {
        let unconfirmed = model(
            refusal: .purchaseUnconfirmed(TrialRefusal(meter: .organize, requested: 5, remaining: 0)),
            product: product
        )

        XCTAssertEqual(unconfirmed.actions, [.restore, .dismiss])
        XCTAssertFalse(
            unconfirmed.actions.contains { if case .buy = $0 { return true } else { return false } },
            "A customer whose purchase merely could not be confirmed must not be sold it again"
        )
        XCTAssertFalse(
            unconfirmed.message.localizedCaseInsensitiveContains("allowance"),
            unconfirmed.message
        )
    }

    /// Restore is offered wherever a purchase is, which App Review requires.
    func testRestoreIsAlwaysAvailableAlongsideBuy() {
        XCTAssertTrue(model(refusal: spent(), product: product).actions.contains(.restore))
        XCTAssertTrue(model(refusal: .requiresUnlock, product: product).actions.contains(.restore))
    }

    // MARK: - Copy

    /// A refusal does not mean the balance is zero — the policy refuses any run
    /// larger than what remains — so a customer with room for a smaller batch
    /// must not be told their allowance is gone.
    func testPartialAllowanceReportsWhatIsLeft() {
        let message = model(refusal: spent(remaining: 12, requested: 40), product: product).message

        XCTAssertTrue(message.contains("12 files left"), message)
        XCTAssertTrue(message.contains("40"), message)
        XCTAssertFalse(message.contains("used up"), message)
    }

    func testExhaustedAllowanceSaysSo() {
        let message = model(refusal: spent(remaining: 0, requested: 3), product: product).message

        XCTAssertTrue(message.contains("used up"), message)
        XCTAssertTrue(message.contains("originals were left untouched"), message)
    }

    /// One file is "1 file", not "1 files".
    func testSingularCountsAreNotPluralized() {
        let message = model(refusal: spent(remaining: 1, requested: 1), product: product).message

        XCTAssertTrue(message.contains("1 file left"), message)
        XCTAssertFalse(message.contains("1 files"), message)
    }

    /// Reorganize is unlock-only, so its copy must not mention an allowance it
    /// never consumed.
    func testRequiresUnlockCopyDoesNotMentionAnAllowance() {
        let model = model(refusal: .requiresUnlock, product: product)

        XCTAssertTrue(model.message.contains("once Chronoframe is unlocked"), model.message)
        XCTAssertFalse(model.message.localizedCaseInsensitiveContains("allowance"), model.message)
    }

    /// A dedupe refusal talks about the Trash, not about copies.
    func testDedupeRefusalCopyDescribesTheTrash() {
        let message = model(
            refusal: .allowanceSpent(TrialRefusal(meter: .dedupe, requested: 9, remaining: 0)),
            product: product
        ).message

        XCTAssertTrue(message.contains("Nothing was moved to the Trash."), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("copied"), message)
    }

    // MARK: - Busy

    /// While StoreKit is working the view disables its buttons from this flag
    /// rather than inventing its own notion of busy.
    func testBusyWhilePurchasingOrRestoring() {
        XCTAssertTrue(model(refusal: spent(), product: product, isPurchasing: true).isBusy)
        XCTAssertTrue(model(refusal: spent(), product: product, isRestoring: true).isBusy)
        XCTAssertFalse(model(refusal: spent(), product: product).isBusy)
    }
}
