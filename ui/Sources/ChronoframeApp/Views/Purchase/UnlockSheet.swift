import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif

/// Offered when a run was refused (free-trial step 5, T13).
///
/// Deliberately thin. Everything that decides what to show lives in
/// `UnlockSheetModel`, which is a pure function and is unit-tested; this view
/// renders it and forwards taps. The rules worth getting right — never showing
/// a hardcoded price, never inviting a second purchase from someone whose
/// existing one merely could not be confirmed — are enforced there.
///
/// Meridian: native controls, no gradients, no text explaining what a button
/// obviously does.
struct UnlockSheet: View {
    let refusal: TrialAuthorizationRefusal
    @ObservedObject var entitlementStore: EntitlementStore
    /// Called once the entitlement actually resolves to unlocked. The caller
    /// re-runs preflight and planning from scratch — see `AppState`.
    let onUnlocked: () -> Void
    let onDismiss: () -> Void

    /// Local, because `loadProduct()` publishes only its result. "Still
    /// loading" and "load failed" both leave `product` nil, and they call for
    /// different UI: a spinner versus a Retry button.
    @State private var isLoadingProduct = true

    private var model: UnlockSheetModel {
        UnlockSheetModel.make(
            refusal: refusal,
            product: entitlementStore.product,
            isLoadingProduct: isLoadingProduct,
            isPurchasing: entitlementStore.isPurchasing,
            isRestoring: entitlementStore.isRestoring
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(model.title)
                .font(.headline)

            Text(model.message)
                .fixedSize(horizontal: false, vertical: true)

            if let statusMessage = entitlementStore.statusMessage {
                Text(statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("unlockSheet.status")
            }

            if model.isBusy {
                ProgressView()
                    .controlSize(.small)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                ForEach(Array(model.actions.enumerated()), id: \.offset) { _, action in
                    button(for: action)
                }
            }
        }
        .padding(20)
        .frame(width: 420)
        .accessibilityIdentifier("unlockSheet")
        .task {
            await reloadProduct()
        }
        .onChange(of: entitlementStore.state) { _, state in
            // Fires for a purchase AND for a successful restore, which is the
            // point: both end with an unlocked entitlement and both should let
            // the run proceed.
            if state.isUnlocked {
                onUnlocked()
            }
        }
    }

    @ViewBuilder
    private func button(for action: UnlockSheetAction) -> some View {
        switch action {
        case let .buy(displayName, displayPrice):
            Button("\(displayName) · \(displayPrice)") {
                Task { await entitlementStore.purchase() }
            }
            .keyboardShortcut(.defaultAction)
            .disabled(model.isBusy)
            .accessibilityIdentifier("unlockSheet.buy")

        case .retryProductLoad:
            Button("Try Again") {
                Task { await reloadProduct() }
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("unlockSheet.retry")

        case .restore:
            Button("Restore Purchases") {
                Task { await entitlementStore.restore() }
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("unlockSheet.restore")

        case .dismiss:
            Button("Not Now", role: .cancel) {
                onDismiss()
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("unlockSheet.dismiss")
        }
    }

    private func reloadProduct() async {
        isLoadingProduct = true
        await entitlementStore.loadProduct()
        isLoadingProduct = false
    }
}
