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

    /// Describe evidence, never a probability of duplication or safe deletion.
    /// The cluster kind alone cannot establish content identity for variants.
    static func summary(
        _ reason: MatchReason,
        in cluster: DuplicateCluster? = nil,
        videoEvidence: VideoMatchEvidence? = nil
    ) -> String {
        if let videoEvidence { return videoEvidenceSummary(videoEvidence) }
        switch reason.kind {
        case .exactDuplicate:
            return "Identical file content"
        case .burst, .nearDuplicate, .editedVariant:
            let evidence = photoEvidence(reason)
            if reason.kind != .editedVariant, let delta = reason.timeDeltaSeconds, delta.isFinite {
                return "\(evidence), taken \(formattedTimeDelta(delta)) apart"
            }
            return evidence
        }
    }

    static func oneLiner(_ annotation: ClusterAnnotation) -> String {
        if let evidence = annotation.videoEvidence {
            return "\(evidence.agreeingSamples) of \(evidence.usableSamples) sample frames matched · \(String(format: "%.1fs", evidence.durationDeltaSeconds)) duration difference · review only"
        }
        let reason = annotation.matchReason
        if reason.kind == .exactDuplicate { return "Identical file content" }
        if reason.kind == .burst, let delta = reason.timeDeltaSeconds, delta.isFinite {
            return "\(photoEvidence(reason)), \(formattedTimeDelta(delta)) apart"
        }
        return photoEvidence(reason)
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

    /// Recommendation strength is not a deletion or restoration guarantee.
    static func confidenceLabel(_ level: ConfidenceLevel) -> String {
        switch level {
        case .high: return "Strong"
        case .medium: return "Check"
        case .low: return "Careful"
        }
    }

    static func videoEvidenceSummary(_ evidence: VideoMatchEvidence) -> String {
        let frameWord = evidence.usableSamples == 1 ? "frame" : "frames"
        let duration = String(format: "%.1f", evidence.durationDeltaSeconds)
        return "\(evidence.agreeingSamples) of \(evidence.usableSamples) sampled \(frameWord) agree. Video lengths differ by \(duration) seconds. Review only; sampled agreement does not establish identical content."
    }

    // MARK: - Private

    private static func photoEvidence(_ reason: MatchReason) -> String {
        guard let distance = reason.averageVisionDistance, distance.isFinite, distance >= 0 else {
            return "Possible visual similarity; review required"
        }
        return "Visual match confirmed; files may differ"
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
