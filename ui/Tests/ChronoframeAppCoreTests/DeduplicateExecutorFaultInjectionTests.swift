import Foundation
import XCTest
@testable import ChronoframeCore

/// Fault-injection tests for `DeduplicateExecutor.commit()` that simulate
/// failure modes that can't be reached through normal happy-path inputs:
/// `.organize_logs/` becoming unwritable after preflight (Finding #7),
/// per-item Trash failures mixed with successes, and abort-while-in-flight.
///
/// These confirm what the executor *currently does* under these conditions
/// — they document the surface so a future fix can intentionally change the
/// behavior and have the test update at the same time.
final class DeduplicateExecutorFaultInjectionTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DedupeFault-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? chmod(temporaryDirectoryURL.path, 0o755)
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private func chmod(_ path: String, _ mode: mode_t) throws {
        let result = Darwin.chmod(path, mode)
        if result != 0 {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    /// A final receipt failure after a durable `.trashed` transition retains
    /// the journal so relaunch recovery can finalize an ABORTED receipt.
    // AGENTS-INVARIANT: 9
    // AGENTS-INVARIANT: 13
    func testFinalReceiptFailureRetainsJournalForRecovery() async throws {
        let dst = temporaryDirectoryURL.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: dst, withIntermediateDirectories: true)

        let target = dst.appendingPathComponent("victim.jpg")
        try Data(repeating: 0x42, count: 256).write(to: target)

        let fileOps = MovingFileOpsThatRevokeLogsAfterFirstTrash(
            logsDirectory: dst.appendingPathComponent(".organize_logs"),
            tempDirectory: temporaryDirectoryURL
        )
        let executor = DeduplicateExecutor(fileOperations: fileOps)
        let plan = DeduplicationPlan(items: [
            DeduplicationPlan.Item(
                path: target.path,
                sizeBytes: 256,
                owningClusterID: UUID(),
                owningClusterKind: .exactDuplicate,
                pairOrigin: nil,
                expectedIdentity: testFileIdentity(at: target)
            )
        ])
        let stream = executor.commit(plan: plan, destinationRoot: dst.path, hardDelete: false)

        var trashedSuccessPaths: [(path: String, trashURL: URL?)] = []
        var trashedStalePaths: [(path: String, message: String)] = []
        var failedEvents: [(path: String, message: String)] = []
        var criticalReceiptMessages: [String] = []
        var summary: DeduplicateCommitSummary?
        do {
            for try await event in stream {
                switch event {
                case let .itemTrashed(originalPath, trashURL, _):
                    trashedSuccessPaths.append((originalPath, trashURL))
                case let .itemTrashedReceiptStale(originalPath, _, _, message):
                    trashedStalePaths.append((originalPath, message))
                case let .itemFailed(originalPath, message):
                    failedEvents.append((originalPath, message))
                case let .criticalReceiptFailure(message):
                    criticalReceiptMessages.append(message)
                case .complete(let s):
                    summary = s
                default: break
                }
            }
        } catch {
            // Receipt finalize also fails; expected when logs dir is revoked.
        }

        XCTAssertEqual(trashedSuccessPaths.count, 1)
        XCTAssertEqual(trashedSuccessPaths.first?.path, target.path)
        XCTAssertTrue(trashedStalePaths.isEmpty,
            "Spool durability replaces per-item stale receipt events.")
        XCTAssertTrue(failedEvents.isEmpty)
        XCTAssertEqual(criticalReceiptMessages.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.path))

        let s = try XCTUnwrap(summary)
        XCTAssertEqual(s.deletedCount, 1)
        XCTAssertEqual(s.failedCount, 1)

        // Restore permissions so tearDown can clean up.
        try? chmod(dst.appendingPathComponent(".organize_logs").path, 0o755)

        let logsDir = dst.appendingPathComponent(".organize_logs")
        let contents = try FileManager.default.contentsOfDirectory(atPath: logsDir.path)
        let receiptName = try XCTUnwrap(contents.first { $0.hasPrefix("dedupe_audit_receipt_") && $0.hasSuffix(".json") })
        let receiptURL = logsDir.appendingPathComponent(receiptName)
        let spoolURL = DeduplicateExecutor.spoolURL(for: receiptURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: spoolURL.path))
        let recovery = MutationRecoveryCoordinator().recover(destinationRoot: dst)
        XCTAssertGreaterThanOrEqual(recovery.recoveredItemCount, 1)

        let recovered = try JSONDecoder.dedupe.decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(recovered.status, "ABORTED")
        XCTAssertEqual(recovered.items.first?.trashURL, trashedSuccessPaths.first?.trashURL?.absoluteString)
        XCTAssertFalse(FileManager.default.fileExists(atPath: spoolURL.path))
    }
}

// MARK: - Fault-injecting adapters

/// A `DeduplicateFileOperations` that:
/// - moves files into a fake-trash sibling directory (so we don't pollute
///   the user's real Trash during a test),
/// - revokes write permission on the receipt directory immediately after
///   the first successful trash, so the subsequent per-item `writeReceipt`
///   throws an EACCES.
///
/// Reproduces the exact race described in Finding #7 from the deep review.
private final class MovingFileOpsThatRevokeLogsAfterFirstTrash: DeduplicateFileOperations, @unchecked Sendable {
    let logsDirectory: URL
    let fakeTrash: URL
    private var firstTrashCompleted = false

    init(logsDirectory: URL, tempDirectory: URL) {
        self.logsDirectory = logsDirectory
        self.fakeTrash = tempDirectory.appendingPathComponent("fake-trash", isDirectory: true)
        try? FileManager.default.createDirectory(at: fakeTrash, withIntermediateDirectories: true)
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func trashItem(at url: URL) throws -> URL? {
        let destination = fakeTrash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        if !firstTrashCompleted {
            firstTrashCompleted = true
            // Revoke write+execute on the logs dir so subsequent receipt
            // writes throw. chmod the directory inode, not its contents.
            _ = Darwin.chmod(logsDirectory.path, 0o500)
        }
        return destination
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }
}
