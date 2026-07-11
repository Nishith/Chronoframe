import Foundation

/// OS-independent description of a single Apple Photos asset, decoupled
/// from PhotoKit so catalog browsing, selection, and export planning can be
/// modeled and unit-tested without a real `PHAsset`. `PhotosCatalogService`
/// maps `PHAsset` onto this at the OS boundary (see the `Photos` bridge in
/// `ChronoframeAppCore`).
///
/// Chronoframe only ever reads the Photos library. A summary never carries
/// bytes; it carries just enough identity and metadata to browse, select,
/// and later re-fetch the live asset for a read-only export.
public struct PhotosAssetSummary: Equatable, Sendable, Identifiable {
    public enum MediaKind: String, Equatable, Sendable, CaseIterable {
        case photo
        case video
        /// A media type Chronoframe does not import (audio, or a future
        /// PhotoKit case). Kept visible in the model so counts stay honest,
        /// but the export planner excludes it.
        case unsupported

        /// True when Chronoframe imports this kind. The export planner drops
        /// everything else so an unknown/audio asset can never be staged.
        public var isImportable: Bool {
            switch self {
            case .photo, .video:
                return true
            case .unsupported:
                return false
            }
        }
    }

    /// PhotoKit `localIdentifier`. Stable within a library; the export path
    /// re-fetches the live `PHAsset` from this immediately before reading,
    /// so a summary is only ever a browsing/selection token.
    public let id: String
    public let mediaKind: MediaKind
    public let creationDate: Date?
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Best-known original filename (e.g. `IMG_0001.HEIC`). Used as the
    /// basename hint for staging so Live Photo movie halves and metadata
    /// sidecars keep the photo's basename and pair downstream for free.
    public let originalFilename: String?
    public let isFavorite: Bool
    /// True when the asset's original bytes are not resident on this device
    /// and a network fetch is required to export it (iCloud-optimized
    /// storage). Surfaced so the UI can warn before a long download.
    public let isCloudStoredOnly: Bool

    public init(
        id: String,
        mediaKind: MediaKind,
        creationDate: Date?,
        pixelWidth: Int,
        pixelHeight: Int,
        originalFilename: String?,
        isFavorite: Bool,
        isCloudStoredOnly: Bool
    ) {
        self.id = id
        self.mediaKind = mediaKind
        self.creationDate = creationDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.originalFilename = originalFilename
        self.isFavorite = isFavorite
        self.isCloudStoredOnly = isCloudStoredOnly
    }
}

/// OS-independent description of an Apple Photos album or smart album.
public struct PhotosAlbumSummary: Equatable, Sendable, Identifiable {
    public enum Kind: String, Equatable, Sendable, CaseIterable {
        /// The system "All Photos" / library-wide pseudo-album. Always first.
        case allPhotos
        /// A user-created album.
        case userAlbum
        /// A system smart album (Favorites, Recents, Videos, …).
        case smartAlbum
    }

    public let id: String
    public let title: String
    public let kind: Kind
    /// Asset count reported by the fetch result. Conservative for browsing
    /// only — the export path always re-derives the exact selection.
    public let approximateCount: Int

    public init(id: String, title: String, kind: Kind, approximateCount: Int) {
        self.id = id
        self.title = title
        self.kind = kind
        self.approximateCount = approximateCount
    }
}

/// One page of assets from a catalog fetch. Paging keeps the browser
/// responsive on large libraries without materializing every `PHAsset`
/// summary up front.
public struct PhotosCatalogPage: Equatable, Sendable {
    public let assets: [PhotosAssetSummary]
    public let pageIndex: Int
    public let pageSize: Int
    /// Total assets in the album, so the UI can show "N of M" and decide
    /// whether to request the next page.
    public let totalCount: Int

    public init(assets: [PhotosAssetSummary], pageIndex: Int, pageSize: Int, totalCount: Int) {
        self.assets = assets
        self.pageIndex = pageIndex
        self.pageSize = pageSize
        self.totalCount = totalCount
    }

    /// True when at least one more page exists after this one.
    public var hasMore: Bool {
        (pageIndex + 1) * pageSize < totalCount
    }

    /// An empty terminal page, used when an album is empty or a page index
    /// runs past the end of the album.
    public static func empty(pageIndex: Int, pageSize: Int, totalCount: Int) -> PhotosCatalogPage {
        PhotosCatalogPage(assets: [], pageIndex: pageIndex, pageSize: pageSize, totalCount: totalCount)
    }
}
