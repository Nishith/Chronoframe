import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

/// Composes the spoken VoiceOver descriptions for the Photos import surfaces —
/// the authorization gate, album picker, asset cells, and the import button.
///
/// Kept as pure functions (no view state) so the wording is unit-testable
/// without a running UI or a real Photos library.
enum PhotosImportAccessibilityText {
    // Built per call rather than cached: `DateFormatter` is not `Sendable`, so
    // a stored static would trip Swift 6 strict concurrency on this
    // non-isolated enum. Label composition is not a hot path.
    private static func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Singular media noun for an asset.
    static func mediaNoun(_ asset: PhotosAssetSummary) -> String {
        switch asset.mediaKind {
        case .video: return "Video"
        case .photo: return "Photo"
        case .unsupported: return "Item"
        }
    }

    /// Spoken label for one asset cell: media kind, capture date, favorite and
    /// iCloud state, and whether it is currently selected for import.
    static func assetLabel(_ asset: PhotosAssetSummary, isSelected: Bool) -> String {
        var parts: [String] = [mediaNoun(asset)]
        if let date = asset.creationDate {
            parts.append(formattedDate(date))
        }
        if asset.isFavorite {
            parts.append("Favorite")
        }
        if asset.isCloudStoredOnly {
            parts.append("Stored in iCloud")
        }
        parts.append(isSelected ? "Selected" : "Not selected")
        return parts.joined(separator: ", ")
    }

    /// Spoken label for an album row in the picker.
    static func albumLabel(_ album: PhotosAlbumSummary) -> String {
        let noun = album.approximateCount == 1 ? "item" : "items"
        return "\(album.title), \(album.approximateCount) \(noun)"
    }

    /// Spoken label for the primary import button, reflecting the selection.
    static func importButtonLabel(selectedCount: Int) -> String {
        switch selectedCount {
        case 0:
            return "Review and import. Select photos or videos first."
        case 1:
            return "Review and import 1 selected item"
        default:
            return "Review and import \(selectedCount) selected items"
        }
    }

    /// Spoken description of the authorization gate for a blocked/undetermined
    /// state, so VoiceOver users understand why the browser is not shown.
    static func authorizationGateLabel(_ status: PhotosAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Chronoframe needs permission to read your Photos library."
        case .denied:
            return "Photos access is turned off. Turn it on in System Settings to import."
        case .restricted:
            return "Photos access is restricted on this Mac and can't be changed here."
        case .authorized, .limited:
            return ""
        }
    }
}
