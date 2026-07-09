import Combine
import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

@MainActor
final class RunCoordinator {
    private let preferencesStore: PreferencesStore
    private let setupStore: SetupStore
    private let historyStore: HistoryStore
    private let runSessionStore: RunSessionStore
    private let finderService: any FinderServicing
    private let showSettingsWindowAction: @MainActor () -> Void
    private let navigate: @MainActor (AppRoute) -> Void
    private let canStartRun: @MainActor () -> Bool
    private let makeSecurityScope: @MainActor (RunConfiguration) -> SecurityScopedFolderAccess?
    private let makeWatchedImportSecurityScope: @MainActor (WatchedImportContext) -> SecurityScopedFolderAccess?
    private let reportTransientError: @MainActor (String) -> Void

    /// Set while a watched-source Review & Import flow is in flight
    /// (preview shown, transfer not yet finished). `startTransfer()`
    /// consumes it instead of building a configuration from Setup, so
    /// the import runs against the context's pinned source/destination
    /// regardless of profile or manual-path state.
    private(set) var activeWatchedImportContext: WatchedImportContext?
    private var completionCancellable: AnyCancellable?

    init(
        preferencesStore: PreferencesStore,
        setupStore: SetupStore,
        historyStore: HistoryStore,
        runSessionStore: RunSessionStore,
        finderService: any FinderServicing,
        showSettingsWindowAction: @escaping @MainActor () -> Void,
        navigate: @escaping @MainActor (AppRoute) -> Void,
        canStartRun: @escaping @MainActor () -> Bool,
        makeSecurityScope: @escaping @MainActor (RunConfiguration) -> SecurityScopedFolderAccess? = { _ in nil },
        makeWatchedImportSecurityScope: @escaping @MainActor (WatchedImportContext) -> SecurityScopedFolderAccess? = { _ in nil },
        reportTransientError: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.preferencesStore = preferencesStore
        self.setupStore = setupStore
        self.historyStore = historyStore
        self.runSessionStore = runSessionStore
        self.finderService = finderService
        self.showSettingsWindowAction = showSettingsWindowAction
        self.navigate = navigate
        self.canStartRun = canStartRun
        self.makeSecurityScope = makeSecurityScope
        self.makeWatchedImportSecurityScope = makeWatchedImportSecurityScope
        self.reportTransientError = reportTransientError

        // A finished (or failed/cancelled) transfer consumes the watched
        // import context; a failed or cancelled preview invalidates it.
        // A successful preview (.dryRunFinished) keeps it alive for the
        // upcoming transfer.
        completionCancellable = runSessionStore.$lastRunCompletion.sink { [weak self] record in
            guard let record else { return }
            Task { @MainActor [weak self] in
                guard let self, self.activeWatchedImportContext != nil else { return }
                if record.mode == .transfer || record.status == .failed || record.status == .cancelled {
                    self.activeWatchedImportContext = nil
                }
            }
        }
    }

    func startPreview() async {
        guard canStartRun() else { return }
        // A Setup-driven preview replaces any pending watched import.
        activeWatchedImportContext = nil
        navigate(.organize(.run))
        let configuration = setupStore.makeConfiguration(preferences: preferencesStore, mode: .preview)
        await runSessionStore.requestRun(
            mode: .preview,
            configuration: configuration,
            securityScope: makeSecurityScope(configuration)
        )
    }

    /// Watched-source Review & Import entry point. Deliberately does NOT
    /// gate on `canStartRun()` (which validates Setup paths) — the
    /// context carries its own validated source and destination.
    func startPreview(importContext: WatchedImportContext) async {
        guard !runSessionStore.isRunning else { return }
        activeWatchedImportContext = importContext
        navigate(.organize(.run))
        let configuration = makeConfiguration(from: importContext, mode: .preview)
        await runSessionStore.requestRun(
            mode: .preview,
            configuration: configuration,
            securityScope: makeWatchedImportSecurityScope(importContext)
        )
    }

    func startTransfer() async {
        if let context = activeWatchedImportContext {
            await startWatchedTransfer(context: context)
            return
        }
        guard canStartRun() else { return }
        navigate(.organize(.run))
        let configuration = setupStore.makeConfiguration(preferences: preferencesStore, mode: .transfer)
        await runSessionStore.requestRun(
            mode: .transfer,
            configuration: configuration,
            securityScope: makeSecurityScope(configuration)
        )
    }

    private func startWatchedTransfer(context: WatchedImportContext) async {
        // Revalidate before mutation: the destination the user is looking
        // at must still be the one the preview targeted. A change cancels
        // with a clear message — it never silently retargets in either
        // direction. (Engine preflight independently re-checks overlap.)
        let activeDestination = setupStore.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.pathsMatch(activeDestination, context.destinationPath) else {
            activeWatchedImportContext = nil
            reportTransientError(
                "The destination changed after this import was previewed. Open Sources and use Review & Import again."
            )
            return
        }
        navigate(.organize(.run))
        let configuration = makeConfiguration(from: context, mode: .transfer)
        await runSessionStore.requestRun(
            mode: .transfer,
            configuration: configuration,
            securityScope: makeWatchedImportSecurityScope(context)
        )
    }

    /// Watched-import runs mirror `SetupStore.makeConfiguration` for all
    /// preference-driven settings, but pin the paths from the context and
    /// never carry a profile name (profile resolution could rewrite them).
    private func makeConfiguration(from context: WatchedImportContext, mode: RunMode) -> RunConfiguration {
        RunConfiguration(
            mode: mode,
            sourcePath: context.sourceURL.path,
            destinationPath: context.destinationPath,
            profileName: nil,
            verifyCopies: preferencesStore.verifyCopies,
            parallelTransferEnabled: preferencesStore.parallelTransferEnabled,
            workerCount: max(1, preferencesStore.workerCount),
            folderStructure: preferencesStore.folderStructure,
            eventSuggestionMode: preferencesStore.smartEventSuggestionsEnabled ? .suggest : .off
        )
    }

    /// Clears a pending watched import (Setup edits, source removal).
    func invalidateWatchedImportContext() {
        activeWatchedImportContext = nil
    }

    private static func pathsMatch(_ a: String, _ b: String) -> Bool {
        URL(fileURLWithPath: a).standardizedFileURL.path == URL(fileURLWithPath: b).standardizedFileURL.path
    }

    func confirmRunPrompt() {
        runSessionStore.confirmPrompt()
    }

    func confirmRunPromptStartFresh() {
        runSessionStore.confirmPromptStartFresh()
    }

    func dismissRunPrompt() {
        runSessionStore.dismissPrompt()
    }

    func cancelRun() {
        runSessionStore.cancelCurrentRun()
    }

    func openDestination() {
        finderService.openPath(runSessionStore.summary?.artifacts.destinationRoot ?? historyStore.destinationRoot)
    }

    func openReport() {
        guard let path = runSessionStore.summary?.artifacts.reportPath else { return }
        finderService.openPath(path)
    }

    func openLogsDirectory() {
        guard let path = runSessionStore.summary?.artifacts.logsDirectoryPath else { return }
        finderService.openPath(path)
    }

    func openSettingsWindow() {
        showSettingsWindowAction()
    }
}
