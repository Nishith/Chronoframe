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
    @State private var lastAnnouncedProgressBucket: Int = -1

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
        .accessibilityLabel("Now: \(model.context.currentTaskTitle). Progress: \(model.progressAccessibilityValue)")
        .onChange(of: model.context.progress) { newProgress in
            announceProgressThrottled(progress: newProgress)
        }
    }

    private func announceProgressThrottled(progress: Double) {
        guard model.context.status == .running else {
            lastAnnouncedProgressBucket = -1
            return
        }
        if progress == 0.0 {
            lastAnnouncedProgressBucket = 0
            return
        }
        let bucket = Int(progress * 10) // 0 to 10
        if bucket > lastAnnouncedProgressBucket {
            lastAnnouncedProgressBucket = bucket
            if bucket > 0 && bucket <= 10 {
                let message = "\(bucket * 10) percent completed"
                #if canImport(AppKit)
                NSAccessibility.post(
                    element: NSApp as Any,
                    notification: .announcementRequested,
                    userInfo: [
                        .announcement: message,
                        .priority: NSAccessibilityPriorityLevel.low.rawValue
                    ]
                )
                #endif
            }
        }
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

// MARK: - Waypoint Runway (ADA visual progress improvements)

struct WaypointRunway: View {
    let currentFileURL: URL?

    @State private var history: [URL] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Copy Queue")
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                .tracking(0.6)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(history, id: \.self) { url in
                        RunwayThumbnail(url: url, isCurrent: url == currentFileURL)
                            .transition(.asymmetric(
                                insertion: .move(edge: .trailing).combined(with: .opacity),
                                removal: .opacity
                            ))
                    }

                    if history.isEmpty {
                        Text("Queue empty")
                            .font(.caption)
                            .foregroundStyle(DesignTokens.ColorSystem.inkMuted)
                            .frame(height: 52)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.ColorSystem.canvas)
        .cornerRadius(DesignTokens.Corner.innerCard)
        .overlay(
            RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous)
                .strokeBorder(DesignTokens.ColorSystem.hairline, lineWidth: 0.5)
        )
        .onChange(of: currentFileURL) { newURL in
            if let newURL {
                Motion.withMotion(.spring(response: 0.38, dampingFraction: 0.72), reduceMotion: reduceMotion) {
                    if !history.contains(newURL) {
                        history.append(newURL)
                        if history.count > 10 {
                            history.removeFirst()
                        }
                    }
                }
            }
        }
    }
}

private struct RunwayThumbnail: View {
    let url: URL
    let isCurrent: Bool

    @State private var image: NSImage?
    @State private var showWaypoint = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(DesignTokens.ColorSystem.imageStage)

                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 52, height: 52)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isCurrent ? DesignTokens.ColorSystem.accentAction : DesignTokens.ColorSystem.photoEdgeHighlight, lineWidth: isCurrent ? 2.0 : 0.5)
            }

            if !isCurrent || showWaypoint {
                Circle()
                    .fill(DesignTokens.ColorSystem.accentWaypoint)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
                    .offset(x: 3, y: 3)
                    .transition(.scale)
            }
        }
        .task(id: url) {
            if let cg = await ThumbnailRenderer.cgImage(for: url, size: CGSize(width: 104, height: 104), scale: 2.0) {
                image = NSImage(cgImage: cg, size: NSSize(width: 52, height: 52))
            }
            if isCurrent {
                // Pulse waypoint checkmark after copy resolves
                try? await Task.sleep(nanoseconds: 800_000_000)
                Motion.withMotion(.spring(response: 0.35, dampingFraction: 0.6), reduceMotion: reduceMotion) {
                    showWaypoint = true
                }
            }
        }
    }
}
