#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - The one way to recover a destination (free-trial step 3)
//
// Filesystem recovery and trial reconciliation must always happen together, in
// that order. This type exists so that pairing cannot drift apart.
//
// There were eight places constructing a `MutationRecoveryCoordinator` and ten
// calls to `.recover(destinationRoot:)` — in `OrganizerEngine.prepare`, three in
// `RunSessionStore`, `AppState`'s post-bootstrap launch recovery, three in
// `DeduplicateEngine`, `HistoryStore`, and `CLI.swift`. Wiring reconciliation
// into a hand-picked subset of those would guarantee drift, and the failure is
// quiet and one-directional: filesystem recovery completes at launch, the
// reservation stays open and therefore FULLY CHARGED, and the customer is
// refused work they are entitled to. Nothing errors; the balance is just wrong.
//
// `script/check_recovery_goes_through_helper.sh` fails CI if a direct
// `.recover(destinationRoot:` call reappears outside this file.

public enum DestinationRecovery {
    /// Supplies the reconciler for the current process, or nil to skip ledger
    /// reconciliation entirely.
    ///
    /// Deliberately nil by default, and deliberately not a silent convenience:
    /// step 3 ships dark, so nothing has a ledger to hand over yet, and the
    /// surfaces that never meter — the CLI, and any unrestricted build — should
    /// keep returning nil forever rather than pretend to reconcile.
    ///
    /// `nonisolated(unsafe)` matches the existing provider seams in this
    /// codebase (`MediaDiscovery.isICloudDatalessProvider`,
    /// `DestinationOperationLock.isRemoteVolumeProvider`). It is written once by
    /// the composition root during bootstrap and only read afterwards.
    public nonisolated(unsafe) static var reconcilerProvider: (@Sendable () -> (any TrialLedgerReconciling)?)?

    /// Reconcile durable mutation intent for `destinationRoot`, then settle any
    /// trial reservation the recovered run left open.
    ///
    /// Order matters: the reconciler reads receipts and journals that
    /// `MutationRecoveryCoordinator` may still be consolidating, so it must run
    /// second or it would judge a half-settled state.
    ///
    /// Reconciliation never affects the returned report, and never throws into
    /// the caller. Recovery is a safety mechanism; trial bookkeeping must not be
    /// able to interfere with it.
    @discardableResult
    public static func recoverAndReconcile(
        destinationRoot: URL,
        coordinator: MutationRecoveryCoordinator = MutationRecoveryCoordinator()
    ) -> MutationRecoveryReport {
        let report = coordinator.recover(destinationRoot: destinationRoot)
        reconcilerProvider?()?.reconcile(destinationRoot: destinationRoot)
        return report
    }
}
