#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import Combine

@MainActor
public final class HistoryStore: ObservableObject {
    @Published public private(set) var entries: [RunHistoryEntry]
    @Published public private(set) var transferredSources: [TransferredSourceRecord]
    @Published public private(set) var destinationRoot: String
    @Published public private(set) var lastRefreshError: String?
    private let indexer: any RunHistoryIndexing
    private let transferredSourcesLog: TransferredSourcesLog
    private let trashItem: (URL) throws -> Void

    public init(
        entries: [RunHistoryEntry] = [],
        transferredSources: [TransferredSourceRecord] = [],
        destinationRoot: String = "",
        indexer: any RunHistoryIndexing = RunHistoryIndexer(),
        transferredSourcesLog: TransferredSourcesLog = TransferredSourcesLog(),
        trashItem: @escaping (URL) throws -> Void = { url in
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        }
    ) {
        self.entries = entries
        self.transferredSources = transferredSources
        self.destinationRoot = destinationRoot
        self.lastRefreshError = nil
        self.indexer = indexer
        self.transferredSourcesLog = transferredSourcesLog
        self.trashItem = trashItem
    }

    public func refresh(destinationRoot: String) async {
        setDestinationRoot(destinationRoot)
        await loadEntries()
    }

    /// Records the active destination and clears the in-memory lists. Cheap
    /// (no disk I/O), so callers that must reflect the new root immediately
    /// can call this synchronously and offload `loadEntries()` to a Task.
    public func setDestinationRoot(_ destinationRoot: String) {
        // Validate the incoming root BEFORE clobbering the prior state.
        // Phase 1 finding #4: calling this with "" (profile-clear /
        // setup-clear flows) must not wipe a previously-loaded valid root that
        // downstream callers rely on as the implicit "where receipts live" handle.
        let trimmed = destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        self.destinationRoot = trimmed
        self.entries = []
        self.transferredSources = []
        self.lastRefreshError = nil
    }

    /// Reads run-history artifacts and the transferred-sources log for the
    /// current `destinationRoot`. The disk scan runs off the main actor so a
    /// slow or network destination can't freeze the UI.
    public func loadEntries() async {
        let trimmed = destinationRoot
        guard !trimmed.isEmpty else { return }

        let indexer = self.indexer
        let log = self.transferredSourcesLog
        let outcome = await Task.detached(priority: .userInitiated) {
            () -> (entries: [RunHistoryEntry]?, errorMessage: String?, sources: [TransferredSourceRecord]) in
            var entries: [RunHistoryEntry]?
            var errorMessage: String?
            do {
                entries = try indexer.index(destinationRoot: trimmed)
            } catch {
                errorMessage = UserFacingErrorMessage.message(for: error, context: .history)
            }
            let sources = log.load(destinationRoot: trimmed)
            return (entries, errorMessage, sources)
        }.value

        guard destinationRoot == trimmed else { return }

        if let entries = outcome.entries {
            self.entries = entries
            self.lastRefreshError = nil
            #if canImport(CoreSpotlight)
            SpotlightIndexer.indexHistoryEntries(entries)
            #endif
        }
        if let errorMessage = outcome.errorMessage {
            self.lastRefreshError = errorMessage
        }
        self.transferredSources = outcome.sources
    }

    /// Records a successful transfer in the per-destination JSON log and
    /// refreshes the in-memory `transferredSources` list.
    public func recordSuccessfulTransfer(sourcePath: String, destinationRoot: String, copiedCount: Int) {
        let trimmedSource = sourcePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDest = destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSource.isEmpty, !trimmedDest.isEmpty else { return }

        transferredSources = transferredSourcesLog.recordTransfer(
            sourcePath: trimmedSource,
            destinationRoot: trimmedDest,
            copiedCount: copiedCount
        )
    }

    /// Removes a source-path record from the per-destination log and updates the list.
    public func removeTransferredSource(_ record: TransferredSourceRecord) {
        let trimmedDest = destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDest.isEmpty else { return }
        transferredSources = transferredSourcesLog.removeRecord(
            sourcePath: record.sourcePath,
            destinationRoot: trimmedDest
        )
    }

    /// Moves the artifact file for `entry` to the Trash and removes it from the in-memory list.
    /// Removes missing entries from the in-memory list because there is nothing left to trash.
    public func remove(entry: RunHistoryEntry) {
        let url = URL(fileURLWithPath: entry.path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)
                #if canImport(CoreSpotlight)
                SpotlightIndexer.deindexHistoryEntry(path: entry.path)
                #endif
            }
            return
        }

        do {
            try trashItem(url)
            if let index = entries.firstIndex(where: { $0.id == entry.id }) {
                entries.remove(at: index)
                #if canImport(CoreSpotlight)
                SpotlightIndexer.deindexHistoryEntry(path: entry.path)
                #endif
            }
        } catch {
            lastRefreshError = UserFacingErrorMessage.withDetails(
                "Chronoframe could not move this history item to Trash. Open it in Finder and remove it manually.",
                details: error.localizedDescription
            )
        }
    }

    /// Moves all artifact files to the Trash and clears the in-memory list.
    public func removeAll() {
        var failedCount = 0
        var removedIDs: Set<UUID> = []
        for entry in entries {
            let url = URL(fileURLWithPath: entry.path)
            guard FileManager.default.fileExists(atPath: url.path) else {
                removedIDs.insert(entry.id)
                continue
            }

            do {
                try trashItem(url)
                removedIDs.insert(entry.id)
            } catch {
                failedCount += 1
            }
        }

        entries.removeAll { removedIDs.contains($0.id) }

        if failedCount > 0 {
            lastRefreshError = "Chronoframe could not move \(failedCount) history item\(failedCount == 1 ? "" : "s") to Trash. Open the destination in Finder and remove them manually."
        }
    }
}
