import ChronoframeCore
import XCTest
@testable import ChronoframeApp

/// Exercises the `MatchReasonFormatter` branches the existing
/// `DeduplicateStatusViewTests` case does not reach: the non-burst `summary`
/// and `oneLiner` paths, the empty-keeper fallback, every `SafetyWarning`
/// variant, and the time-delta formatting tiers (< 1s / seconds / minutes /
/// hours). Pure string formatting; no rendering.
final class MatchReasonFormatterBranchTests: XCTestCase {
    func testNearDuplicateSummaryReportsSimilarityWithAndWithoutTimeDelta() {
        let withDelta = MatchReason(timeDeltaSeconds: 45, averageVisionDistance: 0.1, kind: .nearDuplicate)
        XCTAssertEqual(MatchReasonFormatter.summary(withDelta), "90% visually similar, taken 45s apart")

        let withoutDelta = MatchReason(averageVisionDistance: 0.1, kind: .nearDuplicate)
        XCTAssertEqual(MatchReasonFormatter.summary(withoutDelta), "90% visually similar")
    }

    func testSimilarityFallsBackToTildeWhenVisionDistanceMissing() {
        let noDistance = MatchReason(kind: .nearDuplicate)
        XCTAssertEqual(MatchReasonFormatter.summary(noDistance), "~ visually similar")
    }

    func testVideoEvidenceUsesConcreteFrameAgreementCopy() {
        let evidence = VideoMatchEvidence(
            usableSamples: 5,
            agreeingSamples: 4,
            medianHammingDistance: 3,
            durationDeltaSeconds: 0.4,
            visionCorroborated: false
        )
        let annotation = ClusterAnnotation(
            confidence: .medium,
            matchReason: MatchReason(kind: .nearDuplicate),
            videoEvidence: evidence
        )

        XCTAssertEqual(MatchReasonFormatter.oneLiner(annotation), "4 of 5 sampled frames match")
        XCTAssertEqual(
            MatchReasonFormatter.summary(annotation),
            "4 of 5 sampled frames agree. Video lengths differ by 0.4 seconds."
        )
    }

    func testOneLinerCoversEveryClusterKind() {
        XCTAssertEqual(
            MatchReasonFormatter.oneLiner(annotation(.exactDuplicate, distance: 0.0)),
            "Exact match"
        )
        XCTAssertEqual(
            MatchReasonFormatter.oneLiner(annotation(.editedVariant, distance: 0.2)),
            "Edited variant"
        )
        XCTAssertEqual(
            MatchReasonFormatter.oneLiner(annotation(.nearDuplicate, distance: 0.15)),
            "85% visually similar"
        )
    }

    func testOneLinerBurstOmitsDeltaWhenAbsent() {
        XCTAssertEqual(
            MatchReasonFormatter.oneLiner(annotation(.burst, distance: 0.1, timeDelta: nil)),
            "90% similar burst"
        )
    }

    func testKeeperSummaryFallsBackWhenNoFactors() {
        XCTAssertEqual(MatchReasonFormatter.keeperSummary(KeeperReason()), "Best overall quality")
    }

    func testKeeperSummaryDescribesResolutionRawAndSharpnessFactors() {
        let summary = MatchReasonFormatter.keeperSummary(KeeperReason(factors: [
            .higherResolution(factor: 2.0),
            .isRaw,
            .sharperFaces(delta: 1.5),
        ]))
        XCTAssertEqual(summary, "Kept: 2.0× resolution, RAW format, sharper faces (+1.5)")
    }

    func testWarningSummaryCoversAllVariants() {
        XCTAssertEqual(
            MatchReasonFormatter.warningSummary(.differentPeople(faceCountDelta: 2)),
            "Different number of faces detected (±2)"
        )
        XCTAssertEqual(
            MatchReasonFormatter.warningSummary(.textOverlayDetected),
            "Text overlay detected in one version"
        )
        XCTAssertEqual(
            MatchReasonFormatter.warningSummary(.significantExposureDifference),
            "Significant exposure difference"
        )
    }

    func testWarningSummaryTimeDeltaTiers() {
        XCTAssertEqual(MatchReasonFormatter.warningSummary(.largeTimeGap(seconds: 1)), "Taken < 1s apart")
        XCTAssertEqual(MatchReasonFormatter.warningSummary(.largeTimeGap(seconds: 30)), "Taken 30s apart")
        XCTAssertEqual(MatchReasonFormatter.warningSummary(.largeTimeGap(seconds: 7200)), "Taken 2.0 hr apart")
    }

    // MARK: - Helpers

    private func annotation(
        _ kind: ClusterKind,
        distance: Double,
        timeDelta: TimeInterval? = 12
    ) -> ClusterAnnotation {
        ClusterAnnotation(
            matchReason: MatchReason(
                timeDeltaSeconds: timeDelta,
                averageVisionDistance: distance,
                kind: kind
            )
        )
    }
}
