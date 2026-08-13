import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Which refusals may carry a free test batch (free-trial step 5, T15).
///
/// The rule with teeth is the second one: a customer whose purchase could not
/// be confirmed is metered exactly like a trial, so the refusal looks the same
/// from the gate's side — but they may already have paid, and offering them a
/// free sample of the thing they bought would be wrong.
final class FreeTestBatchOfferTests: XCTestCase {
    private func transfer(_ name: String, bucket: String = "2026-01-11") -> PlannedTransfer {
        PlannedTransfer(
            sourcePath: "/Volumes/Card/\(name)",
            destinationPath: "/Volumes/Archive/\(bucket)/\(name)",
            identity: FileIdentity(size: Int64(name.count), digest: "digest-\(name)"),
            dateBucket: bucket,
            isDuplicate: false
        )
    }

    private var plan: [PlannedTransfer] {
        (0..<10).map { transfer("file-\($0).raf") }
    }

    private func offer(
        _ refusal: TrialAuthorizationRefusal,
        plannedTransfers: [PlannedTransfer]? = nil
    ) -> FreeTestBatch? {
        TrialAuthorizationError.offeringFreeTestBatch(
            TrialAuthorizationError(refusal: refusal),
            plannedTransfers: plannedTransfers ?? plan
        ).offeredBatch
    }

    // MARK: - The offer is made

    func testASpentAllowanceWithRoomLeftOffersABatch() {
        let batch = offer(
            .allowanceSpent(TrialRefusal(meter: .organize, requested: 10, remaining: 4))
        )

        XCTAssertEqual(batch?.includedCount, 4)
        XCTAssertEqual(batch?.deferredCount, 6)
    }

    // MARK: - The offer is withheld

    /// The one that matters. This customer may have paid.
    func testAnUnconfirmedPurchaseIsNeverOfferedAFreeBatch() {
        let batch = offer(
            .purchaseUnconfirmed(TrialRefusal(meter: .organize, requested: 10, remaining: 4))
        )

        XCTAssertNil(
            batch,
            "A customer whose purchase could not be confirmed must not be offered a free sample of it"
        )
    }

    func testAnUnlockOnlyActionIsNotOfferedABatch() {
        XCTAssertNil(offer(.requiresUnlock))
    }

    /// Nothing left means the batch would be empty, and offering to copy
    /// nothing is worse than not offering.
    func testAFullySpentAllowanceOffersNothing() {
        XCTAssertNil(
            offer(.allowanceSpent(TrialRefusal(meter: .organize, requested: 10, remaining: 0)))
        )
    }

    /// Duplicate cleanup is metered on its own meter and is not a transfer, so
    /// there is no plan to slice.
    func testTheDedupeMeterIsNotOfferedATransferBatch() {
        XCTAssertNil(
            offer(.allowanceSpent(TrialRefusal(meter: .dedupe, requested: 10, remaining: 4)))
        )
    }

    /// If the allowance covers the whole plan then size is not why this was
    /// refused, and re-offering the same run would loop.
    func testABatchCoveringTheWholePlanIsNotOffered() {
        XCTAssertNil(
            offer(.allowanceSpent(TrialRefusal(meter: .organize, requested: 10, remaining: 50)))
        )
    }

    func testAnEmptyPlanOffersNothing() {
        XCTAssertNil(
            offer(
                .allowanceSpent(TrialRefusal(meter: .organize, requested: 0, remaining: 4)),
                plannedTransfers: []
            )
        )
    }

    // MARK: - The refusal itself is untouched

    /// Attaching an offer must not change what the customer is told, or the
    /// copy the refusal already got right in T8.
    func testTheOfferDoesNotAlterTheRefusalOrItsMessage() {
        let refusal = TrialAuthorizationRefusal.allowanceSpent(
            TrialRefusal(meter: .organize, requested: 10, remaining: 4)
        )
        let original = TrialAuthorizationError(refusal: refusal)

        let enriched = TrialAuthorizationError.offeringFreeTestBatch(original, plannedTransfers: plan)

        XCTAssertEqual(enriched.refusal, original.refusal)
        XCTAssertEqual(enriched.errorDescription, original.errorDescription)
        XCTAssertNotNil(enriched.offeredBatch)
    }

    /// A refusal carries no offer unless something built one, so every existing
    /// construction site stays exactly as it was.
    func testARefusalCarriesNoOfferByDefault() {
        XCTAssertNil(TrialAuthorizationError(refusal: .requiresUnlock).offeredBatch)
    }
}
