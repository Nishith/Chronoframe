import ChronoframeAppCore
import ChronoframeCore
import XCTest
@testable import ChronoframeApp

/// Regression coverage for `DeduplicateAccessibilityText`, the pure helper that
/// composes spoken VoiceOver descriptions for the dedupe review. These tests
/// lock in the wording and branch behavior (confidence vocabulary, suggestion
/// framing, warning flag, review state) so accidental changes are caught.
final class DeduplicateAccessibilityTextTests: XCTestCase {

    // MARK: - confidenceLabel

    func testConfidenceLabelUsesPlainVocabularyAndDefaultsToMedium() {
        XCTAssertEqual(DeduplicateAccessibilityText.confidenceLabel(.high), "high")
        XCTAssertEqual(DeduplicateAccessibilityText.confidenceLabel(.medium), "medium")
        XCTAssertEqual(DeduplicateAccessibilityText.confidenceLabel(.low), "low")
        XCTAssertEqual(DeduplicateAccessibilityText.confidenceLabel(nil), "medium")
    }

    // MARK: - clusterRowLabel

    func testClusterRowLabelLeadsWithKindTitleForEveryKind() {
        let expected: [(ClusterKind, String)] = [
            (.exactDuplicate, "Exact duplicates group, "),
            (.nearDuplicate, "Near duplicates group, "),
            (.burst, "Bursts group, "),
            (.editedVariant, "Edited variants group, "),
        ]
        for (kind, prefix) in expected {
            let label = DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster(kind: kind))
            XCTAssertTrue(label.hasPrefix(prefix), "Expected \(prefix) prefix, got: \(label)")
            XCTAssertTrue(label.contains("2 photos"))
        }
    }

    func testClusterRowLabelNamesTheSuggestedKeeperWhenPresent() {
        XCTAssertTrue(
            DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster(includeKeeper: true))
                .contains("suggested keeper keeper.jpg")
        )
        XCTAssertFalse(
            DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster(includeKeeper: false))
                .contains("suggested keeper")
        )
    }

    func testClusterRowLabelFlagsWarningsButNotCleanGroups() {
        XCTAssertTrue(
            DeduplicateAccessibilityText.clusterRowLabel(
                cluster: cluster(warnings: [.differentPeople(faceCountDelta: 2)])
            ).contains("needs careful review")
        )
        XCTAssertFalse(
            DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster(warnings: []))
                .contains("needs careful review")
        )
    }

    func testClusterRowLabelWithoutAnnotationSpeaksMediumConfidenceAndNoWarning() {
        let label = DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster(hasAnnotation: false))
        XCTAssertTrue(label.contains("medium confidence"))
        XCTAssertFalse(label.contains("needs careful review"))
    }

    // MARK: - clusterRowValue

    func testClusterRowValueLeadsWithReviewStateAndReclaimableBytes() {
        let reviewed = DeduplicateAccessibilityText.clusterRowValue(
            cluster: cluster(), isApproved: true, recoverableBytes: 1_048_576
        )
        XCTAssertTrue(reviewed.hasPrefix("Reviewed. "))
        XCTAssertTrue(reviewed.contains("1 MB reclaimable."))

        let pending = DeduplicateAccessibilityText.clusterRowValue(
            cluster: cluster(), isApproved: false, recoverableBytes: 1_048_576
        )
        XCTAssertTrue(pending.hasPrefix("Suggested, not reviewed. "))
    }

    func testClusterRowValueAppendsMatchReasonOnlyWhenAnnotated() {
        let annotated = DeduplicateAccessibilityText.clusterRowValue(
            cluster: cluster(kind: .exactDuplicate), isApproved: false, recoverableBytes: 1_048_576
        )
        XCTAssertTrue(annotated.contains("Exact match"))

        let bare = DeduplicateAccessibilityText.clusterRowValue(
            cluster: cluster(hasAnnotation: false), isApproved: false, recoverableBytes: 1_048_576
        )
        XCTAssertTrue(bare.hasSuffix("reclaimable."), "Unannotated value should stop at the byte summary: \(bare)")
    }

    // MARK: - rapidTriageLabel

    func testRapidTriageLabelIsOneIndexedAndCountsTotal() {
        let label = DeduplicateAccessibilityText.rapidTriageLabel(
            cluster: cluster(), currentIndex: 0, totalCount: 3
        )
        XCTAssertTrue(label.hasPrefix("Group 1 of 3, "), label)
    }

    func testRapidTriageLabelUsesBriefWarningFlagNotTheFullSummary() {
        // The banner carries the specific warning; the label must not repeat it
        // verbatim (otherwise VoiceOver announces it twice).
        let label = DeduplicateAccessibilityText.rapidTriageLabel(
            cluster: cluster(warnings: [.differentPeople(faceCountDelta: 1)]),
            currentIndex: 1,
            totalCount: 4
        )
        XCTAssertTrue(label.contains("needs careful review"))
        XCTAssertFalse(label.contains("Different number of faces"))

        XCTAssertFalse(
            DeduplicateAccessibilityText.rapidTriageLabel(
                cluster: cluster(warnings: []), currentIndex: 0, totalCount: 1
            ).contains("needs careful review")
        )
    }

    func testRapidTriageValueIsTheReclaimableSummary() {
        let value = DeduplicateAccessibilityText.rapidTriageValue(
            cluster: cluster(), reclaimableBytes: 1_048_576
        )
        XCTAssertTrue(value.contains("1 MB reclaimable."))
    }

    // MARK: - member label / value

    func testMemberLabelTagsSuggestedKeeperOnly() {
        let keeper = PhotoCandidate(path: "/Photos/keeper.jpg", size: 2_000_000, modificationTime: 0, qualityScore: 0.9)
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberLabel(member: keeper, isSuggestedKeeper: true),
            "keeper.jpg, suggested keeper"
        )
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberLabel(member: keeper, isSuggestedKeeper: false),
            "keeper.jpg"
        )
    }

    func testMemberValueReportsDecisionFocusAndPlainConfidence() {
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberValue(decision: .keep, isFocused: true, confidence: .high),
            "Marked keep, selected, high confidence group"
        )
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberValue(decision: .delete, isFocused: false, confidence: .low),
            "Marked delete, low confidence group"
        )
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberValue(decision: .delete, isFocused: false, confidence: nil),
            "Marked delete"
        )
    }

    // MARK: - suggestedKeeperName

    func testSuggestedKeeperNameResolvesOrReturnsNil() {
        XCTAssertEqual(DeduplicateAccessibilityText.suggestedKeeperName(in: cluster(includeKeeper: true)), "keeper.jpg")
        XCTAssertNil(DeduplicateAccessibilityText.suggestedKeeperName(in: cluster(includeKeeper: false)))
        // Suggested id that no member matches must not crash or mislabel.
        XCTAssertNil(DeduplicateAccessibilityText.suggestedKeeperName(in: cluster(keeperID: "/Photos/ghost.jpg")))
    }

    // MARK: - Factory

    private func cluster(
        kind: ClusterKind = .nearDuplicate,
        confidence: ConfidenceLevel = .high,
        warnings: [SafetyWarning] = [],
        includeKeeper: Bool = true,
        hasAnnotation: Bool = true,
        keeperID: String? = nil
    ) -> DuplicateCluster {
        let members = [
            PhotoCandidate(path: "/Photos/keeper.jpg", size: 2_000_000, modificationTime: 0, qualityScore: 0.9),
            PhotoCandidate(path: "/Photos/duplicate.jpg", size: 1_048_576, modificationTime: 0, qualityScore: 0.4),
        ]
        let keeperIDs: [String]
        if let keeperID {
            keeperIDs = [keeperID]
        } else {
            keeperIDs = includeKeeper ? ["/Photos/keeper.jpg"] : []
        }
        return DuplicateCluster(
            kind: kind,
            members: members,
            suggestedKeeperIDs: keeperIDs,
            bytesIfPruned: 1_048_576,
            annotation: hasAnnotation
                ? ClusterAnnotation(
                    confidence: confidence,
                    matchReason: MatchReason(timeDeltaSeconds: 12, averageVisionDistance: 0.08, kind: kind),
                    warnings: warnings
                )
                : nil
        )
    }
}
