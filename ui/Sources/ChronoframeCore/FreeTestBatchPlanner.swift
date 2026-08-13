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
        FreeTestBatchSelection(sourcePaths: Set(included.map(\.sourcePath)))
    }
}

/// Exactly which files a confirmed batch may copy.
///
/// Held by source path rather than by index or count, so that applying it to a
/// freshly planned set is subtractive: the result is always a subset of what
/// was confirmed.
public struct FreeTestBatchSelection: Equatable, Sendable {
    public let sourcePaths: Set<String>

    public init(sourcePaths: Set<String>) {
        self.sourcePaths = sourcePaths
    }

    public var count: Int { sourcePaths.count }

    public var isEmpty: Bool { sourcePaths.isEmpty }

    /// Keep only the planned transfers this selection names.
    ///
    /// Ordered the same way `FreeTestBatchPlanner` orders a batch, so the run
    /// copies files in the order they were shown.
    public func apply(to transfers: [PlannedTransfer]) -> [PlannedTransfer] {
        FreeTestBatchPlanner.inBatchOrder(
            transfers.filter { sourcePaths.contains($0.sourcePath) }
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

    /// Oldest date folder first, then by source path.
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
