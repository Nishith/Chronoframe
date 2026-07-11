import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class PhotosCatalogModelTests: XCTestCase {
    func testMediaKindImportability() {
        XCTAssertTrue(PhotosAssetSummary.MediaKind.photo.isImportable)
        XCTAssertTrue(PhotosAssetSummary.MediaKind.video.isImportable)
        XCTAssertFalse(PhotosAssetSummary.MediaKind.unsupported.isImportable)
    }

    func testMediaKindAllCasesCovered() {
        XCTAssertEqual(Set(PhotosAssetSummary.MediaKind.allCases), [.photo, .video, .unsupported])
    }

    func testAlbumKindAllCasesCovered() {
        XCTAssertEqual(Set(PhotosAlbumSummary.Kind.allCases), [.allPhotos, .userAlbum, .smartAlbum])
    }

    func testAssetSummaryPreservesFields() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let asset = PhotosAssetSummary(
            id: "asset-1",
            mediaKind: .photo,
            creationDate: date,
            pixelWidth: 4032,
            pixelHeight: 3024,
            originalFilename: "IMG_0001.HEIC",
            isFavorite: true,
            isCloudStoredOnly: true
        )
        XCTAssertEqual(asset.id, "asset-1")
        XCTAssertEqual(asset.mediaKind, .photo)
        XCTAssertEqual(asset.creationDate, date)
        XCTAssertEqual(asset.pixelWidth, 4032)
        XCTAssertEqual(asset.pixelHeight, 3024)
        XCTAssertEqual(asset.originalFilename, "IMG_0001.HEIC")
        XCTAssertTrue(asset.isFavorite)
        XCTAssertTrue(asset.isCloudStoredOnly)
    }

    func testAlbumSummaryPreservesFields() {
        let album = PhotosAlbumSummary(id: "alb-1", title: "Trip", kind: .userAlbum, approximateCount: 42)
        XCTAssertEqual(album.id, "alb-1")
        XCTAssertEqual(album.title, "Trip")
        XCTAssertEqual(album.kind, .userAlbum)
        XCTAssertEqual(album.approximateCount, 42)
    }

    func testCatalogPageHasMoreAtBoundaries() {
        // 25 total, 10 per page → pages 0,1 have more; page 2 (last) does not.
        XCTAssertTrue(page(index: 0, size: 10, total: 25).hasMore)
        XCTAssertTrue(page(index: 1, size: 10, total: 25).hasMore)
        XCTAssertFalse(page(index: 2, size: 10, total: 25).hasMore)
    }

    func testCatalogPageHasMoreExactMultiple() {
        // 20 total, 10 per page → page 1 is the last full page, no more.
        XCTAssertTrue(page(index: 0, size: 10, total: 20).hasMore)
        XCTAssertFalse(page(index: 1, size: 10, total: 20).hasMore)
    }

    func testEmptyPageIsTerminal() {
        let empty = PhotosCatalogPage.empty(pageIndex: 3, pageSize: 10, totalCount: 5)
        XCTAssertTrue(empty.assets.isEmpty)
        XCTAssertFalse(empty.hasMore)
        XCTAssertEqual(empty.pageIndex, 3)
        XCTAssertEqual(empty.totalCount, 5)
    }

    private func page(index: Int, size: Int, total: Int) -> PhotosCatalogPage {
        PhotosCatalogPage(assets: [], pageIndex: index, pageSize: size, totalCount: total)
    }
}

/// Test double proving the `PhotosCatalogReading` seam is injectable without
/// PhotoKit, and that a consumer can page a fixture library end to end.
final class FakePhotosCatalog: PhotosCatalogReading, @unchecked Sendable {
    private let albumList: [PhotosAlbumSummary]
    private let assetsByAlbum: [String: [PhotosAssetSummary]]

    init(albums: [PhotosAlbumSummary], assetsByAlbum: [String: [PhotosAssetSummary]]) {
        self.albumList = albums
        self.assetsByAlbum = assetsByAlbum
    }

    func albums() -> [PhotosAlbumSummary] { albumList }

    func assetPage(in album: PhotosAlbumSummary, pageIndex: Int, pageSize: Int) -> PhotosCatalogPage {
        let all = assetsByAlbum[album.id] ?? []
        let size = max(1, pageSize)
        let start = max(0, pageIndex) * size
        guard start < all.count else {
            return .empty(pageIndex: pageIndex, pageSize: size, totalCount: all.count)
        }
        let end = min(start + size, all.count)
        return PhotosCatalogPage(
            assets: Array(all[start..<end]),
            pageIndex: pageIndex,
            pageSize: size,
            totalCount: all.count
        )
    }
}

final class PhotosCatalogReadingSeamTests: XCTestCase {
    func testSeamPagesThroughFixtureAlbum() {
        let album = PhotosAlbumSummary(id: "alb", title: "All", kind: .allPhotos, approximateCount: 3)
        let assets = (0..<3).map {
            PhotosAssetSummary(
                id: "a\($0)",
                mediaKind: .photo,
                creationDate: nil,
                pixelWidth: 100,
                pixelHeight: 100,
                originalFilename: "a\($0).jpg",
                isFavorite: false,
                isCloudStoredOnly: false
            )
        }
        let catalog: any PhotosCatalogReading = FakePhotosCatalog(
            albums: [album],
            assetsByAlbum: [album.id: assets]
        )

        XCTAssertEqual(catalog.albums().map(\.id), ["alb"])

        let page0 = catalog.assetPage(in: album, pageIndex: 0, pageSize: 2)
        XCTAssertEqual(page0.assets.map(\.id), ["a0", "a1"])
        XCTAssertTrue(page0.hasMore)

        let page1 = catalog.assetPage(in: album, pageIndex: 1, pageSize: 2)
        XCTAssertEqual(page1.assets.map(\.id), ["a2"])
        XCTAssertFalse(page1.hasMore)

        let past = catalog.assetPage(in: album, pageIndex: 2, pageSize: 2)
        XCTAssertTrue(past.assets.isEmpty)
        XCTAssertFalse(past.hasMore)
    }
}
