#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Combine
import Foundation

/// View-model for the Photos import workspace: authorization state, album and
/// asset browsing, multi-selection, and the read-only export that populates a
/// staging directory before handing off to the verified-transfer pipeline.
///
/// The store never touches Setup or a profile. `prepareImport` captures the
/// destination that is active at click time (via the injected capture) and
/// returns a fully-pinned `PhotosImportContext`; the caller then drives the
/// normal preview → consent → transfer flow. The Photos library is only ever
/// read.
@MainActor
public final class PhotosImportStore: ObservableObject {
    /// The organize destination captured at import time.
    public struct DestinationCapture: Equatable, Sendable {
        public let path: String
        public let bookmarkKeys: [String]
        public init(path: String, bookmarkKeys: [String]) {
            self.path = path
            self.bookmarkKeys = bookmarkKeys
        }
    }

    @Published public private(set) var authorization: PhotosAuthorizationStatus
    @Published public private(set) var albums: [PhotosAlbumSummary] = []
    @Published public private(set) var selectedAlbumID: String?
    @Published public private(set) var assets: [PhotosAssetSummary] = []
    @Published public private(set) var totalAssetCount: Int = 0
    @Published public private(set) var hasMorePages: Bool = false
    @Published public private(set) var selectedAssetIDs: Set<String> = []
    @Published public private(set) var isLoadingAssets: Bool = false
    @Published public private(set) var isPreparingImport: Bool = false
    /// A plain, reassuring status/error line for the UI. Never raw error text.
    @Published public private(set) var statusMessage: String?

    private let access: any PhotosLibraryAccessing
    private let catalog: any PhotosCatalogReading
    private let exporter: any PhotosResourceExporting
    private let stagingParentURL: URL
    private let pageSize: Int
    private var loadedPageCount = 0
    /// Each selected asset's summary, captured when it was selected, in
    /// selection order. Selections persist across albums and pages, so the
    /// export resolves from here rather than from the currently loaded
    /// `assets`, keeping the exported set equal to `selectedCount`.
    private var selectedSummaries: [PhotosAssetSummary] = []

    public init(
        access: any PhotosLibraryAccessing,
        catalog: any PhotosCatalogReading,
        exporter: any PhotosResourceExporting,
        stagingParentURL: URL,
        pageSize: Int = 120
    ) {
        self.access = access
        self.catalog = catalog
        self.exporter = exporter
        self.stagingParentURL = stagingParentURL
        self.pageSize = max(1, pageSize)
        self.authorization = access.currentAuthorization()
    }

    public var selectedCount: Int { selectedAssetIDs.count }

    /// True when there is at least one selection, access is granted, and no
    /// export is already running.
    public var canImport: Bool {
        !selectedAssetIDs.isEmpty && !isPreparingImport && authorization.allowsReading
    }

    // MARK: - Authorization

    public func refreshAuthorization() {
        authorization = access.currentAuthorization()
        loadAlbumsIfAuthorized()
    }

    public func requestAccess() async {
        authorization = await access.requestReadAccess()
        loadAlbumsIfAuthorized()
    }

    /// Loads albums when access is granted and they have not been loaded yet.
    public func loadAlbumsIfAuthorized() {
        guard authorization.allowsReading, albums.isEmpty else { return }
        loadAlbums()
    }

    private func loadAlbums() {
        let list = catalog.albums()
        albums = list
        if selectedAlbumID == nil, let first = list.first {
            selectAlbum(id: first.id)
        }
    }

    // MARK: - Browsing

    public func selectAlbum(id: String) {
        guard let album = albums.first(where: { $0.id == id }) else { return }
        selectedAlbumID = id
        assets = []
        loadedPageCount = 0
        totalAssetCount = 0
        hasMorePages = false
        loadNextPage(for: album)
    }

    public func loadMoreAssets() {
        guard hasMorePages, !isLoadingAssets else { return }
        guard let id = selectedAlbumID, let album = albums.first(where: { $0.id == id }) else { return }
        loadNextPage(for: album)
    }

    private func loadNextPage(for album: PhotosAlbumSummary) {
        isLoadingAssets = true
        defer { isLoadingAssets = false }
        let page = catalog.assetPage(in: album, pageIndex: loadedPageCount, pageSize: pageSize)
        assets.append(contentsOf: page.assets)
        totalAssetCount = page.totalCount
        hasMorePages = page.hasMore
        loadedPageCount += 1
    }

    // MARK: - Selection

    public func toggleSelection(_ assetID: String) {
        if selectedAssetIDs.contains(assetID) {
            deselect(assetID)
            return
        }
        // Only importable media (photo/video) can be selected.
        guard let summary = assets.first(where: { $0.id == assetID }),
              summary.mediaKind.isImportable
        else { return }
        select(summary)
    }

    public func isSelected(_ assetID: String) -> Bool {
        selectedAssetIDs.contains(assetID)
    }

    public func clearSelection() {
        selectedAssetIDs.removeAll()
        selectedSummaries.removeAll()
    }

    /// Adds one asset to the selection, keeping `selectedAssetIDs` and
    /// `selectedSummaries` in sync. Every path that grows the selection goes
    /// through this single helper so the two collections can't drift apart
    /// the way they did before the BASH-02 fix.
    private func select(_ summary: PhotosAssetSummary) {
        selectedAssetIDs.insert(summary.id)
        selectedSummaries.append(summary)
    }

    /// Removes one asset from the selection, keeping both collections in sync.
    private func deselect(_ assetID: String) {
        selectedAssetIDs.remove(assetID)
        selectedSummaries.removeAll { $0.id == assetID }
    }

    // MARK: - Import preparation (read-only export into staging)

    /// Exports the current selection's originals into a fresh staging
    /// directory and returns a pinned import context, or nil (with a
    /// `statusMessage`) if there is nothing to import or the export failed.
    /// The Photos library is never modified.
    public func prepareImport(destination: DestinationCapture?) async -> PhotosImportContext? {
        guard !isPreparingImport else { return nil }
        guard let destination, !destination.path.isEmpty else {
            statusMessage = "Choose an organize destination before importing from Photos."
            return nil
        }

        let plan = PhotosExportPlanner.plan(for: selectedSummaries)
        guard !plan.isEmpty else {
            statusMessage = "Select at least one photo or video to import."
            return nil
        }

        isPreparingImport = true
        statusMessage = nil
        defer { isPreparingImport = false }

        // Purge any staging left behind by an abandoned import, then export
        // into a fresh per-import subdirectory.
        purgeStagingParent()
        let importID = UUID()
        let stagingDirectory = stagingParentURL.appendingPathComponent(importID.uuidString, isDirectory: true)

        do {
            let receipt = try await PhotosExportExecutor(exporter: exporter)
                .export(plan: plan, to: stagingDirectory)
            guard !receipt.isEmpty else {
                purgeStagingParent()
                statusMessage = "Chronoframe couldn't read the selected items from Photos, so there is nothing to import. Your Photos library was not changed."
                return nil
            }
            if !receipt.failures.isEmpty {
                statusMessage = "\(receipt.failures.count) item(s) couldn't be read and were skipped. Your Photos library was not changed."
            }
            return PhotosImportContext(
                importID: importID,
                stagingDirectoryURL: stagingDirectory,
                destinationPath: destination.path,
                destinationBookmarkKeys: destination.bookmarkKeys,
                assetIDs: receipt.exportedAssetIDs,
                sourceDateHints: receipt.sourceDateHints
            )
        } catch {
            purgeStagingParent()
            statusMessage = "Chronoframe couldn't prepare the Photos import. Your Photos library was not changed."
            return nil
        }
    }

    /// Deletes a finished import's staging directory. Safe to call more than
    /// once; a missing directory is not an error.
    public func cleanupStaging(for context: PhotosImportContext) {
        try? FileManager.default.removeItem(at: context.stagingDirectoryURL)
    }

    private func purgeStagingParent() {
        try? FileManager.default.removeItem(at: stagingParentURL)
    }
}
