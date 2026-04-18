#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

struct CurrentRunView: View {
    let appState: AppState
    @ObservedObject private var runSessionStore: RunSessionStore
    @ObservedObject private var runLogStore: RunLogStore
    @ObservedObject private var historyStore: HistoryStore
    @State private var workspaceTab: RunWorkspaceTab = .overview

    init(appState: AppState) {
        self.appState = appState
        self._runSessionStore = ObservedObject(wrappedValue: appState.runSessionStore)
        self._runLogStore = ObservedObject(wrappedValue: appState.runLogStore)
        self._historyStore = ObservedObject(wrappedValue: appState.historyStore)
    }

    private var model: RunWorkspaceModel {
        RunWorkspaceModel(
            runSessionStore: runSessionStore,
            runLogStore: runLogStore,
            historyStore: historyStore,
            canStartRun: appState.canStartRun
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DesignTokens.Layout.sectionSpacing) {
                RunHeroSection(model: model, workspaceTab: $workspaceTab, appState: appState)

                if model.showsPreviewReview {
                    RunPreviewReviewSection(
                        model: model,
                        startTransfer: { Task { await appState.startTransfer() } }
                    )
                }

                RunMetricsGridSection(model: model)

                RunWorkspaceShell(
                    model: model,
                    workspaceTab: $workspaceTab,
                    appState: appState
                )
            }
            .padding(DesignTokens.Layout.contentPadding)
            .frame(maxWidth: DesignTokens.Layout.contentMaxWidth, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Run")
    }
}
