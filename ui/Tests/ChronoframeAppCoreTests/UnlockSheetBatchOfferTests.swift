import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// The free test batch as the unlock sheet offers it (free-trial step 5, T15).
final class UnlockSheetBatchOfferTests: XCTestCase {
    private let product = StoreProductInfo(
        productID: "com.nishith.chronoframe.unlock",
        displayName: "Chronoframe",
        displayPrice: "$29.99"
    )

    private func transfer(_ name: String, bucket: String) -> PlannedTransfer {
        PlannedTransfer(
            sourcePath: "/Volumes/Card/\(name)",
            destinationPath: "/Volumes/Archive/\(bucket)/\(name)",
            identity: FileIdentity(size: Int64(name.count), digest: "digest-\(name)"),
            dateBucket: bucket,
            isDuplicate: false
        )
    }

    private func batch(included: Int, deferred: Int, singleDate: Bool = false) -> FreeTestBatch {
        let transfers = (0..<included).map {
            transfer("file-\($0).raf", bucket: singleDate ? "2026-01-11" : "2026-0\(($0 % 3) + 1)-05")
        }
        return FreeTestBatch(included: transfers, deferredCount: deferred)
    }

    private var spent: TrialAuthorizationRefusal {
        .allowanceSpent(TrialRefusal(meter: .organize, requested: 900, remaining: 3))
    }

    private func model(
        refusal: TrialAuthorizationRefusal? = nil,
        offeredBatch: FreeTestBatch?,
        product: StoreProductInfo? = nil,
        isLoadingProduct: Bool = false
    ) -> UnlockSheetModel {
        UnlockSheetModel.make(
            refusal: refusal ?? spent,
            product: product ?? self.product,
            isLoadingProduct: isLoadingProduct,
            isPurchasing: false,
            isRestoring: false,
            offeredBatch: offeredBatch
        )
    }

    private func batchAction(_ model: UnlockSheetModel) -> UnlockSheetAction? {
        model.actions.first {
            if case .runFreeTestBatch = $0 { return true }
            return false
        }
    }

    // MARK: - Offered

    func testASpentAllowanceWithARoomySmallerRunOffersTheBatch() {
        let model = model(offeredBatch: batch(included: 3, deferred: 897))

        XCTAssertEqual(batchAction(model), .runFreeTestBatch(fileCount: 3, deferredCount: 897))
    }

    /// Unlocking stays the primary path; the batch sits below it, above Cancel.
    func testTheBatchIsOfferedBelowUnlockAndAboveDismiss() {
        let model = model(offeredBatch: batch(included: 3, deferred: 897))

        let kinds = model.actions.map { action -> String in
            switch action {
            case .buy: return "buy"
            case .restore: return "restore"
            case .runFreeTestBatch: return "batch"
            case .retryProductLoad: return "retry"
            case .dismiss: return "dismiss"
            }
        }
        XCTAssertEqual(kinds, ["buy", "restore", "batch", "dismiss"])
    }

    /// A count alone does not say which photos would be copied.
    func testTheDetailNamesTheSpanAndWhatIsLeftBehind() {
        let detail = model(offeredBatch: batch(included: 3, deferred: 897)).batchDetail ?? ""

        XCTAssertTrue(detail.contains("3 files"), detail)
        XCTAssertTrue(detail.contains("897"), detail)
        XCTAssertTrue(detail.contains("to"), "A multi-day batch names its span: \(detail)")
    }

    func testASingleDayBatchDoesNotNameARange() {
        let detail = model(offeredBatch: batch(included: 2, deferred: 5, singleDate: true)).batchDetail ?? ""

        XCTAssertTrue(detail.contains("2026-01-11"), detail)
        XCTAssertFalse(detail.contains("2026-01-11 to 2026-01-11"), detail)
    }

    /// A price that has not loaded is no reason to withhold something free.
    func testTheBatchIsStillOfferedWhileTheProductIsLoading() {
        let model = model(offeredBatch: batch(included: 3, deferred: 897), product: nil, isLoadingProduct: true)

        XCTAssertEqual(batchAction(model), .runFreeTestBatch(fileCount: 3, deferredCount: 897))
    }

    func testTheBatchIsStillOfferedWhenTheProductFailedToLoad() {
        let model = model(offeredBatch: batch(included: 3, deferred: 897), product: nil)

        XCTAssertNotNil(batchAction(model))
    }

    // MARK: - Withheld

    /// The engine already withholds a batch here. This is the second,
    /// independent check: a customer who may have paid must never be offered a
    /// free sample of what they bought, even if a batch somehow reached this
    /// sheet.
    func testAnUnconfirmedPurchaseIsNeverOfferedABatchEvenIfOneIsPassed() {
        let model = model(
            refusal: .purchaseUnconfirmed(TrialRefusal(meter: .organize, requested: 900, remaining: 3)),
            offeredBatch: batch(included: 3, deferred: 897)
        )

        XCTAssertNil(batchAction(model))
        XCTAssertNil(model.batchDetail)
    }

    func testAnUnlockOnlyRefusalIsNeverOfferedABatch() {
        let model = model(refusal: .requiresUnlock, offeredBatch: batch(included: 3, deferred: 897))

        XCTAssertNil(batchAction(model))
    }

    func testNoBatchMeansNoBatchAction() {
        let model = model(offeredBatch: nil)

        XCTAssertNil(batchAction(model))
        XCTAssertNil(model.batchDetail)
    }

    func testAnEmptyBatchIsNotOffered() {
        let model = model(offeredBatch: FreeTestBatch(included: [], deferredCount: 900))

        XCTAssertNil(batchAction(model))
    }

    /// Nothing deferred means the plan already fits, so there is no smaller run
    /// to offer and pressing it would just repeat the refused run.
    func testABatchCoveringTheWholePlanIsNotOffered() {
        let model = model(offeredBatch: batch(included: 3, deferred: 0))

        XCTAssertNil(batchAction(model))
    }

    /// The sheet without a batch must be exactly what T13 shipped.
    func testTheSheetIsUnchangedWhenNoBatchIsOffered() {
        let withoutBatch = model(offeredBatch: nil)
        let t13 = UnlockSheetModel.make(
            refusal: spent,
            product: product,
            isLoadingProduct: false,
            isPurchasing: false,
            isRestoring: false
        )

        XCTAssertEqual(withoutBatch, t13)
    }
}
