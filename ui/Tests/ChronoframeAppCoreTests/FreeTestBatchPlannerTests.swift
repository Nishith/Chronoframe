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

/// Covers reducing a whole planning result to a confirmed batch (T15).
///
/// Filtering `transfers` and stopping there would leave the run reporting more
/// work than it does, so the counts and histogram are the point here.
final class FreeTestBatchPlanReductionTests: XCTestCase {
    private func transfer(
        _ name: String,
        bucket: String,
        isDuplicate: Bool = false
    ) -> PlannedTransfer {
        PlannedTransfer(
            sourcePath: "/Volumes/Card/\(name)",
            destinationPath: "/Volumes/Archive/\(bucket)/\(bucket)_001.raf",
            identity: FileIdentity(size: Int64(name.count), digest: "digest-\(name)"),
            dateBucket: bucket,
            isDuplicate: isDuplicate
        )
    }

    private func planningResult(_ transfers: [PlannedTransfer]) -> DryRunPlanningResult {
        DryRunPlanningResult(
            discoveredSourceCount: 40,
            destinationIndexedCount: 5,
            sourceHashedCount: 40,
            copyPlan: CopyPlanResult(
                transfers: transfers,
                counts: CopyPlanCounts(
                    alreadyInDestinationCount: 7,
                    newCount: transfers.filter { !$0.isDuplicate }.count,
                    duplicateCount: transfers.filter(\.isDuplicate).count,
                    hashErrorCount: 3
                ),
                warningMessages: [],
                sequenceState: SequenceCounterState()
            )
        )
    }

    private var fullPlan: [PlannedTransfer] {
        [
            transfer("a.raf", bucket: "2026-01-11"),
            transfer("b.raf", bucket: "2026-02-04"),
            transfer("c.raf", bucket: "2026-03-02", isDuplicate: true),
            transfer("d.raf", bucket: "2026-04-09"),
        ]
    }

    func testReducingKeepsOnlyTheConfirmedTransfers() {
        let result = planningResult(fullPlan)
        let batch = FreeTestBatchPlanner.batch(from: fullPlan, limit: 2)

        let reduced = result.reduced(to: batch.selection)

        XCTAssertEqual(reduced.transferCount, 2)
        XCTAssertEqual(
            reduced.transfers.map(\.sourcePath),
            ["/Volumes/Card/a.raf", "/Volumes/Card/b.raf"]
        )
    }

    /// The counts have to follow the plan, or the run reports more work than it
    /// does. Both kinds of planned file move, because both are copied.
    func testReducingRewritesTheCopyCounts() {
        let result = planningResult(fullPlan)
        let batch = FreeTestBatchPlanner.batch(from: fullPlan, limit: 3)

        let reduced = result.reduced(to: batch.selection)

        XCTAssertEqual(reduced.counts.newCount, 2, "a and b are new; c is the duplicate")
        XCTAssertEqual(reduced.counts.duplicateCount, 1)
    }

    /// Discovery facts are not batch facts. A file already in the destination
    /// stays already in the destination however small the batch is.
    func testReducingLeavesDiscoveryCountsAlone() {
        let result = planningResult(fullPlan)
        let batch = FreeTestBatchPlanner.batch(from: fullPlan, limit: 1)

        let reduced = result.reduced(to: batch.selection)

        XCTAssertEqual(reduced.counts.alreadyInDestinationCount, 7)
        XCTAssertEqual(reduced.counts.hashErrorCount, 3)
        XCTAssertEqual(reduced.discoveredSourceCount, 40)
    }

    /// The histogram is what the Run workspace draws. Left alone it would show
    /// bars for dates the batch is not going to touch.
    func testReducingRebuildsTheDateHistogram() {
        let result = planningResult(fullPlan)
        let batch = FreeTestBatchPlanner.batch(from: fullPlan, limit: 2)

        let reduced = result.reduced(to: batch.selection)

        XCTAssertEqual(
            reduced.dateHistogram.map(\.plannedCount).reduce(0, +),
            2,
            "The histogram must total the reduced plan, not the full one"
        )
        XCTAssertFalse(
            reduced.dateHistogram.contains { $0.key.hasPrefix("2026-04") },
            "A date outside the batch must not appear: \(reduced.dateHistogram)"
        )
    }

    func testReducingToAnEmptySelectionPlansNothing() {
        let result = planningResult(fullPlan)

        let reduced = result.reduced(to: FreeTestBatchSelection(confirmedIdentities: [:]))

        XCTAssertEqual(reduced.transferCount, 0)
        XCTAssertEqual(reduced.counts.newCount, 0)
        XCTAssertEqual(reduced.counts.duplicateCount, 0)
        XCTAssertTrue(reduced.dateHistogram.isEmpty)
    }

    /// A batch covering the whole plan changes the counts to the same numbers,
    /// so a confirmed full batch is not quietly different from no batch at all.
    func testReducingToTheWholePlanPreservesItsCounts() {
        let result = planningResult(fullPlan)
        let batch = FreeTestBatchPlanner.batch(from: fullPlan, limit: 99)

        let reduced = result.reduced(to: batch.selection)

        XCTAssertEqual(reduced.transferCount, result.transferCount)
        XCTAssertEqual(reduced.counts.newCount, result.counts.newCount)
        XCTAssertEqual(reduced.counts.duplicateCount, result.counts.duplicateCount)
    }

    /// Review rows describe what was discovered, not what this run copies.
    func testReducingLeavesReviewItemsAlone() {
        var result = planningResult(fullPlan)
        result.previewReviewItems = []
        let batch = FreeTestBatchPlanner.batch(from: fullPlan, limit: 1)

        XCTAssertEqual(result.reduced(to: batch.selection).previewReviewItems.count, 0)
    }
}

/// Saying so when the rebuilt batch is smaller than the confirmed one (T15).
///
/// The selection guarantees a subset, so nothing unseen is ever copied. But a
/// subset can be smaller, and shrinking without a word is the silent
/// truncation this feature exists to avoid.
final class FreeTestBatchShortfallTests: XCTestCase {
    private func transfer(_ name: String) -> PlannedTransfer {
        PlannedTransfer(
            sourcePath: "/Volumes/Card/\(name)",
            destinationPath: "/Volumes/Archive/2026-01-11/\(name)",
            identity: FileIdentity(size: Int64(name.count), digest: "digest-\(name)"),
            dateBucket: "2026-01-11",
            isDuplicate: false
        )
    }

    func testAShortfallSaysHowManyAndWhy() {
        let message = FreeTestBatchPlanner.shortfallMessage(confirmed: 380, copying: 377) ?? ""

        XCTAssertTrue(message.contains("3 files"), message)
        XCTAssertTrue(message.contains("380"), message)
        XCTAssertTrue(message.contains("377"), message)
        XCTAssertTrue(message.contains("originals untouched"), message)
    }

    func testOneMissingFileIsSingular() {
        let message = FreeTestBatchPlanner.shortfallMessage(confirmed: 2, copying: 1) ?? ""

        XCTAssertTrue(message.contains("1 file of the 2"), message)
    }

    /// Nothing to report when everything confirmed is still there.
    func testNoShortfallWhenTheWholeBatchSurvived() {
        XCTAssertNil(FreeTestBatchPlanner.shortfallMessage(confirmed: 380, copying: 380))
    }

    /// A batch that matched nothing has its own outcome and its own message, so
    /// this must not add a second one on top.
    func testAnEmptyRunIsLeftToTheZeroBatchBranch() {
        XCTAssertNil(FreeTestBatchPlanner.shortfallMessage(confirmed: 380, copying: 0))
    }

    /// Defensive: `apply` cannot grow a selection, so this should be
    /// unreachable — but reporting a negative shortfall would be worse than
    /// reporting nothing.
    func testMoreCopiedThanConfirmedReportsNothing() {
        XCTAssertNil(FreeTestBatchPlanner.shortfallMessage(confirmed: 2, copying: 3))
    }

    // MARK: - Which files went missing

    func testMissingPathsNameBothTheVanishedAndTheChanged() {
        let confirmed = [transfer("a.raf"), transfer("b.raf"), transfer("c.raf")]
        let selection = FreeTestBatch(included: confirmed, deferredCount: 0).selection

        var changed = transfer("b.raf")
        changed.identity = FileIdentity(size: 999, digest: "different")
        let rebuilt = [transfer("a.raf"), changed]

        let applied = selection.apply(to: rebuilt)
        XCTAssertEqual(applied.map(\.sourcePath), ["/Volumes/Card/a.raf"])
        XCTAssertEqual(
            selection.missingSourcePaths(after: applied),
            ["/Volumes/Card/b.raf", "/Volumes/Card/c.raf"],
            "b changed and c vanished; both are missing from the run"
        )
    }

    func testNothingIsMissingWhenTheBatchSurvivedIntact() {
        let confirmed = [transfer("a.raf"), transfer("b.raf")]
        let selection = FreeTestBatch(included: confirmed, deferredCount: 0).selection

        XCTAssertTrue(selection.missingSourcePaths(after: confirmed).isEmpty)
    }
}
