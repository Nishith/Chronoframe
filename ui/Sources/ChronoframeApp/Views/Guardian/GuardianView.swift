#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// The Library Guardian workspace: scan the organized library for bit rot, make
/// explicit trust decisions, keep a verified mirror, and restore damaged files
/// from that mirror. Gated behind `GuardianCapability.isEnabled`, so it is only
/// reachable once the sidebar destination is shown.
///
/// The view holds no Guardian logic of its own — every action goes through
/// `AppState`, which pins the library and mirror at action time and delegates to
/// the off-main-actor `GuardianEngine`.
struct GuardianView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var store: GuardianStore

    init(appState: AppState) {
        self.appState = appState
        self._store = ObservedObject(wrappedValue: appState.guardianStore)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if appState.guardianLibraryPath.isEmpty {
                    unconfiguredNotice
                } else {
                    scanCard
                    if let summary = store.lastScanSummary {
                        summaryCard(summary)
                    }
                    if !reviewableFindings.isEmpty {
                        findingsCard
                    }
                    mirrorCard
                    restoreCard
                }

                if let message = store.statusMessage {
                    Text(verbatim: message)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Guardian")
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Library Guardian")
                .scaledFont(.title, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            Text("Detect silent bit rot, keep a verified mirror, and restore damaged files.")
                .scaledFont(.body)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
        }
    }

    private var unconfiguredNotice: some View {
        card {
            Text("Choose an Organize destination first")
                .scaledFont(.body, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            Text("Guardian protects an already-organized library. Set a destination in Organize, then return here to scan it.")
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
        }
    }

    private var scanCard: some View {
        card {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Library")
                        .scaledFont(.label, weight: .semibold)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    Text(verbatim: URL(fileURLWithPath: appState.guardianLibraryPath).lastPathComponent)
                        .scaledFont(.body, weight: .medium)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                }
                Spacer()
                if store.isScanning {
                    ProgressView().controlSize(.small)
                    Button("Cancel") { store.cancelScan() }
                } else {
                    Button("Scan now") { Task { await appState.scanGuardianLibrary() } }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func summaryCard(_ summary: GuardianStore.ScanSummary) -> some View {
        card {
            Text("Last scan")
                .scaledFont(.label, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            HStack(spacing: 16) {
                metric("\(summary.verified)", "verified")
                metric("\(summary.corrupt)", "bit rot")
                metric("\(summary.missing)", "missing")
                metric("\(summary.newFiles)", "new")
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(GuardianAccessibilityText.scanSummary(summary))
            if summary.partialScan {
                Text("Some folders couldn't be read, so this scan is incomplete.")
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
        }
    }

    private var findingsCard: some View {
        card {
            Text("Needs review")
                .scaledFont(.body, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            ForEach(reviewableFindings, id: \.relativePath) { finding in
                Button {
                    store.toggleTrustSelection(finding.relativePath)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: store.selectedTrustPaths.contains(finding.relativePath) ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(DesignTokens.ColorSystem.accentAction)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(verbatim: URL(fileURLWithPath: finding.relativePath).lastPathComponent)
                                .scaledFont(.body)
                                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                            Text(verbatim: statusLabel(finding.status))
                                .scaledFont(.label)
                                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(GuardianAccessibilityText.finding(finding))
            }
            HStack {
                Button("Accept as trusted") { Task { await appState.acceptGuardianTrust() } }
                    .disabled(store.selectedTrustPaths.isEmpty)
                Button("Acknowledge deletion") { Task { await appState.acknowledgeGuardianDeletions() } }
                    .disabled(store.selectedTrustPaths.isEmpty)
            }
        }
    }

    private var mirrorCard: some View {
        card {
            Text("Verified mirror")
                .scaledFont(.body, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            if appState.guardianMirrorPath.isEmpty {
                Text("No mirror configured. Choose a second volume to hold a bit-for-bit copy.")
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            } else {
                Text(verbatim: appState.guardianMirrorPath)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            HStack {
                Button("Choose mirror…") { Task { await appState.chooseGuardianMirrorFolder() } }
                if store.isMirroring {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Mirror now") { Task { await appState.runGuardianMirror() } }
                        .disabled(appState.guardianMirrorPath.isEmpty || store.report == nil)
                }
            }
        }
    }

    private var restoreCard: some View {
        card {
            Text("Restore from mirror")
                .scaledFont(.body, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            if let plan = store.restorePlan {
                if plan.restorable.isEmpty {
                    Text("Nothing can be safely restored — the mirror has no verified copy of the damaged files.")
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                } else {
                    ForEach(plan.restorable, id: \.relativePath) { action in
                        Button {
                            store.toggleRestoreSelection(action.relativePath)
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: store.selectedRestorePaths.contains(action.relativePath) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(DesignTokens.ColorSystem.accentAction)
                                Text(verbatim: URL(fileURLWithPath: action.relativePath).lastPathComponent)
                                    .scaledFont(.body)
                                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                                Spacer()
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(GuardianAccessibilityText.restoreAction(action, isSelected: store.selectedRestorePaths.contains(action.relativePath)))
                    }
                    Button("Restore selected") { Task { await appState.runGuardianRestore() } }
                        .disabled(store.selectedRestorePaths.isEmpty || store.isRestoring)
                }
            } else {
                Button("Review restore") { Task { await appState.prepareGuardianRestore() } }
                    .disabled(appState.guardianMirrorPath.isEmpty || store.report == nil)
            }
        }
    }

    // MARK: - Helpers

    private var reviewableFindings: [GuardianIntegrityFinding] {
        guard let report = store.report else { return [] }
        return report.findings.filter {
            $0.status == .corrupt || $0.status == .modified || $0.status == .missing || $0.status == .new
        }
    }

    private func statusLabel(_ status: GuardianIntegrityStatus) -> String {
        switch status {
        case .corrupt: return "Suspected bit rot"
        case .modified: return "Changed since trusted"
        case .missing: return "Missing"
        case .new: return "New, not yet trusted"
        case .verified: return "Verified"
        case .dataless: return "In iCloud, skipped"
        case .unreadable: return "Couldn't read"
        case .changedDuringScan: return "Changed during scan"
        }
    }

    private func metric(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: value)
                .scaledFont(.title, weight: .semibold)
                .monospacedDigit()
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            Text(verbatim: label)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
        }
    }

    @ViewBuilder
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignTokens.ColorSystem.utilityBand)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(DesignTokens.ColorSystem.hairline, lineWidth: 0.5)
            )
    }
}
