#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI

/// A compact, quiet card that surfaces what Chronoframe is doing right now.
/// During a transfer this shows the current task title and a live
/// QuickLook thumbnail of the file currently being copied. When the engine
/// has not reported a path (between phases, idle, etc.) it falls back to a
/// status icon tinted by the workspace tone.
struct NowCopyingCard: View {
    let model: RunWorkspaceModel

    var body: some View {
        DarkroomPanel(variant: .inset) {
            HStack(alignment: .center, spacing: DesignTokens.Spacing.md) {
                NowCopyingThumbnail(
                    fileURL: model.context.currentFileURL,
                    fallbackSymbol: heroSymbol,
                    fallbackTone: model.heroState.tone.color
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Now")
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkMuted)

                    Text(model.context.currentTaskTitle)
                        .scaledFont(.body, weight: .medium)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .contentTransition(.identity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Spacer(minLength: DesignTokens.Spacing.sm)

                tonePill
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Now: \(model.context.currentTaskTitle)")
    }

    private var tonePill: some View {
        Text(model.heroState.badgeTitle)
            .scaledFont(.label)
            .foregroundStyle(model.heroState.tone.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(model.heroState.tone.color.opacity(0.12))
            )
    }

    private var heroSymbol: String {
        switch model.context.status {
        case .running: return "arrow.triangle.2.circlepath"
        case .finished: return "checkmark.circle.fill"
        case .dryRunFinished: return "eye"
        case .preflighting: return "clock.arrow.circlepath"
        case .cancelled: return "pause.circle"
        case .failed: return "exclamationmark.triangle"
        case .nothingToCopy, .nothingToReorganize: return "checkmark.seal"
        case .reverted: return "arrow.uturn.backward.circle.fill"
        case .revertEmpty: return "tray"
        case .reorganized: return "rectangle.3.offgrid.fill"
        case .idle: return "circle.dashed"
        }
    }
}

/// 44×44 live thumbnail tile. Renders QuickLook output for the active
/// source file when one is present; otherwise shows a tone-tinted status
/// glyph. Cross-fades between successive files using `Motion.instant`.
private struct NowCopyingThumbnail: View {
    let fileURL: URL?
    let fallbackSymbol: String
    let fallbackTone: Color

    @State private var image: NSImage?
    @State private var renderedPath: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DesignTokens.ColorSystem.imageStage)

            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: fallbackSymbol)
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(fallbackTone)
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(DesignTokens.ColorSystem.photoEdgeHighlight, lineWidth: 0.5)
        }
        .motion(Motion.instant, value: renderedPath)
        .onChange(of: fileURL?.path) { _ in
            loadThumbnail()
        }
        .onAppear { loadThumbnail() }
    }

    private func loadThumbnail() {
        guard let url = fileURL else {
            image = nil
            renderedPath = nil
            return
        }
        let path = url.path
        guard path != renderedPath else { return }
        renderedPath = path
        Task.detached(priority: .utility) {
            let cg = await ThumbnailRenderer.cgImage(
                for: url,
                size: CGSize(width: 88, height: 88),
                scale: 2.0
            )
            await MainActor.run {
                guard renderedPath == path else { return }
                if let cg {
                    image = NSImage(cgImage: cg, size: NSSize(width: 44, height: 44))
                } else {
                    image = nil
                }
            }
        }
    }
}
