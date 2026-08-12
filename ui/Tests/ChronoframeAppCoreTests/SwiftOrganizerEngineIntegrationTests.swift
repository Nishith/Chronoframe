import Foundation
import XCTest
@testable import ChronoframeAppCore

final class SwiftOrganizerEngineIntegrationTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftOrganizerEngineIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testPreflightResolvesProfileAndCountsPendingJobs() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let database = try OrganizerDatabase(url: destinationURL.appendingPathComponent(".organize_cache.db"))
        try database.enqueueJobs([
            CopyJobRecord(
                sourcePath: "/tmp/a.jpg",
                destinationPath: "/tmp/b.jpg",
                identity: FileIdentity(size: 1, digest: "pending"),
                status: .pending
            )
        ])
        database.close()

        let repository = TestProfilesRepository(
            profiles: [
                Profile(name: "camera", sourcePath: sourceURL.path, destinationPath: destinationURL.path),
            ],
            profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
        )
        let engine = SwiftOrganizerEngine(authorizer: UnrestrictedTrialAuthorizer(), profilesRepository: repository)

        let preflight = try await engine.preflight(
            RunConfiguration(
                mode: .preview,
                profileName: "camera",
                folderStructure: .yyyyMonEvent
            )
        )

        XCTAssertEqual(preflight.resolvedSourcePath, sourceURL.path)
        XCTAssertEqual(preflight.resolvedDestinationPath, destinationURL.path)
        XCTAssertEqual(preflight.configuration.folderStructure, .yyyyMonEvent)
        XCTAssertEqual(preflight.pendingJobCount, 1)
        XCTAssertEqual(preflight.profilesFilePath, repository.profilesFileURL().path)
    }

    @MainActor
    func testStartPreviewStreamsPlannerEventsAndWritesArtifacts() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("camera/IMG_20240102_101010.jpg")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: fileURL)

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )

        let stream = try engine.start(
            RunConfiguration(
                mode: .preview,
                sourcePath: sourceURL.path,
                destinationPath: destinationURL.path
            )
        )
        let events = try await Self.collect(stream)

        // Discovery, destination indexing, and source hashing are streamed live
        // from the planner so the Run workspace can show determinate progress.
        XCTAssertEqual(Self.render(events), [
            "startup",
            "phaseStarted:discovery",
            "phaseCompleted:discovery",
            "phaseStarted:dest_hash",
            "phaseCompleted:dest_hash",
            "phaseStarted:src_hash",
            "phaseProgress:src_hash:1/1",
            "phaseCompleted:src_hash",
            "phaseStarted:classification",
            "phaseCompleted:classification",
            "dateHistogram:1",
            "copyPlanReady:1",
            "complete:dryRunFinished",
        ])

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected complete event")
        }

        XCTAssertEqual(summary.metrics.discoveredCount, 1)
        XCTAssertEqual(summary.metrics.plannedCount, 1)
        XCTAssertEqual(summary.metrics.dateHistogram.map(\.key), ["2024-01"])
        XCTAssertEqual(summary.metrics.dateHistogram.map(\.plannedCount), [1])
        XCTAssertEqual(summary.status, .dryRunFinished)
        XCTAssertEqual(summary.title, "Preview complete")
        XCTAssertEqual(summary.artifacts.destinationRoot, destinationURL.path)

        guard let reportPath = summary.artifacts.reportPath else {
            return XCTFail("Missing report path")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportPath))
        let reportContents = try String(contentsOfFile: reportPath, encoding: .utf8)
        XCTAssertTrue(reportContents.contains("Source,Destination,Hash,Status"))
        XCTAssertTrue(reportContents.contains(fileURL.path))
        XCTAssertTrue(reportContents.contains("PENDING"))

        XCTAssertEqual(
            summary.artifacts.logsDirectoryPath,
            destinationURL.appendingPathComponent(".organize_logs", isDirectory: true).path
        )
        XCTAssertEqual(
            summary.artifacts.logFilePath,
            destinationURL.appendingPathComponent(".organize_log.txt").path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.artifacts.logFilePath ?? ""))
    }

    @MainActor
    func testStartPreviewSurfacesCrowdedGreenfieldDayAsInfo() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("crowded-source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("crowded-dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        for index in 1...1_001 {
            let fileURL = sourceURL.appendingPathComponent(
                String(format: "batch/IMG_20260419_%06d.jpg", index)
            )
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("source-\(index)".utf8).write(to: fileURL)
        }

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )

        let stream = try engine.start(
            RunConfiguration(
                mode: .preview,
                sourcePath: sourceURL.path,
                destinationPath: destinationURL.path
            )
        )
        let events = try await Self.collect(stream)

        let issues = events.compactMap { event -> RunIssue? in
            if case let .issue(issue) = event {
                return issue
            }
            return nil
        }
        XCTAssertTrue(issues.contains {
            $0.severity == .info
                && $0.message == "Day 2026-04-19: 1,001 files — using 4-digit sequence numbers."
        })
        XCTAssertFalse(issues.contains {
            $0.severity == .warning && $0.message.contains("Sequence overflow")
        })
        XCTAssertTrue(events.contains {
            if case let .dateHistogram(buckets) = $0 {
                return buckets.map(\.key) == ["2026-04"]
                    && buckets.map(\.plannedCount) == [1_001]
            }
            return false
        })

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected complete event")
        }
        XCTAssertEqual(summary.metrics.dateHistogram.map(\.key), ["2026-04"])
        XCTAssertEqual(summary.metrics.dateHistogram.map(\.plannedCount), [1_001])
    }

    @MainActor
    func testStartTransferExecutesNativeCopyAndWritesExecutionArtifacts() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("camera/IMG_20240102_101010.jpg")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: fileURL)

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )

        let stream = try engine.start(
            RunConfiguration(
                mode: .transfer,
                sourcePath: sourceURL.path,
                destinationPath: destinationURL.path
            )
        )
        let events = try await Self.collect(stream)

        XCTAssertEqual(Self.render(events), [
            "startup",
            "phaseStarted:discovery",
            "phaseCompleted:discovery",
            "phaseStarted:dest_hash",
            "phaseCompleted:dest_hash",
            "phaseStarted:src_hash",
            "phaseProgress:src_hash:1/1",
            "phaseCompleted:src_hash",
            "phaseStarted:classification",
            "phaseCompleted:classification",
            "dateHistogram:1",
            "copyPlanReady:1",
            "phaseStarted:copy",
            "phaseProgress:copy:1/1",
            "phaseCompleted:copy",
            "complete:finished",
        ])

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }

        XCTAssertEqual(summary.status, .finished)
        XCTAssertEqual(summary.title, "Done")
        XCTAssertEqual(summary.metrics.discoveredCount, 1)
        XCTAssertEqual(summary.metrics.plannedCount, 1)
        XCTAssertEqual(summary.metrics.copiedCount, 1)
        XCTAssertEqual(summary.metrics.failedCount, 0)
        XCTAssertEqual(summary.metrics.dateHistogram.map(\.key), ["2024-01"])
        XCTAssertEqual(summary.metrics.dateHistogram.map(\.plannedCount), [1])

        let copiedFileURL = destinationURL.appendingPathComponent("2024/01/02/2024-01-02_001.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedFileURL.path))

        let copiedJobCount = try Self.withDatabaseWhenReady(at: destinationURL.appendingPathComponent(".organize_cache.db")) { database in
            try database.loadQueuedJobs(status: .copied).count
        }
        XCTAssertEqual(copiedJobCount, 1)

        let destinationCachePaths = try Self.withDatabaseWhenReady(
            at: destinationURL.appendingPathComponent(".organize_cache.db")
        ) { database in
            try database.loadRawCacheRecords(namespace: .destination).map(\.path)
        }
        XCTAssertEqual(destinationCachePaths, [copiedFileURL.path])

        let logsDirectoryPath = try XCTUnwrap(summary.artifacts.logsDirectoryPath)
        let logsDirectoryURL = URL(fileURLWithPath: logsDirectoryPath, isDirectory: true)
        let receipts = try FileManager.default.contentsOfDirectory(at: logsDirectoryURL, includingPropertiesForKeys: nil)
        XCTAssertEqual(receipts.filter { $0.lastPathComponent.hasPrefix("audit_receipt_") }.count, 1)

        let logContents = try String(
            contentsOfFile: try XCTUnwrap(summary.artifacts.logFilePath),
            encoding: .utf8
        )
        XCTAssertTrue(logContents.contains("Run complete"))
    }

    /// Finding #4: a source that cannot be hashed yields zero planned copies.
    /// That is not "Already up to date" — files are missing from the
    /// destination, so the run must complete as `.failed`.
    @MainActor
    func testTransferWithOnlyUnreadableSourceReportsFailedNotUpToDate() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("camera/IMG_20240102_101010.jpg")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("unreadable".utf8).write(to: fileURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o000)], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: fileURL.path) }

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )
        let stream = try engine.start(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        let events = try await Self.collect(stream)

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }
        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.title, "Some files couldn't be read")
        XCTAssertEqual(summary.metrics.hashErrorCount, 1)
        XCTAssertEqual(summary.metrics.copiedCount, 0)
    }

    /// Finding #4: a run that copies some files but leaves others unprocessed
    /// (here an unreadable source) is incomplete, not "Done" — even though it
    /// never hit the abort threshold. The readable file is still copied.
    @MainActor
    func testTransferWithMixedSourcesCopiesGoodFileButReportsIncomplete() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let goodURL = sourceURL.appendingPathComponent("camera/IMG_20240102_101010.jpg")
        let badURL = sourceURL.appendingPathComponent("camera/IMG_20240103_101010.jpg")
        try FileManager.default.createDirectory(at: goodURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("good".utf8).write(to: goodURL)
        try Data("bad".utf8).write(to: badURL)
        try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o000)], ofItemAtPath: badURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: 0o644)], ofItemAtPath: badURL.path) }

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )
        let stream = try engine.start(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        let events = try await Self.collect(stream)

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }
        XCTAssertEqual(summary.status, .failed)
        XCTAssertEqual(summary.title, "Transfer incomplete")
        XCTAssertEqual(summary.metrics.copiedCount, 1)
        XCTAssertEqual(summary.metrics.hashErrorCount, 1)
        // The readable file was still organized.
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationURL.appendingPathComponent("2024/01/02/2024-01-02_001.jpg").path
        ))
    }

    /// Finding #3: a parallel transfer paused on permanently-low disk must
    /// observe `cancelCurrentRun()` and stop. The copy workers run on GCD
    /// queues where `Task.isCancelled` is always false, so before the shared
    /// cancellation flag was plumbed into the transfer stream a cancel never
    /// reached them and the run hung in `group.wait()` while files could still
    /// be written once space returned. With the fix the stream finishes
    /// promptly and nothing is copied.
    @MainActor
    func testParallelTransferObservesCancellationWhilePausedOnLowDisk() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Two distinct files → two parallel copy jobs (not internal duplicates).
        for index in 0..<2 {
            let day = String(format: "%02d", index + 2) // 02, 03 — valid dates
            let fileURL = sourceURL.appendingPathComponent("camera/IMG_202401\(day)_101010.jpg")
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data("payload-\(index)-\(String(repeating: "x", count: index + 1))".utf8).write(to: fileURL)
        }

        // Permanent low disk forces every copy worker to park in
        // `checkDiskSpace`; pin power/thermal so concurrency isn't throttled to 1.
        var executor = TransferExecutor()
        executor.freeDiskSpaceProvider = { _ in 0 }
        executor.isLowPowerModeEnabledProvider = { false }
        executor.thermalStateProvider = { .nominal }

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            ),
            transferExecutor: executor
        )

        let stream = try engine.start(
            RunConfiguration(
                mode: .transfer,
                sourcePath: sourceURL.path,
                destinationPath: destinationURL.path,
                verifyCopies: false,
                parallelTransferEnabled: true,
                workerCount: 2
            )
        )

        // Consume events; the moment a worker reports the low-disk pause, cancel.
        // If cancellation did not propagate to the GCD workers this loop would
        // never terminate (the run stays parked), so reaching the end of the
        // stream is itself the assertion that the fix works.
        var sawPause = false
        for try await event in stream {
            if case let .issue(issue) = event,
               issue.message.contains("Paused: Insufficient disk space") {
                sawPause = true
                engine.cancelCurrentRun()
            }
        }

        XCTAssertTrue(sawPause, "Expected the low-disk pause to be reported before cancellation")

        // Nothing may be copied into the destination after cancellation.
        let copiedMedia = FileManager.default
            .enumerator(at: destinationURL, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "jpg" } ?? []
        XCTAssertTrue(copiedMedia.isEmpty, "No media may be written after the run was cancelled: \(copiedMedia)")
    }

    @MainActor
    func testResumeTransferUsesPersistedRawQueueAndEmitsCopyOnlyEvents() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("incoming/photo.jpg")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("resume-data".utf8).write(to: fileURL)
        let identity = try FileIdentityHasher().hashIdentity(at: fileURL)

        let database = try OrganizerDatabase(url: destinationURL.appendingPathComponent(".organize_cache.db"))
        try database.enqueueQueuedJobs([
            QueuedCopyJob(
                sourcePath: fileURL.path,
                destinationPath: destinationURL.appendingPathComponent("2023/06/15/2023-06-15_001.jpg").path,
                hash: identity.rawValue,
                status: .pending
            ),
        ])
        database.close()

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )

        let stream = try engine.resume(
            RunConfiguration(
                mode: .transfer,
                sourcePath: sourceURL.path,
                destinationPath: destinationURL.path
            )
        )
        let events = try await Self.collect(stream)

        XCTAssertEqual(Self.render(events), [
            "startup",
            "dateHistogram:1",
            "phaseStarted:copy",
            "phaseProgress:copy:1/1",
            "phaseCompleted:copy",
            "complete:finished",
        ])

        let histogramBuckets = events.compactMap { event -> [DateHistogramBucket]? in
            if case let .dateHistogram(buckets) = event { return buckets }
            return nil
        }
        XCTAssertEqual(
            histogramBuckets,
            [[DateHistogramBucket(key: "2023-06", plannedCount: 1)]],
            "Resume must reconstruct the source-timeline histogram from the persisted queue so the Run screen's Timeline panel renders bars instead of the empty 'Scanning source' state."
        )

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }

        XCTAssertEqual(summary.status, .finished)
        XCTAssertEqual(summary.metrics.plannedCount, 1)
        XCTAssertEqual(summary.metrics.copiedCount, 1)
        XCTAssertEqual(summary.metrics.failedCount, 0)
        XCTAssertEqual(summary.metrics.dateHistogram, [DateHistogramBucket(key: "2023-06", plannedCount: 1)])

        let resumedFileURL = destinationURL.appendingPathComponent("2023/06/15/2023-06-15_001.jpg")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resumedFileURL.path))

        let resumedStatuses = try Self.withDatabaseWhenReady(at: destinationURL.appendingPathComponent(".organize_cache.db")) { database in
            try database.loadQueuedJobs().map(\.status)
        }
        XCTAssertEqual(resumedStatuses, [.copied])

        let resumedHashes = try Self.withDatabaseWhenReady(at: destinationURL.appendingPathComponent(".organize_cache.db")) { database in
            try database.loadRawCacheRecords(namespace: .destination).map(\.hash)
        }
        XCTAssertEqual(resumedHashes, [identity.rawValue])

        let logContents = try String(
            contentsOfFile: try XCTUnwrap(summary.artifacts.logFilePath),
            encoding: .utf8
        )
        XCTAssertTrue(logContents.contains("Found 1 pending jobs from interrupted session"))
        XCTAssertTrue(logContents.contains("Resumed session complete"))
    }

    // MARK: - Trial gate (free-trial step 4, T8)

    /// An engine for a resolved, locked customer, metered against `ledger`.
    ///
    /// The production authorizer rather than a stub, so these tests exercise the
    /// actual policy — including which refusal a locked customer gets — instead
    /// of a hand-written approximation of it.
    @MainActor
    private func meteredEngine(ledger: any TrialLedger) -> SwiftOrganizerEngine {
        SwiftOrganizerEngine(
            authorizer: EntitlementTrialAuthorizer(ledger: ledger) {
                TrialEntitlementSnapshot(state: .locked, accountKey: Self.testAccountKey)
            },
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )
    }

    private static let testAccountKey = "app-txn-1"

    /// The T8 acceptance criterion: a refused transfer leaves no queued rows, no
    /// receipt, no spool journal, and no media.
    ///
    /// Deliberately NOT a whole-destination byte-identity assertion — planning
    /// legitimately writes `.organize_cache.db` and the run log before the gate
    /// is reached, and asserting otherwise would make the test a lie about what
    /// "nothing happened" means here.
    @MainActor
    func testRefusedTransferEnqueuesNothingWritesNoReceiptAndCopiesNothing() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Two distinct files on distinct days, so the plan is two transfers and
        // neither is an internal duplicate of the other.
        for day in ["02", "03"] {
            let fileURL = sourceURL.appendingPathComponent("camera/IMG_202401\(day)_101010.jpg")
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("payload-\(day)".utf8).write(to: fileURL)
        }
        let sourceDigests = try Self.mediaDigests(under: sourceURL)

        // One file of allowance against a two-file plan.
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 1, dedupeFiles: 1))
        let engine = meteredEngine(ledger: ledger)

        let stream = try engine.start(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )

        do {
            _ = try await Self.collect(stream)
            XCTFail("A refused transfer must not run to completion")
        } catch let error as TrialAuthorizationError {
            guard case let .allowanceSpent(refusal) = error.refusal else {
                return XCTFail("A resolved locked customer is told the allowance is spent, got \(error.refusal)")
            }
            XCTAssertEqual(refusal.meter, .organize)
            XCTAssertEqual(refusal.requested, 2)
            XCTAssertEqual(refusal.remaining, 1)
        }

        let queuedJobs = try Self.withDatabaseWhenReady(
            at: destinationURL.appendingPathComponent(".organize_cache.db")
        ) { try $0.loadQueuedJobs() }
        XCTAssertTrue(queuedJobs.isEmpty, "A refused transfer must enqueue nothing, got \(queuedJobs)")

        let logsContents = (try? FileManager.default.contentsOfDirectory(
            at: destinationURL.appendingPathComponent(".organize_logs", isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(
            logsContents.filter { $0.lastPathComponent.hasPrefix("audit_receipt_") }.isEmpty,
            "A refused transfer must write no receipt, got \(logsContents)"
        )
        XCTAssertTrue(
            logsContents.filter { $0.pathExtension == "spool" }.isEmpty,
            "A refused transfer must write no spool journal, got \(logsContents)"
        )

        XCTAssertTrue(
            Self.mediaURLs(under: destinationURL).isEmpty,
            "A refused transfer must copy no media"
        )
        XCTAssertEqual(
            try Self.mediaDigests(under: sourceURL),
            sourceDigests,
            "A refused transfer must leave every source file exactly as it found it"
        )

        // A refusal writes nothing to the ledger either, so retrying after an
        // unlock starts from the same balance.
        XCTAssertEqual(try ledger.balance(accountKey: Self.testAccountKey).usage.organizeUsed, 0)
        XCTAssertTrue(try ledger.openReservations().isEmpty)
    }

    /// A run that is permitted charges the files that actually landed, and
    /// leaves no reservation open behind it.
    @MainActor
    func testCompletedTransferSettlesItsReservation() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("camera/IMG_20240102_101010.jpg")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("alpha".utf8).write(to: fileURL)

        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 10))
        let engine = meteredEngine(ledger: ledger)

        let stream = try engine.start(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        let events = try await Self.collect(stream)

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }
        XCTAssertEqual(summary.status, .finished)
        XCTAssertEqual(summary.metrics.copiedCount, 1)

        XCTAssertEqual(try ledger.balance(accountKey: Self.testAccountKey).usage.organizeUsed, 1)
        XCTAssertTrue(
            try ledger.openReservations().isEmpty,
            "A finished run must not leave its reservation open — an open reservation stays charged in full"
        )
    }

    /// Resuming an interrupted run must not charge for it twice, and must settle
    /// at the number of files that ended up in the destination — not at the
    /// larger number the original run reserved, and not at the size of the
    /// resumed batch alone.
    @MainActor
    func testResumeSettlesTheOriginalReservationWithoutChargingAgain() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("incoming/photo.jpg")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("resume-data".utf8).write(to: fileURL)
        let identity = try FileIdentityHasher().hashIdentity(at: fileURL)

        // The queue an interrupted run left behind: one file it already copied,
        // and one it never got to — both under the run's own ID.
        let interruptedRunID = UUID()
        let database = try OrganizerDatabase(url: destinationURL.appendingPathComponent(".organize_cache.db"))
        try database.enqueueQueuedJobs([
            QueuedCopyJob(
                sourcePath: "/already/copied.jpg",
                destinationPath: destinationURL.appendingPathComponent("2023/06/14/2023-06-14_001.jpg").path,
                hash: FileIdentity(size: 4, digest: "already-copied").rawValue,
                status: .copied,
                runID: interruptedRunID,
                mutationState: .finalized
            ),
            QueuedCopyJob(
                sourcePath: fileURL.path,
                destinationPath: destinationURL.appendingPathComponent("2023/06/15/2023-06-15_001.jpg").path,
                hash: identity.rawValue,
                status: .pending,
                runID: interruptedRunID
            ),
        ])
        database.close()

        // The reservation the interrupted run took up front, for the whole plan.
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 10))
        _ = try ledger.reserve(
            runID: interruptedRunID,
            accountKey: Self.testAccountKey,
            meter: .organize,
            count: 5,
            destinationRoot: destinationURL.path
        )
        XCTAssertEqual(
            try ledger.balance(accountKey: Self.testAccountKey).usage.organizeUsed, 5,
            "An open reservation is charged in full until it is settled"
        )

        let stream = try meteredEngine(ledger: ledger).resume(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        let events = try await Self.collect(stream)

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }
        XCTAssertEqual(summary.status, .finished)
        XCTAssertEqual(summary.metrics.copiedCount, 1)

        // 2 — the file the interrupted run copied plus the one this pass copied.
        // Not 5 (the reservation, which the resume must settle rather than
        // leave standing), not 6 (a second reservation stacked on top of it),
        // and not 1 (the resumed batch alone, which would let the work the first
        // pass did go uncharged).
        XCTAssertEqual(
            try ledger.balance(accountKey: Self.testAccountKey).usage.organizeUsed, 2,
            "A resume settles the reservation it inherited, at the count the whole run landed"
        )
        XCTAssertTrue(try ledger.openReservations().isEmpty)
    }

    /// A queue that cannot be attributed to a reservation is metered, not waved
    /// through. Rows enqueued before run IDs existed carry none, so resuming
    /// them must not become a way to copy for free.
    @MainActor
    func testResumeOfAnUnattributableQueueIsRefusedWhenTheAllowanceIsSpent() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("incoming/photo.jpg")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy-data".utf8).write(to: fileURL)
        let identity = try FileIdentityHasher().hashIdentity(at: fileURL)
        let resumedDestination = destinationURL.appendingPathComponent("2023/06/15/2023-06-15_001.jpg")

        let database = try OrganizerDatabase(url: destinationURL.appendingPathComponent(".organize_cache.db"))
        try database.enqueueQueuedJobs([
            // No run ID — the pre-T3 shape.
            QueuedCopyJob(
                sourcePath: fileURL.path,
                destinationPath: resumedDestination.path,
                hash: identity.rawValue,
                status: .pending
            ),
        ])
        database.close()

        // The whole allowance is already spent by an unrelated, settled run.
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 1, dedupeFiles: 1))
        let spentRunID = UUID()
        _ = try ledger.reserve(
            runID: spentRunID, accountKey: Self.testAccountKey,
            meter: .organize, count: 1, destinationRoot: nil
        )
        try ledger.finalize(runID: spentRunID, actualCount: 1)

        let stream = try meteredEngine(ledger: ledger).resume(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )

        do {
            _ = try await Self.collect(stream)
            XCTFail("A resume with no covering reservation must be metered like any other transfer")
        } catch let error as TrialAuthorizationError {
            guard case .allowanceSpent = error.refusal else {
                return XCTFail("Expected allowanceSpent, got \(error.refusal)")
            }
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: resumedDestination.path),
            "A refused resume must copy nothing"
        )
        let statuses = try Self.withDatabaseWhenReady(
            at: destinationURL.appendingPathComponent(".organize_cache.db")
        ) { try $0.loadQueuedJobs().map(\.status) }
        XCTAssertEqual(statuses, [.pending], "The queue is left exactly as it was, so an unlock can resume it")
    }

    /// The gate is the only suspension point between the last cancellation
    /// check and the first mutation, and resolving entitlement can wait on the
    /// App Store — so a cancel can land inside it.
    ///
    /// By then `RunSessionStore.cancelCurrentRun()` has already released the
    /// destination lease, so enqueuing or copying past this point would mutate
    /// the destination with no lock held. The reservation is given back because
    /// this is the one moment where nothing can have been mutated under it.
    @MainActor
    func testCancellingDuringAuthorizationEnqueuesNothingAndReleasesTheReservation() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("camera/IMG_20240102_101010.jpg")
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("alpha".utf8).write(to: fileURL)

        let authorizer = SlowAuthorizer()
        let engine = SwiftOrganizerEngine(
            authorizer: authorizer,
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )
        // The cancel happens while the gate is suspended, which is exactly the
        // window a real StoreKit round-trip opens.
        authorizer.whileAuthorizing = { [weak engine] in
            await MainActor.run {
                guard let engine else { return }
                engine.cancelCurrentRun()
            }
        }

        let stream = try engine.start(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        let events = try await Self.collect(stream)

        XCTAssertNil(
            events.last.flatMap { event -> RunSummary? in
                if case let .complete(summary) = event { return summary }
                return nil
            },
            "A run cancelled inside the gate finishes without a completion summary"
        )
        XCTAssertTrue(
            Self.mediaURLs(under: destinationURL).isEmpty,
            "Nothing may be copied after the lease was released"
        )

        let queuedJobs = try Self.withDatabaseWhenReady(
            at: destinationURL.appendingPathComponent(".organize_cache.db")
        ) { try $0.loadQueuedJobs() }
        XCTAssertTrue(queuedJobs.isEmpty, "Nothing may be enqueued after the lease was released, got \(queuedJobs)")

        XCTAssertEqual(
            authorizer.releasedRunIDs.count, 1,
            "The reservation is given back: nothing was enqueued, copied, or written under it"
        )
        XCTAssertEqual(authorizer.finalizedRunIDs, [], "Nothing landed, so nothing is settled")
    }

    // MARK: - Reorganize (free-trial step 4, T10)

    /// Reorganize requires the unlock outright. It is not metered — no
    /// reservation is taken, so there is nothing to settle and nothing to
    /// refund — and a locked customer is told they need the unlock rather than
    /// that their allowance is spent.
    @MainActor
    func testReorganizeRequiresTheUnlock() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        for name in ["2024-04-08_001.HEIC", "2024-04-08_002.HEIC", "2024-04-09_001.HEIC"] {
            try Data("x".utf8).write(to: destinationURL.appendingPathComponent(name))
        }

        // A full allowance, to prove reorganize is gated on the unlock rather
        // than on the meter.
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100))
        let engine = meteredEngine(ledger: ledger)
        let stream = try engine.reorganize(
            destinationRoot: destinationURL.path,
            targetStructure: .yyyyMMDD
        )

        do {
            _ = try await Self.collect(stream)
            XCTFail("A locked customer must not be able to reorganize")
        } catch let error as TrialAuthorizationError {
            XCTAssertEqual(
                error.refusal, .requiresUnlock,
                "Reorganize is unlock-only, so the refusal must never claim the allowance is spent"
            )
        }

        // Nothing moved: the flat files are still flat.
        for name in ["2024-04-08_001.HEIC", "2024-04-08_002.HEIC", "2024-04-09_001.HEIC"] {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: destinationURL.appendingPathComponent(name).path),
                "A refused reorganize must move nothing: \(name) was moved"
            )
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destinationURL.appendingPathComponent("2024/04/08/2024-04-08_001.HEIC").path
        ))

        let logs = (try? FileManager.default.contentsOfDirectory(
            at: destinationURL.appendingPathComponent(".organize_logs", isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(
            logs.filter { $0.lastPathComponent.hasPrefix("reorganize_audit_receipt_") }.isEmpty,
            "A refused reorganize must write no receipt, got \(logs)"
        )

        // Unlock-only means unmetered: no reservation was taken either way.
        XCTAssertEqual(try ledger.balance(accountKey: Self.testAccountKey).usage.organizeUsed, 0)
        XCTAssertTrue(try ledger.openReservations().isEmpty)
    }

    /// An unlocked customer reorganizes normally, and still without a
    /// reservation — the unlock is the whole check.
    @MainActor
    func testReorganizeProceedsWhenUnlocked() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        for name in ["2024-04-08_001.HEIC", "2024-04-09_001.HEIC"] {
            try Data("x".utf8).write(to: destinationURL.appendingPathComponent(name))
        }

        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100))
        let engine = SwiftOrganizerEngine(
            authorizer: EntitlementTrialAuthorizer(ledger: ledger) {
                TrialEntitlementSnapshot(
                    state: .unlocked(reason: .inAppPurchase),
                    accountKey: Self.testAccountKey
                )
            },
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )

        let stream = try engine.reorganize(
            destinationRoot: destinationURL.path,
            targetStructure: .yyyyMMDD
        )
        let events = try await Self.collect(stream)

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }
        XCTAssertEqual(summary.status, .reorganized)
        XCTAssertEqual(summary.metrics.movedCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationURL.appendingPathComponent("2024/04/08/2024-04-08_001.HEIC").path
        ))
        XCTAssertEqual(try ledger.balance(accountKey: Self.testAccountKey).usage.organizeUsed, 0)
    }

    /// A layout that is already correct is reported as such for free. Refusing
    /// there would put a paywall in front of the word "no" — the same reason an
    /// empty organize run is permitted whatever the balance.
    @MainActor
    func testAlreadyCorrectLayoutIsReportedWithoutRequiringTheUnlock() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        let nestedURL = destinationURL.appendingPathComponent("2024/04/08", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: nestedURL.appendingPathComponent("2024-04-08_001.HEIC"))

        let engine = meteredEngine(
            ledger: InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100))
        )
        let stream = try engine.reorganize(
            destinationRoot: destinationURL.path,
            targetStructure: .yyyyMMDD
        )
        let events = try await Self.collect(stream)

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }
        XCTAssertEqual(summary.status, .nothingToReorganize)
        XCTAssertEqual(summary.metrics.movedCount, 0)
    }

    /// An unrestricted authorizer is the CLI and Developer ID channel, and must
    /// behave exactly as it did before the gate existed.
    @MainActor
    func testUnrestrictedAuthorizerTransfersWithoutMetering() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        for day in ["02", "03", "04"] {
            let fileURL = sourceURL.appendingPathComponent("camera/IMG_202401\(day)_101010.jpg")
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data("payload-\(day)".utf8).write(to: fileURL)
        }

        let stream = try makeEngine().start(
            RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        let events = try await Self.collect(stream)

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected completion summary")
        }
        XCTAssertEqual(summary.status, .finished)
        XCTAssertEqual(summary.metrics.copiedCount, 3)
    }

    private static func mediaURLs(under root: URL) -> [URL] {
        FileManager.default
            .enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension.lowercased() == "jpg" } ?? []
    }

    /// Path → content digest, so "unchanged" means the bytes, not just the name.
    private static func mediaDigests(under root: URL) throws -> [String: String] {
        let hasher = FileIdentityHasher()
        var digests: [String: String] = [:]
        for url in mediaURLs(under: root) {
            digests[url.path] = try hasher.hashIdentity(at: url).rawValue
        }
        return digests
    }

    private static func collect(_ stream: AsyncThrowingStream<RunEvent, Error>) async throws -> [RunEvent] {
        var events: [RunEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private static func withDatabaseWhenReady<T>(
        at url: URL,
        attempts: Int = 50,
        delayNanoseconds: UInt64 = 20_000_000,
        body: (OrganizerDatabase) throws -> T
    ) throws -> T {
        var lastError: Error?

        for attempt in 0..<attempts {
            do {
                let database = try OrganizerDatabase(url: url, readOnly: true)
                defer { database.close() }
                return try body(database)
            } catch {
                lastError = error
                if attempt + 1 < attempts {
                    Thread.sleep(forTimeInterval: TimeInterval(delayNanoseconds) / 1_000_000_000)
                }
            }
        }

        throw lastError ?? TestFailure.expectedFailure("Timed out waiting for database access")
    }

    private static func render(_ events: [RunEvent]) -> [String] {
        events.map {
            switch $0 {
            case .startup:
                return "startup"
            case let .phaseStarted(phase, _):
                return "phaseStarted:\(phase.rawValue)"
            case let .phaseCompleted(phase, _):
                return "phaseCompleted:\(phase.rawValue)"
            case let .copyPlanReady(count):
                return "copyPlanReady:\(count)"
            case let .complete(summary):
                return "complete:\(summary.status.rawValue)"
            case let .issue(issue):
                return "issue:\(issue.message)"
            case let .phaseProgress(phase, completed, total, _, _, _):
                return "phaseProgress:\(phase.rawValue):\(completed)/\(total)"
            case let .prompt(message):
                return "prompt:\(message)"
            case let .dateHistogram(buckets):
                return "dateHistogram:\(buckets.count)"
            }
        }
    }
}

extension SwiftOrganizerEngineIntegrationTests {
    @MainActor
    func testRevertStreamsProgressAndCompletesWithRevertedStatus() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Drop a real file in the destination, hash it, and synthesize a receipt
        // that points at it with the matching hash.
        let photoURL = destinationURL.appendingPathComponent("2024/04/08/2024-04-08_001.HEIC", isDirectory: false)
        try FileManager.default.createDirectory(
            at: photoURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("photo-bytes".utf8).write(to: photoURL)
        let identity = try FileIdentityHasher().hashIdentity(at: photoURL)

        let receiptURL = destinationURL.appendingPathComponent("audit_receipt_test.json")
        let receiptJSON = """
        {
            "timestamp": "2026-04-24T10:00:00",
            "total_jobs": 1,
            "status": "COMPLETED",
            "transfers": [
                { "source": "/src/photo.HEIC", "dest": "\(photoURL.path)", "hash": "\(identity.rawValue)" }
            ]
        }
        """
        try Data(receiptJSON.utf8).write(to: receiptURL)

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(profiles: [], profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml"))
        )

        let stream = try engine.revert(receiptURL: receiptURL, destinationRoot: destinationURL.path)

        var sawStartup = false
        var sawPhaseStarted = false
        var sawPhaseProgress = false
        var sawPhaseCompleted = false
        var summary: RunSummary?

        for try await event in stream {
            switch event {
            case .startup: sawStartup = true
            case .phaseStarted(let phase, _) where phase == .revert: sawPhaseStarted = true
            case .phaseProgress(let phase, _, _, _, _, _) where phase == .revert: sawPhaseProgress = true
            case .phaseCompleted(let phase, _) where phase == .revert: sawPhaseCompleted = true
            case let .complete(s): summary = s
            default: break
            }
        }

        XCTAssertTrue(sawStartup)
        XCTAssertTrue(sawPhaseStarted)
        XCTAssertTrue(sawPhaseProgress)
        XCTAssertTrue(sawPhaseCompleted)
        XCTAssertEqual(summary?.status, .reverted)
        XCTAssertEqual(summary?.metrics.revertedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: photoURL.path))
    }

    @MainActor
    func testReorganizeStreamsMovesAndCompletesWithReorganizedStatus() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        // Three flat files; reorganize → YYYY/MM/DD.
        for name in ["2024-04-08_001.HEIC", "2024-04-08_002.HEIC", "2024-04-09_001.HEIC"] {
            try Data("x".utf8).write(to: destinationURL.appendingPathComponent(name))
        }

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(profiles: [], profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml"))
        )

        let stream = try engine.reorganize(
            destinationRoot: destinationURL.path,
            targetStructure: .yyyyMMDD
        )

        var planReadyCount = 0
        var summary: RunSummary?
        var phaseProgressCount = 0
        for try await event in stream {
            switch event {
            case let .copyPlanReady(count): planReadyCount = count
            case .phaseProgress(let phase, _, _, _, _, _) where phase == .reorganize: phaseProgressCount += 1
            case let .complete(s): summary = s
            default: break
            }
        }

        XCTAssertEqual(planReadyCount, 3)
        XCTAssertEqual(phaseProgressCount, 3)
        XCTAssertEqual(summary?.status, .reorganized)
        XCTAssertEqual(summary?.metrics.movedCount, 3)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationURL.appendingPathComponent("2024/04/08/2024-04-08_001.HEIC").path
        ))
    }

    @MainActor
    func testReorganizeReportsNothingToReorganizeForAlreadyConformantLayout() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        let nestedDir = destinationURL.appendingPathComponent("2024/04/08", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: nestedDir.appendingPathComponent("2024-04-08_001.HEIC"))

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(profiles: [], profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml"))
        )

        let stream = try engine.reorganize(
            destinationRoot: destinationURL.path,
            targetStructure: .yyyyMMDD
        )

        var summary: RunSummary?
        for try await event in stream {
            if case let .complete(s) = event { summary = s }
        }

        XCTAssertEqual(summary?.status, .nothingToReorganize)
        XCTAssertEqual(summary?.metrics.movedCount, 0)
    }

    @MainActor
    func testRevertThrowsForMissingReceipt() throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let missingReceipt = destinationURL.appendingPathComponent("does-not-exist.json")

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(profiles: [], profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml"))
        )

        XCTAssertThrowsError(try engine.revert(receiptURL: missingReceipt, destinationRoot: destinationURL.path))
    }

    @MainActor
    func testRevertQuarantinesMalformedReceipt() throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let receiptURL = destinationURL.appendingPathComponent("audit_receipt_bad.json")
        try Data("{not valid json".utf8).write(to: receiptURL)

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(profiles: [], profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml"))
        )

        XCTAssertThrowsError(try engine.revert(receiptURL: receiptURL, destinationRoot: destinationURL.path)) { error in
            guard case RevertExecutorError.invalidReceipt = error else {
                XCTFail("Expected invalidReceipt, got \(error)")
                return
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: receiptURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: destinationURL.appendingPathComponent("audit_receipt_bad.corrupt").path
        ))
    }

    @MainActor
    func testRevertDoesNotQuarantineUnreadableReceipt() throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let receiptURL = destinationURL.appendingPathComponent("audit_receipt_directory.json", isDirectory: true)
        try FileManager.default.createDirectory(at: receiptURL, withIntermediateDirectories: true)

        let engine = SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(profiles: [], profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml"))
        )

        XCTAssertThrowsError(try engine.revert(receiptURL: receiptURL, destinationRoot: destinationURL.path)) { error in
            guard case RevertExecutorError.receiptUnreadable = error else {
                XCTFail("Expected receiptUnreadable, got \(error)")
                return
            }
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: receiptURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: destinationURL.appendingPathComponent("audit_receipt_directory.corrupt").path
        ))
    }

    // MARK: - Source/destination disjointness preflight

    @MainActor
    private func makeEngine() -> SwiftOrganizerEngine {
        SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )
    }

    private func assertOverlapRejected(
        _ error: Error,
        _ expected: SourceDestinationDisjointness.Conflict,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let OrganizerEngineError.sourceOverlapsDestination(conflict) = error else {
            XCTFail("Expected sourceOverlapsDestination, got \(error)", file: file, line: line)
            return
        }
        XCTAssertEqual(conflict, expected, file: file, line: line)
    }

    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightRejectsSourceInsideDestination() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        let sourceURL = destinationURL.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        do {
            _ = try await makeEngine().preflight(
                RunConfiguration(mode: .preview, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
            )
            XCTFail("Preflight must reject a source inside the destination")
        } catch {
            assertOverlapRejected(error, .sourceInsideDestination)
        }
    }

    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightRejectsDestinationInsideSource() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("photos", isDirectory: true)
        let destinationURL = sourceURL.appendingPathComponent("organized", isDirectory: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        do {
            _ = try await makeEngine().preflight(
                RunConfiguration(mode: .transfer, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
            )
            XCTFail("Preflight must reject a destination inside the source")
        } catch {
            assertOverlapRejected(error, .destinationInsideSource)
        }
    }

    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightRejectsEqualSourceAndDestination() async throws {
        let folderURL = temporaryDirectoryURL.appendingPathComponent("same", isDirectory: true)
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)

        do {
            _ = try await makeEngine().preflight(
                RunConfiguration(mode: .preview, sourcePath: folderURL.path, destinationPath: folderURL.path)
            )
            XCTFail("Preflight must reject source == destination")
        } catch {
            assertOverlapRejected(error, .sourceInsideDestination)
        }
    }

    /// The guard runs at every engine entry point, not only preflight —
    /// a destination that changed after folder selection cannot slip an
    /// overlapping pair into `start` or `resume` (TOCTOU).
    // AGENTS-INVARIANT: 21
    @MainActor
    func testStartAndResumeRejectOverlapEvenWhenPreflightWasSkipped() throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        let sourceURL = destinationURL.appendingPathComponent("incoming", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

        let configuration = RunConfiguration(
            mode: .transfer,
            sourcePath: sourceURL.path,
            destinationPath: destinationURL.path
        )
        let engine = makeEngine()

        XCTAssertThrowsError(try engine.start(configuration)) { error in
            assertOverlapRejected(error, .sourceInsideDestination)
        }
        XCTAssertThrowsError(try engine.resume(configuration)) { error in
            assertOverlapRejected(error, .sourceInsideDestination)
        }
    }

    /// A symlinked alias of the destination (or a folder inside it) used
    /// as the source must be caught: containment resolves existing
    /// symlinks before comparing.
    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightRejectsSymlinkedSourceAliasIntoDestination() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        let insideURL = destinationURL.appendingPathComponent("2024", isDirectory: true)
        try FileManager.default.createDirectory(at: insideURL, withIntermediateDirectories: true)
        let aliasURL = temporaryDirectoryURL.appendingPathComponent("alias-source")
        try FileManager.default.createSymbolicLink(at: aliasURL, withDestinationURL: insideURL)

        do {
            _ = try await makeEngine().preflight(
                RunConfiguration(mode: .preview, sourcePath: aliasURL.path, destinationPath: destinationURL.path)
            )
            XCTFail("Preflight must reject a symlinked source alias inside the destination")
        } catch {
            assertOverlapRejected(error, .sourceInsideDestination)
        }
    }

    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightAcceptsDisjointSiblingFolders() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let preflight = try await makeEngine().preflight(
            RunConfiguration(mode: .preview, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        XCTAssertEqual(preflight.resolvedSourcePath, sourceURL.path)
        XCTAssertEqual(preflight.resolvedDestinationPath, destinationURL.path)
    }

    /// A sibling folder whose name shares a prefix with the destination
    /// ("dest" vs "dest-archive") must NOT be treated as overlapping —
    /// containment is path-component-based, not string-prefix-based.
    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightAcceptsSharedNamePrefixSiblings() async throws {
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("dest-archive", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let preflight = try await makeEngine().preflight(
            RunConfiguration(mode: .preview, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        XCTAssertEqual(preflight.resolvedSourcePath, sourceURL.path)
    }

    /// The user-facing copy for overlap rejections must be plain,
    /// actionable, and reassure that nothing was changed.
    @MainActor
    func testOverlapErrorCopyIsPlainAndReassuring() {
        let sourceInside = OrganizerEngineError.sourceOverlapsDestination(.sourceInsideDestination)
        let destinationInside = OrganizerEngineError.sourceOverlapsDestination(.destinationInsideSource)

        let sourceText = sourceInside.errorDescription ?? ""
        let destinationText = destinationInside.errorDescription ?? ""

        XCTAssertTrue(sourceText.contains("inside the destination folder"))
        XCTAssertTrue(sourceText.contains("No files were changed."))
        XCTAssertTrue(destinationText.contains("inside the source folder"))
        XCTAssertTrue(destinationText.contains("No files were changed."))
    }
}

/// Permits everything, but runs `whileAuthorizing` inside the gate's suspension
/// — standing in for a StoreKit round-trip slow enough for the user to cancel
/// during it — and records what was settled or given back.
private final class SlowAuthorizer: TrialAuthorizing, @unchecked Sendable {
    private let lock = NSLock()
    private var released: [UUID] = []
    private var finalized: [UUID] = []

    /// Set before the run starts and not mutated afterwards.
    var whileAuthorizing: (@Sendable () async -> Void)?

    var releasedRunIDs: [UUID] { lock.withLock { released } }
    var finalizedRunIDs: [UUID] { lock.withLock { finalized } }

    func authorizeMeteredWork(
        runID: UUID,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) async -> TrialAuthorization {
        await whileAuthorizing?()
        return .permitted
    }

    func finalizeMeteredWork(runID: UUID, actualCount: Int) async {
        lock.withLock { finalized.append(runID) }
    }

    func releaseMeteredWork(runID: UUID) async {
        lock.withLock { released.append(runID) }
    }

    func authorizeUnlockOnlyWork() async -> TrialAuthorization { .permitted }
}

private final class TestProfilesRepository: ProfilesRepositorying {
    private var profiles: [Profile]
    private let storedProfilesFileURL: URL

    init(profiles: [Profile], profilesFileURL: URL) {
        self.profiles = profiles
        self.storedProfilesFileURL = profilesFileURL
    }

    func profilesFileURL() -> URL {
        storedProfilesFileURL
    }

    func loadProfiles() throws -> [Profile] {
        profiles
    }

    func save(profile: Profile) throws {
        profiles.removeAll { $0.name == profile.name }
        profiles.append(profile)
    }

    func deleteProfile(named name: String) throws {
        profiles.removeAll { $0.name == name }
    }
}
