#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Trial ledger reconciliation (free-trial step 3)
//
// Step 4 of reserve → mutate → finalize → reconcile.
//
// A reservation left open by a crash, a cancellation, or a stream that ended
// without a final event stays charged AT ITS FULL RESERVED AMOUNT — that falls
// out of the ledger's usage query, not out of a special case. This file is what
// eventually closes it, by looking at the durable evidence the run left behind
// and finalizing the reservation with the count that actually happened.
//
// `MutationRecoveryCoordinator` (Core) stays completely ignorant of the ledger.
// Reconciliation runs AFTER it, so the receipts and journals it consolidates are
// already in their settled state by the time they are read here.
//
// THREE RULES, all load-bearing:
//
//   1. An unreachable destination leaves the reservation OPEN and fully
//      charged. Never infer that an inaccessible path means nothing happened —
//      a sandbox denial and an unmounted volume look nothing like an empty run.
//   2. Reconciliation is idempotent. `finalize` only moves `open → finalized`,
//      so a second pass cannot change a settled row.
//   3. Nothing here deletes receipts, journals, or quarantine paths. This is a
//      reader.

/// What the evidence on disk proves about one open reservation.
///
/// Only `.completed` settles a reservation, and it means something stricter
/// than "here is a count": it means the evidence is FINAL and no later pass
/// could legitimately arrive at a different number. Everything else leaves the
/// reservation open and fully charged, because `finalize` is one-way — once a
/// reservation is settled, a later, truer count can never correct it.
public enum TrialReconciliationOutcome: Sendable, Equatable {
    /// The evidence is final: exactly this many mutations landed, and no more
    /// can land under this reservation.
    case completed(count: Int)
    /// The destination could not be read, or its evidence could not be decoded.
    /// Never confuse this with an empty run.
    case unreachable
    /// The evidence is readable but not final — the run can still make progress,
    /// so a count taken now would be premature. A later pass retries.
    case unsettled
    /// No evidence belonging to this reservation lives at this destination.
    case notApplicable
}

/// Reads the durable proof of what a run actually did.
///
/// A protocol so the reconciler's decisions are testable without a filesystem,
/// and so the I/O stays in one place.
public protocol TrialReconciliationEvidence: Sendable {
    func outcome(
        for reservation: OpenReservation,
        destinationRoot: URL
    ) -> TrialReconciliationOutcome
}

public protocol TrialLedgerReconciling: Sendable {
    /// Settle every open reservation belonging to `destinationRoot`.
    func reconcile(destinationRoot: URL)
}

public struct TrialLedgerReconciler: TrialLedgerReconciling {
    private let ledger: any TrialLedger
    private let evidence: any TrialReconciliationEvidence

    public init(
        ledger: any TrialLedger,
        evidence: any TrialReconciliationEvidence = FileSystemTrialReconciliationEvidence()
    ) {
        self.ledger = ledger
        self.evidence = evidence
    }

    public func reconcile(destinationRoot: URL) {
        // A ledger that cannot be read reconciles nothing. It must not throw
        // into the recovery path: filesystem recovery has already run and its
        // result must reach the caller regardless of trial bookkeeping.
        guard let open = try? ledger.openReservations() else { return }

        let root = destinationRoot.standardizedFileURL.resolvingSymlinksInPath().path
        for reservation in open {
            // A reservation with no destination, or one belonging elsewhere,
            // is not this pass's to settle. It stays open — and stays charged —
            // until a pass for its own destination runs.
            guard let reserved = reservation.destinationRoot,
                  URL(fileURLWithPath: reserved, isDirectory: true)
                      .standardizedFileURL.resolvingSymlinksInPath().path == root
            else {
                continue
            }

            switch evidence.outcome(for: reservation, destinationRoot: destinationRoot) {
            case .unreachable, .unsettled, .notApplicable:
                continue
            case let .completed(count):
                // `finalize` clamps into `0...reserved_count` and only acts on
                // an open row, so this is safe to repeat and cannot charge more
                // than the gate authorized.
                try? ledger.finalize(runID: reservation.runID, actualCount: count)
            }
        }
    }
}

// MARK: - Filesystem evidence

/// Reads what actually happened from the destination's own durable artifacts.
public struct FileSystemTrialReconciliationEvidence: TrialReconciliationEvidence {
    private let presenceChecker: any FilesystemPresenceChecking

    public init(
        presenceChecker: any FilesystemPresenceChecking = POSIXFilesystemPresenceChecker()
    ) {
        self.presenceChecker = presenceChecker
    }

    /// `FileManager` is not `Sendable`, so it is used directly rather than
    /// stored — this type has to cross into whatever context recovery runs on.
    /// Nothing here mutates the filesystem, and the injectable seam that
    /// actually matters is `presenceChecker`, which decides reachability and so
    /// decides whether a reservation stays charged.
    private var fileManager: FileManager { .default }

    public func outcome(
        for reservation: OpenReservation,
        destinationRoot: URL
    ) -> TrialReconciliationOutcome {
        switch reservation.meter {
        case .organize:
            return organizeOutcome(runID: reservation.runID, destinationRoot: destinationRoot)
        case .dedupe:
            return dedupeOutcome(runID: reservation.runID, destinationRoot: destinationRoot)
        }
    }

    // MARK: Organize

    /// Counts `CopyJobs` rows for the run that reached a proven-complete state.
    ///
    /// The queue database is the right evidence here rather than the receipt: it
    /// is written transactionally as each copy finalizes, so it survives a kill
    /// mid-run, whereas the receipt's transfer list is only complete once the
    /// run finishes.
    private func organizeOutcome(runID: UUID, destinationRoot: URL) -> TrialReconciliationOutcome {
        let databaseURL = destinationRoot.appendingPathComponent(".organize_cache.db")

        switch presenceChecker.presence(at: databaseURL.path) {
        case .inaccessible:
            return .unreachable
        case .missing:
            // No queue database at all. There is nothing that could prove work
            // happened here, and nothing that could disprove it either — so this
            // stays open rather than being finalized at zero.
            return .unreachable
        case .exists:
            break
        }

        guard let database = try? OrganizerDatabase(url: databaseURL) else { return .unreachable }
        defer { database.close() }

        // A crashed run keeps its unfinished jobs PENDING so the user can resume
        // and finish them. While any remain, this run is not over: settling now
        // would charge the partial count, and the resumed files would then copy
        // for free, because `finalize` only ever acts on an open reservation.
        guard let resumable = try? database.resumableJobCount(runID: runID) else { return .unreachable }
        guard resumable == 0 else { return .unsettled }

        guard let count = try? database.completedJobCount(runID: runID) else { return .unreachable }
        return .completed(count: count)
    }

    // MARK: Dedupe

    /// Counts the items a commit actually moved to the Trash, from its receipt
    /// and — if consolidation has not yet folded it in — its journal.
    ///
    /// Both are read, never written or removed.
    private func dedupeOutcome(runID: UUID, destinationRoot: URL) -> TrialReconciliationOutcome {
        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)

        guard presenceChecker.presence(at: logsDirectory.path) == .exists else {
            return .unreachable
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return .unreachable
        }

        // The receipt filename embeds the run ID, so the run's own artifacts are
        // identifiable without decoding every receipt in the folder.
        let marker = runID.uuidString
        let receiptURLs = contents.filter {
            $0.lastPathComponent.hasPrefix("dedupe_audit_receipt_")
                && $0.pathExtension == "json"
                && $0.lastPathComponent.contains(marker)
        }
        guard !receiptURLs.isEmpty else { return .unreachable }

        // Distinct paths, so a path recorded in both the receipt and the
        // journal is counted once. Repeat passes therefore produce the same
        // number rather than an accumulating one.
        var trashedPaths: Set<String> = []
        let decoder = Self.makeDecoder()
        for receiptURL in receiptURLs {
            // An artifact that exists but cannot be read or decoded proves
            // nothing. Swallowing the error and returning the count so far —
            // possibly zero — would settle the reservation on the strength of
            // evidence we failed to read.
            guard let data = try? Data(contentsOf: receiptURL),
                  let receipt = try? decoder.decode(DeduplicateAuditReceipt.self, from: data)
            else {
                return .unreachable
            }

            // Recovery leaves a receipt PENDING when it could not settle the
            // journal — an unreachable volume, or a Trash location it could not
            // confirm. The visible count is provisional, and a later pass can
            // prove more moves, so settling now would lock in a charge that can
            // never be corrected.
            guard receipt.status != "PENDING" else { return .unsettled }

            for item in receipt.items where item.trashURL != nil {
                trashedPaths.insert(item.originalPath)
            }

            // `loadSpoolRecords` returns empty for an absent journal and skips
            // only a torn final line, so a throw here means the file exists and
            // could not be read.
            let spoolURL = receiptURL.appendingPathExtension("spool")
            do {
                trashedPaths.formUnion(try DeduplicateExecutor.loadSpoolRecords(from: spoolURL).keys)
            } catch {
                return .unreachable
            }
        }

        return .completed(count: trashedPaths.count)
    }

    // Built per call: `JSONDecoder` is not `Sendable`, and reconciliation runs
    // once per recovery pass, not per file.
    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
