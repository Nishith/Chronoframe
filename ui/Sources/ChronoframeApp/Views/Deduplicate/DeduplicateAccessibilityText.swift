import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

/// Composes the spoken VoiceOver descriptions for deduplicate review surfaces —
/// cluster rows, rapid-triage cards, and member thumbnails.
///
/// Kept as pure functions (no view state) so the wording and throttling can be
/// unit-tested without a running UI. Confidence is always spoken with the plain
/// "high / medium / low" vocabulary (not the "Safe / Check / Risky" UI
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

    // MARK: - Media-aware nouns

    /// Singular media noun ("photo" / "video" / "item") for a cluster — media-aware
    /// so exact-video review never mislabels clips as photos. Clusters are
    /// homogeneous in practice (a photo and a video can't be byte-identical), but
    /// a mixed cluster falls back to the neutral "item".
    static func mediaNoun(_ cluster: DuplicateCluster) -> String {
        if cluster.members.allSatisfy({ $0.mediaKind == .video }) { return "video" }
        if cluster.members.contains(where: { $0.mediaKind == .video }) { return "item" }
        return "photo"
    }

    /// Plural form of `mediaNoun(_:)` — "photos" / "videos" / "items".
    static func pluralMediaNoun(_ cluster: DuplicateCluster) -> String {
        mediaNoun(cluster) + "s"
    }

    /// Singular media noun for a single member ("photo" / "video"). A lone member
    /// is never mixed, so the noun follows its own `mediaKind`.
    static func mediaNoun(_ member: PhotoCandidate) -> String {
        member.mediaKind == .video ? "video" : "photo"
    }

    /// "this photo" / "this video" — for hints and actions that refer to one
    /// focused member.
    static func thisMediaPhrase(_ member: PhotoCandidate) -> String {
        "this \(mediaNoun(member))"
    }

    /// "3 photos" / "2 videos" / "4 items" — media-aware count phrase used by the
    /// cluster list count and the VoiceOver row/card labels.
    static func memberCountPhrase(_ cluster: DuplicateCluster) -> String {
        let count = cluster.members.count
        return "\(count) \(count == 1 ? mediaNoun(cluster) : pluralMediaNoun(cluster))"
    }

    // MARK: - Media-aware composed labels

    /// Container label for the rapid-triage member strip — "Photos in this group"
    /// / "Videos in this group" / "Items in this group".
    static func membersInGroupLabel(_ cluster: DuplicateCluster) -> String {
        "\(pluralMediaNoun(cluster).capitalized) in this group"
    }

    /// Pointer-hover help for the cluster row's keep-all action.
    static func keepAllHelp(_ cluster: DuplicateCluster) -> String {
        "Keep all \(pluralMediaNoun(cluster)) in this group"
    }

    /// Pointer-hover help for the cluster row's delete-all action.
    static func deleteAllHelp(_ cluster: DuplicateCluster) -> String {
        "Delete all \(pluralMediaNoun(cluster)) in this group"
    }

    /// VoiceOver hint for a comparison-pane thumbnail — "Selects this photo for
    /// keyboard keep or delete actions".
    static func selectsForKeyboardActionsHint(_ member: PhotoCandidate) -> String {
        "Selects \(thisMediaPhrase(member)) for keyboard keep or delete actions"
    }

    /// VoiceOver hint for a member thumbnail in the detail strip.
    static func selectsForComparisonHint(_ member: PhotoCandidate) -> String {
        "Selects \(thisMediaPhrase(member)) for comparison and decision review"
    }

    /// VoiceOver label for the large preview pane — "Selected photo preview" /
    /// "Selected video preview".
    static func selectedPreviewLabel(_ cluster: DuplicateCluster) -> String {
        "Selected \(mediaNoun(cluster)) preview"
    }

    /// VoiceOver label for the metadata panel — "Photo details" / "Video details".
    static func detailsLabel(_ member: PhotoCandidate) -> String {
        "\(mediaNoun(member).capitalized) details"
    }

    /// VoiceOver custom-action name for focusing a member — "Focus photo" /
    /// "Focus video".
    static func focusActionName(_ member: PhotoCandidate) -> String {
        "Focus \(mediaNoun(member))"
    }

    /// Edited-variant warning headline — "These photos may be intentionally
    /// different".
    static func intentionallyDifferentNote(_ cluster: DuplicateCluster) -> String {
        "These \(pluralMediaNoun(cluster)) may be intentionally different"
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
        return AccessibilityPathFormatter.formatFilename(URL(fileURLWithPath: keeper.path).lastPathComponent)
    }

    static func clusterRowLabel(cluster: DuplicateCluster) -> String {
        var parts: [String] = [
            "\(cluster.kind.title) group",
            memberCountPhrase(cluster),
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
            memberCountPhrase(cluster),
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
        let name = AccessibilityPathFormatter.formatFilename(URL(fileURLWithPath: member.path).lastPathComponent)
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

    static func photoPreviewDetail(
        member: PhotoCandidate,
        decision: DedupeDecision,
        isSuggestedKeeper: Bool,
        confidence: ConfidenceLevel?,
        keeperReason: KeeperReason?
    ) -> String {
        let name = AccessibilityPathFormatter.formatFilename(URL(fileURLWithPath: member.path).lastPathComponent)
        var parts = [decision == .keep ? "Marked keep" : "Marked delete"]
        if isSuggestedKeeper {
            if let rationale = keeperRationale(keeperReason) {
                parts.append("suggested keeper, \(rationale)")
            } else {
                parts.append("suggested keeper")
            }
        }
        if let confidence {
            parts.append("\(confidenceLabel(confidence)) confidence group")
        }
        parts.append(name)
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
