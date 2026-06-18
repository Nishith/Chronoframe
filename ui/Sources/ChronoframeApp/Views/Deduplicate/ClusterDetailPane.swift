#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import AppKit
import ImageIO
import SwiftUI

/// Right pane: large preview of the focused photo plus the cluster member
/// strip. Each strip thumbnail shows a Keep/Delete badge and exposes
/// keyboard-friendly toggles. The "Accept suggestion" button applies the
/// scanner's suggested keeper for the current cluster.
struct ClusterDetailPane: View {
    let cluster: DuplicateCluster?
    @Binding var focusedMemberPath: String?
    @ObservedObject var sessionStore: DeduplicateSessionStore
    @ObservedObject var thumbnailLoader: DedupeThumbnailLoader
    var onAcceptAndAdvance: (() -> Void)? = nil
    @State private var thumbnailStripHeight = DeduplicateDetailPreviewLayout.defaultThumbnailStripHeight
    @State private var dragStartThumbnailStripHeight: CGFloat?
    @State private var showingReasonDetail = false
    @State private var showingComparisonOverlay = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor

    var body: some View {
        Group {
            if let cluster {
                VStack(spacing: 0) {
                    detailContent(for: cluster)
                }
                .background {
                    // Two separate buttons: stacking two
                    // `.keyboardShortcut` modifiers on one button silently
                    // drops one (see RapidTriageView).
                    Group {
                        Button { navigateMember(by: -1, in: cluster) } label: { EmptyView() }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        Button { navigateMember(by: 1, in: cluster) } label: { EmptyView() }
                            .keyboardShortcut(.rightArrow, modifiers: [])
                        Button { setFocusedDecision(.keep, in: cluster) } label: { EmptyView() }
                            .keyboardShortcut("k", modifiers: [])
                        Button { setFocusedDecision(.delete, in: cluster) } label: { EmptyView() }
                            .keyboardShortcut("d", modifiers: [])
                        Button { setFocusedDecision(.delete, in: cluster) } label: { EmptyView() }
                            .keyboardShortcut(.delete, modifiers: [])
                        Button { showingComparisonOverlay = true } label: { EmptyView() }
                            .keyboardShortcut(.space, modifiers: [])
                    }
                    .opacity(0)
                    .frame(width: 0, height: 0)
                    .accessibilityHidden(true)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "rectangle.on.rectangle.angled")
                        .font(.system(size: 48))
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .accessibilityHidden(true)
                    Text("Select a cluster on the left")
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("No duplicate group selected")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.dedupeReviewDetail)
    }

    @ViewBuilder
    private func detailContent(for cluster: DuplicateCluster) -> some View {
        let focused = focusedMember(in: cluster)

        GeometryReader { geometry in
            let stripHeight = DeduplicateDetailPreviewLayout.clampedThumbnailStripHeight(
                thumbnailStripHeight,
                availableHeight: geometry.size.height
            )
            let previewHeight = max(
                0,
                geometry.size.height - stripHeight - DeduplicateDetailPreviewLayout.resizeHandleHeight
            )
            let isWideLayout = geometry.size.width >= 450
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    warningBanner(for: cluster)
                    if isWideLayout {
                        detailContentWide(focused: focused, cluster: cluster)
                    } else {
                        detailContentCompact(focused: focused, cluster: cluster)
                    }
                }
                .frame(height: previewHeight)

                PreviewResizeHandle(
                    dragChanged: { translation in
                        resizeThumbnailStrip(by: translation, availableHeight: geometry.size.height)
                    },
                    dragEnded: { translation in
                        finishResizingThumbnailStrip(by: translation, availableHeight: geometry.size.height)
                    },
                    adjust: { delta in
                        thumbnailStripHeight = DeduplicateDetailPreviewLayout.clampedThumbnailStripHeight(
                            stripHeight + delta,
                            availableHeight: geometry.size.height
                        )
                    }
                )

                memberStripArea(cluster: cluster, height: stripHeight)
            }
            .background(DesignTokens.ColorSystem.imageStage)
            .sheet(isPresented: $showingComparisonOverlay) {
                if let pair = sideBySidePair(for: focused, in: cluster) {
                    ComparisonOverlayView(leftPath: pair.left.path, rightPath: pair.right.path)
                }
            }
        }
    }

    private func memberStripArea(cluster: DuplicateCluster, height: CGFloat) -> some View {
        let thumbnailSize = DeduplicateDetailPreviewLayout.thumbnailSize(forStripHeight: height)
        return ViewThatFits(in: .horizontal) {
            memberStripWide(cluster: cluster, thumbnailSize: thumbnailSize)
            memberStripCompact(cluster: cluster, thumbnailSize: thumbnailSize)
        }
        .padding(.vertical, DesignTokens.Spacing.sm)
        .padding(.trailing, DesignTokens.Spacing.md)
        .frame(height: height)
        .background(.ultraThinMaterial)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.dedupeMemberStrip)
    }

    private func memberStripWide(cluster: DuplicateCluster, thumbnailSize: CGFloat) -> some View {
        HStack(spacing: DesignTokens.Spacing.md) {
            memberThumbnailStrip(cluster: cluster, thumbnailSize: thumbnailSize)
                .frame(minWidth: 0, maxWidth: .infinity)
            acceptSuggestionButton(for: cluster)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func memberStripCompact(cluster: DuplicateCluster, thumbnailSize: CGFloat) -> some View {
        VStack(alignment: .trailing, spacing: DesignTokens.Spacing.sm) {
            memberThumbnailStrip(cluster: cluster, thumbnailSize: thumbnailSize)
                .frame(minWidth: 0, maxWidth: .infinity)
            acceptSuggestionButton(for: cluster)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func memberThumbnailStrip(cluster: DuplicateCluster, thumbnailSize: CGFloat) -> some View {
        ScrollView(.horizontal, showsIndicators: true) {
            HStack(spacing: 8) {
                ForEach(cluster.members) { member in
                    memberThumb(member: member, cluster: cluster, thumbnailSize: thumbnailSize)
                }
            }
            .padding(.horizontal, DesignTokens.Spacing.md)
        }
    }

    private func acceptSuggestionButton(for cluster: DuplicateCluster) -> some View {
        Button("Accept & Next") {
            sessionStore.approveCluster(cluster.id)
            onAcceptAndAdvance?()
        }
        .fixedSize()
        .keyboardShortcut(.return, modifiers: [])
        .accessibilityIdentifier(AccessibilityIdentifiers.dedupeAcceptClusterSuggestionButton)
        .accessibilityLabel("Confirm and move to next group")
        .accessibilityHint("Confirms keep and delete choices for this group, then selects the next group")
    }

    private func detailContentCompact(focused: PhotoCandidate?, cluster: DuplicateCluster) -> some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            preview(for: focused, cluster: cluster)
                .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
            if let focused {
                metadataPanel(for: focused, cluster: cluster)
            }
        }
        .padding(DesignTokens.Spacing.md)
    }

    private func detailContentWide(focused: PhotoCandidate?, cluster: DuplicateCluster) -> some View {
        HStack(alignment: .top, spacing: DesignTokens.Spacing.lg) {
            previewArea(for: focused, cluster: cluster)
                .frame(minWidth: 160, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
            if let focused {
                metadataPanel(for: focused, cluster: cluster)
                    .frame(width: 200)
            }
        }
        .padding(DesignTokens.Spacing.lg)
    }

    /// Default-mode preview area. When the cluster has 2+ members and the
    /// available width can comfortably host two panes, render the suggested
    /// keeper on the left and the currently-focused other member on the
    /// right — the "Compare" sheet remains available for slider/difference/
    /// flicker modes. Falls back to a single large preview otherwise.
    @ViewBuilder
    private func previewArea(for focused: PhotoCandidate?, cluster: DuplicateCluster) -> some View {
        let pair = sideBySidePair(for: focused, in: cluster)
        if let pair {
            GeometryReader { geometry in
                if geometry.size.width >= 480 {
                    HStack(spacing: DesignTokens.Spacing.md) {
                        comparisonPane(member: pair.left, role: .keeper, cluster: cluster)
                        comparisonPane(member: pair.right, role: .other, cluster: cluster)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    preview(for: focused, cluster: cluster)
                }
            }
        } else {
            preview(for: focused, cluster: cluster)
        }
    }

    private enum ComparisonRole {
        case keeper
        case other

        var label: String {
            switch self {
            case .keeper: return "Keeper"
            case .other: return "Compare"
            }
        }

        var systemImage: String {
            switch self {
            case .keeper: return "star.fill"
            case .other: return "rectangle.on.rectangle"
            }
        }

        var tint: Color {
            switch self {
            case .keeper: return DesignTokens.ColorSystem.accentWaypoint
            case .other: return DesignTokens.ColorSystem.inkSecondary
            }
        }
    }

    private struct ComparisonPair {
        let left: PhotoCandidate
        let right: PhotoCandidate
    }

    private func sideBySidePair(for focused: PhotoCandidate?, in cluster: DuplicateCluster) -> ComparisonPair? {
        guard cluster.members.count >= 2 else { return nil }
        let keeper = cluster.members.first(where: { isSuggestedKeeper($0, in: cluster) }) ?? cluster.members[0]
        let other: PhotoCandidate
        if let focused, focused.id != keeper.id {
            other = focused
        } else if let firstOther = cluster.members.first(where: { $0.id != keeper.id }) {
            other = firstOther
        } else {
            return nil
        }
        return ComparisonPair(left: keeper, right: other)
    }

    private func comparisonPane(member: PhotoCandidate, role: ComparisonRole, cluster: DuplicateCluster) -> some View {
        let isFocused = member.path == focusedMemberPath
        let decision = sessionStore.decisions.byPath[member.path] ?? (isSuggestedKeeper(member, in: cluster) ? .keep : .delete)
        return Button {
            focusedMemberPath = member.path
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.black.opacity(0.34))
                LargePreviewImage(path: member.path)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                comparisonPaneBadge(role: role, decision: decision)
                    .padding(10)
            }
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(
                    isFocused ? DesignTokens.ColorSystem.accentWaypoint : Color.white.opacity(0.08),
                    lineWidth: isFocused ? 2 : 0.5
                )
        }
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(member.path, inFileViewerRootedAtPath: "")
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(role.label): \(AccessibilityPathFormatter.formatFilename(URL(fileURLWithPath: member.path).lastPathComponent))")
        .accessibilityHint(DeduplicateAccessibilityText.selectsForKeyboardActionsHint(member))
        .accessibilityAddTraits(isFocused ? .isSelected : [])
    }

    private func comparisonPaneBadge(role: ComparisonRole, decision: DedupeDecision) -> some View {
        HStack(spacing: 6) {
            Image(systemName: role.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(role.tint)
            Text(role.label)
                .scaledFont(.label, weight: .semibold)
                .foregroundStyle(.white)
            if differentiateWithoutColor {
                Image(systemName: decision == .keep ? "checkmark" : "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(decision == .keep ? DesignTokens.ColorSystem.statusSuccess : DesignTokens.ColorSystem.statusDanger)
            } else {
                Circle()
                    .fill(decision == .keep ? DesignTokens.ColorSystem.statusSuccess : DesignTokens.ColorSystem.statusDanger)
                    .frame(width: 6, height: 6)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.black.opacity(0.46), in: Capsule())
    }

    private func preview(for member: PhotoCandidate?, cluster: DuplicateCluster) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.34))
            if let member {
                LargePreviewImage(path: member.path)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .accessibilityHidden(true)
                    .overlay(alignment: .bottomLeading) {
                        photoStageLabel(for: member)
                            .accessibilityHidden(true)
                    }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 56))
                    // Placeholder sits on the dark photo-preview fill, so it must
                    // stay light in both appearances (not the dark ink token).
                    .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(member == nil)
        .accessibilityLabel(DeduplicateAccessibilityText.selectedPreviewLabel(cluster))
        .accessibilityAddTraits(.isImage)
        .accessibilityValue(member.map { selectedMember in
            DeduplicateAccessibilityText.photoPreviewDetail(
                member: selectedMember,
                decision: sessionStore.decisions.byPath[selectedMember.path] ?? (isSuggestedKeeper(selectedMember, in: cluster) ? .keep : .delete),
                isSuggestedKeeper: isSuggestedKeeper(selectedMember, in: cluster),
                confidence: cluster.annotation?.confidence,
                keeperReason: cluster.annotation?.keeperReason
            )
        } ?? "")
    }

    private func metadataPanel(for member: PhotoCandidate, cluster: DuplicateCluster) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.ColorSystem.imageStage)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(DeduplicateInspectorText.title(forCaptureDate: member.captureDate))
                        .scaledFont(.subtitle, weight: .semibold)
                        .lineLimit(2)

                    HStack(alignment: .firstTextBaseline) {
                        Text("File")
                            .scaledFont(.label)
                        Spacer()
                        Text(DeduplicateInspectorText.fileName(forPath: member.path))
                            .scaledFont(.mono)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(member.path)
                    }

                    metaRow("Size", value: byteCountFormatter.string(fromByteCount: member.size))
                    if let width = member.pixelWidth, let height = member.pixelHeight {
                        metaRow("Dimensions", value: "\(width) × \(height)")
                    }

                    Divider().padding(.vertical, 2)

                    qualityRow("Quality", score: member.qualityScore)
                    sharpnessRow("Sharpness", score: member.sharpness)
                    if let face = member.faceScore {
                        faceRow("Face", detected: face > 0.5)
                    }
                    if member.isRaw {
                        Label("RAW", systemImage: "camera.aperture")
                            .scaledFont(.label)
                    }
                    if let pairedPath = member.pairedPath {
                        Label("Paired with \(URL(fileURLWithPath: pairedPath).lastPathComponent)", systemImage: "link")
                            .scaledFont(.label)
                            .lineLimit(2)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel(DeduplicateAccessibilityText.detailsLabel(member))
                .accessibilityValue(metadataAccessibilityValue(for: member, cluster: cluster))
                .accessibilityAddTraits(.isImage)

                Divider().padding(.vertical, 2)

                decisionControls(for: member, cluster: cluster)

                if let annotation = cluster.annotation {
                    Divider().padding(.vertical, 2)
                    reasoningSection(annotation: annotation, cluster: cluster)
                }
            }
            .padding(DesignTokens.Spacing.md)
            .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignTokens.ColorSystem.imageStageHairline, lineWidth: 0.5)
        }
    }

    private func metaRow(_ label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
            Spacer()
            Text(value)
                .scaledFont(.mono)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
        }
    }

    private func qualityRow(_ label: String, score: Double) -> some View {
        let (filled, text) = Self.qualityLabel(score)
        return HStack(alignment: .firstTextBaseline) {
            Text(label)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
            Spacer()
            HStack(spacing: 3) {
                ForEach(0..<5, id: \.self) { i in
                    Circle()
                        .fill(i < filled ? DesignTokens.ColorSystem.accentAction : DesignTokens.ColorSystem.hairline)
                        .frame(width: 5, height: 5)
                }
            }
            Text(text)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
        }
        .help(String(format: "Raw score: %.2f", score))
    }

    private func sharpnessRow(_ label: String, score: Double) -> some View {
        let text = Self.sharpnessLabel(score)
        return HStack(alignment: .firstTextBaseline) {
            Text(label)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
            Spacer()
            Text(text)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
        }
        .help(String(format: "Raw score: %.2f", score))
    }

    private func faceRow(_ label: String, detected: Bool) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
            Spacer()
            Label(detected ? "Detected" : "None", systemImage: detected ? "person.fill" : "person.slash")
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
        }
    }

    static func qualityLabel(_ score: Double) -> (Int, String) {
        switch score {
        case 0.8...: return (5, "Excellent")
        case 0.6..<0.8: return (4, "Good")
        case 0.4..<0.6: return (3, "Fair")
        case 0.2..<0.4: return (2, "Poor")
        default: return (1, "Very poor")
        }
    }

    static func sharpnessLabel(_ score: Double) -> String {
        switch score {
        case 0.5...: return "Sharp"
        case 0.25..<0.5: return "Soft"
        default: return "Motion blur"
        }
    }

    private func metadataAccessibilityValue(for member: PhotoCandidate, cluster: DuplicateCluster) -> String {
        var parts: [String] = [
            DeduplicateInspectorText.title(forCaptureDate: member.captureDate),
            "File \(DeduplicateInspectorText.fileName(forPath: member.path))",
            "Size \(byteCountFormatter.string(fromByteCount: member.size))"
        ]
        if let width = member.pixelWidth, let height = member.pixelHeight {
            parts.append("Dimensions \(width) by \(height)")
        }
        parts.append("Quality \(Self.qualityLabel(member.qualityScore).1)")
        parts.append("Sharpness \(Self.sharpnessLabel(member.sharpness))")
        if let face = member.faceScore {
            parts.append(face > 0.5 ? "Face detected" : "No face detected")
        }
        if member.isRaw {
            parts.append("RAW")
        }
        if let pairedPath = member.pairedPath {
            parts.append("Paired with \(URL(fileURLWithPath: pairedPath).lastPathComponent)")
        }
        if let annotation = cluster.annotation {
            parts.append(MatchReasonFormatter.oneLiner(annotation))
        }
        return parts.joined(separator: ", ")
    }

    private func decisionControls(for member: PhotoCandidate, cluster: DuplicateCluster) -> some View {
        let current = sessionStore.decisions.byPath[member.path] ?? (isSuggestedKeeper(member, in: cluster) ? .keep : .delete)
        return Picker("Decision", selection: Binding<DedupeDecision>(
            get: { current },
            set: { newValue in sessionStore.setDecision(newValue, forPath: member.path) }
        )) {
            Label("Keep", systemImage: "tray.and.arrow.down")
                .tag(DedupeDecision.keep)
            Label("Delete", systemImage: "trash")
                .tag(DedupeDecision.delete)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    private func memberThumb(member: PhotoCandidate, cluster: DuplicateCluster, thumbnailSize: CGFloat) -> some View {
        let decision = sessionStore.decisions.byPath[member.path] ?? (isSuggestedKeeper(member, in: cluster) ? .keep : .delete)
        let isFocused = member.path == focusedMemberPath
        return Button {
            focusedMemberPath = member.path
        } label: {
            ZStack(alignment: .bottomTrailing) {
                DedupeThumbnailView(
                    path: member.path,
                    size: CGSize(width: thumbnailSize, height: thumbnailSize),
                    loader: thumbnailLoader
                )
                .opacity(decision == .delete ? 0.55 : 1.0)
                .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(isFocused ? DesignTokens.ColorSystem.accentWaypoint : Color.white.opacity(0.16), lineWidth: isFocused ? 2 : 0.5)
                )
                .overlay(alignment: .topLeading) {
                    if isSuggestedKeeper(member, in: cluster) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(DesignTokens.ColorSystem.accentWaypoint)
                            .padding(4)
                            .background(.black.opacity(0.45), in: Circle())
                            .padding(4)
                    }
                }

                Image(systemName: decision == .keep ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(decision == .keep ? DesignTokens.ColorSystem.statusSuccess : DesignTokens.ColorSystem.statusDanger, .black.opacity(0.42))
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(member.path, inFileViewerRootedAtPath: "")
            }
            Divider()
            Button("Keep") { sessionStore.setDecision(.keep, forPath: member.path) }
            Button("Delete", role: .destructive) { sessionStore.setDecision(.delete, forPath: member.path) }
        }
        .help(URL(fileURLWithPath: member.path).lastPathComponent)
        // Collapse the decorative badge/star symbols into one spoken element
        // so VoiceOver announces the filename and Keep/Delete state instead of
        // raw SF Symbol names.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(DeduplicateAccessibilityText.memberLabel(
            member: member,
            isSuggestedKeeper: isSuggestedKeeper(member, in: cluster),
            keeperReason: cluster.annotation?.keeperReason
        ))
        .accessibilityValue(DeduplicateAccessibilityText.memberValue(
            decision: decision,
            isFocused: member.path == focusedMemberPath,
            confidence: cluster.annotation?.confidence
        ))
        .accessibilityHint(DeduplicateAccessibilityText.selectsForComparisonHint(member))
        // `.accessibilityElement(children: .ignore)` on the button content drops
        // the inherited button role; re-add it so the tappable thumbnail isn't
        // reported as "Unknown role".
        .accessibilityAddTraits(isFocused ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: DeduplicateAccessibilityText.focusActionName(member)) {
            focusedMemberPath = member.path
        }
        .accessibilityAction(named: "Keep") {
            sessionStore.setDecision(.keep, forPath: member.path)
        }
        .accessibilityAction(named: "Delete") {
            sessionStore.setDecision(.delete, forPath: member.path)
        }
    }

    private func photoStageLabel(for member: PhotoCandidate) -> some View {
        HStack(spacing: 7) {
            Circle()
                .fill(DesignTokens.ColorSystem.accentWaypoint)
                .frame(width: 6, height: 6)
            Text(URL(fileURLWithPath: member.path).lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .scaledFont(.label, weight: .semibold)
        .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.black.opacity(0.46), in: Capsule())
        .padding(10)
    }

    // MARK: - Warning Banner

    @ViewBuilder
    private func warningBanner(for cluster: DuplicateCluster) -> some View {
        if let annotation = cluster.annotation, !annotation.warnings.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text(DeduplicateAccessibilityText.intentionallyDifferentNote(cluster))
                        .scaledFont(.label, weight: .semibold)
                    ForEach(Array(annotation.warnings.enumerated()), id: \.offset) { _, warning in
                        Text(MatchReasonFormatter.warningSummary(warning))
                            .scaledFont(.label)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    }
                }
                Spacer()
            }
            .padding(8)
            .background(Color.orange.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .padding(.horizontal, DesignTokens.Spacing.lg)
            .padding(.top, DesignTokens.Spacing.sm)
        }
    }

    // MARK: - Reasoning Section

    @ViewBuilder
    private func reasoningSection(annotation: ClusterAnnotation, cluster: DuplicateCluster) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                Motion.withMotion(.easeInOut(duration: 0.2), reduceMotion: reduceMotion) {
                    showingReasonDetail.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showingReasonDetail ? "chevron.down" : "chevron.right")
                        .font(.caption2)
                    Text("Why matched")
                        .scaledFont(.label, weight: .medium)
                    Spacer()
                    confidenceBadge(annotation.confidence)
                }
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showingReasonDetail {
                VStack(alignment: .leading, spacing: 4) {
                    Text(MatchReasonFormatter.summary(annotation.matchReason, in: cluster, videoEvidence: annotation.videoEvidence))
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    if let keeperReason = annotation.keeperReason {
                        Text(MatchReasonFormatter.keeperSummary(keeperReason))
                            .scaledFont(.label)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    }
                }
            }
        }

        if cluster.members.count >= 2 {
            Button {
                showingComparisonOverlay = true
            } label: {
                Label("Compare", systemImage: "rectangle.on.rectangle")
                    .scaledFont(.label)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .keyboardShortcut("c", modifiers: [])
        }
    }

    private func confidenceBadge(_ level: ConfidenceLevel) -> some View {
        Text(MatchReasonFormatter.confidenceLabel(level))
            .scaledFont(.label, weight: .semibold)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(confidenceColor(level).opacity(0.15))
            .foregroundStyle(confidenceColor(level))
            .clipShape(Capsule())
    }

    private func confidenceColor(_ level: ConfidenceLevel) -> Color {
        switch level {
        case .high: return DesignTokens.ColorSystem.statusSuccess
        case .medium: return DesignTokens.ColorSystem.statusWarning
        case .low: return DesignTokens.ColorSystem.statusDanger
        }
    }

    private func focusedMember(in cluster: DuplicateCluster) -> PhotoCandidate? {
        if let path = focusedMemberPath, let match = cluster.members.first(where: { $0.path == path }) {
            return match
        }
        return cluster.members.first
    }

    private func navigateMember(by delta: Int, in cluster: DuplicateCluster) {
        focusedMemberPath = DeduplicateMemberNavigation.focusedPath(
            afterMoving: delta,
            from: focusedMemberPath,
            through: cluster.members
        )
    }

    private func setFocusedDecision(_ decision: DedupeDecision, in cluster: DuplicateCluster) {
        guard let member = focusedMember(in: cluster) else { return }
        sessionStore.setDecision(decision, forPath: member.path)
    }

    private func isSuggestedKeeper(_ member: PhotoCandidate, in cluster: DuplicateCluster) -> Bool {
        cluster.suggestedKeeperIDs.prefix(1).contains(member.id)
    }

    private func resizeThumbnailStrip(by translation: CGFloat, availableHeight: CGFloat) {
        let currentHeight = DeduplicateDetailPreviewLayout.clampedThumbnailStripHeight(
            thumbnailStripHeight,
            availableHeight: availableHeight
        )
        let startHeight = dragStartThumbnailStripHeight ?? currentHeight
        dragStartThumbnailStripHeight = startHeight
        thumbnailStripHeight = DeduplicateDetailPreviewLayout.clampedThumbnailStripHeight(
            startHeight - translation,
            availableHeight: availableHeight
        )
    }

    private func finishResizingThumbnailStrip(by translation: CGFloat, availableHeight: CGFloat) {
        resizeThumbnailStrip(by: translation, availableHeight: availableHeight)
        dragStartThumbnailStripHeight = nil
    }

    private var byteCountFormatter: ByteCountFormatter {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }
}

/// Pure text composition for the member metadata panel, kept testable in the
/// spirit of `DeduplicateAccessibilityText`.
///
/// People recognize photos by when they were taken, not by export filename, so
/// the panel leads with the capture date. The filename stays one row below —
/// in duplicate triage it carries real evidence (" copy" suffixes, export
/// numbering) and must remain visible, just not be the headline.
enum DeduplicateInspectorText {
    static func title(
        forCaptureDate captureDate: Date?,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) -> String {
        guard let captureDate else { return "Capture date unknown" }
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: captureDate)
    }

    static func fileName(forPath path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

enum DeduplicateMemberNavigation {
    static func focusedPath(
        afterMoving delta: Int,
        from focusedPath: String?,
        through members: [PhotoCandidate]
    ) -> String? {
        guard !members.isEmpty else { return focusedPath }
        let currentIndex = members.firstIndex(where: { $0.path == focusedPath }) ?? 0
        let nextIndex = (currentIndex + delta + members.count) % members.count
        return members[nextIndex].path
    }
}

enum DeduplicateDetailPreviewLayout {
    static let defaultThumbnailStripHeight: CGFloat = 126
    static let minimumThumbnailStripHeight: CGFloat = 112
    static let maximumThumbnailStripHeight: CGFloat = 320
    static let minimumPreviewHeight: CGFloat = 260
    static let resizeHandleHeight: CGFloat = 10
    static let minimumThumbnailSize: CGFloat = 88
    static let maximumThumbnailSize: CGFloat = 240
    private static let thumbnailVerticalChrome: CGFloat = 38

    static func thumbnailStripHeightBounds(forAvailableHeight availableHeight: CGFloat) -> ClosedRange<CGFloat> {
        let usableHeight = max(0, availableHeight - resizeHandleHeight)
        let lowerBound = min(minimumThumbnailStripHeight, usableHeight)
        let previewMinimum = min(minimumPreviewHeight, max(0, usableHeight - lowerBound))
        let upperBound = max(lowerBound, min(maximumThumbnailStripHeight, usableHeight - previewMinimum))
        return lowerBound...upperBound
    }

    static func clampedThumbnailStripHeight(_ height: CGFloat, availableHeight: CGFloat) -> CGFloat {
        let bounds = thumbnailStripHeightBounds(forAvailableHeight: availableHeight)
        return min(max(height, bounds.lowerBound), bounds.upperBound)
    }

    static func thumbnailSize(forStripHeight stripHeight: CGFloat) -> CGFloat {
        min(
            max(stripHeight - thumbnailVerticalChrome, minimumThumbnailSize),
            maximumThumbnailSize
        )
    }
}

private struct PreviewResizeHandle: View {
    let dragChanged: (CGFloat) -> Void
    let dragEnded: (CGFloat) -> Void
    let adjust: (CGFloat) -> Void
    @State private var isHovering = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(DesignTokens.ColorSystem.hairline)
                .frame(height: 1)

            Capsule(style: .continuous)
                .fill(isHovering ? DesignTokens.ColorSystem.accentAction : DesignTokens.ColorSystem.hairline.opacity(0.6))
                .frame(width: 44, height: isHovering ? 4 : 3)
        }
        .frame(height: DeduplicateDetailPreviewLayout.resizeHandleHeight)
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    dragChanged(value.translation.height)
                }
                .onEnded { value in
                    dragEnded(value.translation.height)
                }
        )
        .onHover { isHovering = $0 }
        .help("Drag to resize the preview and duplicate thumbnails")
        .accessibilityLabel("Resize preview and duplicate thumbnails")
        .accessibilityHint("Drag up to make thumbnails larger, or down to make the preview larger")
        // Give the adjustable resize handle a concrete role so it isn't reported
        // as "Unknown role"; it stays operable via the adjustable action below.
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                adjust(24)
            case .decrement:
                adjust(-24)
            @unknown default:
                break
            }
        }
    }
}

private struct LargePreviewImage: View {
    let path: String
    @State private var image: NSImage?
    @State private var failed = false

    private var isVideo: Bool { MediaLibraryRules.isVideoFile(path: path) }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else if failed {
                // A video whose format QuickLook can't decode (some .mkv/.avi/
                // .wmv) shows a film placeholder rather than a misleading photo
                // icon, so the user understands why no frame is visible before
                // deciding to move the file to Trash.
                Image(systemName: isVideo ? "film" : "photo")
                    .font(.system(size: 56))
                    // Placeholder sits on the dark photo-preview fill, so it must
                    // stay light in both appearances (not the dark ink token).
                    .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
                    .accessibilityLabel(
                        isVideo
                            ? "Video preview unavailable for this format"
                            : "Preview unavailable"
                    )
            } else {
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: path) {
            image = nil
            failed = false
            let scale = NSScreen.main?.backingScaleFactor ?? 2.0
            let cgImage = await Self.loadPreviewCGImage(at: path, scale: scale, isVideo: isVideo)
            guard !Task.isCancelled else { return }
            guard let cgImage else {
                failed = true
                return
            }
            let pixelSize = CGSize(width: cgImage.width, height: cgImage.height)
            image = NSImage(cgImage: cgImage, size: pixelSize)
        }
    }

    private nonisolated static func loadPreviewCGImage(
        at path: String,
        scale: CGFloat,
        isVideo: Bool
    ) async -> CGImage? {
        let url = URL(fileURLWithPath: path)
        // Videos have no CGImageSource; render a QuickLook poster frame so the
        // user can visually confirm the clip before deleting it. QuickLook is
        // also a reliable fallback for any still format ImageIO can't open.
        if isVideo {
            return await ThumbnailRenderer.cgImage(
                for: url,
                size: CGSize(width: 1200, height: 1200),
                scale: scale
            )
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let maxPixelSize = Int(1200 * scale)
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
