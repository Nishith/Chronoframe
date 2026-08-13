#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

@MainActor
public final class SwiftOrganizerEngine: OrganizerEngine {
    /// Asked before any transfer enqueues, copies, or writes anything.
    /// Reorganize's gate is T10.
    private let authorizer: any TrialAuthorizing
    /// Told what a revert undid, so the allowance comes back.
    ///
    /// Deliberately a different type from `authorizer`: `TrialRefunding` has no
    /// way to refuse anything, so having it in scope on the revert path cannot
    /// turn into a gate there.
    private let refunder: any TrialRefunding
    private let profilesRepository: any ProfilesRepositorying
    private let planner: DryRunPlanner
    private let transferExecutor: TransferExecutor
    private let revertExecutor: RevertExecutor
    private let reorganizeExecutor: ReorganizeExecutor
    private var activeTask: Task<Void, Never>?
    private var activeRunID: UUID?
    /// Per-run cancellation flag the executors poll inside synchronous
    /// hot paths. Held here so `cancelCurrentRun()` can flip it
    /// alongside `activeTask.cancel()`.
    private var activeCancellationRef: TaskCancellationCheck?

    /// - Parameter authorizer: who may do metered work. **Required on purpose.**
    ///   A default would make every forgotten or future constructor a silent
    ///   licensing bypass — and silent is the operative word, because a missing
    ///   gate does not crash, log, or fail a test. It just gives the product
    ///   away. Requiring it turns that into a compile error and forces each
    ///   composition root to state its policy out loud.
    ///
    ///   Revert deliberately takes no authorizer anywhere: a paywall must never
    ///   be able to strand a library mid-migration.
    /// - Parameter refunder: told what a revert undid. Defaulted, unlike
    ///   `authorizer`: forgetting it leaves a customer over-charged, which is
    ///   visible in their balance and correctable, whereas forgetting the
    ///   authorizer gives the product away silently and permanently.
    public init(
        authorizer: any TrialAuthorizing,
        refunder: any TrialRefunding = NoOpTrialRefunder(),
        profilesRepository: any ProfilesRepositorying = ProfilesRepository(),
        planner: DryRunPlanner = DryRunPlanner(),
        transferExecutor: TransferExecutor = TransferExecutor(),
        revertExecutor: RevertExecutor = RevertExecutor(),
        reorganizeExecutor: ReorganizeExecutor = ReorganizeExecutor()
    ) {
        self.authorizer = authorizer
        self.refunder = refunder
        self.profilesRepository = profilesRepository
        self.planner = planner
        self.transferExecutor = transferExecutor
        self.revertExecutor = revertExecutor
        self.reorganizeExecutor = reorganizeExecutor
    }

    public func preflight(_ configuration: RunConfiguration) async throws -> RunPreflight {
        let resolvedConfiguration = try resolvedConfiguration(for: configuration)
        let pendingJobs = pendingJobCount(destinationRoot: resolvedConfiguration.destinationPath)

        return RunPreflight(
            configuration: resolvedConfiguration,
            resolvedSourcePath: resolvedConfiguration.sourcePath,
            resolvedDestinationPath: resolvedConfiguration.destinationPath,
            pendingJobCount: pendingJobs,
            profilesFilePath: profilesRepository.profilesFileURL().path
        )
    }

    public func start(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error> {
        let resolvedConfiguration = try resolvedConfiguration(for: configuration)

        switch resolvedConfiguration.mode {
        case .preview:
            return makePreviewStream(configuration: resolvedConfiguration)
        case .transfer:
            return makeTransferStream(configuration: resolvedConfiguration, resumePendingJobs: false)
        case .revert, .reorganize:
            // Revert + reorganize are surfaced via dedicated entry points
            // (SwiftOrganizerEngine.revert / .reorganize). They cannot be invoked
            // through the generic start() pipeline because they take additional
            // arguments (a receipt path or a target FolderStructure).
            throw OrganizerEngineError.failedToLaunch(
                "\(resolvedConfiguration.mode.title) runs must be started from their matching app action."
            )
        }
    }

    public func start(
        _ configuration: RunConfiguration,
        batch: FreeTestBatchSelection
    ) throws -> AsyncThrowingStream<RunEvent, Error> {
        let resolvedConfiguration = try resolvedConfiguration(for: configuration)

        guard resolvedConfiguration.mode == .transfer else {
            throw OrganizerEngineError.failedToLaunch(
                "Only a transfer can run as a free test batch."
            )
        }

        return makeTransferStream(
            configuration: resolvedConfiguration,
            resumePendingJobs: false,
            batch: batch
        )
    }

    public func resume(_ configuration: RunConfiguration) throws -> AsyncThrowingStream<RunEvent, Error> {
        let resolvedConfiguration = try resolvedConfiguration(for: configuration)

        switch resolvedConfiguration.mode {
        case .preview:
            return makePreviewStream(configuration: resolvedConfiguration)
        case .transfer:
            return makeTransferStream(configuration: resolvedConfiguration, resumePendingJobs: true)
        case .revert, .reorganize:
            throw OrganizerEngineError.failedToLaunch(
                "\(resolvedConfiguration.mode.title) runs cannot be resumed. Start the action again."
            )
        }
    }

    public func cancelCurrentRun() {
        activeTask?.cancel()
        // Phase 1 finding: also flip the per-run cancellation flag the
        // executors poll. `activeTask.cancel()` only marks the Swift
        // Task; long-running synchronous bodies inside the executor
        // poll `isCancelledRef.isCancelled` and would otherwise not
        // observe the cancel until they reach a Task-cancellation
        // checkpoint (which doesn't exist on the SQLite / file-walk
        // paths).
        activeCancellationRef?.cancel()
        activeCancellationRef = nil
        activeTask = nil
        activeRunID = nil
    }

    private func setActiveTask(
        _ task: Task<Void, Never>,
        id: UUID,
        cancellationRef: TaskCancellationCheck? = nil
    ) {
        activeRunID = id
        activeTask = task
        activeCancellationRef = cancellationRef
    }

    private func clearActiveTask(id: UUID) {
        guard activeRunID == id else { return }
        activeTask = nil
        activeRunID = nil
        activeCancellationRef = nil
    }

    // MARK: - Revert

    public func revert(receiptURL: URL, destinationRoot: String) throws -> AsyncThrowingStream<RunEvent, Error> {
        // Validate the receipt up front so we can throw synchronously and let
        // the caller surface a clean error before kicking off any async work.
        let receipt: RevertReceipt
        do {
            receipt = try revertExecutor.loadReceipt(at: receiptURL)
        } catch let error as RevertExecutorError {
            // A malformed receipt blocks this revert action and would keep
            // surfacing if we left the file in place. Quarantine only decoded
            // JSON failures; unreadable receipts may be valid and retryable.
            if case .invalidReceipt = error {
                revertExecutor.quarantineCorruptReceipt(at: receiptURL)
            }
            throw error
        }
        return makeRevertStream(
            receipt: receipt,
            destinationRoot: destinationRoot,
            receiptURL: receiptURL
        )
    }

    private func makeRevertStream(
        receipt: RevertReceipt,
        destinationRoot: String,
        receiptURL: URL
    ) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let revertExecutor = self.revertExecutor
            let refunder = self.refunder
            let isCancelledRef = TaskCancellationCheck()
            let runID = UUID()

            let task = Task.detached(priority: .userInitiated) {
                defer {
                    Task { @MainActor in
                        self.clearActiveTask(id: runID)
                    }
                }
                continuation.yield(.startup)
                continuation.yield(.phaseStarted(phase: .revert, total: receipt.transfers.count))

                let observer = RevertExecutionObserver(
                    onTaskProgress: { completed, total in
                        continuation.yield(
                            .phaseProgress(
                                phase: .revert,
                                completed: completed,
                                total: total,
                                bytesCopied: nil,
                                bytesTotal: nil,
                                currentFilePath: nil
                            )
                        )
                    },
                    onIssue: { issue in
                        continuation.yield(.issue(issue))
                    }
                )

                let result = revertExecutor.revert(
                    receipt: receipt,
                    observer: observer,
                    destinationBoundary: URL(fileURLWithPath: destinationRoot, isDirectory: true),
                    isCancelled: { isCancelledRef.isCancelled }
                )

                // Give back the allowance for what this pass actually removed,
                // before the cancellation check: a cancel does not un-remove the
                // files already deleted, and leaving them charged would bill the
                // customer for work that is undone on disk.
                //
                // `reservationRunID` is nil for a receipt that cannot supply a
                // trustworthy key, and the refunder does nothing with nil rather
                // than guessing one.
                await refunder.refundUndoneWork(
                    receiptRunID: receipt.reservationRunID,
                    meter: .organize,
                    itemPaths: result.revertedPaths
                )

                if isCancelledRef.isCancelled {
                    continuation.finish()
                    return
                }

                continuation.yield(
                    .phaseCompleted(
                        phase: .revert,
                        result: RunPhaseResult(
                            revertedCount: result.revertedCount,
                            skippedCount: result.skippedCount,
                            missingCount: result.missingCount
                        )
                    )
                )

                let metrics = RunMetrics(
                    revertedCount: result.revertedCount,
                    skippedCount: result.skippedCount,
                    missingCount: result.missingCount
                )

                let artifacts = RunArtifactPaths(
                    destinationRoot: destinationRoot,
                    reportPath: receiptURL.path,
                    logFilePath: nil,
                    logsDirectoryPath: URL(fileURLWithPath: destinationRoot)
                        .appendingPathComponent(EngineArtifactLayout.chronoframeDefault.logsDirectoryName, isDirectory: true)
                        .path
                )

                let status: RunStatus = result.totalTransfers == 0 ? .revertEmpty : .reverted
                let title = status == .revertEmpty ? "Nothing to revert" : "Revert complete"

                continuation.yield(
                    .complete(
                        RunSummary(
                            status: status,
                            title: title,
                            metrics: metrics,
                            artifacts: artifacts
                        )
                    )
                )
                continuation.finish()
            }

            self.setActiveTask(task, id: runID, cancellationRef: isCancelledRef)
            continuation.onTermination = { @Sendable _ in
                isCancelledRef.cancel()
                task.cancel()
            }
        }
    }

    // MARK: - Reorganize

    public func reorganize(
        destinationRoot: String,
        targetStructure: FolderStructure
    ) throws -> AsyncThrowingStream<RunEvent, Error> {
        let destinationURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
        // Build the plan synchronously so any walk error throws cleanly.
        let plan = try reorganizeExecutor.plan(
            destinationRoot: destinationURL,
            targetStructure: targetStructure
        )
        return makeReorganizeStream(plan: plan)
    }

    private func makeReorganizeStream(plan: ReorganizePlan) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let reorganizeExecutor = self.reorganizeExecutor
            let authorizer = self.authorizer
            let isCancelledRef = TaskCancellationCheck()
            let runID = UUID()

            let task = Task.detached(priority: .userInitiated) {
                defer {
                    Task { @MainActor in
                        self.clearActiveTask(id: runID)
                    }
                }
                continuation.yield(.startup)

                if plan.isEmpty {
                    let metrics = RunMetrics(skippedCount: plan.unchangedCount)
                    let artifacts = RunArtifactPaths(destinationRoot: plan.destinationRoot)
                    continuation.yield(
                        .complete(
                            RunSummary(
                                status: .nothingToReorganize,
                                title: "Layout already correct",
                                metrics: metrics,
                                artifacts: artifacts
                            )
                        )
                    )
                    continuation.finish()
                    return
                }

                // The gate. Reorganize is unlock-only, not metered: it takes no
                // reservation and consumes no allowance, so there is nothing to
                // settle afterwards and nothing to give back on failure.
                //
                // It sits after the empty-plan branch on purpose. A library
                // whose layout is already correct is told so for free —
                // refusing there would be a paywall in front of the word "no",
                // which is the same reason an empty organize run is permitted.
                //
                // Planning stays free too: it only reads, and the plan is
                // already built by the time this stream starts.
                let authorization = await authorizer.authorizeUnlockOnlyWork()
                if let refusal = authorization.refusal {
                    continuation.finish(throwing: TrialAuthorizationError(refusal: refusal))
                    return
                }

                // A cancel can land inside that await, and reorganize MOVES
                // files in place rather than copying them, so starting after a
                // cancel is the worst of the three surfaces to get wrong.
                if isCancelledRef.isCancelled || Task.isCancelled {
                    continuation.finish()
                    return
                }

                continuation.yield(.copyPlanReady(count: plan.moves.count))
                continuation.yield(.phaseStarted(phase: .reorganize, total: plan.moves.count))

                let observer = ReorganizeExecutionObserver(
                    onTaskProgress: { completed, total in
                        continuation.yield(
                            .phaseProgress(
                                phase: .reorganize,
                                completed: completed,
                                total: total,
                                bytesCopied: nil,
                                bytesTotal: nil,
                                currentFilePath: nil
                            )
                        )
                    },
                    onIssue: { issue in
                        continuation.yield(.issue(issue))
                    }
                )

                let result: ReorganizeExecutionResult
                do {
                    result = try reorganizeExecutor.execute(
                        plan: plan,
                        observer: observer,
                        isCancelled: { isCancelledRef.isCancelled }
                    )
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                if isCancelledRef.isCancelled {
                    continuation.finish()
                    return
                }

                continuation.yield(
                    .phaseCompleted(
                        phase: .reorganize,
                        result: RunPhaseResult(
                            failedCount: result.failedCount,
                            skippedCount: result.skippedCount,
                            movedCount: result.movedCount
                        )
                    )
                )

                let metrics = RunMetrics(
                    plannedCount: plan.moves.count,
                    failedCount: result.failedCount,
                    skippedCount: result.skippedCount,
                    movedCount: result.movedCount
                )
                let artifacts = RunArtifactPaths(
                    destinationRoot: plan.destinationRoot,
                    reportPath: result.receiptPath
                )

                continuation.yield(
                    .complete(
                        RunSummary(
                            status: .reorganized,
                            title: "Reorganize complete",
                            metrics: metrics,
                            artifacts: artifacts
                        )
                    )
                )
                continuation.finish()
            }

            self.setActiveTask(task, id: runID, cancellationRef: isCancelledRef)
            continuation.onTermination = { @Sendable _ in
                isCancelledRef.cancel()
                task.cancel()
            }
        }
    }

    private func resolvedConfiguration(for configuration: RunConfiguration) throws -> RunConfiguration {
        let profiles = try profilesRepository.loadProfiles()
        let resolvedConfiguration: RunConfiguration

        if let profileName = configuration.profileName, !profileName.isEmpty {
            guard let profile = profiles.first(where: { $0.name == profileName }) else {
                throw OrganizerEngineError.profileNotFound(profileName)
            }

            resolvedConfiguration = configuration.resolving(profile: profile)
        } else {
            resolvedConfiguration = configuration
        }

        guard FileManager.default.fileExists(atPath: resolvedConfiguration.sourcePath) else {
            throw OrganizerEngineError.sourceDoesNotExist(resolvedConfiguration.sourcePath)
        }

        guard !resolvedConfiguration.destinationPath.isEmpty else {
            throw OrganizerEngineError.destinationMissing
        }

        // Overlapping roots are rejected at every entry point (preflight,
        // start, resume) rather than only at selection time, so a
        // destination that changed between choosing folders and running
        // cannot slip an overlapping pair through (TOCTOU).
        if let conflict = SourceDestinationDisjointness.conflict(
            sourcePath: resolvedConfiguration.sourcePath,
            destinationPath: resolvedConfiguration.destinationPath
        ) {
            throw OrganizerEngineError.sourceOverlapsDestination(conflict)
        }

        return resolvedConfiguration
    }

    private func makePreviewStream(configuration: RunConfiguration) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let planner = self.planner
            let isCancelledRef = TaskCancellationCheck()
            let runID = UUID()
            let task = Task.detached(priority: .userInitiated) {
                defer {
                    Task { @MainActor in
                        self.clearActiveTask(id: runID)
                    }
                }
                do {
                    // Yield startup immediately so the UI transitions out of "Preparing…"
                    // before the (potentially long) planning walk begins.
                    continuation.yield(.startup)

                    let result = try await planner.planAsync(
                        sourceRoot: URL(fileURLWithPath: configuration.sourcePath, isDirectory: true),
                        destinationRoot: URL(fileURLWithPath: configuration.destinationPath, isDirectory: true),
                        workerCount: max(1, configuration.workerCount),
                        folderStructure: configuration.folderStructure,
                        eventSuggestionMode: configuration.eventSuggestionMode,
                        isCancelled: { isCancelledRef.isCancelled || Task.isCancelled },
                        onEvent: { continuation.yield($0) }
                    )

                    if isCancelledRef.isCancelled || Task.isCancelled {
                        continuation.finish()
                        return
                    }

                    let artifacts = try Self.writeDryRunArtifacts(
                        result: result,
                        destinationRoot: configuration.destinationPath
                    )
                    let metrics = RunMetrics(
                        discoveredCount: result.discoveredSourceCount,
                        plannedCount: result.transferCount,
                        alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                        duplicateCount: result.counts.duplicateCount,
                        hashErrorCount: result.counts.hashErrorCount,
                        dateHistogram: result.dateHistogram
                    )

                    Self.emitPostPlanningEvents(for: result, into: continuation)
                    continuation.yield(
                        .complete(
                            RunSummary(
                                status: .dryRunFinished,
                                title: "Preview complete",
                                metrics: metrics,
                                artifacts: artifacts
                            )
                        )
                    )
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            self.setActiveTask(task, id: runID, cancellationRef: isCancelledRef)
            continuation.onTermination = { @Sendable _ in
                isCancelledRef.cancel()
                task.cancel()
            }
        }
    }

    private func makeTransferStream(
        configuration: RunConfiguration,
        resumePendingJobs: Bool,
        batch: FreeTestBatchSelection? = nil
    ) -> AsyncThrowingStream<RunEvent, Error> {
        AsyncThrowingStream { continuation in
            let planner = self.planner
            let transferExecutor = self.transferExecutor
            let authorizer = self.authorizer
            let runID = UUID()
            // Finding #3: the transfer's parallel copy/hash work runs on GCD
            // queues where `Task.isCancelled` is always false (there is no
            // current Task). Without a shared flag the workers never observe a
            // cancel and can keep mutating after the UI reported the run
            // stopped. Use the same `TaskCancellationCheck` the preview, revert,
            // and reorganize streams already plumb through.
            let isCancelledRef = TaskCancellationCheck()
            let task = Task.detached(priority: .userInitiated) {
                defer {
                    Task { @MainActor in
                        self.clearActiveTask(id: runID)
                    }
                }
                let destinationURL = URL(fileURLWithPath: configuration.destinationPath, isDirectory: true)
                let databaseURL = destinationURL.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
                let logURL = destinationURL.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.runLogFilename)
                let runLogger = PersistentRunLogger(logURL: logURL)

                do {
                    try runLogger.open()

                    let database = try OrganizerDatabase(url: databaseURL)
                    defer {
                        database.close()
                        runLogger.close()
                    }

                    runLogger.log(
                        "=== Run started: src=\(configuration.sourcePath) dst=\(configuration.destinationPath) dry_run=False workers=\(max(1, configuration.workerCount)) ==="
                    )

                    let cleanedTemporaryFiles = transferExecutor.cleanupTemporaryFiles(at: destinationURL)
                    if cleanedTemporaryFiles > 0 {
                        runLogger.warn("Cleaned up \(cleanedTemporaryFiles) orphaned .tmp files from previous interrupted run")
                        continuation.yield(
                            .issue(
                                RunIssue(
                                    severity: .info,
                                    message: "Cleaned \(cleanedTemporaryFiles) orphaned .tmp files"
                                )
                            )
                        )
                    }

                    // Phase 1 finding #3: consolidate any PENDING
                    // receipts left by a crashed previous run, so the
                    // files it copied before the crash become
                    // revertable from Run History instead of being
                    // orphaned in the destination.
                    let recovered = transferExecutor.recoverInterruptedRuns(at: destinationURL)
                    if recovered > 0 {
                        runLogger.warn("Recovered \(recovered) interrupted run receipt(s) from prior session(s)")
                        continuation.yield(
                            .issue(
                                RunIssue(
                                    severity: .info,
                                    message: "Recovered \(recovered) interrupted run\(recovered == 1 ? "" : "s") from a previous session. They appear in Run History as ABORTED and can be reverted."
                                )
                            )
                        )
                    }

                    let recoveredDedupe = DeduplicateExecutor.recoverInterruptedRuns(at: destinationURL)
                    if recoveredDedupe > 0 {
                        runLogger.warn("Recovered \(recoveredDedupe) interrupted deduplicate receipt(s) from prior session(s)")
                        continuation.yield(
                            .issue(
                                RunIssue(
                                    severity: .info,
                                    message: "Recovered \(recoveredDedupe) interrupted deduplicate run\(recoveredDedupe == 1 ? "" : "s") from a previous session. They appear in Run History as ABORTED and can be reverted."
                                )
                            )
                        )
                    }

                    continuation.yield(.startup)

                    if resumePendingJobs {
                        try await Self.resumeTransfer(
                            configuration: configuration,
                            database: database,
                            destinationURL: destinationURL,
                            transferExecutor: transferExecutor,
                            authorizer: authorizer,
                            runLogger: runLogger,
                            isCancelled: { isCancelledRef.isCancelled || Task.isCancelled },
                            continuation: continuation
                        )
                    } else {
                        try await Self.startTransfer(
                            configuration: configuration,
                            planner: planner,
                            database: database,
                            destinationURL: destinationURL,
                            transferExecutor: transferExecutor,
                            authorizer: authorizer,
                            batch: batch,
                            runLogger: runLogger,
                            isCancelled: { isCancelledRef.isCancelled || Task.isCancelled },
                            continuation: continuation
                        )
                    }
                } catch {
                    if isCancelledRef.isCancelled || Task.isCancelled {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }

            // Register the shared flag so `cancelCurrentRun()` flips it (the GCD
            // workers poll it) in addition to cancelling the Swift Task.
            self.setActiveTask(task, id: runID, cancellationRef: isCancelledRef)
            continuation.onTermination = { @Sendable _ in
                task.cancel()
                isCancelledRef.cancel()
            }
        }
    }

    private func pendingJobCount(destinationRoot: String) -> Int {
        let dbURL = URL(fileURLWithPath: destinationRoot).appendingPathComponent(".organize_cache.db")
        guard FileManager.default.fileExists(atPath: dbURL.path) else { return 0 }

        do {
            let database = try OrganizerDatabase(url: dbURL, readOnly: true)
            defer { database.close() }
            return try database.pendingJobCount()
        } catch {
            return 0
        }
    }

    private nonisolated static func startTransfer(
        configuration: RunConfiguration,
        planner: DryRunPlanner,
        database: OrganizerDatabase,
        destinationURL: URL,
        transferExecutor: TransferExecutor,
        authorizer: any TrialAuthorizing,
        batch: FreeTestBatchSelection?,
        runLogger: PersistentRunLogger,
        isCancelled: @escaping @Sendable () -> Bool,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async throws {
        let plan = try await planner.planAsync(
            sourceRoot: URL(fileURLWithPath: configuration.sourcePath, isDirectory: true),
            destinationRoot: destinationURL,
            workerCount: max(1, configuration.workerCount),
            folderStructure: configuration.folderStructure,
            eventSuggestionMode: configuration.eventSuggestionMode,
            isCancelled: isCancelled,
            onEvent: { continuation.yield($0) }
        )

        if isCancelled() {
            continuation.finish()
            return
        }

        // A confirmed free test batch narrows the plan before anything else
        // sees it (T15), so the events, the log line, the gate, and the queue
        // all describe the run that is actually about to happen. Reducing after
        // any of those would report work this run is not going to do.
        //
        // Subtractive by construction: the selection names source paths and the
        // identity each had when it was confirmed, so a re-plan that turned up
        // new or altered files cannot smuggle them in here.
        let result = batch.map { plan.reduced(to: $0) } ?? plan

        emitPostPlanningEvents(for: result, into: continuation)
        runLogger.log(
            "Classification: \(result.counts.alreadyInDestinationCount) already in dest, \(result.counts.newCount) new, \(result.counts.duplicateCount) internal dups, \(result.counts.hashErrorCount) hash errors"
        )

        for info in result.infoMessages {
            runLogger.log(info)
        }
        for warning in result.warningMessages {
            runLogger.warn(warning)
        }

        // A batch that reduced to nothing is not an up-to-date library: every
        // file the customer confirmed has since been moved, deleted, or edited.
        // Falling through to the branch below would tell them their photos are
        // already safely copied, which is the opposite of what happened. No new
        // `RunStatus` for it — `.nothingToCopy` is accurate, and the warning
        // says why.
        if batch != nil, result.transferCount == 0 {
            let message = "None of the files in that batch are still where they were when you confirmed it, "
                + "so nothing was copied. Your originals were left untouched. Run a preview to see what is there now."
            runLogger.warn("Free test batch matched no planned transfers; nothing was enqueued or copied.")
            continuation.yield(.issue(RunIssue(severity: .warning, message: message)))
            continuation.yield(
                .complete(
                    RunSummary(
                        status: .nothingToCopy,
                        title: "Nothing left to copy",
                        metrics: RunMetrics(
                            discoveredCount: result.discoveredSourceCount,
                            plannedCount: 0,
                            alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                            duplicateCount: result.counts.duplicateCount,
                            hashErrorCount: result.counts.hashErrorCount,
                            dateHistogram: result.dateHistogram
                        ),
                        artifacts: transferExecutor.artifactPaths(destinationRoot: destinationURL)
                    )
                )
            )
            continuation.finish()
            return
        }

        if result.transferCount == 0 {
            // Finding #4: zero planned copies is only genuinely "up to date"
            // when every discovered file was accounted for. If some sources
            // could not be hashed, files are missing from the destination and
            // reporting success would be a lie.
            if result.counts.hashErrorCount > 0 {
                runLogger.warn("Nothing planned to copy, but \(result.counts.hashErrorCount) source file(s) could not be read")
                continuation.yield(
                    .complete(
                        RunSummary(
                            status: .failed,
                            title: "Some files couldn't be read",
                            metrics: RunMetrics(
                                discoveredCount: result.discoveredSourceCount,
                                plannedCount: 0,
                                alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                                duplicateCount: result.counts.duplicateCount,
                                hashErrorCount: result.counts.hashErrorCount,
                                dateHistogram: result.dateHistogram
                            ),
                            artifacts: transferExecutor.artifactPaths(destinationRoot: destinationURL),
                            failureMessage: "Chronoframe could not read \(result.counts.hashErrorCount) source file(s), so nothing was copied. Originals were left untouched; check file access and try again."
                        )
                    )
                )
                continuation.finish()
                return
            }
            runLogger.log("Nothing to copy — all files already in destination")
            continuation.yield(
                .complete(
                    RunSummary(
                        status: .nothingToCopy,
                        title: "Already up to date",
                        metrics: RunMetrics(
                            discoveredCount: result.discoveredSourceCount,
                            plannedCount: 0,
                            alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                            duplicateCount: result.counts.duplicateCount,
                            hashErrorCount: result.counts.hashErrorCount,
                            dateHistogram: result.dateHistogram
                        ),
                        artifacts: transferExecutor.artifactPaths(destinationRoot: destinationURL)
                    )
                )
            )
            continuation.finish()
            return
        }

        // One ID for the whole run, minted here and threaded down through the
        // trial reservation, the queued rows, the executor, and the audit
        // receipt — which is what lets crash recovery and refunds match a
        // reservation to the work that actually happened.
        let runID = UUID()

        // The gate. It sits after planning and after the zero-transfer branches
        // — planning and preview are free and must stay free — and before the
        // first thing that persists an intention to mutate. A refusal therefore
        // leaves no queued rows, no receipt, and no copied file.
        do {
            try await authorizeTransfer(
                runID: runID,
                fileCount: result.transferCount,
                destinationURL: destinationURL,
                authorizer: authorizer,
                runLogger: runLogger
            )
        } catch let error as TrialAuthorizationError {
            // The plan is still in hand here, and this is the only place it is.
            // A refusal that leaves allowance on the table carries the smaller
            // run that would fit, so the UI can offer it instead of sending
            // someone to Finder to build a smaller folder by hand (T15).
            throw TrialAuthorizationError.offeringFreeTestBatch(
                error,
                plannedTransfers: result.transfers
            )
        }

        // The gate is the only suspension point between the last cancellation
        // check and the first mutation, and it can be a slow one — resolving
        // entitlement may wait on the App Store. A cancel landing inside it has
        // already made `RunSessionStore` release the destination lease, so
        // enqueuing and copying past this point would mutate the destination
        // with no lock held.
        //
        // Releasing is safe here, and only here: the reservation was taken
        // moments ago and provably nothing has been enqueued, copied, or
        // written under it. That is the one condition `releaseMeteredWork`
        // allows; an ambiguous outcome anywhere later stays charged.
        if isCancelled() {
            await authorizer.releaseMeteredWork(runID: runID)
            continuation.finish()
            return
        }

        try database.enqueuePlannedTransfers(result.transfers, runID: runID)
        let errorCounter = IssueCounter()
        let executionResult = try transferExecutor.executeQueuedJobs(
            database: database,
            destinationRoot: destinationURL,
            verifyCopies: configuration.verifyCopies,
            runLogger: runLogger,
            status: .pending,
            orderByInsertion: true,
            maxConcurrentCopies: Self.maxConcurrentCopies(for: configuration),
            observer: TransferExecutionObserver(
                onPhaseStarted: { total, _ in
                    continuation.yield(.phaseStarted(phase: .copy, total: total))
                },
                onPhaseProgress: { completed, total, bytesCopied, bytesTotal, currentSourcePath in
                    continuation.yield(
                        .phaseProgress(
                            phase: .copy,
                            completed: completed,
                            total: total,
                            bytesCopied: Int(bytesCopied),
                            bytesTotal: Int(bytesTotal),
                            currentFilePath: currentSourcePath
                        )
                    )
                },
                onIssue: { issue in
                    if issue.severity == .error {
                        errorCounter.increment()
                    }
                    continuation.yield(.issue(issue))
                }
            ),
            isCancelled: isCancelled,
            runID: runID
        )

        // Before the cancellation check, not after: a cancel that arrives once
        // the last job has already landed leaves a settleable run, and skipping
        // the settle would keep it charged at the full reserved amount until a
        // later recovery pass happened to visit this destination.
        await settleReservation(runID: runID, database: database, authorizer: authorizer)

        if isCancelled() {
            continuation.finish()
            return
        }

        continuation.yield(
            .phaseCompleted(
                phase: .copy,
                result: RunPhaseResult(
                    copiedCount: executionResult.copiedCount,
                    failedCount: executionResult.failedCount
                )
            )
        )
        runLogger.log("Run complete")
        // Finding #4: a run that finished without hitting the abort threshold is
        // not necessarily a success. If any planned file failed to copy, was
        // skipped (source changed or unreadable), or could not be hashed during
        // planning, files are missing from the destination — report it honestly
        // rather than as "Done".
        let leftUnprocessed = executionResult.failedCount > 0
            || executionResult.skippedCount > 0
            || result.counts.hashErrorCount > 0
        let completedStatus: RunStatus
        let completedTitle: String
        if executionResult.status != "COMPLETED" {
            completedStatus = .failed
            completedTitle = "Transfer stopped"
        } else if leftUnprocessed {
            completedStatus = .failed
            completedTitle = "Transfer incomplete"
        } else {
            completedStatus = .finished
            completedTitle = "Done"
        }
        continuation.yield(
            .complete(
                RunSummary(
                    status: completedStatus,
                    title: completedTitle,
                    metrics: RunMetrics(
                        discoveredCount: result.discoveredSourceCount,
                        plannedCount: result.transferCount,
                        alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                        duplicateCount: result.counts.duplicateCount,
                        hashErrorCount: result.counts.hashErrorCount,
                        copiedCount: executionResult.copiedCount,
                        failedCount: executionResult.failedCount,
                        errorCount: errorCounter.value,
                        bytesCopied: executionResult.bytesCopied,
                        bytesTotal: executionResult.bytesTotal,
                        skippedCount: executionResult.skippedCount,
                        dateHistogram: result.dateHistogram
                    ),
                    artifacts: executionResult.artifacts,
                    failureMessage: completedStatus == .failed
                        ? "The transfer did not finish: \(executionResult.failedCount) failed and \(executionResult.skippedCount) were skipped. Originals were left untouched."
                        : nil
                )
            )
        )
        continuation.finish()
    }

    private nonisolated static func resumeTransfer(
        configuration: RunConfiguration,
        database: OrganizerDatabase,
        destinationURL: URL,
        transferExecutor: TransferExecutor,
        authorizer: any TrialAuthorizing,
        runLogger: PersistentRunLogger,
        isCancelled: @escaping @Sendable () -> Bool,
        continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) async throws {
        let pendingJobCount = try database.pendingJobCount()
        runLogger.log("Found \(pendingJobCount) pending jobs from interrupted session")

        if pendingJobCount == 0 {
            continuation.yield(
                .complete(
                    RunSummary(
                        status: .nothingToCopy,
                        title: "Already up to date",
                        metrics: RunMetrics(),
                        artifacts: transferExecutor.artifactPaths(destinationRoot: destinationURL)
                    )
                )
            )
            continuation.finish()
            return
        }

        // The Run screen's Timeline reads buckets from `metrics.dateHistogram`,
        // which is populated by this event. The fresh-transfer path emits it
        // from the planner result; on resume there's no planner run, so we
        // reconstruct it from the persisted job queue.
        let resumedHistogram = try resumeDateHistogram(database: database)
        if !resumedHistogram.isEmpty {
            continuation.yield(.dateHistogram(buckets: resumedHistogram))
        }

        // Continue the run being resumed rather than minting a new identity: the
        // queued rows, the receipt, and the trial reservation are all keyed by
        // this ID, and a resume must not look like a second run. Jobs enqueued
        // before run IDs were threaded carry none, so fall back to a fresh ID
        // rather than leaving the rows unattributable.
        let inheritedRunID = try database.queuedRunID(status: .pending)
        let resumeRunID = inheritedRunID ?? UUID()

        // Resuming does not double-charge, and does not need a special case to
        // avoid doing so: re-reserving a run ID that already has a reservation
        // row returns the stored decision and writes nothing (`TrialLedger`).
        //
        // The gate is still asked, because the fallback ID above is minted
        // exactly when the queue cannot be attributed to one run — legacy rows
        // predating run IDs, or a queue holding more than one run's leftovers.
        // No reservation covers that work, so it is metered here rather than
        // becoming a way to copy for free by resuming instead of starting.
        try await authorizeTransfer(
            runID: resumeRunID,
            fileCount: pendingJobCount,
            destinationURL: destinationURL,
            authorizer: authorizer,
            runLogger: runLogger
        )

        // Same window as the fresh path: the gate can suspend, and a cancel
        // inside it has already released the destination lease.
        //
        // Only a run ID minted moments ago is released. An INHERITED
        // reservation may already cover files the interrupted run copied, and
        // `release` zeroes a reservation outright — giving that charge back
        // would make work that is sitting in the destination free.
        if isCancelled() {
            if inheritedRunID == nil {
                await authorizer.releaseMeteredWork(runID: resumeRunID)
            }
            continuation.finish()
            return
        }

        let errorCounter = IssueCounter()
        let executionResult = try transferExecutor.executeQueuedJobs(
            database: database,
            destinationRoot: destinationURL,
            verifyCopies: configuration.verifyCopies,
            runLogger: runLogger,
            status: .pending,
            orderByInsertion: true,
            maxConcurrentCopies: Self.maxConcurrentCopies(for: configuration),
            observer: TransferExecutionObserver(
                onPhaseStarted: { total, _ in
                    continuation.yield(.phaseStarted(phase: .copy, total: total))
                },
                onPhaseProgress: { completed, total, bytesCopied, bytesTotal, currentSourcePath in
                    continuation.yield(
                        .phaseProgress(
                            phase: .copy,
                            completed: completed,
                            total: total,
                            bytesCopied: Int(bytesCopied),
                            bytesTotal: Int(bytesTotal),
                            currentFilePath: currentSourcePath
                        )
                    )
                },
                onIssue: { issue in
                    if issue.severity == .error {
                        errorCounter.increment()
                    }
                    continuation.yield(.issue(issue))
                }
            ),
            isCancelled: isCancelled,
            runID: resumeRunID
        )

        await settleReservation(runID: resumeRunID, database: database, authorizer: authorizer)

        if isCancelled() {
            continuation.finish()
            return
        }

        continuation.yield(
            .phaseCompleted(
                phase: .copy,
                result: RunPhaseResult(
                    copiedCount: executionResult.copiedCount,
                    failedCount: executionResult.failedCount
                )
            )
        )
        runLogger.log("Resumed session complete")
        // Finding #4: mirror the fresh-transfer honesty — a resumed run that
        // failed or skipped any pending job did not finish the job queue.
        let leftUnprocessed = executionResult.failedCount > 0 || executionResult.skippedCount > 0
        let completedStatus: RunStatus
        let completedTitle: String
        if executionResult.status != "COMPLETED" {
            completedStatus = .failed
            completedTitle = "Transfer stopped"
        } else if leftUnprocessed {
            completedStatus = .failed
            completedTitle = "Transfer incomplete"
        } else {
            completedStatus = .finished
            completedTitle = "Done"
        }
        continuation.yield(
            .complete(
                RunSummary(
                    status: completedStatus,
                    title: completedTitle,
                    metrics: RunMetrics(
                        plannedCount: pendingJobCount,
                        copiedCount: executionResult.copiedCount,
                        failedCount: executionResult.failedCount,
                        errorCount: errorCounter.value,
                        bytesCopied: executionResult.bytesCopied,
                        bytesTotal: executionResult.bytesTotal,
                        skippedCount: executionResult.skippedCount,
                        dateHistogram: resumedHistogram
                    ),
                    artifacts: executionResult.artifacts,
                    failureMessage: completedStatus == .failed
                        ? "The resumed transfer did not finish: \(executionResult.failedCount) failed and \(executionResult.skippedCount) were skipped. Originals were left untouched."
                        : nil
                )
            )
        )
        continuation.finish()
    }

    // MARK: - Trial gate (free-trial step 4, T8)

    /// Reserve trial allowance for `fileCount` files, or refuse the run.
    ///
    /// Throws rather than returning, so a caller cannot forget to check: every
    /// path that reaches a mutation has to have gone through a `try`.
    private nonisolated static func authorizeTransfer(
        runID: UUID,
        fileCount: Int,
        destinationURL: URL,
        authorizer: any TrialAuthorizing,
        runLogger: PersistentRunLogger
    ) async throws {
        let authorization = await authorizer.authorizeMeteredWork(
            runID: runID,
            meter: .organize,
            count: fileCount,
            // Standardized because reconciliation matches an open reservation
            // to a destination by path. It resolves symlinks on both sides, so
            // this only has to avoid gratuitous `.`/`..` differences.
            destinationRoot: destinationURL.standardizedFileURL.path
        )
        guard let refusal = authorization.refusal else { return }

        // Deliberately says nothing about why. The log lives inside the
        // destination the customer can hand to anyone; the reason belongs in
        // the message they see, not in a file on disk.
        runLogger.warn(
            "Transfer not started: \(fileCount) file(s) were not authorized. Nothing was enqueued or copied."
        )
        throw TrialAuthorizationError(refusal: refusal)
    }

    /// Settle the run's reservation with the number of files that actually
    /// landed.
    ///
    /// This is `FileSystemTrialReconciliationEvidence`'s rule for organize,
    /// applied in-process while the database is already open, and it is
    /// deliberately the same rule rather than a shortcut:
    ///
    /// - **Jobs still pending means the run is not over.** A crashed or aborted
    ///   run keeps its unfinished jobs `PENDING` so the user can resume. Settling
    ///   now would charge the partial count, and because `finalize` only ever
    ///   acts on an open reservation, everything the resume then copies would be
    ///   free.
    /// - **A count that cannot be read settles nothing.** `finalize` is one-way,
    ///   so a wrong number can never be corrected; an open reservation stays
    ///   charged in full and is retried by reconciliation, which is the
    ///   recoverable direction to be wrong in.
    ///
    /// Nothing here releases. A run whose outcome is ambiguous stays charged
    /// until evidence — not an assumption — says otherwise.
    private nonisolated static func settleReservation(
        runID: UUID,
        database: OrganizerDatabase,
        authorizer: any TrialAuthorizing
    ) async {
        guard let resumable = try? database.resumableJobCount(runID: runID), resumable == 0,
              let landed = try? database.completedJobCount(runID: runID)
        else { return }
        await authorizer.finalizeMeteredWork(runID: runID, actualCount: landed)
    }

    private nonisolated static func resumeDateHistogram(
        database: OrganizerDatabase
    ) throws -> [DateHistogramBucket] {
        let pendingJobs = try database.loadQueuedJobs(status: .pending, orderByInsertion: true)
        return CopyPlanBuilder.dateHistogram(
            fromDestinationPaths: pendingJobs.lazy.map { $0.destinationPath },
            namingRules: .chronoframeDefault
        )
    }

    private nonisolated static func maxConcurrentCopies(for configuration: RunConfiguration) -> Int {
        guard configuration.parallelTransferEnabled else {
            return 1
        }
        return min(max(1, configuration.workerCount), 4)
    }

    /// Emits the summary events that follow the planner walk.
    /// `destinationIndexing` and `sourceHashing` are already streamed live by the
    /// planner via `onEvent`; this method emits the classification summary and the
    /// final `copyPlanReady` event after `plan()` returns.
    private nonisolated static func emitPostPlanningEvents(
        for result: DryRunPlanningResult,
        into continuation: AsyncThrowingStream<RunEvent, Error>.Continuation
    ) {
        continuation.yield(.phaseStarted(phase: .classification, total: result.counts.newCount))
        continuation.yield(
            .phaseCompleted(
                phase: .classification,
                result: RunPhaseResult(
                    newCount: result.counts.newCount,
                    alreadyInDestinationCount: result.counts.alreadyInDestinationCount,
                    duplicateCount: result.counts.duplicateCount,
                    hashErrorCount: result.counts.hashErrorCount
                )
            )
        )

        continuation.yield(.dateHistogram(buckets: result.dateHistogram))

        for info in result.infoMessages {
            continuation.yield(.issue(RunIssue(severity: .info, message: info)))
        }
        for warning in result.warningMessages {
            continuation.yield(.issue(RunIssue(severity: .warning, message: warning)))
        }
        continuation.yield(.copyPlanReady(count: result.transferCount))
    }

    nonisolated private static func writeDryRunArtifacts(
        result: DryRunPlanningResult,
        destinationRoot: String
    ) throws -> RunArtifactPaths {
        let destinationURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
        let logsDirectoryURL = destinationURL.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)

        let timestamp = Self.timestampFormatter.string(from: Date())
        let reportURL = logsDirectoryURL.appendingPathComponent("dry_run_report_\(timestamp).csv")
        let previewReviewURL = logsDirectoryURL.appendingPathComponent("preview_review_\(timestamp).jsonl")
        let logURL = destinationURL.appendingPathComponent(".organize_log.txt")

        try writeReport(result.transfers, to: reportURL)
        try writePreviewReview(result.previewReviewItems, to: previewReviewURL)
        if !FileManager.default.fileExists(atPath: logURL.path) {
            try Data().write(to: logURL)
        }

        return RunArtifactPaths(
            destinationRoot: destinationRoot,
            reportPath: reportURL.path,
            previewReviewPath: previewReviewURL.path,
            logFilePath: logURL.path,
            logsDirectoryPath: logsDirectoryURL.path
        )
    }

    nonisolated private static func writeReport(_ transfers: [PlannedTransfer], to reportURL: URL) throws {
        let temporaryReportURL = reportURL.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: temporaryReportURL.path, contents: Data())
        let handle = try FileHandle(forWritingTo: temporaryReportURL)

        do {
            try handle.write(contentsOf: Data("Source,Destination,Hash,Status\n".utf8))
            for transfer in transfers {
                let row = [
                    csvField(transfer.sourcePath),
                    csvField(transfer.destinationPath),
                    csvField(transfer.identity.rawValue),
                    csvField(CopyJobStatus.pending.rawValue),
                ]
                .joined(separator: ",") + "\n"
                try handle.write(contentsOf: Data(row.utf8))
            }
            try handle.close()

            if FileManager.default.fileExists(atPath: reportURL.path) {
                try FileManager.default.removeItem(at: reportURL)
            }
            try FileManager.default.moveItem(at: temporaryReportURL, to: reportURL)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporaryReportURL)
            throw error
        }
    }

    nonisolated private static func csvField(_ value: String) -> String {
        "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    nonisolated private static func writePreviewReview(
        _ items: [PreviewReviewItem],
        to url: URL
    ) throws {
        let temporaryURL = url.appendingPathExtension("tmp")
        FileManager.default.createFile(atPath: temporaryURL.path, contents: Data())
        let handle = try FileHandle(forWritingTo: temporaryURL)
        let encoder = JSONEncoder()

        do {
            for item in items {
                let data = try encoder.encode(item)
                try handle.write(contentsOf: data)
                try handle.write(contentsOf: Data("\n".utf8))
            }
            try handle.close()

            if FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            try FileManager.default.moveItem(at: temporaryURL, to: url)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    nonisolated private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

private final class IssueCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0

    var value: Int {
        lock.withLock { _value }
    }

    func increment() {
        lock.withLock { _value += 1 }
    }
}

/// Sendable cancel-flag shared between the main-actor engine and the detached
/// task driving a revert/reorganize stream. The continuation's `onTermination`
/// callback flips it; the executor body polls `isCancelled` between items.
private final class TaskCancellationCheck: @unchecked Sendable {
    private let lock = NSLock()
    private var _cancelled = false
    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return _cancelled
    }
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        _cancelled = true
    }
}
