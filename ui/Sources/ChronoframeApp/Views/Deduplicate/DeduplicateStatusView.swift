#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

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
    @ViewBuilder let primary: () -> Primary
    @ViewBuilder let secondary: () -> Secondary

    init(
        style: Style,
        title: String,
        message: String? = nil,
        warning: String? = nil,
        detail: String? = nil,
        @ViewBuilder primary: @escaping () -> Primary,
        @ViewBuilder secondary: @escaping () -> Secondary
    ) {
        self.style = style
        self.title = title
        self.message = message
        self.warning = warning
        self.detail = detail
        self.primary = primary
        self.secondary = secondary
    }

    var body: some View {
        VStack(spacing: DesignTokens.Spacing.md) {
            icon

            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
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
                    .font(.caption)
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
    }

    @ViewBuilder
    private var icon: some View {
        switch style {
        case .progress:
            ProgressView()
                .controlSize(.large)
        case .success, .restored, .warning:
            if let name = style.systemImage {
                Image(systemName: name)
                    .font(.system(size: 48))
                    .foregroundStyle(style.tint)
            }
        }
    }
}

extension DeduplicateStatusView where Secondary == EmptyView {
    init(
        style: Style,
        title: String,
        message: String? = nil,
        warning: String? = nil,
        detail: String? = nil,
        @ViewBuilder primary: @escaping () -> Primary
    ) {
        self.init(
            style: style,
            title: title,
            message: message,
            warning: warning,
            detail: detail,
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
        detail: String? = nil
    ) {
        self.init(
            style: style,
            title: title,
            message: message,
            warning: warning,
            detail: detail,
            primary: { EmptyView() },
            secondary: { EmptyView() }
        )
    }
}
