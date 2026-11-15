import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Store-level coverage for Undo in Preview Triage (PR B).
///
/// The regression this guards against: an undo that re-runs the forward
/// transform (which is lossy — it strips `.unknownDate`/`.lowConfidenceDate`
/// issues) or restores a stale field snapshot. The fix restores a *whole-item*
/// snapshot, so these tests assert a full round-trip including the stripped
/// issues coming back.
///
/// Note on scope: the `UndoManager` wiring itself (⌘Z → `applyRestore`) is
/// exercised manually, not here. Calling `UndoManager` from inside an `async`
/// XCTest task corrupts the Swift task allocator via `XCTSwiftErrorObservation`
/// — an XCTest harness artifact unrelated to the app's run loop. We therefore
/// drive the restore primitive directly, which is where the real logic lives.
@MainActor
final class PreviewReviewUndoTests: XCTestCase {
    // Touched only from setUp/tearDown and serially-run test bodies, so it does
    // not need the class's MainActor isolation; opting out keeps the synchronous
    // XCTest setUp/tearDown overrides (which must stay nonisolated) able to reach it.
    nonisolated(unsafe) private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PreviewReviewUndoTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    private final class Box<T> { var value: T? }

    /// Runs an async, MainActor-isolated operation to completion by pumping the
    /// run loop, so the enclosing test method can stay synchronous.
    @discardableResult
    private func runAsync<T>(
        timeout: TimeInterval = 5,
        _ operation: @escaping @MainActor () async -> T
    ) -> T {
        let expectation = expectation(description: "async-op")
        let box = Box<T>()
        Task { @MainActor in
            box.value = await operation()
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: timeout)
        return box.value!
    }

    private func makeItem() -> PreviewReviewItem {
        PreviewReviewItem(
            sourcePath: "/src/IMG_0001.HEIC",
            identityRawValue: "1024_deadbeefcafe",
            resolvedDate: Date(timeIntervalSince1970: 1_000_000),
            dateSource: .unknown,
            dateConfidence: .low,
            plannedDestinationPath: nil,
            status: .ready,
            issues: [.unknownDate]
        )
    }

    private func writeArtifact(_ items: [PreviewReviewItem]) throws -> String {
        let url = tempDir.appendingPathComponent("preview_review_test.jsonl")
        let encoder = JSONEncoder()
        let lines = try items.map { item -> String in
            String(data: try encoder.encode(item), encoding: .utf8)!
        }
        try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// Loads a store with one item and no UndoManager bound (so the restore
    /// primitive can be exercised without the async/UndoManager harness crash).
    private func makeLoadedStore(_ item: PreviewReviewItem) throws -> PreviewReviewStore {
        let artifact = try writeArtifact([item])
        let store = PreviewReviewStore()
        let root = tempDir.path
        runAsync { await store.load(artifactPath: artifact, destinationRoot: root) }
        XCTAssertEqual(store.items.count, 1)
        return store
    }

    func testRestoreSwapsWholeSnapshotBringingBackStrippedIssues() throws {
        let original = makeItem()
        let store = try makeLoadedStore(original)

        // Simulate the post-edit item the forward transform produces: a user
        // override with the date issue stripped.
        var edited = original
        edited.resolvedDate = Date(timeIntervalSince1970: 2_000_000)
        edited.dateSource = .userOverride
        edited.dateConfidence = .high
        edited.issues = []
        edited.acceptedEventName = "Trip"

        store.applyRestore(edited, actionName: "Edit Review Item")
        XCTAssertEqual(store.items[0], edited)

        // Restoring the original must bring back the .unknownDate issue — a
        // lossy, transform-based inverse could not do this.
        store.applyRestore(original, actionName: "Edit Review Item")
        XCTAssertEqual(store.items[0], original)
        XCTAssertTrue(store.items[0].issues.contains(.unknownDate))
        XCTAssertEqual(store.items[0].dateSource, .unknown)

        runAsync { await store.drainPendingPersists() }
    }

    func testForwardSaveAppliesTheExpectedTransform() throws {
        let store = try makeLoadedStore(makeItem())
        let d1 = Date(timeIntervalSince1970: 2_000_000)

        runAsync { await store.saveOverride(for: store.items[0], captureDate: d1, eventName: "Birthday") }

        XCTAssertEqual(store.items[0].resolvedDate, d1)
        XCTAssertEqual(store.items[0].dateSource, .userOverride)
        XCTAssertEqual(store.items[0].dateConfidence, .high)
        XCTAssertFalse(store.items[0].issues.contains(.unknownDate))
        XCTAssertEqual(store.items[0].acceptedEventName, "Birthday")
        XCTAssertTrue(store.isStale)
        XCTAssertNil(store.errorMessage)

        runAsync { await store.drainPendingPersists() }
    }

    func testChoosingAlternativeDateAppliesUserOverrideAndClearsConflict() throws {
        var conflict = makeItem()
        let metadataDate = Date(timeIntervalSince1970: 1_000_000)
        let filenameDate = Date(timeIntervalSince1970: 2_000_000)
        conflict.resolvedDate = metadataDate
        conflict.dateSource = .photoMetadata
        conflict.dateConfidence = .high
        conflict.issues = [.conflictingDates]
        conflict.alternativeDate = DateReviewAlternative(date: filenameDate, source: .filename)
        let store = try makeLoadedStore(conflict)
        XCTAssertTrue(store.filteredItems.contains(where: { $0.sourcePath == conflict.sourcePath }))
        store.filter = .conflictingDates
        XCTAssertEqual(store.filteredItems.map(\.sourcePath), [conflict.sourcePath])

        runAsync {
            await store.saveOverride(
                for: store.items[0],
                captureDate: try! XCTUnwrap(store.items[0].alternativeDate?.date),
                eventName: nil,
                actionName: "Use Alternative Date"
            )
        }

        XCTAssertEqual(store.items[0].resolvedDate, filenameDate)
        XCTAssertEqual(store.items[0].dateSource, .userOverride)
        XCTAssertEqual(store.items[0].dateConfidence, .high)
        XCTAssertFalse(store.items[0].issues.contains(.conflictingDates))
        XCTAssertNil(store.items[0].alternativeDate)
        XCTAssertFalse(store.items[0].needsAttention)
        runAsync { await store.drainPendingPersists() }
    }

    private func makeConflictItem(alternative: DateReviewAlternative? = nil) -> PreviewReviewItem {
        var conflict = makeItem()
        conflict.resolvedDate = Date(timeIntervalSince1970: 1_000_000)
        conflict.dateSource = .photoMetadata
        conflict.dateConfidence = .high
        conflict.issues = [.conflictingDates]
        conflict.alternativeDate = alternative
        conflict.plannedDestinationPath = "/dst/1970/01/12/IMG_0001.HEIC"
        conflict.bucketTimeZoneOffsetSeconds = 19_800
        return conflict
    }

    private func savedOverride(for item: PreviewReviewItem) throws -> ReviewOverride? {
        let database = try OrganizerDatabase(
            url: tempDir.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
        )
        defer { database.close() }
        return try database.loadReviewOverride(
            identity: try XCTUnwrap(FileIdentity(rawValue: try XCTUnwrap(item.identityRawValue))),
            sourcePath: item.sourcePath
        )
    }

    func testKeepingTheDateClearsConflictWithoutChangingDateOrDestinationAndPersists() throws {
        // No alternative: before this action the row could only be cleared by
        // entering a date override.
        let conflict = makeConflictItem()
        let store = try makeLoadedStore(conflict)

        runAsync { await store.keepCurrentDate(for: store.items[0]) }

        var expected = conflict
        expected.issues = []
        expected.dateConflictAccepted = true
        XCTAssertEqual(store.items[0], expected)
        XCTAssertFalse(store.items[0].needsAttention)
        XCTAssertTrue(store.isStale)
        XCTAssertNil(store.errorMessage)

        let saved = try XCTUnwrap(savedOverride(for: conflict))
        XCTAssertTrue(saved.dateConflictAccepted)
        XCTAssertNil(saved.captureDate)
        XCTAssertNil(saved.eventName)
    }

    func testKeepingTheDateDropsTheAlternativeAndKeepsAnAcceptedEventName() throws {
        var conflict = makeConflictItem(
            alternative: DateReviewAlternative(date: Date(timeIntervalSince1970: 2_000_000), source: .filename)
        )
        conflict.acceptedEventName = "Trip"
        let store = try makeLoadedStore(conflict)

        runAsync { await store.keepCurrentDate(for: store.items[0]) }

        XCTAssertEqual(store.items[0].resolvedDate, conflict.resolvedDate)
        XCTAssertEqual(store.items[0].dateSource, .photoMetadata)
        XCTAssertNil(store.items[0].alternativeDate)
        XCTAssertFalse(store.items[0].issues.contains(.conflictingDates))
        let saved = try XCTUnwrap(savedOverride(for: conflict))
        XCTAssertTrue(saved.dateConflictAccepted)
        XCTAssertEqual(saved.eventName, "Trip")
    }

    func testKeepingTheDateIsANoOpForRowsWithoutAConflict() throws {
        let store = try makeLoadedStore(makeItem())
        let before = store.items[0]

        runAsync { await store.keepCurrentDate(for: store.items[0]) }

        XCTAssertEqual(store.items[0], before)
        XCTAssertFalse(store.isStale)
        XCTAssertNil(try savedOverride(for: before))
    }

    func testUndoingKeepRestoresTheConflictAndRedoClearsItAgain() throws {
        let conflict = makeConflictItem(
            alternative: DateReviewAlternative(date: Date(timeIntervalSince1970: 2_000_000), source: .filename)
        )
        let store = try makeLoadedStore(conflict)
        runAsync { await store.keepCurrentDate(for: store.items[0]) }
        let kept = store.items[0]

        // Undo: the whole-item snapshot comes back and the saved decision goes.
        store.applyRestore(conflict, actionName: "Keep This Date")
        XCTAssertEqual(store.items[0], conflict)
        XCTAssertTrue(store.items[0].needsAttention)
        runAsync { await store.drainPendingPersists() }
        XCTAssertNil(try savedOverride(for: conflict))

        // Redo.
        store.applyRestore(kept, actionName: "Keep This Date")
        XCTAssertEqual(store.items[0], kept)
        runAsync { await store.drainPendingPersists() }
        XCTAssertEqual(try savedOverride(for: conflict)?.dateConflictAccepted, true)
    }

    func testAcceptingAnEventNameAfterKeepDoesNotBringTheConflictBack() throws {
        var conflict = makeConflictItem()
        conflict.eventSuggestion = EventSuggestion(
            groupID: "g1", suggestedName: "Trip", source: .sourceFolder, confidence: .medium
        )
        let store = try makeLoadedStore(conflict)
        runAsync { await store.keepCurrentDate(for: store.items[0]) }

        runAsync { await store.acceptSuggestion(for: store.items[0]) }

        let saved = try XCTUnwrap(savedOverride(for: conflict))
        XCTAssertTrue(saved.dateConflictAccepted)
        XCTAssertEqual(saved.eventName, "Trip")
        XCTAssertNil(saved.captureDate)
    }

    func testEnteringADateAfterKeepReplacesTheKeptDecision() throws {
        let store = try makeLoadedStore(makeConflictItem())
        runAsync { await store.keepCurrentDate(for: store.items[0]) }
        let entered = Date(timeIntervalSince1970: 3_000_000)

        runAsync { await store.saveOverride(for: store.items[0], captureDate: entered, eventName: nil) }

        XCTAssertNil(store.items[0].dateConflictAccepted)
        let saved = try XCTUnwrap(savedOverride(for: store.items[0]))
        XCTAssertFalse(saved.dateConflictAccepted)
        XCTAssertEqual(saved.captureDate, entered)
    }

    func testAcceptSuggestionWithNoSuggestionIsANoOp() throws {
        let store = try makeLoadedStore(makeItem())
        let before = store.items[0]

        runAsync { await store.acceptSuggestion(for: store.items[0]) }

        XCTAssertEqual(store.items[0], before)
        runAsync { await store.drainPendingPersists() }
    }
}
