import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit

/// An interactive, scrubbable chronological histogram of photos and videos.
/// Supports click-and-drag scrubbing across date buckets, triggering haptic
/// feedback when crossing boundary segments, and displays highlighted states
/// for the selected timeline bucket.
struct InteractiveTimelineView: View {
    let buckets: [DateHistogramBucket]
    let barFills: [Double]
    @Binding var selectedBucketKey: String?
    @Binding var isScrubbing: Bool
    var customAccessibilityValue: String? = nil

    private let chartHeight: CGFloat = 136
    private let minBarHeight: CGFloat = 3

    @State private var hoveredBucketKey: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let maxCount = max(buckets.map(\.plannedCount).max() ?? 1, 1)

        GeometryReader { geo in
            let spacing: CGFloat = max(1, min(4, geo.size.width / CGFloat(buckets.count) * 0.15))
            let totalSpacing = spacing * CGFloat(max(0, buckets.count - 1))
            let barWidth = max(2, (geo.size.width - totalSpacing) / CGFloat(buckets.count))

            ZStack(alignment: .bottomLeading) {
                // Background gesture target covering the entire chart
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                isScrubbing = true
                                let x = value.location.x
                                let index = Int(x / (barWidth + spacing))
                                let clampedIndex = max(0, min(buckets.count - 1, index))
                                let bucket = buckets[clampedIndex]
                                if selectedBucketKey != bucket.key {
                                    selectedBucketKey = bucket.key
                                    triggerHapticFeedback()
                                }
                            }
                            .onEnded { _ in
                                isScrubbing = false
                            }
                    )

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(buckets.enumerated()), id: \.element.id) { index, bucket in
                        let isSelected = selectedBucketKey == bucket.key
                        let selectedKeyIsValid = selectedBucketKey != nil && buckets.contains { $0.key == selectedBucketKey }
                        let anySelected = selectedKeyIsValid
                        let dimOpacity = anySelected && !isSelected ? 0.35 : 1.0

                        bar(
                            for: bucket,
                            fill: barFills[index],
                            maxCount: maxCount,
                            width: barWidth,
                            availableHeight: geo.size.height,
                            isSelected: isSelected
                        )
                        .opacity(dimOpacity)
                        .motion(Motion.mechanical, value: dimOpacity)
                    }
                }
                .allowsHitTesting(false) // Let the background gesture capture drags cleanly

                yearMarkers(width: geo.size.width)
            }
        }
        .frame(height: chartHeight)
        .padding(DesignTokens.Spacing.md)
        .background(DesignTokens.ColorSystem.imageStage, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityIdentifier("InteractiveTimeline")
        .accessibilityLabel("Scrubbable timeline")
        .accessibilityValue(customAccessibilityValue ?? accessibilityValue)
        .accessibilityAdjustableAction { direction in
            guard !buckets.isEmpty else { return }
            let currentIndex = buckets.firstIndex { $0.key == selectedBucketKey }
            switch direction {
            case .increment:
                let nextIndex = min(buckets.count - 1, (currentIndex ?? -1) + 1)
                selectedBucketKey = buckets[nextIndex].key
                triggerHapticFeedback()
            case .decrement:
                if let current = currentIndex {
                    let prevIndex = max(0, current - 1)
                    selectedBucketKey = buckets[prevIndex].key
                    triggerHapticFeedback()
                } else {
                    selectedBucketKey = buckets.last?.key
                    triggerHapticFeedback()
                }
            @unknown default:
                break
            }
        }
        .onChange(of: buckets) { _, newBuckets in
            if let selected = selectedBucketKey, !newBuckets.contains(where: { $0.key == selected }) {
                selectedBucketKey = nil
            }
        }
    }

    private func bar(
        for bucket: DateHistogramBucket,
        fill: Double,
        maxCount: Int,
        width: CGFloat,
        availableHeight: CGFloat,
        isSelected: Bool
    ) -> some View {
        let ratio = Double(bucket.plannedCount) / Double(maxCount)
        let height = max(minBarHeight, CGFloat(ratio) * availableHeight)
        let cornerRadius = min(width, height) / 2
        let track = seasonalTint(for: bucket.key)

        return ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(isSelected ? DesignTokens.ColorSystem.accentWaypoint.opacity(0.24) : track)

            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(fillColor(for: fill, isSelected: isSelected))
                .frame(height: max(0, height * CGFloat(isSelected ? 1.0 : fill)))
                .motion(reduceMotion ? Motion.mechanical : Motion.filmic, value: fill)
        }
        .frame(width: width, height: height)
    }

    private func fillColor(for fill: Double, isSelected: Bool) -> Color {
        if isSelected {
            return DesignTokens.ColorSystem.accentWaypoint
        }
        if fill >= 1.0 {
            return DesignTokens.ColorSystem.statusSuccess
        }
        if fill > 0 {
            return DesignTokens.ColorSystem.accentWaypoint
        }
        return .clear
    }

    private func triggerHapticFeedback() {
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .default)
    }

    private func seasonalTint(for key: String) -> Color {
        guard key.count >= 7, key != "Unknown" else {
            return DesignTokens.ColorSystem.inkMuted.opacity(0.18)
        }
        let monthPart = key.dropFirst(5).prefix(2)
        guard let month = Int(monthPart), (1...12).contains(month) else {
            return DesignTokens.ColorSystem.inkMuted.opacity(0.18)
        }
        let warmth = (cos(Double(month - 7) / 6.0 * .pi) + 1) / 2
        let hue = (220 - warmth * 185) / 360
        return Color(hue: hue, saturation: 0.32, brightness: 0.66, opacity: 0.32)
    }

    private func yearMarkers(width: CGFloat) -> some View {
        let markers = yearMarkerEntries
        return ZStack(alignment: .topLeading) {
            ForEach(markers, id: \.index) { marker in
                VStack(alignment: .leading, spacing: 4) {
                    Rectangle()
                        .fill(Color.white.opacity(0.14))
                        .frame(width: 0.5, height: chartHeight - 20)
                    Text(marker.year)
                        .scaledFont(.label, weight: .medium)
                        .monospacedDigit()
                        .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
                }
                .offset(x: markerOffset(for: marker.index, width: width), y: 0)
            }
        }
        .allowsHitTesting(false)
    }

    private var yearMarkerEntries: [(index: Int, year: String)] {
        var lastYear: String?
        return buckets.enumerated().compactMap { index, bucket in
            guard bucket.key.count >= 4, bucket.key != "Unknown" else { return nil }
            let year = String(bucket.key.prefix(4))
            guard year != lastYear else { return nil }
            lastYear = year
            return (index, year)
        }
    }

    private func markerOffset(for index: Int, width: CGFloat) -> CGFloat {
        guard buckets.count > 1 else { return 0 }
        let ratio = CGFloat(index) / CGFloat(max(buckets.count - 1, 1))
        return min(max(0, ratio * width), max(0, width - 32))
    }

    private var accessibilityValue: String {
        if let key = selectedBucketKey, let matchingBucket = buckets.first(where: { $0.key == key }) {
            let count = matchingBucket.plannedCount
            return "Selected month: \(key), \(count) files planned. Timeline contains \(buckets.count) months."
        }
        let total = buckets.reduce(0) { $0 + $1.plannedCount }
        return "Timeline containing \(total) files across \(buckets.count) months. Unselected."
    }
}
