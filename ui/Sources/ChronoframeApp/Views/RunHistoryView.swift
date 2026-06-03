#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Charts
import SwiftUI

private enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case reports
    case receipts
    case logs
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .reports:
            return "Reports"
        case .receipts:
            return "Receipts"
        case .logs:
            return "Logs"
        case .other:
            return "Other"
        }
    }

    func matches(_ entry: RunHistoryEntry) -> Bool {
        switch self {
        case .all:
            return true
        case .reports:
            return entry.kind == .dryRunReport || entry.kind == .csvArtifact
        case .receipts:
            return entry.kind == .auditReceipt
                || entry.kind == .dedupeAuditReceipt
                || entry.kind == .reorganizeAuditReceipt
                || entry.kind == .jsonArtifact
        case .logs:
            return entry.kind == .runLog || entry.kind == .queueDatabase
        case .other:
            return !(matchesCategory(.reports, entry) || matchesCategory(.receipts, entry) || matchesCategory(.logs, entry))
        }
    }

    private func matchesCategory(_ category: HistoryFilter, _ entry: RunHistoryEntry) -> Bool {
        switch category {
        case .all, .other:
            return false
        case .reports:
            return entry.kind == .dryRunReport || entry.kind == .csvArtifact
        case .receipts:
            return entry.kind == .auditReceipt
                || entry.kind == .dedupeAuditReceipt
                || entry.kind == .reorganizeAuditReceipt
                || entry.kind == .jsonArtifact
        case .logs:
            return entry.kind == .runLog || entry.kind == .queueDatabase
        }
    }
}

private struct HistorySection: Identifiable {
    // Identify by `date` rather than a fresh UUID per instance, so that
    // when `groupedEntries` rebuilds (a search-text change, a filter
    // flip, a store refresh) SwiftUI sees the same identity for an
    // unchanged section and preserves animation/scroll/hover state.
    var id: Date { date }
    let date: Date
    let entries: [RunHistoryEntry]
}

struct RunHistoryView: View {
    let appState: AppState
    @ObservedObject private var historyStore: HistoryStore
    @State private var searchText = ""
    @State private var historyFilter: HistoryFilter = .all
    @State private var pendingRevertEntry: RunHistoryEntry?
    @State private var selectedReceiptEntry: RunHistoryEntry?

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    init(appState: AppState) {
        self.appState = appState
        self._historyStore = ObservedObject(wrappedValue: appState.historyStore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionSpacing) {
                headerStrip

                if !heroStripIsEmpty {
                    heroStrip
                }

                if let error = historyStore.lastRefreshError, !error.isEmpty {
                    refreshErrorStrip(error)
                }

                reusableSourcesSection
                recoveryCenterSection
                archiveSection
            }
            .padding(DesignTokens.Layout.contentPadding)
            .frame(maxWidth: DesignTokens.Layout.archiveMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .darkroom()
        .navigationTitle("Run History")
        .searchable(text: $searchText, prompt: "Search artifacts")
        .confirmationDialog(
            Self.confirmationTitle(for: pendingRevertEntry),
            isPresented: Binding(
                get: { pendingRevertEntry != nil },
                set: { if !$0 { pendingRevertEntry = nil } }
            ),
            presenting: pendingRevertEntry
        ) { entry in
            Button(Self.confirmationActionLabel(for: entry), role: Self.confirmationActionRole(for: entry)) {
                appState.revertHistoryEntry(entry)
                pendingRevertEntry = nil
            }
            Button("Cancel", role: .cancel) {
                pendingRevertEntry = nil
            }
        } message: { entry in
            Text(Self.confirmationMessage(for: entry))
        }
        .sheet(item: $selectedReceiptEntry) { entry in
            ReceiptDetailSheet(entry: entry, appState: appState)
        }
    }

    // MARK: - Confirmation copy

    /// Dedupe revert restores files from the Trash; the prior single
    /// hardcoded message used transfer-revert language ("remove the
    /// files this receipt copied, but only if their contents still
    /// match…") which was wrong for dedupe receipts. Branch by
    /// `entry.kind` so the dialog matches the actual operation. The
    /// helpers are static + pure so they can be tested without
    /// rendering SwiftUI.
    static func confirmationTitle(for entry: RunHistoryEntry?) -> String {
        switch entry?.kind {
        case .dedupeAuditReceipt: return "Restore deduplicated files?"
        case .reorganizeAuditReceipt: return "Undo this reorganize?"
        default: return "Revert this transfer?"
        }
    }

    static func confirmationActionLabel(for entry: RunHistoryEntry) -> String {
        switch entry.kind {
        case .dedupeAuditReceipt: return "Restore"
        case .reorganizeAuditReceipt: return "Undo"
        default: return "Revert"
        }
    }

    static func confirmationActionRole(for entry: RunHistoryEntry) -> ButtonRole? {
        switch entry.kind {
        case .dedupeAuditReceipt, .reorganizeAuditReceipt: return nil
        default: return .destructive
        }
    }

    static func confirmationMessage(for entry: RunHistoryEntry) -> String {
        switch entry.kind {
        case .dedupeAuditReceipt:
            return "Chronoframe will move the files this dedupe run sent to the Trash back to their original locations. Files that have since been emptied from the Trash cannot be restored.\n\nReceipt: \(entry.relativePath)"
        case .reorganizeAuditReceipt:
            return "Chronoframe will move the files this reorganize run changed back to their previous locations, but only if their contents still match the receipt.\n\nReceipt: \(entry.relativePath)"
        default:
            return "Chronoframe will remove the files this receipt copied, but only if their contents still match the original transfer. Files modified after the original copy will be preserved.\n\nReceipt: \(entry.relativePath)"
        }
    }

    // MARK: - Header strip

    private var headerStrip: some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Archive")
                    .font(DesignTokens.Typography.title)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                Text(headerMessage)
                    .font(DesignTokens.Typography.subtitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .lineLimit(2)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            Button {
                appState.openDestination()
            } label: {
                Label("Open Destination", systemImage: "folder")
            }
            .buttonStyle(.bordered)
            .disabled(historyStore.destinationRoot.isEmpty)
        }
    }

    private var headerMessage: String {
        if historyStore.entries.isEmpty {
            return historyStore.destinationRoot.isEmpty
                ? "Choose a destination in Setup, then a preview will create the first report here."
                : "Run a preview or transfer to build the first entries in this archive."
        }
        return "\(historyStore.entries.count) artifacts · \(historyStore.transferredSources.count) reusable sources."
    }

    // MARK: - Hero strip (P1.3)

    /// Returns true when there isn't enough archive data to render a meaningful
    /// hero strip — e.g. no completed transfers yet. Keeps the empty
    /// destination state quiet rather than showing "0 frames archived".
    private var heroStripIsEmpty: Bool {
        !Self.shouldShowArchiveOverview(receiptEntries: archiveOverviewReceiptEntries, totalFramesArchived: totalFramesArchived)
    }

    private var heroStrip: some View {
        DarkroomPanel(variant: .panel) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(totalFramesArchived.formatted())
                        .font(DesignTokens.Typography.display)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        .contentTransition(.numericText())

                    Text("frames archived")
                        .font(DesignTokens.Typography.label)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted)

                    Text(sinceLabel)
                        .font(DesignTokens.Typography.body)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
                .frame(maxWidth: 220, alignment: .leading)

                Divider()
                    .frame(height: 84)

                sparkline
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Archive overview: \(totalFramesArchived) frames archived across \(archiveOverviewReceiptEntries.count) runs.")
    }

    /// Cumulative count of completed-run receipts over time. Renders an area
    /// chart on top of a line for visual weight; uses the muted accent action
    /// tone so it doesn't compete with the destination filter pills below.
    private var sparkline: some View {
        let points = sparklinePoints
        return Chart {
            ForEach(points) { point in
                AreaMark(
                    x: .value("Date", point.date),
                    y: .value("Runs", point.cumulative)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [
                            DesignTokens.ColorSystem.accentAction.opacity(0.35),
                            DesignTokens.ColorSystem.accentAction.opacity(0.04)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Runs", point.cumulative)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(DesignTokens.ColorSystem.accentAction)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.padding(.vertical, 4)
        }
        .frame(height: 84)
    }

    private var totalFramesArchived: Int {
        historyStore.transferredSources.reduce(0) { $0 + $1.totalCopiedCount }
    }

    private var sinceLabel: String {
        guard let earliest = archiveOverviewReceiptEntries.last?.createdAt else {
            return "—"
        }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return "Since \(formatter.string(from: earliest)) · \(archiveOverviewReceiptEntries.count) run\(archiveOverviewReceiptEntries.count == 1 ? "" : "s")"
    }

    private var archiveOverviewReceiptEntries: [RunHistoryEntry] {
        Self.archiveOverviewReceiptEntries(from: historyStore.entries)
    }

    static func archiveOverviewReceiptEntries(from entries: [RunHistoryEntry]) -> [RunHistoryEntry] {
        entries
            .filter { $0.kind == .auditReceipt }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func shouldShowArchiveOverview(receiptEntries: [RunHistoryEntry], totalFramesArchived: Int) -> Bool {
        !receiptEntries.isEmpty && totalFramesArchived > 0
    }

    private var sparklinePoints: [SparklinePoint] {
        // Process oldest -> newest so the cumulative line trends up.
        let chronological = archiveOverviewReceiptEntries.sorted { $0.createdAt < $1.createdAt }
        return chronological.enumerated().map { index, entry in
            SparklinePoint(id: index, date: entry.createdAt, cumulative: index + 1)
        }
    }

    private struct SparklinePoint: Identifiable {
        let id: Int
        let date: Date
        let cumulative: Int
    }

    private func refreshErrorStrip(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
            Text(message)
                .font(DesignTokens.Typography.body)
                .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
        }
        .padding(DesignTokens.Layout.compactPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous)
                .fill(DesignTokens.ColorSystem.statusWarning.opacity(0.08))
        )
    }

    // MARK: - Recovery center

    private var recoveryCenterSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SectionHeading(
                title: "Undo Center",
                message: "Recent runs that have a recovery receipt."
            )

            let receipts = filteredRecoveryReceipts
            if receipts.isEmpty {
                EmptyStateView(
                    title: "No Revertable Runs Yet",
                    message: "Transfers, dedupe commits, and reorganize runs write receipts here when they can be undone safely.",
                    systemImage: "arrow.uturn.backward.circle"
                )
            } else {
                DarkroomPanel(variant: .panel) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(receipts.prefix(5).enumerated()), id: \.element.id) { index, entry in
                            if index != 0 {
                                Rectangle()
                                    .fill(DesignTokens.ColorSystem.hairline.opacity(0.5))
                                    .frame(height: 0.5)
                            }
                            recoveryRow(for: entry)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("recoveryCenterSection")
    }

    private var filteredRecoveryReceipts: [RunHistoryEntry] {
        historyStore.entries
            .filter {
                $0.kind == .auditReceipt
                    || $0.kind == .dedupeAuditReceipt
                    || $0.kind == .reorganizeAuditReceipt
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private func recoveryRow(for entry: RunHistoryEntry) -> some View {
        HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
            Image(systemName: recoverySymbol(for: entry.kind))
                .foregroundStyle(tint(for: entry.kind))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 3) {
                Text(recoveryTitle(for: entry))
                    .font(.subheadline.weight(.semibold))
                Text("\(entry.createdAt.formatted(date: .abbreviated, time: .shortened)) · \(entry.relativePath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            Button(Self.confirmationActionLabel(for: entry)) {
                pendingRevertEntry = entry
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
    }

    private func recoverySymbol(for kind: RunHistoryEntryKind) -> String {
        switch kind {
        case .dedupeAuditReceipt:
            return "trash.slash"
        case .reorganizeAuditReceipt:
            return "rectangle.3.offgrid"
        default:
            return "arrow.uturn.backward.circle"
        }
    }

    private func recoveryTitle(for entry: RunHistoryEntry) -> String {
        switch entry.kind {
        case .dedupeAuditReceipt:
            return "Deduplicate run can be restored"
        case .reorganizeAuditReceipt:
            return "Reorganize run can be undone"
        default:
            return "Transfer can be reverted"
        }
    }

    // MARK: - Reusable sources

    private var reusableSourcesSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            SectionHeading(
                title: "Reusable Sources",
                message: "Paths from completed transfers into this destination."
            )

            if historyStore.transferredSources.isEmpty {
                EmptyStateView(
                    title: "No Reusable Sources Yet",
                    message: "After a completed transfer, the source folder will appear here so you can use it again without re-entering the path.",
                    systemImage: "folder.badge.questionmark"
                )
            } else {
                DarkroomPanel(variant: .panel) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(historyStore.transferredSources.enumerated()), id: \.element.id) { index, record in
                            if index != 0 {
                                Rectangle()
                                    .fill(DesignTokens.ColorSystem.hairline)
                                    .frame(height: 0.5)
                            }
                            transferredSourceRow(for: record)
                        }
                    }
                }
            }
        }
    }

    static func sourceFolderLabel(for sourcePath: String) -> String {
        URL(fileURLWithPath: sourcePath).lastPathComponent
    }

    private func transferredSourceRow(for record: TransferredSourceRecord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 4) {
                Text(Self.sourceFolderLabel(for: record.sourcePath))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .lineLimit(1)
                Text(record.sourcePath)
                    .font(DesignTokens.Typography.mono)
                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Last used \(record.lastTransferredAt.formatted(date: .abbreviated, time: .shortened))")
                    Text("·")
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted.opacity(0.5))
                    Text("\(record.runCount) run\(record.runCount == 1 ? "" : "s")")
                    Text("·")
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted.opacity(0.5))
                    Text("\(record.totalCopiedCount) copied")
                }
                .font(DesignTokens.Typography.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            Button("Use Again") {
                appState.useHistoricalSource(record)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("useHistoricalSourceButton")

            Menu {
                Button("Reveal in Finder") {
                    appState.revealTransferredSource(record)
                }
                .accessibilityIdentifier("revealHistoricalSourceButton")
                Divider()
                Button("Forget This Source", role: .destructive) {
                    appState.forgetTransferredSource(record)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions for source")
        }
        .padding(.horizontal, 2)
        .padding(.vertical, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Archive (artifact list)

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.md) {
                SectionHeading(
                    title: "Artifacts",
                    message: "Reports, receipts, and logs from every preview and transfer."
                )

                Spacer(minLength: DesignTokens.Spacing.md)

                Picker("Filter", selection: $historyFilter) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)
                .accessibilityIdentifier("historyFilterControl")
            }

            if filteredEntries.isEmpty {
                EmptyStateView(
                    title: historyStore.entries.isEmpty ? "No Artifacts Yet" : "No Matching Artifacts",
                    message: historyStore.entries.isEmpty
                        ? "Run a preview or transfer, then return here to inspect reports, receipts, and logs."
                        : "Try a different filter or search term.",
                    systemImage: "doc.text.magnifyingglass"
                )
            } else {
                DarkroomPanel(variant: .panel) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(groupedEntries.enumerated()), id: \.element.id) { sectionIndex, section in
                            if sectionIndex != 0 {
                                Rectangle()
                                    .fill(DesignTokens.ColorSystem.hairline)
                                    .frame(height: 0.5)
                                    .padding(.vertical, DesignTokens.Spacing.sm)
                            }

                            VStack(alignment: .leading, spacing: 0) {
                                sectionHeader(for: section.date)

                                ForEach(Array(section.entries.enumerated()), id: \.element.id) { entryIndex, entry in
                                    if entryIndex != 0 {
                                        Rectangle()
                                            .fill(DesignTokens.ColorSystem.hairline.opacity(0.5))
                                            .frame(height: 0.5)
                                    }
                                    artifactRow(for: entry)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    private func sectionHeader(for date: Date) -> some View {
        Text(date.formatted(date: .abbreviated, time: .omitted).uppercased())
            .font(DesignTokens.Typography.label)
            .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
            .tracking(0.8)
            .padding(.bottom, DesignTokens.Spacing.xs)
            .padding(.top, DesignTokens.Spacing.xs)
    }

    private func artifactRow(for entry: RunHistoryEntry) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Circle()
                .fill(ribbonTint(for: entry.kind))
                .frame(width: 6, height: 6)
                .padding(.top, 4)
                .accessibilityHidden(true)

            Image(systemName: entry.kind.systemImage)
                .font(.system(size: 14))
                .foregroundStyle(tint(for: entry.kind))
                .frame(width: 20, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(DesignTokens.Typography.body)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(entry.kind.title)
                    Text("·")
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted.opacity(0.5))
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    if let size = entry.fileSizeBytes {
                        Text("·")
                            .foregroundStyle(DesignTokens.ColorSystem.inkMuted.opacity(0.5))
                        Text(Self.fileSizeFormatter.string(fromByteCount: size))
                    }
                }
                .font(DesignTokens.Typography.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            Text(entry.relativePath)
                .font(DesignTokens.Typography.mono)
                .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 260, alignment: .trailing)

            Button("Open") {
                if entry.kind == .auditReceipt || entry.kind == .dedupeAuditReceipt || entry.kind == .reorganizeAuditReceipt {
                    selectedReceiptEntry = entry
                } else {
                    appState.openHistoryEntry(entry)
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityLabel("Open \(entry.title)")
            .accessibilityIdentifier("openArtifact_\(entry.id)")

            Menu {
                Button("Reveal in Finder") {
                    appState.revealHistoryEntry(entry)
                }
                .accessibilityIdentifier("revealArtifact_\(entry.id)")
                if entry.kind == .auditReceipt || entry.kind == .dedupeAuditReceipt || entry.kind == .reorganizeAuditReceipt {
                    Divider()
                    Button("Revert this run…") {
                        pendingRevertEntry = entry
                    }
                    .accessibilityIdentifier("revertArtifact_\(entry.id)")
                }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    historyStore.remove(entry: entry)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityLabel("More actions for \(entry.title)")
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    private var filteredEntries: [RunHistoryEntry] {
        historyStore.entries
            .filter { historyFilter.matches($0) }
            .filter { entry in
                guard !searchText.isEmpty else { return true }
                let query = searchText.lowercased()
                return entry.title.lowercased().contains(query)
                    || entry.relativePath.lowercased().contains(query)
                    || entry.kind.title.lowercased().contains(query)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var groupedEntries: [HistorySection] {
        let grouped = Dictionary(grouping: filteredEntries) { entry in
            Calendar.current.startOfDay(for: entry.createdAt)
        }

        return grouped
            .keys
            .sorted(by: >)
            .map { date in
                HistorySection(
                    date: date,
                    entries: grouped[date]?.sorted(by: { $0.createdAt > $1.createdAt }) ?? []
                )
            }
    }

    private func tint(for kind: RunHistoryEntryKind) -> SwiftUI.Color {
        switch kind {
        case .dryRunReport, .csvArtifact:
            return DesignTokens.ColorSystem.accentAction
        case .auditReceipt, .jsonArtifact:
            return DesignTokens.ColorSystem.statusSuccess
        case .dedupeAuditReceipt, .reorganizeAuditReceipt:
            return DesignTokens.ColorSystem.accentWaypoint
        case .runLog:
            return DesignTokens.ColorSystem.accentWaypoint
        case .queueDatabase:
            return DesignTokens.ColorSystem.statusActive
        }
    }

    /// Status-tinted dot for the artifact ribbon. Green for completed
    /// transfers/dedupe/reorganize that wrote a receipt; amber for in-flight
    /// or partial states (previews, logs); muted for everything else.
    private func ribbonTint(for kind: RunHistoryEntryKind) -> SwiftUI.Color {
        switch kind {
        case .auditReceipt, .dedupeAuditReceipt, .reorganizeAuditReceipt:
            return DesignTokens.ColorSystem.statusSuccess
        case .dryRunReport, .csvArtifact, .jsonArtifact:
            return DesignTokens.ColorSystem.accentAction
        case .runLog, .queueDatabase:
            return DesignTokens.ColorSystem.inkMuted
        }
    }
}

struct ReceiptDetailSheet: View {
    let entry: RunHistoryEntry
    let appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var transfers: [ReceiptVisualItem] = []
    @State private var metadata: ReceiptMetadata? = nil
    @State private var verificationResults: [String: VerificationStatus] = [:]
    @State private var isVerifying = false
    @State private var errorMessage: String? = nil

    enum VerificationStatus: String {
        case pending = "Pending"
        case matching = "Match"
        case mismatch = "Modified"
        case missing = "Missing"
    }

    struct ReceiptVisualItem: Identifiable {
        let id = UUID()
        let source: String
        let dest: String
        let hash: String
        let sizeBytes: Int64?
    }

    struct ReceiptMetadata {
        let title: String
        let timestamp: Date
        let status: String
        let schemaVersion: Int
        let totalFiles: Int
        let bytesReclaimed: Int64?
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionSpacing) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(metadata?.title ?? entry.kind.title)
                        .font(.title2.weight(.bold))
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    if let meta = metadata {
                        Text("Run: \(meta.timestamp.formatted(date: .abbreviated, time: .shortened)) · Status: \(meta.status)")
                            .font(.subheadline)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    }
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                }
                .buttonStyle(.plain)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
                    .padding()
            } else if transfers.isEmpty {
                VStack {
                    ProgressView("Loading receipt content...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Table of transfers
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(transfers) { item in
                            HStack(alignment: .center) {
                                Image(systemName: isVideo(item.dest) ? "video" : "photo")
                                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                                    .frame(width: 20)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(URL(fileURLWithPath: item.dest).lastPathComponent)
                                        .font(.subheadline.weight(.medium))
                                    Text(item.dest)
                                        .font(.caption2)
                                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }

                                Spacer()

                                if let size = item.sizeBytes {
                                    Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                        .font(.caption)
                                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                                }

                                statusView(for: item.dest)
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(DesignTokens.ColorSystem.hairline.opacity(0.15))
                            )
                            .contextMenu {
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.selectFile(item.dest, inFileViewerRootedAtPath: "")
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 400)

                // Actions Footer
                HStack {
                    Button(isVerifying ? "Verifying..." : "Verify Status") {
                        Task { await runVerification() }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isVerifying)

                    Spacer()

                    Button("Revert This Run…") {
                        dismiss()
                        appState.revertHistoryEntry(entry)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.top, 12)
            }
        }
        .padding(DesignTokens.Layout.contentPadding)
        .frame(width: 600)
        .darkroom()
        .onAppear {
            loadReceipt()
        }
    }

    private func isVideo(_ path: String) -> Bool {
        let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
        return ["mov", "mp4", "m4v"].contains(ext)
    }

    @ViewBuilder
    private func statusView(for path: String) -> some View {
        let status = verificationResults[path] ?? .pending
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor(status))
                .frame(width: 6, height: 6)
            Text(status.rawValue)
                .font(.caption)
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(statusColor(status).opacity(0.1), in: Capsule())
    }

    private func statusColor(_ status: VerificationStatus) -> Color {
        switch status {
        case .pending: return DesignTokens.ColorSystem.inkMuted
        case .matching: return DesignTokens.ColorSystem.statusSuccess
        case .mismatch: return DesignTokens.ColorSystem.statusWarning
        case .missing: return DesignTokens.ColorSystem.inkMuted
        }
    }

    private func loadReceipt() {
        let fileURL = URL(fileURLWithPath: entry.path)
        guard let data = try? Data(contentsOf: fileURL) else {
            errorMessage = "Could not read the receipt file from disk."
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if entry.kind == .dedupeAuditReceipt {
            if let dedupeReceipt = try? decoder.decode(DeduplicateAuditReceipt.self, from: data) {
                self.metadata = ReceiptMetadata(
                    title: "Deduplication Run Details",
                    timestamp: dedupeReceipt.createdAt,
                    status: dedupeReceipt.status,
                    schemaVersion: dedupeReceipt.schemaVersion,
                    totalFiles: dedupeReceipt.items.count,
                    bytesReclaimed: dedupeReceipt.bytesReclaimed
                )
                self.transfers = dedupeReceipt.items.map {
                    ReceiptVisualItem(source: $0.originalPath, dest: $0.originalPath, hash: "", sizeBytes: $0.sizeBytes)
                }
            } else {
                errorMessage = "Failed to parse the deduplication receipt."
            }
        } else if entry.kind == .reorganizeAuditReceipt {
            if let reorganizeReceipt = try? decoder.decode(ReorganizeAuditReceipt.self, from: data) {
                self.metadata = ReceiptMetadata(
                    title: "Reorganize Run Details",
                    timestamp: reorganizeReceipt.startedAt,
                    status: reorganizeReceipt.status,
                    schemaVersion: reorganizeReceipt.schemaVersion,
                    totalFiles: reorganizeReceipt.items.count,
                    bytesReclaimed: nil
                )
                self.transfers = reorganizeReceipt.items.map {
                    ReceiptVisualItem(source: $0.sourcePath, dest: $0.destinationPath, hash: $0.hash, sizeBytes: nil)
                }
            } else {
                errorMessage = "Failed to parse the reorganize receipt."
            }
        } else {
            // Standard organize audit receipt
            if let revertReceipt = try? decoder.decode(RevertReceipt.self, from: data) {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyyMMdd_HHmmss"
                let date = revertReceipt.timestamp.flatMap { formatter.date(from: $0) } ?? entry.createdAt

                self.metadata = ReceiptMetadata(
                    title: "Organize Run Details",
                    timestamp: date,
                    status: revertReceipt.status ?? "COMPLETED",
                    schemaVersion: revertReceipt.schemaVersion ?? 1,
                    totalFiles: revertReceipt.transfers.count,
                    bytesReclaimed: nil
                )
                self.transfers = revertReceipt.transfers.map {
                    ReceiptVisualItem(source: $0.source, dest: $0.dest, hash: $0.hash, sizeBytes: nil)
                }
            } else {
                errorMessage = "Failed to parse the organize receipt."
            }
        }
    }

    private func runVerification() async {
        isVerifying = true
        let items = transfers
        await Task.detached(priority: .userInitiated) {
            let fileManager = FileManager.default
            let hasher = FileIdentityHasher()
            var results: [String: VerificationStatus] = [:]

            for item in items {
                if !fileManager.fileExists(atPath: item.dest) {
                    results[item.dest] = .missing
                } else if item.hash.isEmpty {
                    results[item.dest] = .matching
                } else {
                    do {
                        let fd = Darwin.open(item.dest, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
                        if fd >= 0 {
                            var fdStat = stat()
                            if fstat(fd, &fdStat) == 0 {
                                let identity = try hasher.hashIdentity(descriptor: fd, size: Int64(fdStat.st_size))
                                results[item.dest] = (identity.rawValue == item.hash) ? .matching : .mismatch
                            } else {
                                results[item.dest] = .mismatch
                            }
                            Darwin.close(fd)
                        } else {
                            results[item.dest] = .mismatch
                        }
                    } catch {
                        results[item.dest] = .mismatch
                    }
                }
            }

            await MainActor.run {
                self.verificationResults = results
                self.isVerifying = false
            }
        }.value
    }
}
