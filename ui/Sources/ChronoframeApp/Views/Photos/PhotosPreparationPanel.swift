#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

/// Progress for the read-only export that stages Photos originals before an
/// import. Stop keeps everything already prepared.
struct PhotosPreparationPanel: View {
    let progress: PhotosPreparationProgress
    let onStop: () -> Void

    static let stopButtonIdentifier = AccessibilityIdentifiers.photosImportStopButton

    var showsCloudWait: Bool { progress.isWaitingForCloud }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(
                value: Double(min(progress.completed + progress.failed, max(progress.total, 1))),
                total: Double(max(progress.total, 1))
            )
            .accessibilityLabel(Text(verbatim: PhotosPreparationText.progressLine(progress)))
            Text(verbatim: PhotosPreparationText.progressLine(progress))
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            if let label = progress.currentAssetLabel {
                Text(label)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            if showsCloudWait {
                Text(LocalizedStringKey(PhotosPreparationText.waitingForCloud), bundle: .module)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
            if progress.failed > 0 {
                Text(verbatim: PhotosPreparationText.failuresLine(progress.failed))
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(action: onStop) {
                Text("Stop", bundle: .module)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier(Self.stopButtonIdentifier)
        }
        .frame(maxWidth: 360, alignment: .leading)
    }
}
