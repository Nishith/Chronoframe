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
    /// A smaller run the remaining allowance covers, when one was offered (T15).
    var offeredBatch: FreeTestBatch?
    /// Called once the entitlement actually resolves to unlocked. The caller
    /// re-runs preflight and planning from scratch — see `AppState`.
    let onUnlocked: () -> Void
    /// Run the batch shown above the buttons. The caller re-runs preflight and
    /// planning, then copies only the files this sheet listed.
    var onRunFreeTestBatch: () -> Void = {}
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
            isRestoring: entitlementStore.isRestoring,
            offeredBatch: offeredBatch
        )
    }

    /// Rendered above the buttons rather than beside them, because it comes
    /// with the file list it is promising.
    private var batchAction: UnlockSheetAction? {
        model.actions.first { if case .runFreeTestBatch = $0 { return true } else { return false } }
    }

    private var buttonRowActions: [UnlockSheetAction] {
        model.actions.filter { if case .runFreeTestBatch = $0 { return false } else { return true } }
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

            if let batchAction, let detail = model.batchDetail, let batch = offeredBatch {
                Divider()
                freeTestBatchOffer(action: batchAction, detail: detail, batch: batch)
            }

            Divider()

            HStack(spacing: 10) {
                Spacer()
                ForEach(Array(buttonRowActions.enumerated()), id: \.offset) { _, action in
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

        case .runFreeTestBatch:
            // Rendered by `freeTestBatchOffer`, which shows the files first.
            EmptyView()

        case .dismiss:
            Button("Not Now", role: .cancel) {
                onDismiss()
            }
            .disabled(model.isBusy)
            .accessibilityIdentifier("unlockSheet.dismiss")
        }
    }

    /// The offer, and the exact plan it would run.
    ///
    /// The list is the point: settled policy is that a reduced plan is shown in
    /// full and confirmed before anything is copied, never silently truncated.
    /// Pressing the button below is that confirmation, so the files it covers
    /// have to be visible from here.
    @ViewBuilder
    private func freeTestBatchOffer(
        action: UnlockSheetAction,
        detail: String,
        batch: FreeTestBatch
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(detail)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Show these \(batch.includedCount) files") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(batch.included, id: \.sourcePath) { transfer in
                            Text(transfer.sourcePath)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 4)
                }
                .frame(maxHeight: 160)
            }
            .accessibilityIdentifier("unlockSheet.batchFiles")

            if case let .runFreeTestBatch(fileCount, _) = action {
                Button("Copy These \(fileCount) Files") {
                    onRunFreeTestBatch()
                }
                .disabled(!model.isBatchEnabled)
                .accessibilityIdentifier("unlockSheet.runBatch")
            }
        }
    }

    private func reloadProduct() async {
        isLoadingProduct = true
        await entitlementStore.loadProduct()
        isLoadingProduct = false
    }
}
