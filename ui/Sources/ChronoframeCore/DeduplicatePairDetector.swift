import AVFoundation
import Foundation
import ImageIO

/// Detects two kinds of file pairs that must be treated as a single unit
/// during deduplicate keep/delete decisions:
///
/// 1. RAW + JPEG sidecars — same parent dir + same basename, one extension
///    in `MediaLibraryRules.rawExtensions`, the other in `{jpg, jpeg, heic}`.
/// 2. Live Photo pairs — HEIC still + sibling MOV that share the same
///    Apple Content Identifier (ImageIO key 17 in maker-Apple, QuickTime
///    `com.apple.quicktime.content.identifier` in the movie).
public enum DeduplicatePairDetector {
    public struct DetectionResult: Sendable, Equatable {
        public var pairs: [String: Pair]
        public var unsupportedMoviePaths: Set<String>

        public init(pairs: [String: Pair] = [:], unsupportedMoviePaths: Set<String> = []) {
            self.pairs = pairs
            self.unsupportedMoviePaths = unsupportedMoviePaths
        }
    }
    public static let rawExtensions: Set<String> = [
        ".dng", ".nef", ".cr2", ".cr3", ".arw", ".raf", ".orf", ".rw2",
    ]
    public static let companionablePhotoExtensions: Set<String> = [
        ".jpg", ".jpeg", ".heic",
    ]

    /// Metadata sidecar extensions. A sidecar carries edits/ratings for a photo
    /// and is not itself a dedup candidate (never hashed or clustered) — it must
    /// travel with its parent photo as a unit.
    public static let sidecarExtensions: Set<String> = [".xmp", ".aae"]

    /// Injection seam for sidecar existence checks so `detectSidecars` is
    /// unit-testable without a real filesystem. Production hits disk.
    nonisolated(unsafe) public static var sidecarFileExists: @Sendable (String) -> Bool = { path in
        FileManager.default.fileExists(atPath: path)
    }

    public struct Pair: Sendable, Equatable {
        public var primaryPath: String
        public var secondaryPath: String
        public var kind: Kind

        public enum Kind: String, Sendable, Equatable {
            case rawJpeg
            case livePhoto
        }
    }

    /// Scan the given paths and return a map from path → partner path for
    /// every detected pair. Paths that have no partner are absent from the
    /// map. Each pair's two members both appear as keys (mutual link).
    public static func detectPairs(
        in paths: [String],
        includeLivePhotos: Bool,
        movieMetadataLoader: any LivePhotoMetadataLoading = BoundedLivePhotoMetadataLoader()
    ) async -> [String: Pair] {
        await detectPairResult(
            in: paths,
            includeLivePhotos: includeLivePhotos,
            movieMetadataLoader: movieMetadataLoader
        ).pairs
    }

    public static func detectPairResult(
        in paths: [String],
        includeLivePhotos: Bool,
        movieMetadataLoader: any LivePhotoMetadataLoading = BoundedLivePhotoMetadataLoader()
    ) async -> DetectionResult {
        var pairs: [String: Pair] = [:]

        let rawJpegByBasename = groupByBasename(paths)
        for (_, group) in rawJpegByBasename where group.count > 1 {
            // Partition into RAW vs companion image; ignore everything else.
            var rawPath: String?
            var companionPath: String?
            for entry in group {
                let ext = MediaLibraryRules.normalizedExtension(for: entry)
                if rawExtensions.contains(ext) { rawPath = entry }
                else if companionablePhotoExtensions.contains(ext) { companionPath = entry }
            }
            if let rawPath, let companionPath {
                let pair = Pair(primaryPath: rawPath, secondaryPath: companionPath, kind: .rawJpeg)
                pairs[rawPath] = pair
                pairs[companionPath] = pair
            }
        }

        guard includeLivePhotos, !Task.isCancelled else { return DetectionResult(pairs: pairs) }

        // Live Photo: read content identifier from each HEIC and from each
        // sibling MOV; match within the same parent directory.
        let heicByDirectory = groupByDirectory(paths.filter { $0.lowercased().hasSuffix(".heic") })
        let movByDirectory = groupByDirectory(paths.filter {
            let ext = MediaLibraryRules.normalizedExtension(for: $0)
            return ext == ".mov" || ext == ".m4v"
        })
        let allMovieMetadata = await movieMetadataLoader.loadIdentifiers(
            for: movByDirectory.values.flatMap { $0 }.map { URL(fileURLWithPath: $0) }
        )

        for (directory, heics) in heicByDirectory {
            guard let movs = movByDirectory[directory] else { continue }
            let moviePaths = Set(movs)
            let movByIdentifier = allMovieMetadata.identifiersByPath.reduce(into: [String: String]()) { acc, entry in
                if moviePaths.contains(entry.key) { acc[entry.value] = entry.key }
            }
            guard !movByIdentifier.isEmpty else { continue }

            for heic in heics {
                guard let id = livePhotoIdentifier(forImageAt: URL(fileURLWithPath: heic)) else { continue }
                guard let movPath = movByIdentifier[id] else { continue }
                let pair = Pair(primaryPath: heic, secondaryPath: movPath, kind: .livePhoto)
                pairs[heic] = pair
                pairs[movPath] = pair
            }
        }

        return DetectionResult(
            pairs: pairs,
            unsupportedMoviePaths: allMovieMetadata.unsupportedPaths
        )
    }

    /// Maps each media path to any co-located sidecar files that share its
    /// basename. A sidecar may replace the extension (`photo.xmp`) or be
    /// appended to the full filename (`photo.jpg.xmp`); both forms are matched
    /// in the same directory. Sidecars are deduplicated per media path.
    ///
    /// `.aae` (iPhone edit instructions) uses both forms too, plus
    /// `IMG_<digits>.<ext>` owning `IMG_E<digits>.aae` (exact digits). Because
    /// iPhones write `.AAE`, `.aae` matches are returned with their on-disk
    /// spelling, resolved against the directory's entries.
    ///
    /// Note both `photo.raw` and `photo.jpg` resolve `photo.xmp` to the same
    /// shared sidecar — so a sidecar can have multiple owners, which is why
    /// deletion fanout is gated on *every* owner being deleted (Keep-wins).
    public static func detectSidecars(for mediaPaths: [String]) -> [String: [String]] {
        var result: [String: [String]] = [:]
        var directoryListings: [String: [String: [String]]] = [:]
        for path in mediaPaths {
            let url = URL(fileURLWithPath: path)
            let directory = url.deletingLastPathComponent()
            let stem = url.deletingPathExtension().lastPathComponent
            let fullName = url.lastPathComponent
            var found: [String] = []
            for ext in [".xmp", ".aae"].filter(sidecarExtensions.contains) {
                if ext == ".aae" {
                    var candidateNames = [stem + ext, fullName + ext]
                    // iOS edit form: IMG_<digits>.<ext> owns IMG_E<digits>.aae.
                    let digits = String(stem.dropFirst(4))
                    if stem.count > 4, stem.prefix(4).uppercased() == "IMG_",
                       digits.allSatisfy({ $0.isASCII && $0.isNumber }) {
                        candidateNames.append("IMG_E" + digits + ext)
                    }
                    for resolved in onDiskSidecarPaths(
                        named: candidateNames,
                        in: directory,
                        listings: &directoryListings
                    ) where !found.contains(resolved) {
                        found.append(resolved)
                    }
                    continue
                }
                // Replaced-extension form: photo.xmp
                let replaced = directory.appendingPathComponent(stem + ext).path
                if sidecarFileExists(replaced) {
                    found.append(replaced)
                }
                // Appended form: photo.jpg.xmp
                let appended = directory.appendingPathComponent(fullName + ext).path
                if appended != replaced, sidecarFileExists(appended) {
                    found.append(appended)
                }
            }
            if !found.isEmpty {
                result[path] = found
            }
        }
        return result
    }

    /// Resolves each candidate name against the directory's real entries
    /// (case-insensitive), so the returned paths use the on-disk spelling and
    /// work on case-sensitive volumes. Each directory is listed at most once
    /// per `detectSidecars` call. Existence is still confirmed through
    /// `sidecarFileExists`.
    private static func onDiskSidecarPaths(
        named candidateNames: [String],
        in directory: URL,
        listings: inout [String: [String: [String]]]
    ) -> [String] {
        let directoryPath = directory.path
        if listings[directoryPath] == nil {
            var entriesByLowercasedName: [String: [String]] = [:]
            let entries = ((try? FileManager.default.contentsOfDirectory(atPath: directoryPath)) ?? []).sorted()
            for entry in entries {
                entriesByLowercasedName[entry.lowercased(), default: []].append(entry)
            }
            listings[directoryPath] = entriesByLowercasedName
        }
        var resolved: [String] = []
        for lowercasedName in Set(candidateNames.map { $0.lowercased() }).sorted() {
            for entry in listings[directoryPath]?[lowercasedName] ?? [] {
                let entryPath = directory.appendingPathComponent(entry).path
                if sidecarFileExists(entryPath) {
                    resolved.append(entryPath)
                }
            }
        }
        return resolved
    }

    static func groupByBasename(_ paths: [String]) -> [String: [String]] {
        var buckets: [String: [String]] = [:]
        for path in paths {
            let url = URL(fileURLWithPath: path)
            let base = url.deletingPathExtension().path
            buckets[base, default: []].append(path)
        }
        return buckets
    }

    static func groupByDirectory(_ paths: [String]) -> [String: [String]] {
        var buckets: [String: [String]] = [:]
        for path in paths {
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            buckets[parent, default: []].append(path)
        }
        return buckets
    }

    /// Read the Apple Content Identifier from a HEIC's maker-Apple
    /// dictionary. Returns nil if the file is not a Live Photo still.
    public static func livePhotoIdentifier(forImageAt url: URL) -> String? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let makerApple = properties[kCGImagePropertyMakerAppleDictionary] as? [String: Any]
        else {
            return nil
        }
        // Key "17" is Apple's documented Content Identifier slot.
        return makerApple["17"] as? String
    }

    /// Read the Apple Content Identifier from a QuickTime movie's metadata.
    /// Returns nil if the file is not the .mov half of a Live Photo.
    public static func livePhotoIdentifier(forMovieAt url: URL) async -> String? {
        await BoundedLivePhotoMetadataLoader()
            .loadIdentifiers(for: [url])
            .identifiersByPath[url.path]
    }
}
