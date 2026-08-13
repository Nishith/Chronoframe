import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Running a confirmed free test batch (free-trial step 5, T15).
final class FreeTestBatchRunTests: XCTestCase {
    private nonisolated(unsafe) var historyStore: HistoryStore!
    private nonisolated(unsafe) var logStore: RunLogStore!
    private nonisolated(unsafe) var tempDestinationURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        historyStore = await HistoryStore()
        logStore = await RunLogStore(capacity: 200)
        tempDestinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FreeTestBatchRunTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDestinationURL, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let tempDestinationURL {
            try? FileManager.default.removeItem(at: tempDestinationURL)
        }
        tempDestinationURL = nil
        historyStore = nil
        logStore = nil
        try await super.tearDown()
    }

    private var configuration: RunConfiguration {
        RunConfiguration(
            mode: .transfer,
            sourcePath: "/tmp/source",
            destinationPath: tempDestinationURL.path
        )
    }

    private func preflight(pendingJobCount: Int) -> RunPreflight {
        RunPreflight(
            configuration: configuration,
            resolvedSourcePath: configuration.sourcePath,
            resolvedDestinationPath: configuration.destinationPath,
            pendingJobCount: pendingJobCount
        )
    }

    private var selection: FreeTestBatchSelection {
        FreeTestBatchSelection(
            confirmedIdentities: ["/Volumes/Card/a.raf": FileIdentity(size: 12, digest: "digest-a")]
        )
    }

    // MARK: - A confirmed batch runs without asking again

    @MainActor
    func testAConfirmedBatchStartsWithoutTheGenericTransferPrompt() async {
        let engine = MockOrganizerEngine(preflightResult: .success(preflight(pendingJobCount: 0)))
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .transfer, configuration: configuration, batch: selection)

        XCTAssertNil(store.prompt, "The batch sheet was the confirmation; asking again is asking twice")
        XCTAssertEqual(engine.startBatches.count, 1)
        XCTAssertEqual(engine.startBatches.first, selection)
    }

    /// Without a batch the existing confirmation still stands.
    @MainActor
    func testAnOrdinaryTransferStillAsksFirst() async {
        let engine = MockOrganizerEngine(preflightResult: .success(preflight(pendingJobCount: 0)))
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .transfer, configuration: configuration)

        XCTAssertEqual(store.prompt?.kind, .confirmTransfer)
        XCTAssertTrue(engine.startBatches.isEmpty)
    }

    // MARK: - A stale queue blocks the batch

    /// `TransferExecutor.executeQueuedJobs` selects pending rows by status
    /// alone — there is no run_id filter — so a batch starting on top of an
    /// interrupted run's queue would copy those jobs too: unconfirmed, and past
    /// the count just authorized.
    @MainActor
    func testPendingJobsBlockABatchInsteadOfCopyingThemToo() async {
        let engine = MockOrganizerEngine(preflightResult: .success(preflight(pendingJobCount: 12)))
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .transfer, configuration: configuration, batch: selection)

        XCTAssertTrue(
            engine.startBatches.isEmpty,
            "Nothing may start while an interrupted transfer's queue is still there"
        )
        XCTAssertTrue(engine.startConfigurations.isEmpty)
        XCTAssertEqual(store.prompt?.kind, .blockingError)
        let message = store.prompt?.message ?? ""
        XCTAssertTrue(message.contains("12 copy jobs"), message)
        XCTAssertTrue(message.contains("originals were left untouched"), message)
    }

    /// The pending-job decision itself is unchanged for a normal transfer.
    @MainActor
    func testPendingJobsStillOfferResumeWhenNoBatchIsInvolved() async {
        let engine = MockOrganizerEngine(preflightResult: .success(preflight(pendingJobCount: 12)))
        let store = RunSessionStore(engine: engine, logStore: logStore, historyStore: historyStore)

        await store.requestRun(mode: .transfer, configuration: configuration)

        XCTAssertEqual(store.prompt?.kind, .resumePendingJobs)
    }
}

/// What the completion notification says (T15).
///
/// A notification is often the only part of a finished run anyone reads, so a
/// sentence contradicting the in-app result is worse than no notification.
final class RunCompletionNotificationTextTests: XCTestCase {
    private func summary(_ status: RunStatus, title: String = "Title") -> RunSummary {
        RunSummary(
            status: status,
            title: title,
            metrics: RunMetrics(discoveredCount: 4, plannedCount: 0, copiedCount: 0),
            artifacts: RunArtifactPaths()
        )
    }

    /// The bug this covers: the in-app branch says the batch matched nothing,
    /// while the notification said the library was already up to date.
    func testAnUnmatchedBatchIsNotAnnouncedAsUpToDate() {
        let text = RunSessionStore.completionNotificationText(
            summary: summary(.nothingToCopy, title: "Nothing left to copy"),
            usedFreeTestBatch: true
        )

        XCTAssertEqual(text?.title, "Nothing left to copy")
        XCTAssertFalse(
            (text?.body ?? "").localizedCaseInsensitiveContains("already"),
            "Nothing was copied, so nothing may imply the files are safely in the destination: \(text?.body ?? "")"
        )
        XCTAssertTrue((text?.body ?? "").contains("moved or changed"), text?.body ?? "")
    }

    /// An ordinary up-to-date run keeps saying so.
    func testAnOrdinaryNothingToCopyRunStillReportsUpToDate() {
        let text = RunSessionStore.completionNotificationText(
            summary: summary(.nothingToCopy),
            usedFreeTestBatch: false
        )

        XCTAssertEqual(text?.title, "Already up to date")
        XCTAssertEqual(text?.body, "All source files are already in the destination.")
    }

    func testACancelledRunIsNotAnnounced() {
        XCTAssertNil(
            RunSessionStore.completionNotificationText(
                summary: summary(.cancelled),
                usedFreeTestBatch: false
            )
        )
    }

    func testAFinishedRunCountsWhatItCopied() {
        let finished = RunSummary(
            status: .finished,
            title: "Transfer complete",
            metrics: RunMetrics(copiedCount: 1),
            artifacts: RunArtifactPaths()
        )

        XCTAssertEqual(
            RunSessionStore.completionNotificationText(summary: finished, usedFreeTestBatch: true)?.body,
            "1 file copied",
            "A batch run that did copy something reports normally"
        )
    }
}
