#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import SwiftUI

/// One group of identical files: a placeholder tile with a Load Preview button, the
/// members, and the keeper choice. The choice is a note on this Mac; nothing in this view
/// changes a file on the NAS.
struct NASExactGroupDetailView: View {
    @ObservedObject var store: NASWorkspaceStore
    let viewModel: NASLibraryViewModel
    @ObservedObject var previewLoader: NASPreviewLoader

    var body: some View {
        if let group = viewModel.selectedGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(verbatim: group.memberRelativePaths.sorted().first.map(Self.fileName) ?? "")
                        .scaledFont(.title, weight: .semibold)
                        .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                    Text(verbatim: NASLibraryCopy.redundantBytesLabel(bytes: group.redundantLogicalBytes))
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    previewTile(group)
                    keeperSection(group)
                }
                .padding(.horizontal, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            Color.clear
        }
    }

    // MARK: Preview

    private func previewTile(_ group: NASExactGroup) -> some View {
        let size = NASPreviewLoader.previewSize
        let image = previewLoader.cachedImage(forDigest: group.digest)
        return VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous)
                    .fill(DesignTokens.ColorSystem.imageStage)
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: DesignTokens.Corner.innerCard, style: .continuous))
                        .accessibilityHidden(true)
                } else if previewLoader.loadingDigests.contains(group.digest) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: group.kind == .video ? "film" : "photo")
                        .font(.system(size: 36, weight: .regular))
                        .foregroundStyle(DesignTokens.ColorSystem.textOnImageStage)
                        .accessibilityHidden(true)
                }
            }
            .frame(width: size.width, height: size.height)

            if image == nil {
                HStack(spacing: 12) {
                    Button {
                        Task { await viewModel.loadPreview(for: group) }
                    } label: {
                        Text(LocalizedStringKey(NASLibraryCopy.loadPreviewButton), bundle: .module)
                    }
                    .disabled(previewLoader.loadingDigests.contains(group.digest))
                    .nasControl(AccessibilityIdentifiers.NAS.loadPreview)

                    if previewLoader.failedDigests.contains(group.digest) {
                        Text(LocalizedStringKey(NASLibraryCopy.previewUnavailable), bundle: .module)
                            .scaledFont(.label)
                            .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    }
                }
                Text(LocalizedStringKey(NASLibraryCopy.previewCaption), bundle: .module)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
        }
    }

    // MARK: Keeper

    private func keeperSection(_ group: NASExactGroup) -> some View {
        let stale = store.isChoiceStale(group)
        return VStack(alignment: .leading, spacing: 8) {
            if stale {
                Text(LocalizedStringKey(NASLibraryCopy.keeperStale), bundle: .module)
                    .scaledFont(.body)
                    .foregroundStyle(DesignTokens.ColorSystem.statusWarning)
            }
            Picker(selection: keeperBinding(group, isStale: stale)) {
                Text(LocalizedStringKey(NASLibraryCopy.keeperNone), bundle: .module)
                    .tag(String?.none)
                ForEach(group.memberRelativePaths.sorted(), id: \.self) { path in
                    Text(verbatim: path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .tag(Optional(path))
                }
            } label: {
                EmptyView()
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .nasControl(AccessibilityIdentifiers.NAS.keeperPicker)

            Text(LocalizedStringKey(NASLibraryCopy.keeperCaption), bundle: .module)
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
        }
    }

    private func keeperBinding(_ group: NASExactGroup, isStale: Bool) -> Binding<String?> {
        Binding(
            get: { isStale ? nil : store.snapshot?.choices[group.digest]?.keeperRelativePath },
            set: { viewModel.chooseKeeper(digest: group.digest, relativePath: $0) }
        )
    }

    private static func fileName(_ relativePath: String) -> String {
        relativePath.split(separator: "/").last.map(String.init) ?? relativePath
    }
}
