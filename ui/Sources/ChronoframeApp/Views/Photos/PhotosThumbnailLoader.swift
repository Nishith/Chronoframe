#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI
#if canImport(Photos)
import Photos
#endif

/// Thumbnail cache for the Photos import grid, keyed by asset local
/// identifier and backed by `NSCache` (auto-eviction under memory pressure +
/// a steady-state `countLimit`).
///
/// The PhotoKit renderer returns image *data* (a `Sendable` type) across the
/// async boundary; the `NSImage` is built on the main actor from that data, so
/// no non-`Sendable` AppKit image ever crosses an async hop (the Swift 6 /
/// CodeQL sendability hazard this repo has hit before).
@MainActor
final class PhotosThumbnailLoader: ObservableObject {
    typealias Renderer = @Sendable (String, CGSize) async -> Data?

    private let cache: NSCache<NSString, NSImage>
    private let renderer: Renderer

    init(countLimit: Int = 256, renderer: Renderer? = nil) {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = countLimit
        self.cache = cache
        self.renderer = renderer ?? PhotosThumbnailLoader.defaultRenderer
    }

    func cachedImage(for id: String) -> NSImage? {
        cache.object(forKey: id as NSString)
    }

    func image(for id: String, size: CGSize) async -> NSImage? {
        if let cached = cache.object(forKey: id as NSString) { return cached }
        guard let data = await renderer(id, size), !Task.isCancelled, let image = NSImage(data: data) else {
            return nil
        }
        cache.setObject(image, forKey: id as NSString)
        return image
    }

    /// Drop every cached thumbnail. Intended for memory-pressure recovery and
    /// tests; not part of the normal flow.
    func purgeCache() {
        cache.removeAllObjects()
    }

    #if canImport(Photos)
    static let defaultRenderer: Renderer = { id, size in
        await fetchThumbnailData(id: id, targetSize: size)
    }

    /// Reads a thumbnail as TIFF data on a background queue and hands only the
    /// `Data` back across the continuation. `.highQualityFormat` delivers the
    /// result handler exactly once, so the continuation resumes once.
    /// `isNetworkAccessAllowed` is false: browsing never pulls originals from
    /// iCloud — an iCloud-only asset simply shows a placeholder.
    private static func fetchThumbnailData(id: String, targetSize: CGSize) async -> Data? {
        guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject else {
            return nil
        }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        return await withCheckedContinuation { (continuation: CheckedContinuation<Data?, Never>) in
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFill,
                options: options
            ) { image, _ in
                continuation.resume(returning: image?.tiffRepresentation)
            }
        }
    }
    #else
    static let defaultRenderer: Renderer = { _, _ in nil }
    #endif
}

/// One asset cell in the Photos import grid: a thumbnail with a selection ring
/// and a media badge. Loads asynchronously through `PhotosThumbnailLoader`.
struct PhotosAssetCell: View {
    let asset: PhotosAssetSummary
    let isSelected: Bool
    let size: CGSize
    @ObservedObject var loader: PhotosThumbnailLoader
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.ColorSystem.imageStage)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size.width, height: size.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            } else {
                Image(systemName: asset.mediaKind == .video ? "video" : "photo")
                    .font(.system(size: min(size.width, size.height) * 0.26, weight: .regular))
                    .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
            }

            if asset.mediaKind == .video {
                badge(systemImage: "video.fill", alignment: .bottomLeading)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DesignTokens.ColorSystem.accentAction, lineWidth: 3)
                badge(systemImage: "checkmark.circle.fill", alignment: .topTrailing)
            }
        }
        .frame(width: size.width, height: size.height)
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(DesignTokens.ColorSystem.imageStageHairline, lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .task(id: asset.id) {
            if let cached = loader.cachedImage(for: asset.id) {
                image = cached
            } else {
                image = await loader.image(for: asset.id, size: size)
            }
        }
    }

    private func badge(systemImage: String, alignment: Alignment) -> some View {
        Image(systemName: systemImage)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            .padding(5)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
            .accessibilityHidden(true)
    }
}
