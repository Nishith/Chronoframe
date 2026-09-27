#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

enum SettingsTab: String, Hashable {
    case general
    case profiles
    case layout
    case performance
    case deduplicate
    case license
    case diagnostics
}

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var preferencesStore: PreferencesStore

    init(appState: AppState) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._preferencesStore = ObservedObject(wrappedValue: appState.preferencesStore)
    }

    var body: some View {
        TabView(selection: $appState.settingsSelection) {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(SettingsTab.general)

            ProfilesView(appState: appState, displayMode: .settings)
                .tabItem {
                    Label("Profiles", systemImage: "person.crop.rectangle.stack")
                }
                .tag(SettingsTab.profiles)

            LayoutSettingsTab(appState: appState, preferencesStore: preferencesStore)
                .tabItem {
                    Label("Layout", systemImage: "rectangle.3.offgrid")
                }
                .tag(SettingsTab.layout)

            PerformanceSettingsTab(preferencesStore: preferencesStore)
                .tabItem {
                    Label("Performance", systemImage: "speedometer")
                }
                .tag(SettingsTab.performance)

            DeduplicateSettingsTab(preferencesStore: preferencesStore)
                .tabItem {
                    Label("Deduplicate", systemImage: "rectangle.on.rectangle.angled")
                }
                .tag(SettingsTab.deduplicate)

            LicenseSettingsTab(
                appState: appState,
                entitlementStore: TrialComposition.entitlementStore
            )
                .tabItem {
                    Label("License", systemImage: "key")
                }
                .tag(SettingsTab.license)

            DiagnosticsSettingsTab(appState: appState, preferencesStore: preferencesStore)
                .tabItem {
                    Label("Diagnostics", systemImage: "stethoscope")
                }
        .tag(SettingsTab.diagnostics)
        }
        .frame(minWidth: 620, idealWidth: 760, minHeight: 520)
        .onAppear {
            #if DEBUG
            UITestScenario.configureCurrentWindow(for: UITestScenario.current(), isSettings: true)
            #endif
        }
        .navigationTitle("Settings")
    }
}

private struct LayoutSettingsTab: View {
    let appState: AppState
    @ObservedObject var preferencesStore: PreferencesStore
    @State private var showingReorganizeConfirmation = false

    var body: some View {
        Form {
            Section {
                Picker("Folder Structure", selection: $preferencesStore.folderStructure) {
                    ForEach(FolderStructure.allCases, id: \.self) { structure in
                        Text(structure.rawValue).tag(structure)
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier(AccessibilityIdentifiers.folderStructurePicker)

                Toggle(isOn: $preferencesStore.smartEventSuggestionsEnabled) {
                    Text("Suggest Smart Events During Preview")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
                    .accessibilityIdentifier(AccessibilityIdentifiers.smartEventSuggestionsToggle)
            } header: {
                Text("Default Layout")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("Future previews and transfers organize files into this directory layout. Smart Events suggest editable groups in Preview; they are only applied after you accept them and rebuild the preview.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }

            Section {
                Button {
                    showingReorganizeConfirmation = true
                } label: {
                    Label("Reorganize Destination Now", systemImage: "rectangle.3.offgrid.fill")
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.reorganizeDestinationButton)
            } header: {
                Text("Reorganize")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("Move every file already in the destination into the layout selected above. Files are moved on the same volume (instant — no copy), originals are never deleted, and an existing file at the new location is never overwritten.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Reorganize destination?",
            isPresented: $showingReorganizeConfirmation
        ) {
            Button("Reorganize", role: .destructive) {
                appState.reorganizeDestination(targetStructure: preferencesStore.folderStructure)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Chronoframe will move every recognised file in the destination into the \(preferencesStore.folderStructure.rawValue) layout. Originals are not deleted, but files will appear at new paths. Open the Run workspace to track progress.")
        }
    }
}

private struct GeneralSettingsTab: View {
    var body: some View {
        Form {
            Section {
                Text("Tune how Chronoframe balances speed, safety, and diagnostics. These settings affect future previews and transfers without changing the organizer's core guarantees.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }
        }
        .formStyle(.grouped)
    }
}

/// One-click throughput settings. Each preset sets exact values, so a preset
/// shows as selected only when every setting it controls matches; anything
/// else is Custom. Standard is the app's default configuration, and both
/// presets keep copy verification on.
enum SafetyPerformancePreset: String, CaseIterable, Identifiable {
    case standard
    case oneAtATime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard:
            return "Standard"
        case .oneAtATime:
            return "One at a Time"
        }
    }

    var summary: String {
        switch self {
        case .standard:
            return "Verified copies, several files at once, \(workerCount) worker threads."
        case .oneAtATime:
            return "Verified copies, one file at a time, \(workerCount) worker threads."
        }
    }

    var workerCount: Int { 8 }

    var parallelTransferEnabled: Bool {
        self == .standard
    }

    @MainActor
    func apply(to preferencesStore: PreferencesStore) {
        preferencesStore.verifyCopies = true
        preferencesStore.parallelTransferEnabled = parallelTransferEnabled
        preferencesStore.workerCount = workerCount
    }

    @MainActor
    func matches(_ preferencesStore: PreferencesStore) -> Bool {
        preferencesStore.verifyCopies
            && preferencesStore.parallelTransferEnabled == parallelTransferEnabled
            && preferencesStore.workerCount == workerCount
    }

    /// The preset the current settings match exactly, or nil for Custom.
    @MainActor
    static func matching(_ preferencesStore: PreferencesStore) -> SafetyPerformancePreset? {
        allCases.first { $0.matches(preferencesStore) }
    }
}

private struct PerformanceSettingsTab: View {
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        Form {
            Section {
                let activePreset = SafetyPerformancePreset.matching(preferencesStore)
                ForEach(SafetyPerformancePreset.allCases) { preset in
                    Button {
                        preset.apply(to: preferencesStore)
                    } label: {
                        presetRow(title: preset.title, summary: preset.summary, isActive: activePreset == preset)
                    }
                    .buttonStyle(.plain)
                }
                if activePreset == nil {
                    presetRow(
                        title: "Custom",
                        summary: "The settings below don't match a preset.",
                        isActive: true
                    )
                }
            } header: {
                Text("Presets")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("Presets adjust the advanced controls below without weakening Chronoframe's source-folder safety guarantees.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }

            Section {
                Stepper(value: $preferencesStore.workerCount, in: 1...32) {
                    LabeledContent {
                        Text("\(preferencesStore.workerCount)")
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    } label: {
                        Text("Worker Threads")
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    }
                }

                Toggle(isOn: $preferencesStore.parallelTransferEnabled) {
                    Text("Parallel Transfers")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
            } header: {
                Text("Throughput")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("More worker threads can improve throughput on faster storage. Parallel transfers allow concurrent file copies and only affect future transfer runs.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }

            Section {
                Toggle(isOn: $preferencesStore.verifyCopies) {
                    Text("Verify Completed Copies")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
            } header: {
                Text("Safety")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("Verification re-hashes copied files after transfer. It adds work, but it provides stronger confidence that destination files match the originals.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }
        }
        .formStyle(.grouped)
    }
}

private extension PerformanceSettingsTab {
    func presetRow(title: String, summary: String, isActive: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(DesignTokens.ColorSystem.accentAction)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(DesignTokens.ColorSystem.inkMuted.opacity(0.4))
            }
        }
    }
}
private struct DeduplicateSettingsTab: View {
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        Form {
            Section {
                Toggle(isOn: $preferencesStore.dedupeBurstModeEnabled) {
                    Text("Burst mode")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }

                Picker("Similarity", selection: $preferencesStore.dedupeSimilarityPreset) {
                    ForEach(DedupeSimilarityPreset.allCases) { preset in
                        Text(preset.title).tag(preset)
                    }
                }
                .pickerStyle(.segmented)

                Text(preferencesStore.dedupeSimilarityPreset.subtitle)
                    .font(.callout)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                Toggle(isOn: $preferencesStore.dedupePerceptualVideoMatchingEnabled) {
                    Label("Find visually similar videos", systemImage: "film")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }

                if preferencesStore.dedupePerceptualVideoMatchingEnabled {
                    Text(preferencesStore.dedupeSimilarityPreset.allowsPerceptualVideoMatching
                        ? "Video frames are analyzed on this Mac. Matches stay review-only."
                        : "Exact Copies only finds byte-identical videos; choose Balanced or Similar Shots for visual video matching.")
                        .font(.callout)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }

                if preferencesStore.dedupeBurstModeEnabled {
                    Stepper(value: $preferencesStore.dedupeTimeWindowSeconds, in: 5...600, step: 5) {
                        LabeledContent {
                            Text("\(preferencesStore.dedupeTimeWindowSeconds)s")
                                .monospacedDigit()
                                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        } label: {
                            Text("Time Window")
                                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        }
                    }
                }
            } header: {
                Text("Detection")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text(preferencesStore.dedupeBurstModeEnabled
                    ? "Burst mode only compares photos taken within the time window — fast, ideal for catching burst sequences and rapid retakes. Visual video matching is a separate, optional pass and may take longer on its first scan."
                    : "Without burst mode, every photo in the destination is compared against every other. Visual video matching remains a separate, optional pass and may take longer on its first scan.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }

            Section {
                Toggle(isOn: $preferencesStore.dedupeTreatRawJpegPairsAsUnit) {
                    Text("Treat RAW + JPEG as a unit")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
                Toggle(isOn: $preferencesStore.dedupeTreatLivePhotoPairsAsUnit) {
                    Text("Treat Live Photo (HEIC + MOV) as a unit")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
                Toggle(isOn: $preferencesStore.dedupeIncludeExactDuplicates) {
                    Text("Surface exact duplicates separately")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
            } header: {
                Text("Pairing")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("Paired files are always kept or deleted together. Exact duplicates use the existing file-identity hash and are surfaced as their own group.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }

            Section {
                Toggle(isOn: $preferencesStore.dedupePerceptualVideoMatchingEnabled) {
                    Text("Find similar videos")
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
            } header: {
                Text("Video")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("Decodes a few frames from each video to catch re-encodes and format conversions of the same recording. Slower scans, and these matches are always review-only — nothing is ever auto-selected for deletion. Byte-identical videos are found regardless of this setting.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct DiagnosticsSettingsTab: View {
    let appState: AppState
    @ObservedObject var preferencesStore: PreferencesStore

    var body: some View {
        Form {
            Section {
                Stepper(
                    value: $preferencesStore.logBufferCapacity,
                    in: PreferencesStore.minimumLogCapacity...PreferencesStore.maximumLogCapacity,
                    step: 250
                ) {
                    LabeledContent {
                        Text("\(preferencesStore.logBufferCapacity)")
                            .monospacedDigit()
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    } label: {
                        Text("In-Memory Log Buffer")
                            .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    }
                }
                .accessibilityIdentifier(AccessibilityIdentifiers.diagnosticsLogBufferStepper)
            } header: {
                Text("Log Buffer")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            } footer: {
                Text("A larger buffer keeps more recent console history in memory for the Run workspace. Lower values use less memory but trim older log lines sooner.")
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            }
        }
        .formStyle(.grouped)
        .onChange(of: preferencesStore.logBufferCapacity) { _, newValue in
            appState.runLogStore.capacity = newValue
        }
    }
}
