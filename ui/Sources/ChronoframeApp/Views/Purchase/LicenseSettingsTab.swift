import SwiftUI
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif

/// Settings → License (free-trial step 5, T14).
///
/// Shows entitlement state, what is left of the free allowance, and Restore
/// Purchases. Like the unlock sheet, the wording is decided by a pure model
/// (`LicenseStatusModel`) so the distinction that matters — an unreadable
/// ledger is not a spent trial, though both read as zero — is unit-tested
/// rather than eyeballed here.
struct LicenseSettingsTab: View {
    @ObservedObject var appState: AppState
    @ObservedObject var entitlementStore: EntitlementStore
    @ObservedObject private var trialStatusStore: TrialStatusStore

    init(appState: AppState, entitlementStore: EntitlementStore) {
        self._appState = ObservedObject(wrappedValue: appState)
        self._entitlementStore = ObservedObject(wrappedValue: entitlementStore)
        self._trialStatusStore = ObservedObject(wrappedValue: appState.trialStatusStore)
    }

    private var model: LicenseStatusModel {
        LicenseStatusModel.make(status: trialStatusStore.status)
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("Status") {
                    Text(model.headline)
                }
                if !model.detail.isEmpty {
                    Text(model.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if !model.allowanceRows.isEmpty {
                Section("Free allowance") {
                    ForEach(model.allowanceRows, id: \.label) { row in
                        LabeledContent(row.label) {
                            Text(row.value)
                        }
                    }
                }
            }

            if model.showsRestore {
                Section {
                    HStack {
                        Button("Restore Purchases") {
                            Task {
                                await entitlementStore.restore()
                                await appState.refreshTrialStatus()
                            }
                        }
                        .disabled(entitlementStore.isRestoring)
                        .accessibilityIdentifier("license.restore")

                        if entitlementStore.isRestoring {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    if let statusMessage = entitlementStore.statusMessage {
                        Text(statusMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("license.status")
                    }
                }
            }
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings.license")
        .task {
            await appState.refreshTrialStatus()
        }
        .onChange(of: entitlementStore.state) { _, _ in
            // A refund or Family Sharing revocation arriving through the
            // transaction observer changes what this pane should say, and the
            // allowance has to be re-read to say it.
            Task { await appState.refreshTrialStatus() }
        }
    }
}
