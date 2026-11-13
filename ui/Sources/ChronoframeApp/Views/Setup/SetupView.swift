#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    let appState: AppState
    @ObservedObject private var setupStore: SetupStore
    @ObservedObject private var preferencesStore: PreferencesStore
    @ObservedObject private var runSessionStore: RunSessionStore
    @State private var isDropTargeted = false
    @AppStorage("didOnboard") private var didOnboard = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(appState: AppState) {
        self.appState = appState
        self._setupStore = ObservedObject(wrappedValue: appState.setupStore)
        self._preferencesStore = ObservedObject(wrappedValue: appState.preferencesStore)
        self._runSessionStore = ObservedObject(wrappedValue: appState.runSessionStore)
    }

    private var screenModel: SetupScreenModel {
        SetupScreenModel(
            setupStore: setupStore,
            preferencesStore: preferencesStore,
            isRunInProgress: runSessionStore.isRunning
        )
    }

    var body: some View {
        GeometryReader { geometry in
            let isWide = geometry.size.width >= 1024
            ScrollViewReader { proxy in
                ScrollView {
                    Group {
                        if isWide {
                            HStack(alignment: .top, spacing: DesignTokens.Layout.sectionSpacing) {
                                VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionSpacing) {
                                    SetupHeroSection(
                                        model: screenModel,
                                        scrollToSource: {
                                            Motion.withMotion(.easeInOut(duration: 0.3), reduceMotion: reduceMotion) { proxy.scrollTo("sourceSection", anchor: .top) }
                                        },
                                        scrollToDestination: {
                                            Motion.withMotion(.easeInOut(duration: 0.3), reduceMotion: reduceMotion) { proxy.scrollTo("destinationSection", anchor: .top) }
                                        }
                                    )

                                    SetupSourceStepSection(
                                        model: screenModel,
                                        dropZone: dropZone,
                                        chooseSource: { Task { await appState.chooseSourceFolder() } },
                                        addSource: { urls in Task { await appState.applyDrop(urls: urls) } },
                                        removeSource: { url in Task { await appState.removeSourceItem(url) } }
                                    )
                                    .id("sourceSection")

                                    SetupDestinationStepSection(
                                        model: screenModel,
                                        preferencesStore: preferencesStore,
                                        chooseDestination: { Task { await appState.chooseDestinationFolder() } },
                                        selectDestination: { url in Task { await appState.selectDestinationFolder(url) } }
                                    )
                                    .id("destinationSection")

                                    SetupReadinessSection(
                                        model: screenModel,
                                        preview: { Task { await appState.startPreview() } },
                                        openSettings: appState.openSettingsWindow,
                                        isRunInProgress: runSessionStore.isRunning
                                    )
                                }
                                .frame(maxWidth: DesignTokens.Layout.setupFormColumnWidth, alignment: .topLeading)

                                VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionSpacing) {
                                    if !didOnboard && setupStore.sourcePath.isEmpty {
                                        OnboardingCard(
                                            title: "Start with the folders that hold your photos.",
                                            subtitle: "Drag them onto this window or add them below. Nothing is copied until you say so.",
                                            accessibilitySummary: "Welcome. Start with the folders that hold your photos.",
                                            onDismiss: { didOnboard = true }
                                        )
                                    }

                                    if !setupStore.sourcePath.isEmpty {
                                        SetupContactSheetSection(sourcePath: contactSheetPath, sourceURL: contactSheetURL)
                                    }

                                    if screenModel.showsSavedSetupSection {
                                        SetupSavedSetupSection(
                                            model: screenModel,
                                            setupStore: setupStore,
                                            refreshProfiles: appState.refreshProfiles,
                                            clearSelectedProfile: appState.clearSelectedProfile,
                                            openProfiles: appState.openProfilesSettings,
                                            onProfileSelection: handleProfileSelection(_:)
                                        )
                                    }
                                }
                                .frame(
                                    minWidth: DesignTokens.Layout.setupEvidenceMinWidth,
                                    maxWidth: DesignTokens.Layout.setupEvidenceMaxWidth,
                                    alignment: .topLeading
                                )
                            }
                        } else {
                            VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionSpacing) {
                                SetupHeroSection(
                                    model: screenModel,
                                    scrollToSource: {
                                        Motion.withMotion(.easeInOut(duration: 0.3), reduceMotion: reduceMotion) { proxy.scrollTo("sourceSection", anchor: .top) }
                                    },
                                    scrollToDestination: {
                                        Motion.withMotion(.easeInOut(duration: 0.3), reduceMotion: reduceMotion) { proxy.scrollTo("destinationSection", anchor: .top) }
                                    }
                                )

                                if !didOnboard && setupStore.sourcePath.isEmpty {
                                    OnboardingCard(
                                        title: "Start with the folders that hold your photos.",
                                        subtitle: "Drag them onto this window or add them below. Nothing is copied until you say so.",
                                        accessibilitySummary: "Welcome. Start with the folders that hold your photos.",
                                        onDismiss: { didOnboard = true }
                                    )
                                }

                                SetupSourceStepSection(
                                    model: screenModel,
                                    dropZone: dropZone,
                                    chooseSource: { Task { await appState.chooseSourceFolder() } },
                                    addSource: { urls in Task { await appState.applyDrop(urls: urls) } },
                                    removeSource: { url in Task { await appState.removeSourceItem(url) } }
                                )
                                .id("sourceSection")

                                SetupDestinationStepSection(
                                    model: screenModel,
                                    preferencesStore: preferencesStore,
                                    chooseDestination: { Task { await appState.chooseDestinationFolder() } },
                                    selectDestination: { url in Task { await appState.selectDestinationFolder(url) } }
                                )
                                .id("destinationSection")

                                if !setupStore.sourcePath.isEmpty {
                                    SetupContactSheetSection(sourcePath: contactSheetPath, sourceURL: contactSheetURL)
                                }

                                if screenModel.showsSavedSetupSection {
                                    SetupSavedSetupSection(
                                        model: screenModel,
                                        setupStore: setupStore,
                                        refreshProfiles: appState.refreshProfiles,
                                        clearSelectedProfile: appState.clearSelectedProfile,
                                        openProfiles: appState.openProfilesSettings,
                                        onProfileSelection: handleProfileSelection(_:)
                                    )
                                }

                                SetupReadinessSection(
                                    model: screenModel,
                                    preview: { Task { await appState.startPreview() } },
                                    openSettings: appState.openSettingsWindow,
                                    isRunInProgress: runSessionStore.isRunning
                                )
                            }
                        }
                    }
                    .padding(DesignTokens.Layout.contentPadding)
                    .frame(
                        maxWidth: isWide
                            ? DesignTokens.Layout.setupWideMaxWidth
                            : DesignTokens.Layout.setupMaxWidth,
                        alignment: .leading
                    )
                    .frame(maxWidth: .infinity, alignment: .center)
                }
            }
        }
        .darkroom()
        .navigationTitle("Choose Folders")
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            didOnboard = true
            return handleDrop(providers: providers)
        }
        .overlay {
            if isDropTargeted {
                Rectangle()
                    .fill(DesignTokens.ColorSystem.accentWaypoint.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(DesignTokens.ColorSystem.accentWaypoint.opacity(0.55), lineWidth: 2)
                            .padding(8)
                    )
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .transition(.opacity)
            }
        }
        .motion(.easeInOut(duration: Motion.Duration.fast), value: isDropTargeted)
    }

    /// A staged source is a manifest directory with nothing to show, so the
    /// contact sheet reads the first listed folder instead.
    private var contactSheetFolder: URL? {
        guard DroppedItemStager.isStagingPath(setupStore.sourcePath) else { return nil }
        return setupStore.sourceItems.first { item in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: item.path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
    }

    private var contactSheetPath: String {
        contactSheetFolder?.path ?? setupStore.sourcePath
    }

    private var contactSheetURL: URL? {
        contactSheetFolder ?? setupStore.sourceURL
    }

    private var dropZone: SetupDropZone {
        SetupDropZone(
            isActive: setupStore.usingDroppedSource,
            droppedSourceLabel: setupStore.droppedSourceLabel,
            isTargeted: $isDropTargeted,
            onDrop: handleDrop(providers:)
        )
    }

    private func handleProfileSelection(_ selection: String) {
        if selection.isEmpty {
            appState.clearSelectedProfile()
        } else {
            appState.useProfile(named: selection)
        }
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        let fileProviders = providers.filter { $0.hasItemConformingToTypeIdentifier("public.file-url") }
        guard !fileProviders.isEmpty else { return false }

        Task {
            var urls: [URL] = []
            for provider in fileProviders {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            await appState.applyDrop(urls: urls)
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
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
}
