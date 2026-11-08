#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI

/// Renders and caches the one preview a group can show (D-NAS-50).
///
/// Nothing here runs on its own: `render(digest:url:)` is called only after the user
/// presses a group's Load Preview button. Selecting a group, scrolling, relaunching and
/// the workspace appearing never reach the renderer. Previews are cached in memory by
/// digest and are never written to disk.
@MainActor
final class NASPreviewLoader: ObservableObject {
    typealias Renderer = @Sendable (URL, CGSize, CGFloat) async -> CGImage?
    typealias ScaleProvider = @Sendable () -> CGFloat

    static let defaultCountLimit = 128
    static let previewSize = CGSize(width: 320, height: 240)

    /// Digests with an image in the cache at some point. Changes drive the view to refresh.
    @Published private(set) var loadedDigests: Set<String> = []
    @Published private(set) var loadingDigests: Set<String> = []
    @Published private(set) var failedDigests: Set<String> = []

    private let cache = NSCache<NSString, NSImage>()
    private let renderer: Renderer
    private let scaleProvider: ScaleProvider

    init(
        countLimit: Int = NASPreviewLoader.defaultCountLimit,
        renderer: @escaping Renderer = { url, size, scale in
            await ThumbnailRenderer.cgImage(for: url, size: size, scale: scale)
        },
        scaleProvider: @escaping ScaleProvider = {
            NSScreen.main?.backingScaleFactor ?? 2.0
        }
    ) {
        cache.countLimit = countLimit
        self.renderer = renderer
        self.scaleProvider = scaleProvider
    }

    /// The cached preview, if one was loaded. Never renders.
    func cachedImage(forDigest digest: String) -> NSImage? {
        cache.object(forKey: digest as NSString)
    }

    /// Renders `url` for `digest` unless a preview is already cached or being rendered.
    @discardableResult
    func render(digest: String, url: URL) async -> NSImage? {
        if let cached = cachedImage(forDigest: digest) { return cached }
        guard !loadingDigests.contains(digest) else { return nil }

        loadingDigests.insert(digest)
        failedDigests.remove(digest)
        let cgImage = await renderer(url, Self.previewSize, scaleProvider())
        loadingDigests.remove(digest)

        guard let cgImage else {
            failedDigests.insert(digest)
            return nil
        }
        let image = NSImage(cgImage: cgImage, size: CGSize(width: cgImage.width, height: cgImage.height))
        cache.setObject(image, forKey: digest as NSString)
        loadedDigests.insert(digest)
        return image
    }
}
