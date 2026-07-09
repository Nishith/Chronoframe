import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

private enum StoreTestError: Error { case boom }

private final class StubAccess: PhotosLibraryAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var _current: PhotosAuthorizationStatus
    private let promptResult: PhotosAuthorizationStatus

    init(current: PhotosAuthorizationStatus, promptResult: PhotosAuthorizationStatus) {
        self._current = current
        self.promptResult = promptResult
    }

    func currentAuthorization() -> PhotosAuthorizationStatus {
        lock.lock(); defer { lock.unlock() }
        return _current
    }

    func requestReadAccess() async -> PhotosAuthorizationStatus {
        lock.lock(); _current = promptResult; lock.unlock()
        return promptResult
    }
}

private final class StubExporter: PhotosResourceExporting, @unchecked Sendable {
    var listFailure = false

    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        if listFailure { throw StoreTestError.boom }
        return [PhotosExportableResource(assetID: id, resourceIndex: 0, fileExtension: "jpg", originalFilename: "\(id).jpg")]
    }

    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        try Data("bytes".utf8).write(to: destinationURL)
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
        XCTAssertEqual(staged.count, 2)
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
}
