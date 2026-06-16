import ChronoframeAppCore
import Foundation
import SwiftUI
import XCTest
@testable import ChronoframeApp

@MainActor
final class RunHistoryViewTests: XCTestCase {
    /// Regression for review rec #4: the revert confirmation dialog
    /// previously hardcoded transfer-revert language ("remove the
    /// files this receipt copied, but only if their contents still
    /// match…") for every receipt kind. Dedupe revert RESTORES files
    /// from the Trash; the wording must reflect that.
    func testConfirmationCopyBranchesByEntryKindForDedupeReceipts() {
        let dedupeEntry = makeEntry(kind: .dedupeAuditReceipt)

        XCTAssertEqual(
            RunHistoryView.confirmationTitle(for: dedupeEntry),
            "Restore deduplicated files?"
        )
        XCTAssertEqual(
            RunHistoryView.confirmationActionLabel(for: dedupeEntry),
            "Restore"
        )
        let message = RunHistoryView.confirmationMessage(for: dedupeEntry)
        XCTAssertTrue(
            message.contains("Trash"),
            "Dedupe revert message must mention the Trash"
        )
        XCTAssertFalse(
            message.contains("remove the files this receipt copied"),
            "Dedupe revert message must not reuse transfer-copy language"
        )
    }

    /// Negative case: the legacy organize transfer audit receipt must
    /// still get the original confirmation copy.
    func testConfirmationCopyKeepsTransferLanguageForAuditReceipts() {
        let transferEntry = makeEntry(kind: .auditReceipt)

        XCTAssertEqual(
            RunHistoryView.confirmationTitle(for: transferEntry),
            "Revert this transfer?"
        )
        XCTAssertEqual(
            RunHistoryView.confirmationActionLabel(for: transferEntry),
            "Revert"
        )
        let message = RunHistoryView.confirmationMessage(for: transferEntry)
        XCTAssertTrue(message.contains("remove the files this receipt copied"))
        XCTAssertTrue(message.contains("contents still match"))
    }

    /// Dedupe restore is affirmative — the primary button must NOT be
    /// red. Transfer revert remains destructive. Pure helper test; no
    /// SwiftUI rendering required.
    func testConfirmationRoleDropsDestructiveForDedupeRestore() {
        let dedupeEntry = makeEntry(kind: .dedupeAuditReceipt)
        let transferEntry = makeEntry(kind: .auditReceipt)

        XCTAssertNil(RunHistoryView.confirmationActionRole(for: dedupeEntry))
        XCTAssertEqual(RunHistoryView.confirmationActionRole(for: transferEntry), .destructive)
    }

    /// `confirmationTitle(for:)` is also called when no entry is
    /// pending (the `.confirmationDialog` modifier evaluates the title
    /// at body construction time). It must default to the transfer
    /// title so the dialog has a stable label even before a receipt
    /// is selected.
    func testConfirmationTitleFallsBackToTransferWhenNoEntryPending() {
        XCTAssertEqual(
            RunHistoryView.confirmationTitle(for: nil),
            "Revert this transfer?"
        )
    }

    // MARK: - Source folder label (design-critique fix #6)

    func testSourceFolderLabelUsesLastPathComponentNotFullVolumePath() {
        // Primary row label must be the folder name, not the entire volume path.
        // /Volumes/Photos_4_27_26/2013 → "2013"
        XCTAssertEqual(
            RunHistoryView.sourceFolderLabel(for: "/Volumes/Photos_4_27_26/2013"),
            "2013"
        )
        // Backup volumes with opaque names → still readable as the leaf name
        XCTAssertEqual(
            RunHistoryView.sourceFolderLabel(for: "/Volumes/Backup_21_12"),
            "Backup_21_12"
        )
        // Deep hierarchy: only the last component
        XCTAssertEqual(
            RunHistoryView.sourceFolderLabel(for: "/Users/alice/Pictures/RAW/2024/January"),
            "January"
        )
    }

    func testArchiveOverviewUsesOnlyTransferReceipts() {
        let dedupeEntry = makeEntry(kind: .dedupeAuditReceipt)
        let reorganizeEntry = makeEntry(kind: .reorganizeAuditReceipt)
        let transferEntry = makeEntry(kind: .auditReceipt)

        let overviewEntries = RunHistoryView.archiveOverviewReceiptEntries(from: [
            dedupeEntry,
            reorganizeEntry,
            transferEntry,
        ])

        XCTAssertEqual(overviewEntries.map(\.kind), [.auditReceipt])
        XCTAssertFalse(
            RunHistoryView.shouldShowArchiveOverview(
                receiptEntries: RunHistoryView.archiveOverviewReceiptEntries(from: [dedupeEntry, reorganizeEntry]),
                totalFramesArchived: 0
            ),
            "Cleanup-only receipts must not render a 0 frames archived overview."
        )
        XCTAssertTrue(
            RunHistoryView.shouldShowArchiveOverview(
                receiptEntries: overviewEntries,
                totalFramesArchived: 12
            )
        )
    }

    private func makeEntry(kind: RunHistoryEntryKind) -> RunHistoryEntry {
        RunHistoryEntry(
            kind: kind,
            title: "Receipt",
            path: "/Volumes/Dest/.organize_logs/receipt.json",
            relativePath: ".organize_logs/receipt.json",
            fileSizeBytes: 100,
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    func testCoordinateToBucketIndexCalculation() {
        let buckets = [
            DateHistogramBucket(key: "2026-01", plannedCount: 5),
            DateHistogramBucket(key: "2026-02", plannedCount: 10),
            DateHistogramBucket(key: "2026-03", plannedCount: 15)
        ]

        let width: CGFloat = 300
        let spacing: CGFloat = 4
        let totalSpacing = spacing * CGFloat(buckets.count - 1)
        let barWidth = (width - totalSpacing) / CGFloat(buckets.count)

        func bucketIndex(for x: CGFloat) -> Int {
            let index = Int(x / (barWidth + spacing))
            return max(0, min(buckets.count - 1, index))
        }

        XCTAssertEqual(bucketIndex(for: 0), 0)
        XCTAssertEqual(bucketIndex(for: 50), 0)
        XCTAssertEqual(bucketIndex(for: 101), 0)
        XCTAssertEqual(bucketIndex(for: 102), 1)
        XCTAssertEqual(bucketIndex(for: 200), 1)
        XCTAssertEqual(bucketIndex(for: 205), 2)
        XCTAssertEqual(bucketIndex(for: 500), 2)
    }

    func testRunHistoryViewTimelineBucketGroupingAndFiltering() {
        let calendar = Calendar.current

        let dateJan15 = calendar.date(from: DateComponents(year: 2023, month: 1, day: 15))!
        let dateFeb15 = calendar.date(from: DateComponents(year: 2023, month: 2, day: 15))!
        let dateJan16 = calendar.date(from: DateComponents(year: 2023, month: 1, day: 16))!

        let entry1 = RunHistoryEntry(kind: .auditReceipt, title: "Run 1", path: "/tmp/1", createdAt: dateJan15)
        let entry2 = RunHistoryEntry(kind: .auditReceipt, title: "Run 2", path: "/tmp/2", createdAt: dateFeb15)
        let entry3 = RunHistoryEntry(kind: .auditReceipt, title: "Run 3", path: "/tmp/3", createdAt: dateJan16)
        let logEntry = RunHistoryEntry(kind: .runLog, title: "Log 1", path: "/tmp/log1", createdAt: dateJan15)

        let allEntries = [entry1, entry2, entry3, logEntry]

        // 1. Grouping
        let receiptEntries = allEntries.filter { $0.kind == .auditReceipt }
        let buckets = RunHistoryView.makeTimelineBuckets(from: receiptEntries)

        XCTAssertEqual(buckets.count, 2)
        XCTAssertEqual(buckets[0].key, "2023-01")
        XCTAssertEqual(buckets[0].plannedCount, 2)
        XCTAssertEqual(buckets[1].key, "2023-02")
        XCTAssertEqual(buckets[1].plannedCount, 1)

        // 2. Filtering
        let filtered1 = RunHistoryView.filterEntries(allEntries, filter: .all, searchText: "", selectedTimelineMonth: "2023-01")
        XCTAssertEqual(filtered1.count, 3)
        XCTAssertTrue(filtered1.contains(entry1))
        XCTAssertTrue(filtered1.contains(entry3))
        XCTAssertTrue(filtered1.contains(logEntry))

        let filtered2 = RunHistoryView.filterEntries(allEntries, filter: .all, searchText: "", selectedTimelineMonth: "2023-02")
        XCTAssertEqual(filtered2.count, 1)
        XCTAssertEqual(filtered2.first, entry2)

        let filteredNone = RunHistoryView.filterEntries(allEntries, filter: .all, searchText: "", selectedTimelineMonth: nil)
        XCTAssertEqual(filteredNone.count, 4)
    }
}
