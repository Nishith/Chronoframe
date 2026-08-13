import Foundation
import XCTest
@testable import ChronoframeCore

/// Covers the free test batch (free-trial step 5, T15).
///
/// The property worth protecting is subtractive execution: what runs is a
/// subset of what was confirmed, whatever the disk did in between.
final class FreeTestBatchPlannerTests: XCTestCase {
    private func transfer(_ name: String, bucket: String) -> PlannedTransfer {
        PlannedTransfer(
            sourcePath: "/Volumes/Card/\(name)",
            destinationPath: "/Volumes/Archive/\(bucket)/\(name)",
            identity: FileIdentity(size: Int64(name.count), digest: "digest-\(name)"),
            dateBucket: bucket,
            isDuplicate: false
        )
    }

    private func plan() -> [PlannedTransfer] {
        // Deliberately not in date order: a real plan comes out in whatever
        // order the source folder was walked.
        [
            transfer("march-b.raf", bucket: "2026-03-02"),
            transfer("january.raf", bucket: "2026-01-11"),
            transfer("march-a.raf", bucket: "2026-03-02"),
            transfer("february.raf", bucket: "2026-02-04"),
        ]
    }

    // MARK: - Proposing

    func testBatchTakesTheOldestFilesFirst() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 2)

        XCTAssertEqual(
            batch.included.map(\.sourcePath),
            ["/Volumes/Card/january.raf", "/Volumes/Card/february.raf"]
        )
        XCTAssertEqual(batch.deferredCount, 2)
    }

    /// Same plan, different walk order, same batch. Without this a re-plan
    /// could propose a different slice of the same library.
    func testBatchDoesNotDependOnPlanOrder() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 3)
        let shuffled = FreeTestBatchPlanner.batch(from: Array(plan().reversed()), limit: 3)

        XCTAssertEqual(batch.included, shuffled.included)
    }

    /// Two files in the same date folder are ordered by path, so the tie is
    /// broken the same way every time.
    func testFilesInOneDateFolderAreOrderedByPath() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 4)

        XCTAssertEqual(
            batch.included.map(\.sourcePath),
            [
                "/Volumes/Card/january.raf",
                "/Volumes/Card/february.raf",
                "/Volumes/Card/march-a.raf",
                "/Volumes/Card/march-b.raf",
            ]
        )
    }

    func testBatchCoveringEverythingHasNothingDeferred() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 99)

        XCTAssertEqual(batch.includedCount, 4)
        XCTAssertEqual(batch.deferredCount, 0)
        XCTAssertTrue(batch.coversWholePlan)
    }

    /// A spent allowance proposes nothing rather than trapping. The caller
    /// decides not to offer; the planner does not crash on the way there.
    func testNoAllowanceProposesAnEmptyBatch() {
        for limit in [0, -1] {
            let batch = FreeTestBatchPlanner.batch(from: plan(), limit: limit)

            XCTAssertTrue(batch.included.isEmpty, "limit \(limit)")
            XCTAssertEqual(batch.deferredCount, 4, "limit \(limit)")
            XCTAssertFalse(batch.coversWholePlan, "limit \(limit)")
        }
    }

    func testEmptyPlanProposesAnEmptyBatch() {
        let batch = FreeTestBatchPlanner.batch(from: [], limit: 10)

        XCTAssertTrue(batch.included.isEmpty)
        XCTAssertEqual(batch.deferredCount, 0)
    }

    func testDateBucketRangeNamesTheSpanTheBatchCovers() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 3)

        XCTAssertEqual(batch.dateBucketRange?.earliest, "2026-01-11")
        XCTAssertEqual(batch.dateBucketRange?.latest, "2026-03-02")
    }

    func testEmptyBatchHasNoDateRangeToReport() {
        XCTAssertNil(FreeTestBatchPlanner.batch(from: [], limit: 10).dateBucketRange)
    }

    // MARK: - Executing exactly what was confirmed

    func testSelectionKeepsOnlyTheConfirmedFiles() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 2)

        let applied = batch.selection.apply(to: plan())

        XCTAssertEqual(applied, batch.included)
        XCTAssertEqual(batch.selection.count, 2)
        XCTAssertFalse(batch.selection.isEmpty)
    }

    /// An empty batch selects nothing, so a caller that reached for it anyway
    /// would copy nothing rather than everything.
    func testSelectionFromAnEmptyBatchSelectsNothing() {
        let selection = FreeTestBatchPlanner.batch(from: plan(), limit: 0).selection

        XCTAssertTrue(selection.isEmpty)
        XCTAssertEqual(selection.count, 0)
        XCTAssertTrue(selection.apply(to: plan()).isEmpty)
    }

    /// The reason a batch carries paths and not a count. A transfer re-plans,
    /// and if new files appeared under the source in the meantime, a
    /// count-limited re-plan would copy files nobody was shown.
    func testFilesThatAppearedAfterConfirmationAreNotCopied() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 2)
        var laterPlan = plan()
        laterPlan.append(transfer("brand-new.raf", bucket: "2026-01-01"))

        let applied = batch.selection.apply(to: laterPlan)

        XCTAssertEqual(applied, batch.included)
        XCTAssertFalse(
            applied.contains { $0.sourcePath.hasSuffix("brand-new.raf") },
            "A file added after the batch was confirmed must not join the run, "
                + "even though its date folder sorts first"
        )
    }

    /// A file replaced in place keeps its path, so a path-only selection would
    /// have copied the new bytes — to a different date folder, if the new
    /// file's date differs. The executor does not catch this: it compares the
    /// source against the hash recorded when the job was planned, and a re-plan
    /// records the new hash, so those agree.
    func testFilesReplacedAfterConfirmationAreDropped() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 2)
        let laterPlan = plan().map { transfer -> PlannedTransfer in
            guard transfer.sourcePath.hasSuffix("january.raf") else { return transfer }
            var replaced = transfer
            replaced.identity = FileIdentity(size: 9_001, digest: "different-content")
            replaced.dateBucket = "2026-07-30"
            replaced.destinationPath = "/Volumes/Archive/2026-07-30/january.raf"
            return replaced
        }

        let applied = batch.selection.apply(to: laterPlan)

        XCTAssertEqual(applied.map(\.sourcePath), ["/Volumes/Card/february.raf"])
    }

    /// The other direction: a file that disappeared is simply not copied. The
    /// run shrinks, which is the safe way for it to be wrong.
    func testFilesThatVanishedAfterConfirmationAreDropped() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 3)
        let laterPlan = plan().filter { !$0.sourcePath.hasSuffix("february.raf") }

        let applied = batch.selection.apply(to: laterPlan)

        XCTAssertEqual(applied.count, 2)
        XCTAssertFalse(applied.contains { $0.sourcePath.hasSuffix("february.raf") })
    }

    /// Applying a selection can never return more than was confirmed, for any
    /// plan at all.
    func testAppliedCountNeverExceedsTheConfirmedCount() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 2)
        let inflatedPlan = plan() + (0..<50).map { transfer("extra-\($0).raf", bucket: "2026-01-01") }

        XCTAssertLessThanOrEqual(batch.selection.apply(to: inflatedPlan).count, batch.includedCount)
    }

    func testSelectionAppliesInTheOrderItWasShown() {
        let batch = FreeTestBatchPlanner.batch(from: plan(), limit: 4)

        let applied = batch.selection.apply(to: Array(plan().reversed()))

        XCTAssertEqual(applied.map(\.sourcePath), batch.included.map(\.sourcePath))
    }
}
