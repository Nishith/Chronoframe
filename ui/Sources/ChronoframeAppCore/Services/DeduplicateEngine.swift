#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public enum DeduplicateEngineError: LocalizedError {
    case destinationMissing
    case scanFailed(String)
    case commitFailed(String)

    public var errorDescription: String? {
        switch self {
        case .destinationMissing:
            return "Choose a destination folder before running a deduplicate scan."
        case let .scanFailed(message):
            return message
        case let .commitFailed(message):
            return message
        }
    }
}

@MainActor
public protocol DeduplicateEngine: AnyObject {
    func scan(_ configuration: DeduplicateConfiguration) throws -> AsyncThrowingStream<DeduplicateEvent, Error>
    func cancelCurrentScan()
    func commit(
        plan: DeduplicationPlan,
        configuration: DeduplicateConfiguration
    ) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error>
    func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error>
}

@MainActor
public final class NativeDeduplicateEngine: DeduplicateEngine {
    /// Asked before a commit trashes anything. Scanning and review are free.
    private let authorizer: any TrialAuthorizing
    /// Told what a revert restored, so the allowance comes back.
    ///
    /// A different type from `authorizer` on purpose: `TrialRefunding` cannot
    /// refuse anything, so having it in scope on the revert path cannot become
    /// a gate there.
    private let refunder: any TrialRefunding
    private let scanner: DeduplicateScanner
    private let executor: DeduplicateExecutor
    private let recoveryCoordinator: MutationRecoveryCoordinator
    /// Reads what a finished commit actually moved to the Trash, so the
    /// reservation settles at that count. Injectable so tests can pin the
    /// outcome without staging Trash state.
    private let reconciliationEvidence: any TrialReconciliationEvidence
    /// Internal rather than private so a test can install a competing
    /// operation's lease deterministically, the way `networkAdvisory` below is
    /// internal for its stub. Nothing outside this type writes them in
    /// production.
    var activeLease: DestinationOperationLease?
    var activeLeaseDestination: String?
    /// Surfaces a one-time warning when the dedupe destination is on a network
    /// volume. Internal so tests can inject a stub advisory + scratch defaults.
    var networkAdvisory = NetworkDestinationAdvisory()

    /// - Parameter authorizer: who may do metered work. Required, never
    ///   defaulted — see `SwiftOrganizerEngine.init` for why a default here
    ///   would be a silent licensing bypass rather than a convenience.
    /// - Parameter refunder: told what a revert restored. Defaulted, unlike
    ///   `authorizer`: forgetting it leaves a customer over-charged, which
    ///   shows in their balance and can be corrected, whereas forgetting the
    ///   authorizer gives the product away silently.
    public init(
        authorizer: any TrialAuthorizing,
        refunder: any TrialRefunding = NoOpTrialRefunder(),
        scanner: DeduplicateScanner = DeduplicateScanner(),
        executor: DeduplicateExecutor = DeduplicateExecutor(),
        recoveryCoordinator: MutationRecoveryCoordinator = MutationRecoveryCoordinator(),
        reconciliationEvidence: any TrialReconciliationEvidence = FileSystemTrialReconciliationEvidence()
    ) {
        self.authorizer = authorizer
        self.refunder = refunder
        self.scanner = scanner
        self.executor = executor
        self.recoveryCoordinator = recoveryCoordinator
        self.reconciliationEvidence = reconciliationEvidence
    }

    public func scan(_ configuration: DeduplicateConfiguration) throws -> AsyncThrowingStream<DeduplicateEvent, Error> {
        guard !configuration.destinationPath.isEmpty else {
            throw DeduplicateEngineError.destinationMissing
        }
        activeLease?.release()
        let destinationURL = URL(fileURLWithPath: configuration.destinationPath, isDirectory: true)
        let lease = try DestinationOperationLock.acquire(
            destinationRoot: destinationURL,
            surface: "app",
            operation: "deduplicate scan"
        )
        _ = DestinationRecovery.recoverAndReconcile(
            destinationRoot: destinationURL,
            coordinator: recoveryCoordinator
        )
        activeLease = lease
        activeLeaseDestination = destinationURL.standardizedFileURL.path
        let networkWarning = networkAdvisory.warningIfNeeded(for: destinationURL)
        return scanHoldingStream(
            scanner.scan(configuration: configuration),
            leadingWarning: networkWarning
        )
    }

    public func cancelCurrentScan() {
        scanner.cancel()
        executor.cancel()
        activeLease?.release()
        activeLease = nil
        activeLeaseDestination = nil
    }

    public func commit(
        plan: DeduplicationPlan,
        configuration: DeduplicateConfiguration
    ) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        let destinationURL = URL(fileURLWithPath: configuration.destinationPath, isDirectory: true)
        let standardizedDestination = destinationURL.standardizedFileURL.path
        if activeLease == nil || activeLeaseDestination != standardizedDestination {
            activeLease?.release()
            activeLease = try DestinationOperationLock.acquire(
                destinationRoot: destinationURL,
                surface: "app",
                operation: "deduplicate commit"
            )
            activeLeaseDestination = standardizedDestination
            _ = DestinationRecovery.recoverAndReconcile(
                destinationRoot: destinationURL,
                coordinator: recoveryCoordinator
            )
        }
        // Minted here, before the executor starts, because the trial
        // reservation is taken at this same point. The receipt used to mint its
        // own ID inside the commit stream, which is after the reservation would
        // already have to exist.
        let runID = UUID()
        guard let lease = activeLease else {
            throw DeduplicateEngineError.commitFailed(
                "Chronoframe could not reserve exclusive access to the destination folder. Try the cleanup again."
            )
        }
        return gatedCommitStream(
            plan: plan,
            configuration: configuration,
            runID: runID,
            destinationURL: destinationURL,
            lease: lease
        )
    }

    // MARK: - Trial gate (free-trial step 4, T9)

    /// Reserve dedupe allowance, then run the commit and settle at the number
    /// of duplicates that actually reached the Trash.
    ///
    /// The gate runs here rather than in `DeduplicateSessionStore` because the
    /// store is a UI path that a caller can route around; this is the only door
    /// to `DeduplicateExecutor.commit`.
    ///
    /// It also runs before `executor.commit` is *called*, not merely before its
    /// stream is consumed. That method starts a `Task.detached` the moment it is
    /// invoked, so it writes the PENDING receipt and creates the spool journal
    /// whether or not anyone iterates the result — gating after the call would
    /// be gating after the first write.
    private func gatedCommitStream(
        plan: DeduplicationPlan,
        configuration: DeduplicateConfiguration,
        runID: UUID,
        destinationURL: URL,
        lease: DestinationOperationLease
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                defer {
                    // Release OUR lease, and clear the engine's slot only if it
                    // still holds ours. While the gate was suspended another
                    // operation may have replaced it; clearing the slot then
                    // would strip the lock bookkeeping from an operation that is
                    // still running. `release()` is idempotent, so releasing a
                    // lease `cancelCurrentScan()` already released is a no-op.
                    if self?.activeLease === lease {
                        self?.activeLease = nil
                        self?.activeLeaseDestination = nil
                    }
                    lease.release()
                }
                guard let self else {
                    continuation.finish()
                    return
                }

                let authorization = await self.authorizer.authorizeMeteredWork(
                    runID: runID,
                    meter: .dedupe,
                    count: plan.items.count,
                    // Standardized because reconciliation matches an open
                    // reservation to a destination by path.
                    destinationRoot: destinationURL.standardizedFileURL.path
                )
                if let refusal = authorization.refusal {
                    continuation.finish(throwing: TrialAuthorizationError(refusal: refusal))
                    return
                }

                // The gate is the only suspension point before the first write,
                // and a cancel or a competing operation can land inside it.
                //
                // Compared by IDENTITY, not by destination path. A cancel
                // followed by a new scan or revert on the same folder installs a
                // different lease for the same path, so a path check would let
                // this now-stale plan mutate files under an operation that
                // believes it holds the lock. Nothing has been written yet, so
                // the reservation goes back.
                guard self.activeLease === lease else {
                    await self.authorizer.releaseMeteredWork(runID: runID)
                    continuation.finish()
                    return
                }

                do {
                    let stream = self.executor.commit(
                        plan: plan,
                        destinationRoot: configuration.destinationPath,
                        additionalSourceRoots: configuration.additionalSources.map(\.path),
                        hardDelete: false,
                        runID: runID
                    )
                    for try await event in stream {
                        continuation.yield(event)
                    }
                    await self.settleReservation(
                        runID: runID,
                        reservedCount: plan.items.count,
                        destinationURL: destinationURL
                    )
                    continuation.finish()
                } catch let error as ReceiptPreflightError {
                    // The one failure where zero files were touched.
                    // AGENTS.md invariant 13 preflights the receipt directory
                    // before any deletion, and every `ReceiptPreflightError`
                    // site in the executor sits ahead of the first Trash move.
                    //
                    // This has to release rather than stay charged. No receipt
                    // is written, so there is nothing for reconciliation to
                    // read: it reports `unreachable` and leaves the reservation
                    // open forever. Staying charged would permanently cost the
                    // customer the whole plan's worth of allowance for a
                    // cleanup that never moved a single file.
                    await self.authorizer.releaseMeteredWork(runID: runID)
                    continuation.finish(throwing: error)
                } catch {
                    // Any other failure is ambiguous from out here — the
                    // executor reports mid-run trouble as events, not throws,
                    // so a throw that is not a preflight failure is a shape we
                    // do not have a rule for. The reservation stays open and
                    // fully charged, and reconciliation settles it from the
                    // receipt and journal once they are readable.
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Settle the commit's reservation at the number of duplicates that
    /// actually reached the Trash.
    ///
    /// Uses the reconciler's own dedupe evidence rather than the summary's
    /// `deletedCount`, so an in-process settle and a later reconciliation pass
    /// can never disagree — and disagreeing is unfixable, because `finalize` is
    /// one-way and whichever ran first would win. The evidence also declines to
    /// settle a commit whose receipt is still `PENDING`, where a later pass can
    /// still prove more moves from the journal.
    ///
    /// The probe is a question, not a ledger row, and is never stored. Today's
    /// dedupe evidence reads only `runID` and `meter`; every other field is
    /// filled with the run's real value except `accountKey`, which the engine
    /// genuinely does not know — it lives inside the authorizer, and the
    /// evidence has no use for it.
    private func settleReservation(
        runID: UUID,
        reservedCount: Int,
        destinationURL: URL
    ) async {
        let outcome = reconciliationEvidence.outcome(
            for: OpenReservation(
                runID: runID,
                accountKey: "",
                meter: .dedupe,
                reservedCount: reservedCount,
                destinationRoot: destinationURL.standardizedFileURL.path,
                createdAt: Date()
            ),
            destinationRoot: destinationURL
        )
        guard case let .completed(count) = outcome else { return }
        await authorizer.finalizeMeteredWork(runID: runID, actualCount: count)
    }

    public func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        let destinationURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
        activeLease?.release()
        activeLease = try DestinationOperationLock.acquire(
            destinationRoot: destinationURL,
            surface: "app",
            operation: "deduplicate revert"
        )
        activeLeaseDestination = destinationURL.standardizedFileURL.path
        _ = DestinationRecovery.recoverAndReconcile(
            destinationRoot: destinationURL,
            coordinator: recoveryCoordinator
        )
        let stream = executor.revert(
            receiptURL: receiptURL,
            destinationBoundary: destinationURL
        )
        return refundingRevertStream(stream)
    }

    // MARK: - Refunding a revert (free-trial step 4, T12)

    /// Forwards a revert's events, holds the destination lease for its
    /// duration, and gives back the allowance for what it actually restored.
    ///
    /// Revert's behaviour is untouched. This observes the stream; it cannot
    /// refuse, retry, or reorder anything, and a missing run ID or a ledger
    /// failure changes nothing about what the revert does.
    private func refundingRevertStream(
        _ stream: AsyncThrowingStream<DeduplicateCommitEvent, Error>
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        AsyncThrowingStream { continuation in
            // Captured strongly so an engine that goes away mid-revert still
            // credits back files that are already out of the Trash.
            let refunder = self.refunder
            Task { @MainActor [weak self] in
                defer {
                    self?.activeLease?.release()
                    self?.activeLease = nil
                    self?.activeLeaseDestination = nil
                }
                // Only the items this pass actually moved back. A Trash item
                // whose bytes no longer match the receipt is left in place by
                // design and reported as `itemFailed`, so a later pass can
                // restore it and refund it then.
                var restoredPaths: [String] = []
                // Reported by the pass that did the restoring, so the refund is
                // keyed to the receipt those items actually came from. Reading
                // the receipt again here would be a second, independent read:
                // anything that replaced the file in between — a sync client,
                // the user — would have this credit one run for another run's
                // items.
                var receiptRunID: UUID?
                do {
                    for try await event in stream {
                        switch event {
                        // The restore path reuses the forward path's event
                        // type: `itemTrashed` here means the file came back
                        // OUT of the Trash.
                        case let .itemTrashed(originalPath, _, _):
                            restoredPaths.append(originalPath)
                        case let .complete(summary):
                            receiptRunID = summary.runID
                        default:
                            break
                        }
                        continuation.yield(event)
                    }
                    await refunder.refundUndoneWork(
                        receiptRunID: receiptRunID, meter: .dedupe, itemPaths: restoredPaths
                    )
                    continuation.finish()
                } catch {
                    // No refund here, and none is owed: every `throw` on the
                    // revert path happens while validating the receipt, before
                    // a single item is restored. Per-item trouble after that is
                    // reported as `itemFailed`, not thrown — so a throw means
                    // `restoredPaths` is empty and there is nothing to credit.
                    continuation.finish(throwing: error)
                }
            }
        }
    }


    private func scanHoldingStream(
        _ stream: AsyncThrowingStream<DeduplicateEvent, Error>,
        leadingWarning: String? = nil
    ) -> AsyncThrowingStream<DeduplicateEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                var reachedReview = false
                if let leadingWarning {
                    continuation.yield(.issue(DeduplicateIssue(severity: .warning, message: leadingWarning)))
                }
                do {
                    for try await event in stream {
                        if case .complete = event { reachedReview = true }
                        continuation.yield(event)
                    }
                    if !reachedReview {
                        self?.activeLease?.release()
                        self?.activeLease = nil
                        self?.activeLeaseDestination = nil
                    }
                    continuation.finish()
                } catch {
                    self?.activeLease?.release()
                    self?.activeLease = nil
                    self?.activeLeaseDestination = nil
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
