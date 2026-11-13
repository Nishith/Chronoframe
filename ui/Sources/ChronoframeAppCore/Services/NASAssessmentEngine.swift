#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// Everything the workspace shows for a library's latest assessment, read from the
/// local assessment store (C-12).
public struct NASAssessmentSnapshot: Sendable, Equatable {
    public var summary: NASScanSummary
    public var groups: [NASExactGroup]
    public var directories: [NASDirectoryRow]
    public var issues: [NASIssue]
    public var choices: [String: NASReviewChoice]
    public var selectedDigest: String?

    public init(
        summary: NASScanSummary,
        groups: [NASExactGroup],
        directories: [NASDirectoryRow],
        issues: [NASIssue],
        choices: [String: NASReviewChoice],
        selectedDigest: String?
    ) {
        self.summary = summary
        self.groups = groups
        self.directories = directories
        self.issues = issues
        self.choices = choices
        self.selectedDigest = selectedDigest
    }
}

/// The assessment surface the workspace store talks to. It can read a library and keep
/// notes on this Mac; it has no way to delete, move or trash anything (INV-27).
public protocol NASAssessmentEngine: AnyObject, Sendable {
    func assess(_ library: NASLibraryRecord, rootURL: URL) throws -> AsyncThrowingStream<NASAssessmentEvent, Error>
    func cancel()
    func latestSnapshot(for library: NASLibraryRecord) throws -> NASAssessmentSnapshot?
    func saveChoice(_ choice: NASReviewChoice, for library: NASLibraryRecord) throws
    func saveSelectedDigest(_ digest: String?, for library: NASLibraryRecord) throws
    func recordPreviewRequest(for library: NASLibraryRecord) throws
}

/// Owns one `NASAssessmentStore` per library UUID, opened lazily under Application Support.
public final class SwiftNASAssessmentEngine: NASAssessmentEngine, @unchecked Sendable {
    private static let selectedDigestKey = "selectedDigest"

    private let storeURL: @Sendable (String) -> URL
    private let lock = NSLock()
    private var stores: [String: NASAssessmentStore] = [:]
    private var activeCancellation: CancellationFlag?

    public init() {
        self.storeURL = { NASPaths.assessmentStoreURL($0) }
    }

    /// Test seam: lets tests keep the store in a temporary folder.
    init(storeURL: @escaping @Sendable (String) -> URL) {
        self.storeURL = storeURL
    }

    public func assess(_ library: NASLibraryRecord, rootURL: URL) throws -> AsyncThrowingStream<NASAssessmentEvent, Error> {
        let store = try store(for: library)
        let flag = CancellationFlag()
        lock.lock()
        activeCancellation = flag
        lock.unlock()

        let configuration = NASAssessmentConfiguration(
            rootURL: rootURL,
            stateURL: storeURL(library.libraryUUID)
        )
        let scanner = NASAssessmentScanner(store: store)
        return scanner.run(configuration, isCancelled: { flag.isSet })
    }

    public func cancel() {
        lock.lock()
        let flag = activeCancellation
        lock.unlock()
        flag?.set()
    }

    public func latestSnapshot(for library: NASLibraryRecord) throws -> NASAssessmentSnapshot? {
        let store = try store(for: library)
        guard let generation = try store.latestGeneration(),
              let summary = try store.scanSummary(generation: generation)
        else { return nil }
        return NASAssessmentSnapshot(
            summary: summary,
            groups: try store.exactGroups(generation: generation),
            directories: try store.directoryRows(generation: generation),
            issues: try store.issues(generation: generation),
            choices: try store.choices(),
            selectedDigest: try store.reviewState(forKey: Self.selectedDigestKey)
        )
    }

    public func saveChoice(_ choice: NASReviewChoice, for library: NASLibraryRecord) throws {
        try store(for: library).saveChoice(choice)
    }

    public func saveSelectedDigest(_ digest: String?, for library: NASLibraryRecord) throws {
        try store(for: library).setReviewState(digest, forKey: Self.selectedDigestKey)
    }

    public func recordPreviewRequest(for library: NASLibraryRecord) throws {
        let store = try store(for: library)
        guard let generation = try store.latestGeneration() else { return }
        try store.incrementPreviewRequests(generation: generation)
    }

    private func store(for library: NASLibraryRecord) throws -> NASAssessmentStore {
        lock.lock()
        defer { lock.unlock() }
        if let existing = stores[library.libraryUUID] { return existing }
        let opened = try NASAssessmentStore(url: storeURL(library.libraryUUID), libraryUUID: library.libraryUUID)
        stores[library.libraryUUID] = opened
        return opened
    }
}

private final class CancellationFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}
