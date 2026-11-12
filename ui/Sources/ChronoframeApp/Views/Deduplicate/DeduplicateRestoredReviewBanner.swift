#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// Shown above the cluster list after a scan restored an earlier review.
struct DeduplicateRestoredReviewBanner: View {
    let restoration: DeduplicateReviewRestoration
    let onDismiss: () -> Void

    var body: some View {
        DarkroomPanel(variant: .inset) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(DeduplicateReviewCopy.restoredTitle), bundle: .module)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        Text(verbatim: DeduplicateReviewCopy.restoredBody(restoration))
                            .font(.caption)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if restoration.settingsChanged {
                            Text(LocalizedStringKey(DeduplicateReviewCopy.settingsChanged), bundle: .module)
                                .font(.caption)
                                .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 8)
                    Button(action: onDismiss) {
                        Label { Text("Dismiss", bundle: .module) } icon: { Image(systemName: "xmark") }
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier(AccessibilityIdentifiers.dedupeRestoredBannerDismiss)
                }
                .padding(.horizontal, DesignTokens.Layout.cardPadding)
                .padding(.vertical, 10)
                Divider()
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.dedupeRestoredBanner)
    }
}
