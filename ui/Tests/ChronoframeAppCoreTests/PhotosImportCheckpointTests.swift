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

    func testResourceRoleDefaultsToOriginal() {
        let resource = PhotosExportableResource(assetID: "A", resourceIndex: 0, fileExtension: "heic", originalFilename: "IMG_A.HEIC")
        XCTAssertEqual(resource.role, .original)
        let edited = PhotosExportableResource(
            assetID: "A", resourceIndex: 1, fileExtension: "jpg", originalFilename: "FullSizeRender.jpg", fileSize: 5, role: .editedRender
        )
        XCTAssertEqual(edited.role, .editedRender)
        XCTAssertNotEqual(resource, edited)
    }

    func testEditedStillResourceDefaultsToNilForExistingDoubles() async throws {
        struct LegacyDouble: PhotosResourceExporting {
            func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] { [] }
            func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {}
        }
        let edited = try await LegacyDouble().editedStillResource(forAssetID: "A")
        XCTAssertNil(edited)
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
        XCTAssertTrue(text.contains("\"version\" : \(PhotosImportCheckpoint.version)"))
        try text.replacingOccurrences(of: "\"version\" : \(PhotosImportCheckpoint.version)", with: "\"version\" : 99")
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

    // MARK: - Edited versions (EPR WP-05)

    /// Written by the pre-WP-05 encoder (version 1, no edited-version keys).
    private let versionOneJSON = #"""
{
  "completed" : [
    {
      "assetID" : "A",
      "files" : [
        {
          "assetID" : "A",
          "path" : "\/staging\/IMG_A.HEIC",
          "stagingStem" : "IMG_A"
        }
      ],
      "sourceDateHints" : {
        "\/staging\/IMG_A.HEIC" : {
          "identity" : "10_d-\/staging\/IMG_A.HEIC",
          "resolvedDate" : {
            "confidence" : "high",
            "date" : "2020-09-13T12:26:40Z",
            "source" : "photoMetadata"
          }
        }
      }
    }
  ],
  "createdAt" : "2023-11-14T22:13:20Z",
  "destinationBookmarkKeys" : [
    "k1"
  ],
  "destinationPath" : "\/tmp\/dest",
  "failures" : [
    {
      "assetID" : "B",
      "message" : "iCloud unavailable"
    }
  ],
  "importID" : "11111111-2222-3333-4444-555555555555",
  "plan" : {
    "entries" : [
      {
        "assetID" : "A",
        "creationDate" : "2020-09-13T12:26:40Z",
        "mediaKind" : "photo",
        "stagingStem" : "IMG_A"
      },
      {
        "assetID" : "B",
        "creationDate" : "2020-09-13T12:26:40Z",
        "mediaKind" : "photo",
        "stagingStem" : "IMG_B"
      }
    ]
  },
  "state" : "stopped",
  "updatedAt" : "2023-11-14T22:13:25Z",
  "version" : 1
}
"""#

    func testOldCheckpointDecodesWithEditedVersionsOff() throws {
        let url = tempRoot.appendingPathComponent(PhotosImportCheckpoint.filename)
        try Data(versionOneJSON.utf8).write(to: url)

        let loaded = try XCTUnwrap(PhotosImportFileCheckpointStore().load(in: tempRoot))

        XCTAssertEqual(loaded.version, 1)
        XCTAssertFalse(loaded.includeEditedVersions)
        XCTAssertTrue(loaded.variantFailures.isEmpty)
        XCTAssertEqual(loaded.completed.count, 1)
        XCTAssertNil(loaded.completed[0].editedFile)
        XCTAssertEqual(loaded.completed[0].files.map(\.stagingStem), ["IMG_A"])
        XCTAssertEqual(loaded.failures.map(\.assetID), ["B"])
        XCTAssertEqual(loaded.state, .stopped)
        XCTAssertEqual(loaded.importID, UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
    }

    func testCheckpointRoundTripsEditedFileAndVariantFailure() throws {
        XCTAssertEqual(PhotosImportCheckpoint.version, 2)
        var checkpoint = PhotosImportCheckpoint(
            importID: UUID(),
            createdAt: t0,
            destinationPath: "/tmp/dest",
            destinationBookmarkKeys: ["k1"],
            plan: plan(["A", "B"]),
            includeEditedVersions: true
        )
        let edited = PhotosExportedFile(assetID: "A", stagingStem: "IMG_A-edited", path: "/staging/IMG_A-edited.jpg")
        let base = record("A", names: ["IMG_A.HEIC"])
        checkpoint.recordCompleted(
            PhotosCompletedAssetRecord(assetID: "A", files: base.files, sourceDateHints: base.sourceDateHints, editedFile: edited),
            at: t0.addingTimeInterval(1)
        )
        checkpoint.recordCompleted(record("B", names: ["IMG_B.HEIC"]), at: t0.addingTimeInterval(2))
        checkpoint.recordVariantFailure(
            PhotosVariantFailure(assetID: "B", reason: .editedRenderUnavailable),
            at: t0.addingTimeInterval(3)
        )

        let store = PhotosImportFileCheckpointStore()
        try store.save(checkpoint, in: tempRoot)
        let loaded = try XCTUnwrap(store.load(in: tempRoot))

        XCTAssertEqual(loaded, checkpoint)
        XCTAssertEqual(loaded.version, 2)
        XCTAssertTrue(loaded.includeEditedVersions)
        XCTAssertEqual(loaded.completed[0].editedFile, edited)
        XCTAssertNil(loaded.completed[1].editedFile)
        XCTAssertEqual(loaded.variantFailures, [PhotosVariantFailure(assetID: "B", reason: .editedRenderUnavailable)])
        XCTAssertEqual(loaded.updatedAt.timeIntervalSince1970, t0.addingTimeInterval(3).timeIntervalSince1970, accuracy: 1)
        // A variant failure never removes the asset from "completed".
        XCTAssertEqual(loaded.completedAssetIDs, ["A", "B"])
        XCTAssertTrue(loaded.remainingEntries.isEmpty)
    }

    /// D-EPR-119: the "edited video or Live Photo not included" count lives in
    /// the checkpoint, so it survives a Resume. No version change; older files
    /// decode with none.
    func testNotIncludedAssetIDsRoundTripAndOldCheckpointsHaveNone() throws {
        var checkpoint = PhotosImportCheckpoint(
            importID: UUID(), createdAt: t0, destinationPath: "/tmp/dest", destinationBookmarkKeys: [],
            plan: plan(["A", "B"]), includeEditedVersions: true
        )
        XCTAssertTrue(checkpoint.editedNotIncludedAssetIDs.isEmpty)
        checkpoint.recordCompleted(record("A", names: ["IMG_A.HEIC"]), at: t0.addingTimeInterval(1))
        checkpoint.recordEditedNotIncluded(assetID: "A", at: t0.addingTimeInterval(2))

        let store = PhotosImportFileCheckpointStore()
        try store.save(checkpoint, in: tempRoot)
        let loaded = try XCTUnwrap(store.load(in: tempRoot))

        XCTAssertEqual(PhotosImportCheckpoint.version, 2)
        XCTAssertEqual(loaded, checkpoint)
        XCTAssertEqual(loaded.editedNotIncludedAssetIDs, ["A"])
        XCTAssertEqual(loaded.updatedAt.timeIntervalSince1970, t0.addingTimeInterval(2).timeIntervalSince1970, accuracy: 1)

        try Data(versionOneJSON.utf8).write(to: tempRoot.appendingPathComponent(PhotosImportCheckpoint.filename))
        XCTAssertEqual(try XCTUnwrap(store.load(in: tempRoot)).editedNotIncludedAssetIDs, [])
    }

    /// D-EPR-119: an asset that resume validation drops is exported again, so
    /// its earlier variant failure and not-included entry are stale.
    func testDiscardCompletedClearsStaleVariantFailure() {
        var checkpoint = PhotosImportCheckpoint(
            importID: UUID(), createdAt: t0, destinationPath: "/tmp/dest", destinationBookmarkKeys: [],
            plan: plan(["A", "B", "C"]), includeEditedVersions: true
        )
        for id in ["A", "B", "C"] {
            checkpoint.recordCompleted(record(id, names: ["IMG_\(id).HEIC"]), at: t0)
        }
        checkpoint.recordVariantFailure(PhotosVariantFailure(assetID: "A", reason: .editedRenderUnavailable), at: t0)
        checkpoint.recordVariantFailure(PhotosVariantFailure(assetID: "C", reason: .editedRenderUnavailable), at: t0)
        checkpoint.recordEditedNotIncluded(assetID: "B", at: t0)
        checkpoint.recordEditedNotIncluded(assetID: "C", at: t0)

        checkpoint.discardCompleted(assetIDs: ["A", "B"])

        XCTAssertEqual(checkpoint.completedAssetIDs, ["C"])
        XCTAssertEqual(checkpoint.variantFailures.map(\.assetID), ["C"], "Only the discarded assets' failures are dropped")
        XCTAssertEqual(checkpoint.editedNotIncludedAssetIDs, ["C"])
    }

    func testCheckpointLoaderRejectsUnknownVersion() throws {
        let url = tempRoot.appendingPathComponent(PhotosImportCheckpoint.filename)
        let store = PhotosImportFileCheckpointStore()
        try Data(versionOneJSON.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 3").utf8).write(to: url)
        XCTAssertNil(store.load(in: tempRoot))
        try Data(versionOneJSON.replacingOccurrences(of: "\"version\" : 1", with: "\"version\" : 0").utf8).write(to: url)
        XCTAssertNil(store.load(in: tempRoot))
    }
}
