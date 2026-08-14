import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif

/// How much of the free allowance is left, in a workspace (free-trial step 5,
/// T16).
///
/// Renders nothing at all when there is nothing to say — unlocked, unresolved,
/// or an unreadable ledger. `TrialIndicatorModel` owns that decision and is
/// unit-tested; this view only draws the result.
///
/// Meridian: one line of plain text, no badge, no colour-coded pill. The
/// allowance is information, not an advertisement.
struct TrialIndicatorLabel: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var trialStatusStore: TrialStatusStore
    let meter: TrialMeter

    init(appState: AppState, meter: TrialMeter) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._trialStatusStore = ObservedObject(wrappedValue: appState.trialStatusStore)
        self.meter = meter
    }

    private var model: TrialIndicatorModel? {
        TrialIndicatorModel.make(
            status: trialStatusStore.status,
            meter: meter,
            isAppStoreChannel: TrialComposition.isMacAppStoreBuild
        )
    }

    var body: some View {
        // The Group renders nothing when there is no model, but still carries
        // the `.task`. That matters: the first status is `.loading`, which
        // produces no model, so a refresh attached to the visible branch alone
        // would never run and the indicator would never appear.
        Group {
            if let model {
                HStack(spacing: 6) {
                    Text(model.text)
                        .font(.callout)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)

                    if model.isSpent {
                        Button("Unlock") {
                            appState.openLicenseSettings()
                        }
                        .buttonStyle(.link)
                        .accessibilityIdentifier("trialIndicator.unlock")
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
            }
        }
        .task {
            // An unrestricted build has no purchase to resolve and shows no
            // allowance, so asking StoreKit would be a round-trip for an answer
            // that cannot change anything on screen.
            guard TrialComposition.isMacAppStoreBuild else { return }
            await appState.refreshTrialStatus()
        }
        .onChange(of: appState.runSessionStore.lastRunCompletion) { _, _ in
            // The ledger moves when work finishes, and the entitlement does
            // not, so nothing else would prompt a re-read. Covers organize,
            // reorganize and revert.
            guard TrialComposition.isMacAppStoreBuild else { return }
            Task { await appState.refreshTrialStatus() }
        }
        .onChange(of: appState.deduplicateSessionStore.commitSummary) { _, _ in
            guard TrialComposition.isMacAppStoreBuild else { return }
            Task { await appState.refreshTrialStatus() }
        }
    }

    private var identifier: String {
        switch meter {
        case .organize:
            return "trialIndicator.organize"
        case .dedupe:
            return "trialIndicator.dedupe"
        }
    }
}
