#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

enum HistoryFilter: String, CaseIterable, Identifiable {
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var searchText = ""
    @State private var historyFilter: HistoryFilter = .all
    @State private var pendingRevertEntry: RunHistoryEntry?
    @State private var selectedReceiptEntry: RunHistoryEntry?
    @State private var selectedTimelineMonth: String? = nil
    @State private var isTimelineScrubbing = false

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
            .frame(maxWidth: .infinity, alignment: .center)
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
                    .scaledFont(.title)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                Text(headerMessage)
                    .scaledFont(.subtitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .lineLimit(2)
                    .padding(.horizontal, 2)
                    .background(DesignTokens.ColorSystem.canvas)
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
                        .scaledFont(.display)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        .contentTransition(.numericText())

                    Text("frames archived")
                        .scaledFont(.label)
                        .tracking(0.8)
                        .textCase(.uppercase)
                        .foregroundStyle(DesignTokens.ColorSystem.captionText)

                    Text(sinceLabel)
                        .scaledFont(.body)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
                .frame(maxWidth: 220, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Archive overview: \(totalFramesArchived) frames archived across \(archiveOverviewReceiptEntries.count) runs.")

                Divider()
                    .frame(height: 120)

                InteractiveTimelineView(
                    buckets: timelineBuckets,
                    barFills: barFills,
                    selectedBucketKey: $selectedTimelineMonth,
                    isScrubbing: $isTimelineScrubbing,
                    customAccessibilityValue: timelineAccessibilityValue
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
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

    private var timelineBuckets: [DateHistogramBucket] {
        Self.makeTimelineBuckets(from: archiveOverviewReceiptEntries)
    }

    static func makeTimelineBuckets(from receiptEntries: [RunHistoryEntry]) -> [DateHistogramBucket] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current

        let grouped = Dictionary(grouping: receiptEntries) { entry in
            formatter.string(from: entry.createdAt)
        }

        return grouped.map { key, entries in
            DateHistogramBucket(key: key, plannedCount: entries.count)
        }.sorted { $0.key < $1.key }
    }

    private var barFills: [Double] {
        Array(repeating: 1.0, count: timelineBuckets.count)
    }

    private var timelineAccessibilityValue: String {
        if let key = selectedTimelineMonth {
            let matchingBucket = timelineBuckets.first { $0.key == key }
            let count = matchingBucket?.plannedCount ?? 0
            return "Selected month: \(formatMonthYear(key)), \(count) runs. Timeline contains \(timelineBuckets.count) months."
        }
        let total = timelineBuckets.reduce(0) { $0 + $1.plannedCount }
        return "Timeline containing \(total) runs across \(timelineBuckets.count) months. Unselected."
    }

    private func formatMonthYear(_ key: String) -> String {
        guard key != "Unknown", key.count >= 7 else {
            return key == "Unknown" ? "Unknown Date" : key
        }
        let yearPart = key.prefix(4)
        let monthPart = key.dropFirst(5).prefix(2)
        guard let month = Int(monthPart), (1...12).contains(month) else {
            return key
        }
        let monthName = DateFormatter().monthSymbols[month - 1]
        return "\(monthName) \(yearPart)"
    }

    private func refreshErrorStrip(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.sm) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
            Text(message)
                .scaledFont(.body)
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
        .accessibilityIdentifier(AccessibilityIdentifiers.recoveryCenterSection)
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
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
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
                    .scaledFont(.mono)
                    .foregroundStyle(DesignTokens.ColorSystem.captionText)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text("Last used \(record.lastTransferredAt.formatted(date: .abbreviated, time: .shortened))")
                    Circle()
                        .fill(DesignTokens.ColorSystem.separatorText)
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)
                    Text("\(record.runCount) run\(record.runCount == 1 ? "" : "s")")
                    Circle()
                        .fill(DesignTokens.ColorSystem.separatorText)
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)
                    Text("\(record.totalCopiedCount) copied")
                }
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.metadataText)
            }

            Spacer(minLength: DesignTokens.Spacing.md)

            Button("Use Again") {
                appState.useHistoricalSource(record)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier(AccessibilityIdentifiers.useHistoricalSourceButton)

            Menu {
                Button("Reveal in Finder") {
                    appState.revealTransferredSource(record)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.revealHistoricalSourceButton)
                Divider()
                Button("Forget This Source", role: .destructive) {
                    appState.forgetTransferredSource(record)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorSystem.captionText)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityActionsMenu(
                label: "Actions for source",
                hint: "Reveal this source in Finder or forget it."
            )
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

                if selectedTimelineMonth != nil {
                    Button(action: {
                        Motion.withMotion(Motion.mechanical, reduceMotion: reduceMotion) {
                            selectedTimelineMonth = nil
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                            Text("Clear Timeline Filter")
                        }
                        .scaledFont(.label)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .transition(.opacity.combined(with: .move(edge: .trailing)))
                    .accessibilityIdentifier("ClearTimelineFilterButton")
                }

                Picker("Filter", selection: $historyFilter) {
                    ForEach(HistoryFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 320)
                .accessibilityLabel("Filter artifacts")
                .accessibilityIdentifier(AccessibilityIdentifiers.historyFilterControl)
            }

            if filteredEntries.isEmpty {
                EmptyStateView(
                    title: historyStore.entries.isEmpty ? "No Artifacts Yet" : "No Matching Artifacts",
                    message: historyStore.entries.isEmpty
                        ? "Run a preview or transfer, then return here to inspect reports, receipts, and logs."
                        : (selectedTimelineMonth != nil ? "Try a different filter, search term, or clear the timeline filter." : "Try a different filter or search term."),
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
            .scaledFont(.label)
            .foregroundStyle(DesignTokens.ColorSystem.captionText)
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
                    .scaledFont(.body)
                    .fontWeight(.medium)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: DesignTokens.Spacing.sm) {
                    Text(entry.kind.title)
                    Circle()
                        .fill(DesignTokens.ColorSystem.separatorText)
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    if let size = entry.fileSizeBytes {
                        Circle()
                            .fill(DesignTokens.ColorSystem.separatorText)
                            .frame(width: 3, height: 3)
                            .accessibilityHidden(true)
                        Text(Self.fileSizeFormatter.string(fromByteCount: size))
                    }
                }
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.captionText)
            }

            Spacer(minLength: DesignTokens.Spacing.sm)

            Text(entry.relativePath)
                .scaledFont(.mono)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
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
            .accessibilityIdentifier(AccessibilityIdentifiers.openArtifact(entry.id))

            Menu {
                Button("Reveal in Finder") {
                    appState.revealHistoryEntry(entry)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.revealArtifact(entry.id))
                Button("Copy Path") {
                    PathClipboard.copy(entry.path, to: SystemPathPasteboard.shared)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.copyArtifactPath(entry.id))
                ShareLink(item: RunArtifactShare.fileURL(for: entry)) {
                    Text("Share…")
                }
                if entry.kind == .auditReceipt || entry.kind == .dedupeAuditReceipt || entry.kind == .reorganizeAuditReceipt {
                    Divider()
                    Button("Revert this run…") {
                        pendingRevertEntry = entry
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.revertArtifact(entry.id))
                }
                Divider()
                Button("Move to Trash", role: .destructive) {
                    historyStore.remove(entry: entry)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DesignTokens.ColorSystem.captionText)
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityActionsMenu(
                label: "Actions for \(entry.title)",
                hint: "Reveal, revert, or move this artifact to Trash."
            )
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .accessibilityElement(children: .contain)
    }

    private var filteredEntries: [RunHistoryEntry] {
        Self.filterEntries(
            historyStore.entries,
            filter: historyFilter,
            searchText: searchText,
            selectedTimelineMonth: selectedTimelineMonth
        )
    }

    static func filterEntries(
        _ entries: [RunHistoryEntry],
        filter: HistoryFilter,
        searchText: String,
        selectedTimelineMonth: String?
    ) -> [RunHistoryEntry] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM"
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone.current

        return entries
            .filter { filter.matches($0) }
            .filter { entry in
                guard !searchText.isEmpty else { return true }
                let query = searchText.lowercased()
                return entry.title.lowercased().contains(query)
                    || entry.relativePath.lowercased().contains(query)
                    || entry.kind.title.lowercased().contains(query)
            }
            .filter { entry in
                guard let monthFilter = selectedTimelineMonth else { return true }
                return formatter.string(from: entry.createdAt) == monthFilter
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
    /// Finding #9: an explicit decode-completed flag. `transfers.isEmpty` was
    /// used as the loading signal, so a valid receipt with zero items showed an
    /// endless "Loading…" spinner. Tracking load completion separately lets a
    /// genuinely empty receipt render its own empty state.
    @State private var hasLoaded = false

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
                        .foregroundStyle(DesignTokens.ColorSystem.captionText)
                }
                .buttonStyle(.plain)
            }

            if let error = errorMessage {
                Text(error)
                    .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
                    .padding()
            } else if !hasLoaded {
                VStack {
                    ProgressView("Loading receipt content...")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if transfers.isEmpty {
                VStack {
                    Text("This receipt has no recorded items.")
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Table of transfers
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(transfers) { item in
                            HStack(alignment: .center) {
                                Image(systemName: isVideo(item.dest) ? "video" : "photo")
                                    .foregroundStyle(DesignTokens.ColorSystem.captionText)
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
                                        .foregroundStyle(DesignTokens.ColorSystem.captionText)
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
        // Single source of truth for video classification so newly supported
        // formats (e.g. .avi/.mkv/.wmv/.3gp) are recognized here too, instead
        // of drifting from `MediaLibraryRules.videoExtensions`.
        MediaLibraryRules.isVideoFile(path: path)
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
        // Finding #9: mark the load complete on every exit so a valid zero-item
        // receipt renders its empty state instead of an endless spinner.
        defer { hasLoaded = true }
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
            var results: [String: VerificationStatus] = [:]
            for item in items {
                results[item.dest] = Self.verifyStatus(forDestination: item.dest, expectedHash: item.hash)
            }
            await MainActor.run {
                self.verificationResults = results
                self.isVerifying = false
            }
        }.value
    }

    /// Verify a single destination file against its receipt hash.
    ///
    /// Finding #8: the descriptor was previously closed only on the success
    /// path, so a `hashIdentity` throw (common on a flaky disk/NAS) leaked the
    /// open file descriptor. `defer` now closes it on every exit, including the
    /// `catch`, keeping descriptor use bounded across many read failures.
    ///
    /// `nonisolated` so the detached verification task can call it off the main
    /// actor (the function touches no view state).
    nonisolated static func verifyStatus(
        forDestination dest: String,
        expectedHash: String,
        fileManager: FileManager = .default,
        hasher: FileIdentityHasher = FileIdentityHasher()
    ) -> VerificationStatus {
        if !fileManager.fileExists(atPath: dest) {
            return .missing
        }
        if expectedHash.isEmpty {
            return .matching
        }
        let fd = Darwin.open(dest, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard fd >= 0 else {
            return .mismatch
        }
        defer { Darwin.close(fd) }

        var fdStat = stat()
        guard fstat(fd, &fdStat) == 0 else {
            return .mismatch
        }
        do {
            let identity = try hasher.hashIdentity(descriptor: fd, size: Int64(fdStat.st_size))
            return identity.rawValue == expectedHash ? .matching : .mismatch
        } catch {
            return .mismatch
        }
    }
}
