import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

#if canImport(AppKit)
private extension RunAnnouncementPlanner.Priority {
    /// Maps the planner's pure, AppKit-free priority to the platform
    /// announcement priority. Only `.high` interrupts the user; progress is
    /// `.low` so VoiceOver drops it when busy rather than talking over a read.
    var nsPriorityLevel: NSAccessibilityPriorityLevel {
        switch self {
        case .high: return .high
        case .medium: return .medium
        case .low: return .low
        }
    }
}
#endif

struct RunHeroSection: View {
    let model: RunWorkspaceModel
    @Binding var workspaceTab: RunWorkspaceTab
    let appState: AppState

    @State private var washOpacity: Double = 0
    @State private var lastAnnouncementSnapshot: RunAnnouncementPlanner.Snapshot?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var announcementSnapshot: RunAnnouncementPlanner.Snapshot {
        RunAnnouncementPlanner.Snapshot(
            status: model.context.status,
            phase: model.context.currentPhase,
            progress: model.context.progress
        )
    }

    /// Posts a VoiceOver announcement for meaningful run-state transitions
    /// (phase changes, coarse progress, completion) without mutating any store.
    /// The planner assigns each a priority so routine progress doesn't interrupt
    /// a user reading the UI — only terminal outcomes are posted at high.
    private func announceRunStateChange(to newSnapshot: RunAnnouncementPlanner.Snapshot) {
        let previous = lastAnnouncementSnapshot ?? newSnapshot
        lastAnnouncementSnapshot = newSnapshot
        guard let announcement = RunAnnouncementPlanner.detailedAnnouncement(from: previous, to: newSnapshot) else { return }
        #if canImport(AppKit)
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: announcement.message,
                .priority: announcement.priority.nsPriorityLevel.rawValue,
            ]
        )
        #endif
    }

    var body: some View {
        DetailHeroCard(
            title: model.heroState.title,
            message: model.heroState.message,
            badgeTitle: model.heroState.badgeTitle,
            badgeSystemImage: model.heroState.badgeSymbol,
            tint: model.heroState.tone.color,
            systemImage: model.heroState.heroSymbol
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if model.showsProgressSurface {
                    RunProgressSurface(model: model)
                }

                HStack {
                    Text("Security")
                        .scaledFont(.body)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    Spacer()
                    LocalSafetyIndicator(
                        sourcePath: model.sourceRoot ?? "",
                        destinationPath: model.destinationRoot ?? "",
                        deduplicatePath: appState.deduplicateDestinationPath
                    )
                }

                SummaryLine(title: "Mode", value: model.context.currentMode?.title ?? "Idle")
                SummaryLine(title: "Current Focus", value: model.context.currentTaskTitle)
                SummaryLine(title: "Issues", value: model.issueSummaryValue, valueColor: model.issueTone.color)
                SummaryLine(title: "Source", value: model.sourceSummaryValue)
                SummaryLine(title: "Destination", value: model.destinationSummaryValue)
            }
        } actions: {
            if let action = model.heroState.primaryAction {
                heroPrimaryButton(for: action)
            }
        }
        .overlay {
            RoundedRectangle(cornerRadius: DesignTokens.Corner.hero, style: .continuous)
                .fill(DesignTokens.ColorSystem.statusSuccess.opacity(washOpacity))
                .allowsHitTesting(false)
                .blendMode(.plusLighter)
        }
        .onChange(of: model.context.status) { newValue in
            guard newValue == .finished, !reduceMotion else { return }
            Motion.withMotion(Motion.wash, reduceMotion: reduceMotion) {
                washOpacity = 0.18
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + Motion.Duration.wash * 0.55) {
                Motion.withMotion(Motion.wash, reduceMotion: reduceMotion) {
                    washOpacity = 0
                }
            }
        }
        .onChange(of: announcementSnapshot) { newSnapshot in
            announceRunStateChange(to: newSnapshot)
        }
    }

    @ViewBuilder
    private func heroPrimaryButton(for action: RunHeroPrimaryAction) -> some View {
        switch action {
        case .setup:
            Button {
                appState.navigate(to: .organize(.setup))
            } label: {
                Label("Return to Setup", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens the Setup workspace to adjust source, destination, or profile")

        case .preview:
            Button {
                Task { await appState.startPreview() }
            } label: {
                Label("Preview Plan", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.canStartRun)
            .accessibilityHint(appState.canStartRun ? "Generates a copy plan without moving any files" : "Choose both folders or a saved profile in Setup first")

        case .transfer:
            Button {
                Task { await appState.startTransfer() }
            } label: {
                Label("Start Transfer", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartTransferFromPreview)
            .accessibilityHint(model.canStartTransferFromPreview ? "Copies files from the source to the destination" : "Run a preview first")

        case .cancel:
            Button(role: .destructive) {
                appState.cancelRun()
            } label: {
                Label("Cancel Run", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Stops the current run. Already-copied files remain in place")

        case .openDestination:
            Button {
                appState.openDestination()
            } label: {
                Label("Open Destination", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.destinationRoot == nil)
            .accessibilityHint("Reveals the destination folder in Finder")

        case .showIssues:
            Button {
                workspaceTab = .issues
            } label: {
                Label("Review Issues", systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens the issues tab below to review warnings and errors")
        }
    }
}

struct RunProgressSurface: View {
    let model: RunWorkspaceModel

    private var isCopying: Bool {
        model.context.status == .running && model.context.currentPhase == .copy
    }

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: model.heroState.tone.color) {
            VStack(alignment: .leading, spacing: 12) {
                if isCopying {
                    HStack(alignment: .lastTextBaseline, spacing: 8) {
                        Text(model.context.metrics.copiedCount.formatted())
                            .scaledFont(.display)
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                            .contentTransition(.numericText())
                            .monospacedDigit()
                        Text("copied")
                            .scaledFont(.subtitle)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    }
                    .motion(Motion.mechanical, value: model.context.metrics.copiedCount)
                }

                progressView
                    .accessibilityLabel("Run progress")
                    .accessibilityValue(model.progressAccessibilityValue)

                if model.showsCopyProgressDetails {
                    copyProgressDetails

                    if isCopying {
                        WaypointRunway(currentFileURL: model.context.currentFileURL)
                            .transition(.opacity)
                    }
                }

                RunPhaseStrip(model: model)
            }
        }
    }

    @ViewBuilder
    private var progressView: some View {
        if model.context.status == .running
            && model.context.progress == 0
            && model.context.currentPhase != nil
            && model.context.currentPhase != .copy {
            ProgressView()
                .progressViewStyle(.linear)
                .tint(model.heroState.tone.color)
        } else {
            ProgressView(value: model.context.progress)
                .progressViewStyle(.linear)
                .tint(model.heroState.tone.color)
        }
    }

    private var copyProgressDetails: some View {
        VStack(alignment: .leading, spacing: 6) {
            SummaryLine(title: "Files", value: model.fileProgressSummaryValue)
            SummaryLine(title: "Data", value: model.byteProgressSummaryValue)
            SummaryLine(title: "Rate", value: model.throughputSummaryValue)
        }
    }
}

struct RunPreviewReviewSection: View {
    let model: RunWorkspaceModel
    let startTransfer: () -> Void

    var body: some View {
        MeridianSurfaceCard(style: .section, tint: DesignTokens.Color.sky) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 16) {
                    reviewSummary
                    Spacer(minLength: 12)
                    transferButton
                }

                VStack(alignment: .leading, spacing: 12) {
                    reviewSummary
                    transferButton
                }
            }
        }
    }

    private var reviewSummary: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Preview Review")
                .scaledFont(.cardTitle)
                .foregroundStyle(DesignTokens.Color.inkPrimary)

            Text(model.previewReviewMessage)
                .font(.body.weight(.medium))
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if model.previewReviewPath != nil {
                HStack(spacing: 8) {
                    ForEach(model.previewReviewSummaryTiles) { tile in
                        Label(tile.value, systemImage: tile.tone == .warning ? "exclamationmark.triangle" : "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                            .help(tile.title)
                    }
                }
            }
        }
    }

    /// `.bordered`, not `.borderedProminent`: whenever this section is visible
    /// the hero directly above already carries the prominent Start Transfer
    /// (`heroState.primaryAction == .transfer` for `.dryRunFinished`), and two
    /// prominent buttons for the same action in one viewport blur which one is
    /// "the" safe path. This button stays as the convenience affordance next to
    /// the review evidence.
    private var transferButton: some View {
        Button(action: startTransfer) {
            Label("Start Transfer", systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .disabled(!model.canStartTransferFromPreview)
        .accessibilityLabel("Start transfer now")
        .accessibilityIdentifier(AccessibilityIdentifiers.startTransferFromPreviewButton)
    }
}


struct RunTickerSection: View {
    let model: RunWorkspaceModel

    var body: some View {
        TickerRow(entries: entries, style: .tiles)
    }

    private var entries: [TickerRow.Entry] {
        let metrics = model.context.metrics
        return [
            TickerRow.Entry(
                id: "discovered",
                value: metrics.discoveredCount.formatted(),
                label: "discovered",
                tone: .neutral
            ),
            TickerRow.Entry(
                id: "planned",
                value: metrics.plannedCount.formatted(),
                label: "planned",
                tone: .neutral
            ),
            TickerRow.Entry(
                id: "copied",
                value: metrics.copiedCount.formatted(),
                label: "copied",
                tone: .success
            ),
            TickerRow.Entry(
                id: "already",
                value: metrics.alreadyInDestinationCount.formatted(),
                label: "already there",
                tone: .neutral
            ),
            TickerRow.Entry(
                id: "duplicates",
                value: metrics.duplicateCount.formatted(),
                label: "duplicates",
                tone: metrics.duplicateCount > 0 ? .warning : .neutral
            ),
            TickerRow.Entry(
                id: "issues",
                value: "\(model.context.issueCount)",
                label: "issues",
                tone: model.context.issueCount > 0 ? .danger : .neutral
            ),
        ]
    }
}

struct RunWorkspaceShell: View {
    let model: RunWorkspaceModel
    @Binding var workspaceTab: RunWorkspaceTab
    let appState: AppState
    @ObservedObject var previewReviewStore: PreviewReviewStore

    var body: some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(
                        eyebrow: "Inspect",
                        title: "Progress, Issues, and Artifacts",
                        message: "Use the workspace to understand what happened, where the run stands now, and what to inspect next."
                    )

                    Spacer(minLength: 12)

                    Picker("Workspace", selection: $workspaceTab) {
                        ForEach(RunWorkspaceTab.allCases) { tab in
                            Text(model.tabTitle(tab)).tag(tab)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(maxWidth: 340)
                    .accessibilityLabel("Run workspace section")
                    .accessibilityIdentifier(AccessibilityIdentifiers.runWorkspaceTabs)
                }

                workspaceContent
            }
        }
    }

    @ViewBuilder
    private var workspaceContent: some View {
        switch workspaceTab {
        case .overview:
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 16) {
                        RunSnapshotPanel(model: model)
                        RunArtifactsPanel(model: model, appState: appState)
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        RunSnapshotPanel(model: model)
                        RunArtifactsPanel(model: model, appState: appState)
                    }
                }
            }
        case .review:
            PreviewReviewPanel(
                model: model,
                store: previewReviewStore,
                appState: appState
            )
        case .issues:
            RunIssuesPanel(model: model)
        case .console:
            RunConsolePanel(model: model)
        }
    }
}

struct RunSnapshotPanel: View {
    let model: RunWorkspaceModel

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: model.heroState.tone.color) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Run Snapshot")
                    .scaledFont(.cardTitle)

                SummaryLine(title: "Status", value: model.heroState.badgeTitle)
                SummaryLine(title: "Speed", value: model.speedSummaryValue)
                SummaryLine(title: "ETA", value: model.etaSummaryValue)
                SummaryLine(title: "Warnings", value: "\(model.context.warningCount)", valueColor: model.warningTone.color)
                SummaryLine(title: "Errors", value: "\(model.context.errorCount)", valueColor: model.errorTone.color)
                SummaryLine(title: "Issues", value: "\(model.context.issueCount)", valueColor: model.issueTone.color)
            }
        }
    }
}

struct RunArtifactsPanel: View {
    let model: RunWorkspaceModel
    let appState: AppState

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: DesignTokens.Color.amber) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Artifacts")
                    .scaledFont(.cardTitle)

                Text(model.destinationSummaryValue)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(model.destinationRoot == nil ? DesignTokens.ColorSystem.captionText : DesignTokens.Color.inkPrimary)
                    .lineLimit(3)
                    .truncationMode(.middle)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        artifactButtons
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        artifactButtons
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var artifactButtons: some View {
        Button("Open Destination") {
            appState.openDestination()
        }
        .disabled(model.destinationRoot == nil)
        .accessibilityLabel("Open destination folder in Finder")
        .accessibilityIdentifier(AccessibilityIdentifiers.openDestinationButton)

        Button("Open Report") {
            appState.openReport()
        }
        .disabled(model.reportPath == nil)
        .accessibilityLabel("Open dry-run report")
        .accessibilityIdentifier(AccessibilityIdentifiers.openReportButton)

        Button("Open Logs") {
            appState.openLogsDirectory()
        }
        .disabled(model.logsDirectoryPath == nil)
        .accessibilityLabel("Open logs directory in Finder")
        .accessibilityIdentifier(AccessibilityIdentifiers.openLogsButton)
    }
}

private func accessibilityPrefix(for tone: RunWorkspaceTone) -> String {
    switch tone {
    case .danger:
        return "Error"
    case .warning:
        return "Warning"
    default:
        return "Notice"
    }
}

struct RunIssuesPanel: View {
    let model: RunWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeridianSurfaceCard(style: .inner, tint: model.issueTone.color) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Issues")
                        .scaledFont(.cardTitle)

                    SummaryLine(title: "Warnings", value: "\(model.context.warningCount)", valueColor: model.warningTone.color)
                    SummaryLine(title: "Errors", value: "\(model.context.errorCount)", valueColor: model.errorTone.color)
                    SummaryLine(title: "Engine Issues", value: "\(model.context.issueCount)", valueColor: model.issueTone.color)
                }
            }

            if model.issueEntries.isEmpty {
                EmptyStateView(
                    title: "No Issues Reported",
                    message: "Warnings and errors will be collected here.",
                    systemImage: "checkmark.shield"
                )
            } else {
                issueActionGuide

                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.issueEntries) { entry in
                        MeridianSurfaceCard(style: .inner, tint: entry.tone.color) {
                            Text(entry.text)
                                .font(.system(size: DesignTokens.Layout.consoleFontSize, weight: .regular, design: .monospaced))
                                .foregroundStyle(entry.tone.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(accessibilityPrefix(for: entry.tone)): \(entry.text)")
                    }
                }
                .accessibilityRotor("Issues") {
                    ForEach(model.issueEntries) { entry in
                        AccessibilityRotorEntry(entry.text, id: entry.id)
                    }
                }
            }
        }
    }

    private var issueActionGuide: some View {
        MeridianSurfaceCard(style: .inner, tint: model.issueTone.color) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Suggested fixes")
                    .font(.subheadline.weight(.semibold))
                ForEach(Self.suggestedFixes(for: model.issueEntries), id: \.self) { fix in
                    Label(fix, systemImage: "wrench.and.screwdriver")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
            }
        }
    }

    static func suggestedFixes(for entries: [RunIssueLineModel]) -> [String] {
        let text = entries.map(\.text).joined(separator: "\n").lowercased()
        var fixes: [String] = []
        if text.contains("permission") || text.contains("access") || text.contains("bookmark") {
            fixes.append("Choose the source or destination folder again so macOS refreshes access.")
        }
        if text.contains("space") || text.contains("disk") || text.contains("volume") {
            fixes.append("Free space on the destination volume, then rebuild the preview.")
        }
        if text.contains("hash") || text.contains("verify") {
            fixes.append("Keep verification on and retry the run; Chronoframe removes bad copies when verification fails.")
        }
        if text.contains("date") || text.contains("unknown") {
            fixes.append("Open the Review tab and correct unknown or low-confidence dates before transfer.")
        }
        if text.contains("exist") || text.contains("collision") || text.contains("duplicate") {
            fixes.append("Inspect skipped and duplicate items in Preview Review before starting transfer.")
        }
        if fixes.isEmpty {
            fixes.append("Open the related file or folder from the artifact panel, then run Preview again after fixing the cause.")
        }
        fixes.append("Original source files are left untouched while you resolve these issues.")
        return fixes
    }
}

struct RunConsolePanel: View {
    let model: RunWorkspaceModel

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: DesignTokens.Color.inkMuted) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Console")
                    .scaledFont(.cardTitle)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if model.consoleEntries.isEmpty {
                            Text("No activity yet.")
                                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        } else {
                            ForEach(model.consoleEntries, id: \.id) { entry in
                                Text(entry.text)
                                    .font(.system(size: DesignTokens.Layout.consoleFontSize, weight: .regular, design: .monospaced))
                                    .foregroundStyle(model.lineTone(for: entry.text).color)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .textSelection(.enabled)
                            }
                        }
                    }
                }
                .frame(minHeight: DesignTokens.Layout.consoleMinHeight, idealHeight: DesignTokens.Layout.consoleIdealHeight)
                .accessibilityLabel("Run log")
                .accessibilityIdentifier(AccessibilityIdentifiers.consoleScrollView)
            }
        }
    }
}

struct RunIdleOnboardingCard: View {
    var body: some View {
        DarkroomPanel(variant: .panel) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.lg) {
                SectionHeading(
                    eyebrow: "How it works",
                    title: "Three steps to an organized library",
                    message: ""
                )
                VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                    onboardingStep(number: "1", title: "Set up source and destination", message: "Go to Setup and choose the folder to organize and where organized copies should go.")
                    onboardingStep(number: "2", title: "Preview to validate the plan", message: "A preview copies nothing — it shows exactly what will happen and flags any issues.")
                    onboardingStep(number: "3", title: "Transfer when you're confident", message: "Start the transfer. This workspace updates live with progress, issues, and artifacts.")
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.runIdleOnboardingCard)
    }

    private func onboardingStep(number: String, title: String, message: String) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
            Text(number)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
                .frame(width: 18, height: 18)
                .background(DesignTokens.ColorSystem.imageStage, in: Circle())
                .overlay(Circle().strokeBorder(DesignTokens.ColorSystem.accentAction, lineWidth: 1))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .scaledFont(.body, weight: .semibold)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                Text(message)
                    .scaledFont(.body)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title). \(message)")
    }
}
