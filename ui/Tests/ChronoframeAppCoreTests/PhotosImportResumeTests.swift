import Combine
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

private enum ScriptedError: Error { case boom }

private struct ResumeStubAccess: PhotosLibraryAccessing {
    let status: PhotosAuthorizationStatus
    func currentAuthorization() -> PhotosAuthorizationStatus { status }
    func requestReadAccess() async -> PhotosAuthorizationStatus { status }
}

/// Exporter whose assets can fail, have no originals, emit scripted progress,
/// or run a hook (for example "press Stop now") right before their bytes are
/// written. Every ordering in these tests comes from the hook, never a sleep.
private final class ScriptedExporter: PhotosResourceExporting, @unchecked Sendable {
    private let lock = NSLock()
    private var _failingWrites: Set<String> = []
    private var _emptyAssets: Set<String> = []
    private var _listingFailures: Set<String> = []
    private var _progress: [Double] = []
    private var _beforeWrite: (@Sendable (String) async -> Void)?
    private var _writes: [String] = []
    private var _listed: [String] = []

    var failingWrites: Set<String> {
        get { lock.withLock { _failingWrites } }
        set { lock.withLock { _failingWrites = newValue } }
    }
    var emptyAssets: Set<String> {
        get { lock.withLock { _emptyAssets } }
        set { lock.withLock { _emptyAssets = newValue } }
    }
    var listingFailures: Set<String> {
        get { lock.withLock { _listingFailures } }
        set { lock.withLock { _listingFailures = newValue } }
    }
    var progress: [Double] {
        get { lock.withLock { _progress } }
        set { lock.withLock { _progress = newValue } }
    }
    var beforeWrite: (@Sendable (String) async -> Void)? {
        get { lock.withLock { _beforeWrite } }
        set { lock.withLock { _beforeWrite = newValue } }
    }
    var writes: [String] { lock.withLock { _writes } }
    var listed: [String] { lock.withLock { _listed } }

    func resetRecording() {
        lock.withLock {
            _writes = []
            _listed = []
        }
    }

    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        lock.withLock { _listed.append(id) }
        if listingFailures.contains(id) { throw ScriptedError.boom }
        if emptyAssets.contains(id) { return [] }
        return [PhotosExportableResource(assetID: id, resourceIndex: 0, fileExtension: "jpg", originalFilename: "\(id).jpg")]
    }

    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        try await writeResource(resource, to: destinationURL, onProgress: { _ in })
    }

    func writeResource(
        _ resource: PhotosExportableResource,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        lock.withLock { _writes.append(resource.assetID) }
        for fraction in progress { onProgress(fraction) }
        if let hook = beforeWrite { await hook(resource.assetID) }
        if failingWrites.contains(resource.assetID) { throw ScriptedError.boom }
        try Data("bytes-\(resource.assetID)".utf8).write(to: destinationURL)
    }
}

/// Wraps the real file store and records every checkpoint it is asked to save.
private final class SpyCheckpointStore: PhotosImportCheckpointStoring, @unchecked Sendable {
    struct Snapshot: Equatable {
        let state: PhotosImportCheckpointState
        let completed: Int
        let failures: Int
    }

    private let inner = PhotosImportFileCheckpointStore()
    private let lock = NSLock()
    private var _saves: [Snapshot] = []

    var saves: [Snapshot] { lock.withLock { _saves } }

    func load(in stagingDirectory: URL) -> PhotosImportCheckpoint? { inner.load(in: stagingDirectory) }
    func save(_ checkpoint: PhotosImportCheckpoint, in stagingDirectory: URL) throws {
        lock.withLock {
            _saves.append(Snapshot(state: checkpoint.state, completed: checkpoint.completed.count, failures: checkpoint.failures.count))
        }
        try inner.save(checkpoint, in: stagingDirectory)
    }
    func remove(in stagingDirectory: URL) { inner.remove(in: stagingDirectory) }
}

/// Wraps the real file store; from the `failFromSave`-th save on (1-based) every
/// save throws, like a full disk. `onSave` runs before each save with its index.
private final class ScriptedCheckpointStore: PhotosImportCheckpointStoring, @unchecked Sendable {
    struct SaveFailure: Error {}

    private let inner = PhotosImportFileCheckpointStore()
    private let lock = NSLock()
    private var count = 0
    private let failFromSave: Int?
    private let onSave: (@Sendable (Int) -> Void)?

    init(failFromSave: Int? = nil, onSave: (@Sendable (Int) -> Void)? = nil) {
        self.failFromSave = failFromSave
        self.onSave = onSave
    }

    var saveCount: Int { lock.withLock { count } }

    func load(in stagingDirectory: URL) -> PhotosImportCheckpoint? { inner.load(in: stagingDirectory) }
    func save(_ checkpoint: PhotosImportCheckpoint, in stagingDirectory: URL) throws {
        let index = lock.withLock { () -> Int in count += 1; return count }
        onSave?(index)
        if let failFromSave, index >= failFromSave { throw SaveFailure() }
        try inner.save(checkpoint, in: stagingDirectory)
    }
    func remove(in stagingDirectory: URL) { inner.remove(in: stagingDirectory) }
}

private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    func next() -> Int { lock.withLock { count += 1; return count } }
}

final class PhotosImportResumeTests: XCTestCase {
    private var created: [URL] = []

    override func tearDown() {
        for url in created { try? FileManager.default.removeItem(at: url) }
        created = []
        super.tearDown()
    }

    // MARK: Helpers

    private let destinationA = PhotosImportStore.DestinationCapture(path: "/tmp/pir-dest-a", bookmarkKeys: ["k"])
    private let destinationB = PhotosImportStore.DestinationCapture(path: "/tmp/pir-dest-b", bookmarkKeys: ["k"])
    private let fileStore = PhotosImportFileCheckpointStore()

    private func makeTempParent() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-resume-\(UUID().uuidString)", isDirectory: true)
        created.append(url)
        return url
    }

    private func asset(_ id: String) -> PhotosAssetSummary {
        PhotosAssetSummary(
            id: id, mediaKind: .photo, creationDate: nil, pixelWidth: 100, pixelHeight: 100,
            originalFilename: "\(id).jpg", isFavorite: false, isCloudStoredOnly: false
        )
    }

    private func plentyOfSpaceExecutor(_ exporter: any PhotosResourceExporting) -> PhotosExportExecutor {
        PhotosExportExecutor(exporter: exporter, timeZone: TimeZone(secondsFromGMT: 0) ?? .current, freeSpaceProvider: { _ in nil })
    }

    @MainActor
    private func makeStore(
        ids: [String],
        exporter: ScriptedExporter,
        staging: URL,
        authorization: PhotosAuthorizationStatus = .authorized,
        checkpointStore: any PhotosImportCheckpointStoring = PhotosImportFileCheckpointStore(),
        factory: ((any PhotosResourceExporting) -> PhotosExportExecutor)? = nil
    ) -> PhotosImportStore {
        let album = PhotosAlbumSummary(id: "all", title: "all", kind: .allPhotos, approximateCount: ids.count)
        let store = PhotosImportStore(
            access: ResumeStubAccess(status: authorization),
            catalog: FakePhotosCatalog(albums: [album], assetsByAlbum: ["all": ids.map(asset)]),
            exporter: exporter,
            stagingParentURL: staging,
            pageSize: 50,
            checkpointStore: checkpointStore,
            exportExecutorFactory: factory ?? { [self] in plentyOfSpaceExecutor($0) },
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        store.loadAlbumsIfAuthorized()
        for id in ids { store.toggleSelection(id) }
        return store
    }

    private func importDirectories(in parent: URL) -> [URL] {
        let children = (try? FileManager.default.contentsOfDirectory(
            at: parent, includingPropertiesForKeys: [.isDirectoryKey], options: []
        )) ?? []
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
    }

    private func onlyImportDirectory(in parent: URL, file: StaticString = #filePath, line: UInt = #line) -> URL {
        let dirs = importDirectories(in: parent)
        XCTAssertEqual(dirs.count, 1, "Expected exactly one import directory", file: file, line: line)
        return dirs.first ?? parent
    }

    @discardableResult
    private func seedCheckpoint(
        parent: URL,
        name: String,
        state: PhotosImportCheckpointState,
        assetIDs: [String],
        planAssetIDs: [String]? = nil,
        updatedAt: Date,
        destinationPath: String = "/tmp/pir-dest-a",
        omitHintFor: Set<String> = [],
        recordedPathOverride: [String: String] = [:]
    ) throws -> URL {
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let plan = PhotosExportPlan(entries: (planAssetIDs ?? assetIDs).map {
            PhotosAssetExportEntry(assetID: $0, mediaKind: .photo, stagingStem: $0)
        })
        var checkpoint = PhotosImportCheckpoint(
            importID: UUID(), createdAt: updatedAt, destinationPath: destinationPath,
            destinationBookmarkKeys: ["k"], plan: plan
        )
        for id in assetIDs {
            let data = Data("bytes-\(id)".utf8)
            let fileURL = dir.appendingPathComponent("\(id).jpg")
            try data.write(to: fileURL)
            let recordedPath = recordedPathOverride[id] ?? fileURL.path
            checkpoint.recordCompleted(
                PhotosCompletedAssetRecord(
                    assetID: id,
                    files: [PhotosExportedFile(assetID: id, stagingStem: id, path: recordedPath)],
                    sourceDateHints: omitHintFor.contains(id) ? [:] : [
                        SourceDateHint.pathKey(for: recordedPath): SourceDateHint(
                            identity: FileIdentity(size: Int64(data.count), digest: "digest-\(id)"),
                            resolvedDate: .unknown
                        )
                    ]
                ),
                at: updatedAt
            )
        }
        checkpoint.setState(state, at: updatedAt)
        try fileStore.save(checkpoint, in: dir)
        return dir
    }

    private func fixedDate(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_600_000_000 + offset)
    }

    private func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    // MARK: Acceptance tests

    @MainActor
    func testPrepareWritesCheckpointAfterEachCompletedAsset() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        exporter.failingWrites = ["b"]
        let spy = SpyCheckpointStore()
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging, checkpointStore: spy)

        let context = await store.prepareImport(destination: destinationA)

        let unwrapped = try XCTUnwrap(context)
        XCTAssertEqual(unwrapped.assetIDs, ["a", "c"])
        XCTAssertEqual(spy.saves, [
            .init(state: .inProgress, completed: 0, failures: 0),
            .init(state: .inProgress, completed: 1, failures: 0),
            .init(state: .inProgress, completed: 1, failures: 1),
            .init(state: .inProgress, completed: 2, failures: 1),
            .init(state: .ready, completed: 2, failures: 1),
        ])
        let checkpoint = try XCTUnwrap(fileStore.load(in: unwrapped.stagingDirectoryURL))
        XCTAssertEqual(checkpoint.state, .ready)
        XCTAssertEqual(checkpoint.completed.map(\.assetID), ["a", "c"])
        XCTAssertEqual(checkpoint.failures.map(\.assetID), ["b"])
        XCTAssertEqual(checkpoint.destinationPath, destinationA.path)
        XCTAssertNil(store.preparation)
        XCTAssertFalse(store.isPreparingImport)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testStopKeepsCompletedAssetsAndMarksStopped() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging)
        exporter.beforeWrite = { id in
            if id == "c" { await MainActor.run { store.cancelPreparation() } }
        }

        let context = await store.prepareImport(destination: destinationA)

        XCTAssertNil(context)
        XCTAssertNil(store.preparation)
        let dir = onlyImportDirectory(in: staging)
        let checkpoint = try XCTUnwrap(fileStore.load(in: dir))
        XCTAssertEqual(checkpoint.state, .stopped)
        XCTAssertEqual(checkpoint.completed.map(\.assetID), ["a", "b"])
        for file in checkpoint.completed.flatMap(\.files) {
            XCTAssertTrue(exists(file.path), "A completed asset's file must survive Stop: \(file.path)")
        }
        XCTAssertFalse(exists(dir.appendingPathComponent("c.jpg").path), "The in-flight asset is rolled back")
        XCTAssertEqual(
            store.statusMessage,
            "Import stopped. 2 of 3 items are ready and were kept. Resume whenever you like. Your Photos library was not changed."
        )
        let resumable = try XCTUnwrap(store.resumable)
        XCTAssertEqual(resumable.readyCount, 2)
        XCTAssertEqual(resumable.totalCount, 3)
        XCTAssertTrue(resumable.destinationMatches)
    }

    @MainActor
    func testResumeSkipsCompletedAndMergesHints() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging)
        exporter.beforeWrite = { id in
            if id == "c" { await MainActor.run { store.cancelPreparation() } }
        }
        _ = await store.prepareImport(destination: destinationA)
        let stoppedDir = onlyImportDirectory(in: staging)
        let stoppedCheckpoint = try XCTUnwrap(fileStore.load(in: stoppedDir))
        exporter.beforeWrite = nil
        exporter.resetRecording()

        let context = await store.resumeImport(destination: destinationA)

        let unwrapped = try XCTUnwrap(context)
        XCTAssertEqual(unwrapped.assetIDs, ["a", "b", "c"], "All three, in plan order")
        XCTAssertEqual(exporter.writes, ["c"], "Only the unfinished asset is written on resume")
        XCTAssertEqual(exporter.listed, ["c"])
        XCTAssertEqual(unwrapped.stagingDirectoryURL.lastPathComponent, stoppedDir.lastPathComponent)
        XCTAssertEqual(unwrapped.sourceDateHints.count, 3)
        for (key, hint) in stoppedCheckpoint.mergedSourceDateHints {
            XCTAssertEqual(unwrapped.sourceDateHints[key], hint, "Hints from the earlier run are carried over")
        }
        XCTAssertEqual(unwrapped.destinationPath, destinationA.path)
        XCTAssertNil(store.resumable)
        XCTAssertNil(store.preparation)
        let finished = try XCTUnwrap(fileStore.load(in: stoppedDir))
        XCTAssertEqual(finished.state, .ready)
        XCTAssertEqual(finished.completed.map(\.assetID), ["a", "b", "c"])
    }

    @MainActor
    func testResumeRefusedWhenDestinationDiffers() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging)
        exporter.beforeWrite = { id in
            if id == "c" { await MainActor.run { store.cancelPreparation() } }
        }
        _ = await store.prepareImport(destination: destinationA)
        let dir = onlyImportDirectory(in: staging)
        exporter.beforeWrite = nil
        exporter.resetRecording()

        store.refreshResumableImport(destination: destinationB)
        XCTAssertEqual(try XCTUnwrap(store.resumable).destinationMatches, false)

        let context = await store.resumeImport(destination: destinationB)

        XCTAssertNil(context)
        XCTAssertEqual(
            store.statusMessage,
            "This import was prepared for a different destination. Choose that destination again to resume, or discard it."
        )
        XCTAssertTrue(exporter.writes.isEmpty)
        XCTAssertNotNil(store.resumable, "A refused resume keeps the checkpoint")
        XCTAssertTrue(exists(dir.path))

        store.refreshResumableImport(destination: nil)
        XCTAssertEqual(try XCTUnwrap(store.resumable).destinationMatches, false)
        store.refreshResumableImport(destination: destinationA)
        XCTAssertEqual(try XCTUnwrap(store.resumable).destinationMatches, true)
    }

    @MainActor
    func testResumeRefusedWhenPhotosAccessIsNotGranted() async throws {
        let staging = makeTempParent()
        try seedCheckpoint(parent: staging, name: "one", state: .stopped, assetIDs: ["a"], updatedAt: fixedDate(0))
        let exporter = ScriptedExporter()
        let store = makeStore(ids: ["a"], exporter: exporter, staging: staging, authorization: .denied)
        store.refreshResumableImport(destination: destinationA)
        XCTAssertNotNil(store.resumable)

        let context = await store.resumeImport(destination: destinationA)

        XCTAssertNil(context)
        XCTAssertEqual(store.statusMessage, "Chronoframe needs access to Photos to continue this import.")
        XCTAssertTrue(exporter.writes.isEmpty)
        XCTAssertNotNil(store.resumable)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testLowSpaceMarksCheckpointAndOffersResume() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        let calls = CallCounter()
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging, factory: { exporter in
            PhotosExportExecutor(
                exporter: exporter,
                timeZone: TimeZone(secondsFromGMT: 0) ?? .current,
                freeSpaceFloorBytes: 2 * 1024 * 1024 * 1024,
                freeSpaceProvider: { _ in calls.next() == 1 ? 10 * 1024 * 1024 * 1024 : 1 * 1024 * 1024 * 1024 }
            )
        })

        let context = await store.prepareImport(destination: destinationA)

        XCTAssertNil(context)
        let dir = onlyImportDirectory(in: staging)
        let checkpoint = try XCTUnwrap(fileStore.load(in: dir))
        XCTAssertEqual(checkpoint.state, .lowSpace)
        XCTAssertEqual(checkpoint.completed.map(\.assetID), ["a"])
        XCTAssertEqual(exporter.writes, ["a"], "Nothing of asset b is written when space is low")
        for file in checkpoint.completed.flatMap(\.files) { XCTAssertTrue(exists(file.path)) }
        XCTAssertEqual(
            store.statusMessage,
            "Chronoframe paused the import because the drive holding its staging folder is almost full. 1 of 3 items are ready and were kept. Free up space, then resume. Your Photos library was not changed."
        )
        let resumable = try XCTUnwrap(store.resumable)
        XCTAssertEqual(resumable.readyCount, 1)
        XCTAssertEqual(resumable.totalCount, 3)
        XCTAssertNil(store.preparation)
    }

    @MainActor
    func testRefreshRemovesInvalidAndConsumedStaging() throws {
        let staging = makeTempParent()
        let noCheckpoint = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: noCheckpoint, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: noCheckpoint.appendingPathComponent("stray.jpg"))
        let consumed = try seedCheckpoint(parent: staging, name: "consumed", state: .ready, assetIDs: ["a"], updatedAt: fixedDate(10))
        let damaged = try seedCheckpoint(parent: staging, name: "damaged", state: .stopped, assetIDs: ["a", "b"], updatedAt: fixedDate(20))
        try FileManager.default.removeItem(at: damaged.appendingPathComponent("b.jpg"))
        let resized = try seedCheckpoint(parent: staging, name: "resized", state: .stopped, assetIDs: ["a"], updatedAt: fixedDate(25))
        try Data("a-different-size".utf8).write(to: resized.appendingPathComponent("a.jpg"))
        let valid = try seedCheckpoint(parent: staging, name: "valid", state: .stopped, assetIDs: ["a", "b"], updatedAt: fixedDate(30))
        let strayFile = staging.appendingPathComponent("notes.txt")
        try Data("keep".utf8).write(to: strayFile)

        let store = makeStore(ids: ["a"], exporter: ScriptedExporter(), staging: staging)
        store.refreshResumableImport(destination: destinationA)

        XCTAssertFalse(exists(noCheckpoint.path))
        XCTAssertFalse(exists(consumed.path))
        XCTAssertFalse(exists(damaged.path))
        XCTAssertFalse(exists(resized.path))
        XCTAssertTrue(exists(valid.path))
        XCTAssertTrue(exists(strayFile.path), "Only subdirectories are examined")
        let resumable = try XCTUnwrap(store.resumable)
        XCTAssertEqual(resumable.stagingDirectoryURL.lastPathComponent, "valid")
        XCTAssertEqual(resumable.readyCount, 2)
        XCTAssertEqual(resumable.interruptedAt, fixedDate(30))
        XCTAssertTrue(resumable.destinationMatches)
    }

    @MainActor
    func testRefreshKeepsNewestWhenSeveralAreResumable() throws {
        let staging = makeTempParent()
        let older = try seedCheckpoint(parent: staging, name: "older", state: .stopped, assetIDs: ["a"], updatedAt: fixedDate(100))
        let newest = try seedCheckpoint(parent: staging, name: "newest", state: .lowSpace, assetIDs: ["a", "b"], updatedAt: fixedDate(300))
        let middle = try seedCheckpoint(parent: staging, name: "middle", state: .inProgress, assetIDs: ["a"], updatedAt: fixedDate(200))

        let store = makeStore(ids: ["a"], exporter: ScriptedExporter(), staging: staging)
        store.refreshResumableImport(destination: destinationA)

        XCTAssertTrue(exists(newest.path))
        XCTAssertFalse(exists(older.path))
        XCTAssertFalse(exists(middle.path))
        XCTAssertEqual(try XCTUnwrap(store.resumable).stagingDirectoryURL.lastPathComponent, "newest")
        XCTAssertEqual(importDirectories(in: staging).count, 1)

        // Nothing resumable: the property clears.
        store.discardResumableImport()
        XCTAssertNil(store.resumable)
        XCTAssertFalse(exists(newest.path))
        store.refreshResumableImport(destination: destinationA)
        XCTAssertNil(store.resumable)
    }

    @MainActor
    func testNewPrepareSupersedesResumableImport() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging)
        exporter.beforeWrite = { id in
            if id == "c" { await MainActor.run { store.cancelPreparation() } }
        }
        _ = await store.prepareImport(destination: destinationA)
        let oldDir = onlyImportDirectory(in: staging)
        XCTAssertNotNil(store.resumable)
        exporter.beforeWrite = nil

        let context = await store.prepareImport(destination: destinationA)

        let unwrapped = try XCTUnwrap(context)
        XCTAssertFalse(exists(oldDir.path), "The interrupted import's directory is removed")
        XCTAssertNotEqual(unwrapped.stagingDirectoryURL.lastPathComponent, oldDir.lastPathComponent)
        XCTAssertEqual(importDirectories(in: staging).count, 1)
        let checkpoint = try XCTUnwrap(fileStore.load(in: unwrapped.stagingDirectoryURL))
        XCTAssertEqual(checkpoint.importID, unwrapped.importID)
        XCTAssertEqual(checkpoint.state, .ready)
        XCTAssertNil(store.resumable)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testPurgeStagingParentNoLongerExists() async throws {
        // 1. A fresh store with two valid checkpoints: a new prepare keeps
        //    nothing of the old ones (older removed by refresh, newest by the
        //    supersede step) and leaves only its own directory. Files that
        //    are not import directories survive; the parent is never purged.
        let staging = makeTempParent()
        let olderDir = try seedCheckpoint(parent: staging, name: "older", state: .stopped, assetIDs: ["a"], updatedAt: fixedDate(100))
        let newerDir = try seedCheckpoint(parent: staging, name: "newer", state: .stopped, assetIDs: ["a"], updatedAt: fixedDate(200))
        let strayFile = staging.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: strayFile)
        let store = makeStore(ids: ["a", "b"], exporter: ScriptedExporter(), staging: staging)

        let context = await store.prepareImport(destination: destinationA)

        let unwrapped = try XCTUnwrap(context)
        XCTAssertFalse(exists(olderDir.path))
        XCTAssertFalse(exists(newerDir.path))
        XCTAssertEqual(importDirectories(in: staging).map(\.lastPathComponent), [unwrapped.stagingDirectoryURL.lastPathComponent])
        XCTAssertTrue(exists(strayFile.path), "The staging parent is not purged")

        // 2. A prepare that fails outright (the staging parent cannot hold a
        //    directory) removes only its own directory, never the parent path.
        let blockedParent = makeTempParent()
        try Data("not a directory".utf8).write(to: blockedParent)
        let blockedStore = makeStore(ids: ["a"], exporter: ScriptedExporter(), staging: blockedParent)

        let failed = await blockedStore.prepareImport(destination: destinationA)

        XCTAssertNil(failed)
        XCTAssertTrue(exists(blockedParent.path), "A failed prepare never removes the staging parent")
        XCTAssertEqual(
            blockedStore.statusMessage,
            "Chronoframe couldn't prepare the Photos import. Your Photos library was not changed."
        )
        XCTAssertNil(blockedStore.preparation)
    }

    @MainActor
    func testPreparationProgressTracksEventsAndCloudWait() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        exporter.progress = [0.4, 1.0]
        let store = makeStore(ids: ["a", "b"], exporter: exporter, staging: staging)
        var observed: [PhotosPreparationProgress?] = []
        let cancellable = store.$preparation.sink { observed.append($0) }
        defer { cancellable.cancel() }

        let context = await store.prepareImport(destination: destinationA)

        XCTAssertNotNil(context)
        var distinct: [PhotosPreparationProgress?] = []
        for value in observed where distinct.last.map({ $0 != value }) ?? true {
            distinct.append(value)
        }
        func progress(_ completed: Int, _ label: String?, _ waiting: Bool) -> PhotosPreparationProgress {
            PhotosPreparationProgress(total: 2, completed: completed, failed: 0, currentAssetLabel: label, isWaitingForCloud: waiting)
        }
        XCTAssertEqual(distinct, [
            nil,
            progress(0, nil, false),
            progress(0, "a.jpg", false),
            progress(0, "a.jpg", true),
            progress(1, nil, false),
            progress(1, "b.jpg", false),
            progress(1, "b.jpg", true),
            progress(2, nil, false),
            nil,
        ])
        XCTAssertNil(store.preparation)
        XCTAssertFalse(store.isPreparingImport)
    }

    @MainActor
    func testEmptyResultRemovesDirectoryAndKeepsLegacyMessage() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        exporter.emptyAssets = ["a", "b"]
        let store = makeStore(ids: ["a", "b"], exporter: exporter, staging: staging)

        let context = await store.prepareImport(destination: destinationA)

        XCTAssertNil(context)
        XCTAssertEqual(
            store.statusMessage,
            "Chronoframe couldn't read the selected items from Photos, so there is nothing to import. Your Photos library was not changed."
        )
        XCTAssertTrue(importDirectories(in: staging).isEmpty, "The empty import's directory is removed")
        XCTAssertNil(store.resumable)
        XCTAssertNil(store.preparation)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testResumeRemovesFilesTheCheckpointDoesNotRecord() async throws {
        let staging = makeTempParent()
        let dir = try seedCheckpoint(
            parent: staging, name: "crashed", state: .inProgress,
            assetIDs: ["a"], planAssetIDs: ["a", "b"], updatedAt: fixedDate(50)
        )
        let recorded = dir.appendingPathComponent("a.jpg")
        let recordedBytes = try Data(contentsOf: recorded)
        try Data("half of a pair".utf8).write(to: dir.appendingPathComponent("b.heic"))
        try Data("partial".utf8).write(to: dir.appendingPathComponent(".x.photoexport.tmp"))
        let exporter = ScriptedExporter()
        exporter.listingFailures = ["b"]
        let store = makeStore(ids: ["a", "b"], exporter: exporter, staging: staging)
        store.refreshResumableImport(destination: destinationA)
        XCTAssertNotNil(store.resumable)

        let context = await store.resumeImport(destination: destinationA)

        let unwrapped = try XCTUnwrap(context)
        XCTAssertEqual(unwrapped.assetIDs, ["a"])
        let remaining = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(remaining, ["a.jpg", PhotosImportCheckpoint.filename].sorted())
        XCTAssertEqual(try Data(contentsOf: recorded), recordedBytes, "A recorded file is never touched")
        let checkpoint = try XCTUnwrap(fileStore.load(in: dir))
        XCTAssertEqual(checkpoint.failures.map(\.assetID), ["b"])
        XCTAssertEqual(checkpoint.state, .ready)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testResumeFailsClosedWhenAnUnrecordedFileCannotBeRemoved() async throws {
        let staging = makeTempParent()
        let dir = try seedCheckpoint(
            parent: staging, name: "locked", state: .inProgress,
            assetIDs: ["a"], planAssetIDs: ["a", "b"], updatedAt: fixedDate(50)
        )
        let orphan = dir.appendingPathComponent("b.heic")
        try Data("half of a pair".utf8).write(to: orphan)
        let exporter = ScriptedExporter()
        let store = makeStore(ids: ["a", "b"], exporter: exporter, staging: staging)
        store.refreshResumableImport(destination: destinationA)
        XCTAssertNotNil(store.resumable)

        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let context = await store.resumeImport(destination: destinationA)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)

        XCTAssertNil(context)
        XCTAssertEqual(
            store.statusMessage,
            "Chronoframe couldn't prepare the Photos import. Your Photos library was not changed."
        )
        XCTAssertTrue(exporter.writes.isEmpty, "Nothing is exported when staging cannot be made clean")
        XCTAssertTrue(exists(orphan.path))
        XCTAssertTrue(exists(dir.appendingPathComponent("a.jpg").path))
        XCTAssertNotNil(fileStore.load(in: dir), "The checkpoint is kept")
        XCTAssertNotNil(store.resumable)
        XCTAssertNil(store.preparation)
    }

    @MainActor
    func testResumeRevalidatesDestinationAndFilesAtResumeTime() async throws {
        // Part A: the destination changed after the last refresh.
        let stagingA = makeTempParent()
        let dirA = try seedCheckpoint(
            parent: stagingA, name: "pinned", state: .stopped,
            assetIDs: ["a"], planAssetIDs: ["a", "b"], updatedAt: fixedDate(50)
        )
        let exporterA = ScriptedExporter()
        let storeA = makeStore(ids: ["a", "b"], exporter: exporterA, staging: stagingA)
        storeA.refreshResumableImport(destination: destinationA)
        XCTAssertEqual(try XCTUnwrap(storeA.resumable).destinationMatches, true)

        let changed = await storeA.resumeImport(destination: destinationB)

        XCTAssertNil(changed)
        XCTAssertEqual(
            storeA.statusMessage,
            "This import was prepared for a different destination. Choose that destination again to resume, or discard it."
        )
        XCTAssertTrue(exporterA.writes.isEmpty)
        XCTAssertTrue(exists(dirA.path))
        XCTAssertNotNil(fileStore.load(in: dirA))
        XCTAssertEqual(try XCTUnwrap(storeA.resumable).destinationMatches, false)

        // Part B: a recorded file disappeared after the last refresh.
        let stagingB = makeTempParent()
        let dirB = try seedCheckpoint(
            parent: stagingB, name: "damaged", state: .stopped,
            assetIDs: ["a", "b"], planAssetIDs: ["a", "b", "c"], updatedAt: fixedDate(50)
        )
        let exporterB = ScriptedExporter()
        let storeB = makeStore(ids: ["a", "b", "c"], exporter: exporterB, staging: stagingB)
        storeB.refreshResumableImport(destination: destinationA)
        XCTAssertEqual(try XCTUnwrap(storeB.resumable).destinationMatches, true)
        try FileManager.default.removeItem(at: dirB.appendingPathComponent("b.jpg"))

        let damaged = await storeB.resumeImport(destination: destinationA)

        XCTAssertNil(damaged)
        XCTAssertTrue(exporterB.writes.isEmpty)
        XCTAssertNil(storeB.resumable)
        XCTAssertFalse(exists(dirB.path), "Refresh removes the damaged directory")
        XCTAssertEqual(
            storeB.statusMessage,
            "Chronoframe couldn't prepare the Photos import. Your Photos library was not changed."
        )
    }

    // MARK: Additional coverage

    @MainActor
    func testAssetWithNoOriginalResourceIsRecordedAsFailure() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        exporter.emptyAssets = ["b"]
        let store = makeStore(ids: ["a", "b"], exporter: exporter, staging: staging)

        let context = await store.prepareImport(destination: destinationA)

        let unwrapped = try XCTUnwrap(context)
        XCTAssertEqual(unwrapped.assetIDs, ["a"])
        let checkpoint = try XCTUnwrap(fileStore.load(in: unwrapped.stagingDirectoryURL))
        XCTAssertEqual(checkpoint.failures.map(\.assetID), ["b"])
        XCTAssertTrue(checkpoint.remainingEntries.isEmpty, "A failed asset is not retried on resume")
        XCTAssertEqual(
            store.statusMessage,
            "1 item(s) couldn't be read and were skipped. Your Photos library was not changed."
        )
    }

    @MainActor
    func testRefreshLeavesPreparedStagingAlonePendingItsRun() async throws {
        let staging = makeTempParent()
        let store = makeStore(ids: ["a"], exporter: ScriptedExporter(), staging: staging)
        let prepared = await store.prepareImport(destination: destinationA)
        let context = try XCTUnwrap(prepared)

        store.refreshResumableImport(destination: destinationA)

        XCTAssertTrue(exists(context.stagingDirectoryURL.path), "A ready import awaiting its run is not consumed staging")
        store.cleanupStaging(for: context)
        XCTAssertFalse(exists(context.stagingDirectoryURL.path))
        store.refreshResumableImport(destination: destinationA)
        XCTAssertNil(store.resumable)
    }

    // MARK: PR #268 review fixes

    // AGENTS-INVARIANT: 22
    @MainActor
    func testNewPrepareKeepsPriorPreparedStagingUntilItsRunReleasesIt() async throws {
        let staging = makeTempParent()
        let store = makeStore(ids: ["a"], exporter: ScriptedExporter(), staging: staging)
        let firstRaw = await store.prepareImport(destination: destinationA)
        let first = try XCTUnwrap(firstRaw)

        let secondRaw = await store.prepareImport(destination: destinationA)
        let second = try XCTUnwrap(secondRaw)

        XCTAssertTrue(exists(first.stagingDirectoryURL.path), "A run may still be reading the earlier prepared staging")
        XCTAssertTrue(exists(second.stagingDirectoryURL.path))
        store.cleanupStaging(for: first)
        XCTAssertFalse(exists(first.stagingDirectoryURL.path))
        XCTAssertTrue(exists(second.stagingDirectoryURL.path))
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testRefreshOnlyDeletesDirectoriesChronoframeCreated() throws {
        let staging = makeTempParent()
        // Not Chronoframe's: neither a UUID name nor a checkpoint inside.
        let foreign = staging.appendingPathComponent("Family Photos", isDirectory: true)
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        let foreignFile = foreign.appendingPathComponent("IMG_0001.jpg")
        try Data("mine".utf8).write(to: foreignFile)
        // Chronoframe's: a UUID name with no checkpoint (a crash before the first save).
        let orphan = staging.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: orphan, withIntermediateDirectories: true)
        // Chronoframe's: a consumed checkpoint under any name.
        let consumed = try seedCheckpoint(parent: staging, name: "consumed", state: .ready, assetIDs: ["a"], updatedAt: fixedDate(10))

        let store = makeStore(ids: ["a"], exporter: ScriptedExporter(), staging: staging)
        store.refreshResumableImport(destination: destinationA)

        XCTAssertTrue(exists(foreignFile.path), "A folder Chronoframe did not create is never touched")
        XCTAssertFalse(exists(orphan.path))
        XCTAssertFalse(exists(consumed.path))
        XCTAssertTrue(exists(staging.path), "The staging parent is never removed")
        XCTAssertNil(store.resumable)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testCheckpointSaveFailureStopsTheExportInsteadOfContinuing() async throws {
        let staging = makeTempParent()
        let exporter = ScriptedExporter()
        // Save 1 is the initial checkpoint, 2 records "a"; the disk is full from save 3.
        let checkpoints = ScriptedCheckpointStore(failFromSave: 3)
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging, checkpointStore: checkpoints)

        let context = await store.prepareImport(destination: destinationA)

        XCTAssertNil(context, "An import whose progress cannot be saved is not handed to a run")
        XCTAssertNil(store.preparation)
        XCTAssertEqual(
            store.statusMessage,
            "Chronoframe stopped the import because it couldn't save its progress. The drive holding its staging folder may be full. 1 of 3 items are ready and were kept. Free up space, then resume. Your Photos library was not changed."
        )
        let dir = onlyImportDirectory(in: staging)
        let onDisk = try XCTUnwrap(fileStore.load(in: dir))
        XCTAssertEqual(onDisk.completed.map(\.assetID), ["a"], "The checkpoint holds only what the disk accepted")
        XCTAssertNotEqual(onDisk.state, .ready)
        let resumable = try XCTUnwrap(store.resumable)
        XCTAssertEqual(resumable.readyCount, 1)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testCheckpointSaveFailureOnTheLastAssetStillStops() async throws {
        let staging = makeTempParent()
        let checkpoints = ScriptedCheckpointStore(failFromSave: 3)
        let store = makeStore(ids: ["a", "b"], exporter: ScriptedExporter(), staging: staging, checkpointStore: checkpoints)

        let context = await store.prepareImport(destination: destinationA)

        XCTAssertNil(context)
        XCTAssertTrue(try XCTUnwrap(store.statusMessage).hasPrefix("Chronoframe stopped the import because it couldn't save its progress."))
        XCTAssertEqual(try XCTUnwrap(store.resumable).readyCount, 1)
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testFailedNewPrepareKeepsTheSupersededImport() async throws {
        let staging = makeTempParent()
        let old = try seedCheckpoint(parent: staging, name: "old", state: .stopped, assetIDs: ["a", "b"], planAssetIDs: ["a", "b", "c"], updatedAt: fixedDate(10))
        let exporter = ScriptedExporter()
        let store = makeStore(
            ids: ["x"], exporter: exporter, staging: staging,
            checkpointStore: ScriptedCheckpointStore(failFromSave: 1)
        )

        let context = await store.prepareImport(destination: destinationA)

        XCTAssertNil(context)
        XCTAssertTrue(exists(old.path), "Hours of downloads are not deleted for a prepare that never got going")
        XCTAssertTrue(exporter.writes.isEmpty)
        XCTAssertEqual(try XCTUnwrap(store.resumable).stagingDirectoryURL.lastPathComponent, "old")
    }

    @MainActor
    func testSupersededImportIsRemovedOnceTheNewImportSavedItsFirstCheckpoint() async throws {
        let staging = makeTempParent()
        let old = try seedCheckpoint(parent: staging, name: "old", state: .stopped, assetIDs: ["a"], updatedAt: fixedDate(10))
        let oldStillThereAtSave = LockedValues()
        let checkpoints = ScriptedCheckpointStore(onSave: { index in
            oldStillThereAtSave.append(index, FileManager.default.fileExists(atPath: old.path))
        })
        let store = makeStore(ids: ["x"], exporter: ScriptedExporter(), staging: staging, checkpointStore: checkpoints)

        let _raw = await store.prepareImport(destination: destinationA)

        _ = try XCTUnwrap(_raw)

        XCTAssertFalse(exists(old.path))
        XCTAssertEqual(oldStillThereAtSave.value(for: 1), true, "Still there while the first checkpoint is being written")
        XCTAssertEqual(oldStillThereAtSave.value(for: 2), false, "Gone once that checkpoint was saved")
    }

    // AGENTS-INVARIANT: 22
    @MainActor
    func testMissingHintReExportsThatAssetOnlyAndRejectsPathsOutsideStaging() async throws {
        // A missing hint for one asset: the others survive, that one is re-exported.
        let staging = makeTempParent()
        let dir = try seedCheckpoint(
            parent: staging, name: "hintless", state: .stopped,
            assetIDs: ["a", "b", "c"], updatedAt: fixedDate(50), omitHintFor: ["b"]
        )
        let exporter = ScriptedExporter()
        let store = makeStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging)
        store.refreshResumableImport(destination: destinationA)

        let resumable = try XCTUnwrap(store.resumable)
        XCTAssertEqual(resumable.readyCount, 2)
        XCTAssertEqual(resumable.checkpoint.completed.map(\.assetID), ["a", "c"])
        let contextRaw = await store.resumeImport(destination: destinationA)
        let context = try XCTUnwrap(contextRaw)
        XCTAssertEqual(exporter.writes, ["b"])
        XCTAssertEqual(context.assetIDs, ["a", "b", "c"])
        XCTAssertEqual(context.sourceDateHints.count, 3)
        XCTAssertTrue(exists(dir.appendingPathComponent("a.jpg").path))

        // A recorded path outside the staging directory is never trusted.
        let stagingB = makeTempParent()
        let outsideDir = makeTempParent()
        try FileManager.default.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        let outside = outsideDir.appendingPathComponent("a.jpg")
        try Data("bytes-a".utf8).write(to: outside)
        let escaped = try seedCheckpoint(
            parent: stagingB, name: "escaped", state: .stopped, assetIDs: ["a"],
            planAssetIDs: ["a", "b"], updatedAt: fixedDate(60), recordedPathOverride: ["a": outside.path]
        )
        let traversal = try seedCheckpoint(
            parent: stagingB, name: "traversal", state: .stopped, assetIDs: ["a"],
            planAssetIDs: ["a", "b"], updatedAt: fixedDate(70),
            recordedPathOverride: ["a": stagingB.appendingPathComponent("traversal/../escaped/a.jpg").path]
        )
        let storeB = makeStore(ids: ["a", "b"], exporter: ScriptedExporter(), staging: stagingB)
        storeB.refreshResumableImport(destination: destinationA)

        XCTAssertNil(storeB.resumable)
        XCTAssertTrue(exists(outside.path), "Only the import's own directory is ever removed")
        XCTAssertFalse(exists(escaped.path))
        XCTAssertFalse(exists(traversal.path))
    }

}

private final class LockedValues: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [Int: Bool] = [:]
    func append(_ key: Int, _ value: Bool) { lock.withLock { values[key] = value } }
    func value(for key: Int) -> Bool? { lock.withLock { values[key] } }
}
