import XCTest
@testable import ChronoframeApp
@testable import ChronoframeCore

final class DeduplicateReviewLanesTests: XCTestCase {
    private func photo(_ name: String) -> PhotoCandidate {
        PhotoCandidate(path: "/dest/\(name).jpg", size: 1, modificationTime: 0, mediaKind: .photo)
    }

    private func video(_ name: String) -> PhotoCandidate {
        PhotoCandidate(path: "/dest/\(name).mov", size: 1, modificationTime: 0, mediaKind: .video)
    }

    private func cluster(
        _ kind: ClusterKind,
        members: [PhotoCandidate],
        confidence: ConfidenceLevel?
    ) -> DuplicateCluster {
        DuplicateCluster(
            kind: kind,
            members: members,
            suggestedKeeperIDs: members.first.map { [$0.id] } ?? [],
            bytesIfPruned: 0,
            annotation: confidence.map {
                ClusterAnnotation(confidence: $0, matchReason: MatchReason(kind: kind))
            }
        )
    }

    private func eligible(_ name: String) -> DuplicateCluster {
        cluster(.exactDuplicate, members: [photo("\(name)a"), photo("\(name)b")], confidence: .high)
    }

    /// High confidence on the annotation, yet the planner gate refuses it:
    /// a perceptual video group is review-only.
    private func highButNotEligible(_ name: String) -> DuplicateCluster {
        cluster(.nearDuplicate, members: [video("\(name)a"), video("\(name)b")], confidence: .high)
    }

    private func uncertain(_ name: String) -> DuplicateCluster {
        cluster(.nearDuplicate, members: [photo("\(name)a"), photo("\(name)b")], confidence: .medium)
    }

    func testEligibleUnreviewedGroupsCountAsSafe() {
        let lanes = DeduplicateReviewLanes(
            clusters: [eligible("one"), eligible("two"), eligible("three")],
            reviewedIDs: []
        )
        XCTAssertEqual(lanes.safeGroupCount, 3)
        XCTAssertEqual(lanes.checkGroupCount, 0)
        XCTAssertEqual(lanes.reviewedGroupCount, 0)
    }

    // AGENTS-INVARIANT: 6
    func testNonEligibleGroupsNeverCountAsSafe() {
        let trap = highButNotEligible("trap")
        XCTAssertEqual(trap.annotation?.confidence, .high)
        XCTAssertFalse(DeduplicationPlanner.isAutomaticCommitEligible(trap))

        let lanes = DeduplicateReviewLanes(
            clusters: [trap, uncertain("soft"), eligible("sure")],
            reviewedIDs: []
        )
        XCTAssertEqual(lanes.safeGroupCount, 1)
        XCTAssertEqual(lanes.checkGroupCount, 2)

        // Even an injected "everything is eligible" closure only changes the count
        // through the closure; the default gate is the planner's.
        let onlyTrap = DeduplicateReviewLanes(clusters: [trap], reviewedIDs: [])
        XCTAssertEqual(onlyTrap.safeGroupCount, 0)
        XCTAssertEqual(onlyTrap.checkGroupCount, 1)
        XCTAssertNil(onlyTrap.safeText)
        XCTAssertNotNil(onlyTrap.checkText)
    }

    func testReviewedGroupsLeaveBothLanes() {
        let safe = eligible("safe")
        let soft = uncertain("soft")
        let other = uncertain("other")
        let lanes = DeduplicateReviewLanes(
            clusters: [safe, soft, other],
            reviewedIDs: [safe.id, soft.id]
        )
        XCTAssertEqual(lanes.safeGroupCount, 0)
        XCTAssertEqual(lanes.checkGroupCount, 1)
        XCTAssertEqual(lanes.reviewedGroupCount, 2)
    }

    func testTextsSingularPluralAndNil() {
        let one = DeduplicateReviewLanes(clusters: [eligible("a"), uncertain("b")], reviewedIDs: [])
        XCTAssertEqual(one.safeText, "1 group is a safe match. Accept it now.")
        XCTAssertEqual(one.checkText, "1 group is a look-alike or less certain. Take a look.")

        let many = DeduplicateReviewLanes(
            clusters: [eligible("a"), eligible("b"), uncertain("c"), uncertain("d"), uncertain("e")],
            reviewedIDs: []
        )
        XCTAssertEqual(many.safeText, "2 groups are safe matches. Accept them together.")
        XCTAssertEqual(many.checkText, "3 groups are look-alikes or less certain. Look at each one.")

        let onlySafe = DeduplicateReviewLanes(clusters: [eligible("a")], reviewedIDs: [])
        XCTAssertNil(onlySafe.checkText)
        let onlyCheck = DeduplicateReviewLanes(clusters: [uncertain("a")], reviewedIDs: [])
        XCTAssertNil(onlyCheck.safeText)

        let thousands = DeduplicateReviewLanes(
            clusters: (0..<1_200).map { eligible("g\($0)") },
            reviewedIDs: []
        )
        XCTAssertEqual(
            thousands.safeText,
            "\(1_200.formatted()) groups are safe matches. Accept them together."
        )
    }

    func testDoneTextOnlyWhenEverythingReviewed() {
        let a = eligible("a")
        let b = uncertain("b")

        let all = DeduplicateReviewLanes(clusters: [a, b], reviewedIDs: [a.id, b.id])
        XCTAssertEqual(all.doneText, "Every group has been reviewed.")
        XCTAssertNil(all.safeText)
        XCTAssertNil(all.checkText)

        let partial = DeduplicateReviewLanes(clusters: [a, b], reviewedIDs: [a.id])
        XCTAssertNil(partial.doneText)

        let none = DeduplicateReviewLanes(clusters: [a, b], reviewedIDs: [])
        XCTAssertNil(none.doneText)
    }

    func testCompactTextIsOneLineForEveryCombination() {
        func lanes(safe: Int, check: Int, reviewed: Int) -> DeduplicateReviewLanes {
            var clusters: [DuplicateCluster] = []
            var reviewedIDs: Set<DuplicateCluster.ID> = []
            var eligibleIDs: Set<DuplicateCluster.ID> = []
            for index in 0..<(safe + check + reviewed) {
                let cluster = DuplicateCluster(
                    kind: .exactDuplicate,
                    members: [PhotoCandidate(path: "/dest/c\(index).jpg", size: 1, modificationTime: 0, qualityScore: 1)],
                    suggestedKeeperIDs: [],
                    bytesIfPruned: 0
                )
                clusters.append(cluster)
                if index < safe { eligibleIDs.insert(cluster.id) }
                if index >= safe + check { reviewedIDs.insert(cluster.id) }
            }
            return DeduplicateReviewLanes(clusters: clusters, reviewedIDs: reviewedIDs) { eligibleIDs.contains($0.id) }
        }

        XCTAssertEqual(lanes(safe: 1, check: 0, reviewed: 0).compactText, "1 safe match")
        XCTAssertEqual(lanes(safe: 3, check: 0, reviewed: 0).compactText, "3 safe matches")
        XCTAssertEqual(lanes(safe: 0, check: 1, reviewed: 0).compactText, "1 group to check")
        XCTAssertEqual(lanes(safe: 2, check: 4, reviewed: 1).compactText, "2 safe matches · 4 groups to check")
        XCTAssertEqual(lanes(safe: 0, check: 0, reviewed: 2).compactText, "Every group has been reviewed.")
        XCTAssertNil(lanes(safe: 0, check: 0, reviewed: 0).compactText)
    }

    func testCompactListGivesUpExactlyTheLanesBarHeight() {
        // The bar must cost the group list, never the photo preview.
        for height in [300.0, 700.0, 2_000.0] {
            XCTAssertEqual(
                DeduplicateReviewLayout.compactClusterListHeight(forAvailableHeight: height, lanesBarShown: true),
                DeduplicateReviewLayout.compactClusterListHeight(forAvailableHeight: height)
                    - DesignTokens.DeduplicateLayout.compactLanesBarHeight
            )
        }
    }

    func testEmptyClustersGiveNoText() {
        let lanes = DeduplicateReviewLanes(clusters: [], reviewedIDs: [])
        XCTAssertEqual(lanes.safeGroupCount, 0)
        XCTAssertEqual(lanes.checkGroupCount, 0)
        XCTAssertEqual(lanes.reviewedGroupCount, 0)
        XCTAssertNil(lanes.safeText)
        XCTAssertNil(lanes.checkText)
        XCTAssertNil(lanes.doneText)
    }

    func testLaneIdentifiersMatchContract() {
        XCTAssertEqual(AccessibilityIdentifiers.dedupeLanes, "dedupe.lanes")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeLanesAcceptSafe, "dedupe.lanes.acceptSafe")
        XCTAssertEqual(AccessibilityIdentifiers.dedupeLanesQuickReview, "dedupe.lanes.quickReview")
    }
}
