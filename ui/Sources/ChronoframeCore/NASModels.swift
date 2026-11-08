import Foundation

/// Master switch for the NAS Library workspace. Release builds stay `false`
/// until the owner records release Go (NAS_REQUIREMENTS section 17.1, gate 7).
/// The remote copy policy (C-06, C-07, C-08, C-09) is NOT gated by this flag.
public enum NASCapability {
    #if DEBUG
    public nonisolated(unsafe) static var isEnabledOverride: Bool?
    #endif

    public static var isEnabled: Bool {
        #if DEBUG
        if let isEnabledOverride { return isEnabledOverride }
        return ProcessInfo.processInfo.environment["CHRONOFRAME_ENABLE_NAS"] == "1"
        #else
        return false
        #endif
    }
}

public enum NASVolumeKind: String, Codable, Sendable, Equatable {
    case local
    case remote
    case unknown
}

public struct NASVolumeObservation: Codable, Sendable, Equatable {
    public var kind: NASVolumeKind
    /// `statfs.f_fstypename`, for example "apfs" or "smbfs". Empty when unknown.
    public var fileSystemType: String
    /// `statfs.f_mntonname`. Empty when unknown.
    public var mountPoint: String
    /// Host parsed from `f_mntfromname` for smbfs/afpfs/nfs, lowercased, never with user info.
    public var serverHost: String?
    /// Share name parsed from `f_mntfromname`, percent-decoded, original case.
    public var shareName: String?
    /// `f_fsid.val[0]` in the low 32 bits, `f_fsid.val[1]` in the high 32 bits.
    public var fileSystemID: UInt64
    /// The path that was actually passed to statfs (nearest existing ancestor).
    public var observedPath: String

    public init(kind: NASVolumeKind, fileSystemType: String, mountPoint: String, serverHost: String?, shareName: String?, fileSystemID: UInt64, observedPath: String) {
        self.kind = kind
        self.fileSystemType = fileSystemType
        self.mountPoint = mountPoint
        self.serverHost = serverHost
        self.shareName = shareName
        self.fileSystemID = fileSystemID
        self.observedPath = observedPath
    }

    public static func unknown(observedPath: String) -> NASVolumeObservation {
        NASVolumeObservation(kind: .unknown, fileSystemType: "", mountPoint: "", serverHost: nil, shareName: nil, fileSystemID: 0, observedPath: observedPath)
    }
}

public struct NASLibraryObservation: Codable, Sendable, Equatable {
    public var volume: NASVolumeObservation
    /// Library root relative to `volume.mountPoint`, NFC, "" when the root is the mount point.
    public var rootRelativePath: String
    /// `lstat(root).st_ino`.
    public var rootFileID: UInt64
    /// `lstat(volume.mountPoint).st_ino`.
    public var shareRootFileID: UInt64
    /// `st_birthtimespec` of the root in seconds; nil when the filesystem reports 0.
    public var rootCreationTime: TimeInterval?

    public init(volume: NASVolumeObservation, rootRelativePath: String, rootFileID: UInt64, shareRootFileID: UInt64, rootCreationTime: TimeInterval?) {
        self.volume = volume
        self.rootRelativePath = rootRelativePath
        self.rootFileID = rootFileID
        self.shareRootFileID = shareRootFileID
        self.rootCreationTime = rootCreationTime
    }
}

public struct NASLibraryRecord: Codable, Sendable, Equatable, Identifiable {
    public static let currentSchemaVersion = 1
    public var libraryUUID: String
    public var displayName: String
    public var bookmark: FolderBookmark
    public var lastObservation: NASLibraryObservation
    public var lastValidatedAt: Date
    public var schemaVersion: Int
    public var id: String { libraryUUID }

    public init(libraryUUID: String, displayName: String, bookmark: FolderBookmark, lastObservation: NASLibraryObservation, lastValidatedAt: Date, schemaVersion: Int = NASLibraryRecord.currentSchemaVersion) {
        self.libraryUUID = libraryUUID
        self.displayName = displayName
        self.bookmark = bookmark
        self.lastObservation = lastObservation
        self.lastValidatedAt = lastValidatedAt
        self.schemaVersion = schemaVersion
    }
}

public enum NASIdentityMismatchReason: String, Codable, Sendable, Equatable, CaseIterable {
    case notRemote
    case missingShareName
    case fileSystemTypeChanged
    case shareNameChanged
    case rootRelativePathChanged
    case rootFileIDChanged
    case shareRootFileIDChanged
    case rootCreationTimeChanged
    case serverHostChanged
}

public enum NASIdentityMatch: Sendable, Equatable {
    case same
    case remounted(newMountPoint: String)
    case mismatch([NASIdentityMismatchReason])
    case ambiguous([NASIdentityMismatchReason])
}

public enum NASItemKind: String, Codable, Sendable, Equatable { case photo, video }

public enum NASItemHashState: String, Codable, Sendable, Equatable {
    case notCandidate   // unique size within scope: never read
    case emptyFile      // size 0: never read, never grouped
    case pending
    case hashed
    case unresolved
}

public enum NASDirectoryStatus: String, Codable, Sendable, Equatable {
    case assessed
    case unreadable
    case excludedSystem
    case skippedPackage
    case nestedMount
}

public enum NASIssueCategory: String, Codable, Sendable, Equatable, CaseIterable {
    case unreadableDirectory
    case unreadableItem
    case skippedLink
    case specialFile
    case excludedSystemContainer
    case skippedPackage
    case nestedMount
    case unresolvedCandidate
}

public struct NASIssue: Codable, Sendable, Equatable {
    public var category: NASIssueCategory
    public var relativePath: String
    public var detail: String
    public init(category: NASIssueCategory, relativePath: String, detail: String) {
        self.category = category
        self.relativePath = relativePath
        self.detail = detail
    }
}

public enum NASUnresolvedReason: String, Codable, Sendable, Equatable, CaseIterable {
    case notRegularFile
    case openFailed
    case sizeChangedBeforeRead
    case modificationTimeChanged
    case readFailed
    case bytesConsumedMismatch
    case sizeChangedDuringRead
    case volumeUnavailable
}

public struct NASReadCounters: Codable, Sendable, Equatable {
    public var bytesRead: Int64
    public var readCalls: Int
    public init(bytesRead: Int64 = 0, readCalls: Int = 0) {
        self.bytesRead = bytesRead
        self.readCalls = readCalls
    }
}

public enum NASHashOutcome: Sendable, Equatable {
    case hashed(FileIdentity, modificationTime: TimeInterval, counters: NASReadCounters)
    case unresolved(NASUnresolvedReason, errorCode: Int32?, counters: NASReadCounters)
}

public enum NASScanMode: String, Codable, Sendable, Equatable { case exactOnly }

public enum NASScanOutcome: String, Codable, Sendable, Equatable {
    case running
    case complete
    case completedWithGaps
    case cancelled
    case interruptedVolumeUnavailable
    case failed
}

public struct NASByteLedger: Codable, Sendable, Equatable {
    /// H: sum of sizes of candidates (size > 0 and size count >= 2), counted once per candidate.
    public var candidateBytesH: Int64
    /// Positive read() returns for candidates that ended `.hashed`.
    public var bytesReadClean: Int64
    /// Positive read() returns for candidates that ended `.unresolved`.
    public var bytesReadUnresolved: Int64
    /// Candidates whose digest was reused from an earlier generation with no read.
    public var cacheHits: Int
    public init(candidateBytesH: Int64 = 0, bytesReadClean: Int64 = 0, bytesReadUnresolved: Int64 = 0, cacheHits: Int = 0) {
        self.candidateBytesH = candidateBytesH
        self.bytesReadClean = bytesReadClean
        self.bytesReadUnresolved = bytesReadUnresolved
        self.cacheHits = cacheHits
    }
    /// NAS-NFR-09: allowed clean bytes = H + max(1% of H, 8 MiB).
    public var cleanReadBudget: Int64 { candidateBytesH + max(candidateBytesH / 100, 8 * 1024 * 1024) }
    public var isWithinBudget: Bool { bytesReadClean <= cleanReadBudget }
}

public struct NASScanCounts: Codable, Sendable, Equatable {
    public var directoriesAssessed: Int
    public var mediaFiles: Int
    public var mediaBytes: Int64
    public var unsupportedFiles: Int
    public var emptyFiles: Int
    public var candidateFiles: Int
    public var hashedFiles: Int
    public var unresolvedFiles: Int
    public var issueCount: Int
    public init(directoriesAssessed: Int = 0, mediaFiles: Int = 0, mediaBytes: Int64 = 0, unsupportedFiles: Int = 0, emptyFiles: Int = 0, candidateFiles: Int = 0, hashedFiles: Int = 0, unresolvedFiles: Int = 0, issueCount: Int = 0) {
        self.directoriesAssessed = directoriesAssessed
        self.mediaFiles = mediaFiles
        self.mediaBytes = mediaBytes
        self.unsupportedFiles = unsupportedFiles
        self.emptyFiles = emptyFiles
        self.candidateFiles = candidateFiles
        self.hashedFiles = hashedFiles
        self.unresolvedFiles = unresolvedFiles
        self.issueCount = issueCount
    }
}

public struct NASScanSummary: Codable, Sendable, Equatable {
    public var generation: Int64
    public var mode: NASScanMode
    public var startedAt: Date
    public var finishedAt: Date?
    public var outcome: NASScanOutcome
    public var counts: NASScanCounts
    public var ledger: NASByteLedger
    public var exactGroupCount: Int
    /// Logical redundant bytes: sum over groups of size * (memberCount - 1). Never "space freed".
    public var redundantLogicalBytes: Int64
    public init(generation: Int64, mode: NASScanMode, startedAt: Date, finishedAt: Date?, outcome: NASScanOutcome, counts: NASScanCounts, ledger: NASByteLedger, exactGroupCount: Int, redundantLogicalBytes: Int64) {
        self.generation = generation
        self.mode = mode
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.counts = counts
        self.ledger = ledger
        self.exactGroupCount = exactGroupCount
        self.redundantLogicalBytes = redundantLogicalBytes
    }
}

public struct NASDirectoryRow: Codable, Sendable, Equatable {
    public var relativePath: String
    public var status: NASDirectoryStatus
    public var mediaFileCount: Int
    public var mediaBytes: Int64
    public var unsupportedFileCount: Int
    public init(relativePath: String, status: NASDirectoryStatus, mediaFileCount: Int = 0, mediaBytes: Int64 = 0, unsupportedFileCount: Int = 0) {
        self.relativePath = relativePath
        self.status = status
        self.mediaFileCount = mediaFileCount
        self.mediaBytes = mediaBytes
        self.unsupportedFileCount = unsupportedFileCount
    }
}

public struct NASItemRow: Codable, Sendable, Equatable {
    public var relativePath: String
    public var kind: NASItemKind
    public var size: Int64
    public var modificationTime: TimeInterval
    public var fileID: UInt64
    public var digest: String?
    public var hashState: NASItemHashState
    public var unresolvedReason: NASUnresolvedReason?
    public init(relativePath: String, kind: NASItemKind, size: Int64, modificationTime: TimeInterval, fileID: UInt64, digest: String? = nil, hashState: NASItemHashState = .notCandidate, unresolvedReason: NASUnresolvedReason? = nil) {
        self.relativePath = relativePath
        self.kind = kind
        self.size = size
        self.modificationTime = modificationTime
        self.fileID = fileID
        self.digest = digest
        self.hashState = hashState
        self.unresolvedReason = unresolvedReason
    }
}

public struct NASExactGroup: Codable, Sendable, Equatable, Identifiable {
    public var digest: String
    public var size: Int64
    public var kind: NASItemKind
    /// Sorted ascending by relativePath (plain String `<` on NFC strings).
    public var memberRelativePaths: [String]
    public var id: String { digest }
    public var redundantLogicalBytes: Int64 { size * Int64(max(0, memberRelativePaths.count - 1)) }
    public init(digest: String, size: Int64, kind: NASItemKind, memberRelativePaths: [String]) {
        self.digest = digest
        self.size = size
        self.kind = kind
        self.memberRelativePaths = memberRelativePaths
    }
}

public struct NASReviewChoice: Codable, Sendable, Equatable {
    public var digest: String
    public var size: Int64
    public var keeperRelativePath: String?
    public var reviewedAt: Date
    public init(digest: String, size: Int64, keeperRelativePath: String?, reviewedAt: Date) {
        self.digest = digest
        self.size = size
        self.keeperRelativePath = keeperRelativePath
        self.reviewedAt = reviewedAt
    }
}

public enum NASAssessmentPhase: String, Codable, Sendable, Equatable { case enumerating, hashing, grouping }

public enum NASAssessmentEvent: Sendable, Equatable {
    case started(generation: Int64)
    case phaseStarted(NASAssessmentPhase)
    case enumerationProgress(directories: Int, files: Int, currentRelativePath: String)
    case hashingProgress(completed: Int, total: Int, bytesRead: Int64)
    case issue(NASIssue)
    case finished(NASScanSummary)
}

public enum NASAssessmentError: LocalizedError, Sendable, Equatable {
    case rootUnavailable(path: String)
    case rootIsLink(path: String)
    case stateInsideLibrary(statePath: String, rootPath: String)
    case storeLibraryMismatch(expected: String, found: String)
    case storeFailed(message: String)

    public var errorDescription: String? {
        switch self {
        case let .rootUnavailable(path): return "Chronoframe can't reach this folder right now: \(path). Nothing on the NAS was changed."
        case let .rootIsLink(path): return "This folder is a link, so Chronoframe won't assess it: \(path). Choose the real folder instead. Nothing was changed."
        case let .stateInsideLibrary(statePath, rootPath): return "Chronoframe refused to keep assessment data inside the library (\(statePath) is inside \(rootPath)). Nothing was changed."
        case .storeLibraryMismatch: return "Saved assessment data belongs to a different library, so Chronoframe didn't use it. Nothing on the NAS was changed."
        case .storeFailed: return "Chronoframe couldn't save assessment progress on this Mac. Nothing on the NAS was changed."
        }
    }
}

public enum NASRemoteCopyError: LocalizedError, Sendable, Equatable {
    case verificationRequired(destinationPath: String)
    case atomicNoReplaceUnsupported(destinationPath: String)
    case destinationVolumeChanged(mountPoint: String)

    public var errorDescription: String? {
        switch self {
        case let .verificationRequired(path):
            return "Copies to a network folder are always verified, so Chronoframe didn't start with verification turned off: \(path). Turn verification on and try again. Your originals were untouched."
        case let .atomicNoReplaceUnsupported(path):
            return "This network folder can't guarantee that a copy never replaces an existing file, so Chronoframe stopped before placing it: \(path). Your originals were untouched."
        case let .destinationVolumeChanged(mountPoint):
            return "The network folder at \(mountPoint) disconnected or changed, so Chronoframe stopped before the next copy. Your originals were untouched."
        }
    }
}
