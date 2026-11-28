import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

private enum StoreTestError: Error { case boom }

private final class StubAccess: PhotosLibraryAccessing, @unchecked Sendable {
    // Tests drive this serially on the main actor, so no lock is needed (an
    // async context can't use NSLock in Swift 6 anyway).
    private var current: PhotosAuthorizationStatus
    private let promptResult: PhotosAuthorizationStatus

    init(current: PhotosAuthorizationStatus, promptResult: PhotosAuthorizationStatus) {
        self.current = current
        self.promptResult = promptResult
    }

    func currentAuthorization() -> PhotosAuthorizationStatus {
        current
    }

    func requestReadAccess() async -> PhotosAuthorizationStatus {
        current = promptResult
        return promptResult
    }
}

private final class StubExporter: PhotosResourceExporting, @unchecked Sendable {
    var listFailure = false
    private let lock = NSLock()
    private var _editedAssets: Set<String> = []
    private var _unsupportedEditedAssets: Set<String> = []
    private var _editedLookups: [String] = []
    private var _beforeWrite: (@Sendable (String) async -> Void)?

    /// Assets that have an edited still render.
    var editedAssets: Set<String> {
        get { lock.withLock { _editedAssets } }
        set { lock.withLock { _editedAssets = newValue } }
    }
    /// Assets whose edit (video or Live Photo) is not exported.
    var unsupportedEditedAssets: Set<String> {
        get { lock.withLock { _unsupportedEditedAssets } }
        set { lock.withLock { _unsupportedEditedAssets = newValue } }
    }
    var editedLookups: [String] { lock.withLock { _editedLookups } }
    var beforeWrite: (@Sendable (String) async -> Void)? {
        get { lock.withLock { _beforeWrite } }
        set { lock.withLock { _beforeWrite = newValue } }
    }

    func editedStillResource(forAssetID id: String) async throws -> PhotosExportableResource? {
        lock.withLock { _editedLookups.append(id) }
        guard editedAssets.contains(id) else { return nil }
        return PhotosExportableResource(
            assetID: id, resourceIndex: 1, fileExtension: "jpg", originalFilename: "FullSizeRender.jpg", role: .editedRender
        )
    }

    func hasUnsupportedEditedRender(forAssetID id: String) async throws -> Bool {
        unsupportedEditedAssets.contains(id)
    }

    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        if listFailure { throw StoreTestError.boom }
        return [PhotosExportableResource(assetID: id, resourceIndex: 0, fileExtension: "jpg", originalFilename: "\(id).jpg")]
    }

    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        if let hook = beforeWrite { await hook(resource.assetID) }
        try Data("bytes-\(resource.role == .editedRender ? "edited-" : "")\(resource.assetID)".utf8).write(to: destinationURL)
    }
}

final class PhotosImportStoreTests: XCTestCase {
    private func stagingParent() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-store-\(UUID().uuidString)", isDirectory: true)
    }

    private func asset(_ id: String, kind: PhotosAssetSummary.MediaKind = .photo) -> PhotosAssetSummary {
        PhotosAssetSummary(
            id: id,
            mediaKind: kind,
            creationDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            originalFilename: "\(id).jpg",
            isFavorite: false,
            isCloudStoredOnly: false
        )
    }

    private func album(_ id: String, count: Int) -> PhotosAlbumSummary {
        PhotosAlbumSummary(id: id, title: id, kind: .allPhotos, approximateCount: count)
    }

    @MainActor
    private func makeStore(
        current: PhotosAuthorizationStatus = .authorized,
        promptResult: PhotosAuthorizationStatus = .authorized,
        albums: [PhotosAlbumSummary],
        assetsByAlbum: [String: [PhotosAssetSummary]],
        exporter: StubExporter = StubExporter(),
        staging: URL,
        pageSize: Int = 2
    ) -> PhotosImportStore {
        PhotosImportStore(
            access: StubAccess(current: current, promptResult: promptResult),
            catalog: FakePhotosCatalog(albums: albums, assetsByAlbum: assetsByAlbum),
            exporter: exporter,
            stagingParentURL: staging,
            pageSize: pageSize
        )
    }

    @MainActor
    func testRequestAccessLoadsAlbumsWhenGranted() async {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let alb = album("all", count: 1)
        let store = makeStore(
            current: .notDetermined,
            promptResult: .authorized,
            albums: [alb],
            assetsByAlbum: ["all": [asset("a")]],
            staging: staging
        )
        XCTAssertEqual(store.authorization, .notDetermined)
        XCTAssertTrue(store.albums.isEmpty)

        await store.requestAccess()

        XCTAssertEqual(store.authorization, .authorized)
        XCTAssertEqual(store.albums.map(\.id), ["all"])
        XCTAssertEqual(store.selectedAlbumID, "all")
        XCTAssertEqual(store.assets.map(\.id), ["a"])
    }

    @MainActor
    func testBrowsingPagesThroughAssets() {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let alb = album("all", count: 3)
        let store = makeStore(
            albums: [alb],
            assetsByAlbum: ["all": [asset("a"), asset("b"), asset("c")]],
            staging: staging,
            pageSize: 2
        )
        store.loadAlbumsIfAuthorized()

        XCTAssertEqual(store.assets.map(\.id), ["a", "b"])
        XCTAssertTrue(store.hasMorePages)
        XCTAssertEqual(store.totalAssetCount, 3)

        store.loadMoreAssets()
        XCTAssertEqual(store.assets.map(\.id), ["a", "b", "c"])
        XCTAssertFalse(store.hasMorePages)
    }

    @MainActor
    func testOnlyImportableAssetsAreSelectable() {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("all", count: 2)],
            assetsByAlbum: ["all": [asset("photo", kind: .photo), asset("audio", kind: .unsupported)]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()

        store.toggleSelection("audio")
        XCTAssertFalse(store.isSelected("audio"), "Unsupported media cannot be selected")

        store.toggleSelection("photo")
        XCTAssertTrue(store.isSelected("photo"))
        XCTAssertEqual(store.selectedCount, 1)
        XCTAssertTrue(store.canImport)

        store.toggleSelection("photo")
        XCTAssertFalse(store.isSelected("photo"))
        store.clearSelection()
        XCTAssertEqual(store.selectedCount, 0)
    }

    @MainActor
    func testPrepareImportExportsSelectionIntoStaging() async {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("all", count: 2)],
            assetsByAlbum: ["all": [asset("a"), asset("b")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a")
        store.toggleSelection("b")

        let capture = PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: ["k"])
        let context = await store.prepareImport(destination: capture)

        let unwrapped = try! XCTUnwrap(context)
        XCTAssertEqual(unwrapped.destinationPath, "/tmp/dest")
        XCTAssertEqual(unwrapped.destinationBookmarkKeys, ["k"])
        XCTAssertEqual(Set(unwrapped.assetIDs), ["a", "b"])
        let staged = try! FileManager.default.contentsOfDirectory(atPath: unwrapped.stagingDirectoryURL.path)
            .filter { $0 != PhotosImportCheckpoint.filename }
        XCTAssertEqual(staged.count, 2)
        XCTAssertEqual(unwrapped.sourceDateHints.count, 2)
        for (path, hint) in unwrapped.sourceDateHints {
            XCTAssertEqual(try! FileIdentityHasher().hashIdentity(at: URL(fileURLWithPath: path)), hint.identity)
            XCTAssertEqual(hint.resolvedDate, .unknown, "Synthetic staging creation dates cannot become capture dates")
        }
    }

    /// BASH-02: selecting in album A, switching to album B and selecting there
    /// must export both. Before the fix only B's asset was exported while the
    /// UI still showed two selected.
    @MainActor
    func testSelectionsFromDifferentAlbumsAreAllExported() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("A", count: 1), album("B", count: 1)],
            assetsByAlbum: ["A": [asset("a")], "B": [asset("b")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a")
        store.selectAlbum(id: "B")
        store.toggleSelection("b")
        XCTAssertEqual(store.selectedCount, 2)

        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )

        let unwrapped = try XCTUnwrap(context)
        XCTAssertEqual(Set(unwrapped.assetIDs), ["a", "b"])
        XCTAssertEqual(unwrapped.assetIDs.count, store.selectedCount, "Exported set matches the displayed count")
        let staged = try FileManager.default.contentsOfDirectory(atPath: unwrapped.stagingDirectoryURL.path)
            .filter { $0 != PhotosImportCheckpoint.filename }
        XCTAssertEqual(staged.count, 2)
    }

    @MainActor
    func testSelectionSurvivesReturningToAnAlbumAndCanBeDeselectedThere() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("A", count: 1), album("B", count: 1)],
            assetsByAlbum: ["A": [asset("a")], "B": [asset("b")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a")
        store.selectAlbum(id: "B")
        store.toggleSelection("b")
        store.selectAlbum(id: "A")
        XCTAssertTrue(store.isSelected("a"))

        store.toggleSelection("a")

        XCTAssertEqual(store.selectedCount, 1)
        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )
        XCTAssertEqual(try XCTUnwrap(context).assetIDs, ["b"])
    }

    @MainActor
    func testAssetInTwoAlbumsIsOneSelection() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("All", count: 1), album("Favorites", count: 1)],
            assetsByAlbum: ["All": [asset("x")], "Favorites": [asset("x")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("x")
        store.selectAlbum(id: "Favorites")
        XCTAssertTrue(store.isSelected("x"))
        XCTAssertEqual(store.selectedCount, 1)

        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )
        XCTAssertEqual(try XCTUnwrap(context).assetIDs, ["x"])

        store.toggleSelection("x")
        XCTAssertEqual(store.selectedCount, 0)
    }

    @MainActor
    func testSelectionFromALaterPageIsExportedAfterSwitchingAlbums() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("A", count: 3), album("B", count: 1)],
            assetsByAlbum: ["A": [asset("a1"), asset("a2"), asset("a3")], "B": [asset("b")]],
            staging: staging,
            pageSize: 2
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a1")
        store.loadMoreAssets()
        store.toggleSelection("a3")
        store.selectAlbum(id: "B")

        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )
        XCTAssertEqual(Set(try XCTUnwrap(context).assetIDs), ["a1", "a3"])
    }

    @MainActor
    func testClearSelectionClearsEveryAlbum() async {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("A", count: 1), album("B", count: 1)],
            assetsByAlbum: ["A": [asset("a")], "B": [asset("b")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a")
        store.selectAlbum(id: "B")
        store.toggleSelection("b")

        store.clearSelection()

        XCTAssertEqual(store.selectedCount, 0)
        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )
        XCTAssertNil(context)
    }

    @MainActor
    func testPrepareImportWithoutDestinationFails() async {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("all", count: 1)],
            assetsByAlbum: ["all": [asset("a")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a")

        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "", bookmarkKeys: [])
        )
        XCTAssertNil(context)
        XCTAssertNotNil(store.statusMessage)
    }

    @MainActor
    func testPrepareImportWithoutSelectionFails() async {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("all", count: 1)],
            assetsByAlbum: ["all": [asset("a")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()

        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )
        XCTAssertNil(context)
        XCTAssertNotNil(store.statusMessage)
    }

    @MainActor
    func testPrepareImportWithUnreadableSelectionFails() async {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let exporter = StubExporter()
        exporter.listFailure = true
        let store = makeStore(
            albums: [album("all", count: 1)],
            assetsByAlbum: ["all": [asset("a")]],
            exporter: exporter,
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a")

        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )
        XCTAssertNil(context, "An export that reads nothing yields no import")
        XCTAssertNotNil(store.statusMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: staging.path),
                       "A failed export leaves no staging behind")
    }

    @MainActor
    func testCleanupStagingRemovesDirectory() async {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let store = makeStore(
            albums: [album("all", count: 1)],
            assetsByAlbum: ["all": [asset("a")]],
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        store.toggleSelection("a")
        let context = await store.prepareImport(
            destination: PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: [])
        )
        let unwrapped = try! XCTUnwrap(context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unwrapped.stagingDirectoryURL.path))

        store.cleanupStaging(for: unwrapped)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unwrapped.stagingDirectoryURL.path))
    }

    // MARK: - Include edited versions (WP-07)

    @MainActor
    private func selectedStore(
        ids: [String],
        exporter: StubExporter,
        staging: URL
    ) -> PhotosImportStore {
        let store = makeStore(
            albums: [album("all", count: ids.count)],
            assetsByAlbum: ["all": ids.map { asset($0) }],
            exporter: exporter,
            staging: staging,
            pageSize: 10
        )
        store.loadAlbumsIfAuthorized()
        for id in ids { store.toggleSelection(id) }
        return store
    }

    private let destination = PhotosImportStore.DestinationCapture(path: "/tmp/dest", bookmarkKeys: ["k"])

    @MainActor
    func testToggleDefaultsOffAndPersistsOnlyForCurrentImport() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let defaultsBefore = Set(UserDefaults.standard.dictionaryRepresentation().keys)
        let exporter = StubExporter()
        exporter.editedAssets = ["a"]
        let store = selectedStore(ids: ["a"], exporter: exporter, staging: staging)
        XCTAssertFalse(store.includeEditedVersions, "Off by default")

        store.includeEditedVersions = true
        let contextRaw = await store.prepareImport(destination: destination)
        let context = try XCTUnwrap(contextRaw)
        XCTAssertTrue(store.includeEditedVersions, "Held while the import is current")

        store.cleanupStaging(for: context)
        XCTAssertFalse(store.includeEditedVersions, "The choice ends with the import")

        let fresh = selectedStore(ids: ["a"], exporter: exporter, staging: staging)
        XCTAssertFalse(fresh.includeEditedVersions, "A new store never inherits the choice")
        XCTAssertEqual(Set(UserDefaults.standard.dictionaryRepresentation().keys), defaultsBefore,
                       "The choice is never written to UserDefaults")
    }

    @MainActor
    func testDiscardingTheInterruptedImportResetsTheToggle() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let exporter = StubExporter()
        let store = selectedStore(ids: ["a", "b"], exporter: exporter, staging: staging)
        exporter.beforeWrite = { id in
            if id == "b" { await MainActor.run { store.cancelPreparation() } }
        }
        store.includeEditedVersions = true
        _ = await store.prepareImport(destination: destination)
        XCTAssertNotNil(store.resumable)

        store.discardResumableImport()

        XCTAssertFalse(store.includeEditedVersions)
    }

    @MainActor
    func testStoreForwardsIncludeEditedVersionsToExecutor() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let exporter = StubExporter()
        exporter.editedAssets = ["a", "b"]
        let store = selectedStore(ids: ["a", "b"], exporter: exporter, staging: staging)

        store.includeEditedVersions = true
        let contextRaw = await store.prepareImport(destination: destination)
        let context = try XCTUnwrap(contextRaw)

        XCTAssertEqual(exporter.editedLookups, ["a", "b"], "The toggle reaches the executor")
        let checkpoint = try XCTUnwrap(PhotosImportFileCheckpointStore().load(in: context.stagingDirectoryURL))
        XCTAssertTrue(checkpoint.includeEditedVersions, "The choice is recorded for Resume")
        let counts = try XCTUnwrap(store.editedVersionCounts)
        XCTAssertEqual(counts, PhotosImportEditedVersionCounts(
            includedEditedVersions: true, originals: 2, editedVersions: 2, couldNotSave: 0, notIncluded: 0
        ))

        // Off stays off: the executor is never asked about edits.
        exporter.editedAssets = []
        let offStore = selectedStore(ids: ["a"], exporter: exporter, staging: staging)
        let before = exporter.editedLookups.count
        let offContextRaw = await offStore.prepareImport(destination: destination)
        let offContext = try XCTUnwrap(offContextRaw)
        XCTAssertEqual(exporter.editedLookups.count, before)
        XCTAssertFalse(try XCTUnwrap(PhotosImportFileCheckpointStore().load(in: offContext.stagingDirectoryURL)).includeEditedVersions)
        XCTAssertEqual(offStore.editedVersionCounts?.includedEditedVersions, false)
    }

    /// D-EPR-119: not-included edits are recorded in the checkpoint, so the
    /// count a Resume reports covers the assets prepared before the stop.
    @MainActor
    func testNotIncludedCountSurvivesResume() async throws {
        let staging = stagingParent()
        defer { try? FileManager.default.removeItem(at: staging) }
        let exporter = StubExporter()
        exporter.unsupportedEditedAssets = ["a"]
        exporter.editedAssets = ["b", "c"]
        let store = selectedStore(ids: ["a", "b", "c"], exporter: exporter, staging: staging)
        exporter.beforeWrite = { id in
            if id == "c" { await MainActor.run { store.cancelPreparation() } }
        }
        store.includeEditedVersions = true

        _ = await store.prepareImport(destination: destination)

        let dir = try XCTUnwrap(store.resumable?.stagingDirectoryURL)
        let stopped = try XCTUnwrap(PhotosImportFileCheckpointStore().load(in: dir))
        XCTAssertEqual(stopped.completed.map(\.assetID), ["a", "b"])
        XCTAssertEqual(stopped.editedNotIncludedAssetIDs, ["a"])
        exporter.beforeWrite = nil

        let resumed = await store.resumeImport(destination: destination)

        XCTAssertNotNil(resumed)
        XCTAssertEqual(try XCTUnwrap(PhotosImportFileCheckpointStore().load(in: dir)).editedNotIncludedAssetIDs, ["a"])
        XCTAssertEqual(store.editedVersionCounts, PhotosImportEditedVersionCounts(
            includedEditedVersions: true, originals: 3, editedVersions: 2, couldNotSave: 0, notIncluded: 1
        ), "Resume ignores the toggle and counts the earlier assets too")
    }
}
