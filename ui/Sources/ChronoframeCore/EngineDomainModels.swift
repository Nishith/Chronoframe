import Darwin
import Foundation

public struct FileIdentity: RawRepresentable, Hashable, Codable, Sendable {
    public var size: Int64
    public var digest: String

    public init(size: Int64, digest: String) {
        self.size = size
        self.digest = digest
    }

    public init?(rawValue: String) {
        let components = rawValue.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard
            components.count == 2,
            let size = Int64(components[0]),
            !components[1].isEmpty
        else {
            return nil
        }

        self.init(size: size, digest: String(components[1]))
    }

    public var rawValue: String {
        "\(size)_\(digest)"
    }
}

public enum CacheNamespace: Int, Codable, CaseIterable, Sendable {
    case source = 1
    case destination = 2
}

public struct FileCacheRecord: Equatable, Codable, Sendable {
    public var namespace: CacheNamespace
    public var path: String
    public var identity: FileIdentity
    public var size: Int64
    public var modificationTime: TimeInterval

    public init(
        namespace: CacheNamespace,
        path: String,
        identity: FileIdentity,
        size: Int64,
        modificationTime: TimeInterval
    ) {
        self.namespace = namespace
        self.path = path
        self.identity = identity
        self.size = size
        self.modificationTime = modificationTime
    }

    public var identityString: String {
        identity.rawValue
    }
}

public enum CopyJobStatus: String, Codable, CaseIterable, Sendable {
    case pending = "PENDING"
    case copied = "COPIED"
    case failed = "FAILED"
}

public struct CopyJobRecord: Equatable, Codable, Sendable {
    public var sourcePath: String
    public var destinationPath: String
    public var identity: FileIdentity
    public var status: CopyJobStatus

    public init(
        sourcePath: String,
        destinationPath: String,
        identity: FileIdentity,
        status: CopyJobStatus
    ) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.identity = identity
        self.status = status
    }

    public var identityString: String {
        identity.rawValue
    }
}

public struct SequenceCounterState: Equatable, Codable, Sendable {
    public var primaryByDate: [String: Int]
    public var duplicatesByDate: [String: Int]

    public init(
        primaryByDate: [String: Int] = [:],
        duplicatesByDate: [String: Int] = [:]
    ) {
        self.primaryByDate = primaryByDate
        self.duplicatesByDate = duplicatesByDate
    }
}

public struct PlannedTransfer: Equatable, Codable, Sendable {
    public var sourcePath: String
    public var destinationPath: String
    public var identity: FileIdentity
    public var dateBucket: String
    public var isDuplicate: Bool

    public init(
        sourcePath: String,
        destinationPath: String,
        identity: FileIdentity,
        dateBucket: String,
        isDuplicate: Bool
    ) {
        self.sourcePath = sourcePath
        self.destinationPath = destinationPath
        self.identity = identity
        self.dateBucket = dateBucket
        self.isDuplicate = isDuplicate
    }
}

public struct EngineArtifactLayout: Equatable, Codable, Sendable {
    public var queueDatabaseFilename: String
    public var runLogFilename: String
    public var logsDirectoryName: String
    public var dryRunReportPrefix: String
    public var auditReceiptPrefix: String

    public init(
        queueDatabaseFilename: String,
        runLogFilename: String,
        logsDirectoryName: String,
        dryRunReportPrefix: String,
        auditReceiptPrefix: String
    ) {
        self.queueDatabaseFilename = queueDatabaseFilename
        self.runLogFilename = runLogFilename
        self.logsDirectoryName = logsDirectoryName
        self.dryRunReportPrefix = dryRunReportPrefix
        self.auditReceiptPrefix = auditReceiptPrefix
    }

    public static let pythonReference = EngineArtifactLayout(
        queueDatabaseFilename: ".organize_cache.db",
        runLogFilename: ".organize_log.txt",
        logsDirectoryName: ".organize_logs",
        dryRunReportPrefix: "dry_run_report_",
        auditReceiptPrefix: "audit_receipt_"
    )
}

public struct PlannerNamingRules: Equatable, Codable, Sendable {
    public var sequenceWidth: Int
    public var duplicateDirectoryName: String
    public var unknownDateDirectoryName: String
    public var unknownFilenamePrefix: String
    public var collisionSuffixPrefix: String

    public init(
        sequenceWidth: Int,
        duplicateDirectoryName: String,
        unknownDateDirectoryName: String,
        unknownFilenamePrefix: String,
        collisionSuffixPrefix: String
    ) {
        self.sequenceWidth = sequenceWidth
        self.duplicateDirectoryName = duplicateDirectoryName
        self.unknownDateDirectoryName = unknownDateDirectoryName
        self.unknownFilenamePrefix = unknownFilenamePrefix
        self.collisionSuffixPrefix = collisionSuffixPrefix
    }

    public static let pythonReference = PlannerNamingRules(
        sequenceWidth: 3,
        duplicateDirectoryName: "Duplicate",
        unknownDateDirectoryName: "Unknown_Date",
        unknownFilenamePrefix: "Unknown_",
        collisionSuffixPrefix: "_collision_"
    )
}

public struct RetryPolicy: Equatable, Codable, Sendable {
    public var maxAttempts: Int
    public var minimumBackoffSeconds: Double
    public var maximumBackoffSeconds: Double
    public var nonRetryableErrnos: [Int32]

    public init(
        maxAttempts: Int,
        minimumBackoffSeconds: Double,
        maximumBackoffSeconds: Double,
        nonRetryableErrnos: [Int32]
    ) {
        self.maxAttempts = maxAttempts
        self.minimumBackoffSeconds = minimumBackoffSeconds
        self.maximumBackoffSeconds = maximumBackoffSeconds
        self.nonRetryableErrnos = nonRetryableErrnos
    }

    public static let pythonReference = RetryPolicy(
        maxAttempts: 5,
        minimumBackoffSeconds: 1,
        maximumBackoffSeconds: 10,
        nonRetryableErrnos: [
            Int32(ENOSPC),
            Int32(ENOENT),
            Int32(ENOTDIR),
            Int32(EISDIR),
            Int32(EINVAL),
        ]
    )
}

public struct FailureThresholds: Equatable, Codable, Sendable {
    public var consecutive: Int
    public var total: Int

    public init(consecutive: Int, total: Int) {
        self.consecutive = consecutive
        self.total = total
    }

    public static let pythonReference = FailureThresholds(consecutive: 5, total: 20)
}
