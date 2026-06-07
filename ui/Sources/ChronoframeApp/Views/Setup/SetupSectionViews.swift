import SwiftUI
#if canImport(AppKit)
import AppKit
#endif
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import UniformTypeIdentifiers

#if canImport(AppKit)
private struct SetupFolderChooserButton: NSViewRepresentable {
    let title: String
    let accessibilityIdentifier: String
    let action: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.performAction))
        button.bezelStyle = .rounded
        button.controlSize = .regular
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.action = action
        button.title = title
        button.identifier = NSUserInterfaceItemIdentifier(accessibilityIdentifier)
        button.setAccessibilityIdentifier(accessibilityIdentifier)
    }

    final class Coordinator: NSObject {
        var action: () -> Void

        init(action: @escaping () -> Void) {
            self.action = action
        }

        @objc func performAction() {
            action()
        }
    }
}
#endif

struct SetupHeroSection: View {
    let model: SetupScreenModel
    let scrollToSource: () -> Void
    let scrollToDestination: () -> Void

    private var heroSystemImage: String {
        switch model.heroTone {
        case .ready: return "checkmark.circle.fill"
        case .warning: return "folder.badge.plus"
        default: return "photo.on.rectangle.angled"
        }
    }

    private var useBrandMark: Bool {
        model.heroTone == .idle || model.heroTone == .ready
    }

    var body: some View {
        DetailHeroCard(
            title: "Setup",
            message: "",
            badgeTitle: model.heroBadgeTitle,
            badgeSystemImage: model.heroBadgeSymbol,
            tint: model.heroTone.color,
            systemImage: heroSystemImage,
            usesBrandMark: useBrandMark
        ) {
            // One orientation row and one next-step line. The steps below
            // carry their own state pills, and the single prominent action
            // lives at the end of the steps it depends on (the Start
            // section) — the hero orients, it does not act.
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Privacy")
                        .scaledFont(.body)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    Spacer()
                    LocalSafetyIndicator(
                        sourcePath: model.context.sourcePath,
                        destinationPath: model.context.destinationPath,
                        deduplicatePath: model.context.deduplicateDestinationPath
                    )
                }

                SummaryLine(
                    title: "Next",
                    value: model.nextStepSummary,
                    valueColor: model.heroTone.color,
                    onTap: nextStepTap
                )
            }
        } actions: {
            EmptyView()
        }
    }

    private var nextStepTap: (() -> Void)? {
        switch model.primaryAction {
        case .chooseSource:
            return scrollToSource
        case .chooseDestination:
            return scrollToDestination
        case .preview:
            return nil
        }
    }
}

struct SetupContactSheetSection: View {
    let sourcePath: String

    var body: some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                SectionHeading(
                    title: "Source Contact Sheet",
                    message: sourcePath.isEmpty
                        ? "A contact sheet of the first frames will appear here once you choose a source."
                        : "A quick visual read of the frames Chronoframe will organize."
                )

                ContactSheetView(sourcePath: sourcePath)
            }
        }
    }
}

struct SetupSavedSetupSection: View {
    let model: SetupScreenModel
    @ObservedObject var setupStore: SetupStore
    let refreshProfiles: () -> Void
    let clearSelectedProfile: () -> Void
    let openProfiles: () -> Void
    let onProfileSelection: (String) -> Void

    var body: some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(
                        eyebrow: "Saved Setup",
                        title: "Profiles",
                        message: "Use a saved source and destination pair."
                    )

                    Spacer(minLength: 12)

                    MeridianStatusBadge(
                        title: model.savedSetupBadgeTitle,
                        systemImage: model.savedSetupBadgeSymbol,
                        tint: model.savedSetupTone.color
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        profilePickerSection
                        Spacer(minLength: 12)
                        profileActions
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        profilePickerSection
                        profileActions
                    }
                }

                if setupStore.usingProfile, let profile = setupStore.activeProfile {
                    MeridianSurfaceCard(style: .inner, tint: DesignTokens.Color.sky) {
                        VStack(alignment: .leading, spacing: 12) {
                            SummaryLine(title: "Selected", value: profile.name)
                            SummaryLine(title: "Source", value: profile.sourcePath)
                            SummaryLine(title: "Destination", value: profile.destinationPath)
                        }
                    }
                }
            }
        }
    }

    private var profilePickerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selected Profile")
                .font(.subheadline.weight(.semibold))

            Picker(
                "Profile",
                selection: Binding(
                    get: { setupStore.selectedProfileName },
                    set: { selection in
                        onProfileSelection(selection)
                    }
                )
            ) {
                Text("Manual Paths").tag("")
                ForEach(setupStore.profiles) { profile in
                    Text(profile.name).tag(profile.name)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .accessibilityIdentifier(AccessibilityIdentifiers.profilePicker)
            .accessibilityLabel("Profile")
        }
    }

    private var profileActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                Button("Refresh Profiles", action: refreshProfiles)
                Button("Manage Profiles", action: openProfiles)

                if setupStore.usingProfile {
                    Button("Clear Selection", action: clearSelectedProfile)
                }
            }

            Menu("Profile Actions") {
                Button("Refresh Profiles", action: refreshProfiles)
                Button("Manage Profiles", action: openProfiles)

                if setupStore.usingProfile {
                    Button("Clear Selection", action: clearSelectedProfile)
                }
            }
        }
    }
}

struct SetupSourceStepSection: View {
    let model: SetupScreenModel
    let dropZone: SetupDropZone
    let chooseSource: () -> Void
    let selectSource: (URL) -> Void

    @State private var isTargeted = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sourceIsReady: Bool {
        if case .ready = model.sourceStepState { return true }
        return false
    }

    var body: some View {
        setupStepCard(
            stepTitle: "1. Source",
            message: "The library Chronoframe should organize.",
            stepState: model.sourceStepState
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !sourceIsReady {
                    dropZone
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .motion(Motion.filmic, value: sourceIsReady)
                }

                MeridianSurfaceCard(style: .inner, tint: model.sourceStepState.tone.color) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            PathValueView(
                                title: "Manual Folder Source",
                                value: model.displayedSourcePath,
                                helper: model.sourcePathHelper
                            )

                            Spacer(minLength: 12)

                            SetupFolderChooserButton(
                                title: "Choose Source...",
                                accessibilityIdentifier: "chooseSourceButton",
                                action: chooseSource
                            )
                                .accessibilityIdentifier(AccessibilityIdentifiers.chooseSourceButton)
                                .accessibilityHint("Opens a folder picker to choose the source library")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            PathValueView(
                                title: "Manual Folder Source",
                                value: model.displayedSourcePath,
                                helper: model.sourcePathHelper
                            )

                            SetupFolderChooserButton(
                                title: "Choose Source...",
                                accessibilityIdentifier: "chooseSourceButton",
                                action: chooseSource
                            )
                                .accessibilityIdentifier(AccessibilityIdentifiers.chooseSourceButton)
                                .accessibilityHint("Opens a folder picker to choose the source library")
                        }
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
            guard !fileProviders.isEmpty else { return false }
            Task {
                if let provider = fileProviders.first {
                    if let url = await loadFileURL(from: provider) {
                        selectSource(url)
                        #if canImport(AppKit)
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        #endif
                    }
                }
            }
            return true
        }
        .overlay(
            Group {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(DesignTokens.ColorSystem.accentWaypoint.opacity(0.55), lineWidth: 2)
                        .padding(2)
                }
            }
        )
        .motion(.easeInOut(duration: Motion.Duration.fast), value: isTargeted)
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1.0)
        .onHover { hovering in
            Motion.withMotion(.spring(response: 0.25, dampingFraction: 0.7), reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }

    private func setupStepCard<Content: View>(
        stepTitle: String,
        message: String,
        stepState: SetupStepState,
        @ViewBuilder content: () -> Content
    ) -> some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(title: stepTitle, message: message)
                    Spacer(minLength: 12)
                    MeridianStatusBadge(title: stepState.title, tint: stepState.tone.color)
                }

                content()
            }
        }
    }
}

struct SetupDestinationStepSection: View {
    let model: SetupScreenModel
    let chooseDestination: () -> Void
    let selectDestination: (URL) -> Void

    @State private var isTargeted = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(
                        title: "2. Destination",
                        message: "Where organized copies and receipts are written."
                    )
                    Spacer(minLength: 12)
                    MeridianStatusBadge(title: model.destinationStepState.title, tint: model.destinationStepState.tone.color)
                }

                MeridianSurfaceCard(style: .inner, tint: model.destinationStepState.tone.color) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            PathValueView(
                                title: "Destination Folder",
                                value: model.context.destinationPath,
                                helper: model.destinationPathHelper
                            )

                            Spacer(minLength: 12)

                            SetupFolderChooserButton(
                                title: "Choose Destination...",
                                accessibilityIdentifier: "chooseDestinationButton",
                                action: chooseDestination
                            )
                                .accessibilityIdentifier(AccessibilityIdentifiers.chooseDestinationButton)
                                .accessibilityHint("Opens a folder picker to choose where organized copies will be written")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            PathValueView(
                                title: "Destination Folder",
                                value: model.context.destinationPath,
                                helper: model.destinationPathHelper
                            )

                            SetupFolderChooserButton(
                                title: "Choose Destination...",
                                accessibilityIdentifier: "chooseDestinationButton",
                                action: chooseDestination
                            )
                                .accessibilityIdentifier(AccessibilityIdentifiers.chooseDestinationButton)
                                .accessibilityHint("Opens a folder picker to choose where organized copies will be written")
                        }
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
            guard !fileProviders.isEmpty else { return false }
            Task {
                if let provider = fileProviders.first {
                    if let url = await loadFileURL(from: provider) {
                        selectDestination(url)
                        #if canImport(AppKit)
                        NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                        #endif
                    }
                }
            }
            return true
        }
        .overlay(
            Group {
                if isTargeted {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(DesignTokens.ColorSystem.accentWaypoint.opacity(0.55), lineWidth: 2)
                        .padding(2)
                }
            }
        )
        .motion(.easeInOut(duration: Motion.Duration.fast), value: isTargeted)
        .scaleEffect(isHovered && !reduceMotion ? 1.015 : 1.0)
        .onHover { hovering in
            Motion.withMotion(.spring(response: 0.25, dampingFraction: 0.7), reduceMotion: reduceMotion) {
                isHovered = hovering
            }
        }
    }
}

struct SetupReadinessSection: View {
    let model: SetupScreenModel
    let preview: () -> Void
    let transfer: () -> Void
    let openSettings: () -> Void
    let isRunInProgress: Bool

    @State private var showsSafetyDetails = false

    var body: some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(
                        title: "Start",
                        message: model.readinessMessage
                    )

                    Spacer(minLength: 12)

                    MeridianStatusBadge(
                        title: model.readinessBadgeTitle,
                        systemImage: model.readinessBadgeSymbol,
                        tint: model.readinessTone.color
                    )
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        previewButton
                        transferButton
                        Button("Adjust Settings…", action: openSettings)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 10) {
                        previewButton
                        transferButton
                        Button("Adjust Settings…", action: openSettings)
                    }
                    .padding(8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }

                // The safe-path promise in one line; the full evidence
                // (trust items + readiness checklist) stays one click away.
                // The heavy proof belongs at the transfer confirmation, not
                // in front of a non-destructive preview.
                DisclosureGroup(isExpanded: $showsSafetyDetails) {
                    VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                        TrustProofSurface(items: TrustProofModel.setupSafetySummary(
                            source: model.context.sourcePath,
                            destination: model.context.destinationPath,
                            verifyCopies: model.context.verifyCopies
                        ))

                        SetupPreflightChecklist(model: model)
                    }
                    .padding(.top, DesignTokens.Spacing.sm)
                } label: {
                    Label(
                        "Everything runs on this Mac. Originals are never changed.",
                        systemImage: "lock.shield"
                    )
                    .font(.subheadline)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.setupSafetyDetailsDisclosure)
            }
        }
    }

    private var previewButton: some View {
        Button(action: preview) {
            Label("Preview", systemImage: "eye")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canStartRun || isRunInProgress)
        .accessibilityIdentifier(AccessibilityIdentifiers.previewButton)
        .accessibilityLabel("Preview")
        .accessibilityHint(model.canStartRun ? "Generates a copy plan without moving any files" : "Choose both folders or a saved profile first")
    }

    private var transferButton: some View {
        Button(action: transfer) {
            Label("Transfer", systemImage: "arrow.right.circle.fill")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .disabled(!model.canStartRun || isRunInProgress)
        .accessibilityIdentifier(AccessibilityIdentifiers.transferButton)
        .accessibilityLabel("Transfer")
        .accessibilityHint(model.canStartRun ? "Copies files from the source to the destination after confirmation" : "Choose both folders or a saved profile first")
    }
}

private struct SetupPreflightChecklist: View {
    let model: SetupScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Readiness check")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                preflightItem(
                    title: "Source access",
                    value: model.context.sourcePath.isEmpty ? "Needed" : "Ready",
                    isReady: !model.context.sourcePath.isEmpty,
                    systemImage: "folder"
                )
                preflightItem(
                    title: "Destination",
                    value: model.context.destinationPath.isEmpty ? "Needed" : "Writable check during preview",
                    isReady: !model.context.destinationPath.isEmpty,
                    systemImage: "externaldrive"
                )
                preflightItem(
                    title: "Originals",
                    value: "Read-only",
                    isReady: true,
                    systemImage: "lock.shield"
                )
                preflightItem(
                    title: "Recovery",
                    value: "Receipt after transfer",
                    isReady: true,
                    systemImage: "arrow.uturn.backward.circle"
                )
                preflightItem(
                    title: "Copy verification",
                    value: model.context.verifyCopies ? "On" : "Off",
                    isReady: model.context.verifyCopies,
                    systemImage: model.context.verifyCopies ? "checkmark.shield" : "speedometer"
                )
            }
        }
        .accessibilityIdentifier(AccessibilityIdentifiers.setupPreflightChecklist)
    }

    private func preflightItem(
        title: String,
        value: String,
        isReady: Bool,
        systemImage: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(isReady ? DesignTokens.ColorSystem.statusSuccess : DesignTokens.ColorSystem.statusWarning)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.caption2)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .lineLimit(2)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.ColorSystem.hairline.opacity(0.35), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

struct SetupDropZone: View {
    let isActive: Bool
    let droppedSourceLabel: String?
    @Binding var isTargeted: Bool
    let onDrop: ([NSItemProvider]) -> Bool

    @State private var isHovering = false

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: isTargeted ? DesignTokens.Color.sky : DesignTokens.Color.cloud) {
            ZStack {
                if !isActive {
                    DropZonePlaceholderFrames(emphasized: isHovering || isTargeted)
                        .accessibilityHidden(true)
                }

                VStack(spacing: 10) {
                    MeridianLeadIcon(
                        systemImage: isActive ? "photo.on.rectangle.angled" : "square.and.arrow.down.on.square",
                        tint: isTargeted ? DesignTokens.Color.sky : DesignTokens.Color.inkMuted,
                        isAccessibilityHidden: true
                    )

                    if isActive {
                        Text(droppedSourceLabel ?? "Dropped items ready")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.Color.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(isTargeted ? "Release to use as source" : "Drop a folder to begin")
                            .font(.headline)
                            .foregroundStyle(isTargeted ? DesignTokens.Color.sky : DesignTokens.Color.inkPrimary)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous)
                    .strokeBorder(
                        isTargeted ? DesignTokens.Color.sky : DesignTokens.Color.inkMuted.opacity(0.30),
                        style: StrokeStyle(lineWidth: 1, dash: [10, 6])
                    )
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous))
        .onHover { hovering in
            isHovering = hovering
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            onDrop(providers)
        }
        .accessibilityLabel(AccessibilityLabels.dropZone)
        .accessibilityHint(AccessibilityLabels.dropZoneHint)
        .accessibilityIdentifier(AccessibilityIdentifiers.dropZone)
    }
}

/// A barely-perceptible montage of placeholder "film frames" that drift on a
/// 12-second cycle. Foreground label + dashed border still own the layout;
/// this layer reads as a light-table the user is about to place photos on.
private struct DropZonePlaceholderFrames: View {
    let emphasized: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let frames: [PlaceholderFrame] = [
        .init(unitX: 0.10, unitY: 0.20, width: 64, height: 44, rotation: -4, phase: 0.0),
        .init(unitX: 0.28, unitY: 0.66, width: 58, height: 58, rotation: 3, phase: 1.1),
        .init(unitX: 0.46, unitY: 0.28, width: 72, height: 48, rotation: -2, phase: 2.3),
        .init(unitX: 0.62, unitY: 0.74, width: 50, height: 66, rotation: 5, phase: 3.0),
        .init(unitX: 0.78, unitY: 0.32, width: 66, height: 44, rotation: -3, phase: 4.2),
        .init(unitX: 0.92, unitY: 0.68, width: 52, height: 52, rotation: 2, phase: 5.0),
        .init(unitX: 0.15, unitY: 0.85, width: 56, height: 38, rotation: 1, phase: 6.1)
    ]

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate
                let period: Double = 12
                let omega = 2 * .pi / period
                Canvas(opaque: false) { context, _ in
                    let baseOpacity = emphasized ? 0.20 : 0.10
                    for frame in Self.frames {
                        let phase = t * omega + frame.phase
                        let dx = CGFloat(cos(phase)) * 4
                        let dy = CGFloat(sin(phase * 0.8)) * 3
                        let x = frame.unitX * geo.size.width + dx
                        let y = frame.unitY * geo.size.height + dy
                        let rect = CGRect(
                            x: x - frame.width / 2,
                            y: y - frame.height / 2,
                            width: frame.width,
                            height: frame.height
                        )
                        let path = Path(roundedRect: rect, cornerRadius: 4)
                        var transformed = context
                        transformed.translateBy(x: x, y: y)
                        transformed.rotate(by: .degrees(frame.rotation))
                        transformed.translateBy(x: -x, y: -y)
                        transformed.fill(
                            path,
                            with: .color(DesignTokens.ColorSystem.imageStage.opacity(baseOpacity))
                        )
                        transformed.stroke(
                            path,
                            with: .color(DesignTokens.ColorSystem.photoEdgeHighlight.opacity(baseOpacity * 2.4)),
                            lineWidth: 0.5
                        )
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .motion(Motion.filmic, value: emphasized)
    }

    private struct PlaceholderFrame {
        let unitX: Double
        let unitY: Double
        let width: CGFloat
        let height: CGFloat
        let rotation: Double
        let phase: Double
    }
}

@MainActor
fileprivate func loadFileURL(from provider: NSItemProvider) async -> URL? {
    await withCheckedContinuation { continuation in
        provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
            if let url = item as? URL {
                continuation.resume(returning: url)
                return
            }
            if let data = item as? Data,
               let url = URL(dataRepresentation: data, relativeTo: nil) {
                continuation.resume(returning: url)
                return
            }
            if let string = item as? String,
               let url = URL(string: string) {
                continuation.resume(returning: url)
                return
            }
            continuation.resume(returning: nil)
        }
    }
}
