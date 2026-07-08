import Combine
import Foundation
import XCTest
@testable import ChronoframeAppCore

/// The typed once-per-run completion record is what watched-source
/// checkpoint advancement keys off — it must fire exactly once per run,
/// with the run's own token and resolved paths, for success, failure,
/// and cancellation alike.
final class RunCompletionRecordTests: XCTestCase {
    private func makeStores(engine: MockOrganizerEngine) -> RunSessionStore {
        RunSessionStore(
            engine: engine,
            logStore: RunLogStore(capacity: 100),
            historyStore: HistoryStore()
        )
    }

    private func makePreflight(mode: RunMode) -> RunPreflight {
        RunPreflight(
            configuration: RunConfiguration(
                mode: mode,
                sourcePath: "/tmp/watched-source",
                destinationPath: "/tmp/library"
            ),
            resolvedSourcePath: "/tmp/watched-source",
            resolvedDestinationPath: "/tmp/library"
        )
    }

    @MainActor
    func testSuccessfulPreviewPublishesExactlyOneRecordWithTokenAndPaths() async throws {
        let engine = MockOrganizerEngine(
            preflightResult: .success(makePreflight(mode: .preview)),
            startMode: .events([
                .complete(RunSummary(
                    status: .dryRunFinished,
                    title: "Preview complete",
                    metrics: RunMetrics(plannedCount: 2),
                    artifacts: RunArtifactPaths(destinationRoot: "/tmp/library")
                ))
            ])
        )
        let store = makeStores(engine: engine)

        var records: [RunCompletionRecord] = []
        let cancellable = store.$lastRunCompletion.sink { record in
            if let record { records.append(record) }
        }
        defer { cancellable.cancel() }

        await store.requestRun(
            mode: .preview,
            configuration: RunConfiguration(mode: .preview, sourcePath: "/tmp/watched-source", destinationPath: "/tmp/library")
        )
        let requestToken = store.currentRunToken
        let finished = await waitForCondition { store.lastRunCompletion != nil }
        XCTAssertTrue(finished)

        XCTAssertEqual(records.count, 1, "Exactly one record per run")
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.runToken, requestToken)
        XCTAssertEqual(record.mode, .preview)
        XCTAssertEqual(record.status, .dryRunFinished)
        XCTAssertEqual(record.resolvedSourcePath, "/tmp/watched-source")
        XCTAssertEqual(record.resolvedDestinationPath, "/tmp/library")
        XCTAssertEqual(record.configuration?.sourcePath, "/tmp/watched-source")
    }

    @MainActor
    func testSequentialRunsCarryDistinctTokens() async throws {
        let engine = MockOrganizerEngine(
            preflightResult: .success(makePreflight(mode: .preview)),
            startMode: .events([
                .complete(RunSummary(
                    status: .dryRunFinished,
                    title: "Preview complete",
                    metrics: RunMetrics(),
                    artifacts: RunArtifactPaths(destinationRoot: "/tmp/library")
                ))
            ])
        )
        let store = makeStores(engine: engine)

        await store.requestRun(
            mode: .preview,
            configuration: RunConfiguration(mode: .preview, sourcePath: "/s", destinationPath: "/d")
        )
        _ = await waitForCondition { store.lastRunCompletion != nil }
        let firstToken = store.lastRunCompletion?.runToken

        await store.requestRun(
            mode: .preview,
            configuration: RunConfiguration(mode: .preview, sourcePath: "/s", destinationPath: "/d")
        )
        _ = await waitForCondition { store.lastRunCompletion?.runToken != firstToken }

        XCTAssertNotEqual(store.lastRunCompletion?.runToken, firstToken)
    }

    @MainActor
    func testFailedRunPublishesFailedRecord() async throws {
        struct TestError: Error {}
        let engine = MockOrganizerEngine(
            preflightResult: .success(makePreflight(mode: .transfer)),
            startMode: .fails(TestError())
        )
        let store = makeStores(engine: engine)

        await store.requestRun(
            mode: .transfer,
            configuration: RunConfiguration(mode: .transfer, sourcePath: "/tmp/watched-source", destinationPath: "/tmp/library")
        )
        store.confirmPrompt()
        let finished = await waitForCondition { store.lastRunCompletion != nil }
        XCTAssertTrue(finished)

        let record = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(record.status, .failed)
        XCTAssertEqual(record.mode, .transfer)
        XCTAssertEqual(record.resolvedSourcePath, "/tmp/watched-source",
                       "Failure records still identify the run so consumers can react (without acknowledging work)")
    }

    @MainActor
    func testCancelledRunPublishesCancelledRecord() async throws {
        let engine = MockOrganizerEngine(
            preflightResult: .success(makePreflight(mode: .preview)),
            startMode: .pending
        )
        let store = makeStores(engine: engine)

        await store.requestRun(
            mode: .preview,
            configuration: RunConfiguration(mode: .preview, sourcePath: "/tmp/watched-source", destinationPath: "/tmp/library")
        )
        let running = await waitForCondition { store.status == .running }
        XCTAssertTrue(running)

        store.cancelCurrentRun()

        let record = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(record.status, .cancelled)
        XCTAssertEqual(record.mode, .preview)
    }
}
