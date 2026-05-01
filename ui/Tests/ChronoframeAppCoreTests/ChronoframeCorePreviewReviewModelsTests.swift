import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCorePreviewReviewModelsTests: XCTestCase {
    func testUserVisibleTitlesCoverAllReviewStates() {
        XCTAssertEqual(
            DateResolutionSource.allCases.map(\.title),
            ["Photo Metadata", "Filename", "Created Date", "Modified Date", "Edited", "Unknown"]
        )
        XCTAssertEqual(
            DateResolutionConfidence.allCases.map(\.title),
            ["High", "Medium", "Low", "Unknown"]
        )
        XCTAssertEqual(
            PreviewReviewStatus.allCases.map(\.title),
            ["Ready", "Already There", "Duplicate", "Needs Attention"]
        )
        XCTAssertEqual(
            PreviewReviewIssueKind.allCases.map(\.title),
            ["Unknown date", "Low confidence date", "Duplicate", "Already in destination", "Could not read file"]
        )
    }

    func testReviewOverrideNormalizesEventNamesAndAppliesDateOnlyWhenPresent() {
        let identity = FileIdentity(size: 12, digest: "abc")
        let original = ResolvedMediaDate(date: Date(timeIntervalSince1970: 10), source: .filename, confidence: .medium)
        let overrideDate = Date(timeIntervalSince1970: 20)

        XCTAssertEqual(ReviewOverride.normalizedEventName("  Birthday  "), "Birthday")
        XCTAssertNil(ReviewOverride.normalizedEventName("   "))
        XCTAssertEqual(original.applying(nil), original)
        XCTAssertEqual(
            original.applying(ReviewOverride(identity: identity, sourcePath: "/source/a.jpg", eventName: "  Beach  ")),
            original
        )

        let overridden = original.applying(
            ReviewOverride(identity: identity, sourcePath: "/source/a.jpg", captureDate: overrideDate)
        )
        XCTAssertEqual(overridden.date, overrideDate)
        XCTAssertEqual(overridden.source, .userOverride)
        XCTAssertEqual(overridden.confidence, .high)
    }

    func testPreviewReviewSummaryCountsEveryStatusAndIssue() {
        let items = [
            item("/ready.jpg", status: .ready, issues: []),
            item("/unknown.jpg", status: .ready, issues: [.unknownDate]),
            item("/low.jpg", status: .ready, issues: [.lowConfidenceDate]),
            item("/duplicate.jpg", status: .duplicate, issues: [.duplicate]),
            item("/existing.jpg", status: .alreadyInDestination, issues: [.alreadyInDestination]),
            item("/broken.jpg", status: .hashError, issues: [.hashError]),
        ]

        XCTAssertEqual(items[0].id, "/ready.jpg")
        XCTAssertFalse(items[0].needsAttention)
        XCTAssertTrue(items[1].needsAttention)
        XCTAssertTrue(items[2].needsAttention)
        XCTAssertTrue(items[5].needsAttention)

        let summary = PreviewReviewSummary(items: items)
        XCTAssertEqual(summary.totalCount, 6)
        XCTAssertEqual(summary.readyCount, 3)
        XCTAssertEqual(summary.needsAttentionCount, 3)
        XCTAssertEqual(summary.unknownDateCount, 1)
        XCTAssertEqual(summary.lowConfidenceDateCount, 1)
        XCTAssertEqual(summary.duplicateCount, 1)
        XCTAssertEqual(summary.alreadyInDestinationCount, 1)
        XCTAssertEqual(summary.hashErrorCount, 1)
    }

    func testEventSuggestionsSplitByBucketAndGapAndSuppressGenericFolders() {
        let sourceRoot = "/library/source"
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let candidates = [
            candidate("/library/source/DCIM/a.jpg", root: sourceRoot, date: base, bucket: "2024-04-30"),
            candidate("/library/source/Camera/b.jpg", root: sourceRoot, date: base.addingTimeInterval(60), bucket: "2024-04-30"),
            candidate("/library/source/Beach/c.jpg", root: sourceRoot, date: base.addingTimeInterval(9 * 60 * 60), bucket: "2024-04-30"),
            candidate("/library/source/Beach/d.jpg", root: sourceRoot, date: base.addingTimeInterval(9 * 60 * 60), bucket: "2024-04-30"),
            candidate("/library/source/Zoo/e.jpg", root: sourceRoot, date: base.addingTimeInterval(9 * 60 * 60 + 120), bucket: "2024-04-30"),
            candidate("/library/source/Beta/f.jpg", root: sourceRoot, date: base, bucket: "2024-05-01"),
            candidate("/library/source/Alpha/g.jpg", root: sourceRoot, date: base, bucket: "2024-05-01"),
            candidate("/library/source/root-file.jpg", root: sourceRoot, date: base, bucket: "2024-05-02"),
        ]

        let suggestions = EventSuggestionEngine.suggestions(for: candidates)

        XCTAssertTrue(EventSuggestionEngine.suggestions(for: []).isEmpty)
        XCTAssertEqual(suggestions["/library/source/DCIM/a.jpg"]?.groupID, "2024-04-30-1")
        XCTAssertNil(suggestions["/library/source/DCIM/a.jpg"]?.suggestedName)
        XCTAssertEqual(suggestions["/library/source/DCIM/a.jpg"]?.source, .timeCluster)
        XCTAssertEqual(suggestions["/library/source/DCIM/a.jpg"]?.confidence, .low)

        XCTAssertEqual(suggestions["/library/source/Beach/c.jpg"]?.groupID, "2024-04-30-2")
        XCTAssertEqual(suggestions["/library/source/Beach/c.jpg"]?.suggestedName, "Beach")
        XCTAssertEqual(suggestions["/library/source/Beach/c.jpg"]?.source, .sourceFolder)
        XCTAssertEqual(suggestions["/library/source/Beach/c.jpg"]?.confidence, .medium)

        XCTAssertEqual(suggestions["/library/source/Beta/f.jpg"]?.suggestedName, "Alpha")
        XCTAssertNil(suggestions["/library/source/root-file.jpg"]?.suggestedName)
    }

    private func item(
        _ path: String,
        status: PreviewReviewStatus,
        issues: [PreviewReviewIssueKind]
    ) -> PreviewReviewItem {
        PreviewReviewItem(
            sourcePath: path,
            identityRawValue: nil,
            resolvedDate: nil,
            dateSource: .unknown,
            dateConfidence: .unknown,
            plannedDestinationPath: nil,
            status: status,
            issues: issues
        )
    }

    private func candidate(
        _ path: String,
        root: String,
        date: Date,
        bucket: String
    ) -> EventSuggestionCandidate {
        EventSuggestionCandidate(
            sourcePath: path,
            sourceRoot: root,
            capturedAt: date,
            dateBucket: bucket
        )
    }
}
