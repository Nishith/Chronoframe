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
    /// `destinationURL` is an empty file the executor just created exclusively
    /// to claim the name; the implementation replaces it.
    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws
    /// Same as `writeResource(_:to:)`, additionally reporting 0...1 progress.
    func writeResource(
        _ resource: PhotosExportableResource,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
}

public extension PhotosResourceExporting {
    /// Default keeps every existing test double compiling: ignores progress.
    func writeResource(
        _ resource: PhotosExportableResource,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try await writeResource(resource, to: destinationURL)
    }
}

/// A single file written into the staging directory during export.
public struct PhotosExportedFile: Equatable, Codable, Sendable {
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
public struct PhotosAssetExportFailure: Equatable, Codable, Sendable {
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
    public let sourceDateHints: [String: SourceDateHint]

    public init(exportedFiles: [PhotosExportedFile], failures: [PhotosAssetExportFailure], sourceDateHints: [String: SourceDateHint] = [:]) {
        self.exportedFiles = exportedFiles
        self.failures = failures
        self.sourceDateHints = sourceDateHints
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

/// Per-asset progress of an export, in the order the executor produces it.
public enum PhotosExportEvent: Equatable, Sendable {
    /// `index` is 0-based within this export call.
    case assetStarted(assetID: String, index: Int, total: Int)
    /// 0...1 from the exporter, forwarded unchanged.
    case resourceProgress(assetID: String, fraction: Double)
    case assetCompleted(assetID: String, files: [PhotosExportedFile], sourceDateHints: [String: SourceDateHint])
    case assetFailed(assetID: String, message: String)
}

/// Thrown before any write of the next asset when staging space is below the floor.
public enum PhotosExportStop: Error, Equatable, Sendable {
    case lowStagingSpace(freeBytes: Int64, floorBytes: Int64)
}

/// Copies selected Photos originals into a Chronoframe-owned staging
/// directory, read-only. The staging directory is later handed to the
/// existing verified-transfer pipeline as the run source; the Photos library
/// itself is never modified regardless of success, failure, or cancellation.
public struct PhotosExportExecutor {
    private let exporter: any PhotosResourceExporting
    private let timeZone: TimeZone
    private let freeSpaceFloorBytes: Int64
    private let freeSpaceProvider: @Sendable (URL) -> Int64?
    /// Upper bound on candidate names tried per resource. Internal so a test
    /// can exhaust it without ten thousand files.
    var maxNameAttempts = 10_000

    public static let defaultFreeSpaceFloorBytes: Int64 = 2 * 1024 * 1024 * 1024

    /// `timeZone` picks the calendar day for items whose only date is Photos'
    /// own capture instant, which carries no timezone of its own.
    public init(
        exporter: any PhotosResourceExporting,
        timeZone: TimeZone = .current,
        freeSpaceFloorBytes: Int64 = PhotosExportExecutor.defaultFreeSpaceFloorBytes,
        freeSpaceProvider: @escaping @Sendable (URL) -> Int64? = PhotosExportExecutor.liveFreeSpace
    ) {
        self.exporter = exporter
        self.timeZone = timeZone
        self.freeSpaceFloorBytes = freeSpaceFloorBytes
        self.freeSpaceProvider = freeSpaceProvider
    }

    /// Available capacity for important usage on `url`'s volume; nil on error.
    public static func liveFreeSpace(at url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) else {
            return nil
        }
        return values.volumeAvailableCapacityForImportantUsage
    }

    public func export(
        plan: PhotosExportPlan,
        to stagingDirectory: URL,
        reservedFilenames: Set<String> = [],
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onEvent: @escaping @Sendable (PhotosExportEvent) -> Void = { _ in }
    ) async throws -> PhotosExportReceipt {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        // Discovery returns canonical URLs (notably /private/var for /var).
        let stagingRoot = stagingDirectory.resolvingSymlinksInPath()

        var exported: [PhotosExportedFile] = []
        var failures: [PhotosAssetExportFailure] = []
        // Compared by filesystem-style key (see `nameKey`): staging is usually
        // a case-insensitive, normalization-insensitive APFS volume.
        var usedFilenames = Set(reservedFilenames.map(Self.nameKey))
        var sourceDateHints: [String: SourceDateHint] = [:]

        for (entryIndex, entry) in plan.entries.enumerated() {
            try throwIfCancelled(isCancelled)

            // Stop before anything of this asset is written, so no rollback is
            // needed and every completed asset's files stay in place. An
            // unknown free-space value never stops the export.
            if let free = freeSpaceProvider(stagingDirectory), free < freeSpaceFloorBytes {
                throw PhotosExportStop.lowStagingSpace(freeBytes: free, floorBytes: freeSpaceFloorBytes)
            }
            onEvent(.assetStarted(assetID: entry.assetID, index: entryIndex, total: plan.entries.count))

            // Export all of an asset's resources as a unit. Files are buffered
            // and only published once every resource succeeds, so a partial
            // failure — a Live Photo whose still writes but whose paired movie
            // fails — rolls back the asset's files instead of handing the
            // transfer pipeline an incomplete pair.
            var assetFiles: [PhotosExportedFile] = []
            var writtenURLs: [URL] = []
            do {
                let resources = try await exporter.originalResources(forAssetID: entry.assetID)
                guard !resources.isEmpty else {
                    let message = "No original photo or video was available to import for this item."
                    failures.append(PhotosAssetExportFailure(assetID: entry.assetID, message: message))
                    onEvent(.assetFailed(assetID: entry.assetID, message: message))
                    continue
                }
                for resource in resources {
                    try throwIfCancelled(isCancelled)
                    // The name is claimed with an exclusive create, so nothing
                    // already in staging is ever replaced. Only a file this
                    // call created reaches the rollback list.
                    let destination = try claimDestination(
                        in: stagingRoot,
                        stem: entry.stagingStem,
                        fileExtension: resource.fileExtension,
                        resourceIndex: resource.resourceIndex,
                        used: &usedFilenames
                    )
                    // Include the current resource in rollback even if the
                    // exporter fails after creating a partial staging file.
                    writtenURLs.append(destination)
                    try await exporter.writeResource(resource, to: destination) { fraction in
                        onEvent(.resourceProgress(assetID: entry.assetID, fraction: fraction))
                    }
                    assetFiles.append(
                        PhotosExportedFile(
                            assetID: entry.assetID,
                            stagingStem: entry.stagingStem,
                            path: destination.path
                        )
                    )
                }
                try throwIfCancelled(isCancelled)
                let captureDate = resolveAssetDate(entry: entry, paths: assetFiles.map(\.path), isCancelled: { isCancelled() || Task.isCancelled })
                var assetHints: [String: SourceDateHint] = [:]
                for file in assetFiles {
                    try throwIfCancelled(isCancelled)
                    assetHints[SourceDateHint.pathKey(for: file.path)] = SourceDateHint(
                        identity: try FileIdentityHasher().hashIdentity(at: URL(fileURLWithPath: file.path)),
                        resolvedDate: captureDate
                    )
                }
                try throwIfCancelled(isCancelled)
                exported.append(contentsOf: assetFiles)
                sourceDateHints.merge(assetHints) { _, new in new }
                onEvent(.assetCompleted(assetID: entry.assetID, files: assetFiles, sourceDateHints: assetHints))
            } catch is CancellationError {
                rollBack(writtenURLs)
                throw CancellationError()
            } catch is PhotosExportNameExhausted {
                rollBack(writtenURLs)
                let message = "Chronoframe couldn't find a free file name for this item, so it was skipped. Your Photos library was not changed."
                failures.append(PhotosAssetExportFailure(assetID: entry.assetID, message: message))
                onEvent(.assetFailed(assetID: entry.assetID, message: message))
            } catch {
                // A resource failed mid-asset: roll back what was written so an
                // incomplete unit never reaches the transfer pipeline.
                rollBack(writtenURLs)
                let message = "Chronoframe couldn't read this item from Photos, so it was skipped. Your Photos library was not changed."
                failures.append(PhotosAssetExportFailure(assetID: entry.assetID, message: message))
                onEvent(.assetFailed(assetID: entry.assetID, message: message))
            }
        }

        return PhotosExportReceipt(exportedFiles: exported, failures: failures, sourceDateHints: sourceDateHints)
    }

    /// One date per asset: still metadata wins over the paired movie (whose
    /// recording may start before midnight), then movie metadata, filename,
    /// and Photos' asset instant, filed under its day in the import timezone.
    /// No metadata means Unknown, never import day.
    private func resolveAssetDate(entry: PhotosAssetExportEntry, paths: [String], isCancelled: @escaping @Sendable () -> Bool) -> ResolvedMediaDate {
        let ordered = paths.filter { MediaLibraryRules.isPhotoFile(path: $0) }
            + paths.filter { !MediaLibraryRules.isPhotoFile(path: $0) }
        var dates: [ResolvedMediaDate] = []
        for path in ordered {
            let date = FileDateResolver().resolveCaptureDate(for: path, isCancelled: isCancelled)
            if date.source == .photoMetadata || date.source == .videoMetadata { return date }
            dates.append(date)
        }
        if let filename = dates.first(where: { $0.source == .filename }) { return filename }
        if let date = entry.creationDate, date.timeIntervalSince1970.isFinite, !DateClassification.isUnknown(date) {
            return ResolvedMediaDate(
                date: date,
                source: .photosAsset,
                confidence: .medium,
                bucketTimeZoneOffsetSeconds: timeZone.secondsFromGMT(for: date)
            )
        }
        return .unknown
    }

    /// Removes a partially-exported asset's staged files so an incomplete unit
    /// never reaches the transfer pipeline.
    private func rollBack(_ urls: [URL]) {
        for url in urls {
            try? FileManager.default.removeItem(at: url)
        }
    }

    private func throwIfCancelled(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() || Task.isCancelled {
            throw CancellationError()
        }
    }

    /// Picks a free staging name for one resource and claims it by creating
    /// the file exclusively (`O_CREAT | O_EXCL`), returning its URL. The file
    /// is left empty for the exporter to replace with the resource's bytes.
    ///
    /// Candidates are `<stem>.<ext>`, then `<stem>-<resourceIndex>.<ext>`, then
    /// `<stem>-<resourceIndex>-<n>.<ext>` for n = 2, 3, ... A candidate is
    /// skipped when:
    /// - its name key is already in `used`: a reserved name (a file an
    ///   earlier, resumed export published), another asset's name in this
    ///   export, or an earlier resource of the same asset. The key folds case
    ///   and Unicode normalization (`nameKey`), so names APFS would treat as
    ///   one file collide here. A fallback name can itself equal another
    ///   asset's name, hence a loop rather than a single fallback.
    /// - the exclusive create finds the name already on disk (an unrecorded
    ///   leftover, or a variant the key does not foresee). The existing file
    ///   is never touched; the next candidate is tried.
    ///
    /// The search stops after `maxNameAttempts` candidates and throws
    /// `PhotosExportNameExhausted`, which fails only this asset.
    private func claimDestination(
        in directory: URL,
        stem: String,
        fileExtension: String,
        resourceIndex: Int,
        used: inout Set<String>
    ) throws -> URL {
        let ext = Self.normalizedExtension(fileExtension)
        for attempt in 0..<maxNameAttempts {
            let name = Self.candidateFilename(stem: stem, ext: ext, resourceIndex: resourceIndex, attempt: attempt)
            guard used.insert(Self.nameKey(name)).inserted else { continue }
            let url = directory.appendingPathComponent(name)
            if try Self.createExclusively(at: url) { return url }
        }
        throw PhotosExportNameExhausted()
    }

    private static func candidateFilename(stem: String, ext: String, resourceIndex: Int, attempt: Int) -> String {
        let base: String
        switch attempt {
        case 0: base = stem
        case 1: base = "\(stem)-\(resourceIndex)"
        default: base = "\(stem)-\(resourceIndex)-\(attempt)"
        }
        return ext.isEmpty ? base : "\(base).\(ext)"
    }

    /// Canonically decomposed, case-folded form of a filename. Diacritics are
    /// kept: "Cafe" and "Caf\u{E9}" are distinct files on APFS. Full case
    /// folding can merge a few names APFS keeps apart (ß and SS); the cost is
    /// a harmless extra rename, never an overwrite.
    static func nameKey(_ name: String) -> String {
        name.decomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
    }

    /// Creates an empty file at `url` without replacing or following anything.
    /// Returns false when the name is already taken.
    private static func createExclusively(at url: URL) throws -> Bool {
        let descriptor = open(url.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0o644)
        if descriptor >= 0 {
            close(descriptor)
            return true
        }
        if errno == EEXIST { return false }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    static func normalizedExtension(_ raw: String) -> String {
        var ext = raw.lowercased()
        while ext.hasPrefix(".") { ext.removeFirst() }
        return ext.filter { $0.isLetter || $0.isNumber }
    }
}

/// No free staging name was found for a resource within the attempt limit.
struct PhotosExportNameExhausted: Error {}
