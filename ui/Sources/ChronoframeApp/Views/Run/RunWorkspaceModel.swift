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
        currentFileURL: URL? = nil
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
                currentFileURL: runSessionStore.currentFileURL
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

    var heroState: RunHeroState {
        switch context.status {
        case .idle:
            return RunHeroState(
                title: context.canStartRun ? "Preview the plan first" : "Choose your folders first",
                message: context.canStartRun
                    ? "A preview copies nothing. It shows where every photo and video would go, so you can check before copying."
                    : "Add the folders to organize and a destination, then come back here to preview and copy.",
                badgeTitle: "Not started",
                badgeSymbol: "circle.dashed",
                heroSymbol: "eye",
                tone: context.canStartRun ? .ready : .idle,
                primaryAction: context.canStartRun ? .preview : .setup
            )

        case .preflighting:
            return RunHeroState(
                title: "Getting ready",
                message: "Chronoframe is checking your folders before it starts.",
                badgeTitle: "Preparing",
                badgeSymbol: "clock.arrow.circlepath",
                heroSymbol: "clock.arrow.circlepath",
                tone: .ready,
                primaryAction: nil
            )

        case .running:
            let mode = context.currentMode ?? .transfer
            return RunHeroState(
                title: mode == .preview ? "Building the preview" : "Copying your photos",
                message: mode == .preview
                    ? "You can keep using your Mac. Nothing is being copied."
                    : "You can keep using your Mac. Originals are only read, never changed.",
                badgeTitle: mode == .preview ? "Previewing" : "Copying",
                badgeSymbol: "arrow.triangle.2.circlepath",
                heroSymbol: "bolt.horizontal.circle",
                tone: .active,
                primaryAction: .cancel
            )

        case .dryRunFinished:
            return RunHeroState(
                title: "Preview ready",
                message: previewHeadline.sentence,
                badgeTitle: "Preview ready",
                badgeSymbol: "checkmark.circle.fill",
                heroSymbol: "doc.text.magnifyingglass",
                tone: .ready,
                primaryAction: .transfer
            )

        case .finished:
            let copied = context.metrics.copiedCount
            let subject = copied == 1 ? "1 photo or video is" : "\(copied.formatted()) photos and videos are"
            return RunHeroState(
                title: "Copy complete",
                message: "\(subject) in your organized library. Your originals were not changed.",
                badgeTitle: "Done",
                badgeSymbol: "checkmark.circle.fill",
                heroSymbol: "checkmark.circle.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .nothingToCopy:
            return RunHeroState(
                title: "Already up to date",
                message: "Everything in these folders is already in your organized library. Nothing was copied.",
                badgeTitle: "Up to date",
                badgeSymbol: "checkmark.seal.fill",
                heroSymbol: "checkmark.seal.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .cancelled:
            return RunHeroState(
                title: "Stopped",
                message: "Chronoframe stopped before finishing. Files already copied stay in place and your originals were not changed. Preview again when you are ready.",
                badgeTitle: "Stopped",
                badgeSymbol: "pause.circle.fill",
                heroSymbol: "pause.circle.fill",
                tone: .warning,
                primaryAction: context.canStartRun ? .preview : .setup
            )

        case .failed:
            return RunHeroState(
                title: "Something needs attention",
                message: context.lastErrorMessage ?? "Chronoframe could not finish. Your originals were not changed. Check that both folders are available, then try again.",
                badgeTitle: "Needs attention",
                badgeSymbol: "exclamationmark.octagon.fill",
                heroSymbol: "exclamationmark.triangle.fill",
                tone: .danger,
                primaryAction: .showIssues
            )

        case .reverted:
            return RunHeroState(
                title: "Undo complete",
                message: "Chronoframe removed the copies listed in that receipt. Copies changed since then were kept.",
                badgeTitle: "Undone",
                badgeSymbol: "arrow.uturn.backward.circle.fill",
                heroSymbol: "arrow.uturn.backward.circle.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .revertEmpty:
            return RunHeroState(
                title: "Nothing to undo",
                message: "That receipt lists no copies.",
                badgeTitle: "Empty",
                badgeSymbol: "tray",
                heroSymbol: "tray",
                tone: .ready,
                primaryAction: .openDestination
            )

        case .reorganized:
            return RunHeroState(
                title: "Layout updated",
                message: "Chronoframe moved the files in your organized library into the new folder layout.",
                badgeTitle: "Updated",
                badgeSymbol: "rectangle.3.offgrid.fill",
                heroSymbol: "rectangle.3.offgrid.fill",
                tone: .success,
                primaryAction: .openDestination
            )

        case .nothingToReorganize:
            return RunHeroState(
                title: "Layout already matches",
                message: "Every file is already in the chosen layout. Nothing was moved.",
                badgeTitle: "Up to date",
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
            return "Scanning"
        }
        return "\(Int(context.progress * 100))%"
    }

    var destinationRoot: String? {
        let destination = context.summary?.artifacts.destinationRoot ?? context.historyDestinationRoot
        return destination.isEmpty ? nil : destination
    }

    var destinationSummaryValue: String {
        destinationRoot ?? "Your destination will appear here once you choose one."
    }

    var sourceRoot: String? {
        context.currentSourceRoot.isEmpty ? nil : context.currentSourceRoot
    }

    var sourceSummaryValue: String {
        sourceRoot ?? "Your folders will appear here once you choose them."
    }

    var issueSummaryValue: String {
        let warningCount = context.warningCount
        let errorCount = context.errorCount
        let issueCount = context.issueCount
        if warningCount == 0 && errorCount == 0 && issueCount == 0 {
            return "No problems reported"
        }
        var parts: [String] = []
        if warningCount > 0 {
            parts.append("\(warningCount) warning\(warningCount == 1 ? "" : "s")")
        }
        if errorCount > 0 {
            parts.append("\(errorCount) error\(errorCount == 1 ? "" : "s")")
        }
        if issueCount > 0 {
            parts.append("\(issueCount) other problem\(issueCount == 1 ? "" : "s")")
        }
        return parts.joined(separator: ", ")
    }

    /// Value of the hero's "Now" line. An empty or idle task reads as "Not started".
    var nowSummaryValue: String {
        let task = context.currentTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if task.isEmpty || task.caseInsensitiveCompare("Idle") == .orderedSame {
            return "Not started"
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
            return copied > 0 ? "\(copied.formatted()) files copied" : "Getting ready to copy"
        }

        let percent = min(100, max(0, Int((Double(copied) / Double(total) * 100).rounded())))
        return "\(copied.formatted()) of \(total.formatted()) files · \(percent)%"
    }

    var byteProgressSummaryValue: String {
        guard context.metrics.bytesTotal > 0 else {
            return "Measuring"
        }

        return "\(formattedBytes(context.metrics.bytesCopied)) of \(formattedBytes(context.metrics.bytesTotal))"
    }

    var throughputSummaryValue: String {
        let speed = speedSummaryValue
        let eta = etaSummaryValue
        if speed == "—", eta == "—" {
            switch context.status {
            case .finished, .nothingToCopy, .reverted, .reorganized:
                return "Done"
            default:
                return "Starting…"
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
        let complete = entries.filter { $0.state == .complete }.map { $0.phase.title }
        let current = entries.filter { $0.state == .current }.map { $0.phase.title }
        let pending = entries.filter { $0.state == .pending }.map { $0.phase.title }

        func line(color: String, label: String, names: [String]) -> String {
            let joined = names.isEmpty ? "none" : names.joined(separator: ", ")
            return "\(color) · \(label) (\(names.count)): \(joined)"
        }

        return [
            "Phase progress",
            line(color: "Green", label: "Complete", names: complete),
            line(color: "Yellow", label: "Current", names: current),
            line(color: "Gray", label: "Pending", names: pending),
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
        let closing = "Nothing is removed until you approve it."
        if setAside > 1 {
            return "\(setAside.formatted()) exact copies were set aside in the Duplicate folder during this copy. Deduplicate checks the whole organized library, including look-alikes. \(closing)"
        }
        if setAside == 1 {
            return "1 exact copy was set aside in the Duplicate folder during this copy. Deduplicate checks the whole organized library, including look-alikes. \(closing)"
        }
        return "Deduplicate checks your organized library for exact copies and look-alikes. \(closing)"
    }

    var outcomeSummaryMessage: String {
        switch context.status {
        case .finished:
            return "Your originals were not changed. The report and the receipt for undoing this copy are in History."
        case .nothingToCopy:
            return "Nothing needed copying."
        case .reverted:
            return "Copies changed since the original copy were kept."
        case .reorganized:
            return "Files were moved into the chosen layout and a receipt was saved."
        case .nothingToReorganize:
            return "The library already matches the chosen layout."
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
                title: "Ready",
                value: abbreviated(summary.readyCount),
                caption: "Ready to copy.",
                tone: .ready
            ),
            RunMetricTileModel(
                id: "attention-review",
                title: "Needs Attention",
                value: abbreviated(summary.needsAttentionCount),
                caption: "No date, an unsure date, or unreadable.",
                tone: summary.needsAttentionCount > 0 ? .warning : .success
            ),
            RunMetricTileModel(
                id: "unknown-review",
                title: "No Date",
                value: abbreviated(summary.unknownDateCount),
                caption: "Go to the Unknown_Date folder unless you set a date.",
                tone: summary.unknownDateCount > 0 ? .warning : .success
            ),
            RunMetricTileModel(
                id: "dupe-review",
                title: "Exact Copies",
                value: abbreviated(summary.duplicateCount),
                caption: "Exact copies, set aside in the Duplicate folder.",
                tone: summary.duplicateCount > 0 ? .warning : .muted
            ),
        ]
    }

    var metrics: [RunMetricTileModel] {
        [
            RunMetricTileModel(
                id: "discovered",
                title: "Found",
                value: abbreviated(context.metrics.discoveredCount),
                caption: "Photos and videos in your folders.",
                tone: .accent
            ),
            RunMetricTileModel(
                id: "planned",
                title: "To Copy",
                value: abbreviated(context.metrics.plannedCount),
                caption: "New files in the plan.",
                tone: .ready
            ),
            RunMetricTileModel(
                id: "already",
                title: "Already There",
                value: abbreviated(context.metrics.alreadyInDestinationCount),
                caption: "Skipped because the same file is already in the library.",
                tone: .success
            ),
            RunMetricTileModel(
                id: "duplicates",
                title: "Exact Copies",
                value: abbreviated(context.metrics.duplicateCount),
                caption: "Set aside in the Duplicate folder.",
                tone: .warning
            ),
            RunMetricTileModel(
                id: "issues",
                title: "Problems",
                value: abbreviated(context.issueCount),
                caption: "Warnings and files that could not be copied or checked.",
                tone: issueTone
            ),
            RunMetricTileModel(
                id: "copied",
                title: "Copied",
                value: abbreviated(context.metrics.copiedCount),
                caption: "Files copied so far.",
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
            ? "No warnings or errors have been reported yet. If something changes, this view will pull the important problems out of the full activity log."
            : "Warnings and errors are separated here so you can review the most important problems without scanning the entire activity log."
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
            return "Overview"
        case .review:
            let count = context.previewReviewSummary.needsAttentionCount
            return count > 0 ? "Review (\(count))" : "Review"
        case .issues:
            let count = max(context.warningCount + context.errorCount, context.issueCount)
            return count > 0 ? "Problems (\(count))" : "Problems"
        case .console:
            return "Activity"
        }
    }

    func lineTone(for line: String) -> RunWorkspaceTone {
        tone(for: line)
    }

    func phaseAccessibilityLabel(for phase: RunPhase) -> String {
        guard let currentPhase = context.currentPhase else {
            return "Phase \(phase.title): not started"
        }
        let currentIndex = RunPhase.allCases.firstIndex(of: currentPhase) ?? 0
        let phaseIndex = RunPhase.allCases.firstIndex(of: phase) ?? 0
        if phaseIndex < currentIndex {
            return "Phase \(phase.title): complete"
        } else if phase == currentPhase {
            return "Phase \(phase.title): in progress"
        } else {
            return "Phase \(phase.title): pending"
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
            return "\(totalSeconds)s"
        }
        if totalSeconds < 3_600 {
            return "\(totalSeconds / 60)m \(totalSeconds % 60)s"
        }
        return "\(totalSeconds / 3_600)h \((totalSeconds % 3_600) / 60)m"
    }

    private func formattedBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
