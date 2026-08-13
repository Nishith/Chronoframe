#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import Combine
import UserNotifications
#if canImport(AppKit)
import AppKit
#endif

/// Typed, once-per-run completion notice. Consumers that react to
/// finished runs (watched-source checkpoint advancement, import-context
/// cleanup) key off this record instead of correlating `$summary` with
/// the mutable `lastPreflight` — the record snapshots the run's identity
/// and resolved paths atomically at the moment it ends.
public struct RunCompletionRecord: Equatable, Sendable {
    /// Unique per accepted run request in this session.
    public let runToken: UUID
    public let mode: RunMode?
    public let status: RunStatus
    /// The resolved configuration the engine actually ran (nil for
    /// revert/reorganize flows, which have no RunConfiguration).
    public let configuration: RunConfiguration?
    public let resolvedSourcePath: String?
    public let resolvedDestinationPath: String?
    public let finishedAt: Date

    public init(
        runToken: UUID,
        mode: RunMode?,
        status: RunStatus,
        configuration: RunConfiguration?,
        resolvedSourcePath: String?,
        resolvedDestinationPath: String?,
        finishedAt: Date
    ) {
        self.runToken = runToken
        self.mode = mode
        self.status = status
        self.configuration = configuration
        self.resolvedSourcePath = resolvedSourcePath
        self.resolvedDestinationPath = resolvedDestinationPath
        self.finishedAt = finishedAt
    }
}

@MainActor
public final class RunSessionStore: ObservableObject {
    @Published public private(set) var status: RunStatus
    @Published public private(set) var currentMode: RunMode?
    @Published public private(set) var currentTaskTitle: String
    @Published public private(set) var currentPhase: RunPhase?
    @Published public private(set) var progress: Double
    @Published public private(set) var metrics: RunMetrics
    @Published public private(set) var artifacts: RunArtifactPaths
    @Published public private(set) var summary: RunSummary?
    @Published public private(set) var prompt: RunPrompt?
    @Published public private(set) var lastPreflight: RunPreflight?
    @Published public private(set) var lastErrorMessage: String?
    /// Set instead of left to `lastErrorMessage` alone when a run was refused
    /// rather than broken.
    ///
    /// A refusal is not a failure, and the difference decides what the customer
    /// is offered: `allowanceSpent` may lead to the unlock, `purchaseUnconfirmed`
    /// must not, and the App Intent has to turn either into "open Chronoframe"
    /// rather than attempting a purchase in the background. Recovering that from
    /// the formatted message string would mean parsing English.
    @Published public private(set) var lastRefusal: TrialAuthorizationRefusal?

    /// A smaller run the remaining allowance covers, offered alongside the
    /// refusal (free-trial step 5, T15).
    ///
    /// Set only when the engine could honestly propose one. Nil means the only
    /// way forward is the unlock.
    @Published public private(set) var lastOfferedBatch: FreeTestBatch?

    /// Whether the run currently streaming is limited to a confirmed batch.
    private var currentRunUsedFreeTestBatch = false
    @Published public private(set) var latestPreviewReviewPath: String?
    /// Source URL of the file currently being copied, surfaced by the
    /// transfer phase. UI uses it to render a live QuickLook thumbnail in
    /// the Now-Copying card. `nil` outside of the copy phase or when the
    /// engine has not yet reported a file (e.g. between phases).
    @Published public private(set) var currentFileURL: URL?
    /// Published exactly once per run, when it reaches a terminal state
    /// (complete, failed, or cancelled mid-run). See `RunCompletionRecord`.
    @Published public private(set) var lastRunCompletion: RunCompletionRecord?

    /// Identifies the current accepted run request; snapshotted into
    /// `RunCompletionRecord.runToken` so consumers can match a completion
    /// to the request they initiated.
    public private(set) var currentRunToken = UUID()

    private let engine: any OrganizerEngine
    private let logStore: RunLogStore
    private let historyStore: HistoryStore
    private var streamTask: Task<Void, Never>?
    private var securityScope: SecurityScopedFolderAccess?
    private var preparedRun: PreparedRun?
    private var directOperationLease: DestinationOperationLease?
    private var copySpeedLastSampleDate = Date()
    private var copySpeedLastBytes = 0
    private var currentPhaseStartDate: Date?
    /// Monotonic token used to drop events from cancelled or replaced
    /// stream tasks. A long-running engine task may yield one more event
    /// after `cancel()` is called but before its `for try await` loop
    /// reaches the next checkpoint, and that yield can race with a new
    /// run the user has just started. Each `streamTask` captures the
    /// epoch value at start; `consumeIfCurrent` drops events whose epoch
    /// no longer matches.
    private var currentRunEpoch: UInt64 = 0
    /// Surfaces a one-time warning when the destination is on a network volume,
    /// where the cross-process lock can't guarantee single-machine access.
    /// Internal so tests can inject a stubbed advisory + scratch defaults.
    var networkAdvisory = NetworkDestinationAdvisory()

    public init(engine: any OrganizerEngine, logStore: RunLogStore, historyStore: HistoryStore) {
        self.engine = engine
        self.logStore = logStore
        self.historyStore = historyStore
        self.status = .idle
        self.currentMode = nil
        self.currentTaskTitle = "Idle"
        self.currentPhase = nil
        self.progress = 0
        self.metrics = RunMetrics()
        self.artifacts = RunArtifactPaths()
        self.summary = nil
        self.prompt = nil
        self.lastPreflight = nil
        self.lastErrorMessage = nil
        self.lastRefusal = nil
        self.latestPreviewReviewPath = nil
    }

    public var isRunning: Bool {
        // Finding #7: preflight is part of an in-flight operation. Excluding it
        // let a second run (or a dedupe operation) start during the preflight
        // window. Callers that gate "can another operation begin?" must see the
        // app as busy from the moment a run is requested.
        status == .running || status == .preflighting
    }

    public var logLines: [String] {
        logStore.lines
    }

    public var issueCount: Int {
        max(metrics.errorCount, metrics.hashErrorCount + metrics.failedCount)
    }

    /// - Parameter batch: a confirmed free test batch (T15). When present the
    ///   run copies only those files, and the generic "Start Transfer?" prompt
    ///   is skipped — the batch sheet the customer just confirmed showed them
    ///   the exact reduced plan, and asking again would be asking twice about
    ///   the same run.
    public func requestRun(
        mode: RunMode,
        configuration: RunConfiguration,
        securityScope: SecurityScopedFolderAccess? = nil,
        batch: FreeTestBatchSelection? = nil
    ) async {
        resetSessionState(mode: mode)
        // Finding #7: capture the epoch AFTER resetSessionState bumps it. If a
        // newer run starts (or the user cancels) while we await preflight, the
        // epoch advances and this completion is stale — its security scope has
        // already been closed and its UI state replaced. Discarding it prevents
        // a stale preflight from overwriting the newer request's prompt or
        // running against an access scope that is no longer held.
        let epoch = currentRunEpoch
        self.securityScope = securityScope
        status = .preflighting
        currentTaskTitle = "Preparing \(mode.title)..."

        do {
            let preparedRun = try await engine.prepare(configuration)
            guard currentRunEpoch == epoch else { return }
            self.preparedRun = preparedRun
            let preflight = preparedRun.preflight
            lastPreflight = preflight

            // A batch must never start on top of a queue somebody else left
            // behind. `TransferExecutor.executeQueuedJobs` selects pending rows
            // by status alone — there is no run_id filter — so a batch run
            // would copy the stale jobs too: without confirmation, and past the
            // count that was just authorized. The resume/start-fresh prompt is
            // the existing decision for that queue, and it has to happen first.
            if batch != nil, preflight.pendingJobCount > 0 {
                prompt = RunPrompt(
                    kind: .blockingError,
                    title: "Finish the interrupted transfer first",
                    message: "Chronoframe found \(preflight.pendingJobCount) copy job"
                        + "\(preflight.pendingJobCount == 1 ? "" : "s") still queued from a transfer that "
                        + "was interrupted. Start a transfer to resume or discard them, then run the free "
                        + "test batch. Nothing was copied and your originals were left untouched.",
                    preflight: preflight
                )
                return
            }

            if mode == .transfer, batch == nil {
                let promptKind: RunPromptKind = preflight.pendingJobCount > 0 ? .resumePendingJobs : .confirmTransfer
                let message: String
                if preflight.pendingJobCount > 0 {
                    message = "Chronoframe found \(preflight.pendingJobCount) pending copy jobs in the destination queue. Continue by resuming the persisted transfer?"
                } else {
                    message = "Chronoframe will leave the source untouched and transfer into \(preflight.resolvedDestinationPath). Continue?"
                }

                prompt = RunPrompt(
                    kind: promptKind,
                    title: preflight.pendingJobCount > 0 ? "Resume Pending Transfer" : "Start Transfer",
                    message: message,
                    preflight: preflight
                )
                return
            }

            beginStream(using: preflight, resumePendingJobs: false, batch: batch)
        } catch {
            guard currentRunEpoch == epoch else { return }
            handleFailure(error: error)
        }
    }

    /// Run a revert against the audit receipt at `receiptURL`. Streams the
    /// engine's `RunEvent`s into this store so the standard Run workspace
    /// renders progress, issues, and the final summary.
    public func requestRevert(
        receiptURL: URL,
        destinationRoot: String,
        securityScope: SecurityScopedFolderAccess? = nil
    ) {
        resetSessionState(mode: .revert)
        do {
            let root = URL(fileURLWithPath: destinationRoot, isDirectory: true)
            directOperationLease = try DestinationOperationLock.acquire(
                destinationRoot: root,
                surface: "app",
                operation: "revert"
            )
            _ = DestinationRecovery.recoverAndReconcile(destinationRoot: root)
        } catch {
            handleFailure(error: error)
            return
        }
        self.securityScope = securityScope
        status = .running
        currentTaskTitle = "Reverting…"
        artifacts = RunArtifactPaths(
            destinationRoot: destinationRoot,
            reportPath: receiptURL.path,
            logFilePath: nil,
            logsDirectoryPath: URL(fileURLWithPath: destinationRoot)
                .appendingPathComponent(".organize_logs", isDirectory: true).path
        )
        emitNetworkDestinationWarningIfNeeded(forDestinationPath: destinationRoot)

        let epoch = currentRunEpoch
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = try engine.revert(receiptURL: receiptURL, destinationRoot: destinationRoot)
                for try await event in stream {
                    guard self.currentRunEpoch == epoch else { return }
                    self.consume(event)
                }
                guard self.currentRunEpoch == epoch else { return }
                self.preparedRun?.lease.release()
                self.preparedRun = nil
                self.directOperationLease?.release()
                self.directOperationLease = nil
            } catch {
                guard self.currentRunEpoch == epoch else { return }
                self.handleFailure(error: error)
            }
        }
    }

    /// Reorganize the destination layout to match `targetStructure`. Streams
    /// engine events into this store identically to `requestRun` so the same
    /// UI surface renders progress.
    public func requestReorganize(
        destinationRoot: String,
        targetStructure: FolderStructure,
        securityScope: SecurityScopedFolderAccess? = nil
    ) {
        resetSessionState(mode: .reorganize)
        do {
            let root = URL(fileURLWithPath: destinationRoot, isDirectory: true)
            directOperationLease = try DestinationOperationLock.acquire(
                destinationRoot: root,
                surface: "app",
                operation: "reorganize"
            )
            _ = DestinationRecovery.recoverAndReconcile(destinationRoot: root)
        } catch {
            handleFailure(error: error)
            return
        }
        self.securityScope = securityScope
        status = .running
        currentTaskTitle = "Reorganizing…"
        artifacts = RunArtifactPaths(destinationRoot: destinationRoot)
        emitNetworkDestinationWarningIfNeeded(forDestinationPath: destinationRoot)

        let epoch = currentRunEpoch
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let stream = try engine.reorganize(
                    destinationRoot: destinationRoot,
                    targetStructure: targetStructure
                )
                for try await event in stream {
                    guard self.currentRunEpoch == epoch else { return }
                    self.consume(event)
                }
                guard self.currentRunEpoch == epoch else { return }
                self.directOperationLease?.release()
                self.directOperationLease = nil
            } catch {
                guard self.currentRunEpoch == epoch else { return }
                self.handleFailure(error: error)
            }
        }
    }

    public func requestReorganizeRevert(
        receiptURL: URL,
        destinationRoot: String,
        securityScope: SecurityScopedFolderAccess? = nil
    ) {
        resetSessionState(mode: .reorganize)
        do {
            let root = URL(fileURLWithPath: destinationRoot, isDirectory: true)
            directOperationLease = try DestinationOperationLock.acquire(
                destinationRoot: root,
                surface: "app",
                operation: "reorganize revert"
            )
            _ = DestinationRecovery.recoverAndReconcile(destinationRoot: root)
        } catch {
            handleFailure(error: error)
            return
        }
        self.securityScope = securityScope
        status = .running
        currentTaskTitle = "Undoing Reorganize…"
        artifacts = RunArtifactPaths(
            destinationRoot: destinationRoot,
            reportPath: receiptURL.path,
            logFilePath: nil,
            logsDirectoryPath: URL(fileURLWithPath: destinationRoot)
                .appendingPathComponent(".organize_logs", isDirectory: true).path
        )
        emitNetworkDestinationWarningIfNeeded(forDestinationPath: destinationRoot)

        let epoch = currentRunEpoch
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let executor = ReorganizeExecutor()
            let observer = ReorganizeExecutionObserver(
                onTaskStart: { total in
                    Task { @MainActor [weak self] in
                        guard let self, self.currentRunEpoch == epoch else { return }
                        self.consume(.phaseStarted(phase: .reorganize, total: total))
                    }
                },
                onTaskProgress: { completed, total in
                    Task { @MainActor [weak self] in
                        guard let self, self.currentRunEpoch == epoch else { return }
                        self.consume(.phaseProgress(
                            phase: .reorganize,
                            completed: completed,
                            total: total,
                            bytesCopied: nil,
                            bytesTotal: nil,
                            currentFilePath: nil
                        ))
                    }
                },
                onIssue: { issue in
                    Task { @MainActor [weak self] in
                        guard let self, self.currentRunEpoch == epoch else { return }
                        self.consume(.issue(issue))
                    }
                }
            )
            // Suspend the main actor during heavy file hashing and moves so the
            // UI stays responsive. The @MainActor Task resumes here after the
            // DispatchQueue work completes.
            let outcome: Result<ReorganizeExecutionResult, Error> = await withCheckedContinuation { cont in
                DispatchQueue.global(qos: .userInitiated).async {
                    cont.resume(returning: Result { try executor.revert(receiptURL: receiptURL, observer: observer) })
                }
            }
            guard self.currentRunEpoch == epoch else { return }
            switch outcome {
            case let .success(result):
                self.consume(.phaseCompleted(
                    phase: .reorganize,
                    result: RunPhaseResult(
                        failedCount: result.failedCount,
                        skippedCount: result.skippedCount,
                        movedCount: result.movedCount
                    )
                ))
                self.consume(.complete(RunSummary(
                    status: .reorganized,
                    title: "Reorganize undone",
                    metrics: RunMetrics(
                        plannedCount: result.totalMoves,
                        failedCount: result.failedCount,
                        skippedCount: result.skippedCount,
                        movedCount: result.movedCount
                    ),
                    artifacts: self.artifacts
                )))
            case let .failure(error):
                self.handleFailure(error: error)
            }
        }
    }

    public func confirmPrompt() {
        guard let prompt else { return }

        switch prompt.kind {
        case .blockingError:
            dismissPrompt()
        case .confirmTransfer:
            guard let preflight = prompt.preflight else {
                dismissPrompt()
                return
            }
            beginStream(using: preflight, resumePendingJobs: false)
        case .resumePendingJobs:
            guard let preflight = prompt.preflight else {
                dismissPrompt()
                return
            }
            beginStream(using: preflight, resumePendingJobs: true)
        }
    }

    /// Discards the stale pending queue at the destination and starts a full
    /// re-plan + transfer, identical to a first-time transfer run.
    public func confirmPromptStartFresh() {
        guard let prompt, let preflight = prompt.preflight else {
            dismissPrompt()
            return
        }
        clearAllJobs(at: preflight.resolvedDestinationPath)
        beginStream(using: preflight, resumePendingJobs: false)
    }

    public func dismissPrompt() {
        prompt = nil
        if status == .preflighting {
            preparedRun?.lease.release()
            preparedRun = nil
            status = .idle
            currentTaskTitle = "Idle"
            closeSecurityScope()
        }
    }

    public func cancelCurrentRun() {
        engine.cancelCurrentRun()
        streamTask?.cancel()
        streamTask = nil
        currentRunEpoch &+= 1

        // Only an actively-running stream produces a "Cancelled" summary. A
        // cancel during preflight is handled below by resetting to idle, so
        // this checks `.running` explicitly rather than `isRunning` (which now
        // also covers `.preflighting`).
        if status == .running {
            status = .cancelled
            currentTaskTitle = "Cancelled"
            metrics.speedMBps = 0
            metrics.etaSeconds = nil
            summary = RunSummary(
                status: .cancelled,
                title: "Cancelled",
                metrics: metrics,
                artifacts: artifacts
            )
            publishRunCompletion(status: .cancelled)
        }
        // Phase 1: a pending confirm-prompt was previously left in
        // place when the user cancelled from the Run workspace, so the
        // confirm dialog would stay modal over an already-cancelled
        // run. Clear it so the UI resets cleanly. Also drop the
        // preflight status if we were sitting on it — the prior path
        // only cleared status when `isRunning` was already true.
        prompt = nil
        preparedRun?.lease.release()
        preparedRun = nil
        directOperationLease?.release()
        directOperationLease = nil
        if status == .preflighting {
            status = .idle
            currentTaskTitle = ""
        }
        closeSecurityScope()
    }

    private func resetSessionState(mode: RunMode) {
        if streamTask != nil || status == .running {
            engine.cancelCurrentRun()
        }
        streamTask?.cancel()
        streamTask = nil
        currentRunEpoch &+= 1
        currentRunToken = UUID()
        preparedRun?.lease.release()
        preparedRun = nil
        directOperationLease?.release()
        directOperationLease = nil
        closeSecurityScope()
        currentMode = mode
        currentPhase = nil
        currentTaskTitle = "Idle"
        progress = 0
        metrics = RunMetrics()
        artifacts = RunArtifactPaths()
        summary = nil
        prompt = nil
        lastPreflight = nil
        lastErrorMessage = nil
        lastRefusal = nil
        latestPreviewReviewPath = nil
        currentFileURL = nil
        logStore.clear()
        copySpeedLastSampleDate = Date()
        copySpeedLastBytes = 0
        currentPhaseStartDate = nil
    }

    /// Discards the interrupted run's queue, settling its trial reservation
    /// from that queue's own evidence first — see
    /// `DestinationRecovery.settleAndDiscardQueue`, which is where the ordering
    /// that makes the charge honest lives.
    private func clearAllJobs(at destinationPath: String) {
        do {
            try DestinationRecovery.settleAndDiscardQueue(
                destinationRoot: URL(fileURLWithPath: destinationPath, isDirectory: true)
            )
        } catch {
            // Non-fatal: if we can't clear the old queue the fresh plan will
            // still run; some jobs may be skipped by INSERT OR IGNORE but the
            // transfer will proceed as best it can.
        }
    }

    private func beginStream(
        using preflight: RunPreflight,
        resumePendingJobs: Bool,
        batch: FreeTestBatchSelection? = nil
    ) {
        // Read back when the run completes: a zero-copy outcome means something
        // different for a batch than for a full transfer, and the completion
        // notification has to say which.
        currentRunUsedFreeTestBatch = batch != nil
        prompt = nil
        status = .running
        currentMode = preflight.configuration.mode
        currentTaskTitle = resumePendingJobs ? "Resuming transfer..." : "Starting \(preflight.configuration.mode.title.lowercased())..."
        artifacts = RunArtifactPaths(
            destinationRoot: preflight.resolvedDestinationPath,
            reportPath: nil,
            logFilePath: URL(fileURLWithPath: preflight.resolvedDestinationPath).appendingPathComponent(".organize_log.txt").path,
            logsDirectoryPath: URL(fileURLWithPath: preflight.resolvedDestinationPath).appendingPathComponent(".organize_logs", isDirectory: true).path
        )

        emitNetworkDestinationWarningIfNeeded(forDestinationPath: preflight.resolvedDestinationPath)

        let epoch = currentRunEpoch
        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }

            do {
                let stream: AsyncThrowingStream<RunEvent, Error>
                if let batch {
                    stream = try engine.start(preflight.configuration, batch: batch)
                } else if resumePendingJobs {
                    stream = try engine.resume(preflight.configuration)
                } else {
                    stream = try engine.start(preflight.configuration)
                }

                for try await event in stream {
                    guard self.currentRunEpoch == epoch else { return }
                    self.consume(event)
                }
                guard self.currentRunEpoch == epoch else { return }
                self.preparedRun?.lease.release()
                self.preparedRun = nil
            } catch {
                guard self.currentRunEpoch == epoch else { return }
                self.handleFailure(error: error)
            }
        }
    }

    /// Emit a one-time warning issue when the run targets a network volume.
    /// Best-effort and advisory only — it never blocks the run.
    private func emitNetworkDestinationWarningIfNeeded(forDestinationPath path: String) {
        let root = URL(fileURLWithPath: path, isDirectory: true)
        guard let message = networkAdvisory.warningIfNeeded(for: root) else { return }
        consume(.issue(RunIssue(severity: .warning, message: message)))
    }

    private func consume(_ event: RunEvent) {
        switch event {
        case .startup:
            currentTaskTitle = "Initializing..."
            logStore.append("Engine started.")

        case let .phaseStarted(phase, total):
            currentPhase = phase
            currentPhaseStartDate = Date()
            if Self.usesFileCountETA(phase), let total, total > 0 {
                currentTaskTitle = Self.formattedFileProgressTitle(
                    phase: phase,
                    completed: 0,
                    total: total,
                    etaSeconds: nil
                )
            } else {
                currentTaskTitle = phase.runningTitle
            }
            progress = 0
            metrics.speedMBps = 0
            metrics.etaSeconds = nil
            if phase == .copy {
                if let total {
                    metrics.plannedCount = max(metrics.plannedCount, total)
                }
                metrics.bytesCopied = 0
                metrics.bytesTotal = 0
                copySpeedLastBytes = 0
                copySpeedLastSampleDate = Date()
            }

        case let .phaseProgress(phase, completed, total, bytesCopied, bytesTotal, currentFilePath):
            if phase == .copy {
                if let path = currentFilePath, !path.isEmpty {
                    currentFileURL = URL(fileURLWithPath: path)
                }
            } else {
                currentFileURL = nil
            }
            if total > 0 {
                progress = Double(completed) / Double(total)
                if phase == .copy {
                    currentTaskTitle = "\(phase.runningTitle) \(completed.formatted()) of \(total.formatted()) files…"
                } else if Self.usesFileCountETA(phase) {
                    let etaSeconds = estimatedFileETA(completed: completed, total: total)
                    metrics.etaSeconds = etaSeconds
                    currentTaskTitle = Self.formattedFileProgressTitle(
                        phase: phase,
                        completed: completed,
                        total: total,
                        etaSeconds: etaSeconds
                    )
                }
            } else {
                // total == 0 means indeterminate (count is known, total is not).
                // Show the running count in the title so the user sees forward progress.
                currentTaskTitle = "\(phase.runningTitle) \(completed.formatted()) files…"
                if Self.usesFileCountETA(phase) {
                    metrics.etaSeconds = nil
                }
            }

            // Keep the Copied metric card updated live during the copy phase
            // so the user sees forward progress rather than "0" the whole time.
            if phase == .copy {
                metrics.copiedCount = completed
            }

            guard phase == .copy, let bytesCopied, let bytesTotal, bytesTotal > 0 else { return }
            metrics.bytesCopied = Int64(bytesCopied)
            metrics.bytesTotal = Int64(bytesTotal)
            let now = Date()
            let elapsed = now.timeIntervalSince(copySpeedLastSampleDate)
            if elapsed >= 0.5 {
                let delta = bytesCopied - copySpeedLastBytes
                metrics.speedMBps = Double(delta) / elapsed / 1_000_000
                if metrics.speedMBps > 0 {
                    metrics.etaSeconds = Double(bytesTotal - bytesCopied) / (metrics.speedMBps * 1_000_000)
                }
                copySpeedLastBytes = bytesCopied
                copySpeedLastSampleDate = now
            }

        case let .phaseCompleted(phase, result):
            progress = 1
            metrics.speedMBps = 0
            metrics.etaSeconds = nil

            switch phase {
            case .discovery:
                metrics.discoveredCount = result.found ?? metrics.discoveredCount
            case .classification:
                metrics.alreadyInDestinationCount = result.alreadyInDestinationCount ?? metrics.alreadyInDestinationCount
                metrics.duplicateCount = result.duplicateCount ?? metrics.duplicateCount
                metrics.hashErrorCount = result.hashErrorCount ?? metrics.hashErrorCount
                logStore.append("Classification complete:")
                logStore.append("  New files:        \(result.newCount ?? 0)")
                logStore.append("  Already in dest:  \(result.alreadyInDestinationCount ?? 0)")
                logStore.append("  Duplicates:       \(result.duplicateCount ?? 0)")
                if let hashErrors = result.hashErrorCount, hashErrors > 0 {
                    logStore.append("  Hash errors:      \(hashErrors)")
                }
            case .copy:
                metrics.copiedCount = result.copiedCount ?? metrics.copiedCount
                metrics.failedCount = result.failedCount ?? metrics.failedCount
                currentFileURL = nil
                logStore.append("Copy complete: \(result.copiedCount ?? 0) succeeded, \(result.failedCount ?? 0) failed.")
            case .sourceHashing:
                // The planner carries the final discovered count in the sourceHashing
                // phaseCompleted. Propagate it so the Discovered metric card updates
                // as soon as the walk finishes (before the discovery summary fires).
                if let found = result.found {
                    metrics.discoveredCount = found
                }
            case .destinationIndexing:
                break
            case .revert:
                metrics.revertedCount = result.revertedCount ?? metrics.revertedCount
                metrics.skippedCount = result.skippedCount ?? metrics.skippedCount
                metrics.missingCount = result.missingCount ?? metrics.missingCount
                logStore.append(
                    "Revert complete: \(result.revertedCount ?? 0) reverted, "
                    + "\(result.skippedCount ?? 0) preserved, "
                    + "\(result.missingCount ?? 0) already missing."
                )
            case .reorganize:
                metrics.movedCount = result.movedCount ?? metrics.movedCount
                metrics.skippedCount = result.skippedCount ?? metrics.skippedCount
                metrics.failedCount = result.failedCount ?? metrics.failedCount
                logStore.append(
                    "Reorganize complete: \(result.movedCount ?? 0) moved, "
                    + "\(result.skippedCount ?? 0) skipped, "
                    + "\(result.failedCount ?? 0) failed."
                )
            }

        case let .copyPlanReady(count):
            metrics.plannedCount = count
            logStore.append("Plan ready: \(count) files queued for copy.")

        case let .dateHistogram(buckets):
            metrics.dateHistogram = buckets

        case let .issue(issue):
            if issue.severity == .error {
                metrics.errorCount += 1
            }
            logStore.append(issue: issue)

        case let .prompt(message):
            prompt = RunPrompt(
                kind: .blockingError,
                title: "Organizer Needs Attention",
                message: UserFacingErrorMessage.backendPrompt(message)
            )

        case let .complete(summary):
            status = summary.status
            currentTaskTitle = summary.title
            var finalMetrics = summary.metrics
            if finalMetrics.dateHistogram.isEmpty, !metrics.dateHistogram.isEmpty {
                finalMetrics.dateHistogram = metrics.dateHistogram
            }
            let finalSummary = RunSummary(
                status: summary.status,
                title: summary.title,
                metrics: finalMetrics,
                artifacts: summary.artifacts,
                failureMessage: summary.failureMessage
            )
            metrics = finalMetrics
            artifacts = summary.artifacts
            self.summary = finalSummary
            if finalSummary.status == .failed {
                lastErrorMessage = finalSummary.failureMessage
                    ?? "Chronoframe could not complete this run. Originals were left untouched."
            }
            preparedRun?.lease.release()
            preparedRun = nil
            directOperationLease?.release()
            directOperationLease = nil
            if finalSummary.status == .dryRunFinished {
                latestPreviewReviewPath = finalSummary.artifacts.previewReviewPath
            }
            // Record this source path in the per-destination "completed sources" log
            // before refreshing, so the refresh re-reads the updated file.
            if finalSummary.status == .finished || finalSummary.status == .nothingToCopy {
                let sourcePath = lastPreflight?.resolvedSourcePath
                    ?? lastPreflight?.configuration.sourcePath
                    ?? ""
                // Don't record drag-and-drop staging dirs: their paths are
                // ephemeral (cleared on next launch) so "Use as source
                // again" would be broken and the entry would look like gibberish.
                if !DroppedItemStager.isStagingPath(sourcePath) {
                    historyStore.recordSuccessfulTransfer(
                        sourcePath: sourcePath,
                        destinationRoot: finalSummary.artifacts.destinationRoot,
                        copiedCount: finalSummary.metrics.copiedCount
                    )
                }
            }
            let refreshRoot = finalSummary.artifacts.destinationRoot
            historyStore.setDestinationRoot(refreshRoot)
            let completionEpoch = currentRunEpoch
            Task { @MainActor [weak self] in
                guard let self else { return }
                await self.historyStore.loadEntries()
                guard self.currentRunEpoch == completionEpoch else { return }
                self.closeSecurityScope()
            }
            logStore.append("Finished: \(finalSummary.title)")
            publishRunCompletion(status: finalSummary.status)
            postRunCompletionNotification(summary: finalSummary)
        }
    }

    /// Reading `lastPreflight` here is safe (unlike external consumers
    /// correlating it with `$summary` over time): `consume` and
    /// `handleFailure` are epoch-guarded, so the preflight on hand
    /// belongs to exactly the run that is terminating.
    private func publishRunCompletion(status: RunStatus) {
        let destinationRoot = artifacts.destinationRoot
        lastRunCompletion = RunCompletionRecord(
            runToken: currentRunToken,
            mode: currentMode,
            status: status,
            configuration: lastPreflight?.configuration,
            resolvedSourcePath: lastPreflight?.resolvedSourcePath,
            resolvedDestinationPath: lastPreflight?.resolvedDestinationPath
                ?? (destinationRoot.isEmpty ? nil : destinationRoot),
            finishedAt: Date()
        )
    }

    // MARK: - Run completion notifications

    /// Requests permission to display macOS notifications. Call once during app startup.
    public static func requestNotificationPermission() {
        guard isRunningInAppBundle, !notificationsDisabledForUITest else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// `UNUserNotificationCenter.current()` raises an NSException when the host
    /// process isn't a proper `.app` bundle (xctest runners, CLI tools), so skip
    /// the call in those contexts.
    private static var isRunningInAppBundle: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    private static var notificationsDisabledForUITest: Bool {
        ProcessInfo.processInfo.environment["CHRONOFRAME_UI_TEST_DISABLE_NOTIFICATIONS"] == "1"
    }

    /// What the completion notification says, or nil when a run warrants none.
    ///
    /// Pure and separated from posting so the wording is unit-tested. It has to
    /// be: a notification is often the only part of a finished run anyone
    /// reads, so a sentence that contradicts the in-app result is worse than no
    /// notification at all.
    static func completionNotificationText(
        summary: RunSummary,
        usedFreeTestBatch: Bool
    ) -> (title: String, body: String)? {
        switch summary.status {
        case .finished:
            return (
                "Transfer complete",
                "\(summary.metrics.copiedCount) file\(summary.metrics.copiedCount == 1 ? "" : "s") copied"
            )
        case .dryRunFinished:
            return (
                "Preview complete",
                "\(summary.metrics.plannedCount) file\(summary.metrics.plannedCount == 1 ? "" : "s") planned"
            )
        case .nothingToCopy:
            // Not "already up to date" when a batch matched nothing: every file
            // the customer confirmed has since moved or changed, and telling
            // them their photos are safely in the destination would be a false
            // assurance — the same one the in-app branch exists to avoid.
            guard !usedFreeTestBatch else {
                return (
                    "Nothing left to copy",
                    "The files in that batch have moved or changed, so nothing was copied."
                )
            }
            return ("Already up to date", "All source files are already in the destination.")
        case .failed:
            return ("Transfer failed", summary.failureMessage ?? summary.title)
        case .cancelled:
            return nil  // user-initiated, no notification needed
        default:
            return nil
        }
    }

    private func postRunCompletionNotification(summary: RunSummary) {
        guard Self.isRunningInAppBundle, !Self.notificationsDisabledForUITest else { return }
        guard let text = Self.completionNotificationText(
            summary: summary,
            usedFreeTestBatch: currentRunUsedFreeTestBatch
        ) else { return }
        let content = UNMutableNotificationContent()
        content.title = text.title
        content.body = text.body

        // Attach the app icon as the notification's hero image so it visibly
        // matches what the user sees in the Dock and the in-app brand mark.
        // macOS also uses this to pick the small badge icon in Notification
        // Center when the cached Launch Services icon is stale.
        if let iconURL = Self.notificationAppIconURL(),
           let attachment = try? UNNotificationAttachment(
                identifier: "chronoframe.app-icon",
                url: iconURL,
                options: [UNNotificationAttachmentOptionsThumbnailHiddenKey: false]
           ) {
            content.attachments = [attachment]
        }

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil  // deliver immediately
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }

    /// Returns a stable file URL pointing at a PNG of the app icon, suitable
    /// for `UNNotificationAttachment`. Written once per launch to the caches
    /// directory; cached in memory afterward.
    private static var cachedNotificationIconURL: URL?
    private static func notificationAppIconURL() -> URL? {
        #if canImport(AppKit)
        if let cached = cachedNotificationIconURL,
           FileManager.default.fileExists(atPath: cached.path) {
            return cached
        }
        guard let caches = try? FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let url = caches.appendingPathComponent("Chronoframe-NotificationIcon.png")

        guard let icon = NSImage(named: NSImage.applicationIconName) else { return nil }
        // Render at a fixed point size so the attachment always looks crisp;
        // the bundle icon itself is multi-resolution and `tiffRepresentation`
        // picks a representation based on current size.
        icon.size = NSSize(width: 512, height: 512)
        guard let tiff = icon.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:]) else {
            return nil
        }
        do {
            try png.write(to: url, options: .atomic)
            cachedNotificationIconURL = url
            return url
        } catch {
            return nil
        }
        #else
        return nil
        #endif
    }

    private func handleFailure(error: Error) {
        let message = UserFacingErrorMessage.message(for: error, context: .run)
        if let trialError = error as? TrialAuthorizationError {
            handleRefusal(
                trialError.refusal,
                offeredBatch: trialError.offeredBatch,
                message: message
            )
            return
        }
        handleFailure(message: message)
    }

    /// A refused run did not run, and must not be recorded as one that failed.
    ///
    /// Nothing broke and nothing was written: T8–T10 guarantee a refusal
    /// enqueues nothing, writes no receipt, and moves no file. So there is no
    /// Run History entry to make — that list is built from receipts on disk —
    /// and nothing to notify about. Publishing a `.failed` completion would
    /// additionally tell watched-source bookkeeping that a run finished when
    /// none did.
    ///
    /// Status returns to `.idle` rather than gaining a `RunStatus` case.
    /// `RunStatus` is `String, Codable` and is persisted into receipts and
    /// history; a refusal is not a run outcome and must not become one.
    /// `lastRefusal` is what the UI branches on.
    private func handleRefusal(
        _ refusal: TrialAuthorizationRefusal,
        offeredBatch: FreeTestBatch? = nil,
        message: String
    ) {
        status = .idle
        currentTaskTitle = "Idle"
        metrics.speedMBps = 0
        metrics.etaSeconds = nil
        lastRefusal = refusal
        lastOfferedBatch = offeredBatch
        lastErrorMessage = message
        logStore.append(message)
        // Released here, before the unlock sheet is presented. An App Store
        // sheet can sit open indefinitely, and holding the destination lock for
        // that whole time would block every other Chronoframe operation on that
        // folder — including the retry this sheet exists to enable.
        preparedRun?.lease.release()
        preparedRun = nil
        directOperationLease?.release()
        directOperationLease = nil
        closeSecurityScope()
    }

    /// Clear the refusal without starting anything.
    ///
    /// For a customer who closes the unlock sheet. The run stays un-run; there
    /// is nothing to clean up because `handleRefusal` already released
    /// everything it held.
    public func dismissRefusal() {
        lastRefusal = nil
        lastOfferedBatch = nil
    }

    private func handleFailure(message: String) {
        status = .failed
        currentTaskTitle = "Failed"
        metrics.speedMBps = 0
        metrics.etaSeconds = nil
        lastErrorMessage = message
        logStore.append("ERROR: \(message)")
        summary = RunSummary(
            status: .failed,
            title: "Failed",
            metrics: metrics,
            artifacts: artifacts,
            failureMessage: message
        )
        publishRunCompletion(status: .failed)
        preparedRun?.lease.release()
        preparedRun = nil
        directOperationLease?.release()
        directOperationLease = nil
        closeSecurityScope()
    }

    private func closeSecurityScope() {
        securityScope?.close()
        securityScope = nil
    }

    private func estimatedFileETA(completed: Int, total: Int) -> Double? {
        guard completed > 0, total > completed, let currentPhaseStartDate else {
            return nil
        }

        let elapsed = max(Date().timeIntervalSince(currentPhaseStartDate), 0.001)
        let averageSecondsPerFile = elapsed / Double(completed)
        return averageSecondsPerFile * Double(total - completed)
    }

    private static func usesFileCountETA(_ phase: RunPhase) -> Bool {
        phase == .sourceHashing || phase == .destinationIndexing
    }

    private static func formattedFileProgressTitle(
        phase: RunPhase,
        completed: Int,
        total: Int,
        etaSeconds: Double?
    ) -> String {
        let progress = "\(completed.formatted()) of \(total.formatted()) files"
        guard let etaSeconds, etaSeconds > 0 else {
            return "\(phase.runningTitle) \(progress)"
        }
        return "\(phase.runningTitle) \(progress) · \(formattedRemainingTime(etaSeconds))"
    }

    private static func formattedRemainingTime(_ seconds: Double) -> String {
        let totalSeconds = max(1, Int(seconds.rounded()))
        if totalSeconds < 60 {
            return "less than 1m remaining"
        }
        if totalSeconds < 3_600 {
            return "\(totalSeconds / 60)m remaining"
        }
        return "\(totalSeconds / 3_600)h \((totalSeconds % 3_600) / 60)m remaining"
    }
}
