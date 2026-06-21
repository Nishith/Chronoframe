#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

enum DedupeClusterConfidenceFilter: String, CaseIterable {
    case all
    case high
    case medium
    case low

    /// One vocabulary for confidence everywhere a user sees it: these tab
    /// labels, the row badge (`MatchReasonFormatter.confidenceLabel`), and the
    /// bulk action ("Accept All Safe") all use Safe / Check / Risky so the
    /// user can connect them. VoiceOver speaks the underlying
    /// high/medium/low confidence via `DeduplicateAccessibilityText`.
    var label: String {
        switch self {
        case .all: return "All"
        case .high: return "Safe"
        case .medium: return "Check"
        case .low: return "Risky"
        }
    }

    func includes(_ cluster: DuplicateCluster) -> Bool {
        switch self {
        case .all: return true
        case .high: return (cluster.annotation?.confidence ?? .medium) == .high
        case .medium: return (cluster.annotation?.confidence ?? .medium) == .medium
        case .low: return (cluster.annotation?.confidence ?? .medium) == .low
        }
    }

    static func filtered(_ clusters: [DuplicateCluster], by filter: DedupeClusterConfidenceFilter) -> [DuplicateCluster] {
        clusters.filter { filter.includes($0) }
    }
}

/// Canonical review order: safest kinds first, matching the list's visual
/// grouping, so the default focus lands on the safest group and "next"
/// always means the next row the user actually sees.
enum DedupeReviewOrder {
    static let kindOrder: [ClusterKind] = [.exactDuplicate, .burst, .nearDuplicate, .editedVariant]

    static func sorted(_ clusters: [DuplicateCluster]) -> [DuplicateCluster] {
        let rank = Dictionary(uniqueKeysWithValues: kindOrder.enumerated().map { ($1, $0) })
        return clusters.enumerated()
            .sorted { a, b in
                let rankA = rank[a.element.kind] ?? kindOrder.count
                let rankB = rank[b.element.kind] ?? kindOrder.count
                if rankA != rankB { return rankA < rankB }
                // Stable within a kind: preserve the scanner's order.
                return a.offset < b.offset
            }
            .map(\.element)
    }
}

enum DedupeAccessibilityFocusSelection {
    static func selectedClusterID(
        accessibilityFocusedClusterID: UUID?,
        currentSelection: UUID?
    ) -> UUID? {
        accessibilityFocusedClusterID ?? currentSelection
    }
}

/// Left pane: scrollable list of all clusters grouped by kind. Each row
/// shows a thumbnail strip of the cluster's members, member count, and
/// recoverable bytes. Selecting a row sets the focused cluster in the
/// parent view.
struct ClusterListPane: View {
    let clusters: [DuplicateCluster]
    let decisions: DedupeDecisions
    let approvedClusterIDs: Set<DuplicateCluster.ID>
    let deletionPlan: DeduplicationPlan
    @Binding var focusedClusterID: UUID?
    @Binding var focusedMemberPath: String?
    @ObservedObject var thumbnailLoader: DedupeThumbnailLoader
    @Binding var confidenceFilter: DedupeClusterConfidenceFilter
    var videoAnalysisNote: String? = nil
    var onKeepAll: (DuplicateCluster) -> Void = { _ in }
    var onAcceptSuggestion: (DuplicateCluster) -> Void = { _ in }
    var onDeleteAll: (DuplicateCluster) -> Void = { _ in }
    var accessibilityFocusedClusterID: AccessibilityFocusState<UUID?>.Binding

    private var filteredClusters: [DuplicateCluster] {
        DedupeClusterConfidenceFilter.filtered(clusters, by: confidenceFilter)
    }

    private var grouped: [(ClusterKind, [DuplicateCluster])] {
        let order = DedupeReviewOrder.kindOrder
        return order.compactMap { kind in
            let matching = filteredClusters.filter { $0.kind == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    /// Pre-aggregate `deletionPlan.items` into a per-cluster byte total
    /// so each row's recoverable-bytes lookup is O(1) instead of
    /// O(plan.items). For large dedupe sessions the previous scan-per-
    /// row approach turned into tens of thousands of comparisons on
    /// every body re-evaluation.
    private var recoverableBytesByCluster: [DuplicateCluster.ID: Int64] {
        var totals: [DuplicateCluster.ID: Int64] = [:]
        totals.reserveCapacity(clusters.count)
        for item in deletionPlan.items {
            totals[item.owningClusterID, default: 0] += item.sizeBytes
        }
        return totals
    }

    private func bucketCount(_ filter: DedupeClusterConfidenceFilter) -> Int {
        DedupeClusterConfidenceFilter.filtered(clusters, by: filter).count
    }

    var body: some View {
        VStack(spacing: 0) {
            if let videoAnalysisNote {
                HStack(alignment: .firstTextBaseline, spacing: DesignTokens.Spacing.xs) {
                    Image(systemName: "film")
                        .accessibilityHidden(true)
                    Text(videoAnalysisNote)
                        .font(.caption)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .lineLimit(2)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, DesignTokens.Spacing.sm)
                .padding(.top, DesignTokens.Spacing.xs)
                .accessibilityElement(children: .combine)
            }
            Picker("Filter", selection: $confidenceFilter) {
                ForEach(DedupeClusterConfidenceFilter.allCases, id: \.self) { filter in
                    Text("\(filter.label) (\(bucketCount(filter)))")
                        .tag(filter)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, DesignTokens.Spacing.sm)
            .padding(.vertical, DesignTokens.Spacing.xs)

            // Compute the per-cluster aggregate ONCE per body, not
            // once per visible row. See `recoverableBytesByCluster`.
            let bytesByCluster = recoverableBytesByCluster
            List(selection: $focusedClusterID) {
                ForEach(grouped, id: \.0) { kind, list in
                    Section(header: Text("\(kind.title) (\(list.count))")) {
                        ForEach(list) { cluster in
                            ClusterRow(
                                cluster: cluster,
                                decisions: decisions,
                                isApproved: approvedClusterIDs.contains(cluster.id),
                                recoverableBytes: bytesByCluster[cluster.id] ?? 0,
                                thumbnailLoader: thumbnailLoader,
                                onKeepAll: { onKeepAll(cluster) },
                                onAcceptSuggestion: { onAcceptSuggestion(cluster) },
                                onDeleteAll: { onDeleteAll(cluster) }
                            )
                            .tag(cluster.id)
                            .contentShape(Rectangle())
                            .accessibilityFocused(accessibilityFocusedClusterID, equals: cluster.id)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .accessibilityRotor(LocalizedStringKey("Safe Matches")) {
                ForEach(filteredClusters.filter { ($0.annotation?.confidence ?? .medium) == .high }) { cluster in
                    AccessibilityRotorEntry(DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster), id: cluster.id)
                }
            }
            .accessibilityRotor(LocalizedStringKey("Check Matches")) {
                ForEach(filteredClusters.filter { ($0.annotation?.confidence ?? .medium) == .medium }) { cluster in
                    AccessibilityRotorEntry(DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster), id: cluster.id)
                }
            }
            .accessibilityRotor(LocalizedStringKey("Risky Matches")) {
                ForEach(filteredClusters.filter { ($0.annotation?.confidence ?? .medium) == .low }) { cluster in
                    AccessibilityRotorEntry(DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster), id: cluster.id)
                }
            }
            .accessibilityRotor(LocalizedStringKey("Exact Duplicates")) {
                ForEach(filteredClusters.filter { $0.kind == .exactDuplicate }) { cluster in
                    AccessibilityRotorEntry(DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster), id: cluster.id)
                }
            }
            .accessibilityRotor(LocalizedStringKey("Perceptual Matches")) {
                ForEach(filteredClusters.filter { $0.kind != .exactDuplicate }) { cluster in
                    AccessibilityRotorEntry(DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster), id: cluster.id)
                }
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.dedupeReviewClusterList)
        .onChange(of: focusedClusterID) { _, newID in
            guard let newID, let cluster = clusters.first(where: { $0.id == newID }) else { return }
            focusedMemberPath = cluster.members.first?.path
        }
    }

}

private struct ClusterRow: View {
    let cluster: DuplicateCluster
    let decisions: DedupeDecisions
    let isApproved: Bool
    let recoverableBytes: Int64
    @ObservedObject var thumbnailLoader: DedupeThumbnailLoader
    var onKeepAll: () -> Void = {}
    var onAcceptSuggestion: () -> Void = {}
    var onDeleteAll: () -> Void = {}
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(cluster.members.prefix(5)) { member in
                    DedupeThumbnailView(
                        path: member.path,
                        size: CGSize(width: 44, height: 44),
                        loader: thumbnailLoader
                    )
                    .accessibilityHidden(true)
                    .opacity(decisionFor(member) == .delete ? 0.45 : 1.0)
                    .overlay(alignment: .topTrailing) {
                        // Once the user has touched a decision the
                        // scanner's suggestion is no longer actionable
                        // signal — the decision badge / opacity already
                        // communicate keep vs delete. Hide the seal so
                        // the thumbnail doesn't carry three signals.
                        let hasExplicitDecision = decisions.byPath[member.path] != nil
                        if !hasExplicitDecision && isSuggestedKeeper(member) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(DesignTokens.ColorSystem.statusSuccess)
                                .padding(2)
                        }
                    }
                }
                if cluster.members.count > 5 {
                    Text("+\(cluster.members.count - 5)")
                        .font(.caption2)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
                Spacer()
                if isHovered {
                    hoverActions
                        .transition(.opacity.animation(Motion.resolved(.easeInOut(duration: 0.12), reduceMotion: reduceMotion)))
                }
            }
            HStack(spacing: 4) {
                confidenceDot
                Text(DeduplicateAccessibilityText.memberCountPhrase(cluster))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                // ByteCountFormatter renders 0 as the words "Zero KB"; an
                // unreviewed group has nothing selected yet, so show nothing.
                if recoverableBytes > 0 {
                    Circle()
                        .fill(DesignTokens.ColorSystem.separatorText)
                        .frame(width: 3, height: 3)
                        .accessibilityHidden(true)
                    Text(Self.formatter.string(fromByteCount: recoverableBytes))
                        .font(.caption)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
                if hasWarnings {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                }
                Spacer()
                if isApproved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.ColorSystem.statusSuccess)
                        .accessibilityHidden(true)
                } else {
                    Text("Suggested")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(DesignTokens.ColorSystem.statusWarning.opacity(0.12), in: Capsule())
                        .accessibilityHidden(true)
                }
                actionsMenu
            }
            if let annotation = cluster.annotation {
                Text(MatchReasonFormatter.oneLiner(annotation))
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.ColorSystem.captionText)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Keep All in Group") { onKeepAll() }
            Button("Accept Suggestion") { onAcceptSuggestion() }
            Divider()
            Button("Delete All in Group", role: .destructive) { onDeleteAll() }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DeduplicateAccessibilityText.clusterRowLabel(cluster: cluster))
        .accessibilityValue(DeduplicateAccessibilityText.clusterRowValue(
            cluster: cluster,
            isApproved: isApproved,
            recoverableBytes: recoverableBytes
        ))
        .accessibilityHint("Selects this duplicate group for review")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Keep All in Group") { onKeepAll() }
        .accessibilityAction(named: "Accept Suggestion") { onAcceptSuggestion() }
        .accessibilityAction(named: "Delete All in Group") { onDeleteAll() }
    }

    private var actionsMenu: some View {
        Menu {
            Button("Keep All in Group") { onKeepAll() }
            Button("Accept Suggestion") { onAcceptSuggestion() }
            Divider()
            Button("Delete All in Group", role: .destructive) { onDeleteAll() }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 13, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityActionsMenu(
            label: "Actions for duplicate group",
            hint: "Keep all, accept the suggestion, or delete all in this duplicate group."
        )
    }

    private var hoverActions: some View {
        HStack(spacing: 2) {
            Button {
                onKeepAll()
            } label: {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.ColorSystem.statusSuccess)
            }
            .buttonStyle(.borderless)
            .help(DeduplicateAccessibilityText.keepAllHelp(cluster))
            // These hover-revealed buttons are a pointer convenience; the
            // always-visible actions menu and the row's VoiceOver custom actions
            // provide the same operations for keyboard / assistive-tech users.
            // `.help` only sets AXHelp, so give each an explicit label too — an
            // icon-only button would otherwise read as bare "button" and trip the
            // audit's sufficient-element-description check.
            .accessibilityLabel("Keep all in group")

            Button {
                onAcceptSuggestion()
            } label: {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.ColorSystem.accentAction)
            }
            .buttonStyle(.borderless)
            .help("Accept suggestion (keep best, delete rest)")
            .accessibilityLabel("Accept suggestion")

            Button(role: .destructive) {
                onDeleteAll()
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DesignTokens.ColorSystem.statusDanger)
            }
            .buttonStyle(.borderless)
            .help(DeduplicateAccessibilityText.deleteAllHelp(cluster))
            .accessibilityLabel("Delete all in group")
        }
    }

    private func decisionFor(_ member: PhotoCandidate) -> DedupeDecision {
        decisions.byPath[member.path] ?? (isSuggestedKeeper(member) ? .keep : .delete)
    }

    private var hasWarnings: Bool {
        guard let annotation = cluster.annotation else { return false }
        return !annotation.warnings.isEmpty
    }

    @ViewBuilder
    private var confidenceDot: some View {
        let level = cluster.annotation?.confidence ?? .medium
        if differentiateWithoutColor {
            Image(systemName: confidenceSymbol(level))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(confidenceColor(level))
                .frame(width: 10)
                .accessibilityHidden(true)
        } else {
            Circle()
                .fill(confidenceColor(level))
                .frame(width: 6, height: 6)
                .accessibilityHidden(true)
        }
    }

    private func confidenceColor(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .high: return DesignTokens.ColorSystem.statusSuccess
        case .medium: return DesignTokens.ColorSystem.statusWarning
        case .low: return DesignTokens.ColorSystem.statusDanger
        }
    }

    private func confidenceSymbol(_ level: ConfidenceLevel) -> String {
        switch level {
        case .high: return "checkmark.seal.fill"
        case .medium: return "exclamationmark.circle.fill"
        case .low: return "exclamationmark.triangle.fill"
        }
    }

    private func isSuggestedKeeper(_ member: PhotoCandidate) -> Bool {
        cluster.suggestedKeeperIDs.prefix(1).contains(member.id)
    }

}
