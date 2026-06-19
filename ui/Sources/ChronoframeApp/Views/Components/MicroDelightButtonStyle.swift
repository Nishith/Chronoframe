import SwiftUI

struct ProminentMicroDelightButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var role: ButtonRole? = nil

    func makeBody(configuration: Configuration) -> some View {
        let backgroundColor = role == .destructive
            ? DesignTokens.ColorSystem.statusDanger
            : DesignTokens.ColorSystem.accentAction

        configuration.label
            .font(.body.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed 
                          ? backgroundColor.opacity(0.85) 
                          : backgroundColor)
            )
            .foregroundColor(.white)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .motion(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

struct BorderedMicroDelightButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(configuration.isPressed 
                          ? Color.primary.opacity(0.15) 
                          : Color.primary.opacity(0.05))
            )
            .foregroundColor(.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1.0)
            .motion(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == ProminentMicroDelightButtonStyle {
    static var prominentMicroDelight: ProminentMicroDelightButtonStyle {
        ProminentMicroDelightButtonStyle()
    }

    static func prominentMicroDelight(role: ButtonRole?) -> ProminentMicroDelightButtonStyle {
        ProminentMicroDelightButtonStyle(role: role)
    }
}

extension ButtonStyle where Self == BorderedMicroDelightButtonStyle {
    static var borderedMicroDelight: BorderedMicroDelightButtonStyle {
        BorderedMicroDelightButtonStyle()
    }
}
