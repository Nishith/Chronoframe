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
    /// Applied only when something renders, so an absent indicator leaves no
    /// padding behind. Callers inside an already-padded container pass none.
    let insets: EdgeInsets

    init(appState: AppState, meter: TrialMeter, insets: EdgeInsets = EdgeInsets()) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._trialStatusStore = ObservedObject(wrappedValue: appState.trialStatusStore)
        self.meter = meter
        self.insets = insets
    }

    private var model: TrialIndicatorModel? {
        TrialIndicatorModel.make(
            status: trialStatusStore.status,
            meter: meter,
            isAppStoreChannel: TrialComposition.isMacAppStoreBuild
        )
    }

    var body: some View {
        // No Group, and no modifiers on an empty branch: when there is nothing
        // to say this must contribute *nothing* to layout, including a parent
        // stack's spacing. That is why the status refresh lives on the
        // workspace views rather than here — a `.task` would need a real view
        // to hang on, and the first status is always `.loading`, which renders
        // nothing.
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
            .padding(insets)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
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
