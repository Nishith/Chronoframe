import Darwin
import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// The destination is user-selected and may already hold anything, so the
/// record files Chronoframe writes there must never be written through a link
/// planted at a name Chronoframe is about to use: the organize receipt's
/// finalization temp and transfer spool, the dedupe spool journal, and the
/// dry-run report and preview-review files.
final class DestinationRecordWritersNoFollowTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DestinationRecordNoFollow-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeSentinel(in directory: URL) throws -> URL {
        let sentinel = directory.appendingPathComponent("sentinel-\(UUID().uuidString).txt")
        try Data("SENTINEL".utf8).write(to: sentinel)
        return sentinel
    }

    private func assertSentinelUntouched(_ sentinel: URL, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(
            try? String(contentsOf: sentinel, encoding: .utf8),
            "SENTINEL",
            "A planted link must never receive Chronoframe's record data",
            file: file,
            line: line
        )
    }

    // MARK: - Organize receipt finalization and transfer spool

    private let receiptRunID = UUID()
    private let receiptCreatedAt = Date(timeIntervalSince1970: 1_790_000_000)

    private func organizeLogsDirectory(in destination: URL) throws -> URL {
        let logs = destination.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        return logs
    }

    private func receiptStem(in logs: URL) -> String {
        TransferExecutor.uniqueReceiptStem(
            in: logs,
            createdAt: receiptCreatedAt,
            runID: receiptRunID,
            fileManager: .default
        )
    }

    private func finishReceipt(in destination: URL) throws {
        let writer = try StreamingAuditReceiptWriter(
            destinationRoot: destination,
            runID: receiptRunID,
            createdAt: receiptCreatedAt
        )
        try writer.appendTransfer(sourcePath: "/src/a.jpg", destinationPath: "/dst/a.jpg", hash: "h")
        try writer.finish(
            status: "COMPLETED",
            abortReason: nil,
            attemptedJobs: 1,
            failedCount: 0,
            verifyCopies: false
        )
    }

    private func assertFinalizedReceipt(in logs: URL, stem: String, planted: String, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try Data(contentsOf: logs.appendingPathComponent("\(stem).json"))
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any], file: file, line: line)
        XCTAssertEqual(payload["status"] as? String, "COMPLETED", file: file, line: line)
        XCTAssertEqual((payload["transfers"] as? [[String: Any]])?.count, 1, file: file, line: line)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: logs.path)
            .filter { $0.hasSuffix(".tmp") && $0 != planted }
        XCTAssertEqual(leftovers, [], "Finalization must leave no temporary file of its own behind", file: file, line: line)
    }

    // AGENTS-INVARIANT: 26
    func testSymlinkAtReceiptFinalizationTempNameIsNeverWrittenThrough() throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let stem = receiptStem(in: logs)
        try FileManager.default.createSymbolicLink(
            at: logs.appendingPathComponent("\(stem).json.tmp"),
            withDestinationURL: sentinel
        )

        try finishReceipt(in: destination)

        assertSentinelUntouched(sentinel)
        try assertFinalizedReceipt(in: logs, stem: stem, planted: "\(stem).json.tmp")
    }

    // AGENTS-INVARIANT: 26
    func testHardLinkAtReceiptFinalizationTempNameIsNeverWrittenThrough() throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let stem = receiptStem(in: logs)
        try FileManager.default.linkItem(at: sentinel, to: logs.appendingPathComponent("\(stem).json.tmp"))

        try finishReceipt(in: destination)

        assertSentinelUntouched(sentinel)
        try assertFinalizedReceipt(in: logs, stem: stem, planted: "\(stem).json.tmp")
    }

    // AGENTS-INVARIANT: 26
    func testDanglingSymlinkAtTransferSpoolNameIsRefusedAndNothingIsCreatedThroughIt() throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let outside = try makeDirectory().appendingPathComponent("created-through-link.txt")
        let stem = receiptStem(in: logs)
        try FileManager.default.createSymbolicLink(
            at: logs.appendingPathComponent("\(stem).transfers.tmp"),
            withDestinationURL: outside
        )

        XCTAssertThrowsError(
            try StreamingAuditReceiptWriter(
                destinationRoot: destination,
                runID: receiptRunID,
                createdAt: receiptCreatedAt
            )
        ) { error in
            XCTAssertTrue(error is DestinationMetadataUnsafeError, "got \(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
    }

    // MARK: - Organize receipt: spool read-back, retry and recovery

    private func receiptStatus(at url: URL) throws -> String? {
        let data = try Data(contentsOf: url)
        return (try JSONSerialization.jsonObject(with: data) as? [String: Any])?["status"] as? String
    }

    private let forgedSpoolBody = #"    {"source":"/elsewhere/forged.jpg","destination":"/dst/forged.jpg","hash":"x"}"#

    private func assertSpoolSwapIsRefusedAtFinalization(
        swapIn: (_ spool: URL, _ sentinel: URL) throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let stem = receiptStem(in: logs)
        let writer = try StreamingAuditReceiptWriter(
            destinationRoot: destination,
            runID: receiptRunID,
            createdAt: receiptCreatedAt
        )
        try writer.appendTransfer(sourcePath: "/src/a.jpg", destinationPath: "/dst/a.jpg", hash: "h")
        let spool = logs.appendingPathComponent("\(stem).transfers.tmp")
        try FileManager.default.removeItem(at: spool)
        try swapIn(spool, sentinel)

        XCTAssertThrowsError(
            try writer.finish(status: "COMPLETED", abortReason: nil, attemptedJobs: 1, failedCount: 0, verifyCopies: false),
            file: file,
            line: line
        ) { error in
            XCTAssertTrue(error is DestinationMetadataUnsafeError, "got \(error)", file: file, line: line)
        }

        XCTAssertEqual(
            try receiptStatus(at: logs.appendingPathComponent("\(stem).json")),
            "PENDING",
            "A refused finalization must leave the PENDING receipt for recovery",
            file: file,
            line: line
        )
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: logs.path)
            .filter { $0.hasSuffix(".tmp") && $0 != "\(stem).transfers.tmp" }
        XCTAssertEqual(leftovers, [], "A refused finalization must remove its own temporary file", file: file, line: line)
        XCTAssertEqual(
            try String(contentsOf: sentinel, encoding: .utf8),
            forgedSpoolBody,
            "The planted file must not be written to",
            file: file,
            line: line
        )
    }

    // AGENTS-INVARIANT: 26
    func testSpoolSwappedForSymlinkIsNotEmbeddedInTheFinalizedReceipt() throws {
        try assertSpoolSwapIsRefusedAtFinalization { spool, sentinel in
            try Data(self.forgedSpoolBody.utf8).write(to: sentinel)
            try FileManager.default.createSymbolicLink(at: spool, withDestinationURL: sentinel)
        }
    }

    // AGENTS-INVARIANT: 26
    func testSpoolSwappedForAnotherRegularFileIsNotEmbeddedInTheFinalizedReceipt() throws {
        try assertSpoolSwapIsRefusedAtFinalization { spool, sentinel in
            try Data(self.forgedSpoolBody.utf8).write(to: sentinel)
            try Data(self.forgedSpoolBody.utf8).write(to: spool)
        }
    }

    func testFinalizationCanBeRetriedAfterAFailedRenameAndLeavesNoTemporaryFile() throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let stem = receiptStem(in: logs)
        let writer = try StreamingAuditReceiptWriter(
            destinationRoot: destination,
            runID: receiptRunID,
            createdAt: receiptCreatedAt
        )
        try writer.appendTransfer(sourcePath: "/src/a.jpg", destinationPath: "/dst/a.jpg", hash: "h")
        // A directory where the receipt belongs makes the final rename fail.
        let receipt = logs.appendingPathComponent("\(stem).json")
        try FileManager.default.removeItem(at: receipt)
        try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: false)

        XCTAssertThrowsError(
            try writer.finish(status: "COMPLETED", abortReason: nil, attemptedJobs: 1, failedCount: 0, verifyCopies: false)
        )
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: logs.path).filter { $0.hasSuffix(".tmp") && $0 != "\(stem).transfers.tmp" },
            []
        )

        try FileManager.default.removeItem(at: receipt)
        try writer.finish(status: "COMPLETED", abortReason: nil, attemptedJobs: 1, failedCount: 0, verifyCopies: false)

        try assertFinalizedReceipt(in: logs, stem: stem, planted: "")
    }

    private func leaveInterruptedRun(in destination: URL) throws -> (logs: URL, stem: String) {
        let logs = try organizeLogsDirectory(in: destination)
        let stem = receiptStem(in: logs)
        do {
            let writer = try StreamingAuditReceiptWriter(
                destinationRoot: destination,
                runID: receiptRunID,
                createdAt: receiptCreatedAt
            )
            try writer.appendTransfer(sourcePath: "/src/a.jpg", destinationPath: "/dst/a.jpg", hash: "h")
        }
        return (logs, stem)
    }

    // AGENTS-INVARIANT: 26
    func testRecoveryDoesNotReadAJournalThatIsNowALink() throws {
        let destination = try makeDirectory()
        let (logs, stem) = try leaveInterruptedRun(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        try Data(forgedSpoolBody.utf8).write(to: sentinel)
        let spool = logs.appendingPathComponent("\(stem).transfers.tmp")
        try FileManager.default.removeItem(at: spool)
        try FileManager.default.createSymbolicLink(at: spool, withDestinationURL: sentinel)

        XCTAssertEqual(TransferExecutor().recoverInterruptedRuns(at: destination), 0)

        XCTAssertEqual(try receiptStatus(at: logs.appendingPathComponent("\(stem).json")), "PENDING")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: spool.path), "The planted link is left for the user to look at")
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), forgedSpoolBody)
    }

    // AGENTS-INVARIANT: 26
    func testRecoveryNeverWritesThroughALinkAtItsOldTemporaryName() throws {
        let destination = try makeDirectory()
        let (logs, stem) = try leaveInterruptedRun(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let receipt = logs.appendingPathComponent("\(stem).json")
        try FileManager.default.createSymbolicLink(
            at: receipt.appendingPathExtension("recovery.tmp"),
            withDestinationURL: sentinel
        )

        XCTAssertEqual(TransferExecutor().recoverInterruptedRuns(at: destination), 1)

        assertSentinelUntouched(sentinel)
        XCTAssertEqual(try receiptStatus(at: receipt), "ABORTED")
        let data = try Data(contentsOf: receipt)
        let payload = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual((payload["transfers"] as? [[String: Any]])?.count, 1, "The journalled transfer is kept")
    }

    // MARK: - Dedupe spool journal

    // The receipt name carries the start time to the second and the spool name is
    // `<receipt>.json.spool`, so a fixed clock tells the test the exact name the
    // run is about to use.
    private let dedupeStart = Date(timeIntervalSince1970: 1_790_000_000)

    private func dedupeReceiptURL(in logs: URL, runID: UUID) throws -> URL {
        try DeduplicateExecutor.makeReceiptURL(logsDirectory: logs, runID: runID, createdAt: dedupeStart)
    }

    private func runDedupeCommit(destination: URL, target: URL, runID: UUID) async -> Error? {
        let plan = DeduplicationPlan(items: [
            DeduplicationPlan.Item(
                path: target.path,
                sizeBytes: 64,
                owningClusterID: UUID(),
                owningClusterKind: .exactDuplicate,
                pairOrigin: nil,
                expectedIdentity: testFileIdentity(at: target)
            )
        ])
        let start = dedupeStart
        let stream = DeduplicateExecutor(now: { start }).commit(
            plan: plan,
            destinationRoot: destination.path,
            hardDelete: false,
            runID: runID
        )
        do {
            for try await _ in stream {}
        } catch {
            return error
        }
        return nil
    }

    private func dedupeReceipts(in logs: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: logs.path)
            .filter { $0.hasPrefix("dedupe_audit_receipt_") && $0.hasSuffix(".json") }
    }

    private func makeDedupeVictim(in destination: URL) throws -> URL {
        let target = destination.appendingPathComponent("victim.jpg")
        try Data(repeating: 0x42, count: 64).write(to: target)
        return target
    }

    // AGENTS-INVARIANT: 26
    func testHardLinkAtDedupeSpoolNameIsRefusedBeforeAnyFileMoves() async throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let target = try makeDedupeVictim(in: destination)
        let runID = UUID()
        try FileManager.default.linkItem(
            at: sentinel,
            to: DeduplicateExecutor.spoolURL(for: try dedupeReceiptURL(in: logs, runID: runID))
        )

        let error = await runDedupeCommit(destination: destination, target: target, runID: runID)

        XCTAssertTrue(error is ReceiptPreflightError, "got \(String(describing: error))")
        assertSentinelUntouched(sentinel)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "Nothing may move once the journal is refused")
    }

    // AGENTS-INVARIANT: 26
    func testDanglingSymlinkAtDedupeSpoolNameIsRefusedAndNothingIsCreatedThroughIt() async throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let outside = try makeDirectory().appendingPathComponent("created-through-link.txt")
        let target = try makeDedupeVictim(in: destination)
        let runID = UUID()
        try FileManager.default.createSymbolicLink(
            at: DeduplicateExecutor.spoolURL(for: try dedupeReceiptURL(in: logs, runID: runID)),
            withDestinationURL: outside
        )

        let error = await runDedupeCommit(destination: destination, target: target, runID: runID)

        XCTAssertTrue(error is ReceiptPreflightError, "got \(String(describing: error))")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    // AGENTS-INVARIANT: 26
    func testRefusedDedupeSpoolLeavesNoPendingReceiptBehind() async throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let target = try makeDedupeVictim(in: destination)
        let runID = UUID()
        try FileManager.default.createSymbolicLink(
            at: DeduplicateExecutor.spoolURL(for: try dedupeReceiptURL(in: logs, runID: runID)),
            withDestinationURL: sentinel
        )

        let error = await runDedupeCommit(destination: destination, target: target, runID: runID)

        XCTAssertTrue(error is ReceiptPreflightError, "got \(String(describing: error))")
        XCTAssertEqual(
            try dedupeReceipts(in: logs),
            [],
            "A run that never started must not leave a PENDING receipt for Recovery and Run History to find"
        )
        XCTAssertEqual(DeduplicateExecutor.recoverInterruptedRuns(at: destination), 0)
        assertSentinelUntouched(sentinel)
    }

    // AGENTS-INVARIANT: 26
    func testRetainedDedupeJournalIsNeverTruncatedAndTheRunDoesNotStart() async throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let target = try makeDedupeVictim(in: destination)
        let runID = UUID()
        let receiptURL = try dedupeReceiptURL(in: logs, runID: runID)
        let spoolURL = DeduplicateExecutor.spoolURL(for: receiptURL)
        let retained = Data(#"{"state":"trashed","originalPath":"/dst/earlier.jpg","schemaVersion":2}"#.utf8 + [0x0A])
        try retained.write(to: spoolURL)

        let error = await runDedupeCommit(destination: destination, target: target, runID: runID)

        let preflight = try XCTUnwrap(error as? ReceiptPreflightError, "got \(String(describing: error))")
        XCTAssertTrue(preflight.underlying is DeduplicateJournalInUseError, "got \(preflight.underlying)")
        XCTAssertEqual(try Data(contentsOf: spoolURL), retained, "The retained journal is the only record of what the earlier run moved")
        XCTAssertEqual(try dedupeReceipts(in: logs), [], "The refused run must not write a receipt over the earlier run's name")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    // MARK: - Dedupe journal read-back

    private let forgedJournalLine = #"{"state":"trashed","originalPath":"/dst/forged.jpg","actualTrashURL":"file:///elsewhere/forged.jpg","schemaVersion":2}"#

    private func plantForgedJournal(at spool: URL, sentinel: URL) throws {
        try Data((forgedJournalLine + "\n").utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: spool, withDestinationURL: sentinel)
    }

    private func assertRefused(_ body: () throws -> Any, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { error in
            XCTAssertTrue(error is DestinationMetadataUnsafeError, "got \(error)", file: file, line: line)
        }
    }

    // AGENTS-INVARIANT: 26
    func testDedupeJournalReadersRefuseAJournalThatIsALink() throws {
        let logs = try organizeLogsDirectory(in: try makeDirectory())
        let sentinel = try makeSentinel(in: try makeDirectory())
        let spool = logs.appendingPathComponent("dedupe_audit_receipt_x.json.spool")
        try plantForgedJournal(at: spool, sentinel: sentinel)

        assertRefused { try DeduplicateExecutor.loadSpoolRecords(from: spool) }
        assertRefused { try DeduplicateExecutor.loadLatestJournalRecords(from: spool) }
    }

    // AGENTS-INVARIANT: 26
    func testDedupeJournalReadersRefuseADanglingLinkInsteadOfTreatingItAsAnAbsentJournal() throws {
        let logs = try organizeLogsDirectory(in: try makeDirectory())
        let spool = logs.appendingPathComponent("dedupe_audit_receipt_x.json.spool")
        try FileManager.default.createSymbolicLink(
            at: spool,
            withDestinationURL: logs.appendingPathComponent("nowhere.txt")
        )

        assertRefused { try DeduplicateExecutor.loadSpoolRecords(from: spool) }
        assertRefused { try DeduplicateExecutor.loadLatestJournalRecords(from: spool) }
    }

    // AGENTS-INVARIANT: 26
    func testDedupeJournalReadBackRefusesAFileThatIsNotTheJournalTheRunOpened() throws {
        let logs = try organizeLogsDirectory(in: try makeDirectory())
        let spool = logs.appendingPathComponent("dedupe_audit_receipt_x.json.spool")
        let handle = try DestinationMetadataFile.openForAppending(at: spool)
        try handle.write(contentsOf: Data((forgedJournalLine + "\n").utf8))
        let journalID = try XCTUnwrap(DestinationMetadataFile.fileID(of: handle))
        try handle.close()

        XCTAssertEqual(try DeduplicateExecutor.loadSpoolRecords(from: spool, expecting: journalID).count, 1)

        try FileManager.default.removeItem(at: spool)
        try Data((forgedJournalLine + "\n").utf8).write(to: spool)
        assertRefused { try DeduplicateExecutor.loadSpoolRecords(from: spool, expecting: journalID) }
    }

    func testDedupeJournalReadersTreatAMissingJournalAsEmpty() throws {
        let logs = try organizeLogsDirectory(in: try makeDirectory())
        let spool = logs.appendingPathComponent("dedupe_audit_receipt_x.json.spool")

        XCTAssertEqual(try DeduplicateExecutor.loadSpoolRecords(from: spool), [:])
        XCTAssertEqual(try DeduplicateExecutor.loadLatestJournalRecords(from: spool).count, 0)
    }

    // AGENTS-INVARIANT: 26
    func testDedupeRecoveryLeavesTheReceiptPendingWhenItsJournalIsALink() throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let runID = UUID()
        let receiptURL = try dedupeReceiptURL(in: logs, runID: runID)
        try DeduplicateExecutor.writeReceipt(
            receiptURL: receiptURL,
            runID: runID,
            status: "PENDING",
            createdAt: dedupeStart,
            finishedAt: nil,
            destinationRoot: destination.path,
            items: [
                DeduplicateAuditReceipt.Item(
                    originalPath: "/dst/forged.jpg",
                    sizeBytes: 64,
                    trashURL: nil,
                    method: .trash,
                    clusterID: UUID(),
                    clusterKind: .exactDuplicate,
                    mediaKind: .photo,
                    expectedIdentity: nil
                )
            ],
            bytesReclaimed: 0,
            abortReason: nil
        )
        try plantForgedJournal(at: DeduplicateExecutor.spoolURL(for: receiptURL), sentinel: sentinel)

        XCTAssertEqual(DeduplicateExecutor.recoverInterruptedRuns(at: destination), 0)

        let receipt = try JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: Data(contentsOf: receiptURL))
        XCTAssertEqual(receipt.status, "PENDING", "A forged journal must not settle the receipt")
        XCTAssertNil(receipt.items.first?.trashURL, "A forged Trash location must never reach a receipt that revert trusts")
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: DeduplicateExecutor.spoolURL(for: receiptURL).path))
    }

    // MARK: - Dry-run report and preview review

    private func plannedTransfers() -> [PlannedTransfer] {
        [
            PlannedTransfer(
                sourcePath: "/src/a.jpg",
                destinationPath: "/dst/a.jpg",
                identity: FileIdentity(size: 1, digest: "abc"),
                dateBucket: "2026-01-01",
                isDuplicate: false
            )
        ]
    }

    private func reviewItems() -> [PreviewReviewItem] {
        [
            PreviewReviewItem(
                sourcePath: "/src/a.jpg",
                identityRawValue: nil,
                resolvedDate: nil,
                dateSource: .unknown,
                dateConfidence: .unknown,
                plannedDestinationPath: "/dst/a.jpg",
                status: .ready,
                issues: []
            )
        ]
    }

    // AGENTS-INVARIANT: 26
    func testSymlinkAtDryRunReportTempNameIsNeverWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        let report = logs.appendingPathComponent("dry_run_report_20260927_120000.csv")
        try FileManager.default.createSymbolicLink(
            at: report.appendingPathExtension("tmp"),
            withDestinationURL: sentinel
        )

        try SwiftOrganizerEngine.writeReport(plannedTransfers(), to: report)

        assertSentinelUntouched(sentinel)
        XCTAssertTrue(try String(contentsOf: report, encoding: .utf8).contains("a.jpg"))
    }

    // AGENTS-INVARIANT: 26
    func testHardLinkAtDryRunReportTempNameIsNeverWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        let report = logs.appendingPathComponent("dry_run_report_20260927_120000.csv")
        try FileManager.default.linkItem(at: sentinel, to: report.appendingPathExtension("tmp"))

        try SwiftOrganizerEngine.writeReport(plannedTransfers(), to: report)

        assertSentinelUntouched(sentinel)
        XCTAssertTrue(try String(contentsOf: report, encoding: .utf8).contains("a.jpg"))
    }

    // AGENTS-INVARIANT: 26
    func testSymlinkAtPreviewReviewTempNameIsNeverWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        let review = logs.appendingPathComponent("preview_review_20260927_120000.jsonl")
        try FileManager.default.createSymbolicLink(
            at: review.appendingPathExtension("tmp"),
            withDestinationURL: sentinel
        )

        try SwiftOrganizerEngine.writePreviewReview(reviewItems(), to: review)

        assertSentinelUntouched(sentinel)
        XCTAssertTrue(try String(contentsOf: review, encoding: .utf8).contains("a.jpg"))
    }

    // AGENTS-INVARIANT: 26
    func testHardLinkAtPreviewReviewTempNameIsNeverWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        let review = logs.appendingPathComponent("preview_review_20260927_120000.jsonl")
        try FileManager.default.linkItem(at: sentinel, to: review.appendingPathExtension("tmp"))

        try SwiftOrganizerEngine.writePreviewReview(reviewItems(), to: review)

        assertSentinelUntouched(sentinel)
        XCTAssertTrue(try String(contentsOf: review, encoding: .utf8).contains("a.jpg"))
    }
}
