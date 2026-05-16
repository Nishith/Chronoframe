import ChronoframeCLIKit
import ChronoframeCore
import XCTest

final class EventEmitterTests: XCTestCase {
    func testJSONEmitterUsesCompatibilityProgressKeys() throws {
        let line = try JSONLineEmitter.line(
            for: .phaseProgress(
                phase: .copy,
                completed: 2,
                total: 5,
                bytesCopied: 128,
                bytesTotal: 512
            )
        )

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        XCTAssertEqual(payload["type"] as? String, "task_progress")
        XCTAssertEqual(payload["task"] as? String, "copy")
        XCTAssertEqual(payload["completed"] as? Int, 2)
        XCTAssertEqual(payload["total"] as? Int, 5)
        XCTAssertEqual(payload["bytes_copied"] as? Int, 128)
        XCTAssertEqual(payload["bytes_total"] as? Int, 512)
    }

    func testJSONEmitterUsesBackendStatusNames() throws {
        let line = try JSONLineEmitter.line(
            for: .complete(
                RunSummary(
                    status: .dryRunFinished,
                    title: "Preview complete",
                    metrics: RunMetrics(plannedCount: 3),
                    artifacts: RunArtifactPaths(destinationRoot: "/out", reportPath: "/out/report.csv")
                )
            )
        )

        let payload = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
        )
        XCTAssertEqual(payload["type"] as? String, "complete")
        XCTAssertEqual(payload["status"] as? String, "dry_run_finished")
        let artifacts = try XCTUnwrap(payload["artifacts"] as? [String: Any])
        XCTAssertEqual(artifacts["destination"] as? String, "/out")
        XCTAssertEqual(artifacts["report"] as? String, "/out/report.csv")
    }

    func testHumanEmitterSuppressesHistogramNoise() {
        XCTAssertNil(HumanLineEmitter.line(for: .dateHistogram(buckets: [])))
    }
}
