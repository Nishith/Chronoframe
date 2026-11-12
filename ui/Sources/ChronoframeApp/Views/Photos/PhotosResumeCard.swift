#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

/// Offer to continue an import whose preparation was stopped, paused for space
/// or interrupted. The prepared files were kept; nothing in Photos changed.
struct PhotosResumeCard: View {
    let resumable: PhotosResumableImport
    let onResume: () -> Void
    let onDiscard: () -> Void

    static let resumeButtonIdentifier = AccessibilityIdentifiers.photosImportResumeButton
    static let discardButtonIdentifier = AccessibilityIdentifiers.photosImportDiscardButton

    var isResumeDisabled: Bool { !resumable.destinationMatches }
    var showsDestinationMismatch: Bool { !resumable.destinationMatches }

    var body: some View {
        DarkroomPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text("An import was interrupted.", bundle: .module)
                    .scaledFont(.cardTitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                Text(verbatim: PhotosPreparationText.resumeBody(resumable))
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsDestinationMismatch {
                    Text(LocalizedStringKey(PhotosPreparationText.destinationMismatch), bundle: .module)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: DesignTokens.Layout.inlineSpacing) {
                    Button(action: onResume) {
                        Text("Resume Import", bundle: .module)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isResumeDisabled)
                    .accessibilityIdentifier(Self.resumeButtonIdentifier)
                    Button(action: onDiscard) {
                        Text("Discard", bundle: .module)
                    }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier(Self.discardButtonIdentifier)
                }
            }
        }
    }
}
