#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI
import TipKit

/// The emotional centerpiece of the Run view: a chronological histogram of
/// the photos and videos found in the source. Each bar is one year-month;
/// height scales with the file count for that month.
///
/// Supports visual scrubbing and selection to inspect files planned for each month.
struct RunTimelineView: View {
    let model: RunWorkspaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedBucketKey: String? = nil
    @State private var isScrubbing = false

    private let chartHeight: CGFloat = 136
    private let minBarHeight: CGFloat = 3

    var body: some View {
        DarkroomPanel(variant: .panel) {
            VStack(alignment: .leading, spacing: DesignTokens.Spacing.md) {
                header

                if buckets.isEmpty {
                    emptyState
                } else {
                    InteractiveTimelineView(
                        buckets: buckets,
                        barFills: barFills,
                        selectedBucketKey: $selectedBucketKey,
                        isScrubbing: $isScrubbing
                    )

                    if let selectedBucketKey, let bucket = buckets.first(where: { $0.key == selectedBucketKey }) {
                        selectionDrawer(for: bucket)
                            .transition(.asymmetric(
                                insertion: .opacity.combined(with: .move(edge: .top)),
                                removal: .opacity
                            ))
                    }
                }

                Text(subtitle)
                    .scaledFont(.body)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Timeline")
                .scaledFont(.cardTitle)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

            Spacer()

            Text(rangeCaption)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.captionText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }

    // MARK: - Selection Drawer

    private func selectionDrawer(for bucket: DateHistogramBucket) -> some View {
        VStack(alignment: .leading, spacing: DesignTokens.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(formatMonthYear(bucket.key))
                        .scaledFont(.subtitle, weight: .bold)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    Text("\(bucket.plannedCount.formatted(.number)) planned files")
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.captionText)
                }

                Spacer()

                Button(action: {
                    Motion.withMotion(Motion.mechanical, reduceMotion: reduceMotion) {
                        selectedBucketKey = nil
                    }
                }) {
                    Text("Clear Selection")
                        .scaledFont(.label)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("ClearTimelineSelectionButton")
            }

            if !bucket.samplePaths.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(bucket.samplePaths, id: \.self) { path in
                            TimelinePeekThumbnail(path: path)
                                .help(URL(fileURLWithPath: path).lastPathComponent)
                        }
                    }
                }
                .frame(height: 56)
            }
        }
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.ColorSystem.imageStage.opacity(0.4), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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

    // MARK: - Empty state

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.ColorSystem.imageStage)

            GhostTimelineBars()
                .padding(DesignTokens.Spacing.md)

            Text(emptyStateMessage)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DesignTokens.Spacing.md)
                .padding(.vertical, 6)
                .background(
                    Capsule().fill(DesignTokens.ColorSystem.imageStage.opacity(0.65))
                )
        }
        .frame(height: chartHeight)
    }

    private var emptyStateMessage: String {
        switch model.context.status {
        case .idle:
            return "Run a preview to see the source timeline."
        case .preflighting, .running:
            return "Scanning source — bars will appear as files are dated."
        default:
            return "No dated files found in this source."
        }
    }

    // MARK: - Data mapping

    private var buckets: [DateHistogramBucket] {
        model.context.metrics.dateHistogram
    }

    /// Distributes `copiedCount` across buckets left-to-right. Each bucket gets
    /// a fill ratio in [0, 1].
    private var barFills: [Double] {
        let copied = model.context.metrics.copiedCount
        var remaining = copied
        return buckets.map { bucket in
            guard bucket.plannedCount > 0 else { return 0 }
            let used = min(remaining, bucket.plannedCount)
            remaining -= used
            let ratio = Double(used) / Double(bucket.plannedCount)
            if model.context.status == .finished || model.context.status == .nothingToCopy {
                return 1.0
            }
            return ratio
        }
    }

    private var rangeCaption: String {
        let dated = buckets.filter { $0.key != "Unknown" }
        guard let first = dated.first, let last = dated.last else {
            let total = buckets.reduce(0) { $0 + $1.plannedCount }
            return total > 0 ? "\(total.formatted()) files" : "—"
        }
        let firstYear = String(first.key.prefix(4))
        let lastYear = String(last.key.prefix(4))
        let total = buckets.reduce(0) { $0 + $1.plannedCount }
        if firstYear == lastYear {
            return "\(firstYear) · \(total.formatted()) files"
        }
        return "\(firstYear)–\(lastYear) · \(total.formatted()) files"
    }

    private var subtitle: String {
        switch model.context.status {
        case .running:
            if model.context.currentPhase == .copy {
                return "Each bar fills as those frames find their place."
            }
            return "Reading dates from the source."
        case .dryRunFinished:
            return "Here's the shape of your source — every bar a month of frames waiting to land."
        case .finished:
            return "Every frame is home."
        case .nothingToCopy:
            return "The destination already has everything it needs."
        case .failed:
            return "The run stopped early. Review issues to continue."
        case .cancelled:
            return "Run cancelled. Start again when ready."
        case .preflighting:
            return "Preparing the run."
        case .idle:
            return "Run a preview to see the timeline of your source."
        case .reverted:
            return "Files restored to their original state."
        case .revertEmpty:
            return "This receipt had no transfers to undo."
        case .reorganized:
            return "Layout updated in place."
        case .nothingToReorganize:
            return "The destination already matches this layout."
        }
    }

    private var accessibilityValue: String {
        let total = buckets.reduce(0) { $0 + $1.plannedCount }
        let copied = model.context.metrics.copiedCount
        if let selected = selectedBucketKey {
            return "Selected month: \(selected). \(copied) of \(total) frames placed across \(buckets.count) months."
        }
        return "\(copied) of \(total) frames placed across \(buckets.count) months. Unselected."
    }
}

/// Placeholder row of low-opacity bars for the timeline empty state.
private struct GhostTimelineBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let heights: [CGFloat] = {
        var rng = SeededTimelineRNG(seed: 0x4368726F6E6F31)
        return (0..<36).map { _ in CGFloat.random(in: 0.18...0.95, using: &rng) }
    }()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let pulse = (sin(t * .pi / 2) + 1) / 2 // 4-second cycle, 0..1
            let opacity = 0.10 + pulse * 0.06

            GeometryReader { geo in
                let spacing: CGFloat = 3
                let count = Self.heights.count
                let barWidth = (geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        let h = Self.heights[i]
                        let height = max(2, h * geo.size.height)
                        RoundedRectangle(cornerRadius: min(barWidth, height) / 2, style: .continuous)
                            .fill(Color.white.opacity(opacity))
                            .frame(width: barWidth, height: height)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Tiny splitmix-style RNG so the ghost-bar silhouette is stable across redraws.
private struct SeededTimelineRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z &>> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z &>> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z &>> 31)
    }
}

/// A slim 4pt capsule replacing the old five-dot phase timeline.
struct RunPhaseStrip: View {
    let model: RunWorkspaceModel

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let phases = model.phaseEntries
            let segmentWidth = width / CGFloat(max(phases.count, 1))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DesignTokens.ColorSystem.hairline.opacity(0.6))

                HStack(spacing: 0) {
                    ForEach(Array(phases.enumerated()), id: \.element.id) { _, entry in
                        Capsule()
                            .fill(color(for: entry.state))
                            .frame(width: segmentWidth)
                            .motion(Motion.mechanical, value: entry.state)
                    }
                }
                .mask(Capsule())

                if let currentIndex {
                    Circle()
                        .fill(DesignTokens.ColorSystem.accentWaypoint)
                        .frame(width: 8, height: 8)
                        .shadow(color: DesignTokens.ColorSystem.accentWaypoint.opacity(0.42), radius: 5)
                        .offset(x: min(max(0, CGFloat(currentIndex) * segmentWidth + segmentWidth - 4), max(0, width - 8)))
                        .motion(Motion.mechanical, value: currentIndex)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Phase progress")
            .accessibilityValue(phasesAccessibilityValue)
            .accessibilityAddTraits(.isImage)
        }
        .frame(height: 4)
        .help(model.phaseStripTooltip)
        .popoverTip(TimelineScrubbingTip(), arrowEdge: .top)
    }

    private func color(for state: RunPhaseTimelineEntry.State) -> Color {
        switch state {
        case .complete:
            return DesignTokens.ColorSystem.statusSuccess
        case .current:
            return DesignTokens.ColorSystem.accentWaypoint
        case .pending:
            return Color.clear
        }
    }

    private var phasesAccessibilityValue: String {
        let completed = model.phaseEntries.filter { $0.state == .complete }.count
        let total = model.phaseEntries.count
        return "\(completed) of \(total) phases complete"
    }

    private var currentIndex: Int? {
        model.phaseEntries.firstIndex { $0.state == .current }
    }
}

struct TimelinePeekThumbnail: View {
    let path: String
    @State private var image: NSImage?

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(DesignTokens.ColorSystem.imageStage)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(DesignTokens.ColorSystem.photoEdgeHighlight, lineWidth: 0.5)
        }
        .task(id: path) {
            let url = URL(fileURLWithPath: path)
            let cg = await ThumbnailRenderer.cgImage(
                for: url,
                size: CGSize(width: 112, height: 112),
                scale: 2.0
            )
            guard !Task.isCancelled, let cg = cg else { return }
            image = NSImage(cgImage: cg, size: NSSize(width: 56, height: 56))
        }
    }
}
