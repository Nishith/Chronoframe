#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// How reachable a watched source currently is.
public enum WatchedSourceAvailability: Equatable, Sendable {
    /// Bookmark resolves, scope started, folder validates — watching.
    case available
    /// The folder (or its volume) is not reachable right now. Ejected
    /// SD cards and drives land here; bookmark resolution failure alone
    /// cannot distinguish an absent volume from lost access, so this
    /// state is retried on mount notifications and manual refresh.
    case unavailable
    /// The path is present on disk but the bookmark no longer resolves
    /// or its security scope will not start — the sandbox grant is gone
    /// and only re-picking the folder can restore it.
    case accessLost
    /// The source overlaps a Chronoframe destination; watching is
    /// suspended until the conflict clears.
    case pausedConflict
}

public struct WatchedSourceState: Identifiable, Equatable, Sendable {
    public var source: WatchedSource
    public var availability: WatchedSourceAvailability
    /// Estimated pending arrivals ("About N new items"); nil when no
    /// complete scan has finished this session.
    public var pendingEstimate: Int?
    public var isChecking: Bool
    public var lastCompleteScanAt: Date?
    /// True when the most recent scan could not read part of the tree;
    /// the previous complete estimate is preserved and the UI says
    /// "Couldn't fully check this folder."
    public var lastScanWasPartial: Bool
    /// True when the monitor runs on the reduced-fidelity polling path.
    public var isDegradedWatch: Bool

    public var id: UUID { source.id }

    public init(
        source: WatchedSource,
        availability: WatchedSourceAvailability = .unavailable,
        pendingEstimate: Int? = nil,
        isChecking: Bool = false,
        lastCompleteScanAt: Date? = nil,
        lastScanWasPartial: Bool = false,
        isDegradedWatch: Bool = false
    ) {
        self.source = source
        self.availability = availability
        self.pendingEstimate = pendingEstimate
        self.isChecking = isChecking
        self.lastCompleteScanAt = lastCompleteScanAt
        self.lastScanWasPartial = lastScanWasPartial
        self.isDegradedWatch = isDegradedWatch
    }
}

public enum WatchedSourceRegistrationError: LocalizedError, Equatable, Sendable {
    case overlapsDestination(SourceDestinationDisjointness.Conflict)
    case overlapsWatchedFolder(existingPath: String)
    case alreadyWatched(path: String)

    public var errorDescription: String? {
        switch self {
        case .overlapsDestination(.sourceInsideDestination):
            return "That folder is inside your destination folder. Watching it would make Chronoframe see its own copies as new items. Choose a folder outside the destination."
        case .overlapsDestination(.destinationInsideSource):
            return "That folder contains your destination folder. Watching it would make Chronoframe see its own copies as new items. Choose a folder that doesn't contain the destination."
        case .overlapsWatchedFolder:
            return "That folder overlaps a folder Chronoframe is already watching. Watching both would count the same photos twice."
        case .alreadyWatched:
            return "Chronoframe is already watching that folder."
        }
    }
}

/// Observable state for the Sources tab. Deliberately synchronous and
/// state-only (like `SetupStore`): all I/O, watching, and scheduling
/// live in `SourceWatchCoordinator`, which drives these mutators.
@MainActor
public final class WatchedSourcesStore: ObservableObject {
    @Published public private(set) var states: [WatchedSourceState] = []
    /// One-shot notice surfaced when the on-disk store was quarantined
    /// ("Your watched folders needed to be re-checked").
    @Published public private(set) var storeNotice: String?

    public init() {}

    /// Sum of pending estimates across available sources (menu-bar line).
    public var totalPendingEstimate: Int {
        states
            .filter { $0.availability == .available }
            .compactMap(\.pendingEstimate)
            .reduce(0, +)
    }

    /// Sidebar attention token: persisted per-source change generations,
    /// so a pending count that goes 1 → 0 → 1 still produces a NEW token
    /// (a plain count-based token would match the already-seen value).
    public var attentionToken: String {
        states
            .filter { ($0.pendingEstimate ?? 0) > 0 }
            .map { "\($0.id.uuidString):\($0.source.changeGeneration)" }
            .sorted()
            .joined(separator: ",")
    }

    // MARK: - Registration guard (pure)

    /// Early-feedback overlap check for registration and destination
    /// changes. The organize engine preflight independently re-enforces
    /// source/destination disjointness at run time (AGENTS invariant 21);
    /// this adds the watched-specific rules: no nesting with other
    /// watched folders (double counting) and no duplicates.
    public static func registrationConflict(
        candidatePath: String,
        destinationPaths: [String],
        existingWatchedPaths: [String]
    ) -> WatchedSourceRegistrationError? {
        let candidate = URL(fileURLWithPath: candidatePath, isDirectory: true).standardizedFileURL.path

        for destination in destinationPaths {
            let trimmed = destination.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if let conflict = SourceDestinationDisjointness.conflict(
                sourcePath: candidate,
                destinationPath: trimmed
            ) {
                return .overlapsDestination(conflict)
            }
        }

        for existing in existingWatchedPaths {
            let existingStandardized = URL(fileURLWithPath: existing, isDirectory: true).standardizedFileURL.path
            if existingStandardized == candidate {
                return .alreadyWatched(path: existing)
            }
            let candidateURL = URL(fileURLWithPath: candidate, isDirectory: true)
            let existingURL = URL(fileURLWithPath: existingStandardized, isDirectory: true)
            if SafePathContainment.isContained(candidateURL, in: existingURL)
                || SafePathContainment.isContained(existingURL, in: candidateURL) {
                return .overlapsWatchedFolder(existingPath: existing)
            }
        }

        return nil
    }

    // MARK: - Coordinator-driven mutators

    public func load(_ sources: [WatchedSource]) {
        states = sources.map { WatchedSourceState(source: $0) }
    }

    public func insert(_ source: WatchedSource) {
        guard state(for: source.id) == nil else { return }
        states.append(WatchedSourceState(source: source))
    }

    public func remove(id: UUID) {
        states.removeAll { $0.id == id }
    }

    public func state(for id: UUID) -> WatchedSourceState? {
        states.first { $0.id == id }
    }

    public func updateSource(_ source: WatchedSource) {
        mutate(source.id) { $0.source = source }
    }

    public func setAvailability(id: UUID, _ availability: WatchedSourceAvailability) {
        mutate(id) { state in
            state.availability = availability
            if availability != .available {
                state.isChecking = false
            }
        }
    }

    public func setChecking(id: UUID, _ checking: Bool) {
        mutate(id) { $0.isChecking = checking }
    }

    /// Applies a COMPLETE scan's outcome.
    public func applyCompleteScan(id: UUID, pendingEstimate: Int, capturedAt: Date) {
        mutate(id) { state in
            state.pendingEstimate = pendingEstimate
            state.lastCompleteScanAt = capturedAt
            state.lastScanWasPartial = false
            state.isChecking = false
        }
    }

    /// A partial scan never updates the estimate — it only flags that
    /// the folder couldn't be fully checked. The previous complete
    /// count stays on screen.
    public func markPartialScan(id: UUID) {
        mutate(id) { state in
            state.lastScanWasPartial = true
            state.isChecking = false
        }
    }

    public func setDegradedWatch(id: UUID, _ degraded: Bool) {
        mutate(id) { $0.isDegradedWatch = degraded }
    }

    public func setStoreNotice(_ notice: String?) {
        storeNotice = notice
    }

    private func mutate(_ id: UUID, _ body: (inout WatchedSourceState) -> Void) {
        guard let index = states.firstIndex(where: { $0.id == id }) else { return }
        var state = states[index]
        body(&state)
        states[index] = state
    }
}
