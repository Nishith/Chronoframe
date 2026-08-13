import Foundation

// MARK: - The free test batch (free-trial step 5, T15)
//
// When a plan is larger than what is left of the free allowance, refusing
// outright and telling someone to go build a smaller folder in Finder is a bad
// trial. Instead Chronoframe offers to copy as much as the allowance covers.
//
// The rule this file exists to protect: **the reduced plan is never applied
// silently.** A batch is proposed, displayed in full, and executed only after
// it is confirmed — and what executes is exactly what was confirmed, never a
// re-derived set that happens to be the same size.
//
// That second half is why a batch carries explicit source paths rather than a
// count. A transfer re-plans against the disk, and between the proposal and the
// confirmation the source can change. A count-limited re-plan would quietly
// copy a *different* 380 files than the ones on screen. A path selection can
// only ever shrink: files that vanished are dropped, and files that appeared
// are not in the selection, so they cannot join the run.

/// A reduced transfer plan sized to fit the remaining free allowance.
public struct FreeTestBatch: Equatable, Sendable {
    /// The transfers the batch would run, in the order it would run them.
    public let included: [PlannedTransfer]

    /// Planned transfers left out of the batch.
    ///
    /// Nothing records these. They are not queued, not written to the receipt,
    /// and not remembered between runs — the next preview simply finds them
    /// again as new work.
    public let deferredCount: Int

    public init(included: [PlannedTransfer], deferredCount: Int) {
        self.included = included
        self.deferredCount = deferredCount
    }

    public var includedCount: Int { included.count }

    /// True when the batch covers the whole plan, so there is nothing to offer.
    public var coversWholePlan: Bool { deferredCount == 0 }

    /// The earliest and latest date folders the batch touches, for copy that
    /// tells someone which of their photos this is.
    public var dateBucketRange: (earliest: String, latest: String)? {
        guard let earliest = included.map(\.dateBucket).min(),
              let latest = included.map(\.dateBucket).max() else { return nil }
        return (earliest, latest)
    }

    /// The batch as a selection that can be handed back to a later run.
    public var selection: FreeTestBatchSelection {
        FreeTestBatchSelection(
            confirmedIdentities: Dictionary(
                included.map { ($0.sourcePath, $0.identity) },
                // A plan cannot contain one source path twice, so this only
                // fires if that ever stops being true. Keeping the first entry
                // matches batch order and keeps `apply` deterministic.
                uniquingKeysWith: { first, _ in first }
            )
        )
    }
}

/// Exactly which files a confirmed batch may copy.
///
/// Keyed by source path **and** the content identity confirmed at that path, so
/// applying it to a freshly planned set is subtractive: the result is always a
/// subset of what was confirmed.
///
/// Path alone is not enough. A file replaced in place between confirmation and
/// the execution re-plan keeps its path, so a path-only filter would copy the
/// new bytes — which may resolve to a different date and therefore a different
/// destination folder than the one displayed. `TransferExecutor.prepareCopy`
/// does not catch it either: that check compares the source against the hash
/// recorded when the job was planned, and a re-plan records the *new* hash, so
/// the two agree. Identity has to be pinned here, at confirmation time.
///
/// Content identity is the right granularity, not the whole planned transfer. A
/// destination path can legitimately differ between plans — the sequence
/// counter assigns suffixes based on what else is in the folder — and dropping
/// a file over that would refuse work the customer confirmed for no benefit.
public struct FreeTestBatchSelection: Equatable, Sendable {
    /// Source path to the identity that path had when the batch was confirmed.
    public let confirmedIdentities: [String: FileIdentity]

    public init(confirmedIdentities: [String: FileIdentity]) {
        self.confirmedIdentities = confirmedIdentities
    }

    public var count: Int { confirmedIdentities.count }

    public var isEmpty: Bool { confirmedIdentities.isEmpty }

    /// Keep only the planned transfers this selection confirmed, still holding
    /// the same content.
    ///
    /// Ordered the same way `FreeTestBatchPlanner` orders a batch, so the run
    /// copies files in the order they were shown.
    public func apply(to transfers: [PlannedTransfer]) -> [PlannedTransfer] {
        FreeTestBatchPlanner.inBatchOrder(
            transfers.filter { confirmedIdentities[$0.sourcePath] == $0.identity }
        )
    }
}

public enum FreeTestBatchPlanner {
    /// Propose a batch of at most `limit` transfers from `transfers`.
    ///
    /// Pure and total. `limit <= 0` yields an empty batch rather than a
    /// precondition failure: a caller that has nothing left to give should get
    /// an empty offer it can decline to make, not a crash.
    public static func batch(from transfers: [PlannedTransfer], limit: Int) -> FreeTestBatch {
        guard limit > 0 else {
            return FreeTestBatch(included: [], deferredCount: transfers.count)
        }

        let ordered = inBatchOrder(transfers)
        let included = Array(ordered.prefix(limit))
        return FreeTestBatch(
            included: included,
            deferredCount: transfers.count - included.count
        )
    }

    /// Oldest date folder first, then by source path (see `inBatchOrder`).
    ///
    /// Deterministic and independent of how the source folder happened to be
    /// walked, which is what lets the same plan produce the same batch twice —
    /// and lets someone recognise the batch as "the earliest of my photos"
    /// rather than an arbitrary slice.
    static func inBatchOrder(_ transfers: [PlannedTransfer]) -> [PlannedTransfer] {
        transfers.sorted { lhs, rhs in
            if lhs.dateBucket != rhs.dateBucket { return lhs.dateBucket < rhs.dateBucket }
            return lhs.sourcePath < rhs.sourcePath
        }
    }
}

// MARK: - Reducing a plan to a confirmed batch

extension DryRunPlanningResult {
    /// The same planning result with only the confirmed batch left in its copy
    /// plan.
    ///
    /// Filtering `transfers` alone is not enough: the counts and the date
    /// histogram are derived from the plan, and leaving them describing the
    /// full plan would have the run report more work than it is going to do.
    ///
    /// - Parameter namingRules: must match what planning used, because the
    ///   histogram keys are parsed back out of destination filenames. Defaults
    ///   the same way `DryRunPlanner.planAsync` does.
    public func reduced(
        to selection: FreeTestBatchSelection,
        namingRules: PlannerNamingRules = .chronoframeDefault
    ) -> DryRunPlanningResult {
        let kept = selection.apply(to: copyPlan.transfers)

        var reduced = self
        reduced.copyPlan.transfers = kept
        // Both kinds of file end up as planned transfers, so both counts move.
        reduced.copyPlan.counts.newCount = kept.filter { !$0.isDuplicate }.count
        reduced.copyPlan.counts.duplicateCount = kept.filter(\.isDuplicate).count
        reduced.copyPlan.dateHistogram = CopyPlanBuilder.dateHistogram(
            fromDestinationPaths: kept.map(\.destinationPath),
            namingRules: namingRules
        )

        // `alreadyInDestinationCount` and `hashErrorCount` are deliberately
        // untouched. They describe what discovery found, not what this run will
        // copy, and a file that was already in the destination stays already in
        // the destination whether or not the batch includes anything.
        //
        // `previewReviewItems` is untouched for the same reason: it is the
        // record of what was discovered and reviewed. Dropping the rows outside
        // the batch would hide true information about real files rather than
        // clarify what the run does.
        return reduced
    }
}
