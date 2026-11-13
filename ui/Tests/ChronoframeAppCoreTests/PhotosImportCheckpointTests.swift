import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class PhotosImportCheckpointTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotosImportCheckpointTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot, FileManager.default.fileExists(atPath: tempRoot.path) {
            try FileManager.default.removeItem(at: tempRoot)
        }
    }

    // MARK: - Fixtures

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func entry(_ id: String, stem: String? = nil) -> PhotosAssetExportEntry {
        PhotosAssetExportEntry(
            assetID: id,
            mediaKind: .photo,
            stagingStem: stem ?? "IMG_\(id)",
            creationDate: Date(timeIntervalSince1970: 1_600_000_000)
        )
    }

    private func plan(_ ids: [String]) -> PhotosExportPlan {
        PhotosExportPlan(entries: ids.map { entry($0) })
    }

    private func makeCheckpoint(ids: [String] = ["A", "B", "C"]) -> PhotosImportCheckpoint {
        PhotosImportCheckpoint(
            importID: UUID(),
            createdAt: t0,
            destinationPath: "/tmp/dest",
            destinationBookmarkKeys: ["k1", "k2"],
            plan: plan(ids)
        )
    }

    private func hint(_ digest: String) -> SourceDateHint {
        SourceDateHint(
            identity: FileIdentity(size: 10, digest: digest),
            resolvedDate: ResolvedMediaDate(
                date: Date(timeIntervalSince1970: 1_600_000_000),
                source: .photoMetadata,
                confidence: .high
            )
        )
    }

    private func record(_ id: String, names: [String]) -> PhotosCompletedAssetRecord {
        let files = names.map { PhotosExportedFile(assetID: id, stagingStem: "IMG_\(id)", path: "/staging/\($0)") }
        var hints: [String: SourceDateHint] = [:]
        for file in files {
            hints[SourceDateHint.pathKey(for: file.path)] = hint("d-\(file.path)")
        }
        return PhotosCompletedAssetRecord(assetID: id, files: files, sourceDateHints: hints)
    }

    // MARK: - Model

    func testNewCheckpointIsInProgressWithNoRecords() {
        let checkpoint = makeCheckpoint()
        XCTAssertEqual(checkpoint.state, .inProgress)
        XCTAssertEqual(checkpoint.version, PhotosImportCheckpoint.version)
        XCTAssertEqual(checkpoint.updatedAt, checkpoint.createdAt)
        XCTAssertTrue(checkpoint.completed.isEmpty)
        XCTAssertTrue(checkpoint.failures.isEmpty)
        XCTAssertEqual(checkpoint.destinationPath, "/tmp/dest")
        XCTAssertEqual(checkpoint.destinationBookmarkKeys, ["k1", "k2"])
        XCTAssertEqual(checkpoint.remainingEntries.map(\.assetID), ["A", "B", "C"])
        XCTAssertTrue(checkpoint.completedAssetIDs.isEmpty)
    }

    func testRecordCompletedUpdatesCompletedIDsReservedFilenamesAndMergedHints() {
        var checkpoint = makeCheckpoint()
        let a = record("A", names: ["IMG_A.HEIC", "IMG_A.MOV"])
        let b = record("B", names: ["IMG_B.jpg"])
        let later = Date(timeIntervalSince1970: 1_700_000_100)

        checkpoint.recordCompleted(a, at: later)
        checkpoint.recordCompleted(b, at: later.addingTimeInterval(5))

        XCTAssertEqual(checkpoint.completedAssetIDs, ["A", "B"])
        XCTAssertEqual(checkpoint.reservedFilenames, ["IMG_A.HEIC", "IMG_A.MOV", "IMG_B.jpg"])
        XCTAssertEqual(checkpoint.mergedSourceDateHints.count, 3)
        for (key, value) in a.sourceDateHints.merging(b.sourceDateHints, uniquingKeysWith: { first, _ in first }) {
            XCTAssertEqual(checkpoint.mergedSourceDateHints[key], value)
        }
        XCTAssertEqual(checkpoint.updatedAt, later.addingTimeInterval(5))
        XCTAssertEqual(checkpoint.completed, [a, b])
    }

    func testRemainingEntriesExcludeCompletedAndFailedInPlanOrder() {
        var checkpoint = makeCheckpoint(ids: ["A", "B", "C", "D", "E"])
        checkpoint.recordCompleted(record("D", names: ["IMG_D.jpg"]), at: t0)
        checkpoint.recordFailure(PhotosAssetExportFailure(assetID: "B", message: "nope"), at: t0.addingTimeInterval(1))

        XCTAssertEqual(checkpoint.remainingEntries.map(\.assetID), ["A", "C", "E"])
        XCTAssertEqual(checkpoint.failures.map(\.assetID), ["B"])
        XCTAssertEqual(checkpoint.updatedAt, t0.addingTimeInterval(1))
    }

    func testExportedAssetIDsFollowPlanOrderNotCompletionOrder() {
        var checkpoint = makeCheckpoint(ids: ["A", "B", "C"])
        checkpoint.recordCompleted(record("C", names: ["IMG_C.jpg"]), at: t0)
        checkpoint.recordCompleted(record("A", names: ["IMG_A.jpg"]), at: t0)

        XCTAssertEqual(checkpoint.exportedAssetIDs, ["A", "C"])
    }

    func testIsResumableForStoppedLowSpaceAndInProgressOnly() {
        var checkpoint = makeCheckpoint()
        let when = t0.addingTimeInterval(9)
        let expectations: [(PhotosImportCheckpointState, Bool)] = [
            (.inProgress, true), (.stopped, true), (.lowSpace, true), (.ready, false)
        ]
        for (state, resumable) in expectations {
            checkpoint.setState(state, at: when)
            XCTAssertEqual(checkpoint.state, state)
            XCTAssertEqual(checkpoint.isResumable, resumable, "\(state)")
            XCTAssertEqual(checkpoint.updatedAt, when)
        }
    }

    // MARK: - Store

    func testRoundTripThroughFileStorePreservesEveryField() throws {
        var checkpoint = makeCheckpoint()
        checkpoint.recordCompleted(record("A", names: ["IMG_A.HEIC", "IMG_A.MOV"]), at: t0.addingTimeInterval(3))
        checkpoint.recordFailure(PhotosAssetExportFailure(assetID: "B", message: "iCloud unavailable"), at: t0.addingTimeInterval(4))
        checkpoint.setState(.stopped, at: t0.addingTimeInterval(5))

        let store = PhotosImportFileCheckpointStore()
        try store.save(checkpoint, in: tempRoot)
        let loaded = try XCTUnwrap(store.load(in: tempRoot))

        XCTAssertEqual(loaded, checkpoint)
        XCTAssertEqual(loaded.importID, checkpoint.importID)
        XCTAssertEqual(loaded.createdAt.timeIntervalSince1970, checkpoint.createdAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded.updatedAt.timeIntervalSince1970, checkpoint.updatedAt.timeIntervalSince1970, accuracy: 1)
        XCTAssertEqual(loaded.plan, checkpoint.plan)
        XCTAssertEqual(loaded.completed, checkpoint.completed)
        XCTAssertEqual(loaded.failures, checkpoint.failures)
        XCTAssertEqual(loaded.state, .stopped)
        XCTAssertEqual(loaded.destinationBookmarkKeys, ["k1", "k2"])
    }

    func testLoadReturnsNilForMissingCorruptAndWrongVersion() throws {
        let store = PhotosImportFileCheckpointStore()
        let url = tempRoot.appendingPathComponent(PhotosImportCheckpoint.filename)

        // Missing.
        XCTAssertNil(store.load(in: tempRoot))

        // Corrupt.
        try Data("{ not json".utf8).write(to: url)
        XCTAssertNil(store.load(in: tempRoot))

        // Wrong version: save a valid checkpoint, then rewrite its version field.
        try store.save(makeCheckpoint(), in: tempRoot)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("\"version\" : 1"))
        try text.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 99")
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(store.load(in: tempRoot))
    }

    func testSaveIsAtomicAndCreatesDirectory() throws {
        let staging = tempRoot.appendingPathComponent("not/yet/existing", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path))

        let store = PhotosImportFileCheckpointStore()
        let checkpoint = makeCheckpoint()
        try store.save(checkpoint, in: staging)

        let url = staging.appendingPathComponent(PhotosImportCheckpoint.filename)
        let data = try Data(contentsOf: url)
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: data))
        // Only the checkpoint remains: no leftover temp file from the atomic write.
        let contents = try FileManager.default.contentsOfDirectory(atPath: staging.path)
        XCTAssertEqual(contents, [PhotosImportCheckpoint.filename])

        // Overwriting replaces it with another complete document.
        var updated = checkpoint
        updated.setState(.stopped, at: t0.addingTimeInterval(1))
        try store.save(updated, in: staging)
        XCTAssertEqual(store.load(in: staging)?.state, .stopped)
    }

    func testRemoveIgnoresMissingFile() throws {
        let store = PhotosImportFileCheckpointStore()
        store.remove(in: tempRoot)   // missing: must not crash or throw

        try store.save(makeCheckpoint(), in: tempRoot)
        let sibling = tempRoot.appendingPathComponent("IMG_A.jpg")
        try Data([1]).write(to: sibling)
        store.remove(in: tempRoot)

        XCTAssertNil(store.load(in: tempRoot))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sibling.path))
        store.remove(in: tempRoot)   // second removal is also a no-op
    }
}
