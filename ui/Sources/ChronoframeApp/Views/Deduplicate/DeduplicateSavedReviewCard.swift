#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// Idle-screen card offering to bring back a review saved for the chosen folder.
struct DeduplicateSavedReviewCard: View {
    let snapshot: DeduplicateReviewSnapshot
    /// Starts a scan; the restore happens when the scan completes.
    let resume: () -> Void
    let discard: () -> Void

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: DesignTokens.ColorSystem.accentAction) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "rectangle.stack")
                        .foregroundStyle(DesignTokens.ColorSystem.accentAction)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(LocalizedStringKey(DeduplicateReviewCopy.savedTitle), bundle: .module)
                            .font(.subheadline.weight(.semibold))
                        Text(verbatim: DeduplicateReviewCopy.savedBody(snapshot))
                            .font(.caption)
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
                    Button(role: .destructive, action: discard) {
                        Text(LocalizedStringKey(DeduplicateReviewCopy.discardButtonTitle), bundle: .module)
                    }
                    .accessibilityIdentifier(AccessibilityIdentifiers.dedupeSavedReviewDiscard)
                    Button(action: resume) {
                        Text(LocalizedStringKey(DeduplicateReviewCopy.resumeButtonTitle), bundle: .module)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(AccessibilityIdentifiers.dedupeSavedReviewResume)
                }
            }
        }
    }
}
