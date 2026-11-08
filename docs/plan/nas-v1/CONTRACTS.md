# NAS v1 contracts

Status: approved plan contract for `docs/NAS_REQUIREMENTS.md` v1.0. Every work package (WP) cites contract IDs (`C-…`). Implement names, signatures, rules and copy **exactly**. If a contract is impossible to implement as written, stop that WP, log it in `BLOCKED.md`, and continue with the next independent WP. Do not invent a variant.

Conventions for every new file:
- Files in `ui/Sources/ChronoframeAppCore/**` and `ui/Sources/ChronoframeApp/**` start with `#if canImport(ChronoframeCore)` / `import ChronoframeCore` / `#endif` (and the same for `ChronoframeAppCore` in App files). The single-target Xcode build compiles all three modules together.
- Core types are `public`, `Sendable`, and have a `public init` with every stored property as a parameter.
- No `print`. No force unwraps outside tests. No `withAnimation` (use `Motion` helpers).
- Relative paths are NFC-normalized (`precomposedStringWithCanonicalMapping`), use `/`, and have no leading `/`.
- "Remote" below always means `NASVolumeKind.remote` **or** `.unknown` unless a rule says otherwise.

---

## C-01 Shared models — `ui/Sources/ChronoframeCore/NASModels.swift` (created verbatim by WP-00)

```swift
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
```

---

## C-02 Volume classification — `NASVolumeClassifier.swift` (Core, WP-01)

```swift
public struct NASStatfsSnapshot: Sendable, Equatable {
    public var fileSystemType: String   // f_fstypename
    public var mountedOn: String        // f_mntonname
    public var mountedFrom: String      // f_mntfromname
    public var flags: UInt32            // f_flags
    public var fileSystemID: UInt64     // packed as in C-01
    public init(fileSystemType: String, mountedOn: String, mountedFrom: String, flags: UInt32, fileSystemID: UInt64)
}

public struct NASVolumeClassifier: Sendable {
    public static let remoteFileSystemTypes: Set<String> = ["smbfs", "afpfs", "nfs", "webdav", "cifs", "ftp"]
    public var statfs: @Sendable (String) -> NASStatfsSnapshot?
    public init(statfs: @escaping @Sendable (String) -> NASStatfsSnapshot?)
    public static let live: NASVolumeClassifier   // wraps Darwin.statfs
    public func classify(_ url: URL) -> NASVolumeObservation
    public static func parseMountedFrom(_ value: String, fileSystemType: String) -> (serverHost: String?, shareName: String?)
}
```

Rules, in order:
1. Start at `url.standardizedFileURL.path`. If `statfs` returns nil, move to the parent path and retry, until "/". If every call returns nil, return `.unknown(observedPath: url.path)`.
2. `kind`: `.remote` if `fileSystemType` is in `remoteFileSystemTypes`; else `.remote` if `flags & UInt32(MNT_LOCAL) == 0`; else `.local`.
3. `serverHost`/`shareName` come from `parseMountedFrom` only when `fileSystemType` is in `remoteFileSystemTypes`; otherwise both nil.
4. `parseMountedFrom` for a value starting with `//` (smbfs, afpfs, webdav style): drop `//`; split once at the first `/` into authority and share; share is percent-decoded and loses any trailing `/`; empty share → nil. Authority: drop everything up to and including the last `@`; drop a `DOMAIN;` prefix (up to and including the last `;`); drop `:port`; lowercase; empty → nil. For nfs (`host:/path`): host = before the first `:`, lowercased; share = path after `:` without the leading `/`, or nil if empty. Any other format → (nil, nil).
5. Never store or log user names or passwords from `mountedFrom`.

Required parse cases (all in tests): `//nishith@DiskStation._smb._tcp.local/photo` → (`diskstation._smb._tcp.local`, `photo`); `//WORKGROUP;nishith:secret@192.168.1.20:445/Family%20Archive` → (`192.168.1.20`, `Family Archive`); `//guest@nas/` → (`nas`, nil); `nas.local:/volume1/photo` (nfs) → (`nas.local`, `volume1/photo`); `/dev/disk3s1` (apfs) → (nil, nil).

## C-03 System containers — `NASSystemContainerRules.swift` (Core, WP-01)

```swift
public enum NASSystemContainerRules {
    public static let excludedDirectoryNames: Set<String> = ["@eaDir", "#recycle", "#snapshot"]
    /// Exact whole-component match, case-insensitive. "My #recycle notes" and "backup" do not match.
    public static func isExcludedSystemContainer(name: String) -> Bool
}
```

## C-04 Library identity — `NASLibraryIdentity.swift` (Core, WP-02)

```swift
public enum NASLibraryIdentity {
    public struct FileStatus: Sendable, Equatable { public var fileID: UInt64; public var isDirectory: Bool; public var isSymbolicLink: Bool; public var birthTime: TimeInterval; public init(...) }
    /// Returns nil when the root can't be lstat'd or is not a directory.
    public static func observe(rootURL: URL, classifier: NASVolumeClassifier = .live, lstat: @Sendable (String) -> FileStatus? = NASLibraryIdentity.liveLstat) -> NASLibraryObservation?
    public static func compare(recorded: NASLibraryObservation, observed: NASLibraryObservation) -> NASIdentityMatch
    public static let liveLstat: @Sendable (String) -> FileStatus?
}

public enum NASShareLeaseKey {
    /// 32 lowercase hex characters: the first 32 of BLAKE2bHasher's hex digest of
    /// "v1|<fileSystemType>|<lowercased shareName, or "fsid:<fileSystemID>" when shareName is nil>|<shareRootFileID>".
    /// Server host is deliberately excluded so DNS/IP aliases of one share collide (safe over-serialization).
    public static func key(volume: NASVolumeObservation, shareRootFileID: UInt64) -> String
}
```

`observe` rules: lstat root; nil or not a directory → nil. Symbolic link root → nil. `rootRelativePath` = root path with the `volume.mountPoint` prefix and the following `/` removed, NFC; "" when equal; when the root path does not start with the mount point, use the full root path without the leading `/`. `shareRootFileID` = lstat(mountPoint).fileID, or 0 when mountPoint is empty or lstat fails. `rootCreationTime` = birthTime when > 0, else nil.

`compare` rules, evaluated completely, collecting reasons:
1. `observed.volume.kind != .remote` → reason `notRemote` (mismatch).
2. Either shareName nil → reason `missingShareName` (ambiguous).
3. `fileSystemType` differs → `fileSystemTypeChanged` (mismatch).
4. Both shareNames present and differ case-insensitively → `shareNameChanged` (mismatch).
5. `rootRelativePath` differs after NFC + lowercasing → `rootRelativePathChanged` (mismatch).
6. `rootFileID` differs → `rootFileIDChanged` (mismatch).
7. `shareRootFileID` differs and both non-zero → `shareRootFileIDChanged` (mismatch).
8. Both creation times non-nil and differ by more than 1.0 s → `rootCreationTimeChanged` (mismatch).
9. Both serverHosts non-nil and differ → `serverHostChanged` (ambiguous).
Result: any mismatch reason → `.mismatch(all mismatch reasons in the order above)`. Else any ambiguous reason → `.ambiguous(ambiguous reasons)`. Else mount points equal → `.same`, otherwise `.remounted(newMountPoint: observed.volume.mountPoint)`.

## C-05 Metered reader — `NASMeteredFileReader.swift` (Core, WP-03)

```swift
public struct NASMeteredFileReader: Sendable {
    public struct FileStat: Sendable, Equatable { public var isRegularFile: Bool; public var size: Int64; public var modificationTime: TimeInterval; public init(...) }
    public struct SystemCalls: Sendable {
        public var open: @Sendable (String) -> Int32              // returns fd or -1 with errno set
        public var fstat: @Sendable (Int32) -> FileStat?          // nil on failure
        public var read: @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int
        public var close: @Sendable (Int32) -> Void
        public var lastError: @Sendable () -> Int32               // errno
        public static let live: SystemCalls                        // open(path, O_RDONLY|O_CLOEXEC|O_NOFOLLOW)
        public init(...)
    }
    public static let chunkByteCount = 1 * 1024 * 1024
    public static let volumeUnavailableErrorCodes: Set<Int32> = [ENXIO, ENOTCONN, ETIMEDOUT, ESTALE, ENODEV, EHOSTDOWN, EHOSTUNREACH, ENETDOWN, ENETUNREACH]
    public var systemCalls: SystemCalls
    public init(systemCalls: SystemCalls = .live)
    public func hash(path: String, expectedSize: Int64, expectedModificationTime: TimeInterval) -> NASHashOutcome
}
```

Algorithm (must match exactly; the digest must equal `FileIdentityHasher().hashIdentity(at:).digest`):
1. `fd = open(path)`. On -1: errno in `volumeUnavailableErrorCodes` → `.unresolved(.volumeUnavailable, errno, zero counters)`; else `.unresolved(.openFailed, errno, zero)`.
2. `pre = fstat(fd)`. nil → `.readFailed`. Not regular → `.notRegularFile`. `pre.size != expectedSize` → `.sizeChangedBeforeRead`. `abs(pre.modificationTime - expectedModificationTime) >= 0.001` → `.modificationTimeChanged`. All with errorCode nil and zero counters.
3. `var hasher = BLAKE2bHasher(); hasher.update(Data(String(expectedSize).utf8))`. Loop with a 1 MiB buffer: `n = read(fd, buf, chunk)`; `readCalls += 1`. `n < 0` and errno == EINTR → continue. `n < 0` otherwise → `.volumeUnavailable` if errno is in the set, else `.readFailed`, with the counters so far. `n == 0` → stop. `n > 0` → `bytesRead += n`, `hasher.update(first n bytes)`; if `bytesRead > expectedSize` → stop and return `.bytesConsumedMismatch`.
4. `bytesRead != expectedSize` → `.bytesConsumedMismatch`.
5. `post = fstat(fd)`: nil → `.readFailed`; `post.size != expectedSize` → `.sizeChangedDuringRead`; mtime differs by ≥ 0.001 → `.modificationTimeChanged`.
6. Success → `.hashed(FileIdentity(size: expectedSize, digest: hasher.finalizeHexDigest()), modificationTime: post.modificationTime, counters:)`.
7. `close(fd)` exactly once on every path after a successful open.
`FileIdentityHasher.swift` is NOT modified.

## C-06 Assessment store — `NASAssessmentStore.swift` (Core, WP-04)

SQLite file at a caller-provided URL. Open sequence copies `OrganizerDatabase.init`'s anchor sequence (`DestinationMetadataFile.openAnchor(at:)` before `sqlite3_open_v2`, `confirmPathStillRefersToFile()` after), with flags `SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX`, then `PRAGMA busy_timeout=30000; PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; PRAGMA foreign_keys=ON;`. The store is always on the Mac's local disk (Application Support), so WAL is allowed here.

Schema (exact DDL, `CREATE … IF NOT EXISTS`):

```sql
CREATE TABLE Meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
CREATE TABLE Scans (
  generation INTEGER PRIMARY KEY,
  mode TEXT NOT NULL,
  algorithmVersion INTEGER NOT NULL,
  startedAt REAL NOT NULL,
  finishedAt REAL,
  outcome TEXT NOT NULL,
  countsJSON TEXT NOT NULL DEFAULT '{}',
  ledgerJSON TEXT NOT NULL DEFAULT '{}',
  previewRequests INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE Directories (
  generation INTEGER NOT NULL,
  relativePath TEXT NOT NULL,
  status TEXT NOT NULL,
  mediaFileCount INTEGER NOT NULL DEFAULT 0,
  mediaBytes INTEGER NOT NULL DEFAULT 0,
  unsupportedFileCount INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (generation, relativePath)
);
CREATE TABLE Items (
  generation INTEGER NOT NULL,
  relativePath TEXT NOT NULL,
  kind TEXT NOT NULL,
  size INTEGER NOT NULL,
  modificationTime REAL NOT NULL,
  fileID INTEGER NOT NULL,
  digest TEXT,
  hashState TEXT NOT NULL,
  unresolvedReason TEXT,
  PRIMARY KEY (generation, relativePath)
);
CREATE INDEX ItemsBySize ON Items(generation, size);
CREATE INDEX ItemsByDigest ON Items(generation, digest);
CREATE TABLE Issues (generation INTEGER NOT NULL, relativePath TEXT NOT NULL, category TEXT NOT NULL, detail TEXT NOT NULL);
CREATE TABLE ReviewChoices (digest TEXT PRIMARY KEY, size INTEGER NOT NULL, keeperRelativePath TEXT, reviewedAt REAL NOT NULL);
CREATE TABLE ReviewState (key TEXT PRIMARY KEY, value TEXT NOT NULL);
```

`Meta` rows: `schemaVersion` = "1", `libraryUUID`. `fileID` is stored with `Int64(bitPattern:)`. Counts and ledger are JSON-encoded `NASScanCounts`/`NASByteLedger` (JSONEncoder, sorted keys).

```swift
public final class NASAssessmentStore: @unchecked Sendable {
    public static let algorithmVersion = 1
    public init(url: URL, libraryUUID: String) throws          // throws NASAssessmentError.storeLibraryMismatch if Meta.libraryUUID differs
    public func close()
    public func beginScan(mode: NASScanMode, startedAt: Date) throws -> Int64   // max(generation)+1, starting at 1; outcome "running"
    public func latestGeneration(excluding generation: Int64? = nil) throws -> Int64?
    public func recordDirectories(_ rows: [NASDirectoryRow], generation: Int64) throws      // one transaction, INSERT OR REPLACE
    public func recordItems(_ rows: [NASItemRow], generation: Int64) throws                 // one transaction, INSERT OR REPLACE
    public func recordIssues(_ issues: [NASIssue], generation: Int64) throws                // one transaction
    public func markCandidates(generation: Int64) throws -> (candidateFiles: Int, candidateBytesH: Int64, emptyFiles: Int)
        // size 0 → emptyFile; size > 0 with COUNT(size) >= 2 in the generation → pending; others stay notCandidate
    public func pendingItems(generation: Int64) throws -> [NASItemRow]                      // hashState = pending, ordered by size DESC, relativePath
    public func reusableDigests(generation: Int64) throws -> [String: NASItemRow]           // hashState = hashed rows keyed by relativePath
    public func updateHashResults(_ rows: [NASItemRow], generation: Int64) throws           // updates digest/hashState/unresolvedReason, one transaction
    public func finishScan(generation: Int64, outcome: NASScanOutcome, counts: NASScanCounts, ledger: NASByteLedger, finishedAt: Date) throws
    public func scanSummary(generation: Int64) throws -> NASScanSummary?
    public func exactGroups(generation: Int64) throws -> [NASExactGroup]
        // hashed rows grouped by digest with count >= 2; sorted by redundantLogicalBytes DESC, then digest ASC
    public func directoryRows(generation: Int64) throws -> [NASDirectoryRow]                // ordered by relativePath
    public func issues(generation: Int64) throws -> [NASIssue]
    public func saveChoice(_ choice: NASReviewChoice) throws
    public func choices() throws -> [String: NASReviewChoice]
    public func setReviewState(_ value: String?, forKey key: String) throws                // nil deletes
    public func reviewState(forKey key: String) throws -> String?
    public func incrementPreviewRequests(generation: Int64) throws
    public func pruneGenerations(keepingLatest count: Int) throws                           // deletes Scans/Directories/Items/Issues rows of older generations; never ReviewChoices/ReviewState
}
```
`scanSummary` computes `exactGroupCount` and `redundantLogicalBytes` from `exactGroups`. A store error surfaces as `NASAssessmentError.storeFailed(message:)` with the SQLite message only in `message` (never shown in UI).

## C-07 Assessment scanner — `NASAssessmentScanner.swift` (Core, WP-05)

```swift
public struct NASAssessmentConfiguration: Sendable, Equatable {
    public var rootURL: URL
    public var stateURL: URL               // the store file location; must not be inside rootURL
    public var workerCount: Int            // default 2, clamped to 1...8
    public var checkpointDirectoryBatch: Int   // default 200
    public var hashResultBatch: Int        // default 200
    public init(rootURL: URL, stateURL: URL, workerCount: Int = 2, checkpointDirectoryBatch: Int = 200, hashResultBatch: Int = 200)
}

public struct NASScanFileSystem: Sendable {
    public struct Entry: Sendable, Equatable { public var name: String; public var isDirectory: Bool; public var isRegularFile: Bool; public var isSymbolicLink: Bool; public var isPackage: Bool; public var size: Int64; public var modificationTime: TimeInterval; public var fileID: UInt64; public var deviceID: Int32; public init(...) }
    public var listDirectory: @Sendable (String) throws -> [String]     // child names
    public var entry: @Sendable (String) -> Entry?                      // lstat + isPackage (URL .isPackageKey) for a full path; nil on failure
    public init(listDirectory:entry:)
    public static let live: NASScanFileSystem
}

public protocol NASActivityProviding: Sendable {
    func begin(reason: String) -> NSObjectProtocol
    func end(_ token: NSObjectProtocol)
}
public struct NASProcessActivityProvider: NASActivityProviding   // ProcessInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason:)

public final class NASAssessmentScanner: @unchecked Sendable {
    public init(store: NASAssessmentStore, reader: NASMeteredFileReader = NASMeteredFileReader(), fileSystem: NASScanFileSystem = .live, activity: any NASActivityProviding = NASProcessActivityProvider(), now: @escaping @Sendable () -> Date = { Date() })
    public func run(_ configuration: NASAssessmentConfiguration, isCancelled: @escaping @Sendable () -> Bool) -> AsyncThrowingStream<NASAssessmentEvent, Error>
}
```

Run algorithm:
1. Preflight (throw before any event): root path standardized; `stateURL.standardizedFileURL.path` equal to the root or starting with `root + "/"` → `stateInsideLibrary`. `fileSystem.entry(root)` nil → `rootUnavailable`; symbolic link → `rootIsLink`; not a directory → `rootUnavailable`. Record `rootDevice = entry.deviceID`.
2. Begin activity with reason `"Chronoframe: assessing a NAS library"`. End it exactly once when the stream finishes for any reason.
3. `generation = store.beginScan`, `previous = store.latestGeneration(excluding: generation)`. Yield `.started`, `.phaseStarted(.enumerating)`.
4. Enumeration: depth-first with an explicit stack, children sorted with `<` on NFC names. For each directory: `listDirectory` throws → directory row `unreadable` + issue `unreadableDirectory`; then if `fileSystem.entry(root)` is nil stop with outcome `interruptedVolumeUnavailable`. For each child name:
   - starts with `.` → skip silently (not counted).
   - `entry(childPath)` nil → issue `unreadableItem`.
   - symbolic link → issue `skippedLink`; never followed.
   - directory: `NASSystemContainerRules.isExcludedSystemContainer` → row `excludedSystem` + issue `excludedSystemContainer`; else `isPackage` (bundles, `.photoslibrary`, apps) → row `skippedPackage` + issue `skippedPackage`; else `deviceID != rootDevice` → row `nestedMount` + issue `nestedMount`; else push for traversal.
   - regular file: `MediaLibraryRules.shouldSkipDiscoveredFile(named:)` → skip silently; `MediaLibraryRules.isSupportedMediaFile(path:)` → item row (kind from `isVideoFile`) and add to this directory's counts; otherwise `unsupportedFileCount += 1`.
   - anything else → issue `specialFile`.
   Each traversed directory gets a row `assessed` with direct-child counts. Flush directory, item and issue rows every `checkpointDirectoryBatch` directories and at the end of enumeration. Check `isCancelled()` before each directory and every 256 children. Yield `.enumerationProgress` at most every 0.25 s. Never call any API that writes inside the root.
5. Candidates: `store.markCandidates`. H = candidateBytesH.
6. Reuse: when `previous` exists, for each pending item whose `previous` row is `hashed` with equal size, `abs(mtime Δ) < 0.001` and equal fileID → copy digest, state `hashed`, `cacheHits += 1`, no read.
7. Hashing: yield `.phaseStarted(.hashing)`. Hash remaining pending items with at most `workerCount` concurrent `reader.hash` calls (use `DispatchQueue.concurrentPerform` over chunks or a `TaskGroup` with a counter; either is acceptable if the concurrency bound holds and is tested). Hashed → digest, `bytesReadClean += counters.bytesRead`. Unresolved → state `unresolved`, reason, `bytesReadUnresolved += counters.bytesRead`, issue `unresolvedCandidate` with `detail = reason.rawValue`. `.volumeUnavailable`, or `.openFailed`/`.readFailed` followed by `entry(root) == nil` → stop scheduling, outcome `interruptedVolumeUnavailable`. Persist results every `hashResultBatch`. Yield `.hashingProgress` at most every 0.25 s and once at the end.
8. Yield `.phaseStarted(.grouping)`. Outcome: cancelled → `cancelled`; volume loss → `interruptedVolumeUnavailable`; any `unreadableDirectory`, `unreadableItem` or `unresolvedCandidate` issue → `completedWithGaps`; else `complete`. Excluded system containers, packages, links, special files and nested mounts do NOT make an assessment incomplete; they are reported exclusions.
9. `store.finishScan`, `store.pruneGenerations(keepingLatest: 2)`, yield `.finished(summary)`, finish the stream. A cancelled or interrupted scan still finishes with a summary; it never throws for those cases.

## C-08 Remote copy policy — `NASRemoteCopyPolicy.swift` (Core, WP-06) and `TransferExecutor.swift` changes

```swift
public struct NASRemoteCopyPolicy: Sendable, Equatable {
    public var isRemote: Bool               // volume.kind != .local
    public var volume: NASVolumeObservation
    public init(isRemote: Bool, volume: NASVolumeObservation)
    public static func resolve(destinationRoot: URL, classifier: NASVolumeClassifier = .live) -> NASRemoteCopyPolicy
    public static let local: NASRemoteCopyPolicy   // isRemote false, volume .local placeholder
}
```

`TransferExecutor` changes (WP-06 only; every other line stays byte-identical):
1. DEBUG seams added next to `exclusiveRename`: `remotePolicyProvider: @Sendable (URL) -> NASRemoteCopyPolicy` (default `{ NASRemoteCopyPolicy.resolve(destinationRoot: $0) }`), `fullFsync: @Sendable (Int32) -> Int32` (default `fcntl(fd, F_FULLFSYNC)`), `plainFsync: @Sendable (Int32) -> Int32` (default `fsync`), `volumeFileSystemID: @Sendable (String) -> UInt64?` (default statfs packed fsid). Release builds call the defaults directly.
2. `TransferFileCopyStrategy` gains `copyData` (`copyfile(…, COPYFILE_DATA)`); `.system` sets it.
3. `executeQueuedJobs` resolves the policy once from `destinationRoot` before scheduling. Remote and `verifyCopies == false` → no job runs; the run aborts with `abortReason = NASRemoteCopyError.verificationRequired(destinationPath:).errorDescription` through the existing abort/receipt path.
4. The policy is passed as a parameter (default `.local`) into `prepareAtomicCopy`, `copyFileContents`, `fsyncFile`, `finalizePreparedCopy` and `renameFile`. Local behavior is unchanged.
5. Remote `copyFileContents`: skip `clone`; `copyData` != 0 → throw the POSIX error (data failure). Then `copyMetadata`; != 0 → emit `RunIssue(severity: .warning, message: "Chronoframe copied and verified this file, but the network folder didn't accept some of its Finder metadata (tags, permissions or dates): <destinationPath>")` and continue.
6. Remote `fsyncFile`: open `O_RDWR | O_CLOEXEC | O_NOFOLLOW`; `fullFsync(fd) == 0` → done; else if errno is `ENOTSUP`, `EINVAL` or `ENOTTY` → `plainFsync(fd) == 0` or throw that errno; any other F_FULLFSYNC failure → throw.
7. Remote `renameFile`: `exclusiveRename` fails with `ENOTSUP` → throw `NASRemoteCopyError.atomicNoReplaceUnsupported(destinationPath:)`. `renameClaimingDestination` is never called for a remote policy.
8. `NASRemoteCopyError` is run-fatal: the job's temporary file is removed (as the existing failure path does), no further job is scheduled, and the run's `abortReason` is the error's `errorDescription`, using the same state the failure-threshold abort uses in both the serial path and the concurrent coordinator. It does not count toward the 5/20 failure thresholds and is not retried.
9. Remote volume guard: before each job's `prepareAtomicCopy`, `volumeFileSystemID(destinationRoot.path)` must equal `policy.volume.fileSystemID`; otherwise throw `NASRemoteCopyError.destinationVolumeChanged(mountPoint: policy.volume.mountPoint)` (run-fatal) before any directory is created.
10. Remote AppleDouble count: after each successful finalize, if `lstat(<final dir>/._<final name>)` succeeds, increment a run counter. When the run ends with a count > 0, emit one `RunIssue(severity: .info, message: "macOS created <n> hidden ._ metadata files beside copies on the network folder. They aren't photos or videos and aren't counted as copies.")`.

## C-09 Database journal policy — `OrganizerDatabase.swift` changes (WP-07)

```swift
public enum OrganizerJournalPolicy: Sendable, Equatable { case automatic, writeAheadLog, rollbackDelete }
// New init parameter appended with a default; existing call sites compile unchanged:
public init(url: URL, readOnly: Bool = false, journalPolicy: OrganizerJournalPolicy = .automatic) throws
// New error case:
case journalModeUnavailable(String)   // carries the journal_mode SQLite reported
```
`.automatic` → `NASVolumeClassifier.live.classify(url.deletingLastPathComponent())`; `.local` → `.writeAheadLog`, otherwise `.rollbackDelete`. Read-only opens ignore the policy.
`.writeAheadLog` → today's pragma block, byte-identical.
`.rollbackDelete` → `PRAGMA busy_timeout=30000;`, then `PRAGMA journal_mode=DELETE;` and read its single text result: not `"delete"` (case-insensitive) → close and throw `journalModeUnavailable(result)`. Then `PRAGMA synchronous=FULL;` and read back `PRAGMA synchronous;`: not `2` → close and throw `journalModeUnavailable("synchronous=<value>")`. No `wal_autocheckpoint`. Then schema and migrations as today. Never delete `-wal`, `-shm` or `-journal` files.
User-facing message (in `UserFacingErrorMessage`): "Chronoframe couldn't open its copy records on this network folder safely, so it didn't copy anything. Another app or Chronoframe window may be using them. Your originals were untouched."

## C-10 Share lease — `DestinationOperationLock.swift` changes (WP-07)

```swift
public enum NASRemoteLeaseConfiguration {
    /// Set once by the app at launch (NASStartup.configure). Nil in the CLI and in tests unless set.
    public nonisolated(unsafe) static var leaseDirectory: URL?
}
// DestinationOperationLease gains `private var companion: DestinationOperationLease?`;
// release() releases its own descriptor first, then the companion.
// DEBUG seam: `public nonisolated(unsafe) static var volumeClassifierProvider: (@Sendable (URL) -> NASVolumeObservation)?`
// DEBUG seam: `public nonisolated(unsafe) static var shareRootFileIDProvider: (@Sendable (String) -> UInt64?)?`
```
`acquire(destinationRoot:surface:operation:)` only (the `lockFileURL:` overload is unchanged):
1. Classify `destinationRoot`. Kind `.local`, or `leaseDirectory == nil` → today's behavior exactly.
2. Otherwise `shareRootFileID = lstat(volume.mountPoint).st_ino` (via the seam in DEBUG); failure or empty mount point → use 0. `key = NASShareLeaseKey.key(volume:shareRootFileID:)`.
3. `companion = try acquire(lockFileURL: leaseDirectory/"<key>.lock", surface:, operation:)`. A busy companion throws the existing `DestinationBusyError`.
4. Acquire the in-root lock as today. If that throws, release the companion, then rethrow.
5. Attach the companion to the returned lease.
Effect: within one app installation, at most one Chronoframe mutation runs per network share at a time, across mount aliases and parent/child destination folders.

## C-11 CLI refusal — `ChronoframeCLIKit/CLI.swift` changes (WP-08)

- New `CLIError.remoteDestinationUnsupported(path: String)`. Message: "Chronoframe's command-line tool can't write to a network folder in this version: <path>. Use the Chronoframe app for NAS destinations. Nothing was changed." Exit code: the same as other usage errors.
- New `static func remoteDestinationRefusal(destinationPath: String, classifier: NASVolumeClassifier) -> CLIError?` returns the error when `classify(URL(fileURLWithPath:)).kind != .local`.
- DEBUG seam `static var volumeClassifier: NASVolumeClassifier = .live`; release uses `.live`.
- First statements of `run(options:output:input:)`, before revert dispatch, cache rebuild, profile loading for the run, engine creation or any lock: resolve the destination as revert → `options.destinationPath ?? destinationBoundary(for: receiptURL)`; otherwise `options.destinationPath`, else the profile's destination using the same lookup `destinationForCacheRebuild(options:profilesRepository:)` uses. Then throw `remoteDestinationRefusal` if non-nil. A NAS source with a local destination is not refused.

## C-12 App Core services (WP-10)

Files under `ui/Sources/ChronoframeAppCore/`:
- `Support/NASPaths.swift`: `enum NASPaths` with `root` = `RuntimePaths.applicationSupportDirectory()/nas`, `registryURL` = `root/libraries.json`, `libraryDirectory(_ uuid: String)` = `root/libraries/<uuid>`, `assessmentStoreURL(_ uuid:)` = `libraryDirectory/assessment.db`, `leaseDirectory` = `root/leases`, `ensureDirectories(for uuid: String?) throws`.
- `Support/NASStartup.swift`: `enum NASStartup { static func configure() }` sets `NASRemoteLeaseConfiguration.leaseDirectory = NASPaths.leaseDirectory` and creates it (errors ignored; the lease then falls back to in-root only, which is today's behavior). Idempotent.
- `Services/NASLibraryRegistry.swift`: `final class NASLibraryRegistry` with `init(url: URL = NASPaths.registryURL)`, `load() throws -> [NASLibraryRecord]` (missing file → []), `upsert(_:) throws`, `remove(libraryUUID:) throws`. Writes JSON (sorted keys, ISO-8601 dates) through `DestinationMetadataFile.replaceFile(at:writing:)`.
- `Services/NASReconnectProbe.swift`: `enum NASReconnectProbe { static func validatedStartPath(for record: NASLibraryRecord, resolve: @Sendable (FolderBookmark) -> URL?, observe: @Sendable (URL) -> NASLibraryObservation?, timeoutSeconds: Double = 2.0) async -> String? }`. It runs resolve+observe on a detached task and races a sleep; returns the path only if observation arrived in time and `compare` is `.same` or `.remounted`. It never runs on the main actor.
- `Services/FolderAccessService.swift`: add `chooseFolder(startingAt:prompt:allowNetworkStart:)` to `FolderAccessServicing` with a protocol-extension default that forwards to `chooseFolder(startingAt:prompt:)`. `FolderAccessService` implements it; with `allowNetworkStart == true` the non-local-volume fallback in `initialPanelDirectoryURL` is skipped (add `allowNetworkStart: Bool = false` to that static).
- `Services/NASAssessmentEngine.swift`:
```swift
public struct NASAssessmentSnapshot: Sendable, Equatable {
    public var summary: NASScanSummary
    public var groups: [NASExactGroup]
    public var directories: [NASDirectoryRow]
    public var issues: [NASIssue]
    public var choices: [String: NASReviewChoice]
    public var selectedDigest: String?
}
public protocol NASAssessmentEngine: AnyObject, Sendable {
    func assess(_ library: NASLibraryRecord, rootURL: URL) throws -> AsyncThrowingStream<NASAssessmentEvent, Error>
    func cancel()
    func latestSnapshot(for library: NASLibraryRecord) throws -> NASAssessmentSnapshot?
    func saveChoice(_ choice: NASReviewChoice, for library: NASLibraryRecord) throws
    func saveSelectedDigest(_ digest: String?, for library: NASLibraryRecord) throws
    func recordPreviewRequest(for library: NASLibraryRecord) throws
}
public final class SwiftNASAssessmentEngine: NASAssessmentEngine   // owns one NASAssessmentStore per library UUID, opened lazily at NASPaths.assessmentStoreURL
```
- `Stores/NASWorkspaceStore.swift` (`@MainActor final class NASWorkspaceStore: ObservableObject`):
```swift
public enum NASWorkspaceState: Equatable, Sendable {
    case noLibrary
    case checkingConnection
    case needsIdentityConfirmation([NASIdentityMismatchReason])
    case differentFolder([NASIdentityMismatchReason])
    case waitingForNAS
    case ready
    case assessing(NASAssessmentPhase)
    case stopping
    case completeAssessment
    case incompleteAssessment(NASScanOutcome)
    case failed(String)
}
@Published public private(set) var state: NASWorkspaceState
@Published public private(set) var library: NASLibraryRecord?
@Published public private(set) var snapshot: NASAssessmentSnapshot?
@Published public private(set) var progress: (directories: Int, files: Int, hashed: Int, hashTotal: Int, currentRelativePath: String)
@Published public private(set) var previewRequestedDigests: Set<String>
public init(engine: any NASAssessmentEngine, registry: NASLibraryRegistry, folderAccess: any FolderAccessServicing, observe: @escaping @Sendable (URL) -> NASLibraryObservation? = { NASLibraryIdentity.observe(rootURL: $0) }, now: @escaping () -> Date = Date.init)
public func loadSavedLibrary() async          // registry first record → checkingConnection → validate
public func chooseLibrary() async             // picker; non-remote choice → failed(C-13 copy "Choose a folder on a network share…")
public func confirmIdentity() async           // only from needsIdentityConfirmation: accept observation, update record
public func reconnect() async                 // validate again; picker start via NASReconnectProbe
public func startAssessment()                 // only from ready/completeAssessment/incompleteAssessment
public func stop()                            // assessing → stopping; engine.cancel()
public func select(digest: String?)           // persists via engine.saveSelectedDigest; never loads previews
public func chooseKeeper(digest: String, relativePath: String?)   // saves NASReviewChoice; non-mutating
public func requestPreview(digest: String)    // inserts digest, records metric; the only preview trigger
public func isChoiceStale(_ group: NASExactGroup) -> Bool   // choice exists and keeper not in group members
```
Validation (used by load/reconnect): resolve bookmark → URL; nil → `waitingForNAS`. Observe → nil → `waitingForNAS`. `compare`: `.same` → `ready`; `.remounted` → update record observation and `ready`; `.ambiguous` → `needsIdentityConfirmation`; `.mismatch` → `differentFolder` (the only action offered is Choose Folder; a new choice creates a new `libraryUUID`, so no choices carry over). On entering `ready`, load `latestSnapshot`; when the latest summary outcome is `complete` → `completeAssessment`, any other finished outcome → `incompleteAssessment(outcome)`.
Event handling: `.phaseStarted(p)` → `assessing(p)`; `.finished(summary)` → reload snapshot and set complete/incomplete; `interruptedVolumeUnavailable` → `waitingForNAS`; thrown error → `failed(UserFacingErrorMessage text)`.

## C-13 App UI (WP-11)

- `SidebarDestination` (Core `ProfileModels.swift`) gains `case nasLibrary` (raw value "nasLibrary"), title "NAS Library", SF Symbol `externaldrive.connected.to.line.below`. `primaryNavigationCases` appends it after `.deduplicate` only when `NASCapability.isEnabled`. Every `switch` over `SidebarDestination` handles it; `isRunning`-style switches return `nasWorkspaceStore.state` is `.assessing` or `.stopping`.
- `AppState` gains `let nasWorkspaceStore: NASWorkspaceStore` built in both inits with `SwiftNASAssessmentEngine()`, `NASLibraryRegistry()`, and the app's folder-access service; calls `NASStartup.configure()` first in the designated init.
- `RootSplitView.detailView`: `case .nasLibrary: NASLibraryView(appState: appState)` on one line (the navigation-title guard parses it).
- New views in `ui/Sources/ChronoframeApp/Views/NAS/`: `NASLibraryView.swift` (root, `static let navigationTitle = "NAS Library"` and `.navigationTitle(Self.navigationTitle)`), `NASLibraryHeaderView.swift`, `NASFolderSummaryView.swift`, `NASExactGroupListView.swift`, `NASExactGroupDetailView.swift`, `NASPreviewLoader.swift`, `NASAccessibilityText.swift`.
- Layout, top to bottom: header (library name, `serverHost/shareName`, mode badge "Assess only", single-Mac note); state banner (one per `NASWorkspaceState`); folder summary as a collapsed `DisclosureGroup`; then an `HStack` holding a lazy `List` of groups (fixed width 320) on the left and the selected group's detail on the right. Do not nest another `NavigationSplitView`. Lists are `List` or `LazyVStack` only.
- Preview: each group detail shows a placeholder tile and a "Load Preview" button. Only that button calls `nasWorkspaceStore.requestPreview(digest:)`, after which `NASPreviewLoader` renders the group's first member through `ThumbnailRenderer` and caches the image in an `NSCache` keyed by digest (countLimit 128). Selection, scrolling, relaunch and appearance never call the renderer.
- Keeper choice: a `Picker` (radio style) over member paths plus "No choice yet"; caption copy below. No delete, move or Trash control exists anywhere in the NAS workspace.
- Accessibility identifiers (add to `AccessibilityIdentifiers.swift` in an `enum NAS`): `nas.chooseFolder`, `nas.startAssessment`, `nas.stop`, `nas.reconnect`, `nas.confirmIdentity`, `nas.groupList`, `nas.groupRow`, `nas.loadPreview`, `nas.keeperPicker`, `nas.folderSummary`, `nas.stateBanner`.
- Every control has a VoiceOver label from `NASAccessibilityText`. Text uses `.scaledFont`. Animations only through `Motion`.

UI copy (verbatim):

| Key | Text |
|---|---|
| empty.title | Assess a photo library on your NAS |
| empty.body | Choose the top folder of your collection. Chronoframe reads it to find identical copies and changes nothing on the NAS. |
| button.choose | Choose Folder… |
| button.start | Assess Library |
| button.rescan | Assess Again |
| button.stop | Stop |
| button.reconnect | Reconnect |
| button.confirm | This Is the Same Library |
| button.loadPreview | Load Preview |
| badge.mode | Assess only |
| note.singleMac | Use one Mac at a time for Chronoframe changes on this NAS. |
| state.checking | Checking the connection to your NAS… |
| state.waiting | Waiting for your NAS. Reconnect the share, then choose Reconnect. Nothing was changed. |
| state.confirm | This share looks slightly different (for example, a new network name). Confirm it's the same library to keep your saved choices. |
| state.different | This isn't the library you assessed before. Choose the folder again to start a new assessment. |
| state.stopping | Stopping… Chronoframe is finishing the file it's reading. |
| state.complete | Assessment complete. Every included folder was checked. |
| state.incomplete | Assessment incomplete. Some folders or files couldn't be read, so this isn't a full picture. |
| state.cancelled | Assessment stopped. Results so far are saved; assess again to finish. |
| error.notNetwork | Choose a folder on a network share. For folders on this Mac, use Deduplicate. |
| summary.redundant | %@ in identical extra copies (logical size, not space freed) |
| keeper.caption | Your choice is saved on this Mac. Chronoframe doesn't delete or move files on a NAS in this version. |
| keeper.none | No choice yet |
| keeper.stale | Your earlier choice no longer matches these files. Choose again. |
| preview.caption | Loading a preview may read the whole file over the network. |
| issues.title | Not checked |

## C-14 Probe and corpus tool (WP-09)

- Logic in Core: `NASProbe.swift`, `NASCorpusGenerator.swift`, `NASParityCheck.swift`. Thin executable target `ChronoframeNASProbeTool` (`ui/Sources/ChronoframeNASProbeTool/main.swift`, depends on `ChronoframeCore`) added to `ui/Package.swift` products and targets, next to `ChronoframeVideoCalibrationTool`, with a comment "Local only; real-share qualification evidence. Not run in CI."
- Commands (print one JSON document to stdout; human summary to stderr):
  - `probe --test-dir PATH [--trash]`: refuses unless PATH exists, is a directory, and contains nothing except entries named `.chronoframe-nas-probe-*`. Works only in `PATH/.chronoframe-nas-probe-<uuid>/` and removes exactly the files it created, then that directory. Results `{id, status: pass|fail|unsupported|error, errorCode?, detail}` for: P01 volume + library observation; P02 8 MiB write then `F_FULLFSYNC` result and `fsync` result; P03 `renamex_np` RENAME_EXCL onto a new name; P04 RENAME_EXCL onto an existing name must fail with EEXIST and leave the existing bytes' BLAKE2b digest unchanged; P05 readback digest equals the written digest; P06 `OrganizerDatabase(url:journalPolicy: .rollbackDelete)` readbacks plus `sqlite3_libversion()`, whether `sqlite3_compileoption_used("ENABLE_LOCKING_STYLE")` is set, and `SQLITE_FCNTL_VFSNAME`; P07 a writer connection holds `BEGIN IMMEDIATE` for 2 s while a second connection on another thread runs `SELECT count(*)` with busy_timeout 30000 (record elapsed ms and result), then again with busy_timeout 0 (record result code); P08 only with `--trash`: `FileManager.trashItem` on an owned file, record outcome, and if it succeeded verify the digest at the resulting URL and move it back. P08 is P1 evidence.
  - `assess-parity --root PATH --state-dir PATH`: runs `NASAssessmentScanner` with its store in `state-dir` (refuse when state-dir is inside root), then hashes every supported media file with `FileIdentityHasher`, builds exhaustive exact groups, and compares the two group sets as sets of sorted relative-path arrays, ignoring scanner `unresolved` items. Output: summary, ledger, budget, `parity: true|false`, differences, wall seconds, `ru_maxrss`.
  - `make-corpus --dest PATH --manifest PATH --files N --duplicate-percent P --seed S`: refuses a non-empty dest or a manifest inside dest. Writes N files of pseudo-random bytes (seeded `SplitMix64`) named `.jpg`/`.heic`/`.mov` in nested folders, including same-size-different-bytes pairs, cross-folder exact duplicates, zero-byte files, a Unicode/NFD name, and `@eaDir`/`#recycle` containers holding duplicates that must be excluded. The manifest lists every file's relative path, size and digest plus the expected exact groups.
