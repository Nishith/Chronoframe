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
    private let scanner: DeduplicateScanner
    private let executor: DeduplicateExecutor
    private let recoveryCoordinator: MutationRecoveryCoordinator
    /// Reads what a finished commit actually moved to the Trash, so the
    /// reservation settles at that count. Injectable so tests can pin the
    /// outcome without staging Trash state.
    private let reconciliationEvidence: any TrialReconciliationEvidence
    private var activeLease: DestinationOperationLease?
    private var activeLeaseDestination: String?
    /// Surfaces a one-time warning when the dedupe destination is on a network
    /// volume. Internal so tests can inject a stub advisory + scratch defaults.
    var networkAdvisory = NetworkDestinationAdvisory()

    /// - Parameter authorizer: who may do metered work. Required, never
    ///   defaulted — see `SwiftOrganizerEngine.init` for why a default here
    ///   would be a silent licensing bypass rather than a convenience.
    public init(
        authorizer: any TrialAuthorizing,
        scanner: DeduplicateScanner = DeduplicateScanner(),
        executor: DeduplicateExecutor = DeduplicateExecutor(),
        recoveryCoordinator: MutationRecoveryCoordinator = MutationRecoveryCoordinator(),
        reconciliationEvidence: any TrialReconciliationEvidence = FileSystemTrialReconciliationEvidence()
    ) {
        self.authorizer = authorizer
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
        return gatedCommitStream(
            plan: plan,
            configuration: configuration,
            runID: runID,
            destinationURL: destinationURL,
            standardizedDestination: standardizedDestination
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
        standardizedDestination: String
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                defer {
                    self?.activeLease?.release()
                    self?.activeLease = nil
                    self?.activeLeaseDestination = nil
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
                    destinationRoot: standardizedDestination
                )
                if let refusal = authorization.refusal {
                    continuation.finish(throwing: TrialAuthorizationError(refusal: refusal))
                    return
                }

                // The gate is the only suspension point before the first write,
                // and `cancelCurrentScan()` releases the destination lease from
                // inside it. No lease means we may not mutate — and nothing has
                // been written yet, so the reservation goes back.
                guard self.activeLease != nil,
                      self.activeLeaseDestination == standardizedDestination
                else {
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
                } catch {
                    // Every executor failure is treated the same: the
                    // reservation stays open and fully charged, and
                    // reconciliation settles it from the receipt and journal
                    // once they are readable.
                    //
                    // No error is special-cased into a release. The tempting
                    // one is `ReceiptPreflightError` — invariant 13 guarantees
                    // zero files touched — but it is nearly unreachable from
                    // here: the destination lock lives in the same
                    // `.organize_logs` directory the receipt preflight writes
                    // to, and it is acquired in `commit` BEFORE this gate. An
                    // unwritable destination therefore throws out of `commit`
                    // synchronously and never takes a reservation at all. What
                    // remains is a lease taken during the scan and a directory
                    // that became unwritable before the commit; that leaves the
                    // reservation charged until reconciliation, which is the
                    // fail-closed direction and not worth an untested branch.
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
        return releasingStream(stream)
    }

    private func releasingStream(
        _ stream: AsyncThrowingStream<DeduplicateCommitEvent, Error>
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        AsyncThrowingStream { continuation in
            Task { @MainActor [weak self] in
                defer {
                    self?.activeLease?.release()
                    self?.activeLease = nil
                    self?.activeLeaseDestination = nil
                }
                do {
                    for try await event in stream { continuation.yield(event) }
                    continuation.finish()
                } catch {
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
