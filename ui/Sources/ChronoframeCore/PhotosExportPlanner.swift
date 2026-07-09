import Foundation

/// One asset's place in a Photos export: the live asset to re-fetch and the
/// collision-free staging basename (no extension) every one of its original
/// resources will share. A Live Photo's still and paired movie both use this
/// stem so they land in staging as `IMG_0001.HEIC` + `IMG_0001.MOV` and pair
/// by basename in the existing transfer pipeline for free.
public struct PhotosAssetExportEntry: Equatable, Sendable {
    public let assetID: String
    public let mediaKind: PhotosAssetSummary.MediaKind
    /// Sanitized, dot-safe, collision-free basename (no extension). The
    /// executor appends each original resource's real file extension.
    public let stagingStem: String

    public init(assetID: String, mediaKind: PhotosAssetSummary.MediaKind, stagingStem: String) {
        self.assetID = assetID
        self.mediaKind = mediaKind
        self.stagingStem = stagingStem
    }
}

/// An ordered, deduplicated plan of assets to export into a staging directory.
/// The plan carries no bytes and no PhotoKit types — it is a pure description
/// the executor consumes.
public struct PhotosExportPlan: Equatable, Sendable {
    public let entries: [PhotosAssetExportEntry]

    public init(entries: [PhotosAssetExportEntry]) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var assetIDs: [String] { entries.map(\.assetID) }
}

/// Turns a user's asset selection into a deterministic export plan.
///
/// Read-only and pure: it filters out non-importable media, derives a stable
/// staging basename from each asset's original filename, and guarantees the
/// stems are unique so two assets that share an original filename (or a Live
/// Photo still + movie across two different assets) can never overwrite one
/// another in staging.
public enum PhotosExportPlanner {
    public static func plan(for assets: [PhotosAssetSummary]) -> PhotosExportPlan {
        var entries: [PhotosAssetExportEntry] = []
        var usedStems = Set<String>()
        var seenAssetIDs = Set<String>()

        for asset in assets {
            guard asset.mediaKind.isImportable else { continue }
            // A selection should never contain the same asset twice, but if
            // it does, keep the first and drop the duplicate so we never
            // stage the same original under two stems.
            guard seenAssetIDs.insert(asset.id).inserted else { continue }

            let base = sanitizedStem(from: asset.originalFilename, mediaKind: asset.mediaKind)
            let unique = disambiguate(base, against: &usedStems)
            entries.append(
                PhotosAssetExportEntry(
                    assetID: asset.id,
                    mediaKind: asset.mediaKind,
                    stagingStem: unique
                )
            )
        }
        return PhotosExportPlan(entries: entries)
    }

    /// Derives a filesystem- and discovery-safe basename (no extension) from
    /// an original filename. Strips the extension, removes path separators and
    /// control characters, and refuses a leading dot so the staged file is
    /// never treated as hidden by media discovery.
    static func sanitizedStem(from originalFilename: String?, mediaKind: PhotosAssetSummary.MediaKind) -> String {
        let fallback = mediaKind == .video ? "Video" : "Photo"
        guard let originalFilename, !originalFilename.isEmpty else { return fallback }

        // An empty stem (e.g. a dotfile-only name) flows through to the
        // fallback below, so no special-casing is needed here.
        let stem = (originalFilename as NSString).deletingPathExtension

        let scalars = stem.unicodeScalars.map { scalar -> Character in
            if scalar == "/" || scalar == ":" || scalar == "\\" {
                return "_"
            }
            if scalar.properties.isDefaultIgnorableCodePoint || scalar.value < 0x20 {
                return "_"
            }
            return Character(scalar)
        }
        var cleaned = String(scalars).trimmingCharacters(in: .whitespaces)
        // Strip leading dots so the staged file is never a dotfile that media
        // discovery skips.
        while cleaned.hasPrefix(".") {
            cleaned.removeFirst()
        }
        cleaned = cleaned.trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? fallback : cleaned
    }

    /// Appends `-2`, `-3`, … until the stem is unused, then reserves it.
    private static func disambiguate(_ base: String, against used: inout Set<String>) -> String {
        if used.insert(base).inserted { return base }
        var suffix = 2
        while true {
            let candidate = "\(base)-\(suffix)"
            if used.insert(candidate).inserted { return candidate }
            suffix += 1
        }
    }
}
