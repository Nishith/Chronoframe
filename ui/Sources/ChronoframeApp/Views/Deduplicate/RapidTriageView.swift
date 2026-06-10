#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

struct RapidTriageView: View {
    @ObservedObject var sessionStore: DeduplicateSessionStore
    @ObservedObject var thumbnailLoader: DedupeThumbnailLoader
    @State private var currentIndex: Int = 0
    @State private var showingComparison = false
    @State private var dragOffset: CGSize = .zero
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var clustersToReview: [DuplicateCluster]

    private var currentCluster: DuplicateCluster? {
        guard currentIndex < clustersToReview.count else { return nil }
        return clustersToReview[currentIndex]
    }

    private var progress: Double {
        guard !clustersToReview.isEmpty else { return 1.0 }
        return Double(currentIndex) / Double(clustersToReview.count)
    }

    private var reclaimableBytes: Int64 {
        let plan = sessionStore.currentDeletionPlan()
        return plan.totalBytes
    }

    private static let bytesFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if let cluster = currentCluster {
                clusterCard(cluster)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                completionView
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            actionBar
        }
        .background(DesignTokens.ColorSystem.panel)
        .frame(minWidth: 700, minHeight: 550)
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Rapid Triage")
                    .font(.headline)
                Spacer()
                Text("\(currentIndex) of \(clustersToReview.count) reviewed")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.ColorSystem.metadataText)
                Circle()
                    .fill(DesignTokens.ColorSystem.separatorText)
                    .frame(width: 3, height: 3)
                    .accessibilityHidden(true)
                Text("\(Self.bytesFormatter.string(fromByteCount: reclaimableBytes)) reclaimable")
                    .font(.caption)
                    .foregroundStyle(DesignTokens.ColorSystem.metadataText)
                Button("Exit") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            ProgressView(value: progress)
                .tint(DesignTokens.ColorSystem.accentAction)
                .accessibilityLabel("Rapid triage progress")
                .accessibilityValue("\(currentIndex) of \(clustersToReview.count) groups reviewed")
        }
        .padding(DesignTokens.Spacing.md)
    }

    // MARK: - Cluster Card

    private func clusterCard(_ cluster: DuplicateCluster) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            if let annotation = cluster.annotation, !annotation.warnings.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Review carefully — \(MatchReasonFormatter.warningSummary(annotation.warnings[0]))")
                        .font(.caption)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .clipShape(Capsule())
            }

            heroImage(for: cluster)
                .offset(dragOffset)
                .gesture(swipeGesture)
                .motion(.spring(response: 0.3), value: dragOffset)
                .accessibilityLabel("Suggested keeper for this duplicate group")
                .accessibilityHint("Swipe right or press Return to accept; swipe left or press the Left arrow to skip.")

            memberStrip(for: cluster)

            if let annotation = cluster.annotation {
                Text(MatchReasonFormatter.oneLiner(annotation))
                    .font(.caption)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
        }
        .padding(DesignTokens.Spacing.lg)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(DeduplicateAccessibilityText.rapidTriageLabel(
            cluster: cluster,
            currentIndex: currentIndex,
            totalCount: clustersToReview.count
        ))
        .accessibilityValue(DeduplicateAccessibilityText.rapidTriageValue(
            cluster: cluster,
            reclaimableBytes: reclaimableBytes
        ))
        .accessibilityAction(named: "Accept") {
            acceptCurrent()
        }
        .accessibilityAction(named: "Skip") {
            skipCurrent()
        }
        .accessibilityAction(named: "Compare") {
            showingComparison = true
        }
    }

    private func heroImage(for cluster: DuplicateCluster) -> some View {
        let keeper = cluster.members.first { cluster.suggestedKeeperIDs.prefix(1).contains($0.id) }
            ?? cluster.members.first
        return Group {
            if let keeper {
                DedupeThumbnailView(
                    path: keeper.path,
                    size: CGSize(width: 400, height: 300),
                    loader: thumbnailLoader
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .shadow(radius: 4)
                .accessibilityLabel("Suggested keeper")
                .accessibilityValue(URL(fileURLWithPath: keeper.path).lastPathComponent)
            }
        }
    }

    private func memberStrip(for cluster: DuplicateCluster) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(cluster.members) { member in
                    let isKeeper = cluster.suggestedKeeperIDs.prefix(1).contains(member.id)
                    let glyph: DedupeDecisionGlyph = isKeeper ? .keep : .delete
                    // Triage shows the cluster's *suggestion* — nothing is
                    // committed until the user accepts/skips — so the label is
                    // phrased as a suggestion, not a final keep/delete decision.
                    let suggestionLabel = isKeeper ? "Suggested keeper" : "Suggested for removal"
                    DedupeThumbnailView(
                        path: member.path,
                        size: CGSize(width: 56, height: 56),
                        loader: thumbnailLoader
                    )
                    .opacity(isKeeper ? 1.0 : 0.6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isKeeper ? DesignTokens.ColorSystem.statusSuccess : Color.clear, lineWidth: 2)
                    )
                    // Non-color cue: a glyph badge so the suggested keeper is
                    // distinguishable without relying on the green stroke.
                    .overlay(alignment: .topTrailing) {
                        Image(systemName: glyph.symbolName)
                            .font(.system(size: 14))
                            .foregroundStyle(
                                isKeeper ? DesignTokens.ColorSystem.statusSuccess : DesignTokens.ColorSystem.inkMuted,
                                Color.white
                            )
                            .padding(2)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(DeduplicateAccessibilityText.memberLabel(
                        member: member,
                        isSuggestedKeeper: isKeeper,
                        keeperReason: cluster.annotation?.keeperReason
                    ))
                    .accessibilityValue(suggestionLabel)
                    .accessibilityAddTraits(.isImage)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Photos in this group")
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: DesignTokens.Spacing.lg) {
            Button {
                skipCurrent()
            } label: {
                Label("Skip", systemImage: "arrow.right")
            }
            .keyboardShortcut(.leftArrow, modifiers: [])

            Button {
                showingComparison = true
            } label: {
                Label("Compare", systemImage: "rectangle.on.rectangle")
            }
            .keyboardShortcut(.space, modifiers: [])
            .sheet(isPresented: $showingComparison) {
                if let cluster = currentCluster,
                   let keeper = cluster.members.first(where: { cluster.suggestedKeeperIDs.prefix(1).contains($0.id) }),
                   let other = cluster.members.first(where: { !cluster.suggestedKeeperIDs.prefix(1).contains($0.id) }) {
                    ComparisonOverlayView(leftPath: keeper.path, rightPath: other.path)
                }
            }

            Button {
                acceptCurrent()
            } label: {
                Label("Accept", systemImage: "checkmark.circle")
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [])

            // Stacked `.keyboardShortcut` modifiers on a single Button
            // collapse to the last one wins, so the right-arrow binding
            // used to be silently dropped. Use an invisible second
            // button to register the second shortcut.
            Button(action: acceptCurrent) {
                EmptyView()
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .padding(DesignTokens.Spacing.md)
    }

    // MARK: - Completion

    private var completionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(DesignTokens.ColorSystem.statusSuccess)
            Text("All clusters reviewed")
                .font(.title3.weight(.semibold))
            Text("Return to the main review to commit your decisions.")
                .font(.caption)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            Button("Done") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
    }

    // MARK: - Actions

    private func acceptCurrent() {
        guard let cluster = currentCluster else { return }
        sessionStore.acceptSuggestionsForCluster(cluster)
        advance()
    }

    private func skipCurrent() {
        advance()
    }

    private func advance() {
        Motion.withMotion(.easeInOut(duration: 0.2), reduceMotion: reduceMotion) {
            dragOffset = .zero
            currentIndex += 1
        }
    }

    private var swipeGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                dragOffset = value.translation
            }
            .onEnded { value in
                switch RapidTriageSwipe.outcome(forTranslationWidth: value.translation.width) {
                case .accept: acceptCurrent()
                case .skip: skipCurrent()
                case .none: break
                }
                dragOffset = .zero
            }
    }

}
