#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// The library's name and share, the "Assess only" badge, the single-Mac note, and the
/// buttons that fit the current state.
struct NASLibraryHeaderView: View {
    let library: NASLibraryRecord?
    let actions: [NASLibraryViewModel.Action]
    let startTitle: String
    let perform: (NASLibraryViewModel.Action) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(verbatim: library?.displayName ?? "")
                        .scaledFont(.title, weight: .semibold)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                        .lineLimit(1)
                    Text(LocalizedStringKey(NASLibraryCopy.modeBadge), bundle: .module)
                        .scaledFont(.label, weight: .semibold)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(DesignTokens.ColorSystem.hairline, lineWidth: 1)
                        )
                }
                if let location {
                    Text(verbatim: location)
                        .scaledFont(.body)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Text(LocalizedStringKey(NASLibraryCopy.singleMacNote), bundle: .module)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
            Spacer(minLength: 12)
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    actionButton(action)
                }
            }
        }
    }

    /// "<server>/<share>", which names the library without showing a local mount path.
    private var location: String? {
        guard let volume = library?.lastObservation.volume else { return nil }
        let parts = [volume.serverHost, volume.shareName].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: "/")
    }

    @ViewBuilder
    private func actionButton(_ action: NASLibraryViewModel.Action) -> some View {
        switch action {
        case .chooseFolder:
            button(NASLibraryCopy.chooseButton, AccessibilityIdentifiers.NAS.chooseFolder, action)
        case .startAssessment:
            button(startTitle, AccessibilityIdentifiers.NAS.startAssessment, action)
        case .stop:
            button(NASLibraryCopy.stopButton, AccessibilityIdentifiers.NAS.stop, action)
        case .reconnect:
            button(NASLibraryCopy.reconnectButton, AccessibilityIdentifiers.NAS.reconnect, action)
        case .confirmIdentity:
            button(NASLibraryCopy.confirmButton, AccessibilityIdentifiers.NAS.confirmIdentity, action)
        case .select, .chooseKeeper, .loadPreview:
            EmptyView() // These belong to a group and are shown in the group views.
        }
    }

    private func button(_ title: String, _ identifier: String, _ action: NASLibraryViewModel.Action) -> some View {
        Button {
            perform(action)
        } label: {
            Text(LocalizedStringKey(title), bundle: .module)
        }
        .nasControl(identifier, visibleTitle: title)
    }
}
