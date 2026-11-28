import ChronoframeCore
import XCTest
@testable import ChronoframeCLIKit

/// A count of 1 must read "1 file", never "1 files". Zero stays plural.
final class CLIPluralTests: XCTestCase {
    private func summary(_ status: RunStatus, metrics: RunMetrics) -> RunSummary {
        RunSummary(status: status, title: "t", metrics: metrics, artifacts: RunArtifactPaths())
    }

    func testPlanReadyLine() {
        XCTAssertEqual(HumanLineEmitter.line(for: .copyPlanReady(count: 1)), "1 file ready to copy.")
        XCTAssertEqual(HumanLineEmitter.line(for: .copyPlanReady(count: 0)), "0 files ready to copy.")
        XCTAssertEqual(HumanLineEmitter.line(for: .copyPlanReady(count: 4)), "4 files ready to copy.")
    }

    func testDiscoveryAndClassificationLines() {
        XCTAssertEqual(
            HumanLineEmitter.line(for: .phaseCompleted(phase: .discovery, result: RunPhaseResult(found: 1))),
            "Discovered 1 file."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .phaseCompleted(phase: .discovery, result: RunPhaseResult(found: 0))),
            "Discovered 0 files."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .phaseCompleted(
                phase: .classification,
                result: RunPhaseResult(newCount: 1, alreadyInDestinationCount: 1)
            )),
            "Classified 1 new file, 1 already in destination."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .phaseCompleted(
                phase: .classification,
                result: RunPhaseResult(newCount: 5, alreadyInDestinationCount: 0)
            )),
            "Classified 5 new files, 0 already in destination."
        )
    }

    func testCompletionLines() {
        XCTAssertEqual(
            HumanLineEmitter.line(for: .complete(summary(.finished, metrics: RunMetrics(copiedCount: 1)))),
            "Done. Copied 1 file."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .complete(summary(.finished, metrics: RunMetrics(copiedCount: 2)))),
            "Done. Copied 2 files."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .complete(summary(.reverted, metrics: RunMetrics(revertedCount: 1)))),
            "Revert complete. Reverted 1 file."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .complete(summary(.reverted, metrics: RunMetrics(revertedCount: 3)))),
            "Revert complete. Reverted 3 files."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .complete(summary(.reorganized, metrics: RunMetrics(movedCount: 1)))),
            "Reorganize complete. Moved 1 file."
        )
        XCTAssertEqual(
            HumanLineEmitter.line(for: .complete(summary(.reorganized, metrics: RunMetrics(movedCount: 0)))),
            "Reorganize complete. Moved 0 files."
        )
    }

    func testResumePromptNamesTheJobsInTheRightNumber() {
        XCTAssertEqual(
            ChronoframeCLI.resumePrompt(pendingJobCount: 1),
            "Found 1 pending copy job. Resume it? [Y/n/fresh]"
        )
        XCTAssertEqual(
            ChronoframeCLI.resumePrompt(pendingJobCount: 7),
            "Found 7 pending copy jobs. Resume them? [Y/n/fresh]"
        )
    }
}
