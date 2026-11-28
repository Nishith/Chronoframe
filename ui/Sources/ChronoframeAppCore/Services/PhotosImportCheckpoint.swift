#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// One completely exported asset: every resource file and its content-bound date hint.
public struct PhotosCompletedAssetRecord: Equatable, Codable, Sendable {
    public let assetID: String
    public let files: [PhotosExportedFile]
    /// Keyed by `SourceDateHint.pathKey`.
    public let sourceDateHints: [String: SourceDateHint]
    /// The exported edited render, when "Include edited versions" was on and the asset had one.
    public let editedFile: PhotosExportedFile?

    public init(
        assetID: String,
        files: [PhotosExportedFile],
        sourceDateHints: [String: SourceDateHint],
        editedFile: PhotosExportedFile? = nil
    ) {
        self.assetID = assetID
        self.files = files
        self.sourceDateHints = sourceDateHints
        self.editedFile = editedFile
    }

    private enum CodingKeys: String, CodingKey {
        case assetID, files, sourceDateHints, editedFile
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        assetID = try container.decode(String.self, forKey: .assetID)
        files = try container.decode([PhotosExportedFile].self, forKey: .files)
        sourceDateHints = try container.decode([String: SourceDateHint].self, forKey: .sourceDateHints)
        editedFile = try container.decodeIfPresent(PhotosExportedFile.self, forKey: .editedFile)
    }
}

/// A per-asset problem with an optional extra file. The asset's original is
/// still exported and counted as completed.
public struct PhotosVariantFailure: Equatable, Codable, Sendable {
    public enum Reason: String, Codable, Sendable {
        case editedRenderUnavailable
    }

    public let assetID: String
    public let reason: Reason

    public init(assetID: String, reason: Reason) {
        self.assetID = assetID
        self.reason = reason
    }
}

public enum PhotosImportCheckpointState: String, Codable, Sendable {
    case inProgress   // a prepare is (or was, if the app died) running
    case stopped      // user pressed Stop; resumable
    case lowSpace     // export paused for free space; resumable
    case ready        // every planned asset is completed or failed; a run may consume it
}

public struct PhotosImportCheckpoint: Equatable, Codable, Sendable {
    public static let version = 2
    public static let filename = ".chronoframe_photos_checkpoint.json"

    public let version: Int
    public let importID: UUID
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public let destinationPath: String
    public let destinationBookmarkKeys: [String]
    public let plan: PhotosExportPlan
    public private(set) var completed: [PhotosCompletedAssetRecord]
    public private(set) var failures: [PhotosAssetExportFailure]
    public private(set) var state: PhotosImportCheckpointState
    /// The "Include edited versions" choice for this import, repeated on Resume.
    public let includeEditedVersions: Bool
    public private(set) var variantFailures: [PhotosVariantFailure]

    public init(
        importID: UUID,
        createdAt: Date,
        destinationPath: String,
        destinationBookmarkKeys: [String],
        plan: PhotosExportPlan,
        includeEditedVersions: Bool = false
    ) {
        self.version = Self.version
        self.importID = importID
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.destinationPath = destinationPath
        self.destinationBookmarkKeys = destinationBookmarkKeys
        self.plan = plan
        self.completed = []
        self.failures = []
        self.state = .inProgress
        self.includeEditedVersions = includeEditedVersions
        self.variantFailures = []
    }

    private enum CodingKeys: String, CodingKey {
        case version, importID, createdAt, updatedAt, destinationPath, destinationBookmarkKeys
        case plan, completed, failures, state, includeEditedVersions, variantFailures
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        importID = try container.decode(UUID.self, forKey: .importID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        destinationPath = try container.decode(String.self, forKey: .destinationPath)
        destinationBookmarkKeys = try container.decode([String].self, forKey: .destinationBookmarkKeys)
        plan = try container.decode(PhotosExportPlan.self, forKey: .plan)
        completed = try container.decode([PhotosCompletedAssetRecord].self, forKey: .completed)
        failures = try container.decode([PhotosAssetExportFailure].self, forKey: .failures)
        state = try container.decode(PhotosImportCheckpointState.self, forKey: .state)
        includeEditedVersions = try container.decodeIfPresent(Bool.self, forKey: .includeEditedVersions) ?? false
        variantFailures = try container.decodeIfPresent([PhotosVariantFailure].self, forKey: .variantFailures) ?? []
    }

    public var completedAssetIDs: Set<String> {
        Set(completed.map(\.assetID))
    }

    /// Plan entries minus completed minus failed, in plan order.
    public var remainingEntries: [PhotosAssetExportEntry] {
        let done = completedAssetIDs
        let failed = Set(failures.map(\.assetID))
        return plan.entries.filter { !done.contains($0.assetID) && !failed.contains($0.assetID) }
    }

    /// Last path component of every completed file.
    public var reservedFilenames: Set<String> {
        Set(completed.flatMap(\.files).map { URL(fileURLWithPath: $0.path).lastPathComponent })
    }

    public var isResumable: Bool {
        state == .stopped || state == .lowSpace || state == .inProgress
    }

    public var mergedSourceDateHints: [String: SourceDateHint] {
        var merged: [String: SourceDateHint] = [:]
        for record in completed {
            merged.merge(record.sourceDateHints) { _, new in new }
        }
        return merged
    }

    /// Completed asset IDs, in plan order.
    public var exportedAssetIDs: [String] {
        let done = completedAssetIDs
        return plan.entries.map(\.assetID).filter { done.contains($0) }
    }

    public mutating func recordCompleted(_ record: PhotosCompletedAssetRecord, at date: Date) {
        completed.append(record)
        updatedAt = date
    }

    /// Forgets the completed records of `assetIDs` so those assets count as
    /// remaining and are exported again.
    public mutating func discardCompleted(assetIDs: Set<String>) {
        completed.removeAll { assetIDs.contains($0.assetID) }
    }

    public mutating func recordFailure(_ failure: PhotosAssetExportFailure, at date: Date) {
        failures.append(failure)
        updatedAt = date
    }

    public mutating func recordVariantFailure(_ failure: PhotosVariantFailure, at date: Date) {
        variantFailures.append(failure)
        updatedAt = date
    }

    /// Forgets recorded failures so those assets count as remaining again.
    public mutating func clearFailures() {
        failures.removeAll()
    }

    public mutating func setState(_ state: PhotosImportCheckpointState, at date: Date) {
        self.state = state
        updatedAt = date
    }
}

public protocol PhotosImportCheckpointStoring: Sendable {
    /// nil when missing, unreadable, or a version other than 1 or 2.
    func load(in stagingDirectory: URL) -> PhotosImportCheckpoint?
    func save(_ checkpoint: PhotosImportCheckpoint, in stagingDirectory: URL) throws
    func remove(in stagingDirectory: URL)
}

public struct PhotosImportFileCheckpointStore: PhotosImportCheckpointStoring {
    public init() {}

    private func fileURL(in stagingDirectory: URL) -> URL {
        stagingDirectory.appendingPathComponent(PhotosImportCheckpoint.filename)
    }

    public func load(in stagingDirectory: URL) -> PhotosImportCheckpoint? {
        guard let data = try? Data(contentsOf: fileURL(in: stagingDirectory)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let checkpoint = try? decoder.decode(PhotosImportCheckpoint.self, from: data),
              checkpoint.version == 1 || checkpoint.version == PhotosImportCheckpoint.version
        else { return nil }
        return checkpoint
    }

    public func save(_ checkpoint: PhotosImportCheckpoint, in stagingDirectory: URL) throws {
        try FileManager.default.createDirectory(at: stagingDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(checkpoint)
        try data.write(to: fileURL(in: stagingDirectory), options: .atomic)
    }

    public func remove(in stagingDirectory: URL) {
        try? FileManager.default.removeItem(at: fileURL(in: stagingDirectory))
    }
}
