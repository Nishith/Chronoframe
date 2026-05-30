import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

/// Composes the spoken VoiceOver descriptions for deduplicate review surfaces —
/// cluster rows, rapid-triage cards, and member thumbnails.
///
/// Kept as pure functions (no view state) so the wording and throttling can be
/// unit-tested without a running UI. Confidence is always spoken with the plain
/// "high / medium / low" vocabulary (not the "Auto / Review / Careful" UI
/// shorthand) so it reads consistently across surfaces.
enum DeduplicateAccessibilityText {
    // Built per call rather than cached in a `static let`: `ByteCountFormatter`
    // is not `Sendable`, so a stored static would trip Swift 6 strict
    // concurrency on this non-isolated enum. Label composition is not a hot
    // path, so the allocation cost is negligible.
    private static func formattedByteCount(_ byteCount: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: byteCount)
    }

    static func confidenceLabel(_ level: ConfidenceLevel?) -> String {
        switch level ?? .medium {
        case .high: return "high"
        case .medium: return "medium"
        case .low: return "low"
        }
    }

    static func suggestedKeeperName(in cluster: DuplicateCluster) -> String? {
        guard let keeperID = cluster.suggestedKeeperIDs.first,
              let keeper = cluster.members.first(where: { $0.id == keeperID }) else {
            return nil
        }
        return URL(fileURLWithPath: keeper.path).lastPathComponent
    }

    static func clusterRowLabel(cluster: DuplicateCluster) -> String {
        var parts: [String] = [
            "\(cluster.kind.title) group",
            "\(cluster.members.count) photos",
            "\(confidenceLabel(cluster.annotation?.confidence)) confidence"
        ]
        if let keeper = suggestedKeeperName(in: cluster) {
            parts.append("suggested keeper \(keeper)")
        }
        if let rationale = keeperRationale(cluster.annotation?.keeperReason) {
            parts.append(rationale)
        }
        if !(cluster.annotation?.warnings.isEmpty ?? true) {
            parts.append("needs careful review")
        }
        return parts.joined(separator: ", ")
    }

    static func clusterRowValue(
        cluster: DuplicateCluster,
        isApproved: Bool,
        recoverableBytes: Int64
    ) -> String {
        let reviewState = isApproved ? "Reviewed" : "Suggested, not reviewed"
        return "\(reviewState). \(reclaimableSummary(cluster: cluster, recoverableBytes: recoverableBytes))"
    }

    static func rapidTriageLabel(
        cluster: DuplicateCluster,
        currentIndex: Int,
        totalCount: Int
    ) -> String {
        var parts = [
            "Group \(currentIndex + 1) of \(totalCount)",
            "\(cluster.members.count) photos",
            "\(confidenceLabel(cluster.annotation?.confidence)) confidence"
        ]
        if let keeper = suggestedKeeperName(in: cluster) {
            parts.append("suggested keeper \(keeper)")
        }
        if let rationale = keeperRationale(cluster.annotation?.keeperReason) {
            parts.append(rationale)
        }
        // A brief "needs careful review" flag here, matching the cluster row.
        // The specific warning text is carried by the visible warning banner
        // (which VoiceOver also reads), so repeating the full summary in this
        // composed label would announce it twice.
        if !(cluster.annotation?.warnings.isEmpty ?? true) {
            parts.append("needs careful review")
        }
        return parts.joined(separator: ", ")
    }

    static func rapidTriageValue(cluster: DuplicateCluster, reclaimableBytes: Int64) -> String {
        reclaimableSummary(cluster: cluster, recoverableBytes: reclaimableBytes)
    }

    static func memberLabel(
        member: PhotoCandidate,
        isSuggestedKeeper: Bool,
        keeperReason: KeeperReason? = nil
    ) -> String {
        let name = URL(fileURLWithPath: member.path).lastPathComponent
        guard isSuggestedKeeper else { return name }
        if let rationale = keeperRationale(keeperReason) {
            return "\(name), suggested keeper, \(rationale)"
        }
        return "\(name), suggested keeper"
    }

    static func memberValue(
        decision: DedupeDecision,
        isFocused: Bool,
        confidence: ConfidenceLevel?
    ) -> String {
        var parts = [decision == .keep ? "Marked keep" : "Marked delete"]
        if isFocused {
            parts.append("selected")
        }
        if let confidence {
            // Use the same plain high/medium/low vocabulary as the cluster-row
            // and rapid-triage labels, so VoiceOver speaks one consistent term
            // for confidence (not the "Auto/Review/Careful" UI shorthand).
            parts.append("\(confidenceLabel(confidence)) confidence group")
        }
        return parts.joined(separator: ", ")
    }

    private static func reclaimableSummary(
        cluster: DuplicateCluster,
        recoverableBytes: Int64
    ) -> String {
        let bytes = formattedByteCount(recoverableBytes)
        if let annotation = cluster.annotation {
            return "\(bytes) reclaimable. \(MatchReasonFormatter.oneLiner(annotation))"
        }
        return "\(bytes) reclaimable."
    }

    static func keeperRationale(_ reason: KeeperReason?) -> String? {
        guard let reason, !reason.factors.isEmpty else { return nil }
        let summary = MatchReasonFormatter.keeperSummary(reason)
        if summary.hasPrefix("Kept: ") {
            return "because " + summary.dropFirst("Kept: ".count)
        }
        return summary
    }
}
