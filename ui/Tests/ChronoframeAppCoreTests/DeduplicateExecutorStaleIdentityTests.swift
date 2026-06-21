import Foundation
import XCTest
@testable import ChronoframeCore

/// Finding #1: a stale deduplicate plan must never trash a file that no longer
/// matches what was scanned. Between scan/review and commit an editor or sync
/// client can replace a selected path with a different file, a symlink, or a
/// directory. The executor re-stats each path immediately before Trash and
/// preserves anything whose live identity (regular file + size + mtime) no
/// longer matches the scan, emitting `.itemStale` instead of `.itemTrashed`.
///
/// These tests drive the executor with a deterministic move-based trash
/// stand-in so they run headless; the staleness check itself reads the real
/// filesystem, which is what the executor does in production.
final class DeduplicateExecutorStaleIdentityTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DedupeStale-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private struct CommitOutcome {
        var trashed: [String] = []
        var stale: [(path: String, reason: String)] = []
        var failed: [(path: String, message: String)] = []
        var summary: DeduplicateCommitSummary?
    }

    /// Build a plan item carrying the file's current scan-time identity, the
    /// same way the planner does.
    private func planItem(for url: URL) -> DeduplicationPlan.Item {
        DeduplicationPlan.Item(
            path: url.path,
            sizeBytes: DeduplicationPlanner.fileIdentity(at: url.path).sizeBytes,
            owningClusterID: UUID(),
            owningClusterKind: .exactDuplicate,
            pairOrigin: nil,
            scanIdentity: DeduplicationPlanner.fileIdentity(at: url.path)
        )
    }

    private func runCommit(_ plan: DeduplicationPlan) async throws -> CommitOutcome {
        let trashRoot = temporaryDirectoryURL.appendingPathComponent("Trash", isDirectory: true)
        let executor = DeduplicateExecutor(
            fileOperations: MovingTrashFileOps(trashRoot: trashRoot)
        )
        var outcome = CommitOutcome()
        for try await event in executor.commit(plan: plan, destinationRoot: temporaryDirectoryURL.path, hardDelete: false) {
            switch event {
            case let .itemTrashed(path, _, _):
                outcome.trashed.append(path)
            case let .itemStale(path, reason):
                outcome.stale.append((path, reason))
            case let .itemFailed(path, message):
                outcome.failed.append((path, message))
            case let .complete(summary):
                outcome.summary = summary
            default:
                break
            }
        }
        return outcome
    }

    private func receiptPaths(_ outcome: CommitOutcome) throws -> [String] {
        let receiptURL = URL(fileURLWithPath: try XCTUnwrap(outcome.summary?.receiptPath))
        let receipt = try JSONDecoder.dedupe.decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        return receipt.items.map(\.originalPath)
    }

    // MARK: - Tests

    /// Baseline: an unchanged file still matches its scan identity and is
    /// trashed and recorded as before. Guards against the staleness check
    /// over-rejecting normal commits.
    // AGENTS-INVARIANT: 5
    func testUnchangedFileIsTrashedAndRecorded() async throws {
        let file = temporaryDirectoryURL.appendingPathComponent("keep.jpg")
        try Data(repeating: 0x11, count: 512).write(to: file)
        let plan = DeduplicationPlan(items: [planItem(for: file)])

        let outcome = try await runCommit(plan)

        XCTAssertEqual(outcome.trashed, [file.path])
        XCTAssertTrue(outcome.stale.isEmpty)
        XCTAssertEqual(outcome.summary?.deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path), "Unchanged file should be trashed")
        XCTAssertEqual(try receiptPaths(outcome), [file.path])
    }

    /// A same-size replacement with a different modification time is a
    /// different file the user never reviewed — preserve it.
    // AGENTS-INVARIANT: 5
    func testSameSizeReplacementIsPreservedAsStale() async throws {
        let file = temporaryDirectoryURL.appendingPathComponent("dup.jpg")
        try Data(repeating: 0x22, count: 512).write(to: file)
        let item = planItem(for: file)

        // Replace with unique content of the SAME size, then force a clearly
        // different mtime so the swap is unambiguous regardless of timer
        // resolution.
        try Data(repeating: 0x33, count: 512).write(to: file)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
            ofItemAtPath: file.path
        )

        let outcome = try await runCommit(DeduplicationPlan(items: [item]))

        XCTAssertEqual(outcome.stale.map(\.path), [file.path])
        XCTAssertTrue(outcome.trashed.isEmpty)
        XCTAssertEqual(outcome.summary?.deletedCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "Replacement must be preserved")
        XCTAssertTrue(try receiptPaths(outcome).isEmpty, "Stale item must be excluded from the receipt")
    }

    /// A file whose size changed since the scan is a different file — preserve.
    // AGENTS-INVARIANT: 5
    func testSizeChangeIsPreservedAsStale() async throws {
        let file = temporaryDirectoryURL.appendingPathComponent("grew.jpg")
        try Data(repeating: 0xAB, count: 100).write(to: file)
        let item = planItem(for: file)

        // Append bytes so the live size no longer matches the scanned size.
        try Data(repeating: 0xCD, count: 200).write(to: file)

        let outcome = try await runCommit(DeduplicationPlan(items: [item]))

        XCTAssertEqual(outcome.stale.map(\.path), [file.path])
        XCTAssertTrue(outcome.trashed.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    /// A file that vanished between scan and commit is reported stale (there is
    /// nothing to trash) rather than failing the run.
    // AGENTS-INVARIANT: 5
    func testMissingFileIsReportedStale() async throws {
        let file = temporaryDirectoryURL.appendingPathComponent("gone.jpg")
        try Data(repeating: 0xEF, count: 48).write(to: file)
        let item = planItem(for: file)
        try FileManager.default.removeItem(at: file)

        let outcome = try await runCommit(DeduplicationPlan(items: [item]))

        XCTAssertEqual(outcome.stale.map(\.path), [file.path])
        XCTAssertTrue(outcome.trashed.isEmpty)
        XCTAssertTrue(outcome.failed.isEmpty, "A vanished file is stale, not a failure")
        XCTAssertEqual(outcome.summary?.deletedCount, 0)
    }

    /// A symlink standing where a regular file was scanned must never be
    /// followed and trashed (AGENTS-INVARIANT 15).
    // AGENTS-INVARIANT: 5
    func testSymlinkReplacementIsPreservedAsStale() async throws {
        let file = temporaryDirectoryURL.appendingPathComponent("link.jpg")
        try Data(repeating: 0x44, count: 256).write(to: file)
        let item = planItem(for: file)

        let target = temporaryDirectoryURL.appendingPathComponent("real-target.bin")
        try Data(repeating: 0x55, count: 256).write(to: target)
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createSymbolicLink(atPath: file.path, withDestinationPath: target.path)

        let outcome = try await runCommit(DeduplicationPlan(items: [item]))

        XCTAssertEqual(outcome.stale.map(\.path), [file.path])
        XCTAssertTrue(outcome.trashed.isEmpty)
        // The symlink and its target both remain on disk.
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path), "Symlink target must be untouched")
    }

    /// A directory replacing the scanned regular file must be preserved.
    // AGENTS-INVARIANT: 5
    func testDirectoryReplacementIsPreservedAsStale() async throws {
        let file = temporaryDirectoryURL.appendingPathComponent("becomes-dir.jpg")
        try Data(repeating: 0x66, count: 128).write(to: file)
        let item = planItem(for: file)

        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        let nested = file.appendingPathComponent("inner.txt")
        try Data("important".utf8).write(to: nested)

        let outcome = try await runCommit(DeduplicationPlan(items: [item]))

        XCTAssertEqual(outcome.stale.map(\.path), [file.path])
        XCTAssertTrue(outcome.trashed.isEmpty)
        var isDir: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir))
        XCTAssertTrue(isDir.boolValue, "Directory must be preserved")
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path), "Directory contents must be untouched")
    }

    /// A mixed plan: the unchanged item is trashed while the replaced item is
    /// preserved — the staleness check is per-item, not all-or-nothing.
    // AGENTS-INVARIANT: 5
    func testMixedPlanTrashesUnchangedAndPreservesStale() async throws {
        let good = temporaryDirectoryURL.appendingPathComponent("good.jpg")
        let swapped = temporaryDirectoryURL.appendingPathComponent("swapped.jpg")
        try Data(repeating: 0x77, count: 64).write(to: good)
        try Data(repeating: 0x88, count: 64).write(to: swapped)
        let goodItem = planItem(for: good)
        let swappedItem = planItem(for: swapped)

        // Swap the second file's bytes + mtime after capturing identity.
        try Data(repeating: 0x99, count: 64).write(to: swapped)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSince1970: 1_000_000_000)],
            ofItemAtPath: swapped.path
        )

        let outcome = try await runCommit(DeduplicationPlan(items: [goodItem, swappedItem]))

        XCTAssertEqual(outcome.trashed, [good.path])
        XCTAssertEqual(outcome.stale.map(\.path), [swapped.path])
        XCTAssertEqual(outcome.summary?.deletedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: good.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: swapped.path))
        XCTAssertEqual(try receiptPaths(outcome), [good.path], "Receipt records only the real deletion")
    }
}

/// Minimal move-based Trash stand-in: `trashItem` relocates the file into a
/// scratch directory so tests are deterministic and need no Trash entitlement.
private final class MovingTrashFileOps: DeduplicateFileOperations, @unchecked Sendable {
    private let trashRoot: URL

    init(trashRoot: URL) {
        self.trashRoot = trashRoot
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func trashItem(at url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let destination = trashRoot.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: destination)
        return destination
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }
}
