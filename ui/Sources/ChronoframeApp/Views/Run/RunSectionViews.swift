import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

struct RunHeroSection: View {
    let model: RunWorkspaceModel
    @Binding var workspaceTab: RunWorkspaceTab
    let appState: AppState

    var body: some View {
        DetailHeroCard(
            eyebrow: "Run Workspace",
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

                SummaryLine(title: "Mode", value: model.context.currentMode?.title ?? "Idle")
                SummaryLine(title: "Current Focus", value: model.context.currentTaskTitle)
                SummaryLine(title: "Issues", value: model.issueSummaryValue, valueColor: model.issueTone.color)
                SummaryLine(title: "Destination", value: model.destinationSummaryValue)
            }
        } actions: {
            if let action = model.heroState.primaryAction {
                heroPrimaryButton(for: action)
            }
        }
    }

    @ViewBuilder
    private func heroPrimaryButton(for action: RunHeroPrimaryAction) -> some View {
        switch action {
        case .setup:
            Button {
                appState.selection = .setup
            } label: {
                Label("Return to Setup", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .preview:
            Button {
                Task { await appState.startPreview() }
            } label: {
                Label("Preview Plan", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.canStartRun)

        case .transfer:
            Button {
                Task { await appState.startTransfer() }
            } label: {
                Label("Start Transfer", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartTransferFromPreview)

        case .cancel:
            Button(role: .destructive) {
                appState.cancelRun()
            } label: {
                Label("Cancel Run", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

        case .openDestination:
            Button {
                appState.openDestination()
            } label: {
                Label("Open Destination", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.destinationRoot == nil)

        case .showIssues:
            Button {
                workspaceTab = .issues
            } label: {
                Label("Review Issues", systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

struct RunProgressSurface: View {
    let model: RunWorkspaceModel

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: model.heroState.tone.color) {
            VStack(alignment: .leading, spacing: 12) {
                progressView
                    .accessibilityLabel("Run progress")
                    .accessibilityValue(model.progressAccessibilityValue)

                RunPhaseTimeline(model: model)
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
}

struct RunPreviewReviewSection: View {
    let model: RunWorkspaceModel
    let startTransfer: () -> Void

    var body: some View {
        MeridianSurfaceCard(tint: DesignTokens.Color.sky) {
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
                .font(DesignTokens.Typography.cardTitle)
                .foregroundStyle(DesignTokens.Color.inkPrimary)

            Text(model.previewReviewMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var transferButton: some View {
        Button(action: startTransfer) {
            Label("Start Transfer", systemImage: "arrow.right.circle.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(!model.canStartTransferFromPreview)
        .accessibilityLabel("Start transfer now")
        .accessibilityIdentifier("startTransferFromPreviewButton")
    }
}

struct RunMetricsGridSection: View {
    let model: RunWorkspaceModel

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: DesignTokens.Layout.metricMinWidth, maximum: 240), spacing: 12)],
            spacing: 12
        ) {
            ForEach(model.metrics) { metric in
                MetricTile(
                    title: metric.title,
                    value: metric.value,
                    caption: metric.caption,
                    tint: metric.tone.color
                )
            }
        }
    }
}

struct RunWorkspaceShell: View {
    let model: RunWorkspaceModel
    @Binding var workspaceTab: RunWorkspaceTab
    let appState: AppState

    var body: some View {
        MeridianSurfaceCard {
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
                    .frame(maxWidth: 340)
                    .accessibilityIdentifier("runWorkspaceTabs")
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
                    .font(DesignTokens.Typography.cardTitle)

                SummaryLine(title: "Status", value: model.heroState.badgeTitle)
                SummaryLine(title: "Speed", value: model.speedSummaryValue)
                SummaryLine(title: "ETA", value: model.etaSummaryValue)
                SummaryLine(title: "Warnings", value: "\(model.context.warningCount)", valueColor: model.warningTone.color)
                SummaryLine(title: "Errors", value: "\(max(model.context.errorCount, model.context.issueCount))", valueColor: model.errorTone.color)
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
                    .font(DesignTokens.Typography.cardTitle)

                Text(model.destinationSummaryValue)
                    .font(.subheadline.monospaced())
                    .foregroundStyle(model.destinationRoot == nil ? .secondary : DesignTokens.Color.inkPrimary)
                    .lineLimit(3)
                    .truncationMode(.middle)

                Text("Open the destination, dry-run report, or logs to inspect what Chronoframe produced.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

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
        .accessibilityIdentifier("openDestinationButton")

        Button("Open Report") {
            appState.openReport()
        }
        .disabled(model.reportPath == nil)
        .accessibilityLabel("Open dry-run report")
        .accessibilityIdentifier("openReportButton")

        Button("Open Logs") {
            appState.openLogsDirectory()
        }
        .disabled(model.logsDirectoryPath == nil)
        .accessibilityLabel("Open logs directory in Finder")
        .accessibilityIdentifier("openLogsButton")
    }
}

struct RunIssuesPanel: View {
    let model: RunWorkspaceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            MeridianSurfaceCard(style: .inner, tint: model.issueTone.color) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Issue Review")
                        .font(DesignTokens.Typography.cardTitle)

                    Text(model.issueWorkspaceSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    SummaryLine(title: "Warnings", value: "\(model.context.warningCount)", valueColor: model.warningTone.color)
                    SummaryLine(title: "Errors", value: "\(model.context.errorCount)", valueColor: model.errorTone.color)
                    SummaryLine(title: "Engine Issues", value: "\(model.context.issueCount)", valueColor: model.issueTone.color)
                }
            }

            if model.issueEntries.isEmpty {
                EmptyStateView(
                    title: "No Issues Reported",
                    message: "Warnings and errors will be collected here so you can review them without scanning the full console.",
                    systemImage: "checkmark.shield"
                )
            } else {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(model.issueEntries) { entry in
                        MeridianSurfaceCard(style: .inner, tint: entry.tone.color) {
                            Text(entry.text)
                                .font(.system(size: DesignTokens.Layout.consoleFontSize, weight: .regular, design: .monospaced))
                                .foregroundStyle(entry.tone.color)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                        }
                    }
                }
            }
        }
    }
}

struct RunConsolePanel: View {
    let model: RunWorkspaceModel

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: DesignTokens.Color.inkMuted) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Console")
                    .font(DesignTokens.Typography.cardTitle)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        if model.consoleEntries.isEmpty {
                            Text("The full backend console will appear here once the organizer starts emitting activity.")
                                .foregroundStyle(.secondary)
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
                .accessibilityIdentifier("consoleScrollView")
            }
        }
    }
}

struct RunPhaseTimeline: View {
    let model: RunWorkspaceModel

    var body: some View {
        ViewThatFits(in: .horizontal) {
            phaseRow(showLabels: true)
            phaseRow(showLabels: false)
        }
    }

    private func phaseRow(showLabels: Bool) -> some View {
        HStack(spacing: 10) {
            ForEach(model.phaseEntries) { entry in
                VStack(spacing: 8) {
                    Circle()
                        .fill(fill(for: entry.state))
                        .frame(width: DesignTokens.Layout.phaseIndicatorSize, height: DesignTokens.Layout.phaseIndicatorSize)
                        .accessibilityLabel(model.phaseAccessibilityLabel(for: entry.phase))

                    if showLabels {
                        Text(entry.phase.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if entry.phase != RunPhase.allCases.last {
                    Capsule()
                        .fill(connectorFill(after: entry.phase))
                        .frame(height: DesignTokens.Layout.phaseConnectorHeight)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    private func fill(for state: RunPhaseTimelineEntry.State) -> SwiftUI.Color {
        switch state {
        case .complete:
            return DesignTokens.Color.success
        case .current:
            return model.heroState.tone.color
        case .pending:
            return DesignTokens.Color.inkMuted.opacity(0.25)
        }
    }

    private func connectorFill(after phase: RunPhase) -> SwiftUI.Color {
        guard let phaseIndex = RunPhase.allCases.firstIndex(of: phase) else {
            return DesignTokens.Color.inkMuted.opacity(0.15)
        }
        let currentIndex = RunPhase.allCases.firstIndex(of: model.context.currentPhase ?? phase) ?? 0
        return phaseIndex < currentIndex ? DesignTokens.Color.success : DesignTokens.Color.inkMuted.opacity(0.15)
    }
}
