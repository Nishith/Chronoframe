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
            title: "Choose Folders",
            titleAccessibilityIdentifier: AccessibilityIdentifiers.setupHeroTitle,
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
                SummaryLine(title: "Privacy", value: "Everything stays on this Mac")

                SummaryLine(
                    title: "Next",
                    value: model.nextStepSummary,
                    valueColor: nil,
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
    let sourceURL: URL?

    var body: some View {
        MeridianSurfaceCard(style: .standard) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                SectionHeading(
                    title: "A first look",
                    message: sourcePath.isEmpty
                        ? "Photos appear here once you add a folder."
                        : "The first photos Chronoframe found in your folders."
                )

                ContactSheetView(sourcePath: sourcePath, sourceURL: sourceURL)
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
                        message: "Use a saved pair of folders."
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
                            SummaryLine(title: "Folder to organize", value: profile.sourcePath)
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
                Text("Folders I Choose").tag("")
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
    let addSource: ([URL]) -> Void
    let removeSource: (URL) -> Void

    @State private var isTargeted = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sourceIsReady: Bool {
        if case .ready = model.sourceStepState { return true }
        return false
    }

    /// Folders can't be removed mid-copy, and a selected profile owns its single folder.
    private var canRemoveItems: Bool {
        !model.context.isRunInProgress && model.context.activeProfile == nil
    }

    var body: some View {
        setupStepCard(
            stepTitle: "1. Folders to organize",
            message: "Add every folder that holds photos or videos. Chronoframe only reads them.",
            stepState: model.sourceStepState
        ) {
            VStack(alignment: .leading, spacing: 12) {
                if !sourceIsReady {
                    dropZone
                        .transition(.opacity.combined(with: .scale(scale: 0.97)))
                        .motion(Motion.filmic, value: sourceIsReady)
                }

                MeridianSurfaceCard(style: .inner, tint: model.sourceStepState.tone.color) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !model.context.sourceItems.isEmpty {
                            SetupSourceItemList(
                                rows: model.context.sourceItems,
                                canRemove: canRemoveItems,
                                remove: removeSource
                            )
                        }

                        if !model.sourcePathHelper.isEmpty {
                            Text(model.sourcePathHelper)
                                .scaledFont(.label)
                                .foregroundStyle(DesignTokens.ColorSystem.captionText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        SetupFolderChooserButton(
                            title: "Add Folders…",
                            accessibilityIdentifier: "chooseSourceButton",
                            action: chooseSource
                        )
                            .accessibilityIdentifier(AccessibilityIdentifiers.chooseSourceButton)
                            .accessibilityHint("Opens a folder picker. You can pick more than one folder.")
                    }
                }
            }
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
            guard !fileProviders.isEmpty else { return false }
            Task {
                var urls: [URL] = []
                for provider in fileProviders {
                    if let url = await loadFileURL(from: provider) {
                        urls.append(url)
                    }
                }
                guard !urls.isEmpty else { return }
                addSource(urls)
                #if canImport(AppKit)
                NSHapticFeedbackManager.defaultPerformer.perform(.generic, performanceTime: .now)
                #endif
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
        MeridianSurfaceCard(style: .standard) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(title: stepTitle, message: message)
                    Spacer(minLength: 12)
                    if case .needed = stepState {
                        MeridianStatusBadge(title: stepState.title, tint: stepState.tone.color)
                    }
                }

                content()
            }
        }
    }
}

private struct SetupSourceItemList: View {
    let rows: [SetupSourceItemRow]
    let canRemove: Bool
    let remove: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                HStack(alignment: .center, spacing: 10) {
                    Image(systemName: row.isFolder ? "folder" : "doc")
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .frame(width: 18)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .scaledFont(.body)
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(row.parent)
                            .scaledFont(.label)
                            .foregroundStyle(DesignTokens.ColorSystem.captionText)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .help(row.id)

                    Spacer(minLength: 8)

                    Button {
                        remove(URL(fileURLWithPath: row.id))
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .disabled(!canRemove)
                    .accessibilityLabel("Remove \(row.name) from the folders to organize")
                    .accessibilityIdentifier(AccessibilityIdentifiers.setupSourceItemRemovePrefix + String(index))
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(AccessibilityIdentifiers.setupSourceItems)
    }
}

struct SetupDestinationStepSection: View {
    let model: SetupScreenModel
    @ObservedObject var preferencesStore: PreferencesStore
    let chooseDestination: () -> Void
    let selectDestination: (URL) -> Void

    @State private var isTargeted = false
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        MeridianSurfaceCard(style: .standard) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                HStack(alignment: .top, spacing: 12) {
                    SectionHeading(
                        title: "2. Destination",
                        message: "Where the organized copies go."
                    )
                    Spacer(minLength: 12)
                    if case .needed = model.destinationStepState {
                        MeridianStatusBadge(title: model.destinationStepState.title, tint: model.destinationStepState.tone.color)
                    }
                }

                MeridianSurfaceCard(style: .inner, tint: model.destinationStepState.tone.color) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 12) {
                            PathValueView(
                                title: "Destination folder",
                                value: model.context.destinationPath,
                                helper: model.destinationPathHelper
                            )

                            Spacer(minLength: 12)

                            SetupFolderChooserButton(
                                title: "Choose Destination…",
                                accessibilityIdentifier: "chooseDestinationButton",
                                action: chooseDestination
                            )
                                .accessibilityIdentifier(AccessibilityIdentifiers.chooseDestinationButton)
                                .accessibilityHint("Opens a folder picker to choose where the organized copies go")
                        }

                        VStack(alignment: .leading, spacing: 12) {
                            PathValueView(
                                title: "Destination folder",
                                value: model.context.destinationPath,
                                helper: model.destinationPathHelper
                            )

                            SetupFolderChooserButton(
                                title: "Choose Destination…",
                                accessibilityIdentifier: "chooseDestinationButton",
                                action: chooseDestination
                            )
                                .accessibilityIdentifier(AccessibilityIdentifiers.chooseDestinationButton)
                                .accessibilityHint("Opens a folder picker to choose where the organized copies go")
                        }
                    }
                }

                SetupLayoutBlock(
                    preferencesStore: preferencesStore,
                    isRunInProgress: model.context.isRunInProgress
                )
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

struct SetupLayoutBlock: View {
    @ObservedObject var preferencesStore: PreferencesStore
    let isRunInProgress: Bool

    var body: some View {
        let structure = preferencesStore.folderStructure
        VStack(alignment: .leading, spacing: 8) {
            Text("Folder layout")
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)

            Picker("Folder layout", selection: $preferencesStore.folderStructure) {
                ForEach(FolderStructure.allCases, id: \.self) { option in
                    Text(FolderLayoutPresentation.title(option)).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
            .disabled(isRunInProgress)
            .accessibilityIdentifier(AccessibilityIdentifiers.setupFolderLayoutPicker)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(FolderLayoutPresentation.exampleLines(structure).enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .scaledFont(.mono)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(FolderLayoutPresentation.accessibilityExample(structure))
        }
    }
}

struct SetupReadinessSection: View {
    let model: SetupScreenModel
    let preview: () -> Void
    let openSettings: () -> Void
    let isRunInProgress: Bool

    @State private var showsSafetyDetails = false

    var body: some View {
        MeridianSurfaceCard(style: .standard) {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.cardSpacing) {
                SectionHeading(
                    title: "3. Preview",
                    message: model.readinessMessage
                )

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 12) {
                        previewButton
                        copySettingsButton
                    }
                    .padding(8)
                    .background(DesignTokens.ColorSystem.utilityBand, in: RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 10) {
                        previewButton
                        copySettingsButton
                    }
                    .padding(8)
                    .background(DesignTokens.ColorSystem.utilityBand, in: RoundedRectangle(cornerRadius: 10))
                }

                // The safe-path promise in one line; the full evidence
                // (trust items + readiness checklist) stays one click away.
                // The heavy proof belongs at the copy confirmation, not
                // in front of a preview that copies nothing.
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
            Label("Preview Plan", systemImage: "eye")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .disabled(!model.canStartRun || isRunInProgress)
        .accessibilityIdentifier(AccessibilityIdentifiers.previewButton)
        .accessibilityLabel("Preview plan")
        .accessibilityHint(model.canStartRun ? "Builds the plan without copying anything" : "Add a folder and choose a destination first")
    }

    private var copySettingsButton: some View {
        Button("Copy Settings…", action: openSettings)
            .buttonStyle(.link)
    }
}

private struct SetupPreflightChecklist: View {
    let model: SetupScreenModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Before you start")
                .font(.subheadline.weight(.semibold))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 8)], spacing: 8) {
                preflightItem(
                    title: "Folders to organize",
                    value: model.context.sourcePath.isEmpty ? "Needed" : "Ready",
                    isReady: !model.context.sourcePath.isEmpty,
                    systemImage: "folder"
                )
                preflightItem(
                    title: "Destination",
                    value: model.context.destinationPath.isEmpty ? "Needed" : "Checked when the preview runs",
                    isReady: !model.context.destinationPath.isEmpty,
                    systemImage: "externaldrive"
                )
                preflightItem(
                    title: "Originals",
                    value: "Never changed",
                    isReady: true,
                    systemImage: "lock.shield"
                )
                preflightItem(
                    title: "Undo",
                    value: "Each copy keeps a receipt",
                    isReady: true,
                    systemImage: "arrow.uturn.backward.circle"
                )
                preflightItem(
                    title: "Copy check",
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
                        Text(droppedSourceLabel ?? "Folders added")
                            .font(.headline)
                            .foregroundStyle(DesignTokens.Color.inkPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text(isTargeted ? "Release to add" : "Drop folders here")
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
