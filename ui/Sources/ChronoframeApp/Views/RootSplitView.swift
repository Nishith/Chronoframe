#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

struct RootSplitView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var setupStore: SetupStore
    @ObservedObject private var runSessionStore: RunSessionStore

    init(appState: AppState) {
        self.appState = appState
        self._setupStore = ObservedObject(wrappedValue: appState.setupStore)
        self._runSessionStore = ObservedObject(wrappedValue: appState.runSessionStore)
    }

    var body: some View {
        NavigationSplitView {
            SidebarView(appState: appState)
                .navigationSplitViewColumnWidth(
                    min: DesignTokens.Sidebar.minWidth,
                    ideal: DesignTokens.Sidebar.idealWidth,
                    max: DesignTokens.Sidebar.maxWidth
                )
        } detail: {
            detailView
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if runSessionStore.isRunning {
                    Button(role: .destructive) {
                        appState.cancelRun()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            }
        }
        .alert(
            runSessionStore.prompt?.title ?? "Chronoframe",
            isPresented: Binding(
                get: { runSessionStore.prompt != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.dismissRunPrompt()
                    }
                }
            )
        ) {
            switch runSessionStore.prompt?.kind {
            case .confirmTransfer:
                Button("Start Copying") {
                    appState.confirmRunPrompt()
                }
                Button("Cancel", role: .cancel) {
                    appState.dismissRunPrompt()
                }
            case .resumePendingJobs:
                Button("Resume") {
                    appState.confirmRunPrompt()
                }
                Button("Start Over") {
                    appState.confirmRunPromptStartFresh()
                }
                Button("Cancel", role: .cancel) {
                    appState.dismissRunPrompt()
                }
            case .blockingError, .none:
                Button("OK", role: .cancel) {
                    appState.dismissRunPrompt()
                }
            }
        } message: {
            Text(runSessionStore.prompt?.message ?? "")
        }
        .alert(
            "Chronoframe Needs Attention",
            isPresented: Binding(
                get: { appState.transientErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.dismissTransientError()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                appState.dismissTransientError()
            }
        } message: {
            Text(appState.transientErrorMessage ?? "")
        }
        .sheet(
            isPresented: Binding(
                get: { appState.unlockRefusal != nil },
                set: { isPresented in
                    if !isPresented {
                        appState.dismissUnlockSheet()
                    }
                }
            )
        ) {
            if let refusal = appState.unlockRefusal {
                UnlockSheet(
                    refusal: refusal,
                    entitlementStore: appState.entitlementStore,
                    offeredBatch: appState.offeredFreeTestBatch,
                    onUnlocked: { Task { await appState.retryAfterUnlock() } },
                    onRunFreeTestBatch: { Task { await appState.runOfferedFreeTestBatch() } },
                    onDismiss: { appState.dismissUnlockSheet() }
                )
            }
        }
        .onAppear {
            #if DEBUG
            UITestScenario.configureCurrentWindow(for: UITestScenario.current())
            #endif
        }
        .task {
            // Post-launch async hook: watched-source activation does
            // filesystem work (bookmark resolution, catch-up scans) and
            // must never run inside AppState.init.
            await appState.startWatchingSources()
        }
    }

    @ViewBuilder
    private var detailView: some View {
        switch appState.selection {
        case .organize:
            OrganizeContainerView(appState: appState)
        case .photos:
            PhotosImportView(appState: appState,
                onResume: { Task { await appState.resumeInterruptedPhotosImport() } },
                currentDestination: { appState.currentDestinationCapture() }
            )
        case .deduplicate:
            DeduplicateView(appState: appState)
        case .guardian:
            GuardianView(appState: appState)
        case .profiles:
            ProfilesView(appState: appState)
        case .nasLibrary:
            NASLibraryView(appState: appState)
        }
    }
}
