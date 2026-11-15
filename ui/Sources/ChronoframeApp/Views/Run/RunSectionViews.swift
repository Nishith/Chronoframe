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
                    Text("Privacy")
                        .scaledFont(.body)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    Spacer()
                    LocalSafetyIndicator(
                        sourcePath: model.sourceRoot ?? "",
                        destinationPath: model.destinationRoot ?? "",
                        deduplicatePath: appState.deduplicateDestinationPath
                    )
                }

                SummaryLine(title: "Now", value: model.nowSummaryValue)
                SummaryLine(title: "Problems", value: model.issueSummaryValue, valueColor: model.issueTone.color)
                SummaryLine(title: "From", value: model.sourceSummaryValue)
                SummaryLine(title: "To", value: model.destinationSummaryValue)
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
        .onChange(of: model.context.status) { _, newValue in
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
        .onChange(of: announcementSnapshot) { _, newSnapshot in
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
                Label("Choose Folders", systemImage: "slider.horizontal.3")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens Choose Folders")

        case .preview:
            Button {
                Task { await appState.startPreview() }
            } label: {
                Label("Preview Plan", systemImage: "eye")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!appState.canStartRun)
            .accessibilityHint(appState.canStartRun ? "Builds the plan without copying anything" : "Choose your folders first")

        case .transfer:
            Button {
                Task { await appState.startTransfer() }
            } label: {
                Label("Start Copying", systemImage: "arrow.right.circle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartTransferFromPreview)
            .accessibilityLabel("Start copying")
            .accessibilityIdentifier(AccessibilityIdentifiers.startTransferFromPreviewButton)
            .accessibilityHint(model.canStartTransferFromPreview ? "Copies the planned files after you confirm" : "Preview first")

        case .cancel:
            Button(role: .destructive) {
                appState.cancelRun()
            } label: {
                Label(appState.runSessionStore.isCancelling ? "Stopping…" : "Stop", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.runSessionStore.isCancelling)
            .accessibilityHint("Stops now. Files already copied stay in place")

        case .openDestination:
            Button {
                appState.openDestination()
            } label: {
                Label("Show in Finder", systemImage: "folder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(model.destinationRoot == nil)
            .accessibilityHint("Reveals the destination folder in Finder")

        case .showIssues:
            Button {
                workspaceTab = .issues
            } label: {
                Label("See Problems", systemImage: "exclamationmark.triangle.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityHint("Opens the Problems tab below to review warnings and errors")
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
                    .accessibilityLabel("Progress")
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

struct RunPreviewSummarySection: View {
    let model: RunWorkspaceModel
    let openReview: () -> Void

    var body: some View {
        MeridianSurfaceCard(style: .section, tint: DesignTokens.Color.sky) {
            VStack(alignment: .leading, spacing: 10) {
                Text("What will happen")
                    .scaledFont(.cardTitle)
                    .foregroundStyle(DesignTokens.Color.inkPrimary)

                let exceptions = model.previewHeadline.exceptions
                if exceptions.isEmpty {
                    Text("No problems found.")
                        .scaledFont(.body)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                } else {
                    ForEach(exceptions) { exception in
                        exceptionRow(exception)
                    }
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.runPreviewSummary)
    }

    @ViewBuilder
    private func exceptionRow(_ exception: RunPreviewHeadline.Exception) -> some View {
        if exception.opensReview {
            Button(action: openReview) {
                rowLabel(exception)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the review list")
        } else {
            rowLabel(exception)
        }
    }

    private func rowLabel(_ exception: RunPreviewHeadline.Exception) -> some View {
        Label(exception.text, systemImage: exception.systemImage)
            .scaledFont(.body)
            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .contentShape(Rectangle())
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
                label: "found",
                tone: .neutral
            ),
            TickerRow.Entry(
                id: "planned",
                value: metrics.plannedCount.formatted(),
                label: "to copy",
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
                label: "exact copies",
                tone: metrics.duplicateCount > 0 ? .warning : .neutral
            ),
            TickerRow.Entry(
                id: "issues",
                value: "\(model.context.issueCount)",
                label: "problems",
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
                        title: "Details",
                        message: ""
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
                    .accessibilityLabel("Details section")
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
                Text("Status")
                    .scaledFont(.cardTitle)

                SummaryLine(title: "Status", value: model.heroState.badgeTitle)
                SummaryLine(title: "Speed", value: model.speedSummaryValue)
                SummaryLine(title: "ETA", value: model.etaSummaryValue)
                SummaryLine(title: "Warnings", value: "\(model.context.warningCount)", valueColor: model.warningTone.color)
                SummaryLine(title: "Errors", value: "\(model.context.errorCount)", valueColor: model.errorTone.color)
                SummaryLine(title: "Problems", value: "\(model.context.issueCount)", valueColor: model.issueTone.color)
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
                Text("Reports and Logs")
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

        Button("Open Preview Report") {
            appState.openReport()
        }
        .disabled(model.reportPath == nil)
        .accessibilityLabel("Open preview report")
        .accessibilityIdentifier(AccessibilityIdentifiers.openReportButton)

        Button("Open Logs") {
            appState.openLogsDirectory()
        }
        .disabled(model.logsDirectoryPath == nil)
        .accessibilityLabel("Open logs folder in Finder")
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
                    Text("Problems")
                        .scaledFont(.cardTitle)

                    SummaryLine(title: "Warnings", value: "\(model.context.warningCount)", valueColor: model.warningTone.color)
                    SummaryLine(title: "Errors", value: "\(model.context.errorCount)", valueColor: model.errorTone.color)
                    SummaryLine(title: "Problems", value: "\(model.context.issueCount)", valueColor: model.issueTone.color)
                }
            }

            if model.issueEntries.isEmpty {
                EmptyStateView(
                    title: "No Problems",
                    message: "Warnings and errors will be listed here.",
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
                .accessibilityRotor("Problems") {
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
            fixes.append("Choose the folders or the destination again so macOS refreshes access.")
        }
        if text.contains("space") || text.contains("disk") || text.contains("volume") {
            fixes.append("Free space on the destination volume, then rebuild the preview.")
        }
        if text.contains("hash") || text.contains("verify") {
            fixes.append("Keep verification on and try again; Chronoframe removes bad copies when verification fails.")
        }
        if text.contains("date") || text.contains("unknown") {
            fixes.append("Open the Review tab and set unknown or unsure dates before copying.")
        }
        if text.contains("exist") || text.contains("collision") || text.contains("duplicate") {
            fixes.append("Check skipped and exact-copy items in the Review tab before copying.")
        }
        if fixes.isEmpty {
            fixes.append("Open the related file or folder from Reports and Logs, then preview again after fixing the cause.")
        }
        fixes.append("Your originals are not changed while you resolve these problems.")
        return fixes
    }
}

struct RunConsolePanel: View {
    let model: RunWorkspaceModel

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: DesignTokens.Color.inkMuted) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Activity")
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
                .accessibilityLabel("Activity log")
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
                    onboardingStep(number: "1", title: "Choose your folders", message: "Add the folders to organize and pick where the copies go.")
                    onboardingStep(number: "2", title: "Preview the plan", message: "A preview copies nothing. It shows exactly what would happen.")
                    onboardingStep(number: "3", title: "Copy when it looks right", message: "Progress and any problems show here while Chronoframe copies.")
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
