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
            return String(localized: "Identical file content", bundle: .module)
        case .burst:
            return burstSummary(reason)
        case .nearDuplicate:
            return nearDuplicateSummary(reason, videoEvidence: videoEvidence)
        case .editedVariant:
            let noun = cluster.map(DeduplicateAccessibilityText.mediaNoun) ?? String(localized: "item", bundle: .module)
            return String(localized: "Edited version of the same \(String(noun))", bundle: .module)
        }
    }

    static func oneLiner(_ annotation: ClusterAnnotation) -> String {
        if let evidence = annotation.videoEvidence {
            return String(localized: "\(String(evidence.agreeingSamples)) of \(String(evidence.usableSamples)) sampled frames match", bundle: .module)
        }
        let similarity = similarityPercentage(annotation.matchReason)
        switch annotation.matchReason.kind {
        case .exactDuplicate:
            return String(localized: "Exact match", bundle: .module)
        case .burst:
            guard let similarity else {
                if let delta = annotation.matchReason.timeDeltaSeconds {
                    return String(localized: "Possible match, \(String(formattedTimeDelta(delta))) apart — review", bundle: .module)
                }
                return String(localized: "Possible burst match — review", bundle: .module)
            }
            if let delta = annotation.matchReason.timeDeltaSeconds {
                return String(localized: "\(String(similarity)) similar, \(String(formattedTimeDelta(delta))) apart", bundle: .module)
            }
            return String(localized: "\(String(similarity)) similar burst", bundle: .module)
        case .nearDuplicate:
            if let evidence = annotation.videoEvidence {
                return videoFrameOneLiner(evidence)
            }
            guard let similarity else { return unconfirmedSimilarityOneLiner }
            return String(localized: "\(String(similarity)) visually similar", bundle: .module)
        case .editedVariant:
            return String(localized: "Edited variant", bundle: .module)
        }
    }

    static func keeperSummary(_ reason: KeeperReason) -> String {
        guard !reason.factors.isEmpty else { return String(localized: "Best overall quality", bundle: .module) }
        let parts = reason.factors.map(factorDescription)
        return String(localized: "Kept: ", bundle: .module) + parts.joined(separator: ", ")
    }

    static func warningSummary(_ warning: SafetyWarning) -> String {
        switch warning {
        case .differentPeople(let delta):
            return String(localized: "Different number of faces detected (±\(String(delta)))", bundle: .module)
        case .differentFraming(let delta):
            return String(format: String(localized: "Different framing (%.0f%% crop difference)", bundle: .module), delta * 100)
        case .largeTimeGap(let seconds):
            return String(localized: "Taken \(String(formattedTimeDelta(seconds))) apart", bundle: .module)
        case .textOverlayDetected:
            return String(localized: "Text overlay detected in one version", bundle: .module)
        case .significantExposureDifference:
            return String(localized: "Significant exposure difference", bundle: .module)
        }
    }

    /// Keep in sync with `DedupeClusterConfidenceFilter.label` — one
    /// confidence vocabulary (Safe / Check / Risky) across badge, filter
    /// tabs, and the "Accept All Safe" bulk action.
    static func confidenceLabel(_ level: ConfidenceLevel) -> String {
        switch level {
        case .high: return String(localized: "Safe", bundle: .module)
        case .medium: return String(localized: "Check", bundle: .module)
        case .low: return String(localized: "Risky", bundle: .module)
        }
    }

    static func videoEvidenceSummary(_ evidence: VideoMatchEvidence) -> String {
        let frameWord = evidence.usableSamples == 1 ? String(localized: "frame", bundle: .module) : String(localized: "frames", bundle: .module)
        let duration = String(format: "%.1f", evidence.durationDeltaSeconds)
        return String(localized: "\(String(evidence.agreeingSamples)) of \(String(evidence.usableSamples)) sampled \(String(frameWord)) agree. Video lengths differ by \(String(duration)) seconds.", bundle: .module)
    }

    // MARK: - Private

    private static func burstSummary(_ reason: MatchReason) -> String {
        var parts: [String] = []
        if let delta = reason.timeDeltaSeconds {
            parts.append(String(localized: "taken \(String(formattedTimeDelta(delta))) apart", bundle: .module))
        }
        if let similarity = similarityPercentage(reason) {
            parts.append(similarity + String(localized: " visually similar", bundle: .module))
        } else {
            parts.append(unconfirmedSimilarityPhrase)
        }
        return parts.joined(separator: ", ").prefix(1).uppercased() + parts.joined(separator: ", ").dropFirst()
    }

    private static func nearDuplicateSummary(_ reason: MatchReason, videoEvidence: VideoMatchEvidence?) -> String {
        if let evidence = videoEvidence {
            return videoFrameSummary(evidence)
        }
        guard let pct = similarityPercentage(reason) else {
            if let delta = reason.timeDeltaSeconds {
                return String(localized: "Possible visual match, taken \(String(formattedTimeDelta(delta))) apart — review to confirm", bundle: .module)
            }
            return unconfirmedSimilaritySummary
        }
        if let delta = reason.timeDeltaSeconds {
            return String(localized: "\(String(pct)) visually similar, taken \(String(formattedTimeDelta(delta))) apart", bundle: .module)
        }
        return String(localized: "\(String(pct)) visually similar", bundle: .module)
    }

    private static func videoFrameSummary(_ evidence: VideoMatchEvidence) -> String {
        let frames = String(localized: "\(String(evidence.agreeingSamples)) of \(String(evidence.usableSamples)) sample frames matched", bundle: .module)
        if evidence.durationDeltaSeconds >= 0.1 {
            return String(localized: "\(String(frames)) · \(String(String(format: "%.1fs", evidence.durationDeltaSeconds))) duration difference", bundle: .module)
        }
        return frames
    }

    private static func videoFrameOneLiner(_ evidence: VideoMatchEvidence) -> String {
        String(localized: "\(String(evidence.agreeingSamples))/\(String(evidence.usableSamples)) frames match", bundle: .module)
    }

    /// dHash-only clusters reach the UI with no `averageVisionDistance`
    /// (`ClusterAnnotator.buildMatchReason` leaves it nil when no pairwise
    /// match supplied a Vision distance), so there is no similarity figure to
    /// report. Those clusters are review-only by design; the copy says the
    /// match is unconfirmed instead of inventing or placeholdering a number.
    private static var unconfirmedSimilaritySummary: String {
        String(localized: "Possible visual match — review to confirm", bundle: .module)
    }
    private static var unconfirmedSimilarityPhrase: String {
        String(localized: "possible visual match — review to confirm", bundle: .module)
    }
    private static var unconfirmedSimilarityOneLiner: String {
        String(localized: "Possible match — review", bundle: .module)
    }

    private static func similarityPercentage(_ reason: MatchReason) -> String? {
        guard let dist = reason.averageVisionDistance else { return nil }
        let pct = Int(round((1.0 - dist) * 100))
        return "\(pct)%"
    }

    private static func formattedTimeDelta(_ seconds: TimeInterval) -> String {
        let abs = Swift.abs(seconds)
        if abs < 2 { return String(localized: "< 1s", bundle: .module) }
        if abs < 60 { return String(format: "%.0fs", abs) }
        if abs < 3600 { return String(format: "%.1f min", abs / 60) }
        return String(format: String(localized: "%.1f hr", bundle: .module), abs / 3600)
    }

    private static func factorDescription(_ factor: KeeperFactor) -> String {
        switch factor {
        case .sharperFaces(let delta):
            return String(format: String(localized: "sharper faces (+%.1f)", bundle: .module), delta)
        case .higherResolution(let factor):
            return String(format: String(localized: "%.1f× resolution", bundle: .module), factor)
        case .isRaw:
            return String(localized: "RAW format", bundle: .module)
        case .largerFile(let delta):
            let formatter = ByteCountFormatter()
            formatter.countStyle = .file
            return String(localized: "larger file (+\(String(formatter.string(fromByteCount: delta))))", bundle: .module)
        case .betterSharpness(let delta):
            return String(format: String(localized: "sharper (+%.2f)", bundle: .module), delta)
        case .eyesOpen:
            return String(localized: "eyes open", bundle: .module)
        case .betterExpression(let delta):
            return String(format: String(localized: "better expression (+%.1f)", bundle: .module), delta)
        case .betterOverallQuality(let delta):
            return String(format: String(localized: "better quality (+%.2f)", bundle: .module), delta)
        }
    }
}
