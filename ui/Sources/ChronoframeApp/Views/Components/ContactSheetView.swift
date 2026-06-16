import AppKit
import ImageIO
import QuickLookThumbnailing
import SwiftUI
import UniformTypeIdentifiers

/// A "contact sheet" that shows the first N images/videos in a folder as
/// thumbnails. Purpose: make the Setup screen *visual*, not just textual —
/// the user sees what they're about to organize.
///
/// Design notes:
/// - Width-adaptive per the wide-layout doctrine: the tile grid is the media
///   surface that grows with its column, showing more frames as space allows
///   (`ContactSheetLayout`). The loader always fetches the maximum so window
///   resizes never re-enumerate the source.
/// - Uses `QLThumbnailGenerator` — works for all native media types.
/// - Cells fade in on appear with a 40ms stagger per Motion tokens.
/// - Empty state is a dimmed placeholder grid, not a blank rectangle.
/// - No filesystem work happens if ``sourcePath`` is empty.
struct ContactSheetView: View {
    let sourcePath: String
    let sourceURL: URL?
    var cellSize: CGFloat = 92

    @StateObject private var loader = ContactSheetLoader()
    @State private var columnWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if shouldCollapseToEmptyRow {
                // Never render a wall of empty tiles: when the scan finished
                // and produced nothing, say why in one compact row instead.
                emptyResultRow
            } else {
                if shouldShowHeroCell {
                    heroCell
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: cellSize, maximum: cellSize), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(gridRange, id: \.self) { index in
                        cell(at: index)
                    }
                }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear
                    .onAppear { columnWidth = geometry.size.width }
                    .onChange(of: geometry.size.width) { columnWidth = $0 }
            }
        }
        .padding(10)
        .background(DesignTokens.ColorSystem.imageStage, in: RoundedRectangle(cornerRadius: DesignTokens.Corner.card, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Corner.card, style: .continuous)
                .strokeBorder(DesignTokens.ColorSystem.hairline, lineWidth: 0.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: sourcePath) {
            await loader.load(
                sourcePath: sourcePath,
                sourceURL: sourceURL,
                count: ContactSheetLayout.maximumTiles,
                cellSize: cellSize
            )
        }
    }

    private var displayedTileCount: Int {
        ContactSheetLayout.tileCount(forColumnWidth: columnWidth, cellSize: cellSize)
    }

    private var shouldCollapseToEmptyRow: Bool {
        !sourcePath.isEmpty && loader.didFinishLoading && loader.loadedThumbnailCount == 0
    }

    private var emptyResultRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(.white.opacity(0.45))
            Text(ContactSheetLayout.emptyResultMessage(foundMediaCount: loader.foundMediaCount))
                .font(.caption.weight(.medium))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var gridRange: Range<Int> {
        let lowerBound = sourcePath.isEmpty ? 0 : min(1, displayedTileCount)
        return lowerBound..<displayedTileCount
    }

    @ViewBuilder
    private var heroCell: some View {
        let thumb = loader.thumbnails[safe: 0] ?? nil

        RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(Color.black.opacity(0.24))
            .overlay {
                if let thumb {
                    Image(nsImage: thumb)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 168)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .transition(.opacity)
                } else if loader.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    ContactSheetHeroPlaceholder()
                }
            }
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(DesignTokens.ColorSystem.accentWaypoint)
                        .frame(width: 6, height: 6)
                    Text(URL(fileURLWithPath: sourcePath).lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(.black.opacity(0.46), in: Capsule())
                .padding(10)
            }
            .frame(maxWidth: .infinity, minHeight: 168, maxHeight: 168)
            .clipped()
            .motion(Motion.reveal, value: thumb != nil)
    }

    @ViewBuilder
    private func cell(at index: Int) -> some View {
        let thumb = loader.thumbnails[safe: index] ?? nil

        ContactSheetThumbnailCell(thumbnail: thumb, cellSize: cellSize)
            .motion(.easeOut(duration: Motion.Duration.reveal).delay(0.04 * Double(index)), value: thumb != nil)
    }

    private var accessibilityLabelText: String {
        if sourcePath.isEmpty {
            return "Contact sheet preview — no source selected."
        }
        if loader.didFinishLoading && loader.loadedThumbnailCount == 0 {
            return "Contact sheet preview — \(ContactSheetLayout.emptyResultMessage(foundMediaCount: loader.foundMediaCount))"
        }
        let visible = min(loader.loadedThumbnailCount, displayedTileCount)
        return "Contact sheet showing \(visible) preview frames from the source."
    }

    private var shouldShowHeroCell: Bool {
        !sourcePath.isEmpty
    }
}

/// Pure layout policy for the contact sheet's width-adaptive tile grid.
/// Wide-layout doctrine: media surfaces grow with the window — the sheet shows
/// more frames as its column widens; forms never stretch to match.
enum ContactSheetLayout {
    /// Upper bound on loaded thumbnails. Bounds source enumeration and
    /// QuickLook work to a fixed cost regardless of window size, and lets the
    /// loader fetch once instead of reloading on every resize.
    static let maximumTiles = 32
    /// Lower bound so the sheet always reads as a grid, including before the
    /// first width measurement lands.
    static let minimumTiles = 10
    /// The grid aims for two rows of tiles below the hero frame.
    static let targetRows = 2

    static func columns(forColumnWidth width: CGFloat, cellSize: CGFloat, spacing: CGFloat = 8) -> Int {
        guard width > 0, cellSize > 0 else { return 0 }
        return max(1, Int((width + spacing) / (cellSize + spacing)))
    }

    static func tileCount(forColumnWidth width: CGFloat, cellSize: CGFloat, spacing: CGFloat = 8) -> Int {
        let columns = columns(forColumnWidth: width, cellSize: cellSize, spacing: spacing)
        guard columns > 0 else { return minimumTiles }
        return min(max(columns * targetRows, minimumTiles), maximumTiles)
    }

    /// Copy for the collapsed empty state, distinguishing "this folder has no
    /// media" from "media exists but previews could not be generated" — the
    /// second is a signal worth surfacing, not hiding behind a generic line.
    static func emptyResultMessage(foundMediaCount: Int) -> String {
        if foundMediaCount > 0 {
            return "Found \(foundMediaCount) media file\(foundMediaCount == 1 ? "" : "s"), but previews couldn't be created for them."
        }
        return "No photos or videos in this folder yet. Frames appear here as soon as Chronoframe can see them."
    }
}

private struct ContactSheetHeroPlaceholder: View {
    var body: some View {
        VStack(spacing: 9) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
            Text("No previewable frames")
                .font(.caption.weight(.semibold))
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            EmptyFilmstripPattern()
                .opacity(0.55)
        }
    }
}

private struct EmptyFilmstripPattern: View {
    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<6, id: \.self) { index in
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.white.opacity(index == 2 ? 0.18 : 0.10), lineWidth: 0.5)
                    .background(Color.white.opacity(index == 2 ? 0.06 : 0.03), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .frame(width: index == 2 ? 74 : 52, height: index == 2 ? 96 : 78)
            }
        }
    }
}

struct ContactSheetThumbnailCell: View {
    let thumbnail: NSImage?
    let cellSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(thumbnail == nil ? Color.white.opacity(0.06) : Color.clear)
            .overlay {
                if let thumbnail {
                    Image(nsImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: cellSize, height: cellSize)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .transition(.opacity)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DesignTokens.ColorSystem.imageStageHairline, lineWidth: 0.5)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(DesignTokens.ColorSystem.photoEdgeHighlight, lineWidth: thumbnail == nil ? 0 : 0.5)
                    .blendMode(.screen)
            }
            .frame(width: cellSize, height: cellSize)
            .clipped()
            .shadow(color: .black.opacity(thumbnail == nil ? 0 : 0.18), radius: 4, x: 0, y: 2)
    }
}

enum ContactSheetThumbnailPipeline {
    static func candidateLimit(for count: Int) -> Int {
        max(count, count * 4)
    }

    static func loadThumbnailData(
        from urls: [URL],
        count: Int,
        size: CGSize,
        scale: CGFloat,
        thumbnailData: @escaping @Sendable (URL, CGSize, CGFloat) async -> Data? = Self.thumbnailData(for:size:scale:)
    ) async -> [Data] {
        guard count > 0 else { return [] }

        let candidates = Array(urls.prefix(candidateLimit(for: count)))
        var byIndex: [Int: Data] = [:]
        await withTaskGroup(of: ThumbnailResult.self) { group in
            for (index, url) in candidates.enumerated() {
                group.addTask {
                    let imageData = await thumbnailData(url, size, scale)
                    return ThumbnailResult(index: index, imageData: imageData)
                }
            }

            for await result in group {
                if let imageData = result.imageData {
                    byIndex[result.index] = imageData
                }
            }
        }

        return candidates.indices.compactMap { byIndex[$0] }.prefix(count).map { $0 }
    }

    private static func thumbnailData(for url: URL, size: CGSize, scale: CGFloat) async -> Data? {
        await ThumbnailRenderer.pngData(for: url, size: size, scale: scale)
    }
}

// MARK: - Loader

@MainActor
private final class ContactSheetLoader: ObservableObject {
    @Published var thumbnails: [NSImage?] = []
    @Published private(set) var phase: Phase = .idle
    /// Media files seen during enumeration (capped at the candidate limit).
    /// Distinguishes "empty folder" from "previews failed" in the empty state.
    @Published private(set) var foundMediaCount = 0

    private var lastSource: String = ""

    enum Phase: Equatable {
        case idle
        case loading
        case finished
    }

    var isLoading: Bool {
        phase == .loading
    }

    var didFinishLoading: Bool {
        phase == .finished
    }

    var loadedThumbnailCount: Int {
        thumbnails.compactMap { $0 }.count
    }

    func load(sourcePath: String, sourceURL: URL?, count: Int, cellSize: CGFloat) async {
        let trimmed = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed == lastSource { return }
        lastSource = trimmed

        guard !trimmed.isEmpty else {
            thumbnails = []
            foundMediaCount = 0
            phase = .idle
            return
        }

        thumbnails = Array(repeating: nil, count: count)
        foundMediaCount = 0
        phase = .loading
        let urls = await Self.findMediaFiles(in: trimmed, url: sourceURL, limit: ContactSheetThumbnailPipeline.candidateLimit(for: count))

        // Bail if the user moved on to a different source while the
        // file enumeration was running. Without this check, a slow
        // walk over the old source can publish stale thumbnails on top
        // of the new source's grid.
        guard trimmed == lastSource, !Task.isCancelled else { return }

        foundMediaCount = urls.count

        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let size = CGSize(width: cellSize * 2, height: cellSize * 2)
        let imageData = await ContactSheetThumbnailPipeline.loadThumbnailData(
            from: urls,
            count: count,
            size: size,
            scale: scale
        )

        // And again after the thumbnail pipeline completes.
        guard trimmed == lastSource, !Task.isCancelled else { return }

        for (index, data) in imageData.prefix(count).enumerated() {
            if let image = NSImage(data: data) {
                thumbnails[index] = image
            }
        }
        phase = .finished
    }

    nonisolated private static func findMediaFiles(in path: String, url: URL?, limit: Int) async -> [URL] {
        #if DEBUG
        NSLog("ContactSheet: Starting findMediaFiles in path: %@, hasURL: %d", path, url != nil)
        #endif
        return await Task.detached(priority: .userInitiated) {
            let root = url ?? URL(fileURLWithPath: path, isDirectory: true)

            let didAccess = root.startAccessingSecurityScopedResource()
            defer { if didAccess { root.stopAccessingSecurityScopedResource() } }

            let keys: [URLResourceKey] = [.isRegularFileKey, .typeIdentifierKey, .creationDateKey]

            // Check if directory is readable at all from this thread
            let isReadable = FileManager.default.isReadableFile(atPath: root.path)
            #if DEBUG
            NSLog("ContactSheet: Path isReadable directly = %d", isReadable)
            #endif

            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else {
                #if DEBUG
                NSLog("ContactSheet: Failed to create directory enumerator for path: %@", root.path)
                #endif
                return []
            }

            var results: [URL] = []
            var checkedCount = 0
            while let next = enumerator.nextObject() {
                checkedCount += 1
                guard results.count < limit else { break }
                guard let fileURL = next as? URL else { continue }
                if Self.isLikelyMedia(fileURL) {
                    results.append(fileURL)
                }
            }
            #if DEBUG
            NSLog("ContactSheet: Finished findMediaFiles. Checked %d items, found %d media files.", checkedCount, results.count)
            #endif
            return results
        }.value
    }

    nonisolated private static let mediaExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp",
        "mp4", "mov", "m4v", "avi", "mkv", "3gp", "hevc",
        "cr2", "cr3", "nef", "arw", "raf", "rw2", "dng", "orf"
    ]

    nonisolated private static func isLikelyMedia(_ url: URL) -> Bool {
        mediaExtensions.contains(url.pathExtension.lowercased())
    }

}

private struct ThumbnailResult: Sendable {
    let index: Int
    let imageData: Data?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
