import Foundation

// MARK: - Analysis versioning

/// Versioned constants for the perceptual video pipeline. Bumping either
/// version invalidates cached `DedupeVideoFeatures` rows (Milestone 2b), so a
/// change to how frames are sampled or hashed deliberately forces re-analysis.
public enum VideoPerceptualAnalysis {
    /// Bumped when the frame hashing / decode path changes.
    public static let analyzerVersion = 1
    /// Bumped when the sampled timestamps change.
    public static let sampleStrategyVersion = 1
    /// Interior, transform-corrected sample positions as fractions of duration.
    /// Interior-biased (no 0% / 100%) to avoid intro/outro black frames; see
    /// the low-variance discard in the extractor (Milestone 2b).
    public static let sampleFractions: [Double] = [0.15, 0.325, 0.50, 0.675, 0.85]
    /// Minimum number of usable (informative, aligned) frame pairs required to
    /// make a perceptual decision. Below this a video is `insufficientVisualEvidence`.
    public static let minimumUsableSamples = 3
}

// MARK: - Decode status

/// Four-state outcome of analyzing a video for perceptual matching, cached so
/// a video is not re-decoded every scan. `insufficientVisualEvidence` is
/// distinct from `decodeFailed`: the file opened fine but did not yield enough
/// informative frames (e.g. a short or near-uniform clip), and retrying is just
/// as expensive — so it is cached and skipped until the file or an analyzer/
/// sample-strategy version changes.
public enum VideoDecodeStatus: String, Sendable, Equatable, Codable {
    case ready
    case unsupported
    case decodeFailed
    case insufficientVisualEvidence
}

// MARK: - Per-video features

/// Precomputed perceptual signal for one video. In Milestone 2a this is
/// supplied directly (and synthesized in tests); Milestone 2b populates it from
/// AVFoundation and persists it to `DedupeVideoFeatures`. The matcher is pure
/// over these features so it can be unit-tested deterministically with no
/// decoding.
public struct VideoPerceptualFeatures: Sendable, Equatable {
    public var path: String
    public var size: Int64
    public var modificationTime: TimeInterval
    public var durationSeconds: Double
    /// Display dimensions after `preferredTransform` (so a rotation-flagged copy
    /// and a baked-in-rotation copy compare equal).
    public var transformedWidth: Int
    public var transformedHeight: Int
    /// Per-frame dHashes for the usable, informative sampled frames, in sample
    /// order. Only meaningful when `status == .ready`.
    public var frameHashes: [UInt64]
    public var status: VideoDecodeStatus
    public var folderRoot: String?

    public init(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        durationSeconds: Double,
        transformedWidth: Int,
        transformedHeight: Int,
        frameHashes: [UInt64],
        status: VideoDecodeStatus,
        folderRoot: String? = nil
    ) {
        self.path = path
        self.size = size
        self.modificationTime = modificationTime
        self.durationSeconds = durationSeconds
        self.transformedWidth = transformedWidth
        self.transformedHeight = transformedHeight
        self.frameHashes = frameHashes
        self.status = status
        self.folderRoot = folderRoot
    }

    /// Display aspect ratio (width / height) after the preferred transform.
    /// Used to reject orientation/aspect-incompatible pairs while still
    /// allowing pure resolution changes (a 4K vs 1080p copy of the same clip).
    public var aspectRatio: Double {
        guard transformedHeight > 0 else { return 0 }
        return Double(transformedWidth) / Double(transformedHeight)
    }
}

// MARK: - Configuration

/// Thresholds for perceptual video matching. Defaults are conservative
/// (precision-first); the real operating point is calibrated against a labeled
/// corpus in Milestone 2c. Duration is a *prefilter only* — never confidence
/// evidence.
public struct VideoPerceptualMatchConfiguration: Sendable, Equatable {
    /// ±T duration window (seconds) for the sliding-neighbor sweep. A pair is
    /// only considered if their durations are within this tolerance.
    public var durationToleranceSeconds: Double
    /// Per-frame dHash Hamming distance under which a frame pair "agrees".
    public var frameHammingThreshold: Int
    /// Upper bound on the *median* per-frame Hamming distance for a match.
    public var aggregateMedianThreshold: Int
    /// Maximum relative aspect-ratio difference for two videos to be comparable
    /// (orientation/aspect reject). Resolution differences are still allowed.
    public var aspectRatioTolerance: Double
    /// Cheap anchor pre-check: if the first usable frame pair already differs by
    /// more than this, skip the full agreement computation (reject clear
    /// non-matches immediately).
    public var anchorHammingThreshold: Int

    public init(
        durationToleranceSeconds: Double = 1.0,
        frameHammingThreshold: Int = 8,
        aggregateMedianThreshold: Int = 6,
        aspectRatioTolerance: Double = 0.10,
        anchorHammingThreshold: Int = 12
    ) {
        self.durationToleranceSeconds = durationToleranceSeconds
        self.frameHammingThreshold = frameHammingThreshold
        self.aggregateMedianThreshold = aggregateMedianThreshold
        self.aspectRatioTolerance = aspectRatioTolerance
        self.anchorHammingThreshold = anchorHammingThreshold
    }
}

// MARK: - Pairwise comparison

/// Outcome of comparing two videos' frame signatures. Pure and deterministic.
public struct VideoFrameComparison: Sendable, Equatable {
    public var usableSamples: Int
    public var agreeingSamples: Int
    public var medianHammingDistance: Int
    public var isMatch: Bool
}

// MARK: - Matcher

/// Pure perceptual video clusterer. Sorts candidates by duration, sweeps a
/// sliding ±T neighbor window (not discrete buckets — so copies whose durations
/// straddle a boundary still compare), rejects orientation/aspect-incompatible
/// pairs, and forms clusters from frame-hash agreement. Emits regular
/// `DuplicateCluster`s (kind `.nearDuplicate`, video members) capped at medium
/// confidence so they are always review-only.
public enum VideoPerceptualMatcher {

    /// Compare two videos' frame signatures. Frames are aligned by index (the
    /// sampling strategy is shared, so frame *i* corresponds), over the common
    /// prefix length. Returns `nil` when there are too few usable aligned pairs
    /// to decide.
    public static func compareFrames(
        _ lhs: [UInt64],
        _ rhs: [UInt64],
        configuration: VideoPerceptualMatchConfiguration
    ) -> VideoFrameComparison? {
        let count = min(lhs.count, rhs.count)
        guard count >= VideoPerceptualAnalysis.minimumUsableSamples else { return nil }

        // Cheap anchor reject before computing the full distribution.
        if PerceptualHash.hammingDistance(lhs[0], rhs[0]) > configuration.anchorHammingThreshold {
            return VideoFrameComparison(
                usableSamples: count,
                agreeingSamples: 0,
                medianHammingDistance: configuration.anchorHammingThreshold + 1,
                isMatch: false
            )
        }

        var distances: [Int] = []
        distances.reserveCapacity(count)
        var agreeing = 0
        for i in 0..<count {
            let d = PerceptualHash.hammingDistance(lhs[i], rhs[i])
            distances.append(d)
            if d <= configuration.frameHammingThreshold { agreeing += 1 }
        }

        let median = medianOf(distances)
        // Match rule: at least max(3, N-1) frame pairs agree AND the median
        // distance is under the aggregate threshold. Requiring N-1 means at
        // most one outlier frame (a fade, a burned-in timestamp) is tolerated.
        let required = max(VideoPerceptualAnalysis.minimumUsableSamples, count - 1)
        let isMatch = agreeing >= required && median <= configuration.aggregateMedianThreshold

        return VideoFrameComparison(
            usableSamples: count,
            agreeingSamples: agreeing,
            medianHammingDistance: median,
            isMatch: isMatch
        )
    }

    /// Cluster `.ready` video features into perceptual `DuplicateCluster`s.
    /// Non-`.ready` features are ignored (exact matching and the four-state
    /// cache handle them elsewhere).
    public static func cluster(
        features: [VideoPerceptualFeatures],
        configuration: VideoPerceptualMatchConfiguration = VideoPerceptualMatchConfiguration(),
        folderPriority: [String: Int] = [:]
    ) -> [DuplicateCluster] {
        let ready = features
            .filter { $0.status == .ready && $0.frameHashes.count >= VideoPerceptualAnalysis.minimumUsableSamples }
            .sorted { lhs, rhs in
                if lhs.durationSeconds != rhs.durationSeconds { return lhs.durationSeconds < rhs.durationSeconds }
                return lhs.path < rhs.path
            }
        guard ready.count > 1 else { return [] }

        var unionFind = VideoUnionFind(count: ready.count)
        // Each matching pair's comparison, kept with its endpoints so the
        // cluster annotation can reflect the strongest evidence in *its* own
        // component (not a global best).
        var rawMatches: [(i: Int, j: Int, comparison: VideoFrameComparison)] = []

        for i in 0..<ready.count {
            let a = ready[i]
            var j = i + 1
            // Sliding duration window: stop as soon as the neighbor is more than
            // T longer (the array is duration-sorted).
            while j < ready.count, ready[j].durationSeconds - a.durationSeconds <= configuration.durationToleranceSeconds {
                let b = ready[j]
                defer { j += 1 }

                // Orientation / aspect reject (resolution differences allowed).
                if !aspectCompatible(a, b, tolerance: configuration.aspectRatioTolerance) { continue }

                guard let comparison = compareFrames(a.frameHashes, b.frameHashes, configuration: configuration),
                      comparison.isMatch else { continue }

                unionFind.union(i, j)
                rawMatches.append((i: i, j: j, comparison: comparison))
            }
        }

        // Strongest (lowest-median) comparison per component root.
        var bestByRoot: [Int: VideoFrameComparison] = [:]
        for match in rawMatches {
            let root = unionFind.find(match.i)
            if let existing = bestByRoot[root], existing.medianHammingDistance <= match.comparison.medianHammingDistance {
                continue
            }
            bestByRoot[root] = match.comparison
        }

        // Group indices by component root.
        var componentMembers: [Int: [Int]] = [:]
        for index in 0..<ready.count {
            componentMembers[unionFind.find(index), default: []].append(index)
        }

        var clusters: [DuplicateCluster] = []
        for (root, indices) in componentMembers where indices.count > 1 {
            let featureMembers = indices.map { ready[$0] }
            let members = featureMembers.map(makeCandidate)
            let suggested = DuplicateClusterer.suggestKeeperIDs(for: members, folderPriority: folderPriority)

            // Evidence: best (lowest-median) agreeing comparison within this
            // component, plus the duration span across its members.
            let best = bestByRoot[root]
            let durations = featureMembers.map(\.durationSeconds)
            let durationDelta = (durations.max() ?? 0) - (durations.min() ?? 0)

            let evidence = VideoMatchEvidence(
                usableSamples: best?.usableSamples ?? VideoPerceptualAnalysis.minimumUsableSamples,
                agreeingSamples: best?.agreeingSamples ?? 0,
                medianHammingDistance: best?.medianHammingDistance ?? configuration.aggregateMedianThreshold,
                durationDeltaSeconds: durationDelta,
                visionCorroborated: false
            )
            let bytes = DuplicateClusterer.bytesIfPruned(members: members, keeperIDs: Set(suggested))

            var cluster = DuplicateCluster(
                kind: .nearDuplicate,
                members: members.sorted { $0.path < $1.path },
                suggestedKeeperIDs: suggested,
                bytesIfPruned: bytes
            )
            // Perceptual video is always review-only: medium confidence, never
            // high. The scorer clamp and planner guard enforce this regardless,
            // but we set it explicitly here too.
            cluster.annotation = ClusterAnnotation(
                confidence: .medium,
                matchReason: MatchReason(
                    averageDhashDistance: evidence.medianHammingDistance,
                    kind: .nearDuplicate
                ),
                videoEvidence: evidence
            )
            clusters.append(cluster)
        }

        return clusters.sorted { ($0.members.first?.path ?? "") < ($1.members.first?.path ?? "") }
    }

    // MARK: - Helpers

    static func aspectCompatible(
        _ a: VideoPerceptualFeatures,
        _ b: VideoPerceptualFeatures,
        tolerance: Double
    ) -> Bool {
        let lhs = a.aspectRatio
        let rhs = b.aspectRatio
        guard lhs > 0, rhs > 0 else { return false }
        return abs(lhs - rhs) / max(lhs, rhs) <= tolerance
    }

    static func makeCandidate(_ feature: VideoPerceptualFeatures) -> PhotoCandidate {
        PhotoCandidate(
            path: feature.path,
            size: feature.size,
            modificationTime: feature.modificationTime,
            pixelWidth: feature.transformedWidth,
            pixelHeight: feature.transformedHeight,
            folderRoot: feature.folderRoot,
            mediaKind: .video
        )
    }

    static func medianOf(_ values: [Int]) -> Int {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count % 2 == 1 { return sorted[mid] }
        // Even count: lower-biased mean of the two central values (deterministic).
        return (sorted[mid - 1] + sorted[mid]) / 2
    }
}

// MARK: - Union-find

/// Compact union-find with path compression + union-by-rank. Local copy so the
/// perceptual matcher does not depend on the (private) one in `DuplicateClusterer`.
private struct VideoUnionFind {
    private var parent: [Int]
    private var rank: [Int]

    init(count: Int) {
        parent = Array(0..<count)
        rank = Array(repeating: 0, count: count)
    }

    mutating func find(_ x: Int) -> Int {
        var root = x
        while parent[root] != root { root = parent[root] }
        var current = x
        while parent[current] != root {
            let next = parent[current]
            parent[current] = root
            current = next
        }
        return root
    }

    mutating func union(_ a: Int, _ b: Int) {
        let rootA = find(a)
        let rootB = find(b)
        guard rootA != rootB else { return }
        if rank[rootA] < rank[rootB] {
            parent[rootA] = rootB
        } else if rank[rootA] > rank[rootB] {
            parent[rootB] = rootA
        } else {
            parent[rootB] = rootA
            rank[rootA] += 1
        }
    }
}
