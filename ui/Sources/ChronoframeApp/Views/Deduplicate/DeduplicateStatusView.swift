#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

struct DeduplicateStatusProgress: Equatable {
    var completed: Int
    var total: Int
    var unit: String

    init(completed: Int, total: Int, unit: String) {
        self.completed = max(0, completed)
        self.total = max(0, total)
        self.unit = unit
    }

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(1, Double(completed) / Double(total))
    }

    var accessibilityValue: String {
        guard total > 0 else { return "In progress" }
        let clampedCompleted = min(completed, total)
        return "\(clampedCompleted) of \(total) \(unit)"
    }
}

/// Shared full-screen status surface used by every non-review state in
/// Deduplicate (scanning, empty, completed, reverting, reverted, failed).
/// Consolidates icon + tint pairings, layout spacing, and copy
/// pluralisation so the eight near-identical states cannot drift again.
struct DeduplicateStatusView<Primary: View, Secondary: View>: View {
    enum Style {
        case progress
        case success
        case restored
        case warning

        var systemImage: String? {
            switch self {
            case .progress: return nil
            case .success: return "checkmark.circle.fill"
            case .restored: return "arrow.uturn.backward.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            }
        }

        var tint: SwiftUI.Color {
            switch self {
            case .progress: return DesignTokens.ColorSystem.accentAction
            case .success, .restored: return DesignTokens.ColorSystem.statusSuccess
            case .warning: return DesignTokens.ColorSystem.statusDanger
            }
        }
    }

    let style: Style
    let title: String
    let message: String?
    let warning: String?
    let detail: String?
    let progress: DeduplicateStatusProgress?
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    init(
        style: Style,
        title: String,
        message: String? = nil,
        warning: String? = nil,
        detail: String? = nil,
        progress: DeduplicateStatusProgress? = nil,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.style = style
        self.title = title
        self.message = message
        self.warning = warning
        self.detail = detail
        self.progress = progress
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            icon

            VStack(spacing: 6) {
                Text(title)
                    .scaledFont(.body, weight: .semibold)
                    .multilineTextAlignment(.center)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .scaledFont(.label)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            if let message, !message.isEmpty {
                Text(message)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal)
            }

            if let warning, !warning.isEmpty {
                Text(warning)
                    .scaledFont(.label)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DesignTokens.ColorSystem.statusDanger)
                    .padding(.horizontal)
            }

            HStack(spacing: DesignTokens.Spacing.sm) {
                secondary()
                primary()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(title)
        .accessibilityValue(statusAccessibilityValue)
    }

    @ViewBuilder
    private var icon: some View {
        switch style {
        case .progress:
            if let fraction = progress?.fraction {
                ProgressView(value: fraction)
                    .controlSize(.large)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(progress?.accessibilityValue ?? "In progress")
            } else {
                ProgressView()
                    .controlSize(.large)
                    .accessibilityLabel("Progress")
                    .accessibilityValue(progress?.accessibilityValue ?? detail ?? "In progress")
            }
        case .success, .restored, .warning:
            if let name = style.systemImage {
                ZStack {
                    Circle()
                        .fill(style.tint.opacity(0.12))
                        .frame(width: 76, height: 76)
                    Circle()
                        .strokeBorder(style.tint.opacity(0.22), lineWidth: 0.5)
                        .frame(width: 76, height: 76)
                    Image(systemName: name)
                        .scaledFont(.metric)
                        .foregroundStyle(style.tint)
                    if showsWaypointDot {
                        Circle()
                            .fill(DesignTokens.ColorSystem.accentWaypoint)
                            .frame(width: 7, height: 7)
                            .offset(x: 24, y: 24)
                    }
                }
            }
        }
    }

    private var showsWaypointDot: Bool {
        switch style {
        case .success:
            return true
        case .progress, .restored, .warning:
            return false
        }
    }

    private var statusAccessibilityValue: String {
        [
            detail,
            message,
            warning,
        ]
        .compactMap { $0?.isEmpty == false ? $0 : nil }
        .joined(separator: ". ")
    }
}

extension DeduplicateStatusView where Secondary == EmptyView {
    init(
        style: Style,
        title: String,
        message: String? = nil,
        warning: String? = nil,
        detail: String? = nil,
        progress: DeduplicateStatusProgress? = nil,
        @ViewBuilder primary: @escaping () -> Primary
    ) {
        self.init(
            style: style,
            title: title,
            message: message,
            warning: warning,
            detail: detail,
            progress: progress,
            primary: primary,
            secondary: { EmptyView() }
        )
    }
}

extension DeduplicateStatusView where Primary == EmptyView, Secondary == EmptyView {
    init(
        style: Style,
        title: String,
        message: String? = nil,
        warning: String? = nil,
        detail: String? = nil,
        progress: DeduplicateStatusProgress? = nil
    ) {
        self.init(
            style: style,
            title: title,
            message: message,
            warning: warning,
            detail: detail,
            progress: progress,
            primary: { EmptyView() },
            secondary: { EmptyView() }
        )
    }
}
