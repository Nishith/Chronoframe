#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import SwiftUI

/// Hosts the Setup, Run, and Run History sub-tabs under the unified Organize
/// sidebar destination. Each sub-tab continues to render the existing view
/// unchanged; this container only owns the segmented picker and the routing.
struct OrganizeContainerView: View {
    @ObservedObject var appState: AppState

    init(appState: AppState) {
        self.appState = appState
    }

    /// Each organize workspace already carries its own primary action and
    /// status. Keeping an additional banner in the top chrome competes with
    /// the tab strip and navigation title at constrained widths.
    static func showsNextActionBanner(setupIsIncomplete: Bool) -> Bool {
        false
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer(minLength: 0)
                WorkspaceTabStrip(
                    selection: $appState.organizeSubSelection,
                    tabs: OrganizeSubSection.allCases,
                    title: { $0.title },
                    systemImage: { $0.systemImage },
                    accessibilityIdentifier: { "organizeTab.\($0.rawValue)" }
                )
                .frame(width: 360)
            }
            .padding(.horizontal, DesignTokens.Layout.contentPadding)
            .padding(.vertical, DesignTokens.Spacing.sm)
            .background(DesignTokens.ColorSystem.utilityBand)

            Divider()

            content
        }
        .navigationTitle("Organize")
    }

    @ViewBuilder
    private var content: some View {
        switch appState.organizeSubSelection {
        case .setup:
            SetupView(appState: appState)
        case .run:
            CurrentRunView(appState: appState)
        case .health:
            HealthDashboardView(appState: appState)
        case .history:
            RunHistoryView(appState: appState)
        }
    }
}
