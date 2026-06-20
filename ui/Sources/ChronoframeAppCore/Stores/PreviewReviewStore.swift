#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import Combine

public enum PreviewReviewFilter: String, CaseIterable, Identifiable, Sendable {
    case needsAttention
    case unknownDate
    case lowConfidenceDate
    case duplicates
    case collisions
    case ready
    case all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsAttention:
            return "Needs Attention"
        case .unknownDate:
            return "Unknown Date"
        case .lowConfidenceDate:
            return "Low Confidence"
        case .duplicates:
            return "Duplicates"
        case .collisions:
            return "Skipped"
        case .ready:
            return "Ready"
        case .all:
            return "All"
        }
    }
}

@MainActor
public final class PreviewReviewStore: ObservableObject {
    @Published public private(set) var items: [PreviewReviewItem] = []
    @Published public private(set) var artifactPath: String?
    @Published public private(set) var destinationRoot: String?
    @Published public private(set) var isLoading = false
    @Published public private(set) var isStale = false
    @Published public private(set) var errorMessage: String?
    @Published public var filter: PreviewReviewFilter = .needsAttention

    /// Undo target for Preview Triage edits. Bound from the view's
    /// `@Environment(\.undoManager)` so capture-date and event corrections are
    /// reversible with ⌘Z. Weak: the manager is owned by the responder chain.
    public weak var undoManager: UndoManager?

    /// Serializes ReviewOverride database writes. Undo/redo can fire writes
    /// back-to-back; opening two `OrganizerDatabase` connections on the same
    /// file concurrently corrupts the heap, so every write chains after the
    /// previous one completes.
    private var persistQueue: Task<Void, Never>?

    private var makeDestinationScope: @MainActor @Sendable (String) -> SecurityScopedFolderAccess?

    public init(
        makeDestinationScope: @escaping @MainActor @Sendable (String) -> SecurityScopedFolderAccess? = { _ in nil }
    ) {
        self.makeDestinationScope = makeDestinationScope
    }

    public func setDestinationScopeProvider(
        _ makeDestinationScope: @escaping @MainActor @Sendable (String) -> SecurityScopedFolderAccess?
    ) {
        self.makeDestinationScope = makeDestinationScope
    }

    public var summary: PreviewReviewSummary {
        PreviewReviewSummary(items: items)
    }

    public var filteredItems: [PreviewReviewItem] {
        switch filter {
        case .needsAttention:
            return items.filter(\.needsAttention)
        case .unknownDate:
            return items.filter { $0.issues.contains(.unknownDate) }
        case .lowConfidenceDate:
            return items.filter { $0.issues.contains(.lowConfidenceDate) }
        case .duplicates:
            return items.filter { $0.status == .duplicate }
        case .collisions:
            return items.filter { $0.status == .alreadyInDestination }
        case .ready:
            return items.filter { $0.status == .ready }
        case .all:
            return items
        }
    }

    public func reset() {
        items = []
        artifactPath = nil
        destinationRoot = nil
        isLoading = false
        isStale = false
        errorMessage = nil
    }

    public func load(artifactPath: String?, destinationRoot: String?) async {
        guard let artifactPath, !artifactPath.isEmpty else {
            reset()
            return
        }

        // Phase 1: when the user edits a preview item and clicks Save,
        // the preview is rebuilt to the SAME artifact path (same dry-run
        // CSV name when parameters are unchanged). `isStale` is the
        // signal that the on-disk artifact has fresh content even though
        // the path didn't change. Without this guard, the short-circuit
        // skips the reload and the UI keeps showing pre-edit items.
        guard artifactPath != self.artifactPath || isStale else {
            self.destinationRoot = destinationRoot
            return
        }

        isLoading = true
        isStale = false
        errorMessage = nil

        do {
            let loadedItems = try await Self.decodeItems(at: artifactPath)
            self.items = loadedItems
            self.artifactPath = artifactPath
            self.destinationRoot = destinationRoot
            if loadedItems.contains(where: \.needsAttention) {
                filter = .needsAttention
            } else {
                filter = .all
            }
        } catch {
            self.items = []
            self.artifactPath = artifactPath
            self.destinationRoot = destinationRoot
            self.errorMessage = UserFacingErrorMessage.message(for: error, context: .run)
        }

        isLoading = false
    }

    public func saveOverride(
        for item: PreviewReviewItem,
        captureDate: Date?,
        eventName: String?,
        actionName: String = "Edit Review Item"
    ) async {
        guard let identityRawValue = item.identityRawValue,
              let identity = FileIdentity(rawValue: identityRawValue),
              let destinationRoot else {
            errorMessage = "Chronoframe needs a readable preview item before it can save that correction."
            return
        }

        // Snapshot the pre-edit item from the *live* array (not the passed-in
        // `item`) so Undo reverts to exactly what was on screen at edit time.
        let previous = items.first(where: { $0.sourcePath == item.sourcePath })

        let override = ReviewOverride(
            identity: identity,
            sourcePath: item.sourcePath,
            captureDate: captureDate,
            eventName: eventName
        )

        if let error = await enqueuePersist(override, destinationRoot: destinationRoot).value {
            errorMessage = UserFacingErrorMessage.message(for: error, context: .run)
            return
        }
        updateLocalItem(item.sourcePath) { current in
            current.resolvedDate = captureDate ?? current.resolvedDate
            if captureDate != nil {
                current.dateSource = .userOverride
                current.dateConfidence = .high
                current.issues.removeAll { $0 == .unknownDate || $0 == .lowConfidenceDate }
            }
            current.acceptedEventName = ReviewOverride.normalizedEventName(eventName)
        }
        isStale = true
        errorMessage = nil
        if let previous {
            registerUndo(restoring: previous, actionName: actionName)
        }
    }

    public func acceptSuggestion(for item: PreviewReviewItem) async {
        guard let suggestedName = item.eventSuggestion?.suggestedName else {
            return
        }
        await saveOverride(
            for: item,
            captureDate: item.dateSource == .userOverride ? item.resolvedDate : nil,
            eventName: suggestedName,
            actionName: "Accept Event Name"
        )
    }

    // MARK: - Undo / Redo

    /// Registers an Undo that restores `snapshot` — a complete pre-edit item.
    /// On execution it re-captures the *current* live item as the Redo target,
    /// so undo and redo always move between real states even if unrelated edits
    /// happened in between. We restore whole-item snapshots rather than
    /// re-running `saveOverride`'s forward transform because that transform is
    /// lossy (it strips `.unknownDate`/`.lowConfidenceDate` issues) and cannot
    /// reconstruct the prior state.
    private func registerUndo(restoring snapshot: PreviewReviewItem, actionName: String) {
        guard let undoManager else { return }
        undoManager.registerUndo(withTarget: self) { target in
            // `undo()`/`redo()` are dispatched on the main thread, so the
            // MainActor-isolated store is safe to touch synchronously here.
            MainActor.assumeIsolated {
                target.applyRestore(snapshot, actionName: actionName)
            }
        }
        undoManager.setActionName(actionName)
    }

    /// Restores a previously-captured item snapshot, registers the inverse for
    /// Redo, and re-persists the matching override. Internal so store-level
    /// tests can drive a deterministic round-trip without the responder chain.
    func applyRestore(_ snapshot: PreviewReviewItem, actionName: String) {
        let current = items.first(where: { $0.sourcePath == snapshot.sourcePath })
        updateLocalItem(snapshot.sourcePath) { $0 = snapshot }
        isStale = true
        errorMessage = nil
        persistOverrideInBackground(for: snapshot)
        if let current {
            registerUndo(restoring: current, actionName: actionName)
        }
    }

    /// Re-persists the override implied by a restored item. The user-visible
    /// revert (the in-memory item swap) already happened synchronously in
    /// `applyRestore`; the database write trails it best-effort on the shared
    /// serialized queue.
    private func persistOverrideInBackground(for item: PreviewReviewItem) {
        guard let identityRawValue = item.identityRawValue,
              let identity = FileIdentity(rawValue: identityRawValue),
              let destinationRoot else {
            return
        }
        let override = ReviewOverride(
            identity: identity,
            sourcePath: item.sourcePath,
            captureDate: item.dateSource == .userOverride ? item.resolvedDate : nil,
            eventName: item.acceptedEventName
        )
        let task = enqueuePersist(override, destinationRoot: destinationRoot)
        Task {
            if let error = await task.value {
                errorMessage = UserFacingErrorMessage.message(for: error, context: .run)
            }
        }
    }

    /// Appends a database write to the serialized `persistQueue` and returns a
    /// handle resolving to its error (or `nil` on success). Each write waits for
    /// the previous one so connections never overlap.
    @discardableResult
    private func enqueuePersist(
        _ override: ReviewOverride,
        destinationRoot: String
    ) -> Task<Error?, Never> {
        let previous = persistQueue
        let work = Task { @MainActor () -> Error? in
            await previous?.value
            do {
                try await self.persistOverride(override, destinationRoot: destinationRoot)
                return nil
            } catch {
                return error
            }
        }
        persistQueue = Task { @MainActor in _ = await work.value }
        return work
    }

    /// Awaits any in-flight override writes. Used by tests to drain the queue
    /// before tearing down a temporary destination.
    func drainPendingPersists() async {
        await persistQueue?.value
    }

    public func acceptVisibleSuggestions() async {
        let visible = filteredItems.filter { $0.eventSuggestion?.suggestedName != nil }
        for item in visible {
            await acceptSuggestion(for: item)
        }
    }

    private func updateLocalItem(
        _ sourcePath: String,
        _ body: (inout PreviewReviewItem) -> Void
    ) {
        guard let index = items.firstIndex(where: { $0.sourcePath == sourcePath }) else {
            return
        }
        body(&items[index])
    }

    private nonisolated static func decodeItems(at path: String) async throws -> [PreviewReviewItem] {
        try await Task.detached(priority: .userInitiated) {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            guard let raw = String(data: data, encoding: .utf8) else {
                return [PreviewReviewItem]()
            }

            let decoder = JSONDecoder()
            var items: [PreviewReviewItem] = []
            for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
                let lineData = Data(line.utf8)
                items.append(try decoder.decode(PreviewReviewItem.self, from: lineData))
            }
            return items
        }.value
    }

    private func persistOverride(
        _ override: ReviewOverride,
        destinationRoot: String
    ) async throws {
        let scope = makeDestinationScope(destinationRoot)
        defer { scope?.close() }
        // The actual database write lives in a `nonisolated static` (mirroring
        // `decodeItems`). Awaiting a nested `Task.detached().value` directly from
        // this `@MainActor` frame trips the Swift task allocator's LIFO check;
        // hopping off the actor first avoids it.
        try await Self.writeReviewOverride(override, destinationRoot: destinationRoot)
    }

    private nonisolated static func writeReviewOverride(
        _ override: ReviewOverride,
        destinationRoot: String
    ) async throws {
        try await Task.detached(priority: .utility) {
            let databaseURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
                .appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
            let database = try OrganizerDatabase(url: databaseURL)
            defer { database.close() }
            try database.saveReviewOverride(override)
        }.value
    }
}
