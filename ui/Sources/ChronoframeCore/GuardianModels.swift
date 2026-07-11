import Foundation

// MARK: - Library Guardian domain models (Phase 0)
//
// Library Guardian protects an organized library after it is built: it keeps a
// trusted manifest of known-good digests (bit-rot detection), maintains a
// verified mirror, and can restore a damaged file from that mirror.
//
// The load-bearing rule that every type here serves:
//
//   Guardian never creates or advances trust automatically from an unexplained
//   filesystem change, never replaces either copy unless the other copy verifies
//   against an already-trusted identity, and never propagates a deletion without
//   retaining a recoverable copy.
//
// These are pure value types with no I/O. The I/O collector (`GuardianLibraryProbe`)
// and the deterministic classifier (`GuardianIntegrityClassifier`) build on them in
// later phases.

/// Schema, digest-algorithm, and canonicalization versioning for the manifest.
/// A manifest whose algorithm or format version is unknown is quarantined — never
/// silently reinterpreted with today's rules.
public enum GuardianManifestVersion {
    /// Storage schema version; bump with a forward migration when the on-disk
    /// manifest layout changes.
    public static let schema = 1
    /// Digest algorithm identifier recorded alongside every entry.
    public static let digestAlgorithm = "blake2b"
    /// Digest-format version (hex-string encoding of the BLAKE2b digest).
    public static let digestFormatVersion = 1
    /// Relative-path canonicalization identifier (Unicode NFC keys).
    public static let pathNormalization = "nfc"
}

/// A manifest entry's trust state. Never auto-promoted by an unexplained change.
public enum GuardianTrustState: String, Codable, Sendable, CaseIterable {
    /// First observed with no provenance. Not treated as known-good; corruption
    /// that predates Guardian is never blessed. Needs explicit acceptance to
    /// become `trusted`.
    case unprotected
    /// Known-good: reached only via explicit user acceptance or derived provenance
    /// (digest matches a verified Chronoframe transfer for that path).
    case trusted
    /// A `trusted` entry whose current digest differs (whether or not mtime
    /// advanced). Never auto-rebaselines — the user decides accept-new vs restore.
    case changedPendingReview
    /// Deletion explicitly acknowledged by the user.
    case retired
}

/// How an entry earned `trusted`. Absent for `unprotected`/`changedPendingReview`.
public enum GuardianTrustProvenance: String, Codable, Sendable {
    /// The user explicitly accepted the current digest as known-good.
    case userAccepted
    /// The digest matched a verified Chronoframe transfer/import/dedupe receipt.
    case verifiedTransfer
}

/// Per-file result of an integrity scan. `corrupt` vs `modified` is a UI hint only:
/// both indicate a `trusted` digest no longer matches and neither advances trust.
public enum GuardianIntegrityStatus: String, Codable, Sendable, CaseIterable {
    /// Current digest equals the trusted digest.
    case verified
    /// Size and mtime unchanged but the digest differs — silent bit rot.
    case corrupt
    /// mtime advanced and the digest differs — looks like an edit, still reviewed.
    case modified
    /// Present in the manifest, absent on disk.
    case missing
    /// On disk, not in the manifest (or `unprotected`) — not yet known-good.
    case new
    /// iCloud-evicted / dataless: skipped, not corruption.
    case dataless
    /// Could not be read/hashed this scan.
    case unreadable
    /// Size or mtime changed between stat and end-of-hash — reported conservatively,
    /// never as corruption.
    case changedDuringScan
}

/// Stable identity of a protected library: a Guardian-issued UUID plus the volume
/// identifier it was last seen on. Guardian state is keyed by the UUID so it lives
/// in Application Support and never has to be written into a read-only library.
public struct GuardianLibraryIdentity: Equatable, Codable, Sendable {
    public var libraryUUID: String
    public var volumeIdentifier: String?

    public init(libraryUUID: String, volumeIdentifier: String? = nil) {
        self.libraryUUID = libraryUUID
        self.volumeIdentifier = volumeIdentifier
    }
}

/// A trusted-baseline record for one file, keyed by canonical relative path.
public struct GuardianManifestEntry: Equatable, Codable, Sendable {
    /// Canonical (NFC-normalized) path relative to the library root.
    public var relativePath: String
    public var size: Int64
    public var modificationTime: TimeInterval
    /// BLAKE2b digest (hex).
    public var digest: String
    public var trustState: GuardianTrustState
    public var provenance: GuardianTrustProvenance?
    public var firstObservedAt: Date
    public var lastVerifiedAt: Date?

    public init(
        relativePath: String,
        size: Int64,
        modificationTime: TimeInterval,
        digest: String,
        trustState: GuardianTrustState,
        provenance: GuardianTrustProvenance? = nil,
        firstObservedAt: Date,
        lastVerifiedAt: Date? = nil
    ) {
        self.relativePath = relativePath
        self.size = size
        self.modificationTime = modificationTime
        self.digest = digest
        self.trustState = trustState
        self.provenance = provenance
        self.firstObservedAt = firstObservedAt
        self.lastVerifiedAt = lastVerifiedAt
    }

    /// The recorded content identity (size + digest) for verification comparisons.
    public var identity: FileIdentity {
        FileIdentity(size: size, digest: digest)
    }
}

/// Outcome of probing a single file on disk (I/O layer, Phase 1).
public enum GuardianProbeOutcome: String, Codable, Sendable {
    /// Read and hashed successfully.
    case hashed
    /// iCloud-evicted / dataless — no bytes to hash.
    case dataless
    /// Could not be opened or read.
    case unreadable
    /// Size or mtime changed while hashing — do not trust this reading.
    case changedDuringScan
}

/// A raw, deterministic observation of one file, produced by the I/O collector and
/// consumed by the pure classifier. Separating this from the classifier keeps the
/// classification logic pure and unit-testable.
public struct GuardianFileObservation: Equatable, Sendable {
    public var relativePath: String
    public var size: Int64
    public var modificationTime: TimeInterval
    /// BLAKE2b digest, or nil when `outcome` is not `.hashed`.
    public var digest: String?
    public var outcome: GuardianProbeOutcome

    public init(
        relativePath: String,
        size: Int64,
        modificationTime: TimeInterval,
        digest: String?,
        outcome: GuardianProbeOutcome
    ) {
        self.relativePath = relativePath
        self.size = size
        self.modificationTime = modificationTime
        self.digest = digest
        self.outcome = outcome
    }
}

/// One classified finding in an integrity report.
public struct GuardianIntegrityFinding: Equatable, Codable, Sendable {
    public var relativePath: String
    public var status: GuardianIntegrityStatus
    public var trustState: GuardianTrustState
    /// Identity recorded in the manifest (nil for genuinely new files).
    public var expectedIdentity: FileIdentity?
    /// Identity observed on disk this scan (nil for missing/dataless/unreadable).
    public var observedIdentity: FileIdentity?
    /// Modification time observed on disk this scan (nil when not hashed). Carried so
    /// the manifest updater can persist a new/unprotected entry without re-reading disk.
    public var observedModificationTime: TimeInterval?

    public init(
        relativePath: String,
        status: GuardianIntegrityStatus,
        trustState: GuardianTrustState,
        expectedIdentity: FileIdentity? = nil,
        observedIdentity: FileIdentity? = nil,
        observedModificationTime: TimeInterval? = nil
    ) {
        self.relativePath = relativePath
        self.status = status
        self.trustState = trustState
        self.expectedIdentity = expectedIdentity
        self.observedIdentity = observedIdentity
        self.observedModificationTime = observedModificationTime
    }
}

/// Immutable result of one integrity scan. `partialScan` is set when any subtree
/// could not be fully read, in which case counts are conservative and no trust
/// state is advanced from this scan.
public struct GuardianIntegrityReport: Equatable, Codable, Sendable {
    public var generatedAt: Date
    public var libraryRoot: String
    public var findings: [GuardianIntegrityFinding]
    public var partialScan: Bool

    public init(
        generatedAt: Date = Date(),
        libraryRoot: String,
        findings: [GuardianIntegrityFinding],
        partialScan: Bool = false
    ) {
        self.generatedAt = generatedAt
        self.libraryRoot = libraryRoot
        self.findings = findings
        self.partialScan = partialScan
    }

    public func count(of status: GuardianIntegrityStatus) -> Int {
        findings.reduce(0) { $0 + ($1.status == status ? 1 : 0) }
    }

    /// Corrupt (silent bit rot) is the highest-signal outcome.
    public var hasCorruption: Bool {
        findings.contains { $0.status == .corrupt }
    }
}

/// Canonicalization for manifest keys and relative-path derivation. Keys use
/// Unicode NFC so the same filename typed or produced two ways maps to one entry;
/// the on-disk name is never rewritten.
public enum GuardianPathNormalization {
    /// NFC-normalized manifest key for a relative path.
    public static func canonicalKey(_ relativePath: String) -> String {
        relativePath.precomposedStringWithCanonicalMapping
    }

    /// Canonical relative path of `fileURL` under `root`, or nil if `fileURL` is not
    /// inside `root`. Both are standardized before comparison so `.`/`..`/trailing
    /// slashes do not defeat the prefix check.
    public static func relativeKey(of fileURL: URL, underRoot root: URL) -> String? {
        let rootComponents = root.standardizedFileURL.pathComponents
        let fileComponents = fileURL.standardizedFileURL.pathComponents
        guard fileComponents.count > rootComponents.count else { return nil }
        guard Array(fileComponents.prefix(rootComponents.count)) == rootComponents else {
            return nil
        }
        let relativeComponents = fileComponents.dropFirst(rootComponents.count)
        return canonicalKey(relativeComponents.joined(separator: "/"))
    }
}
