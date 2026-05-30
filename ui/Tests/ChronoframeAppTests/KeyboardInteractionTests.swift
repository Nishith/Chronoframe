import CoreGraphics
import ChronoframeCore
import XCTest
@testable import ChronoframeApp

/// Unit tests for the pure math behind keyboard- and VoiceOver-driven controls.
/// The view wiring (arrow keys, adjustable actions, drag) all routes through
/// these helpers, so testing them locks the increment/clamp/threshold behavior
/// without needing a running UI.
final class KeyboardInteractionTests: XCTestCase {

    // MARK: - ComparisonSlider

    func testSliderClampsToUnitRange() {
        XCTAssertEqual(ComparisonSlider.clamped(-0.4), 0)
        XCTAssertEqual(ComparisonSlider.clamped(1.7), 1)
        XCTAssertEqual(ComparisonSlider.clamped(0.42), 0.42, accuracy: 0.0001)
    }

    func testSliderAdjustStepsAndClamps() {
        XCTAssertEqual(ComparisonSlider.adjusted(0.5, by: ComparisonSlider.step), 0.55, accuracy: 0.0001)
        XCTAssertEqual(ComparisonSlider.adjusted(0.5, by: -ComparisonSlider.step), 0.45, accuracy: 0.0001)
        // Cannot move past the ends.
        XCTAssertEqual(ComparisonSlider.adjusted(0.98, by: ComparisonSlider.step), 1)
        XCTAssertEqual(ComparisonSlider.adjusted(0.02, by: -ComparisonSlider.step), 0)
    }

    func testSliderFractionFromDragLocation() {
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: 50, width: 200), 0.25, accuracy: 0.0001)
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: -10, width: 200), 0)
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: 300, width: 200), 1)
        // Degenerate width must not divide by zero.
        XCTAssertEqual(ComparisonSlider.fraction(forLocationX: 50, width: 0), 0)
    }

    func testSliderAccessibilityValueIsAPercentage() {
        XCTAssertEqual(ComparisonSlider.accessibilityValue(0), "0% keeper")
        XCTAssertEqual(ComparisonSlider.accessibilityValue(0.5), "50% keeper")
        XCTAssertEqual(ComparisonSlider.accessibilityValue(1), "100% keeper")
    }

    // MARK: - RapidTriageSwipe

    func testSwipeOutcomeRespectsThreshold() {
        let t = RapidTriageSwipe.threshold
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: t + 1), .accept)
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: -(t + 1)), .skip)
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: 0), .none)
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: t), .none, "Exactly at threshold should not commit")
        XCTAssertEqual(RapidTriageSwipe.outcome(forTranslationWidth: -t), .none)
    }

    // MARK: - DedupeReviewKeyboard

    func testClusterKeyboardNavigationClampsToAvailableGroups() {
        XCTAssertEqual(DedupeReviewKeyboard.clusterIndex(afterMoving: 1, from: nil, count: 3), 1)
        XCTAssertEqual(DedupeReviewKeyboard.clusterIndex(afterMoving: -1, from: nil, count: 3), 0)
        XCTAssertEqual(DedupeReviewKeyboard.clusterIndex(afterMoving: -1, from: 0, count: 3), 0)
        XCTAssertEqual(DedupeReviewKeyboard.clusterIndex(afterMoving: 1, from: -10, count: 3), 1)
        XCTAssertEqual(DedupeReviewKeyboard.clusterIndex(afterMoving: -1, from: 99, count: 3), 1)
        XCTAssertEqual(DedupeReviewKeyboard.clusterIndex(afterMoving: 1, from: 2, count: 3), 2)
        XCTAssertNil(DedupeReviewKeyboard.clusterIndex(afterMoving: 1, from: nil, count: 0))
    }

    func testClusterKeyboardNavigationUsesFilteredVisibleRows() {
        let high = Self.cluster(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, path: "/high.jpg", confidence: .high)
        let medium = Self.cluster(id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!, path: "/medium.jpg", confidence: .medium)
        let low = Self.cluster(id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!, path: "/low.jpg", confidence: .low)
        let legacy = Self.cluster(id: UUID(uuidString: "00000000-0000-0000-0000-000000000004")!, path: "/legacy.jpg", confidence: nil)
        let clusters = [high, medium, low, legacy]

        let visibleReviewRows = DedupeClusterConfidenceFilter.filtered(clusters, by: .medium)

        XCTAssertEqual(visibleReviewRows.map(\.id), [medium.id, legacy.id])
        XCTAssertEqual(DedupeClusterConfidenceFilter.filtered(clusters, by: .high).map(\.id), [high.id])
        XCTAssertEqual(DedupeClusterConfidenceFilter.filtered(clusters, by: .low).map(\.id), [low.id])

        let currentIndex = visibleReviewRows.firstIndex { $0.id == medium.id }
        let nextIndex = DedupeReviewKeyboard.clusterIndex(
            afterMoving: 1,
            from: currentIndex,
            count: visibleReviewRows.count
        )

        XCTAssertEqual(nextIndex.map { visibleReviewRows[$0].id }, legacy.id)
    }

    // MARK: - FlickerComparisonPlayback

    func testFlickerPlaybackHonorsReduceMotion() {
        XCTAssertTrue(FlickerComparisonPlayback.effectiveIsPlaying(requestedPlaying: true, reduceMotion: false))
        XCTAssertFalse(FlickerComparisonPlayback.effectiveIsPlaying(requestedPlaying: true, reduceMotion: true))
        XCTAssertFalse(FlickerComparisonPlayback.effectiveIsPlaying(requestedPlaying: false, reduceMotion: false))
    }

    func testFlickerAccessibilityValueNamesPlaybackAndCurrentSide() {
        XCTAssertEqual(FlickerComparisonPlayback.automaticIntervalMilliseconds, 900)
        XCTAssertEqual(
            FlickerComparisonPlayback.accessibilityValue(isShowingKeeper: true, isPlaying: false),
            "Paused, showing keeper"
        )
        XCTAssertEqual(
            FlickerComparisonPlayback.accessibilityValue(isShowingKeeper: false, isPlaying: true),
            "Playing, showing compare, alternating every 0.9 seconds"
        )
    }

    private static func cluster(id: UUID, path: String, confidence: ConfidenceLevel?) -> DuplicateCluster {
        DuplicateCluster(
            id: id,
            kind: .nearDuplicate,
            members: [
                PhotoCandidate(path: path, size: 1, modificationTime: 0),
                PhotoCandidate(path: path.replacingOccurrences(of: ".jpg", with: "-copy.jpg"), size: 1, modificationTime: 0)
            ],
            suggestedKeeperIDs: [path],
            bytesIfPruned: 1,
            annotation: confidence.map {
                ClusterAnnotation(confidence: $0, matchReason: MatchReason(kind: .nearDuplicate))
            }
        )
    }
}
