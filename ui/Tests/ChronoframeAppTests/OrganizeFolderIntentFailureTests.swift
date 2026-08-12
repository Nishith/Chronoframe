import XCTest
@testable import ChronoframeApp
import ChronoframeAppCore
@testable import ChronoframeCore

final class OrganizeFolderIntentFailureTests: XCTestCase {
    // MARK: - Purchase refusals (free-trial step 4, T11)

    /// A refused run is not a broken run, and an unattended automation has to be
    /// told which one it hit. "Transfer failed" would send someone hunting
    /// through folder permissions for a paywall.
    func testRefusalMessagesSayWhatHappenedAndWhereToGo() {
        let messages = [
            OrganizeIntentPurchaseMessage.message(
                for: .allowanceSpent(TrialRefusal(meter: .organize, requested: 40, remaining: 0))
            ),
            OrganizeIntentPurchaseMessage.message(
                for: .purchaseUnconfirmed(TrialRefusal(meter: .organize, requested: 40, remaining: 0))
            ),
            OrganizeIntentPurchaseMessage.message(for: .requiresUnlock),
        ]

        for message in messages {
            XCTAssertTrue(
                message.contains("Open Chronoframe"),
                "A background intent can only send the user to the app: \(message)"
            )
            XCTAssertFalse(
                message.localizedCaseInsensitiveContains("failed"),
                "A refusal is not a failure: \(message)"
            )
        }
    }

    /// The distinction that matters: a customer whose purchase could not be
    /// confirmed may well have paid, so the shortcut must not tell them their
    /// free allowance is gone.
    func testUnconfirmedPurchaseIsNotReportedAsASpentAllowance() {
        let message = OrganizeIntentPurchaseMessage.message(
            for: .purchaseUnconfirmed(TrialRefusal(meter: .organize, requested: 1, remaining: 0))
        )

        XCTAssertTrue(message.contains("could not confirm your purchase"), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("allowance"), message)
        XCTAssertFalse(message.localizedCaseInsensitiveContains("free"), message)
    }

    /// Only the spent-allowance case says the allowance is spent.
    func testSpentAllowanceSaysSoAndPointsAtTheUnlock() {
        let message = OrganizeIntentPurchaseMessage.message(
            for: .allowanceSpent(TrialRefusal(meter: .organize, requested: 40, remaining: 0))
        )

        XCTAssertTrue(message.contains("free allowance is used up"), message)
        XCTAssertTrue(message.contains("unlock"), message)
    }

    func testIncompleteRunUsesActionableEngineFailureMessage() {
        let summary = RunSummary(
            status: .failed,
            title: "Transfer incomplete",
            metrics: RunMetrics(failedCount: 2, skippedCount: 1),
            artifacts: RunArtifactPaths(destinationRoot: "/dest"),
            failureMessage: "The transfer did not finish: 2 failed and 1 was skipped. Originals were left untouched."
        )

        XCTAssertEqual(
            OrganizeIntentFailureMessage.message(summary: summary, lastErrorMessage: nil),
            "The transfer did not finish: 2 failed and 1 was skipped. Originals were left untouched."
        )
    }

    func testMissingTechnicalErrorUsesSpecificFallbackInsteadOfUnknownError() {
        let message = OrganizeIntentFailureMessage.message(summary: nil, lastErrorMessage: nil)
        XCTAssertFalse(message.contains("Unknown error"))
        XCTAssertTrue(message.contains("could not complete"))
    }
}
