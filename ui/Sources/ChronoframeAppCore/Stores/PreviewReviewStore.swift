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

    public init() {}

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

        guard artifactPath != self.artifactPath else {
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
        eventName: String?
    ) async {
        guard let identityRawValue = item.identityRawValue,
              let identity = FileIdentity(rawValue: identityRawValue),
              let destinationRoot else {
            errorMessage = "Chronoframe needs a readable preview item before it can save that correction."
            return
        }

        let override = ReviewOverride(
            identity: identity,
            sourcePath: item.sourcePath,
            captureDate: captureDate,
            eventName: eventName
        )

        do {
            try await Self.persistOverride(override, destinationRoot: destinationRoot)
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
        } catch {
            errorMessage = UserFacingErrorMessage.message(for: error, context: .run)
        }
    }

    public func acceptSuggestion(for item: PreviewReviewItem) async {
        guard let suggestedName = item.eventSuggestion?.suggestedName else {
            return
        }
        await saveOverride(
            for: item,
            captureDate: item.dateSource == .userOverride ? item.resolvedDate : nil,
            eventName: suggestedName
        )
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

    private nonisolated static func persistOverride(
        _ override: ReviewOverride,
        destinationRoot: String
    ) async throws {
        try await Task.detached(priority: .utility) {
            let databaseURL = URL(fileURLWithPath: destinationRoot, isDirectory: true)
                .appendingPathComponent(EngineArtifactLayout.pythonReference.queueDatabaseFilename)
            let database = try OrganizerDatabase(url: databaseURL)
            defer { database.close() }
            try database.saveReviewOverride(override)
        }.value
    }
}
