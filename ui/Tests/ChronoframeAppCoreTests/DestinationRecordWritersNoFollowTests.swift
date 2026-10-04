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

    // MARK: - Dedupe spool journal

    // The spool name is `<receipt>.json.spool`, and the receipt name carries the
    // start time to the second, so plant the link at every name this run could pick.
    private func plantDedupeSpoolLinks(
        in logs: URL,
        runID: UUID,
        plant: (URL) throws -> Void
    ) throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        for offset in -2...6 {
            let timestamp = formatter.string(from: Date().addingTimeInterval(TimeInterval(offset)))
            let receipt = logs.appendingPathComponent("dedupe_audit_receipt_\(timestamp)_\(runID.uuidString).json")
            try plant(DeduplicateExecutor.spoolURL(for: receipt))
        }
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
        let stream = DeduplicateExecutor().commit(
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

    // AGENTS-INVARIANT: 26
    func testHardLinkAtDedupeSpoolNameIsRefusedBeforeAnyFileMoves() async throws {
        let destination = try makeDirectory()
        let logs = try organizeLogsDirectory(in: destination)
        let sentinel = try makeSentinel(in: try makeDirectory())
        let target = destination.appendingPathComponent("victim.jpg")
        try Data(repeating: 0x42, count: 64).write(to: target)
        let runID = UUID()
        try plantDedupeSpoolLinks(in: logs, runID: runID) {
            try FileManager.default.linkItem(at: sentinel, to: $0)
        }

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
        let target = destination.appendingPathComponent("victim.jpg")
        try Data(repeating: 0x42, count: 64).write(to: target)
        let runID = UUID()
        try plantDedupeSpoolLinks(in: logs, runID: runID) {
            try FileManager.default.createSymbolicLink(at: $0, withDestinationURL: outside)
        }

        let error = await runDedupeCommit(destination: destination, target: target, runID: runID)

        XCTAssertTrue(error is ReceiptPreflightError, "got \(String(describing: error))")
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
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
