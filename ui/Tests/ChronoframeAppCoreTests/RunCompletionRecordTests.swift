import Combine
import Foundation
import XCTest
@testable import ChronoframeAppCore
import ChronoframeCore

/// The typed once-per-run completion record is what watched-source
/// checkpoint advancement keys off — it must fire exactly once per run,
/// with the run's own token and resolved paths, for success, failure,
/// and cancellation alike.
@MainActor
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

    private func finishedTransfer(copiedBatchSourcePaths: Set<String>? = nil) -> MockOrganizerEngine.StreamMode {
        .events([
            .complete(RunSummary(
                status: .finished,
                title: "Done",
                metrics: RunMetrics(copiedCount: 1),
                artifacts: RunArtifactPaths(destinationRoot: "/tmp/library"),
                copiedBatchSourcePaths: copiedBatchSourcePaths
            ))
        ])
    }

    /// A batch record names exactly the source paths the engine reports it
    /// retained, and a later full run does not inherit them.
    @MainActor
    func testBatchRunRecordCarriesRetainedPathsAndTheNextRunDoesNot() async throws {
        let engine = MockOrganizerEngine(
            preflightResult: .success(makePreflight(mode: .transfer)),
            startMode: finishedTransfer(copiedBatchSourcePaths: ["/tmp/watched-source/a.jpg"])
        )
        let store = makeStores(engine: engine)
        let configuration = RunConfiguration(mode: .transfer, sourcePath: "/tmp/watched-source", destinationPath: "/tmp/library")
        let batch = FreeTestBatchSelection(confirmedIdentities: [
            "/tmp/watched-source/a.jpg": FileIdentity(size: 1, digest: "a")
        ])

        await store.requestRun(mode: .transfer, configuration: configuration, batch: batch)
        _ = await waitForCondition { store.lastRunCompletion != nil }
        let batchRecord = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(batchRecord.status, .finished)
        XCTAssertEqual(batchRecord.batchSourcePaths, ["/tmp/watched-source/a.jpg"])
        XCTAssertFalse(batchRecord.resumedPendingJobs)

        await store.requestRun(mode: .transfer, configuration: configuration)
        store.confirmPrompt()
        _ = await waitForCondition { store.lastRunCompletion?.runToken != batchRecord.runToken }
        let fullRecord = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(fullRecord.status, .finished)
        XCTAssertNil(fullRecord.batchSourcePaths, "A full run is not limited to the previous batch")
        XCTAssertFalse(fullRecord.resumedPendingJobs)
    }

    /// A confirmed path whose content changed before execution drops out of
    /// `FreeTestBatchSelection.apply` and is never copied — the completion
    /// record must reflect only what the engine actually retained
    /// (`RunSummary.copiedBatchSourcePaths`), not the full confirmed
    /// selection, or a watched-source checkpoint would acknowledge a file
    /// this run never touched.
    @MainActor
    func testBatchRunRecordNarrowsToWhatTheReplanRetainedNotTheFullConfirmedSelection() async throws {
        let engine = MockOrganizerEngine(
            preflightResult: .success(makePreflight(mode: .transfer)),
            // The engine confirms only "a.jpg" was actually retained by the
            // re-plan, even though "b.jpg" was also confirmed in the batch —
            // simulating b.jpg's identity changing between confirmation and
            // execution.
            startMode: finishedTransfer(copiedBatchSourcePaths: ["/tmp/watched-source/a.jpg"])
        )
        let store = makeStores(engine: engine)
        let configuration = RunConfiguration(mode: .transfer, sourcePath: "/tmp/watched-source", destinationPath: "/tmp/library")
        let batch = FreeTestBatchSelection(confirmedIdentities: [
            "/tmp/watched-source/a.jpg": FileIdentity(size: 1, digest: "a"),
            "/tmp/watched-source/b.jpg": FileIdentity(size: 2, digest: "b")
        ])

        await store.requestRun(mode: .transfer, configuration: configuration, batch: batch)
        _ = await waitForCondition { store.lastRunCompletion != nil }
        let record = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(record.status, .finished)
        XCTAssertEqual(
            record.batchSourcePaths, ["/tmp/watched-source/a.jpg"],
            "b.jpg was confirmed but not actually copied, so it must not be acknowledged"
        )
    }

    /// A revert never goes through `beginStream`, so a batch flag left over
    /// from an earlier free test batch must not make its record look like a
    /// batch run (`[]` instead of nil).
    @MainActor
    func testRevertAfterABatchRunPublishesRecordWithNoBatchScope() async throws {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("revert-after-batch-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: destination) }
        let receiptURL = destination.appendingPathComponent(".organize_logs/audit_receipt.json")
        let engine = MockOrganizerEngine(
            preflightResult: .success(makePreflight(mode: .transfer)),
            startMode: finishedTransfer(copiedBatchSourcePaths: ["/tmp/watched-source/a.jpg"]),
            revertMode: .events([
                .complete(RunSummary(
                    status: .reverted,
                    title: "Revert complete",
                    metrics: RunMetrics(revertedCount: 1),
                    artifacts: RunArtifactPaths(destinationRoot: destination.path)
                ))
            ])
        )
        let store = makeStores(engine: engine)
        let configuration = RunConfiguration(mode: .transfer, sourcePath: "/tmp/watched-source", destinationPath: "/tmp/library")
        let batch = FreeTestBatchSelection(confirmedIdentities: [
            "/tmp/watched-source/a.jpg": FileIdentity(size: 1, digest: "a")
        ])

        await store.requestRun(mode: .transfer, configuration: configuration, batch: batch)
        _ = await waitForCondition { store.lastRunCompletion != nil }
        let batchToken = try XCTUnwrap(store.lastRunCompletion).runToken

        store.requestRevert(receiptURL: receiptURL, destinationRoot: destination.path)
        _ = await waitForCondition { store.lastRunCompletion?.runToken != batchToken }
        let revertRecord = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(revertRecord.mode, .revert)
        XCTAssertNil(revertRecord.batchSourcePaths, "A revert is not a batch run")
    }

    @MainActor
    func testResumedRunRecordIsMarkedResumed() async throws {
        let preflight = RunPreflight(
            configuration: RunConfiguration(mode: .transfer, sourcePath: "/tmp/watched-source", destinationPath: "/tmp/library"),
            resolvedSourcePath: "/tmp/watched-source",
            resolvedDestinationPath: "/tmp/library",
            pendingJobCount: 2
        )
        let engine = MockOrganizerEngine(
            preflightResult: .success(preflight),
            resumeMode: finishedTransfer()
        )
        let store = makeStores(engine: engine)

        await store.requestRun(mode: .transfer, configuration: preflight.configuration)
        XCTAssertEqual(store.prompt?.kind, .resumePendingJobs)
        store.confirmPrompt()
        _ = await waitForCondition { store.lastRunCompletion != nil }

        let record = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(record.status, .finished)
        XCTAssertTrue(record.resumedPendingJobs)
        XCTAssertNil(record.batchSourcePaths)
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
        let completed = await waitForCondition { store.lastRunCompletion != nil }
        XCTAssertTrue(completed)
        let record = try XCTUnwrap(store.lastRunCompletion)
        XCTAssertEqual(record.status, .cancelled)
        XCTAssertEqual(record.mode, .preview)
    }
}
