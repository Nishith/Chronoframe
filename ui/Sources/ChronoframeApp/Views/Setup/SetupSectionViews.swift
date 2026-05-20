import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import UniformTypeIdentifiers

struct SetupHeroSection: View {
    let model: SetupScreenModel
    let primaryAction: () -> Void
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
        // Carry the brand mark through the calm states (nothing chosen yet, or
        // everything ready) so Chronoframe's identity anchors the hero. The
        // transitional "warning" state keeps its actionable folder glyph.
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
            VStack(alignment: .leading, spacing: 12) {
                SummaryLine(title: "Source", value: model.sourceSummaryValue, valueColor: model.sourceStepState.tone.color, onTap: scrollToSource)
                SummaryLine(title: "Destination", value: model.destinationSummaryValue, valueColor: model.destinationStepState.tone.color, onTap: scrollToDestination)
                SummaryLine(title: "Mode", value: model.modeSummaryValue)
                SummaryLine(title: "Next", value: model.nextStepSummary, valueColor: model.heroTone.color)
            }
        } actions: {
            heroActionButton
        }
    }

    /// The hero's primary action. We reserve the filled, prominent treatment for
    /// the terminal "Preview Plan" action so the screen has a single visual lead;
    /// the per-step "Choose Source/Destination…" buttons own those moments, so the
    /// hero stays quiet (`.bordered`) while setup is still incomplete.
    @ViewBuilder
    private var heroActionButton: some View {
        if model.primaryAction == .preview {
            heroActionButtonBase.buttonStyle(.borderedProminent)
        } else {
            heroActionButtonBase.buttonStyle(.bordered)
        }
    }

    private var heroActionButtonBase: some View {
        Button(action: primaryAction) {
            Label(model.primaryAction.title, systemImage: model.primaryAction.systemImage)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .disabled(model.primaryActionDisabled)
        .accessibilityLabel(model.primaryAction.title)
        .accessibilityHint(model.primaryActionDisabled ? "Choose both folders to continue" : "Continues to the next setup step")
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
                        title: "Profiles for Repeatable Runs",
                        message: "Use a saved source and destination pair when you want the app and CLI to stay in sync."
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
            .accessibilityIdentifier("profilePicker")
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
                        .animation(Motion.filmic, value: sourceIsReady)
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

                            Button("Choose Source…", action: chooseSource)
                                .accessibilityHint("Opens a folder picker to choose the source library")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            PathValueView(
                                title: "Manual Folder Source",
                                value: model.displayedSourcePath,
                                helper: model.sourcePathHelper
                            )

                            Button("Choose Source…", action: chooseSource)
                                .accessibilityHint("Opens a folder picker to choose the source library")
                        }
                    }
                }
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

                            Button("Choose Destination…", action: chooseDestination)
                                .accessibilityHint("Opens a folder picker to choose where organized copies will be written")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            PathValueView(
                                title: "Destination Folder",
                                value: model.context.destinationPath,
                                helper: model.destinationPathHelper
                            )

                            Button("Choose Destination…", action: chooseDestination)
                                .accessibilityHint("Opens a folder picker to choose where organized copies will be written")
                        }
                    }
                }
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

    var body: some View {
        MeridianSurfaceCard(style: .section) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(
                        title: "Run",
                        message: "Preview to inspect the plan. Transfer when ready."
                    )

                    Spacer(minLength: 12)

                    MeridianStatusBadge(
                        title: model.readinessBadgeTitle,
                        systemImage: model.readinessBadgeSymbol,
                        tint: model.readinessTone.color
                    )
                }

                MeridianSurfaceCard(style: .inner, tint: DesignTokens.Color.amber) {
                    VStack(alignment: .leading, spacing: 12) {
                        SummaryLine(title: "Configuration", value: model.configurationSummary)
                        SummaryLine(title: "Performance", value: model.performanceSummary)
                        SummaryLine(title: "Safety", value: model.safetySummary)
                    }
                }

                SetupPreflightChecklist(model: model)

                Text(model.readinessMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        previewButton
                        transferButton
                        Button("Adjust Settings…", action: openSettings)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        previewButton
                        transferButton
                        Button("Adjust Settings…", action: openSettings)
                    }
                }
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
        .accessibilityIdentifier("previewButton")
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
        .accessibilityIdentifier("transferButton")
        .accessibilityLabel("Transfer")
        .accessibilityHint(model.canStartRun ? "Copies files from the source to the destination after confirmation" : "Choose both folders or a saved profile first")
    }
}

private struct SetupPreflightChecklist: View {
    let model: SetupScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Preflight")
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
        .accessibilityIdentifier("setupPreflightChecklist")
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
                    .foregroundStyle(.secondary)
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

    var body: some View {
        MeridianSurfaceCard(style: .inner, tint: isTargeted ? DesignTokens.Color.sky : DesignTokens.Color.cloud) {
            VStack(spacing: 10) {
                MeridianLeadIcon(
                    systemImage: isActive ? "photo.on.rectangle.angled" : "square.and.arrow.down.on.square",
                    tint: isTargeted ? DesignTokens.Color.sky : DesignTokens.Color.inkMuted
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
            .frame(maxWidth: .infinity, minHeight: 104)
            .padding(.vertical, 8)
            .background {
                // A photo tool should feel like a light table even when empty.
                // Behind the prompt sits a quiet, slowly drifting montage of
                // placeholder frames — no real photos until a source is chosen.
                if !isActive {
                    DropZoneFilmMontage(intensity: isTargeted ? 0.22 : 0.12)
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous)
                    .strokeBorder(
                        isTargeted ? DesignTokens.Color.sky : DesignTokens.Color.inkMuted.opacity(0.32),
                        style: StrokeStyle(lineWidth: 1, dash: [8, 6])
                    )
            )
        }
        .contentShape(RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous))
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            onDrop(providers)
        }
        .accessibilityLabel("Drop photos, videos, or folders to use as source")
        .accessibilityIdentifier("dropZone")
    }
}

/// A decorative, low-opacity montage of placeholder "film frames" that sits
/// behind the empty drop zone. The frames drift on a long, gentle loop so the
/// surface feels alive — a light table waiting for photos — without distracting
/// from the prompt. Honors Reduce Motion (frames hold still).
private struct DropZoneFilmMontage: View {
    /// Overall opacity of the montage; brightens slightly while drag-targeted.
    let intensity: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var drift = false

    private struct Frame: Identifiable {
        let id = UUID()
        let anchor: UnitPoint
        let size: CGSize
        let rotation: Double
        let driftY: CGFloat
        let highlight: Bool
    }

    // Deterministic layout — scattered like prints laid out on a table.
    private let frames: [Frame] = [
        Frame(anchor: UnitPoint(x: 0.10, y: 0.34), size: CGSize(width: 56, height: 42), rotation: -8, driftY: 5, highlight: false),
        Frame(anchor: UnitPoint(x: 0.27, y: 0.66), size: CGSize(width: 44, height: 58), rotation: 6, driftY: -4, highlight: false),
        Frame(anchor: UnitPoint(x: 0.44, y: 0.30), size: CGSize(width: 60, height: 46), rotation: 3, driftY: 6, highlight: true),
        Frame(anchor: UnitPoint(x: 0.62, y: 0.68), size: CGSize(width: 50, height: 50), rotation: -5, driftY: -5, highlight: false),
        Frame(anchor: UnitPoint(x: 0.78, y: 0.36), size: CGSize(width: 46, height: 60), rotation: 7, driftY: 4, highlight: false),
        Frame(anchor: UnitPoint(x: 0.90, y: 0.64), size: CGSize(width: 54, height: 40), rotation: -4, driftY: -6, highlight: false),
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(frames) { frame in
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(
                            frame.highlight
                                ? DesignTokens.ColorSystem.accentWaypoint.opacity(0.16)
                                : DesignTokens.ColorSystem.imageStage.opacity(0.5)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(DesignTokens.ColorSystem.photoEdgeHighlight, lineWidth: 0.5)
                        )
                        .frame(width: frame.size.width, height: frame.size.height)
                        .rotationEffect(.degrees(frame.rotation))
                        .position(x: geo.size.width * frame.anchor.x,
                                  y: geo.size.height * frame.anchor.y)
                        .offset(y: drift ? frame.driftY : -frame.driftY)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()
        }
        .opacity(intensity)
        .animation(Motion.filmic, value: intensity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 12).repeatForever(autoreverses: true)) {
                drift = true
            }
        }
    }
}
