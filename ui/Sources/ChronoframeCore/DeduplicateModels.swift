import Foundation

// MARK: - Settings presets

/// Three named tradeoffs between scan strictness and recall. The settings UI
/// exposes these as a segmented control instead of two raw numeric sliders.
public enum DedupeSimilarityPreset: String, CaseIterable, Sendable, Codable, Identifiable {
    case strict
    case balanced
    case loose

    public var id: String { rawValue }

    // Outcome-shaped labels: the segments answer "what will I see?", not
    // "how does the matcher behave?" (the old Strict/Balanced/Loose).
    public var title: String {
        switch self {
        case .strict: return "Exact copies"
        case .balanced: return "Balanced"
        case .loose: return "Similar shots"
        }
    }

    public var subtitle: String {
        switch self {
        case .strict: return "Only exact video copies and the closest photo matches"
        case .balanced: return "Recommended for most libraries"
        case .loose: return "Casts a wider net — expect more groups to check"
        }
    }

    public var similarityThreshold: Double {
        switch self {
        case .strict: return 0.20
        case .balanced: return 0.35
        case .loose: return 0.55
        }
    }

    public var dhashHammingThreshold: Int {
        switch self {
        case .strict: return 6
        case .balanced: return 10
        case .loose: return 16
        }
    }

    /// Explicit media × preset behavior. Perceptual video remains opt-in and
    /// participates only in Balanced/Similar Shots; Exact Copies keeps video
    /// matching byte-identical while preserving the existing strict photo lane.
    public var allowsPerceptualVideoMatching: Bool {
        self != .strict
    }

    public var videoPerceptualConfiguration: VideoPerceptualMatchConfiguration {
        switch self {
        case .strict:
            return VideoPerceptualMatchConfiguration(
                durationToleranceSeconds: 0.5,
                frameHammingThreshold: 6,
                aggregateMedianThreshold: 4,
                aspectRatioTolerance: 0.05
            )
        case .balanced:
            return VideoPerceptualMatchConfiguration()
        case .loose:
            return VideoPerceptualMatchConfiguration(
                durationToleranceSeconds: 2.0,
                frameHammingThreshold: 10,
                aggregateMedianThreshold: 8,
                aspectRatioTolerance: 0.12
            )
        }
    }
}

// MARK: - Configuration

// MARK: - Cross-folder source (Feature 5)

public struct CrossFolderSource: Sendable, Equatable, Identifiable, Codable {
    public var id: String { path }
    public var path: String
    /// Lower number = higher priority. Files in higher-priority folders are
    /// preferred as keepers when quality is otherwise equal.
    public var priority: Int
    public var label: String?

    public init(path: String, priority: Int = 0, label: String? = nil) {
        self.path = path
        self.priority = priority
        self.label = label
    }
}

/// Settings that drive a single dedupe scan + commit cycle.
public struct DeduplicateConfiguration: Equatable, Sendable {
    public var destinationPath: String
    /// Photos must be taken within this many seconds of each other to be
    /// considered for the same near-duplicate cluster. Only consulted when
    /// `burstModeEnabled` is true.
    public var timeWindowSeconds: Int
    /// When true, only candidates within `timeWindowSeconds` of each other
    /// are compared (today's behavior — fast, focused on burst sequences).
    /// When false, every candidate in the destination is compared against
    /// every other candidate, ignoring capture-date proximity.
    public var burstModeEnabled: Bool
    /// Vision feature-print distance threshold. Lower = stricter (more similar
    /// required to cluster). VNFeaturePrintObservation distances are
    /// unbounded but typically fall in 0.0–2.0 for natural photos.
    public var similarityThreshold: Double
    /// Pre-filter: dHash Hamming distance. Pairs whose dHash differs by more
    /// than this are rejected before paying for the Vision distance check.
    public var dhashHammingThreshold: Int
    public var treatRawJpegPairsAsUnit: Bool
    public var treatLivePhotoPairsAsUnit: Bool
    public var enableExactDuplicateGroup: Bool
    public var workerCount: Int

    // MARK: Feature flags (Phase 2+)

    /// Automatically accept high-confidence clusters without manual review.
    public var autoAcceptHighConfidence: Bool
    /// Run edit-variant detection on near-duplicate clusters to distinguish
    /// intentional edits (crops, exposure adjustments) from true duplicates.
    public var detectEditVariants: Bool
    /// Additional folders to scan alongside the destination (cross-folder
    /// dedup). Empty by default for single-folder behavior.
    public var additionalSources: [CrossFolderSource]

    /// Opt-in: surface visually-similar (perceptual) video clusters in addition
    /// to byte-identical ones. **Off by default** — this is a separate explicit
    /// option, never inferred from the photo similarity preset. When off, the
    /// scanner does no video decoding at all. Perceptual video clusters are
    /// always review-only (medium-capped, never auto-commit eligible).
    public var perceptualVideoMatchingEnabled: Bool
    /// Thresholds for the perceptual video matcher. Only consulted when
    /// `perceptualVideoMatchingEnabled` is true.
    public var videoPerceptualMatchConfiguration: VideoPerceptualMatchConfiguration

    public init(
        destinationPath: String,
        timeWindowSeconds: Int = 30,
        burstModeEnabled: Bool = true,
        similarityThreshold: Double = 0.35,
        dhashHammingThreshold: Int = 10,
        treatRawJpegPairsAsUnit: Bool = true,
        treatLivePhotoPairsAsUnit: Bool = true,
        enableExactDuplicateGroup: Bool = true,
        workerCount: Int = 4,
        autoAcceptHighConfidence: Bool = false,
        detectEditVariants: Bool = true,
        additionalSources: [CrossFolderSource] = [],
        perceptualVideoMatchingEnabled: Bool = false,
        videoPerceptualMatchConfiguration: VideoPerceptualMatchConfiguration = VideoPerceptualMatchConfiguration()
    ) {
        self.destinationPath = destinationPath
        self.timeWindowSeconds = timeWindowSeconds
        self.burstModeEnabled = burstModeEnabled
        self.similarityThreshold = similarityThreshold
        self.dhashHammingThreshold = dhashHammingThreshold
        self.treatRawJpegPairsAsUnit = treatRawJpegPairsAsUnit
        self.treatLivePhotoPairsAsUnit = treatLivePhotoPairsAsUnit
        self.enableExactDuplicateGroup = enableExactDuplicateGroup
        self.workerCount = workerCount
        self.autoAcceptHighConfidence = autoAcceptHighConfidence
        self.detectEditVariants = detectEditVariants
        self.additionalSources = additionalSources
        self.perceptualVideoMatchingEnabled = perceptualVideoMatchingEnabled
        self.videoPerceptualMatchConfiguration = videoPerceptualMatchConfiguration
    }
}

// MARK: - Phases

public enum DeduplicatePhase: String, CaseIterable, Sendable {
    case discovery
    case identityHashing
    case featureExtraction
    case videoAnalysis
    case clustering

    public var title: String {
        switch self {
        case .discovery: return "Discovering files"
        case .identityHashing: return "Hashing for exact duplicates"
        case .featureExtraction: return "Analyzing photo similarity"
        case .videoAnalysis: return "Analyzing video similarity"
        case .clustering: return "Grouping similar shots"
        }
    }
}

public enum ClusterKind: String, Sendable, Codable {
    /// Byte-identical files (matched via the existing BLAKE2b file identity).
    case exactDuplicate
    /// Visually similar shots that span more than ~10s — same scene, different
    /// composition or lighting.
    case nearDuplicate
    /// Visually similar shots taken within ~10s of each other — likely a
    /// burst sequence.
    case burst
    /// Photos that are intentional edits of each other (crops, exposure
    /// adjustments, filters) rather than accidental duplicates.
    case editedVariant

    public var title: String {
        switch self {
        case .exactDuplicate: return "Exact duplicates"
        case .nearDuplicate: return "Near duplicates"
        case .burst: return "Bursts"
        case .editedVariant: return "Edited variants"
        }
    }
}

// MARK: - Media kind

/// Whether a candidate (and the cluster it forms) is a still photo or a
/// video. Drives the three media-sensitive seams — keeper selection,
/// confidence/auto-commit eligibility, and match-reason presentation —
/// while everything downstream (planner, executor, receipt, revert,
/// history) stays a single pipeline. Defaults to `.photo` so existing
/// call sites and decoded state are unchanged.
public enum MediaKind: String, Sendable, Codable, Equatable, CaseIterable {
    case photo
    case video
}

// MARK: - Photo candidates

/// Per-file analysis output produced by the scanner. Drives both clustering
/// and the keeper-quality scoring shown in the review UI.
public struct PhotoCandidate: Sendable, Identifiable, Equatable {
    public var id: String { path }
    public var path: String
    public var size: Int64
    public var modificationTime: TimeInterval
    public var captureDate: Date?
    public var pixelWidth: Int?
    public var pixelHeight: Int?
    public var dhash: UInt64?
    /// Opaque NSSecureCoding-archived `VNFeaturePrintObservation`. Stored as
    /// raw bytes so the cache layer doesn't drag Vision into ChronoframeCore.
    public var featurePrintData: Data?
    public var qualityScore: Double
    public var sharpness: Double
    public var faceScore: Double?
    public var isRaw: Bool
    public var isLivePhotoStill: Bool
    /// Path of the partner file in a RAW+JPEG or Live Photo pair, if any.
    /// The pair member is always carried alongside this candidate when
    /// keep/delete decisions are committed.
    public var pairedPath: String?
    /// Co-located metadata sidecars (e.g. `.xmp`) that share this photo's
    /// basename. Sidecars are not dedup candidates; they travel with their
    /// parent as a unit and are deleted only when every photo that references
    /// them is also deleted (Keep-wins). Populated fresh each scan, never
    /// cached.
    public var sidecarPaths: [String]

    // MARK: Expression analysis (Phase 1 — Feature 2)

    /// Confidence that all detected faces have open eyes (0-1).
    public var eyesOpenScore: Double?
    /// Confidence that detected faces are smiling (0-1).
    public var smileScore: Double?
    /// Laplacian sharpness within the face bounding box (subject-focused).
    public var subjectSharpness: Double?
    /// Motion blur on the subject (0=sharp, 1=heavy blur).
    public var subjectMotionBlur: Double?

    // MARK: Cross-folder (Phase 3 — Feature 5)

    /// Root folder this candidate was discovered in, for cross-folder dedup.
    public var folderRoot: String?

    /// Whether this candidate is a still photo or a video. Videos are built
    /// through a separate minimal lane that never runs the image analyzer,
    /// so their photo-quality signals (dhash, featurePrintData, sharpness,
    /// faceScore, expression scores) are absent and must never influence
    /// keeper selection or confidence. Defaults to `.photo`.
    public var mediaKind: MediaKind
    /// Video-only keeper signals populated by the perceptual lane. They remain
    /// nil for photos and exact-video candidates.
    public var videoEstimatedDataRate: Double?
    public var videoMetadataCompleteness: Int?

    public init(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        captureDate: Date? = nil,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        dhash: UInt64? = nil,
        featurePrintData: Data? = nil,
        qualityScore: Double = 0,
        sharpness: Double = 0,
        faceScore: Double? = nil,
        isRaw: Bool = false,
        isLivePhotoStill: Bool = false,
        pairedPath: String? = nil,
        eyesOpenScore: Double? = nil,
        smileScore: Double? = nil,
        subjectSharpness: Double? = nil,
        subjectMotionBlur: Double? = nil,
        folderRoot: String? = nil,
        mediaKind: MediaKind = .photo,
        videoEstimatedDataRate: Double? = nil,
        videoMetadataCompleteness: Int? = nil,
        sidecarPaths: [String] = []
    ) {
        self.path = path
        self.size = size
        self.modificationTime = modificationTime
        self.captureDate = captureDate
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dhash = dhash
        self.featurePrintData = featurePrintData
        self.qualityScore = qualityScore
        self.sharpness = sharpness
        self.faceScore = faceScore
        self.isRaw = isRaw
        self.isLivePhotoStill = isLivePhotoStill
        self.pairedPath = pairedPath
        self.eyesOpenScore = eyesOpenScore
        self.smileScore = smileScore
        self.subjectSharpness = subjectSharpness
        self.subjectMotionBlur = subjectMotionBlur
        self.folderRoot = folderRoot
        self.mediaKind = mediaKind
        self.videoEstimatedDataRate = videoEstimatedDataRate
        self.videoMetadataCompleteness = videoMetadataCompleteness
        self.sidecarPaths = sidecarPaths
    }
}

// MARK: - Clusters

public struct DuplicateCluster: Sendable, Identifiable, Equatable {
    public var id: UUID
    public var kind: ClusterKind
    public var members: [PhotoCandidate]
    /// Subset of `members.id` — currently at most one primary suggested
    /// keeper. UI pre-selects it as Keep and pre-marks the rest as Delete,
    /// with pair-as-unit safety applied later by the planner/session store.
    public var suggestedKeeperIDs: [String]
    /// Bytes that would be reclaimed if the user accepts the suggestion
    /// (sum of non-keeper sizes including paired partners).
    public var bytesIfPruned: Int64
    /// Confidence, match reasoning, keeper reasoning, and safety warnings.
    /// `nil` for clusters produced by older scan sessions (backwards-compat).
    public var annotation: ClusterAnnotation?

    public init(
        id: UUID = UUID(),
        kind: ClusterKind,
        members: [PhotoCandidate],
        suggestedKeeperIDs: [String],
        bytesIfPruned: Int64,
        annotation: ClusterAnnotation? = nil
    ) {
        self.id = id
        self.kind = kind
        self.members = members
        self.suggestedKeeperIDs = suggestedKeeperIDs
        self.bytesIfPruned = bytesIfPruned
        self.annotation = annotation
    }
}

// MARK: - Events

public enum DeduplicateEvent: Sendable {
    case startup
    case phaseStarted(phase: DeduplicatePhase, total: Int?)
    case phaseProgress(phase: DeduplicatePhase, completed: Int, total: Int)
    case phaseCompleted(phase: DeduplicatePhase)
    case clusterDiscovered(DuplicateCluster)
    case issue(DeduplicateIssue)
    case complete(DeduplicateSummary)
}

public struct DeduplicateIssue: Sendable, Equatable {
    public enum Severity: String, Sendable, Equatable {
        case info
        case warning
        case error
    }

    public var severity: Severity
    public var path: String?
    public var message: String

    public init(severity: Severity, path: String? = nil, message: String) {
        self.severity = severity
        self.path = path
        self.message = message
    }
}

public struct DeduplicateSummary: Sendable, Equatable {
    public var clusterCounts: [ClusterKind: Int]
    public var totalRecoverableBytes: Int64
    public var totalCandidatesScanned: Int
    public var scanDuration: TimeInterval
    /// Diagnostic snapshot of the feature-extraction cache. Useful to spot
    /// regressions where a code change accidentally invalidates the cache
    /// on every scan, or where a destination's database has lost its
    /// dedupe metadata and is silently re-extracting Vision feature prints.
    public var cacheMetrics: DedupeCacheMetrics
    /// Honest accounting of the perceptual video lane, or `nil` when that lane
    /// did not run (the opt-in flag was off). Lets the UI distinguish "no
    /// similar videos found" from "nothing could be analyzed" from "deferred
    /// pending exact cleanup".
    public var videoPerceptualMetrics: VideoPerceptualAnalysisMetrics?

    public init(
        clusterCounts: [ClusterKind: Int] = [:],
        totalRecoverableBytes: Int64 = 0,
        totalCandidatesScanned: Int = 0,
        scanDuration: TimeInterval = 0,
        cacheMetrics: DedupeCacheMetrics = DedupeCacheMetrics(),
        videoPerceptualMetrics: VideoPerceptualAnalysisMetrics? = nil
    ) {
        self.clusterCounts = clusterCounts
        self.totalRecoverableBytes = totalRecoverableBytes
        self.totalCandidatesScanned = totalCandidatesScanned
        self.scanDuration = scanDuration
        self.cacheMetrics = cacheMetrics
        self.videoPerceptualMetrics = videoPerceptualMetrics
    }
}

/// Per-scan accounting for the opt-in perceptual video lane. Only populated
/// when `perceptualVideoMatchingEnabled` was true. Every candidate video is
/// counted in exactly one of `analyzed`/`unsupported`/`decodeFailed`/
/// `insufficientVisualEvidence`/`prefilteredNoNeighbor`, plus a separate
/// `deferredPendingExactCleanup` tally for videos held out of the lane because
/// they were already members of an exact-duplicate cluster.
public struct VideoPerceptualAnalysisMetrics: Sendable, Equatable {
    /// Videos that decoded to `.ready` features (eligible to cluster).
    public var analyzed: Int
    /// Containers AVFoundation could not open / had no usable video track.
    public var unsupported: Int
    /// Videos whose frames could not be decoded at all.
    public var decodeFailed: Int
    /// Videos that decoded but yielded too few informative frames.
    public var insufficientVisualEvidence: Int
    /// Videos whose metadata had no plausible duration/aspect neighbor. These
    /// are intentionally not frame-decoded on a cold scan.
    public var prefilteredNoNeighbor: Int
    /// Videos excluded from the perceptual lane because they were already in an
    /// exact-duplicate cluster (exact wins; they resurface only after the user
    /// cleans exacts and rescans).
    public var deferredPendingExactCleanup: Int
    /// Feature-cache hits/misses for the video lane (a hit reuses a cached
    /// `DedupeVideoFeatures` row; a miss performs a metadata probe and only
    /// decodes frames when the prefilter finds a plausible neighbor).
    public var cacheHits: Int
    public var cacheMisses: Int

    public init(
        analyzed: Int = 0,
        unsupported: Int = 0,
        decodeFailed: Int = 0,
        insufficientVisualEvidence: Int = 0,
        prefilteredNoNeighbor: Int = 0,
        deferredPendingExactCleanup: Int = 0,
        cacheHits: Int = 0,
        cacheMisses: Int = 0
    ) {
        self.analyzed = analyzed
        self.unsupported = unsupported
        self.decodeFailed = decodeFailed
        self.insufficientVisualEvidence = insufficientVisualEvidence
        self.prefilteredNoNeighbor = prefilteredNoNeighbor
        self.deferredPendingExactCleanup = deferredPendingExactCleanup
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
    }

    /// Total videos that went through the decode/cache path (excludes the
    /// exact-deferred set, which is never decoded).
    public var totalConsidered: Int {
        analyzed + unsupported + decodeFailed + insufficientVisualEvidence + prefilteredNoNeighbor
    }
}

/// Snapshot of the cache's behaviour across one scan.
/// Cache metrics describe expensive analysis work, not discovery totals.
/// For photos, a miss incurs a Vision feature print + dHash + quality score
/// computation and a hit reads the prior row from the DedupeFeatures table.
/// For videos, the counts cover identity hashing of the size-collision groups
/// only (a hit reuses a FileCache row, a miss re-hashes); size-unique videos
/// are skipped by the size prefilter and therefore excluded from cache counts,
/// while still contributing to `DeduplicateSummary.totalCandidatesScanned`.
public struct DedupeCacheMetrics: Sendable, Equatable {
    public var hits: Int
    public var misses: Int

    public init(hits: Int = 0, misses: Int = 0) {
        self.hits = hits
        self.misses = misses
    }

    /// Fraction of considered files served from cache. Returns 0 when no
    /// files were considered so callers can render the value safely.
    public var hitRate: Double {
        let total = hits + misses
        guard total > 0 else { return 0 }
        return Double(hits) / Double(total)
    }
}

// MARK: - Decisions and commit

public enum DedupeDecision: String, Sendable, Codable {
    case keep
    case delete
}

/// User-supplied keep/delete map handed to the executor at commit time.
public struct DedupeDecisions: Sendable, Equatable {
    public var byPath: [String: DedupeDecision]
    /// Retained for backward-compatible decoding and older tests. Production
    /// commits always move files to the macOS Trash.
    public var hardDelete: Bool
    /// Paths the user explicitly wants preserved that are **not** members of
    /// any duplicate cluster. The common case is a Live Photo MOV partner
    /// whose paired HEIC is in a cluster but whose own MOV file is not. Step
    /// 5 of `DeduplicationPlanner.plan` (pair expansion) consults this set
    /// before fanning out a delete to such partners, so the user can keep a
    /// singleton partner even when its cluster sibling is being deleted.
    public var pairKeepOverrides: Set<String>

    public init(
        byPath: [String: DedupeDecision] = [:],
        hardDelete: Bool = false,
        pairKeepOverrides: Set<String> = []
    ) {
        self.byPath = byPath
        self.hardDelete = false
        self.pairKeepOverrides = pairKeepOverrides
    }

    public func decision(for path: String) -> DedupeDecision? {
        byPath[path]
    }
}

public enum DeduplicateCommitEvent: Sendable {
    case started(totalToDelete: Int)
    case itemTrashed(originalPath: String, trashURL: URL?, sizeBytes: Int64)
    case itemFailed(originalPath: String, errorMessage: String)
    /// The file WAS moved to Trash, but the per-item receipt update
    /// failed (e.g., logs directory became unwritable mid-run). The
    /// file is in Trash; the on-disk receipt is now stale relative to
    /// reality. Distinct from `itemFailed` so UI listeners don't
    /// render this as "this file failed" — that's a false negative.
    /// Phase 1 finding #7.
    case itemTrashedReceiptStale(originalPath: String, trashURL: URL?, sizeBytes: Int64, errorMessage: String)
    /// Receipt could not be finalized at end-of-run. Distinct from
    /// `itemFailed` (which used to be emitted with `originalPath: ""`)
    /// so consumers don't render a ghost row for an empty path.
    case criticalReceiptFailure(errorMessage: String)
    case complete(DeduplicateCommitSummary)
}

public struct DeduplicateCommitSummary: Sendable, Equatable {
    public var deletedCount: Int
    public var failedCount: Int
    public var bytesReclaimed: Int64
    public var receiptPath: String?
    public var hardDelete: Bool

    public init(
        deletedCount: Int,
        failedCount: Int,
        bytesReclaimed: Int64,
        receiptPath: String?,
        hardDelete: Bool
    ) {
        self.deletedCount = deletedCount
        self.failedCount = failedCount
        self.bytesReclaimed = bytesReclaimed
        self.receiptPath = receiptPath
        self.hardDelete = hardDelete
    }
}

// MARK: - Deletion plan

/// Explicit, fully-resolved description of every filesystem mutation the
/// executor will perform. Built once by `DeduplicationPlanner.plan` and
/// consumed by both the commit footer (so previewed counts/bytes match
/// reality) and the executor (so the audit receipt records every mutation
/// — including paired partners that aren't cluster members on their own,
/// like Live Photo MOV halves).
public struct DeduplicationPlan: Sendable, Equatable {
    public enum PairOrigin: String, Sendable, Codable, Equatable {
        case rawJpeg
        case livePhoto
        /// A metadata sidecar pulled in alongside its parent photo's deletion.
        case sidecar
    }

    public struct Item: Sendable, Equatable {
        public let path: String
        public let sizeBytes: Int64
        public let owningClusterID: UUID
        public let owningClusterKind: ClusterKind
        /// `nil` for direct cluster-member deletions; otherwise the kind of
        /// pair-as-unit expansion that pulled this path into the plan.
        public let pairOrigin: PairOrigin?
        /// Whether the deleted file is a photo or a video. Carried through to
        /// the audit receipt so Run History can render the right preview and
        /// so revert never has to re-classify by extension. Defaults to
        /// `.photo` for existing call sites.
        public let mediaKind: MediaKind

        public init(
            path: String,
            sizeBytes: Int64,
            owningClusterID: UUID,
            owningClusterKind: ClusterKind,
            pairOrigin: PairOrigin? = nil,
            mediaKind: MediaKind = .photo
        ) {
            self.path = path
            self.sizeBytes = sizeBytes
            self.owningClusterID = owningClusterID
            self.owningClusterKind = owningClusterKind
            self.pairOrigin = pairOrigin
            self.mediaKind = mediaKind
        }
    }

    public let items: [Item]

    public init(items: [Item]) {
        self.items = items
    }

    public var pathsToDelete: [String] { items.map(\.path) }
    public var totalBytes: Int64 { items.reduce(0) { $0 + $1.sizeBytes } }
    public var count: Int { items.count }
}

// MARK: - Receipt-local tolerant enums

/// Tolerant, receipt-local copy of `ClusterKind`. The receipt is a durable
/// artifact that an *older* build may have to decode for revert. If a newer
/// build introduces a cluster classification this build doesn't know, revert
/// must still succeed — so unknown raw values decode to `.unknown(raw)`
/// rather than throwing. Deliberately decoupled from the domain `ClusterKind`
/// so adding a display-only classification can never break revert.
public enum ReceiptClusterKind: Sendable, Equatable, Codable {
    case exactDuplicate
    case nearDuplicate
    case burst
    case editedVariant
    case unknown(String)

    public init(_ kind: ClusterKind) {
        switch kind {
        case .exactDuplicate: self = .exactDuplicate
        case .nearDuplicate: self = .nearDuplicate
        case .burst: self = .burst
        case .editedVariant: self = .editedVariant
        }
    }

    public var rawValue: String {
        switch self {
        case .exactDuplicate: return "exactDuplicate"
        case .nearDuplicate: return "nearDuplicate"
        case .burst: return "burst"
        case .editedVariant: return "editedVariant"
        case let .unknown(raw): return raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "exactDuplicate": self = .exactDuplicate
        case "nearDuplicate": self = .nearDuplicate
        case "burst": self = .burst
        case "editedVariant": self = .editedVariant
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Tolerant, receipt-local copy of `MediaKind`. Same rationale as
/// `ReceiptClusterKind`: an unknown future media classification must not
/// break an older build's revert.
public enum ReceiptMediaKind: Sendable, Equatable, Codable {
    case photo
    case video
    case unknown(String)

    public init(_ kind: MediaKind) {
        switch kind {
        case .photo: self = .photo
        case .video: self = .video
        }
    }

    public var rawValue: String {
        switch self {
        case .photo: return "photo"
        case .video: return "video"
        case let .unknown(raw): return raw
        }
    }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "photo": self = .photo
        case "video": self = .video
        default: self = .unknown(raw)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Audit receipt (revertible)

public struct DeduplicateAuditReceipt: Codable, Sendable, Equatable {
    public enum Method: String, Codable, Sendable, Equatable {
        case trash
        case hardDelete
    }

    public struct Item: Codable, Sendable, Equatable {
        public var originalPath: String
        public var sizeBytes: Int64
        public var trashURL: String?
        public var method: Method
        public var clusterID: UUID
        public var clusterKind: ReceiptClusterKind
        /// Whether the trashed file was a photo or a video. Absent in
        /// schema ≤3 receipts (decodes to `nil`); always present from v4.
        public var mediaKind: ReceiptMediaKind?

        public init(
            originalPath: String,
            sizeBytes: Int64,
            trashURL: String?,
            method: Method,
            clusterID: UUID,
            clusterKind: ReceiptClusterKind,
            mediaKind: ReceiptMediaKind? = nil
        ) {
            self.originalPath = originalPath
            self.sizeBytes = sizeBytes
            self.trashURL = trashURL
            self.method = method
            self.clusterID = clusterID
            self.clusterKind = clusterKind
            self.mediaKind = mediaKind
        }
    }

    public var kind: String
    public var schemaVersion: Int
    public var runID: UUID
    public var operation: String
    public var status: String
    public var createdAt: Date
    public var finishedAt: Date?
    public var destinationRoot: String
    /// Phase 1 finding #8: when the scan ran with `additionalSources`,
    /// some items in `items` will have `originalPath` outside
    /// `destinationRoot`. Persist the additional root paths so revert
    /// can accept any of them as a valid containment boundary.
    /// Optional / absent in legacy (v2 and earlier) receipts.
    public var additionalSourceRoots: [String]
    public var items: [Item]
    public var bytesReclaimed: Int64
    public var abortReason: String?

    private enum CodingKeys: String, CodingKey {
        case kind
        case schemaVersion
        case runID
        case operation
        case status
        case createdAt
        case finishedAt
        case destinationRoot
        case additionalSourceRoots
        case items
        case bytesReclaimed
        case abortReason
    }

    public init(
        schemaVersion: Int = 4,
        runID: UUID = UUID(),
        operation: String = "deduplicate",
        status: String = "PENDING",
        createdAt: Date,
        finishedAt: Date? = nil,
        destinationRoot: String,
        additionalSourceRoots: [String] = [],
        items: [Item],
        bytesReclaimed: Int64,
        abortReason: String? = nil
    ) {
        self.kind = "dedupe"
        self.schemaVersion = schemaVersion
        self.runID = runID
        self.operation = operation
        self.status = status
        self.createdAt = createdAt
        self.finishedAt = finishedAt
        self.destinationRoot = destinationRoot
        self.additionalSourceRoots = additionalSourceRoots
        self.items = items
        self.bytesReclaimed = bytesReclaimed
        self.abortReason = abortReason
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.kind = try container.decodeIfPresent(String.self, forKey: .kind) ?? "dedupe"
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.runID = try container.decodeIfPresent(UUID.self, forKey: .runID) ?? UUID()
        self.operation = try container.decodeIfPresent(String.self, forKey: .operation) ?? "deduplicate"
        self.status = try container.decodeIfPresent(String.self, forKey: .status) ?? "COMPLETED"
        self.createdAt = try container.decode(Date.self, forKey: .createdAt)
        self.finishedAt = try container.decodeIfPresent(Date.self, forKey: .finishedAt)
        self.destinationRoot = try container.decode(String.self, forKey: .destinationRoot)
        self.additionalSourceRoots = try container.decodeIfPresent([String].self, forKey: .additionalSourceRoots) ?? []
        self.items = try container.decodeIfPresent([Item].self, forKey: .items) ?? []
        self.bytesReclaimed = try container.decodeIfPresent(Int64.self, forKey: .bytesReclaimed) ?? 0
        self.abortReason = try container.decodeIfPresent(String.self, forKey: .abortReason)
    }
}
