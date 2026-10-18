import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class RunSessionReorganizeRevertTests: XCTestCase {
    @MainActor
    func testCancelStopsUndoBetweenMovesAndRetainsAccessUntilCompletion() async throws {
        let fixture = try makeFixture(fileCount: 3)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = GatedReorganizeFileOperations()
        defer { gate.resume() }
        let tracker = SecurityScopeCloseTracker()
        let store = makeStore(root: fixture.root)
        store.reorganizeRevertExecutor = ReorganizeExecutor(fileOperations: gate)
        store.requestReorganizeRevert(
            receiptURL: fixture.receipt,
            destinationRoot: fixture.root.path,
            securityScope: tracker.makeScope()
        )
        let paused = await waitForCondition { gate.isPaused }
        XCTAssertTrue(paused)
        store.cancelCurrentRun()
        store.cancelCurrentRun()
        XCTAssertTrue(store.isRunning)
        XCTAssertTrue(store.isCancelling)
        XCTAssertEqual(store.currentTaskTitle, "Stopping…")
        XCTAssertNil(store.lastRunCompletion)
        XCTAssertEqual(tracker.closeCount, 0)
        XCTAssertThrowsError(try DestinationOperationLock.acquire(
            destinationRoot: fixture.root, surface: "test", operation: "during undo"
        ))
        let token = store.currentRunToken
        store.requestReorganizeRevert(receiptURL: fixture.receipt, destinationRoot: fixture.root.path)
        XCTAssertEqual(store.currentRunToken, token, "A stopping undo cannot be replaced")

        gate.resume()
        let finished = await waitForCondition { store.lastRunCompletion != nil }
        XCTAssertTrue(finished)
        XCTAssertEqual(store.status, .cancelled)
        XCTAssertEqual(store.summary?.title, "Cancelled")
        XCTAssertEqual(store.lastRunCompletion?.status, .cancelled)
        XCTAssertEqual(store.metrics.plannedCount, 3)
        XCTAssertEqual(store.metrics.movedCount, 1)
        XCTAssertEqual(store.summary?.metrics.movedCount, 1)
        XCTAssertEqual(store.summary?.artifacts.reportPath, fixture.receipt.path)
        XCTAssertFalse(store.isRunning)
        XCTAssertFalse(store.isCancelling)
        try assertFileLocations(fixture, restoredCount: 1)
        let lease = try DestinationOperationLock.acquire(
            destinationRoot: fixture.root, surface: "test", operation: "after undo"
        )
        lease.release()
        let closed = await waitForCondition { tracker.closeCount == 1 }
        XCTAssertTrue(closed)

        // A fresh token must let a subsequent undo finish the remaining moves.
        store.requestReorganizeRevert(receiptURL: fixture.receipt, destinationRoot: fixture.root.path)
        let retried = await waitForCondition { store.lastRunCompletion?.runToken != token }
        XCTAssertTrue(retried)
        XCTAssertEqual(store.status, .reorganized)
        XCTAssertEqual(store.metrics.movedCount, 2)
        XCTAssertEqual(store.metrics.skippedCount, 1)
        try assertFileLocations(fixture, restoredCount: 3)
    }

    @MainActor
    func testCancelDuringLastUndoMovePreservesCompletedOutcome() async throws {
        let fixture = try makeFixture(fileCount: 1)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let gate = GatedReorganizeFileOperations()
        defer { gate.resume() }
        let store = makeStore(root: fixture.root)
        store.reorganizeRevertExecutor = ReorganizeExecutor(fileOperations: gate)
        store.requestReorganizeRevert(receiptURL: fixture.receipt, destinationRoot: fixture.root.path)
        let paused = await waitForCondition { gate.isPaused }
        XCTAssertTrue(paused)
        store.cancelCurrentRun()
        gate.resume()
        let finished = await waitForCondition { store.lastRunCompletion != nil }
        XCTAssertTrue(finished)
        XCTAssertEqual(store.status, .reorganized)
        XCTAssertEqual(store.summary?.title, "Reorganize undone")
        XCTAssertEqual(store.metrics.movedCount, 1)
        try assertFileLocations(fixture, restoredCount: 1)
    }

    @MainActor
    func testCancelBeforeUndoStartsMovesNothingAndReleasesAccess() async throws {
        let fixture = try makeFixture(fileCount: 2)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let tracker = SecurityScopeCloseTracker()
        let store = makeStore(root: fixture.root)
        store.requestReorganizeRevert(
            receiptURL: fixture.receipt,
            destinationRoot: fixture.root.path,
            securityScope: tracker.makeScope()
        )
        store.cancelCurrentRun()
        XCTAssertTrue(store.isRunning)
        let finished = await waitForCondition { store.lastRunCompletion != nil }
        XCTAssertTrue(finished)
        XCTAssertEqual(store.status, .cancelled)
        XCTAssertEqual(store.metrics.movedCount, 0)
        try assertFileLocations(fixture, restoredCount: 0)
        let lease = try DestinationOperationLock.acquire(
            destinationRoot: fixture.root, surface: "test", operation: "after early cancel"
        )
        lease.release()
        let closed = await waitForCondition { tracker.closeCount == 1 }
        XCTAssertTrue(closed)
    }

    @MainActor
    private func makeStore(root: URL) -> RunSessionStore {
        let configuration = RunConfiguration(mode: .preview, sourcePath: "", destinationPath: root.path)
        let engine = MockOrganizerEngine(preflightResult: .success(RunPreflight(
            configuration: configuration, resolvedSourcePath: "", resolvedDestinationPath: root.path
        )))
        return RunSessionStore(engine: engine, logStore: RunLogStore(), historyStore: HistoryStore())
    }

    private struct Fixture {
        let root: URL
        let receipt: URL
        let plan: ReorganizePlan
    }

    private func makeFixture(fileCount: Int) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("RunSessionReorganizeRevertTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for index in 1...fileCount {
            try Data("photo-\(index)".utf8).write(to: root.appendingPathComponent("2026-04-08_00\(index).jpg"))
        }
        let executor = ReorganizeExecutor()
        let plan = try executor.plan(destinationRoot: root, targetStructure: .yyyyMMDD)
        let result = try executor.execute(plan: plan)
        return Fixture(root: root, receipt: URL(fileURLWithPath: try XCTUnwrap(result.receiptPath)), plan: plan)
    }

    private func assertFileLocations(_ fixture: Fixture, restoredCount: Int) throws {
        // Undo visits the receipt in reverse order. Every photo stays at exactly
        // one of its two paths and keeps its original bytes.
        for (index, move) in fixture.plan.moves.reversed().enumerated() {
            let restored = index < restoredCount
            XCTAssertEqual(FileManager.default.fileExists(atPath: move.sourcePath), restored)
            XCTAssertEqual(FileManager.default.fileExists(atPath: move.destinationPath), !restored)
            let currentURL = URL(fileURLWithPath: restored ? move.sourcePath : move.destinationPath)
            let fileIndex = URL(fileURLWithPath: move.sourcePath).deletingPathExtension().lastPathComponent.suffix(1)
            XCTAssertEqual(try Data(contentsOf: currentURL), Data("photo-\(fileIndex)".utf8))
        }
    }
}

/// Performs real filesystem operations, pausing after the first undo move so
/// the main actor can request cancellation before the executor's next poll.
private final class GatedReorganizeFileOperations: ReorganizeFileOperations, @unchecked Sendable {
    private let lock = NSLock()
    private let gate = DispatchSemaphore(value: 0)
    private var paused = false
    var isPaused: Bool { lock.withLock { paused } }
    func resume() { gate.signal() }

    func fileExists(atPath path: String) -> Bool { FileManager.default.fileExists(atPath: path) }
    func fileExists(atPath path: String, isDirectory: UnsafeMutablePointer<ObjCBool>?) -> Bool {
        FileManager.default.fileExists(atPath: path, isDirectory: isDirectory)
    }
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        let shouldPause = lock.withLock {
            if paused { return false }
            paused = true
            return true
        }
        if shouldPause { _ = gate.wait(timeout: .now() + 10) }
    }
    func contentsOfDirectory(atPath path: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: path)
    }
    func removeItem(at url: URL) throws { try FileManager.default.removeItem(at: url) }
    func enumerator(
        at url: URL,
        includingPropertiesForKeys keys: [URLResourceKey]?,
        options mask: FileManager.DirectoryEnumerationOptions
    ) -> FileManager.DirectoryEnumerator? {
        FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys, options: mask)
    }
}
