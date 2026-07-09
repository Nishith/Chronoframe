#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

/// Pure presentation model for one watched-source row. Kept logic-only
/// so status wording and spoken text are unit-testable (accessibility
/// bar: compose non-trivial spoken text in pure helpers).
struct WatchedSourceRowModel: Equatable {
    let state: WatchedSourceState

    var label: String { state.source.label }
    var path: String { state.source.path }

    var statusText: String {
        switch state.availability {
        case .available:
            if state.isChecking && state.pendingEstimate == nil {
                return "Checking…"
            }
            guard let estimate = state.pendingEstimate else {
                return "Checking…"
            }
            if estimate == 0 {
                return "Caught up"
            }
            return estimate == 1 ? "About 1 new item" : "About \(estimate) new items"
        case .unavailable:
            return "Offline — reconnect the drive to keep watching."
        case .accessLost:
            return "Access lost — choose this folder again."
        case .pausedConflict:
            return "Paused — this folder overlaps your destination."
        }
    }

    /// Secondary caveat line, shown under the status when relevant.
    var detailText: String? {
        guard state.availability == .available else { return nil }
        if state.lastScanWasPartial {
            return "Couldn't fully check this folder."
        }
        if let estimate = state.pendingEstimate, estimate > 0 {
            return "Some may already be in your library — Review & Import shows the exact plan."
        }
        if state.isDegradedWatch {
            return "Watching with reduced detail."
        }
        return nil
    }

    var showsWaypointAccent: Bool {
        state.availability == .available && (state.pendingEstimate ?? 0) > 0
    }

    var showsProgress: Bool {
        state.availability == .available && state.isChecking
    }

    var importEnabled: Bool {
        state.availability == .available
    }

    var showsRepickButton: Bool {
        state.availability == .accessLost
    }

    var iconName: String {
        switch state.availability {
        case .available: return "folder"
        case .unavailable: return "externaldrive.badge.questionmark"
        case .accessLost: return "folder.badge.questionmark"
        case .pausedConflict: return "pause.circle"
        }
    }

    var accessibilityLabel: String {
        var parts = [label, statusText]
        if let detailText {
            parts.append(detailText)
        }
        return parts.joined(separator: ", ")
    }
}

/// The Sources tab: watched folders with standing "new arrivals"
/// estimates and one-click Review & Import into the active destination.
struct WatchedSourcesView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var watchedSourcesStore: WatchedSourcesStore
    @State private var ignoreCandidate: WatchedSourceState?
    @State private var removeCandidate: WatchedSourceState?

    init(appState: AppState) {
        self.appState = appState
        self._watchedSourcesStore = ObservedObject(wrappedValue: appState.watchedSourcesStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let notice = watchedSourcesStore.storeNotice {
                noticeBanner(notice)
            }
            if watchedSourcesStore.states.isEmpty {
                emptyState
            } else {
                sourceList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .confirmationDialog(
            "Ignore the items currently in this folder?",
            isPresented: Binding(
                get: { ignoreCandidate != nil },
                set: { if !$0 { ignoreCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Ignore Current Items") {
                if let candidate = ignoreCandidate {
                    Task { await appState.ignoreWatchedSourceCurrentItems(id: candidate.id) }
                }
                ignoreCandidate = nil
            }
            Button("Cancel", role: .cancel) { ignoreCandidate = nil }
        } message: {
            Text("Chronoframe will stop counting the items currently in this folder. No files are changed.", bundle: .module)
        }
        .confirmationDialog(
            "Stop watching this folder?",
            isPresented: Binding(
                get: { removeCandidate != nil },
                set: { if !$0 { removeCandidate = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Stop Watching", role: .destructive) {
                if let candidate = removeCandidate {
                    appState.removeWatchedSource(id: candidate.id)
                }
                removeCandidate = nil
            }
            Button("Cancel", role: .cancel) { removeCandidate = nil }
        } message: {
            Text("Chronoframe forgets the folder and its counts. No files are touched.", bundle: .module)
        }
    }

    private var header: some View {
        HStack(spacing: DesignTokens.Layout.inlineSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Watched Folders", bundle: .module)
                    .scaledFont(.cardTitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                Text("Chronoframe tells you when new photos or videos arrive.", bundle: .module)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }

            Spacer()

            Button {
                appState.refreshWatchedSources()
            } label: {
                Label {
                    Text("Refresh", bundle: .module)
                } icon: {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .disabled(watchedSourcesStore.states.isEmpty)
            .accessibilityIdentifier(AccessibilityIdentifiers.watchedSourcesRefreshButton)
            .accessibilityLabel(Text("Refresh watched folders", bundle: .module))

            Button {
                Task { await appState.addWatchedSourceFolder() }
            } label: {
                Label {
                    Text("Add Folder…", bundle: .module)
                } icon: {
                    Image(systemName: "plus")
                }
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .accessibilityIdentifier(AccessibilityIdentifiers.watchedSourcesAddButton)
            .accessibilityLabel(Text("Add a folder to watch", bundle: .module))
        }
        .padding(.horizontal, DesignTokens.Layout.contentPadding)
        .padding(.vertical, DesignTokens.Layout.compactPadding)
    }

    private func noticeBanner(_ notice: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(DesignTokens.ColorSystem.statusActive)
                .accessibilityHidden(true)
            Text(notice)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, DesignTokens.Layout.contentPadding)
        .padding(.vertical, DesignTokens.Layout.inlineSpacing)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignTokens.ColorSystem.utilityBand)
    }

    private var emptyState: some View {
        VStack(spacing: DesignTokens.Layout.inlineSpacing) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .accessibilityHidden(true)
            Text("Chronoframe can watch folders — a phone-sync folder, an SD card, Downloads — and tell you when new photos arrive.", bundle: .module)
                .scaledFont(.body)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button {
                Task { await appState.addWatchedSourceFolder() }
            } label: {
                Text("Add Folder…", bundle: .module)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityLabel(Text("Add a folder to watch", bundle: .module))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Layout.contentPadding)
    }

    private var sourceList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(watchedSourcesStore.states) { state in
                    row(for: state)
                    Divider()
                        .padding(.leading, DesignTokens.Layout.contentPadding)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for state: WatchedSourceState) -> some View {
        let model = WatchedSourceRowModel(state: state)
        HStack(alignment: .center, spacing: DesignTokens.Layout.inlineSpacing) {
            Image(systemName: model.iconName)
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .frame(width: 26)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(model.label)
                    .scaledFont(.body, weight: .semibold)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    .lineLimit(1)

                Text(model.path)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    if model.showsWaypointAccent {
                        Circle()
                            .fill(DesignTokens.ColorSystem.accentWaypoint)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                    }
                    Text(model.statusText)
                        .scaledFont(.label, weight: .medium)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    if model.showsProgress {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                if let detail = model.detailText {
                    Text(detail)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .lineLimit(2)
                }
            }

            Spacer(minLength: DesignTokens.Layout.inlineSpacing)

            if model.showsRepickButton {
                Button {
                    Task { await appState.repickWatchedSource(id: state.id) }
                } label: {
                    Text("Choose Again…", bundle: .module)
                }
                .accessibilityLabel(Text("Choose this folder again to restore access", bundle: .module))
            }

            importButton(for: state, model: model)
        }
        .padding(.horizontal, DesignTokens.Layout.contentPadding)
        .padding(.vertical, DesignTokens.Layout.compactPadding)
        .contentShape(Rectangle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(model.accessibilityLabel)
        .accessibilityIdentifier(AccessibilityIdentifiers.watchedSourceRow(state.id.uuidString))
        .contextMenu {
            contextMenuItems(for: state)
        }
    }

    /// Prominent only when there is something to act on; bordered
    /// otherwise. Native styles per the Meridian language — the branch
    /// exists because SwiftUI button styles cannot be picked dynamically.
    @ViewBuilder
    private func importButton(for state: WatchedSourceState, model: WatchedSourceRowModel) -> some View {
        if model.showsWaypointAccent {
            Button {
                Task { await appState.reviewAndImportWatchedSource(id: state.id) }
            } label: {
                Text("Review & Import", bundle: .module)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.importEnabled)
            .accessibilityIdentifier(AccessibilityIdentifiers.watchedSourceImportButton(state.id.uuidString))
            .accessibilityLabel(Text("Review and import new items from \(model.label)", bundle: .module))
        } else {
            Button {
                Task { await appState.reviewAndImportWatchedSource(id: state.id) }
            } label: {
                Text("Review & Import", bundle: .module)
            }
            .buttonStyle(.bordered)
            .disabled(!model.importEnabled)
            .accessibilityIdentifier(AccessibilityIdentifiers.watchedSourceImportButton(state.id.uuidString))
            .accessibilityLabel(Text("Review and import new items from \(model.label)", bundle: .module))
        }
    }

    @ViewBuilder
    private func contextMenuItems(for state: WatchedSourceState) -> some View {
        Button {
            appState.revealWatchedSource(id: state.id)
        } label: {
            Text("Reveal in Finder", bundle: .module)
        }
        Button {
            appState.refreshWatchedSources()
        } label: {
            Text("Refresh", bundle: .module)
        }
        Button {
            ignoreCandidate = state
        } label: {
            Text("Ignore Current Items…", bundle: .module)
        }
        .disabled(state.availability != .available)
        Divider()
        Button(role: .destructive) {
            removeCandidate = state
        } label: {
            Text("Stop Watching…", bundle: .module)
        }
    }
}

