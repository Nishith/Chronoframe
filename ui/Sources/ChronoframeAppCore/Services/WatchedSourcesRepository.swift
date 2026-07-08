import Foundation

/// Injection seam over the watched-sources store so the store and
/// coordinator can be tested against an in-memory fake.
public protocol WatchedSourcesRepositorying: AnyObject {
    /// True when the on-disk store was corrupt at open and had to be
    /// quarantined; the UI surfaces "your watched folders needed to be
    /// re-checked" once per occurrence.
    var didQuarantineCorruptStore: Bool { get }

    func loadSources() throws -> [WatchedSource]
    func addSource(_ source: WatchedSource, initialCheckpoint: [String: WatchedFileStamp]) throws
    func removeSource(id: UUID) throws
    func replaceSourcePath(id: UUID, newPath: String, clearCheckpoint: Bool) throws
    func checkpoint(for id: UUID) throws -> [String: WatchedFileStamp]
    func replaceCheckpoint(for id: UUID, entries: [String: WatchedFileStamp]) throws
    @discardableResult
    func bumpChangeGeneration(id: UUID) throws -> Int64
}

/// Production repository: a `WatchedSourceCheckpointDatabase` in
/// Application Support (never at a destination — the standing freshness
/// path must work with every destination offline and must never write
/// there). The database opens lazily on first use so app startup cannot
/// fail on a bad store; open errors surface on the first real call.
public final class WatchedSourcesRepository: WatchedSourcesRepositorying {
    private let databaseURL: URL
    private var database: WatchedSourceCheckpointDatabase?
    private var quarantined = false

    public init(databaseURL: URL = WatchedSourcesRepository.defaultDatabaseURL()) {
        self.databaseURL = databaseURL
    }

    public static func defaultDatabaseURL() -> URL {
        let environment = ProcessInfo.processInfo.environment

        #if DEBUG
        if let override = environment["CHRONOFRAME_WATCHED_SOURCES_DB"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }
        #endif

        return RuntimePaths.applicationSupportDirectory()
            .appendingPathComponent("watched_sources.db")
    }

    public var didQuarantineCorruptStore: Bool {
        quarantined || database?.didQuarantineCorruptStore == true
    }

    public func loadSources() throws -> [WatchedSource] {
        try openedDatabase().loadSources()
    }

    public func addSource(_ source: WatchedSource, initialCheckpoint: [String: WatchedFileStamp]) throws {
        try openedDatabase().addSource(source, initialCheckpoint: initialCheckpoint)
    }

    public func removeSource(id: UUID) throws {
        try openedDatabase().removeSource(id: id)
    }

    public func replaceSourcePath(id: UUID, newPath: String, clearCheckpoint: Bool) throws {
        try openedDatabase().replaceSourcePath(id: id, newPath: newPath, clearCheckpoint: clearCheckpoint)
    }

    public func checkpoint(for id: UUID) throws -> [String: WatchedFileStamp] {
        try openedDatabase().checkpoint(for: id)
    }

    public func replaceCheckpoint(for id: UUID, entries: [String: WatchedFileStamp]) throws {
        try openedDatabase().replaceCheckpoint(for: id, entries: entries)
    }

    @discardableResult
    public func bumpChangeGeneration(id: UUID) throws -> Int64 {
        try openedDatabase().bumpChangeGeneration(id: id)
    }

    private func openedDatabase() throws -> WatchedSourceCheckpointDatabase {
        if let database { return database }
        let opened = try WatchedSourceCheckpointDatabase(url: databaseURL)
        if opened.didQuarantineCorruptStore {
            quarantined = true
        }
        database = opened
        return opened
    }
}
