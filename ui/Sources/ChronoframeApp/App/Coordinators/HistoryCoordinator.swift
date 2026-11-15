import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

@MainActor
final class HistoryCoordinator {
    private let preferencesStore: PreferencesStore
    private let setupStore: SetupStore
    private let historyStore: HistoryStore
    private let runSessionStore: RunSessionStore
    private let deduplicateSessionStore: DeduplicateSessionStore
    private let finderService: any FinderServicing
    private let navigate: @MainActor (AppRoute) -> Void
    private let reportTransientError: @MainActor (String) -> Void
    private let makeSecurityScopeForDestination: @MainActor (String) -> SecurityScopedFolderAccess?

    init(
        preferencesStore: PreferencesStore,
        setupStore: SetupStore,
        historyStore: HistoryStore,
        runSessionStore: RunSessionStore,
        deduplicateSessionStore: DeduplicateSessionStore,
        finderService: any FinderServicing,
        navigate: @escaping @MainActor (AppRoute) -> Void,
        reportTransientError: @escaping @MainActor (String) -> Void = { _ in },
        makeSecurityScopeForDestination: @escaping @MainActor (String) -> SecurityScopedFolderAccess? = { _ in nil }
    ) {
        self.preferencesStore = preferencesStore
        self.setupStore = setupStore
        self.historyStore = historyStore
        self.runSessionStore = runSessionStore
        self.deduplicateSessionStore = deduplicateSessionStore
        self.finderService = finderService
        self.navigate = navigate
        self.reportTransientError = reportTransientError
        self.makeSecurityScopeForDestination = makeSecurityScopeForDestination
    }

    /// Triggers a revert of the receipt. Audit receipts go through the
    /// organize Run workspace so progress/summary show up there; dedupe
    /// receipts go through the Deduplicate workspace which already owns
    /// its own commit-progress surface.
    func revertHistoryEntry(_ entry: RunHistoryEntry) {
        guard !runSessionStore.isRunning, !deduplicateSessionStore.isWorking else {
            reportTransientError("Stop the current run before reverting history.")
            return
        }

        switch entry.kind {
        case .auditReceipt:
            let destinationRoot = receiptDestinationRoot(for: entry)
            navigate(.organize(.run))
            runSessionStore.requestRevert(
                receiptURL: URL(fileURLWithPath: entry.path),
                destinationRoot: destinationRoot,
                securityScope: makeSecurityScopeForDestination(destinationRoot)
            )
        case .dedupeAuditReceipt:
            let destinationRoot = receiptDestinationRoot(for: entry)
            navigate(.deduplicate)
            deduplicateSessionStore.revert(
                receiptURL: URL(fileURLWithPath: entry.path),
                destinationRoot: destinationRoot,
                securityScope: makeSecurityScopeForDestination(destinationRoot)
            )
        case .reorganizeAuditReceipt:
            let destinationRoot = receiptDestinationRoot(for: entry)
            navigate(.organize(.run))
            runSessionStore.requestReorganizeRevert(
                receiptURL: URL(fileURLWithPath: entry.path),
                destinationRoot: destinationRoot,
                securityScope: makeSecurityScopeForDestination(destinationRoot)
            )
        default:
            return
        }
    }

    private func receiptDestinationRoot(for entry: RunHistoryEntry) -> String {
        let receiptURL = URL(fileURLWithPath: entry.path)
        let logDirectory = receiptURL.deletingLastPathComponent()
        if logDirectory.lastPathComponent == ".organize_logs" {
            return logDirectory.deletingLastPathComponent().path
        }
        return historyStore.destinationRoot
    }

    func revealHistoryEntry(_ entry: RunHistoryEntry) {
        finderService.revealInFinder(entry.path)
    }

    func openHistoryEntry(_ entry: RunHistoryEntry) {
        finderService.openPath(entry.path)
    }

    func useHistoricalSource(_ record: TransferredSourceRecord) {
        if setupStore.usingProfile {
            setupStore.clearProfileSelection()
            preferencesStore.lastSelectedProfileName = ""
        }

        setupStore.sourcePath = record.sourcePath
        preferencesStore.lastManualSourcePath = record.sourcePath

        // The chosen folder's only saved authorization may be a folder-list
        // bookmark; keep it as manual.source before the list keys are removed.
        if preferencesStore.bookmark(for: "manual.source")?.path != record.sourcePath,
           let listBookmark = preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.")
               .compactMap({ preferencesStore.bookmark(for: $0) })
               .first(where: { $0.path == record.sourcePath }) {
            preferencesStore.storeBookmark(
                FolderBookmark(key: "manual.source", path: listBookmark.path, data: listBookmark.data)
            )
        }

        // Resolve manual.source bookmark if it matches record.sourcePath
        var isStale = false
        if let bookmark = preferencesStore.bookmark(for: "manual.source"),
           bookmark.path == record.sourcePath,
           let resolved = try? URL(resolvingBookmarkData: bookmark.data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale) {
            setupStore.sourceURL = resolved
        } else {
            setupStore.sourceURL = URL(fileURLWithPath: record.sourcePath)
        }

        // The chosen folder replaces any earlier folder list, so Setup lists
        // just this folder and a later "add folder" starts from it.
        setupStore.clearDroppedSource()
        if let sourceURL = setupStore.sourceURL {
            setupStore.setSourceItems([sourceURL])
        }
        preferencesStore.manualSourceItemPaths = [record.sourcePath]
        for key in preferencesStore.bookmarkKeys(withPrefix: "manual.sourceItem.") {
            preferencesStore.removeBookmark(for: key)
        }

        navigate(.organize(.setup))
    }

    func revealTransferredSource(_ record: TransferredSourceRecord) {
        finderService.revealInFinder(record.sourcePath)
    }

    func forgetTransferredSource(_ record: TransferredSourceRecord) {
        historyStore.removeTransferredSource(record)
    }
}
