import SwiftUI

/// One-card first-run onboarding. Used by Setup and Deduplicate; never a
/// modal, never a tutorial. Dismissal is owned by the caller via the
/// `onDismiss` closure (typically backed by an `@AppStorage` flag).
struct OnboardingCard: View {
    let icon: String
    let title: String
    let subtitle: String
    let bullets: [String]
    let accessibilitySummary: String
    let onDismiss: () -> Void

    init(
        icon: String = "hand.wave",
        title: String,
        subtitle: String,
        bullets: [String] = [],
        accessibilitySummary: String? = nil,
        onDismiss: @escaping () -> Void
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.bullets = bullets
        self.accessibilitySummary = accessibilitySummary ?? title
        self.onDismiss = onDismiss
    }

    var body: some View {
        DarkroomPanel(variant: .panel) {
            HStack(alignment: .top, spacing: DesignTokens.Spacing.md) {
                Image(systemName: icon)
                    .font(.system(size: 20))
                    .foregroundStyle(DesignTokens.ColorSystem.accentWaypoint)
                    .frame(width: 28, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(DesignTokens.Typography.cardTitle)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                    Text(subtitle)
                        .font(DesignTokens.Typography.subtitle)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !bullets.isEmpty {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(bullets, id: \.self) { bullet in
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    Text("•")
                                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                                    Text(bullet)
                                        .font(DesignTokens.Typography.subtitle)
                                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 4)
                    }
                }

                Spacer(minLength: DesignTokens.Spacing.md)

                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss onboarding")
                .accessibilityHint("Hides this welcome card permanently")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilitySummary)
    }
}
