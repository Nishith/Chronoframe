#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// One original resource of a Photos asset, described without any PhotoKit
/// type so the export executor is testable off-device. The concrete
/// `PhotosResourceExportService` builds these from `PHAssetResource`s of
/// original (unedited) type only.
public struct PhotosExportableResource: Equatable, Sendable {
    public let assetID: String
    /// Index among the asset's original resources, used only to disambiguate
    /// the rare case of two same-extension resources on one asset.
    public let resourceIndex: Int
    /// Lower-cased file extension without a leading dot (e.g. `heic`, `mov`).
    public let fileExtension: String
    public let originalFilename: String

    public init(assetID: String, resourceIndex: Int, fileExtension: String, originalFilename: String) {
        self.assetID = assetID
        self.resourceIndex = resourceIndex
        self.fileExtension = fileExtension
        self.originalFilename = originalFilename
    }
}

/// Read-only export gateway to the Apple Photos library.
///
/// The seam surface is deliberately read-only: it can *list* an asset's
/// original resources and *copy* their bytes out to a Chronoframe-owned
/// staging URL — there is no method that mutates the library. This is how
/// the "Photos import is strictly read-only" safety invariant is enforced by
/// construction; the executor literally cannot reach a mutating PhotoKit API.
public protocol PhotosResourceExporting: Sendable {
    /// The original (unedited) importable resources for an asset, in the
    /// order they should be written. Read-only: implemented with
    /// `PHAssetResource.assetResources(for:)`.
    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource]
    /// Copies one resource's original bytes to `destinationURL`. Read-only
    /// against the library: implemented with `PHAssetResourceManager`, which
    /// only reads. Never calls `PHPhotoLibrary.performChanges`.
    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws
}

/// A single file written into the staging directory during export.
public struct PhotosExportedFile: Equatable, Sendable {
    public let assetID: String
    public let stagingStem: String
    public let path: String

    public init(assetID: String, stagingStem: String, path: String) {
        self.assetID = assetID
        self.stagingStem = stagingStem
        self.path = path
    }
}

/// An asset that could not be exported. The library is never changed, so a
/// failure only means that asset is absent from the import.
public struct PhotosAssetExportFailure: Equatable, Sendable {
    public let assetID: String
    public let message: String

    public init(assetID: String, message: String) {
        self.assetID = assetID
        self.message = message
    }
}

/// Outcome of exporting a plan into staging.
public struct PhotosExportReceipt: Equatable, Sendable {
    public let exportedFiles: [PhotosExportedFile]
    public let failures: [PhotosAssetExportFailure]

    public init(exportedFiles: [PhotosExportedFile], failures: [PhotosAssetExportFailure]) {
        self.exportedFiles = exportedFiles
        self.failures = failures
    }

    public var stagedFileCount: Int { exportedFiles.count }
    public var isEmpty: Bool { exportedFiles.isEmpty }
    /// Distinct assets that contributed at least one staged file.
    public var exportedAssetIDs: [String] {
        var seen = Set<String>()
        var order: [String] = []
        for file in exportedFiles where seen.insert(file.assetID).inserted {
            order.append(file.assetID)
        }
        return order
    }
}

/// Copies selected Photos originals into a Chronoframe-owned staging
/// directory, read-only. The staging directory is later handed to the
/// existing verified-transfer pipeline as the run source; the Photos library
/// itself is never modified regardless of success, failure, or cancellation.
public struct PhotosExportExecutor {
    private let exporter: any PhotosResourceExporting

    public init(exporter: any PhotosResourceExporting) {
        self.exporter = exporter
    }

    public func export(
        plan: PhotosExportPlan,
        to stagingDirectory: URL,
        isCancelled: @Sendable () -> Bool = { false }
    ) async throws -> PhotosExportReceipt {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)

        var exported: [PhotosExportedFile] = []
        var failures: [PhotosAssetExportFailure] = []
        var usedFilenames = Set<String>()

        for entry in plan.entries {
            try throwIfCancelled(isCancelled)
            do {
                let resources = try await exporter.originalResources(forAssetID: entry.assetID)
                guard !resources.isEmpty else {
                    failures.append(
                        PhotosAssetExportFailure(
                            assetID: entry.assetID,
                            message: "No original photo or video was available to import for this item."
                        )
                    )
                    continue
                }
                for resource in resources {
                    try throwIfCancelled(isCancelled)
                    let filename = uniqueFilename(
                        stem: entry.stagingStem,
                        fileExtension: resource.fileExtension,
                        resourceIndex: resource.resourceIndex,
                        used: &usedFilenames
                    )
                    let destination = stagingDirectory.appendingPathComponent(filename)
                    try await exporter.writeResource(resource, to: destination)
                    exported.append(
                        PhotosExportedFile(
                            assetID: entry.assetID,
                            stagingStem: entry.stagingStem,
                            path: destination.path
                        )
                    )
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures.append(
                    PhotosAssetExportFailure(
                        assetID: entry.assetID,
                        message: "Chronoframe couldn't read this item from Photos, so it was skipped. Your Photos library was not changed."
                    )
                )
            }
        }

        return PhotosExportReceipt(exportedFiles: exported, failures: failures)
    }

    private func throwIfCancelled(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() {
            throw CancellationError()
        }
    }

    /// Builds `<stem>.<ext>`, disambiguating within a single export the rare
    /// case of two resources on one asset resolving to the same filename.
    private func uniqueFilename(
        stem: String,
        fileExtension: String,
        resourceIndex: Int,
        used: inout Set<String>
    ) -> String {
        let ext = Self.normalizedExtension(fileExtension)
        let base = ext.isEmpty ? stem : "\(stem).\(ext)"
        if used.insert(base).inserted { return base }
        // The only way `base` collides is two resources of one asset sharing
        // an extension. The plan's stems are globally unique and
        // `resourceIndex` is unique per asset, so folding the index in always
        // yields a fresh, unique name.
        let folded = ext.isEmpty ? "\(stem)-\(resourceIndex)" : "\(stem)-\(resourceIndex).\(ext)"
        used.insert(folded)
        return folded
    }

    static func normalizedExtension(_ raw: String) -> String {
        var ext = raw.lowercased()
        while ext.hasPrefix(".") { ext.removeFirst() }
        return ext.filter { $0.isLetter || $0.isNumber }
    }
}
