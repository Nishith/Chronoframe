import ChronoframeAppCore
import ChronoframeCore
import SwiftUI
import XCTest
@testable import ChronoframeApp

@MainActor
final class DeduplicateStatusViewTests: XCTestCase {
    /// `Style` controls the icon glyph + tint. The mapping is the
    /// invariant the consolidation relies on — if it drifts, the eight
    /// migrated states drift with it. Pure enum mapping; no rendering.
    func testStyleIconAndTintMappings() {
        XCTAssertNil(DeduplicateStatusView<EmptyView, EmptyView>.Style.progress.systemImage)
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.success.systemImage,
            "checkmark.circle.fill"
        )
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.restored.systemImage,
            "arrow.uturn.backward.circle.fill"
        )
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.warning.systemImage,
            "exclamationmark.triangle.fill"
        )

        // success and restored share the success tint; warning uses
        // the danger tint. Progress uses the action accent.
        XCTAssertEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.success.tint,
            DeduplicateStatusView<EmptyView, EmptyView>.Style.restored.tint
        )
        XCTAssertNotEqual(
            DeduplicateStatusView<EmptyView, EmptyView>.Style.success.tint,
            DeduplicateStatusView<EmptyView, EmptyView>.Style.warning.tint
        )
    }

    /// Smoke-test: each style renders without crashing for a minimal
    /// configuration. Catches missing required init params or layout
    /// assertions in the shared status surface.
    func testEachStyleRendersWithoutCrashing() {
        let styles: [DeduplicateStatusView<EmptyView, EmptyView>.Style] = [.progress, .success, .restored, .warning]
        for style in styles {
            let view = DeduplicateStatusView<EmptyView, EmptyView>(
                style: style,
                title: "Title",
                message: "Body",
                detail: "12 of 84"
            )
            _ = view.body
        }
    }

    func testStatusViewRendersPrimaryAndSecondaryActions() {
        let view = DeduplicateStatusView(
            style: .success,
            title: "Nothing to deduplicate",
            primary: {
                Button("Scan Again") {}
            },
            secondary: {
                Button("Change Folder") {}
            }
        )

        _ = view.body
    }

    func testCommitFooterCopyAlwaysUsesRecoverableTrashLanguage() {
        XCTAssertEqual(
            DeduplicateView.commitFooterTitle(fileCount: 2, hardDelete: false),
            "2 files will be moved to Trash"
        )
        XCTAssertEqual(
            DeduplicateView.commitFooterTitle(fileCount: 1, hardDelete: true),
            "1 file will be moved to Trash"
        )

        let trashDetail = DeduplicateView.commitFooterDetail(byteCount: 1_048_576, hardDelete: false)
        XCTAssertTrue(trashDetail.contains("recoverable"))
        XCTAssertFalse(trashDetail.contains("permanently"))

        let hardDeleteDetail = DeduplicateView.commitFooterDetail(byteCount: 1_048_576, hardDelete: true)
        XCTAssertTrue(hardDeleteDetail.contains("recoverable"))
        XCTAssertFalse(hardDeleteDetail.contains("permanently"))
    }

    /// With nothing selected yet, the footer must guide instead of printing
    /// the literal zero forms ("0 files will be moved to Trash", and
    /// ByteCountFormatter's "Zero KB recoverable").
    func testCommitFooterZeroStateGuidesInsteadOfPrintingZeroForms() {
        XCTAssertEqual(
            DeduplicateView.commitFooterTitle(fileCount: 0, hardDelete: false),
            "Nothing will move to Trash yet"
        )
        let zeroDetail = DeduplicateView.commitFooterDetail(byteCount: 0, hardDelete: false)
        XCTAssertFalse(zeroDetail.contains("Zero"))
        XCTAssertFalse(zeroDetail.contains("KB"))
        XCTAssertEqual(zeroDetail, "Accept a group's suggestion to select its extra copies.")
    }

    func testCommitFooterAccessibilityValueSpeaksSummaryAndReviewProgress() {
        XCTAssertEqual(
            DeduplicateView.commitFooterAccessibilityValue(
                title: "Nothing will move to Trash yet",
                detail: "Accept a group's suggestion to select its extra copies.",
                reviewedCount: 0,
                suggestedCount: 12
            ),
            "Nothing will move to Trash yet, Accept a group's suggestion to select its extra copies., 0 groups reviewed, 12 still suggested"
        )
        XCTAssertEqual(
            DeduplicateView.commitFooterAccessibilityValue(
                title: "1 file will be moved to Trash",
                detail: "≈ 1 MB recoverable",
                reviewedCount: 1,
                suggestedCount: 0
            ),
            "1 file will be moved to Trash, ≈ 1 MB recoverable, 1 group reviewed, 0 still suggested"
        )
    }

    func testCommittingTitleReportsTrashProgressAndFallsBackBeforeTotalKnown() {
        // Once the executor reports a total, the title names the count.
        XCTAssertEqual(DeduplicateView.committingTitle(fileCount: 1), "Moving 1 file to Trash…")
        XCTAssertEqual(DeduplicateView.committingTitle(fileCount: 5), "Moving 5 files to Trash…")
        // Before `.started` lands (total still 0) the title omits the count
        // rather than claiming "0 files".
        XCTAssertEqual(DeduplicateView.committingTitle(fileCount: 0), "Moving files to Trash…")
    }

    func testDeduplicateReviewLayoutSwitchesAtConfiguredBreakpoint() {
        XCTAssertEqual(
            DeduplicateReviewLayout.mode(forWidth: DesignTokens.DeduplicateLayout.reviewWideBreakpoint - 1),
            .compact
        )
        XCTAssertEqual(
            DeduplicateReviewLayout.mode(forWidth: DesignTokens.DeduplicateLayout.reviewWideBreakpoint),
            .wide
        )
        XCTAssertEqual(
            DeduplicateReviewLayout.mode(forWidth: DesignTokens.DeduplicateLayout.reviewWideBreakpoint + 1),
            .wide
        )
    }

    // MARK: - Breakpoint value guard (design-critique fix #3)

    func testReviewLayoutBreakpointIs700SoHorizontalLayoutActivatesAboveColumnMinimums() {
        // The breakpoint was lowered from 840 → 700. The HSplitView column
        // minimums are 260 (list) + 420 (detail) = 680pt; 700 gives a safe
        // margin while still activating wide layout on any window wider than
        // the 900pt minimum (900 – 248pt sidebar = 652pt < 700 → compact).
        XCTAssertEqual(DesignTokens.DeduplicateLayout.reviewWideBreakpoint, 700, accuracy: 0.5)
        XCTAssertEqual(DeduplicateReviewLayout.mode(forWidth: 700), .wide)
        XCTAssertEqual(DeduplicateReviewLayout.mode(forWidth: 699), .compact)
        // Minimum window (652pt content) stays in compact — no column overflow
        XCTAssertEqual(DeduplicateReviewLayout.mode(forWidth: 652), .compact)
    }

    func testMemberNavigationMovesToNextAndPreviousPhoto() {
        let members = [
            PhotoCandidate(path: "/photos/a.jpg", size: 1, modificationTime: 0),
            PhotoCandidate(path: "/photos/b.jpg", size: 1, modificationTime: 0),
            PhotoCandidate(path: "/photos/c.jpg", size: 1, modificationTime: 0),
        ]

        XCTAssertEqual(
            DeduplicateMemberNavigation.focusedPath(afterMoving: 1, from: "/photos/a.jpg", through: members),
            "/photos/b.jpg"
        )
        XCTAssertEqual(
            DeduplicateMemberNavigation.focusedPath(afterMoving: -1, from: "/photos/b.jpg", through: members),
            "/photos/a.jpg"
        )
    }

    func testMemberNavigationWrapsWithinCluster() {
        let members = [
            PhotoCandidate(path: "/photos/a.jpg", size: 1, modificationTime: 0),
            PhotoCandidate(path: "/photos/b.jpg", size: 1, modificationTime: 0),
            PhotoCandidate(path: "/photos/c.jpg", size: 1, modificationTime: 0),
        ]

        XCTAssertEqual(
            DeduplicateMemberNavigation.focusedPath(afterMoving: 1, from: "/photos/c.jpg", through: members),
            "/photos/a.jpg"
        )
        XCTAssertEqual(
            DeduplicateMemberNavigation.focusedPath(afterMoving: -1, from: "/photos/a.jpg", through: members),
            "/photos/c.jpg"
        )
    }

    func testMemberNavigationStartsFromFirstPhotoWhenFocusIsMissing() {
        let members = [
            PhotoCandidate(path: "/photos/a.jpg", size: 1, modificationTime: 0),
            PhotoCandidate(path: "/photos/b.jpg", size: 1, modificationTime: 0),
        ]

        XCTAssertEqual(
            DeduplicateMemberNavigation.focusedPath(afterMoving: 1, from: nil, through: members),
            "/photos/b.jpg"
        )
        XCTAssertEqual(
            DeduplicateMemberNavigation.focusedPath(afterMoving: -1, from: "/photos/missing.jpg", through: members),
            "/photos/b.jpg"
        )
    }

    // MARK: - Commit button density (design-critique fix #1)

    func testCommitDensityFullLabelIncludesFileCountForClearerDestructiveAction() {
        XCTAssertEqual(CommitFooterButtonDensity.full.commitTitle(fileCount: 1), "Move 1 File to Trash")
        XCTAssertEqual(CommitFooterButtonDensity.full.commitTitle(fileCount: 4), "Move 4 Files to Trash")
        // Zero files → fallback without count (edge case; button should be disabled)
        XCTAssertEqual(CommitFooterButtonDensity.full.commitTitle(fileCount: 0), "Move to Trash")
        // Compact mode always omits the count to save space
        XCTAssertEqual(CommitFooterButtonDensity.compact.commitTitle(fileCount: 99), "Move to Trash")
    }

    func testBulkAcceptLabelMatchesHighConfidenceOnlyBehavior() {
        XCTAssertEqual(CommitFooterButtonDensity.full.acceptAllTitle, "Accept All Safe")
        XCTAssertEqual(CommitFooterButtonDensity.compact.acceptAllTitle, "Accept Safe")
    }

    /// One confidence vocabulary across the review surface: the filter tabs
    /// and the row badge must use the same tier words, and the bulk-accept
    /// button's "Safe" must be the same word as the high tier — otherwise
    /// the user cannot connect the button to the tab it operates on.
    func testConfidenceVocabularyIsUnifiedAcrossFilterBadgeAndBulkAction() {
        XCTAssertEqual(DedupeClusterConfidenceFilter.high.label, "Safe")
        XCTAssertEqual(DedupeClusterConfidenceFilter.medium.label, "Check")
        XCTAssertEqual(DedupeClusterConfidenceFilter.low.label, "Risky")

        XCTAssertEqual(MatchReasonFormatter.confidenceLabel(.high), DedupeClusterConfidenceFilter.high.label)
        XCTAssertEqual(MatchReasonFormatter.confidenceLabel(.medium), DedupeClusterConfidenceFilter.medium.label)
        XCTAssertEqual(MatchReasonFormatter.confidenceLabel(.low), DedupeClusterConfidenceFilter.low.label)

        XCTAssertTrue(
            CommitFooterButtonDensity.full.acceptAllTitle.contains(DedupeClusterConfidenceFilter.high.label)
        )
    }

    /// Review entry is safest-first: exact duplicates lead, then bursts,
    /// near-duplicates, and edited variants — matching the list's visual
    /// grouping so default focus and "next" follow what the user sees.
    /// Order within a kind is preserved (stable).
    func testReviewOrderSortsSafestKindFirstAndIsStable() {
        func cluster(_ kind: ClusterKind, path: String) -> DuplicateCluster {
            DuplicateCluster(
                kind: kind,
                members: [PhotoCandidate(path: path, size: 1, modificationTime: 0, qualityScore: 0.5)],
                suggestedKeeperIDs: [],
                bytesIfPruned: 0
            )
        }

        let scannerOrder = [
            cluster(.editedVariant, path: "/e1"),
            cluster(.nearDuplicate, path: "/n1"),
            cluster(.exactDuplicate, path: "/x1"),
            cluster(.burst, path: "/b1"),
            cluster(.exactDuplicate, path: "/x2"),
        ]

        let sorted = DedupeReviewOrder.sorted(scannerOrder)
        XCTAssertEqual(
            sorted.map { $0.members[0].path },
            ["/x1", "/x2", "/b1", "/n1", "/e1"]
        )
    }

    // MARK: - Quality / sharpness labels (design-critique fix #2)

    func testClusterDetailQualityLabelCoversAllFiveTiersWithCorrectDotCount() {
        let cases: [(Double, Int, String)] = [
            (0.85, 5, "Excellent"),
            (0.80, 5, "Excellent"),  // lower boundary of Excellent
            (0.70, 4, "Good"),
            (0.60, 4, "Good"),       // lower boundary of Good
            (0.50, 3, "Fair"),
            (0.40, 3, "Fair"),       // lower boundary of Fair
            (0.30, 2, "Poor"),
            (0.20, 2, "Poor"),       // lower boundary of Poor
            (0.10, 1, "Very poor"),
            (0.00, 1, "Very poor"),
        ]
        for (score, expectedDots, expectedLabel) in cases {
            let (dots, label) = ClusterDetailPane.qualityLabel(score)
            XCTAssertEqual(dots, expectedDots, "dots for score \(score)")
            XCTAssertEqual(label, expectedLabel, "label for score \(score)")
        }
    }

    func testClusterDetailSharpnessLabelCoversThreeTiersAtBoundaries() {
        XCTAssertEqual(ClusterDetailPane.sharpnessLabel(0.75), "Sharp")
        XCTAssertEqual(ClusterDetailPane.sharpnessLabel(0.50), "Sharp")    // lower boundary
        XCTAssertEqual(ClusterDetailPane.sharpnessLabel(0.35), "Soft")
        XCTAssertEqual(ClusterDetailPane.sharpnessLabel(0.25), "Soft")     // lower boundary
        XCTAssertEqual(ClusterDetailPane.sharpnessLabel(0.10), "Motion blur")
        XCTAssertEqual(ClusterDetailPane.sharpnessLabel(0.00), "Motion blur")
    }

    func testCompactClusterListHeightClampsWithinConfiguredRange() {
        XCTAssertEqual(
            DeduplicateReviewLayout.compactClusterListHeight(forAvailableHeight: 300),
            DesignTokens.DeduplicateLayout.compactClusterListMinHeight,
            accuracy: 0.5
        )
        XCTAssertEqual(
            DeduplicateReviewLayout.compactClusterListHeight(forAvailableHeight: 2_000),
            DesignTokens.DeduplicateLayout.compactClusterListMaxHeight,
            accuracy: 0.5
        )
        let middle = DeduplicateReviewLayout.compactClusterListHeight(forAvailableHeight: 700)
        XCTAssertGreaterThan(middle, DesignTokens.DeduplicateLayout.compactClusterListMinHeight)
        XCTAssertLessThan(middle, DesignTokens.DeduplicateLayout.compactClusterListMaxHeight)
    }

    func testDetailPreviewResizeBoundsPreservePreviewSpace() {
        let availableHeight: CGFloat = 900
        let bounds = DeduplicateDetailPreviewLayout.thumbnailStripHeightBounds(forAvailableHeight: availableHeight)

        XCTAssertEqual(bounds.lowerBound, DeduplicateDetailPreviewLayout.minimumThumbnailStripHeight, accuracy: 0.5)
        XCTAssertLessThanOrEqual(bounds.upperBound, DeduplicateDetailPreviewLayout.maximumThumbnailStripHeight)
        let remainingPreviewHeight = availableHeight - DeduplicateDetailPreviewLayout.resizeHandleHeight - bounds.upperBound
        XCTAssertGreaterThanOrEqual(
            remainingPreviewHeight + 0.5,
            DeduplicateDetailPreviewLayout.minimumPreviewHeight
        )

        XCTAssertEqual(
            DeduplicateDetailPreviewLayout.clampedThumbnailStripHeight(10, availableHeight: availableHeight),
            bounds.lowerBound,
            accuracy: 0.5
        )
        XCTAssertEqual(
            DeduplicateDetailPreviewLayout.clampedThumbnailStripHeight(1_000, availableHeight: availableHeight),
            bounds.upperBound,
            accuracy: 0.5
        )
    }

    func testDetailPreviewThumbnailSizeGrowsWithStripHeight() {
        let compact = DeduplicateDetailPreviewLayout.thumbnailSize(forStripHeight: 126)
        let expanded = DeduplicateDetailPreviewLayout.thumbnailSize(forStripHeight: 260)

        XCTAssertGreaterThan(expanded, compact)
        XCTAssertGreaterThanOrEqual(compact, DeduplicateDetailPreviewLayout.minimumThumbnailSize)
        XCTAssertLessThanOrEqual(expanded, DeduplicateDetailPreviewLayout.maximumThumbnailSize)
    }

    func testCompletedStatusCopyKeepsPartialFailuresVisuallySeparate() {
        let copy = DeduplicateView.completedStatusCopy(for: DeduplicateCommitSummary(
            deletedCount: 3,
            failedCount: 1,
            bytesReclaimed: 1_048_576,
            receiptPath: "/tmp/receipt.json",
            hardDelete: false
        ))

        XCTAssertEqual(copy.message, "Moved 3 files to Trash · 1 MB recoverable")
        XCTAssertEqual(copy.warning, "1 item failed — see Run History for details.")
    }

    func testRevertedStatusCopyKeepsPartialFailuresVisuallySeparate() {
        let copy = DeduplicateView.revertedStatusCopy(for: DeduplicateCommitSummary(
            deletedCount: 2,
            failedCount: 3,
            bytesReclaimed: 1_048_576,
            receiptPath: "/tmp/receipt.json",
            hardDelete: false
        ))

        XCTAssertEqual(copy.message, "Restored 2 files · 1 MB returned to the destination")
        XCTAssertEqual(copy.warning, "3 items could not be restored — see Run History for details.")
    }

    func testMatchReasonFormatterExplainsConfidenceReasonsWarningsAndKeepers() {
        let burst = MatchReason(
            timeDeltaSeconds: 12,
            averageVisionDistance: 0.08,
            minVisionDistance: 0.04,
            averageDhashDistance: 2,
            kind: .burst
        )
        let annotation = ClusterAnnotation(
            confidence: .high,
            matchReason: burst,
            keeperReason: KeeperReason(factors: [
                .betterOverallQuality(delta: 0.21),
                .eyesOpen,
                .largerFile(delta: 1_048_576),
            ]),
            warnings: [.differentFraming(cropDelta: 0.24)]
        )

        XCTAssertEqual(MatchReasonFormatter.summary(MatchReason(kind: .exactDuplicate)), "Identical file content")
        XCTAssertEqual(MatchReasonFormatter.summary(MatchReason(kind: .editedVariant)), "Edited version of the same photo")
        XCTAssertEqual(MatchReasonFormatter.summary(burst), "Taken 12s apart, 92% visually similar")
        XCTAssertEqual(MatchReasonFormatter.oneLiner(annotation), "92% similar, 12s apart")
        XCTAssertEqual(
            MatchReasonFormatter.keeperSummary(annotation.keeperReason!),
            "Kept: better quality (+0.21), eyes open, larger file (+1 MB)"
        )
        XCTAssertEqual(MatchReasonFormatter.warningSummary(annotation.warnings[0]), "Different framing (24% crop difference)")
        XCTAssertEqual(MatchReasonFormatter.warningSummary(.largeTimeGap(seconds: 90)), "Taken 1.5 min apart")
        XCTAssertEqual(MatchReasonFormatter.confidenceLabel(.high), "Safe")
        XCTAssertEqual(MatchReasonFormatter.confidenceLabel(.medium), "Check")
        XCTAssertEqual(MatchReasonFormatter.confidenceLabel(.low), "Risky")
    }

    func testDeduplicateAccessibilityTextNamesSuggestedGroupsWithStateAndWarnings() {
        let cluster = makeAccessibilityCluster(
            confidence: .low,
            warning: .differentPeople(faceCountDelta: 1)
        )

        XCTAssertEqual(
            DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster),
            "Near duplicates group, 2 photos, low confidence, suggested keeper keeper, needs careful review"
        )

        let rowValue = DeduplicateAccessibilityText.clusterRowValue(
            cluster: cluster,
            isApproved: false,
            recoverableBytes: 1_048_576
        )
        XCTAssertTrue(rowValue.hasPrefix("Suggested, not reviewed. 1 MB reclaimable."))
        XCTAssertTrue(rowValue.contains("visually similar"))

        XCTAssertEqual(
            DeduplicateAccessibilityText.rapidTriageLabel(
                cluster: cluster,
                currentIndex: 1,
                totalCount: 4
            ),
            "Group 2 of 4, 2 photos, low confidence, suggested keeper keeper, needs careful review"
        )
    }

    func testDeduplicateAccessibilityTextNamesMemberDecisionAndSelectionState() {
        let cluster = makeAccessibilityCluster(confidence: .high)
        let keeper = cluster.members[0]
        let duplicate = cluster.members[1]

        XCTAssertEqual(
            DeduplicateAccessibilityText.memberLabel(member: keeper, isSuggestedKeeper: true),
            "keeper, suggested keeper"
        )
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberLabel(member: duplicate, isSuggestedKeeper: false),
            "duplicate"
        )
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberValue(
                decision: .keep,
                isFocused: true,
                confidence: cluster.annotation?.confidence
            ),
            "Marked keep, selected, high confidence group"
        )
        XCTAssertEqual(
            DeduplicateAccessibilityText.memberValue(
                decision: .delete,
                isFocused: false,
                confidence: nil
            ),
            "Marked delete"
        )
    }

    private func makeAccessibilityCluster(
        confidence: ConfidenceLevel,
        warning: SafetyWarning? = nil
    ) -> DuplicateCluster {
        DuplicateCluster(
            kind: .nearDuplicate,
            members: [
                PhotoCandidate(path: "/Photos/keeper.jpg", size: 2_000_000, modificationTime: 0, qualityScore: 0.9),
                PhotoCandidate(path: "/Photos/duplicate.jpg", size: 1_048_576, modificationTime: 0, qualityScore: 0.4),
            ],
            suggestedKeeperIDs: ["/Photos/keeper.jpg"],
            bytesIfPruned: 1_048_576,
            annotation: ClusterAnnotation(
                confidence: confidence,
                matchReason: MatchReason(
                    timeDeltaSeconds: 12,
                    averageVisionDistance: 0.08,
                    kind: .nearDuplicate
                ),
                warnings: warning.map { [$0] } ?? []
            )
        )
    }

    /// The metadata panel leads with the capture date (how people recognize a
    /// photo), with the filename demoted to — but never removed from — an
    /// evidence row, since " copy" suffixes carry real triage signal.
    func testInspectorTitleLeadsWithCaptureDateAndKeepsFileNameAsEvidence() throws {
        let locale = Locale(identifier: "en_US_POSIX")
        let timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))

        // A fixed instant: 2026-05-23 10:48:00 UTC.
        let captured = Date(timeIntervalSince1970: 1_779_533_280)
        let title = DeduplicateInspectorText.title(
            forCaptureDate: captured, locale: locale, timeZone: timeZone
        )
        XCTAssertTrue(title.contains("May 23, 2026"), "Title should lead with the capture date, got: \(title)")
        XCTAssertTrue(title.contains("10:48"), "Title should include the capture time, got: \(title)")

        // No capture date: state it plainly instead of showing a bare dash or
        // falling back to the filename as the headline.
        XCTAssertEqual(
            DeduplicateInspectorText.title(forCaptureDate: nil, locale: locale, timeZone: timeZone),
            "Capture date unknown"
        )

        XCTAssertEqual(
            DeduplicateInspectorText.fileName(forPath: "/Photos/2026/daniel-stiel-dlkVbwOITY8-unsplash copy.jpg"),
            "daniel-stiel-dlkVbwOITY8-unsplash copy.jpg"
        )
    }
}
