#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import SwiftUI

// MARK: - Copy

/// The words of the NAS Library workspace (C-13). The constants are the English text and
/// double as localization keys: views render them through
/// `Text(LocalizedStringKey(...), bundle: .module)`.
enum NASLibraryCopy {
    static let emptyTitle = "Assess a photo library on your NAS"
    static let emptyBody = "Choose the top folder of your collection. Chronoframe reads it to find identical copies and changes nothing on the NAS."
    static let chooseButton = "Choose Folder…"
    static let startButton = "Assess Library"
    static let rescanButton = "Assess Again"
    static let stopButton = "Stop"
    static let reconnectButton = "Reconnect"
    static let confirmButton = "This Is the Same Library"
    static let loadPreviewButton = "Load Preview"
    static let modeBadge = "Assess only"
    static let singleMacNote = "Use one Mac at a time for Chronoframe changes on this NAS."
    static let checking = "Checking the connection to your NAS…"
    static let waiting = "Waiting for your NAS. Reconnect the share, then choose Reconnect. Nothing was changed."
    static let confirm = "This share looks slightly different (for example, a new network name). Confirm it's the same library to keep your saved choices."
    static let different = "This isn't the library you assessed before. Choose the folder again to start a new assessment."
    static let stopping = "Stopping… Chronoframe is finishing the file it's reading."
    static let complete = "Assessment complete. Every included folder was checked."
    static let incomplete = "Assessment incomplete. Some folders or files couldn't be read, so this isn't a full picture."
    static let cancelled = "Assessment stopped. Results so far are saved; assess again to finish."
    static let redundantFormat = "%@ in identical extra copies (logical size, not space freed)"
    static let keeperCaption = "Your choice is saved on this Mac. Chronoframe doesn't delete or move files on a NAS in this version."
    static let keeperNone = "No choice yet"
    static let keeperStale = "Your earlier choice no longer matches these files. Choose again."
    static let previewCaption = "Loading a preview may read the whole file over the network."
    static let issuesTitle = "Not checked"

    // Wording for places C-13 gives no fixed text (D-NAS-130).
    static let ready = "Ready to assess. Chronoframe reads this library to find identical copies and changes nothing on the NAS."
    static let enumerating = "Looking through your folders…"
    static let hashing = "Comparing files that look alike…"
    static let grouping = "Grouping identical copies…"
    static let summaryTitle = "Folder summary"
    static let previewUnavailable = "A preview couldn't be made for this file."
    static let groupsTitle = "Identical copies"

    /// The text of the state banner for each workspace state.
    static func bannerText(for state: NASWorkspaceState) -> String {
        switch state {
        case .noLibrary:
            return emptyBody
        case .checkingConnection:
            return checking
        case .needsIdentityConfirmation:
            return confirm
        case .differentFolder:
            return different
        case .waitingForNAS:
            return waiting
        case .ready:
            return ready
        case let .assessing(phase):
            switch phase {
            case .enumerating: return enumerating
            case .hashing: return hashing
            case .grouping: return grouping
            }
        case .stopping:
            return stopping
        case .completeAssessment:
            return complete
        case let .incompleteAssessment(outcome):
            return outcome == .cancelled ? cancelled : incomplete
        case let .failed(message):
            return message
        }
    }

    /// "<size> in identical extra copies (logical size, not space freed)".
    static func redundantBytesLabel(bytes: Int64) -> String {
        let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        let format = String(localized: String.LocalizationValue(redundantFormat), bundle: Bundle.module)
        return String(format: format, size)
    }

    /// The title of the assessment button: first time versus another pass.
    static func startTitle(for state: NASWorkspaceState) -> String {
        switch state {
        case .completeAssessment, .incompleteAssessment: return rescanButton
        default: return startButton
        }
    }
}

// MARK: - View model

/// What the workspace can do. Every action either reads the NAS, saves a note on this
/// Mac, or opens a picker; none of them changes a file on the NAS (INV-27).
@MainActor
final class NASLibraryViewModel: ObservableObject {
    enum Action: String, CaseIterable {
        case chooseFolder
        case startAssessment
        case stop
        case reconnect
        case confirmIdentity
        case select
        case chooseKeeper
        case loadPreview
    }

    let store: NASWorkspaceStore
    let previewLoader: NASPreviewLoader

    init(store: NASWorkspaceStore, previewLoader: NASPreviewLoader = NASPreviewLoader()) {
        self.store = store
        self.previewLoader = previewLoader
    }

    /// The header buttons offered in each state, in order. A different folder offers only
    /// Choose Folder, because nothing saved carries over to it.
    static func visibleActions(for state: NASWorkspaceState, hasLibrary: Bool) -> [Action] {
        switch state {
        case .noLibrary:
            return [.chooseFolder]
        case .checkingConnection, .stopping:
            return []
        case .needsIdentityConfirmation:
            return [.confirmIdentity, .chooseFolder]
        case .differentFolder:
            return [.chooseFolder]
        case .waitingForNAS:
            return [.reconnect, .chooseFolder]
        case .ready, .completeAssessment, .incompleteAssessment:
            return [.startAssessment, .chooseFolder]
        case .assessing:
            return [.stop]
        case .failed:
            return hasLibrary ? [.reconnect, .chooseFolder] : [.chooseFolder]
        }
    }

    var visibleActions: [Action] {
        Self.visibleActions(for: store.state, hasLibrary: store.library != nil)
    }

    /// Loads the saved library the first time the workspace appears. It reads nothing for display.
    func viewDidAppear() async {
        if store.state == .noLibrary, store.library == nil {
            await store.loadSavedLibrary()
        }
    }

    func perform(_ action: Action) async {
        switch action {
        case .chooseFolder: await store.chooseLibrary()
        case .startAssessment: store.startAssessment()
        case .stop: store.stop()
        case .reconnect: await store.reconnect()
        case .confirmIdentity: await store.confirmIdentity()
        case .select, .chooseKeeper, .loadPreview:
            break // These take a group; the views call the methods below directly.
        }
    }

    var selectedGroup: NASExactGroup? {
        guard let digest = store.snapshot?.selectedDigest else { return nil }
        return store.snapshot?.groups.first { $0.digest == digest }
    }

    func select(digest: String?) {
        store.select(digest: digest)
    }

    func chooseKeeper(digest: String, relativePath: String?) {
        store.chooseKeeper(digest: digest, relativePath: relativePath)
    }

    /// The file a preview would show: the group's first member by sorted path.
    func previewURL(for group: NASExactGroup) -> URL? {
        guard let library = store.library, let first = group.memberRelativePaths.sorted().first else { return nil }
        let volume = library.lastObservation.volume
        let mountPoint = volume.mountPoint.isEmpty ? library.bookmark.path : volume.mountPoint
        var root = URL(fileURLWithPath: mountPoint, isDirectory: true)
        if !volume.mountPoint.isEmpty, !library.lastObservation.rootRelativePath.isEmpty {
            root = root.appendingPathComponent(library.lastObservation.rootRelativePath, isDirectory: true)
        }
        root = root.standardizedFileURL
        let url = root.appendingPathComponent(first, isDirectory: false).standardizedFileURL
        // A member path that climbs out of the library root is never read.
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else { return nil }
        return url
    }

    /// The only path to a preview. The store records the request (and refuses it outside a
    /// finished assessment); the loader renders once and caches.
    func loadPreview(for group: NASExactGroup) async {
        store.requestPreview(digest: group.digest)
        guard store.previewRequestedDigests.contains(group.digest), let url = previewURL(for: group) else { return }
        await previewLoader.render(digest: group.digest, url: url)
    }
}

// MARK: - View

/// The NAS Library workspace: assess a photo library on a network share, review groups of
/// identical files, and keep notes about which copy to keep. Gated behind
/// `NASCapability.isEnabled`, so it is only reachable once the sidebar destination shows.
///
/// Nothing here deletes, moves or trashes anything on the NAS.
struct NASLibraryView: View {
    static let navigationTitle = "NAS Library"

    @ObservedObject var appState: AppState
    @ObservedObject private var store: NASWorkspaceStore
    @StateObject private var viewModel: NASLibraryViewModel

    init(appState: AppState) {
        self.appState = appState
        self._store = ObservedObject(wrappedValue: appState.nasWorkspaceStore)
        self._viewModel = StateObject(wrappedValue: NASLibraryViewModel(store: appState.nasWorkspaceStore))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if store.state == .noLibrary, store.library == nil {
                emptyState
            } else {
                NASLibraryHeaderView(
                    library: store.library,
                    actions: viewModel.visibleActions,
                    startTitle: NASLibraryCopy.startTitle(for: store.state),
                    perform: { action in Task { await viewModel.perform(action) } }
                )
                banner
                progressRow
                if showsResults, let snapshot = store.snapshot {
                    NASFolderSummaryView(snapshot: snapshot)
                    HStack(alignment: .top, spacing: 16) {
                        NASExactGroupListView(store: store, viewModel: viewModel)
                            .frame(width: 320)
                        NASExactGroupDetailView(store: store, viewModel: viewModel, previewLoader: viewModel.previewLoader)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .navigationTitle(Self.navigationTitle)
        .task { await viewModel.viewDidAppear() }
    }

    private var showsResults: Bool {
        switch store.state {
        case .completeAssessment, .incompleteAssessment: return true
        default: return false
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey(NASLibraryCopy.emptyTitle), bundle: .module)
                .scaledFont(.title, weight: .semibold)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
            banner
            Button {
                Task { await viewModel.perform(.chooseFolder) }
            } label: {
                Text(LocalizedStringKey(NASLibraryCopy.chooseButton), bundle: .module)
            }
            .nasControl(AccessibilityIdentifiers.NAS.chooseFolder)
            Spacer(minLength: 0)
        }
    }

    private var banner: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: bannerSymbol)
                .foregroundStyle(bannerTint)
                .accessibilityHidden(true)
            bannerLabel
                .scaledFont(.body)
                .foregroundStyle(DesignTokens.ColorSystem.inkPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NASAccessibilityText.stateBanner(store.state))
        .accessibilityIdentifier(AccessibilityIdentifiers.NAS.stateBanner)
    }

    /// A failure message is shown verbatim so Markdown characters in error text aren't interpreted.
    @ViewBuilder
    private var bannerLabel: some View {
        if case let .failed(message) = store.state {
            Text(verbatim: message)
        } else {
            Text(LocalizedStringKey(NASLibraryCopy.bannerText(for: store.state)), bundle: .module)
        }
    }

    @ViewBuilder
    private var progressRow: some View {
        switch store.state {
        case .checkingConnection:
            ProgressView().controlSize(.small)
        case let .assessing(phase):
            VStack(alignment: .leading, spacing: 4) {
                if phase == .hashing, store.progress.hashTotal > 0 {
                    ProgressView(value: Double(store.progress.hashed), total: Double(store.progress.hashTotal))
                    Text(verbatim: "\(store.progress.hashed) / \(store.progress.hashTotal)")
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                } else {
                    ProgressView().controlSize(.small)
                    Text(verbatim: "\(store.progress.directories) folders, \(store.progress.files) files")
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                }
                if !store.progress.currentRelativePath.isEmpty {
                    Text(verbatim: store.progress.currentRelativePath)
                        .scaledFont(.label)
                        .foregroundStyle(DesignTokens.ColorSystem.inkSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        case .stopping:
            ProgressView().controlSize(.small)
        default:
            EmptyView()
        }
    }

    private var bannerSymbol: String {
        switch store.state {
        case .completeAssessment: return "checkmark.circle"
        case .waitingForNAS, .differentFolder, .needsIdentityConfirmation, .incompleteAssessment, .failed:
            return "exclamationmark.triangle"
        default: return "info.circle"
        }
    }

    private var bannerTint: SwiftUI.Color {
        switch store.state {
        case .completeAssessment: return DesignTokens.ColorSystem.statusSuccess
        case .waitingForNAS, .differentFolder, .needsIdentityConfirmation, .incompleteAssessment:
            return DesignTokens.ColorSystem.statusWarning
        case .failed: return DesignTokens.ColorSystem.statusDanger
        default: return DesignTokens.ColorSystem.inkSecondary
        }
    }
}
