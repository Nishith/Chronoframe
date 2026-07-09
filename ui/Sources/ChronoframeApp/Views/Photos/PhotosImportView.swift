#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import AppKit
import SwiftUI

/// The Photos destination: authorize, browse albums, select photos and videos,
/// and Review & Import copies of the originals into the active organize
/// destination through the normal preview → consent → verified-transfer flow.
struct PhotosImportView: View {
    @ObservedObject var appState: AppState
    @ObservedObject private var store: PhotosImportStore
    @ObservedObject private var setupStore: SetupStore
    @StateObject private var thumbnailLoader = PhotosThumbnailLoader()

    private let cellSize = CGSize(width: 118, height: 118)

    init(appState: AppState) {
        self.appState = appState
        self._store = ObservedObject(wrappedValue: appState.photosImportStore)
        self._setupStore = ObservedObject(wrappedValue: appState.setupStore)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear { appState.preparePhotosWorkspace() }
        .onDisappear { thumbnailLoader.purgeCache() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: DesignTokens.Layout.inlineSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Import from Photos", bundle: .module)
                    .scaledFont(.cardTitle)
                    .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                Text("Copy photos and videos from your Photos library into your organized library. Your Photos library is never changed.", bundle: .module)
                    .scaledFont(.label)
                    .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(.horizontal, DesignTokens.Layout.contentPadding)
        .padding(.vertical, DesignTokens.Layout.compactPadding)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if store.authorization.allowsReading {
            browser
        } else {
            authorizationGate
        }
    }

    // MARK: - Authorization gate

    private var authorizationGate: some View {
        VStack(spacing: DesignTokens.Layout.inlineSpacing) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .accessibilityHidden(true)
            Text(gateMessageKey, bundle: .module)
                .scaledFont(.body)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 440)
                .fixedSize(horizontal: false, vertical: true)

            if store.authorization.canPromptForAccess {
                Button {
                    Task { await appState.requestPhotosAccess() }
                } label: {
                    Text("Allow Access…", bundle: .module)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityIdentifiers.photosRequestAccessButton)
                .accessibilityLabel(Text("Allow Chronoframe to read your Photos library", bundle: .module))
            } else {
                Button {
                    openPhotosPrivacySettings()
                } label: {
                    Text("Open System Settings", bundle: .module)
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier(AccessibilityIdentifiers.photosOpenSettingsButton)
                .accessibilityLabel(Text("Open Photos privacy settings in System Settings", bundle: .module))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Layout.contentPadding)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(PhotosImportAccessibilityText.authorizationGateLabel(store.authorization))
    }

    private var gateMessageKey: LocalizedStringKey {
        switch store.authorization {
        case .notDetermined:
            return "Chronoframe needs permission to read your Photos library so it can import copies. It only ever reads — it never changes your Photos library."
        case .denied:
            return "Photos access is turned off. Turn it on for Chronoframe in System Settings › Privacy & Security › Photos to import."
        case .restricted:
            return "Photos access is restricted on this Mac and can't be changed here."
        case .authorized, .limited:
            return ""
        }
    }

    // MARK: - Browser

    private var browser: some View {
        VStack(alignment: .leading, spacing: 0) {
            albumBar
            Divider()
            if store.assets.isEmpty {
                emptyAlbum
            } else {
                assetGrid
            }
            Divider()
            footer
        }
    }

    private var albumBar: some View {
        HStack(spacing: DesignTokens.Layout.inlineSpacing) {
            if store.authorization == .limited {
                Label {
                    Text("Showing your selected photos", bundle: .module)
                } icon: {
                    Image(systemName: "checkmark.circle")
                }
                .scaledFont(.label)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
            }
            Picker(selection: albumSelectionBinding) {
                ForEach(store.albums) { album in
                    Text(album.title).tag(album.id)
                }
            } label: {
                Text("Album", bundle: .module)
            }
            .labelsHidden()
            .frame(maxWidth: 280)
            .accessibilityIdentifier(AccessibilityIdentifiers.photosAlbumPicker)
            .accessibilityLabel(Text("Choose an album", bundle: .module))

            Spacer()

            if store.selectedCount > 0 {
                Button {
                    store.clearSelection()
                } label: {
                    Text("Clear Selection", bundle: .module)
                }
                .buttonStyle(.link)
                .accessibilityLabel(Text("Clear the current selection", bundle: .module))
            }
        }
        .padding(.horizontal, DesignTokens.Layout.contentPadding)
        .padding(.vertical, DesignTokens.Layout.inlineSpacing)
    }

    private var albumSelectionBinding: Binding<String> {
        Binding(
            get: { store.selectedAlbumID ?? "" },
            set: { store.selectAlbum(id: $0) }
        )
    }

    private var emptyAlbum: some View {
        VStack(spacing: DesignTokens.Layout.inlineSpacing) {
            Image(systemName: "photo.stack")
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .accessibilityHidden(true)
            Text("This album has no photos or videos to import.", bundle: .module)
                .scaledFont(.body)
                .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(DesignTokens.Layout.contentPadding)
    }

    private var assetGrid: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: cellSize.width, maximum: cellSize.width), spacing: 8)],
                spacing: 8
            ) {
                ForEach(store.assets) { asset in
                    assetButton(asset)
                }
            }
            .padding(DesignTokens.Layout.contentPadding)
        }
    }

    private func assetButton(_ asset: PhotosAssetSummary) -> some View {
        let selected = store.isSelected(asset.id)
        return Button {
            store.toggleSelection(asset.id)
        } label: {
            PhotosAssetCell(asset: asset, isSelected: selected, size: cellSize, loader: thumbnailLoader)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(AccessibilityIdentifiers.photosAssetCell(asset.id))
        .accessibilityLabel(PhotosImportAccessibilityText.assetLabel(asset, isSelected: selected))
        .accessibilityAddTraits(selected ? [.isSelected] : [])
        .onAppear {
            if asset.id == store.assets.last?.id {
                store.loadMoreAssets()
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .center, spacing: DesignTokens.Layout.inlineSpacing) {
            VStack(alignment: .leading, spacing: 2) {
                if let status = store.statusMessage {
                    Text(status)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if destinationPath.isEmpty {
                    Text("Set an organize destination in Organize › Setup first — imports go there.", bundle: .module)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                } else {
                    Text(selectionSummaryKey, bundle: .module)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
            }

            Spacer()

            if store.isPreparingImport {
                ProgressView()
                    .controlSize(.small)
            }

            Button {
                Task { await appState.reviewAndImportSelectedPhotos() }
            } label: {
                Text(importButtonTitleKey, bundle: .module)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!store.canImport || destinationPath.isEmpty)
            .accessibilityIdentifier(AccessibilityIdentifiers.photosImportButton)
            .accessibilityLabel(Text(PhotosImportAccessibilityText.importButtonLabel(selectedCount: store.selectedCount)))
        }
        .padding(.horizontal, DesignTokens.Layout.contentPadding)
        .padding(.vertical, DesignTokens.Layout.compactPadding)
        .background(DesignTokens.ColorSystem.utilityBand)
    }

    private var importButtonTitleKey: LocalizedStringKey {
        store.selectedCount > 0 ? "Review & Import (\(store.selectedCount))" : "Review & Import"
    }

    private var selectionSummaryKey: LocalizedStringKey {
        switch store.selectedCount {
        case 0: return "Select photos or videos to import."
        case 1: return "1 item selected."
        default: return "\(store.selectedCount) items selected."
        }
    }

    private var destinationPath: String {
        setupStore.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func openPhotosPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }
}
