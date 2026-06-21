import XCTest
@testable import ChronoframeApp
@testable import ChronoframeCore

final class OrganizeFolderIntentFailureTests: XCTestCase {
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
