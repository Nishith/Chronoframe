import Foundation
import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

enum RunWorkspaceTab: String, CaseIterable, Identifiable {
    case overview
    case review
    case issues
    case console

    var id: String { rawValue }
}

enum RunWorkspaceTone: String, Equatable {
    case idle
    case ready
    case active
    case success
    case warning
    case danger
    case accent
    case muted

    var color: SwiftUI.Color {
        switch self {
        case .idle:
            return DesignTokens.Status.idle
        case .ready:
            return DesignTokens.Status.ready
        case .active:
            return DesignTokens.Status.active
        case .success:
            return DesignTokens.Status.success
        case .warning:
            return DesignTokens.Color.warning
        case .danger:
            return DesignTokens.Color.danger
        case .accent:
            return DesignTokens.Color.sky
        case .muted:
            return DesignTokens.Color.inkMuted
        }
    }
}

enum RunHeroPrimaryAction: Equatable {
    case setup
    case preview
    case transfer
    case cancel
    case openDestination
    case showIssues
}

struct RunHeroState: Equatable {
    let title: String
    let message: String
    let badgeTitle: String
    let badgeSymbol: String
    let heroSymbol: String
    let tone: RunWorkspaceTone
    let primaryAction: RunHeroPrimaryAction?
}

struct RunMetricTileModel: Identifiable, Equatable {
    let id: String
    let title: String
    let value: String
    let caption: String
    let tone: RunWorkspaceTone
}

struct RunIssueLineModel: Identifiable, Equatable {
    let id: Int
    let text: String
    let tone: RunWorkspaceTone
}

struct RunWorkspaceLogLine: Identifiable, Equatable {
    let id: Int
    let text: String
}

struct RunPhaseTimelineEntry: Identifiable, Equatable {
    enum State: Equatable {
        case pending
        case current
        case complete
    }

    let phase: RunPhase
    let state: State

    var id: RunPhase { phase }
}

struct RunWorkspaceContext {
    var status: RunStatus
    var currentMode: RunMode?
    var currentTaskTitle: String
    var currentPhase: RunPhase?
    var progress: Double
    var metrics: RunMetrics
    var summary: RunSummary?
    var lastErrorMessage: String?
    var warningCount: Int
    var errorCount: Int
    var issueCount: Int
    var logEntries: [RunWorkspaceLogLine]
    var historyDestinationRoot: String
    var currentSourceRoot: String
    var canStartRun: Bool
    var previewReviewIsStale: Bool
    var previewReviewSummary: PreviewReviewSummary
    var previewReviewPath: String?
    /// Active source file URL during the transfer phase. Drives the
    /// NowCopyingCard's live QuickLook thumbnail; `nil` outside copy.
    var currentFileURL: URL?
    /// The user asked to stop and the engine has not finished stopping yet.
    var isCancelling: Bool

    init(
        status: RunStatus,
        currentMode: RunMode?,
        currentTaskTitle: String,
        currentPhase: RunPhase?,
        progress: Double,
        metrics: RunMetrics,
        summary: RunSummary?,
        lastErrorMessage: String?,
        warningCount: Int,
        errorCount: Int,
        issueCount: Int,
        logEntries: [RunWorkspaceLogLine],
        historyDestinationRoot: String,
        currentSourceRoot: String,
        canStartRun: Bool,
        previewReviewIsStale: Bool = false,
        previewReviewSummary: PreviewReviewSummary = PreviewReviewSummary(),
        previewReviewPath: String? = nil,
        currentFileURL: URL? = nil,
        isCancelling: Bool = false
    ) {
        self.status = status
        self.currentMode = currentMode
        self.currentTaskTitle = currentTaskTitle
        self.currentPhase = currentPhase
        self.progress = progress
        self.metrics = metrics
        self.summary = summary
        self.lastErrorMessage = lastErrorMessage
        self.warningCount = warningCount
        self.errorCount = errorCount
        self.issueCount = issueCount
        self.logEntries = logEntries
        self.historyDestinationRoot = historyDestinationRoot
        self.currentSourceRoot = currentSourceRoot
        self.canStartRun = canStartRun
        self.previewReviewIsStale = previewReviewIsStale
        self.previewReviewSummary = previewReviewSummary
        self.previewReviewPath = previewReviewPath
        self.currentFileURL = currentFileURL
        self.isCancelling = isCancelling
    }
}

enum RunNextStep: Equatable {
    case findDuplicates(setAsideCount: Int)
}

struct RunWorkspaceModel {
    let context: RunWorkspaceContext

    @MainActor
    init(
        runSessionStore: RunSessionStore,
        runLogStore: RunLogStore,
        historyStore: HistoryStore,
        canStartRun: Bool,
        previewReviewStore: PreviewReviewStore? = nil
    ) {
        self.init(
            context: RunWorkspaceContext(
                status: runSessionStore.status,
                currentMode: runSessionStore.currentMode,
                currentTaskTitle: runSessionStore.currentTaskTitle,
                currentPhase: runSessionStore.currentPhase,
                progress: runSessionStore.progress,
                metrics: runSessionStore.metrics,
                summary: runSessionStore.summary,
                lastErrorMessage: runSessionStore.lastErrorMessage,
                warningCount: runLogStore.warningCount,
                errorCount: runLogStore.errorCount,
                issueCount: runSessionStore.issueCount,
                logEntries: Array(runLogStore.entries).map { entry in
                    RunWorkspaceLogLine(id: entry.id, text: entry.text)
                },
                historyDestinationRoot: historyStore.destinationRoot,
                currentSourceRoot: runSessionStore.lastPreflight?.resolvedSourcePath
                    ?? runSessionStore.lastPreflight?.configuration.sourcePath
                    ?? "",
                canStartRun: canStartRun,
                previewReviewIsStale: previewReviewStore?.isStale ?? false,
                previewReviewSummary: previewReviewStore?.summary ?? PreviewReviewSummary(),
                previewReviewPath: runSessionStore.summary?.artifacts.previewReviewPath,
                currentFileURL: runSessionStore.currentFileURL,
                isCancelling: runSessionStore.isCancelling
            )
        )
    }

    init(context: RunWorkspaceContext) {
        self.context = context
    }

    var previewHeadline: RunPreviewHeadline {
        RunPreviewHeadline(
            metrics: context.metrics,
            review: context.previewReviewSummary,
            isStale: context.previewReviewIsStale
        )
    }

    /// Final totals outrank the last progress sample: the engine's summary is
    /// what actually happened, including files that failed or were reduced by
    /// revalidation.
    var outcomeMetrics: RunMetrics { context.summary?.metrics ?? context.metrics }

    var hasOutcomeIssues: Bool {
        outcomeMetrics.failedCount > 0 || outcomeMetrics.errorCount > 0
            || outcomeMetrics.hashErrorCount > 0 || context.issueCount > 0
    }

    var heroState: RunHeroState {
        switch context.status {
        case .idle:
            return RunHeroState(
                title: context.canStartRun ? String(localized: "Preview the plan first", bundle: .module) : String(localized: "Choose your folders first", bundle: .module),
                message: context.canStartRun
                    ? String(localized: "A preview copies nothing. It shows where every photo and video would go, so you can check before copying.", bundle: .module)
                    : String(localized: "Add the folders to organize and a destination, then come back here to preview and copy.", bundle: .module),
                badgeTitle: String(localized: "Not started", bundle: .module),
                badgeSymbol: "circle.dashed",
                heroSymbol: "eye",
                tone: context.canStartRun ? .ready : .idle,
                primaryAction: context.canStartRun ? .preview : .setup
            )

        case .preflighting:
            return RunHeroState(
                title: String(localized: "Getting ready", bundle: .module),
                message: String(localized: "Chronoframe is checking your folders before it starts.", bundle: .module),
                badgeTitle: String(localized: "Preparing", bundle: .module),
                badgeSymbol: "clock.arrow.circlepath",
                heroSymbol: "clock.arrow.circlepath",
                tone: .ready,
                primaryAction: nil
            )

        case .running:
            let mode = context.currentMode ?? .transfer
            if context.isCancelling {
                return RunHeroState(
                    title: String(localized: "Stopping…", bundle: .module),
                    message: String(localized: "Waiting for Chronoframe to stop and save its receipt. Your originals are not changed. Files already copied stay in place.", bundle: .module),
                    badgeTitle: String(localized: "Stopping…", bundle: .module),
                    badgeSymbol: "arrow.triangle.2.circlepath",
                    heroSymbol: "bolt.horizontal.circle",
                    tone: .active,
                    primaryAction: .cancel
                )
            }
            return RunHeroState(
                title: mode == .preview ? String(localized: "Building the preview", bundle: .module) : String(localized: "Copying your photos", bundle: .module),
                message: mode == .preview
                    ? String(localized: "You can keep using your Mac. Nothing is being copied.", bundle: .module)
                    : String(localized: "You can keep using your Mac. Originals are only read, never changed.", bundle: .module),
                badgeTitle: mode == .preview ? String(localized: "Previewing", bundle: .module) : String(localized: "Copying", bundle: .module),
                badgeSymbol: "arrow.triangle.2.circlepath",
                heroSymbol: "bolt.horizontal.circle",
                tone: .active,
                primaryAction: .cancel
            )

        case .dryRunFinished:
            return RunHeroState(
                title: String(localized: "Preview ready", bundle: .module),
                message: previewHeadline.sentence,
                badgeTitle: String(localized: "Preview ready", bundle: .module),
                badgeSymbol: "checkmark.circle.fill",
                heroSymbol: "doc.text.magnifyingglass",
                tone: .ready,
                primaryAction: .transfer
            )

        case .finished where hasOutcomeIssues:
            let failed = outcomeMetrics.failedCount
            let copied = outcomeMetrics.copiedCount
            let message = failed > 0
                ? String(localized: "\(String(copied.formatted())) copied, \(String(failed.formatted())) could not be copied. Your originals were not changed. See Problems for details.", bundle: .module)
                : String(localized: "\(String(copied.formatted())) copied, but Chronoframe reported problems. Your originals were not changed. See Problems for details.", bundle: .module)
            return RunHeroState(
                title: String(localized: "Copy finished with problems", bundle: .module),
                message: message,
                badgeTitle: String(localized: "Needs attention", bundle: .module),
                badgeSymbol: "exclamationmark.triangle.fill",
                heroSymbol: "exclamationmark.triangle.fill",
                tone: .warning,
                primaryAction: .showIssues
            )

        case .finished:
            let copied = context.metrics.copiedCount
            let subject = copied == 1 ? String(localized: "1 photo or video is", bundle: .module) : String(localized: "\(String(copied.formatted())) photos and videos are", bundle: .module)
            return RunHeroState(
                title: String(localized: "Copy complete", bundle: .module),
                message: String(localized: "\(String(subject)) in your organized library. Your originals were not changed.", bundle: .module),
                badgeTitle: String(localized: "Done", bundle: .module),
                badgeSymbol: "checkmark.circle.fill",
                heroSymbol: "checkmark.circle.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .nothingToCopy where hasOutcomeIssues || outcomeMetrics.alreadyInDestinationCount == 0:
            // "Already up to date" is only true when files were found in the
            // library and nothing went wrong. A free test batch whose files
            // moved, an empty source, or a run with warnings all end here too.
            return RunHeroState(
                title: String(localized: "Nothing was copied", bundle: .module),
                message: hasOutcomeIssues
                    ? String(localized: "Chronoframe copied nothing this time. Your originals were not changed. See Problems for why.", bundle: .module)
                    : String(localized: "Chronoframe found nothing to copy. Your originals were not changed.", bundle: .module),
                badgeTitle: String(localized: "Nothing copied", bundle: .module),
                badgeSymbol: "info.circle.fill",
                heroSymbol: "info.circle.fill",
                tone: hasOutcomeIssues ? .warning : .ready,
                primaryAction: hasOutcomeIssues ? .showIssues : .openDestination
            )

        case .nothingToCopy:
            return RunHeroState(
                title: String(localized: "Already up to date", bundle: .module),
                message: String(localized: "Everything in these folders is already in your organized library. Nothing was copied.", bundle: .module),
                badgeTitle: String(localized: "Up to date", bundle: .module),
                badgeSymbol: "checkmark.seal.fill",
                heroSymbol: "checkmark.seal.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .cancelled:
            return RunHeroState(
                title: String(localized: "Stopped", bundle: .module),
                message: String(localized: "Chronoframe stopped before finishing. Files already copied stay in place and your originals were not changed. Preview again when you are ready.", bundle: .module),
                badgeTitle: String(localized: "Stopped", bundle: .module),
                badgeSymbol: "pause.circle.fill",
                heroSymbol: "pause.circle.fill",
                tone: .warning,
                primaryAction: context.canStartRun ? .preview : .setup
            )

        case .failed:
            return RunHeroState(
                title: String(localized: "Something needs attention", bundle: .module),
                message: context.lastErrorMessage ?? String(localized: "Chronoframe could not finish. Your originals were not changed. Check that both folders are available, then try again.", bundle: .module),
                badgeTitle: String(localized: "Needs attention", bundle: .module),
                badgeSymbol: "exclamationmark.octagon.fill",
                heroSymbol: "exclamationmark.triangle.fill",
                tone: .danger,
                primaryAction: .showIssues
            )

        case .reverted:
            return RunHeroState(
                title: String(localized: "Undo complete", bundle: .module),
                message: String(localized: "Chronoframe removed the copies listed in that receipt. Copies changed since then were kept.", bundle: .module),
                badgeTitle: String(localized: "Undone", bundle: .module),
                badgeSymbol: "arrow.uturn.backward.circle.fill",
                heroSymbol: "arrow.uturn.backward.circle.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .revertEmpty:
            return RunHeroState(
                title: String(localized: "Nothing to undo", bundle: .module),
                message: String(localized: "That receipt lists no copies.", bundle: .module),
                badgeTitle: String(localized: "Empty", bundle: .module),
                badgeSymbol: "tray",
                heroSymbol: "tray",
                tone: .ready,
                primaryAction: .openDestination
            )

        case .reorganized:
            return RunHeroState(
                title: String(localized: "Layout updated", bundle: .module),
                message: String(localized: "Chronoframe moved the files in your organized library into the new folder layout.", bundle: .module),
                badgeTitle: String(localized: "Updated", bundle: .module),
                badgeSymbol: "rectangle.3.offgrid.fill",
                heroSymbol: "rectangle.3.offgrid.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .nothingToReorganize:
            return RunHeroState(
                title: String(localized: "Layout already matches", bundle: .module),
                message: String(localized: "Every file is already in the chosen layout. Nothing was moved.", bundle: .module),
                badgeTitle: String(localized: "Up to date", bundle: .module),
                badgeSymbol: "checkmark.seal.fill",
                heroSymbol: "checkmark.seal.fill",
                tone: .success,
                primaryAction: .openDestination
            )
        }
    }

    var showsProgressSurface: Bool {
        context.currentPhase != nil || context.status == .running
    }

    /// True when no run has ever completed and the session is idle —
    /// used to replace empty placeholder sections with onboarding copy.
    var isBlankIdle: Bool {
        context.status == .idle && context.metrics.discoveredCount == 0
    }

    var progressAccessibilityValue: String {
        if context.status == .running
            && context.progress == 0
            && context.currentPhase != nil
            && context.currentPhase != .copy {
            return String(localized: "Scanning", bundle: .module)
        }
        return "\(Int(context.progress * 100))%"
    }

    var destinationRoot: String? {
        let destination = context.summary?.artifacts.destinationRoot ?? context.historyDestinationRoot
        return destination.isEmpty ? nil : destination
    }

    var destinationSummaryValue: String {
        destinationRoot ?? String(localized: "Your destination will appear here once you choose one.", bundle: .module)
    }

    var sourceRoot: String? {
        context.currentSourceRoot.isEmpty ? nil : context.currentSourceRoot
    }

    var sourceSummaryValue: String {
        sourceRoot ?? String(localized: "Your folders will appear here once you choose them.", bundle: .module)
    }

    /// The one number "Problems" means everywhere (ticker, tab, tile, summary
    /// lines): every warning, plus the larger of the logged errors and the
    /// file-level issues the engine counted. An error line and the file-level
    /// issue behind it are the same problem, so they are not added together.
    var problemCount: Int {
        context.warningCount + max(context.errorCount, context.issueCount)
    }

    var issueSummaryValue: String {
        let warningCount = context.warningCount
        let errorCount = context.errorCount
        // File-level issues with no matching error line; the rest are already
        // counted as errors.
        let issueCount = max(0, context.issueCount - errorCount)
        if problemCount == 0 {
            return String(localized: "No problems reported", bundle: .module)
        }
        var parts: [String] = []
        if warningCount > 0 {
            parts.append(warningCount == 1
                ? String(localized: "1 warning", bundle: .module)
                : String(localized: "\(String(warningCount)) warnings", bundle: .module))
        }
        if errorCount > 0 {
            parts.append(errorCount == 1
                ? String(localized: "1 error", bundle: .module)
                : String(localized: "\(String(errorCount)) errors", bundle: .module))
        }
        if issueCount > 0 {
            parts.append(issueCount == 1
                ? String(localized: "1 other problem", bundle: .module)
                : String(localized: "\(String(issueCount)) other problems", bundle: .module))
        }
        return parts.joined(separator: ", ")
    }

    /// Value of the hero's "Now" line. An empty or idle task reads as "Not started".
    var nowSummaryValue: String {
        let task = context.currentTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if task.isEmpty || task.caseInsensitiveCompare("Idle") == .orderedSame {
            return String(localized: "Not started", bundle: .module)
        }
        return task
    }

    var issueTone: RunWorkspaceTone {
        if context.errorCount > 0 || context.issueCount > 0 {
            return .danger
        }
        if context.warningCount > 0 {
            return .warning
        }
        return .success
    }

    var warningTone: RunWorkspaceTone {
        context.warningCount > 0 ? .warning : .muted
    }

    var errorTone: RunWorkspaceTone {
        context.errorCount > 0 ? .danger : .muted
    }

    var speedSummaryValue: String {
        context.metrics.speedMBps > 0 ? String(format: "%.1f MB/s", context.metrics.speedMBps) : "—"
    }

    var etaSummaryValue: String {
        formattedETA(context.metrics.etaSeconds)
    }

    var showsCopyProgressDetails: Bool {
        context.currentPhase == .copy || context.metrics.copiedCount > 0
    }

    var fileProgressSummaryValue: String {
        let total = max(context.metrics.plannedCount, 0)
        let copied = max(context.metrics.copiedCount, 0)
        guard total > 0 else {
            return copied > 0 ? String(localized: "\(String(copied.formatted())) files copied", bundle: .module) : String(localized: "Getting ready to copy", bundle: .module)
        }

        let percent = min(100, max(0, Int((Double(copied) / Double(total) * 100).rounded())))
        return String(localized: "\(String(copied.formatted())) of \(String(total.formatted())) files · \(String(percent))%", bundle: .module)
    }

    var byteProgressSummaryValue: String {
        guard context.metrics.bytesTotal > 0 else {
            return String(localized: "Measuring", bundle: .module)
        }

        return String(localized: "\(String(formattedBytes(context.metrics.bytesCopied))) of \(String(formattedBytes(context.metrics.bytesTotal)))", bundle: .module)
    }

    var throughputSummaryValue: String {
        let speed = speedSummaryValue
        let eta = etaSummaryValue
        if speed == "—", eta == "—" {
            switch context.status {
            case .finished, .nothingToCopy, .reverted, .reorganized:
                return String(localized: "Done", bundle: .module)
            default:
                return String(localized: "Starting…", bundle: .module)
            }
        }
        if eta == "—" {
            return speed
        }
        return "\(speed) · \(eta)"
    }

    var phaseEntries: [RunPhaseTimelineEntry] {
        RunPhase.allCases.map { phase in
            let state: RunPhaseTimelineEntry.State
            guard let currentPhase = context.currentPhase else {
                state = .pending
                return RunPhaseTimelineEntry(phase: phase, state: state)
            }

            let currentIndex = RunPhase.allCases.firstIndex(of: currentPhase) ?? 0
            let phaseIndex = RunPhase.allCases.firstIndex(of: phase) ?? 0
            if phaseIndex < currentIndex {
                state = .complete
            } else if phase == currentPhase {
                state = .current
            } else {
                state = .pending
            }
            return RunPhaseTimelineEntry(phase: phase, state: state)
        }
    }

    var phaseStripTooltip: String {
        let entries = phaseEntries
        let complete = entries.filter { $0.state == .complete }.map { $0.phase.displayTitle }
        let current = entries.filter { $0.state == .current }.map { $0.phase.displayTitle }
        let pending = entries.filter { $0.state == .pending }.map { $0.phase.displayTitle }

        func line(color: String, label: String, names: [String]) -> String {
            let joined = names.isEmpty ? String(localized: "none", bundle: .module) : names.joined(separator: ", ")
            return "\(color) · \(label) (\(names.count)): \(joined)"
        }

        return [
            String(localized: "Phase progress", bundle: .module),
            line(color: String(localized: "Green", bundle: .module), label: String(localized: "Complete", bundle: .module), names: complete),
            line(color: String(localized: "Yellow", bundle: .module), label: String(localized: "Current", bundle: .module), names: current),
            line(color: String(localized: "Gray", bundle: .module), label: String(localized: "Pending", bundle: .module), names: pending),
        ].joined(separator: "\n")
    }

    var showsPreviewReview: Bool {
        context.status == .dryRunFinished
    }

    var showsOutcomeSummary: Bool {
        switch context.status {
        case .finished, .nothingToCopy, .reverted, .reorganized, .nothingToReorganize:
            return true
        default:
            return false
        }
    }

    var nextStep: RunNextStep? {
        context.status == .finished && context.metrics.copiedCount > 0
            ? .findDuplicates(setAsideCount: context.metrics.duplicateCount)
            : nil
    }

    var nextStepBody: String {
        let setAside = context.metrics.duplicateCount
        let closing = String(localized: "Nothing is removed until you approve it.", bundle: .module)
        if setAside > 1 {
            return String(localized: "\(String(setAside.formatted())) exact copies were set aside in the Duplicate folder during this copy. Deduplicate checks the whole organized library, including look-alikes. \(String(closing))", bundle: .module)
        }
        if setAside == 1 {
            return String(localized: "1 exact copy was set aside in the Duplicate folder during this copy. Deduplicate checks the whole organized library, including look-alikes. \(String(closing))", bundle: .module)
        }
        return String(localized: "Deduplicate checks your organized library for exact copies and look-alikes. \(String(closing))", bundle: .module)
    }

    var outcomeSummaryMessage: String {
        switch context.status {
        case .finished:
            return String(localized: "Your originals were not changed. The report and the receipt for undoing this copy are in History.", bundle: .module)
        case .nothingToCopy:
            return String(localized: "Nothing needed copying.", bundle: .module)
        case .reverted:
            return String(localized: "Copies changed since the original copy were kept.", bundle: .module)
        case .reorganized:
            return String(localized: "Files were moved into the chosen layout and a receipt was saved.", bundle: .module)
        case .nothingToReorganize:
            return String(localized: "The library already matches the chosen layout.", bundle: .module)
        default:
            return ""
        }
    }

    var canStartTransferFromPreview: Bool {
        context.metrics.plannedCount > 0 && context.canStartRun && !context.previewReviewIsStale
    }

    var previewReviewPath: String? {
        context.previewReviewPath
    }

    var previewReviewSummaryTiles: [RunMetricTileModel] {
        let summary = context.previewReviewSummary
        return [
            RunMetricTileModel(
                id: "ready-review",
                title: String(localized: "Ready", bundle: .module),
                value: abbreviated(summary.readyCount),
                caption: String(localized: "Ready to copy.", bundle: .module),
                tone: .ready
            ),
            RunMetricTileModel(
                id: "attention-review",
                title: String(localized: "Needs Attention", bundle: .module),
                value: abbreviated(summary.needsAttentionCount),
                caption: String(localized: "No date, an unsure date, or unreadable.", bundle: .module),
                tone: summary.needsAttentionCount > 0 ? .warning : .success
            ),
            RunMetricTileModel(
                id: "unknown-review",
                title: String(localized: "No Date", bundle: .module),
                value: abbreviated(summary.unknownDateCount),
                caption: String(localized: "Go to the Unknown_Date folder unless you set a date.", bundle: .module),
                tone: summary.unknownDateCount > 0 ? .warning : .success
            ),
            RunMetricTileModel(
                id: "dupe-review",
                title: String(localized: "Exact Copies", bundle: .module),
                value: abbreviated(summary.duplicateCount),
                caption: String(localized: "Exact copies, set aside in the Duplicate folder.", bundle: .module),
                tone: summary.duplicateCount > 0 ? .warning : .muted
            ),
        ]
    }

    var metrics: [RunMetricTileModel] {
        [
            RunMetricTileModel(
                id: "discovered",
                title: String(localized: "Found", bundle: .module),
                value: abbreviated(context.metrics.discoveredCount),
                caption: String(localized: "Photos and videos in your folders.", bundle: .module),
                tone: .accent
            ),
            RunMetricTileModel(
                id: "planned",
                title: String(localized: "To Copy", bundle: .module),
                value: abbreviated(context.metrics.plannedCount),
                caption: String(localized: "New files in the plan.", bundle: .module),
                tone: .ready
            ),
            RunMetricTileModel(
                id: "already",
                title: String(localized: "Already There", bundle: .module),
                value: abbreviated(context.metrics.alreadyInDestinationCount),
                caption: String(localized: "Skipped because the same file is already in the library.", bundle: .module),
                tone: .success
            ),
            RunMetricTileModel(
                id: "duplicates",
                title: String(localized: "Exact Copies", bundle: .module),
                value: abbreviated(context.metrics.duplicateCount),
                caption: String(localized: "Set aside in the Duplicate folder.", bundle: .module),
                tone: .warning
            ),
            RunMetricTileModel(
                id: "issues",
                title: String(localized: "Problems", bundle: .module),
                value: abbreviated(problemCount),
                caption: String(localized: "Warnings and files that could not be copied or checked.", bundle: .module),
                tone: issueTone
            ),
            RunMetricTileModel(
                id: "copied",
                title: String(localized: "Copied", bundle: .module),
                value: abbreviated(context.metrics.copiedCount),
                caption: String(localized: "Files copied so far.", bundle: .module),
                tone: .success
            ),
        ]
    }

    var issueEntries: [RunIssueLineModel] {
        context.logEntries
            .filter { isIssueLine($0.text) }
            .map { entry in
                RunIssueLineModel(id: entry.id, text: entry.text, tone: tone(for: entry.text))
            }
    }

    var issueWorkspaceSummary: String {
        issueEntries.isEmpty
            ? String(localized: "No warnings or errors have been reported yet. If something changes, this view will pull the important problems out of the full activity log.", bundle: .module)
            : String(localized: "Warnings and errors are separated here so you can review the most important problems without scanning the entire activity log.", bundle: .module)
    }

    var reportPath: String? {
        context.summary?.artifacts.reportPath
    }

    var logsDirectoryPath: String? {
        context.summary?.artifacts.logsDirectoryPath
    }

    var consoleEntries: [RunWorkspaceLogLine] {
        context.logEntries
    }

    func tabTitle(_ tab: RunWorkspaceTab) -> String {
        switch tab {
        case .overview:
            return String(localized: "Overview", bundle: .module)
        case .review:
            let count = context.previewReviewSummary.needsAttentionCount
            return count > 0 ? String(localized: "Review (\(String(count)))", bundle: .module) : String(localized: "Review", bundle: .module)
        case .issues:
            let count = problemCount
            return count > 0 ? String(localized: "Problems (\(String(count)))", bundle: .module) : String(localized: "Problems", bundle: .module)
        case .console:
            return String(localized: "Activity", bundle: .module)
        }
    }

    func lineTone(for line: String) -> RunWorkspaceTone {
        tone(for: line)
    }

    func phaseAccessibilityLabel(for phase: RunPhase) -> String {
        guard let currentPhase = context.currentPhase else {
            return String(localized: "Phase \(String(phase.displayTitle)): not started", bundle: .module)
        }
        let currentIndex = RunPhase.allCases.firstIndex(of: currentPhase) ?? 0
        let phaseIndex = RunPhase.allCases.firstIndex(of: phase) ?? 0
        if phaseIndex < currentIndex {
            return String(localized: "Phase \(String(phase.displayTitle)): complete", bundle: .module)
        } else if phase == currentPhase {
            return String(localized: "Phase \(String(phase.displayTitle)): in progress", bundle: .module)
        } else {
            return String(localized: "Phase \(String(phase.displayTitle)): pending", bundle: .module)
        }
    }

    private func isIssueLine(_ line: String) -> Bool {
        line.hasPrefix("ERROR:") || line.hasPrefix("WARNING:") || line.hasPrefix("⚠")
    }

    private func tone(for line: String) -> RunWorkspaceTone {
        if line.hasPrefix("ERROR:") {
            return .danger
        }
        if isIssueLine(line) {
            return .warning
        }
        return .muted
    }

    private func abbreviated(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }

    private func formattedETA(_ eta: Double?) -> String {
        guard let eta, eta > 0 else { return "—" }
        let totalSeconds = Int(eta.rounded())
        if totalSeconds < 60 {
            return String(localized: "\(String(totalSeconds))s", bundle: .module)
        }
        if totalSeconds < 3_600 {
            return String(localized: "\(String(totalSeconds / 60))m \(String(totalSeconds % 60))s", bundle: .module)
        }
        return String(localized: "\(String(totalSeconds / 3_600))h \(String((totalSeconds % 3_600) / 60))m", bundle: .module)
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
