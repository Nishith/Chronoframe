#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

enum MatchReasonFormatter {
    static func summary(_ annotation: ClusterAnnotation, in cluster: DuplicateCluster? = nil) -> String {
        if let evidence = annotation.videoEvidence {
            return videoEvidenceSummary(evidence)
        }
        return summary(annotation.matchReason, in: cluster)
    }

    /// `cluster` makes the edited-variant wording media-aware ("same photo" /
    /// "same video"). It defaults to `nil` — when no cluster context is
    /// available the noun falls back to the neutral "item". `videoEvidence`
    /// replaces the vision-distance percentage with frame-agreement copy for
    /// perceptual video clusters.
    static func summary(
        _ reason: MatchReason,
        in cluster: DuplicateCluster? = nil,
        videoEvidence: VideoMatchEvidence? = nil
    ) -> String {
        switch reason.kind {
        case .exactDuplicate:
            return "Identical file content"
        case .burst:
            return burstSummary(reason)
        case .nearDuplicate:
            return nearDuplicateSummary(reason, videoEvidence: videoEvidence)
        case .editedVariant:
            let noun = cluster.map(DeduplicateAccessibilityText.mediaNoun) ?? "item"
            return "Edited version of the same \(noun)"
        }
    }

    static func oneLiner(_ annotation: ClusterAnnotation) -> String {
        if let evidence = annotation.videoEvidence {
            return "\(evidence.agreeingSamples) of \(evidence.usableSamples) sampled frames match"
        }
        let similarity = similarityPercentage(annotation.matchReason)
        switch annotation.matchReason.kind {
        case .exactDuplicate:
            return "Exact match"
        case .burst:
            if let delta = annotation.matchReason.timeDeltaSeconds {
                return "\(similarity) similar, \(formattedTimeDelta(delta)) apart"
            }
            return "\(similarity) similar burst"
        case .nearDuplicate:
            if let evidence = annotation.videoEvidence {
                return videoFrameOneLiner(evidence)
            }
            return "\(similarity) visually similar"
        case .editedVariant:
            return "Edited variant"
        }
    }

    static func keeperSummary(_ reason: KeeperReason) -> String {
        guard !reason.factors.isEmpty else { return "Best overall quality" }
        let parts = reason.factors.map(factorDescription)
        return "Kept: " + parts.joined(separator: ", ")
    }

    static func warningSummary(_ warning: SafetyWarning) -> String {
        switch warning {
        case .differentPeople(let delta):
            return "Different number of faces detected (±\(delta))"
        case .differentFraming(let delta):
            return String(format: "Different framing (%.0f%% crop difference)", delta * 100)
        case .largeTimeGap(let seconds):
            return "Taken \(formattedTimeDelta(seconds)) apart"
        case .textOverlayDetected:
            return "Text overlay detected in one version"
        case .significantExposureDifference:
            return "Significant exposure difference"
        }
    }

    /// Keep in sync with `DedupeClusterConfidenceFilter.label` — one
    /// confidence vocabulary (Safe / Check / Risky) across badge, filter
    /// tabs, and the "Accept All Safe" bulk action.
    static func confidenceLabel(_ level: ConfidenceLevel) -> String {
        switch level {
        case .high: return "Safe"
        case .medium: return "Check"
        case .low: return "Risky"
        }
    }

    static func videoEvidenceSummary(_ evidence: VideoMatchEvidence) -> String {
        let frameWord = evidence.usableSamples == 1 ? "frame" : "frames"
        let duration = String(format: "%.1f", evidence.durationDeltaSeconds)
        return "\(evidence.agreeingSamples) of \(evidence.usableSamples) sampled \(frameWord) agree. Video lengths differ by \(duration) seconds."
    }

    // MARK: - Private

    private static func burstSummary(_ reason: MatchReason) -> String {
        var parts: [String] = []
        if let delta = reason.timeDeltaSeconds {
            parts.append("taken \(formattedTimeDelta(delta)) apart")
        }
        parts.append(similarityPercentage(reason) + " visually similar")
        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst()
    }

    private static func nearDuplicateSummary(_ reason: MatchReason, videoEvidence: VideoMatchEvidence?) -> String {
        if let evidence = videoEvidence {
            return videoFrameSummary(evidence)
        }
        let pct = similarityPercentage(reason)
        if let delta = reason.timeDeltaSeconds {
            return "\(pct) visually similar, taken \(formattedTimeDelta(delta)) apart"
        }
        return "\(pct) visually similar"
    }

    private static func videoFrameSummary(_ evidence: VideoMatchEvidence) -> String {
        let frames = "\(evidence.agreeingSamples) of \(evidence.usableSamples) sample frames matched"
        if evidence.durationDeltaSeconds >= 0.1 {
            return "\(frames) · \(String(format: "%.1fs", evidence.durationDeltaSeconds)) duration difference"
        }
        return frames
    }

    private static func videoFrameOneLiner(_ evidence: VideoMatchEvidence) -> String {
        "\(evidence.agreeingSamples)/\(evidence.usableSamples) frames match"
    }

    private static func similarityPercentage(_ reason: MatchReason) -> String {
        if let dist = reason.averageVisionDistance {
            let pct = Int(round((1.0 - dist) * 100))
            return "\(pct)%"
        }
        return "~"
    }

    private static func formattedTimeDelta(_ seconds: TimeInterval) -> String {
        let abs = Swift.abs(seconds)
        if abs < 2 { return "< 1s" }
        if abs < 60 { return String(format: "%.0fs", abs) }
        if abs < 3600 { return String(format: "%.1f min", abs / 60) }
        return String(format: "%.1f hr", abs / 3600)
    }

    private static func factorDescription(_ factor: KeeperFactor) -> String {
        switch factor {
        case .sharperFaces(let delta):
            return String(format: "sharper faces (+%.1f)", delta)
        case .higherResolution(let factor):
            return String(format: "%.1f× resolution", factor)
        case .isRaw:
            return "RAW format"
        case .largerFile(let delta):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return "larger file (+\(formatter.string(fromByteCount: delta)))"
        case .betterSharpness(let delta):
            return String(format: "sharper (+%.2f)", delta)
        case .eyesOpen:
            return "eyes open"
        case .betterExpression(let delta):
            return String(format: "better expression (+%.1f)", delta)
        case .betterOverallQuality(let delta):
            return String(format: "better quality (+%.2f)", delta)
        }
    }
}
