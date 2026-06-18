import Foundation

/// Assigns a confidence level to a cluster based on how obvious the
/// duplication is. High-confidence clusters can be auto-accepted;
/// low-confidence ones require careful manual review.
public enum ClusterConfidenceScorer {
    public static func score(
        cluster: DuplicateCluster,
        matchReason: MatchReason,
        warnings: [SafetyWarning]
    ) -> ConfidenceLevel {
        let base = baseScore(cluster: cluster, matchReason: matchReason, warnings: warnings)

        // Perceptual (non-exact) video clusters are always review-only in the
        // first release: never let one reach high confidence, even if the
        // distance metrics would otherwise qualify. This is the scorer half of
        // the two structural guards that keep video deletion safe — the planner
        // (`isAutomaticCommitEligible`) enforces the other half, and a bypass in
        // either alone must not be able to auto-delete a video.
        if cluster.kind != .exactDuplicate,
           cluster.members.contains(where: { $0.mediaKind == .video }) {
            return min(base, .medium)
        }
        return base
    }

    private static func baseScore(
        cluster: DuplicateCluster,
        matchReason: MatchReason,
        warnings: [SafetyWarning]
    ) -> ConfidenceLevel {
        if !warnings.isEmpty { return .low }

        if cluster.kind == .exactDuplicate { return .high }

        let visionDist = matchReason.averageVisionDistance ?? 1.0
        let timeDelta = matchReason.timeDeltaSeconds ?? .greatestFiniteMagnitude

        if visionDist < 0.10, timeDelta < 5.0 {
            return .high
        }

        if cluster.kind == .editedVariant {
            return .low
        }

        if visionDist > 0.30 {
            return .low
        }

        return .medium
    }
}
