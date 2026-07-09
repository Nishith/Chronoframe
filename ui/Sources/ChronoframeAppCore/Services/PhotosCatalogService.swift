#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
#if canImport(Photos)
import Photos
#endif

/// Read-only enumeration of the Apple Photos library's albums and assets.
///
/// A protocol seam so the browser store and tests never touch `PHFetchResult`
/// directly (there is no real library in CI). Like `PhotosLibraryAccessing`,
/// every method is strictly read-only: the concrete implementation only ever
/// issues `PHAsset`/`PHAssetCollection` **fetches** and never mutates the
/// library. See the Apple Photos read-only safety invariant.
public protocol PhotosCatalogReading: Sendable {
    /// The browsable albums, "All Photos" first, then user albums, then
    /// system smart albums. Empty when access has not been granted.
    func albums() -> [PhotosAlbumSummary]
    /// One page of assets from an album, newest first. A page index past the
    /// end returns an empty terminal page rather than failing.
    func assetPage(in album: PhotosAlbumSummary, pageIndex: Int, pageSize: Int) -> PhotosCatalogPage
}

/// Sentinel identifier for the system-wide "All Photos" pseudo-album, which
/// has no `PHAssetCollection` of its own.
public enum PhotosCatalogWellKnown {
    public static let allPhotosAlbumID = "com.chronoframe.photos.allPhotos"
}

#if canImport(Photos)
/// PhotoKit-backed catalog reader. Holds no mutable state, so it is trivially
/// `Sendable`; every method resolves a fetch synchronously and maps each
/// `PHAsset` to a `Sendable` `PhotosAssetSummary` before returning, so no
/// non-`Sendable` PhotoKit type ever crosses an async boundary.
public final class PhotosCatalogService: PhotosCatalogReading {
    public init() {}

    public func albums() -> [PhotosAlbumSummary] {
        var result: [PhotosAlbumSummary] = []

        let allPhotosOptions = PHFetchOptions()
        allPhotosOptions.includeHiddenAssets = false
        let allPhotosCount = PHAsset.fetchAssets(with: allPhotosOptions).count
        result.append(
            PhotosAlbumSummary(
                id: PhotosCatalogWellKnown.allPhotosAlbumID,
                title: "All Photos",
                kind: .allPhotos,
                approximateCount: allPhotosCount
            )
        )

        result.append(contentsOf: collections(with: .album, kind: .userAlbum))
        result.append(contentsOf: collections(with: .smartAlbum, kind: .smartAlbum))
        return result
    }

    public func assetPage(in album: PhotosAlbumSummary, pageIndex: Int, pageSize: Int) -> PhotosCatalogPage {
        let clampedPageSize = max(1, pageSize)
        let clampedPageIndex = max(0, pageIndex)
        let fetchResult = assetsFetchResult(for: album)
        let totalCount = fetchResult.count

        let start = clampedPageIndex * clampedPageSize
        guard start < totalCount else {
            return .empty(pageIndex: clampedPageIndex, pageSize: clampedPageSize, totalCount: totalCount)
        }
        let end = min(start + clampedPageSize, totalCount)

        var summaries: [PhotosAssetSummary] = []
        summaries.reserveCapacity(end - start)
        fetchResult.enumerateObjects(at: IndexSet(integersIn: start..<end), options: []) { asset, _, _ in
            summaries.append(Self.summary(for: asset))
        }
        return PhotosCatalogPage(
            assets: summaries,
            pageIndex: clampedPageIndex,
            pageSize: clampedPageSize,
            totalCount: totalCount
        )
    }

    private func collections(
        with type: PHAssetCollectionType,
        kind: PhotosAlbumSummary.Kind
    ) -> [PhotosAlbumSummary] {
        var albums: [PhotosAlbumSummary] = []
        let collections = PHAssetCollection.fetchAssetCollections(with: type, subtype: .any, options: nil)
        collections.enumerateObjects { collection, _, _ in
            // Skip empty smart albums so the browser is not padded with
            // system albums the user has never populated.
            let assetCount = PHAsset.fetchAssets(in: collection, options: nil).count
            if kind == .smartAlbum && assetCount == 0 {
                return
            }
            albums.append(
                PhotosAlbumSummary(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Untitled",
                    kind: kind,
                    approximateCount: assetCount
                )
            )
        }
        return albums
    }

    private func assetsFetchResult(for album: PhotosAlbumSummary) -> PHFetchResult<PHAsset> {
        let options = PHFetchOptions()
        options.includeHiddenAssets = false
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        if album.kind == .allPhotos {
            return PHAsset.fetchAssets(with: options)
        }
        let collections = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [album.id],
            options: nil
        )
        guard let collection = collections.firstObject else {
            return PHAsset.fetchAssets(with: PHFetchOptions().withNoResults())
        }
        return PHAsset.fetchAssets(in: collection, options: options)
    }

    static func summary(for asset: PHAsset) -> PhotosAssetSummary {
        let resource = PHAssetResource.assetResources(for: asset).first
        return PhotosAssetSummary(
            id: asset.localIdentifier,
            mediaKind: PhotosAssetSummary.MediaKind(asset.mediaType),
            creationDate: asset.creationDate,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            originalFilename: resource?.originalFilename,
            isFavorite: asset.isFavorite,
            // Precise on-device residency is only knowable asynchronously
            // during export; browsing stays fast by assuming resident and
            // letting the executor allow network access unconditionally.
            isCloudStoredOnly: false
        )
    }
}

extension PhotosAssetSummary.MediaKind {
    /// Maps PhotoKit's media type onto the OS-independent kind. Audio and any
    /// future unknown case fail closed to `.unsupported` so a non-photo,
    /// non-video asset is never treated as importable.
    public init(_ mediaType: PHAssetMediaType) {
        switch mediaType {
        case .image: self = .photo
        case .video: self = .video
        case .audio, .unknown: self = .unsupported
        @unknown default: self = .unsupported
        }
    }
}

private extension PHFetchOptions {
    /// A fetch that resolves to zero objects — used as a safe fallback when a
    /// requested album no longer exists.
    func withNoResults() -> PHFetchOptions {
        predicate = NSPredicate(value: false)
        return self
    }
}
#else
/// Fallback for platforms without PhotoKit. Keeps `ChronoframeAppCore`
/// buildable elsewhere and reports an empty library.
public final class PhotosCatalogService: PhotosCatalogReading {
    public init() {}
    public func albums() -> [PhotosAlbumSummary] { [] }
    public func assetPage(in album: PhotosAlbumSummary, pageIndex: Int, pageSize: Int) -> PhotosCatalogPage {
        .empty(pageIndex: pageIndex, pageSize: pageSize, totalCount: 0)
    }
}
#endif
