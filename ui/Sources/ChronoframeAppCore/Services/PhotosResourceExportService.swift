#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
#if canImport(Photos)
import Photos
#endif

#if canImport(Photos)
/// PhotoKit-backed, strictly read-only implementation of the export seam.
///
/// It re-fetches the live `PHAsset` by identifier, selects only ORIGINAL
/// (unedited) resources, and copies their bytes out with
/// `PHAssetResourceManager` — which reads. It never calls
/// `PHPhotoLibrary.performChanges` or any `PHAssetChangeRequest`, so importing
/// cannot modify, move, favorite, or delete anything in the user's library.
/// (See the Apple Photos read-only safety invariant and
/// `script/check_photos_import_readonly.sh`.)
public final class PhotosResourceExportService: PhotosResourceExporting {
    public init() {}

    public func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        guard let asset = Self.fetchAsset(localIdentifier: id) else { return [] }
        let phResources = PHAssetResource.assetResources(for: asset)
        return phResources.enumerated().compactMap { index, resource -> PhotosExportableResource? in
            guard Self.isOriginalImportableType(resource.type) else { return nil }
            let ext = (resource.originalFilename as NSString).pathExtension
            return PhotosExportableResource(
                assetID: id,
                resourceIndex: index,
                fileExtension: ext,
                originalFilename: resource.originalFilename
            )
        }
    }

    public func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        guard let asset = Self.fetchAsset(localIdentifier: resource.assetID) else {
            throw PhotosExportError.assetUnavailable
        }
        let phResources = PHAssetResource.assetResources(for: asset)
        guard resource.resourceIndex < phResources.count else {
            throw PhotosExportError.resourceUnavailable
        }
        let phResource = phResources[resource.resourceIndex]

        let options = PHAssetResourceRequestOptions()
        // Originals stored only in iCloud must be fetched over the network.
        options.isNetworkAccessAllowed = true

        // Write to a hidden temp sibling then atomically rename, so a partial
        // or interrupted write never leaves a truncated file under the final
        // name for the transfer pipeline to pick up.
        let tempURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString).photoexport.tmp")

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHAssetResourceManager.default().writeData(for: phResource, toFile: tempURL, options: options) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }

        do {
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
            }
            try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            throw error
        }
    }

    private static func fetchAsset(localIdentifier: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [localIdentifier], options: nil).firstObject
    }

    /// Only unedited originals: the still photo, the video, and a Live Photo's
    /// paired movie. Edited renders (`.fullSizePhoto`/`.fullSizeVideo`),
    /// adjustment data, and everything else are excluded so import always
    /// copies the master the user captured.
    private static func isOriginalImportableType(_ type: PHAssetResourceType) -> Bool {
        switch type {
        case .photo, .video, .pairedVideo:
            return true
        default:
            return false
        }
    }
}

enum PhotosExportError: Error {
    case assetUnavailable
    case resourceUnavailable
}
#endif
