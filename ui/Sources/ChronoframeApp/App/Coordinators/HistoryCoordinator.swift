import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

@MainActor
final class HistoryCoordinator {
    private let preferencesStore: PreferencesStore
    private let setupStore: SetupStore
    private let historyStore: HistoryStore
    private let finderService: any FinderServicing
    private let setSelection: @MainActor (SidebarDestination) -> Void

    init(
        preferencesStore: PreferencesStore,
        setupStore: SetupStore,
        historyStore: HistoryStore,
        finderService: any FinderServicing,
        setSelection: @escaping @MainActor (SidebarDestination) -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.setupStore = setupStore
        self.historyStore = historyStore
        self.finderService = finderService
        self.setSelection = setSelection
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
        setSelection(.setup)
    }

    func revealTransferredSource(_ record: TransferredSourceRecord) {
        finderService.revealInFinder(record.sourcePath)
    }

    func forgetTransferredSource(_ record: TransferredSourceRecord) {
        historyStore.removeTransferredSource(record)
    }
}
