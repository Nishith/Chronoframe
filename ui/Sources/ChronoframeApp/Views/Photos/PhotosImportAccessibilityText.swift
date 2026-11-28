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
        case .video: return String(localized: "Video", bundle: .module)
        case .photo: return String(localized: "Photo", bundle: .module)
        case .unsupported: return String(localized: "Item", bundle: .module)
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
            parts.append(String(localized: "Favorite", bundle: .module))
        }
        if asset.isCloudStoredOnly {
            parts.append(String(localized: "Stored in iCloud", bundle: .module))
        }
        parts.append(isSelected ? String(localized: "Selected", bundle: .module) : String(localized: "Not selected", bundle: .module))
        return parts.joined(separator: ", ")
    }

    /// Spoken label for an album row in the picker.
    static func albumLabel(_ album: PhotosAlbumSummary) -> String {
        let noun = album.approximateCount == 1 ? String(localized: "item", bundle: .module) : String(localized: "items", bundle: .module)
        return "\(album.title), \(album.approximateCount) \(noun)"
    }

    /// Spoken label for the primary import button, reflecting the selection.
    static func importButtonLabel(selectedCount: Int) -> String {
        switch selectedCount {
        case 0:
            return String(localized: "Review and import. Select photos or videos first.", bundle: .module)
        case 1:
            return String(localized: "Review and import 1 selected item", bundle: .module)
        default:
            return String(localized: "Review and import \(String(selectedCount)) selected items", bundle: .module)
        }
    }

    /// Spoken description of the authorization gate for a blocked/undetermined
    /// state, so VoiceOver users understand why the browser is not shown.
    static func authorizationGateLabel(_ status: PhotosAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return String(localized: "Chronoframe needs permission to read your Photos library.", bundle: .module)
        case .denied:
            return String(localized: "Photos access is turned off. Turn it on in System Settings to import.", bundle: .module)
        case .restricted:
            return String(localized: "Photos access is restricted on this Mac and can't be changed here.", bundle: .module)
        case .authorized, .limited:
            return ""
        }
    }
}
