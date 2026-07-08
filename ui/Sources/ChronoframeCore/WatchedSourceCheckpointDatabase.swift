import Foundation
import SQLite3

/// A registered watched source folder.
public struct WatchedSource: Identifiable, Equatable, Sendable {
    public var id: UUID
    /// Last-known absolute path (display and bookmark fallback; the
    /// security-scoped bookmark is the real access handle).
    public var path: String
    public var label: String
    public var addedAt: Date
    /// Monotonic generation, bumped whenever the source's pending set
    /// gains entries. Drives "new since you last looked" attention state
    /// that survives a count returning to a previously-seen value.
    public var changeGeneration: Int64

    public init(
        id: UUID = UUID(),
        path: String,
        label: String,
        addedAt: Date = Date(),
        changeGeneration: Int64 = 0
    ) {
        self.id = id
        self.path = path
        self.label = label
        self.addedAt = addedAt
        self.changeGeneration = changeGeneration
    }
}

public enum WatchedSourceDatabaseError: LocalizedError, Sendable {
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case databaseClosed
    case sourceNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "Chronoframe could not open its watched-folders records. Details: \(message)"
        case let .executionFailed(message):
            return "Chronoframe could not update its watched-folders records. Details: \(message)"
        case let .prepareFailed(message):
            return "Chronoframe could not prepare its watched-folders records. Details: \(message)"
        case let .stepFailed(message):
            return "Chronoframe could not read its watched-folders records. Details: \(message)"
        case .databaseClosed:
            return "Chronoframe lost access to its watched-folders records. Try again."
        case let .sourceNotFound(id):
            return "Chronoframe could not find that watched folder's records. Details: \(id.uuidString)"
        }
    }
}

/// App-side SQLite store for the watched-sources registry and per-source
/// acknowledged checkpoints.
///
/// Lives in Application Support, NOT at any destination: the standing
/// freshness path must work with the destination offline and must never
/// write there. Registry rows and checkpoint rows commit in the same
/// immediate transaction, so add/remove/re-pick are atomic with respect
/// to this store; callers order UserDefaults bookmark writes around
/// these calls and roll the bookmark back if the transaction fails.
///
/// Checkpoints scale to the 100k-file target: per-source rows with a
/// composite primary key, rewritten in a single transaction via a
/// reused prepared statement — no monolithic JSON decode/encode cycles.
///
/// Corruption is quarantined, never silently emptied: if the file fails
/// to open or its quick_check fails, it is renamed aside
/// (`<name>.corrupt-<timestamp>`) with its WAL/SHM siblings, a fresh
/// store is created, and `didQuarantineCorruptStore` is set so the UI
/// can tell the user their watched folders needed to be re-checked.
public final class WatchedSourceCheckpointDatabase: @unchecked Sendable {
    static let currentSchemaVersion = 1

    private let url: URL
    private var database: OpaquePointer?
    public private(set) var didQuarantineCorruptStore = false

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        do {
            try openAndPrepare()
        } catch {
            // First failure: quarantine whatever is on disk and start
            // fresh exactly once. A second failure is a real error.
            try Self.quarantine(storeAt: url)
            didQuarantineCorruptStore = true
            try openAndPrepare()
        }
    }

    deinit {
        close()
    }

    public func close() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    // MARK: - Registry

    public func loadSources() throws -> [WatchedSource] {
        let statement = try prepare(
            "SELECT id, path, label, added_at, change_generation FROM WatchedSources ORDER BY added_at, id"
        )
        defer { sqlite3_finalize(statement) }

        var sources: [WatchedSource] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
            }
            guard
                let idString = Self.columnString(statement, 0),
                let id = UUID(uuidString: idString),
                let path = Self.columnString(statement, 1),
                let label = Self.columnString(statement, 2)
            else {
                // A malformed row is skipped rather than poisoning the
                // whole registry; quarantine handles wholesale corruption.
                continue
            }
            sources.append(WatchedSource(
                id: id,
                path: path,
                label: label,
                addedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3)),
                changeGeneration: sqlite3_column_int64(statement, 4)
            ))
        }
        return sources
    }

    /// Registers a source and seeds its acknowledged checkpoint in one
    /// transaction.
    public func addSource(
        _ source: WatchedSource,
        initialCheckpoint: [String: WatchedFileStamp]
    ) throws {
        try inImmediateTransaction {
            let insert = try prepare(
                "INSERT INTO WatchedSources(id, path, label, added_at, change_generation) VALUES (?, ?, ?, ?, ?)"
            )
            defer { sqlite3_finalize(insert) }
            sqlite3_bind_text(insert, 1, source.id.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_text(insert, 2, source.path, -1, Self.sqliteTransient)
            sqlite3_bind_text(insert, 3, source.label, -1, Self.sqliteTransient)
            sqlite3_bind_double(insert, 4, source.addedAt.timeIntervalSince1970)
            sqlite3_bind_int64(insert, 5, source.changeGeneration)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
            }
            try writeCheckpointRows(sourceID: source.id, entries: initialCheckpoint)
        }
    }

    /// Removes a source and its checkpoint in one transaction.
    public func removeSource(id: UUID) throws {
        try inImmediateTransaction {
            try executeBoundDelete("DELETE FROM Checkpoint WHERE source_id = ?", id: id)
            try executeBoundDelete("DELETE FROM WatchedSources WHERE id = ?", id: id)
        }
    }

    /// Re-pick: replaces the stored path under the same identity. When
    /// the resolved path actually changed the checkpoint is cleared in
    /// the same transaction (the old acknowledgments describe a
    /// different tree).
    public func replaceSourcePath(id: UUID, newPath: String, clearCheckpoint: Bool) throws {
        try inImmediateTransaction {
            let update = try prepare("UPDATE WatchedSources SET path = ? WHERE id = ?")
            defer { sqlite3_finalize(update) }
            sqlite3_bind_text(update, 1, newPath, -1, Self.sqliteTransient)
            sqlite3_bind_text(update, 2, id.uuidString, -1, Self.sqliteTransient)
            guard sqlite3_step(update) == SQLITE_DONE else {
                throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
            }
            guard sqlite3_changes(database) > 0 else {
                throw WatchedSourceDatabaseError.sourceNotFound(id)
            }
            if clearCheckpoint {
                try executeBoundDelete("DELETE FROM Checkpoint WHERE source_id = ?", id: id)
            }
        }
    }

    /// Bumps and returns the source's attention generation.
    @discardableResult
    public func bumpChangeGeneration(id: UUID) throws -> Int64 {
        var generation: Int64 = 0
        try inImmediateTransaction {
            let update = try prepare(
                "UPDATE WatchedSources SET change_generation = change_generation + 1 WHERE id = ?"
            )
            defer { sqlite3_finalize(update) }
            sqlite3_bind_text(update, 1, id.uuidString, -1, Self.sqliteTransient)
            guard sqlite3_step(update) == SQLITE_DONE else {
                throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
            }
            guard sqlite3_changes(database) > 0 else {
                throw WatchedSourceDatabaseError.sourceNotFound(id)
            }

            let select = try prepare("SELECT change_generation FROM WatchedSources WHERE id = ?")
            defer { sqlite3_finalize(select) }
            sqlite3_bind_text(select, 1, id.uuidString, -1, Self.sqliteTransient)
            guard sqlite3_step(select) == SQLITE_ROW else {
                throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
            }
            generation = sqlite3_column_int64(select, 0)
        }
        return generation
    }

    // MARK: - Checkpoints

    public func checkpoint(for id: UUID) throws -> [String: WatchedFileStamp] {
        let statement = try prepare(
            "SELECT rel_path, size, mtime_ns, ctime_ns FROM Checkpoint WHERE source_id = ?"
        )
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, Self.sqliteTransient)

        var entries: [String: WatchedFileStamp] = [:]
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
            }
            guard let relPath = Self.columnString(statement, 0) else { continue }
            entries[relPath] = WatchedFileStamp(
                sizeBytes: sqlite3_column_int64(statement, 1),
                mtimeNanoseconds: sqlite3_column_int64(statement, 2),
                ctimeNanoseconds: sqlite3_column_int64(statement, 3)
            )
        }
        return entries
    }

    /// Rewrites the source's acknowledged checkpoint atomically. Callers
    /// compute the new set with `WatchedSourceFreshness.merged`/`pruned`;
    /// the database never decides what is acknowledged.
    public func replaceCheckpoint(for id: UUID, entries: [String: WatchedFileStamp]) throws {
        try inImmediateTransaction {
            try executeBoundDelete("DELETE FROM Checkpoint WHERE source_id = ?", id: id)
            try writeCheckpointRows(sourceID: id, entries: entries)
        }
    }

    // MARK: - Setup and helpers

    private func openAndPrepare() throws {
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = Self.errorMessage(from: handle)
            sqlite3_close(handle)
            throw WatchedSourceDatabaseError.openFailed(message)
        }
        database = handle

        do {
            try execute("PRAGMA busy_timeout=30000;")
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=FULL;")

            let quickCheck = try scalarString("PRAGMA quick_check;")
            guard quickCheck.lowercased() == "ok" else {
                throw WatchedSourceDatabaseError.openFailed("quick_check reported: \(quickCheck)")
            }

            try execute(
                """
                CREATE TABLE IF NOT EXISTS WatchedSources (
                    id TEXT PRIMARY KEY,
                    path TEXT NOT NULL,
                    label TEXT NOT NULL,
                    added_at REAL NOT NULL,
                    change_generation INTEGER NOT NULL DEFAULT 0
                );
                """
            )
            try execute(
                """
                CREATE TABLE IF NOT EXISTS Checkpoint (
                    source_id TEXT NOT NULL,
                    rel_path TEXT NOT NULL,
                    size INTEGER NOT NULL,
                    mtime_ns INTEGER NOT NULL,
                    ctime_ns INTEGER NOT NULL,
                    PRIMARY KEY (source_id, rel_path)
                );
                """
            )
            try execute("CREATE TABLE IF NOT EXISTS Meta (key TEXT PRIMARY KEY, value TEXT);")
            try execute(
                """
                INSERT INTO Meta(key, value) VALUES ('schema_version', '\(Self.currentSchemaVersion)')
                ON CONFLICT(key) DO NOTHING;
                """
            )
        } catch {
            close()
            throw error
        }
    }

    private static func quarantine(storeAt url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let quarantineURL = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(timestamp)")
        try fileManager.moveItem(at: url, to: quarantineURL)
        // WAL/SHM siblings describe the quarantined main file; move them
        // alongside so the fresh store starts clean.
        for suffix in ["-wal", "-shm"] {
            let sibling = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: sibling.path) {
                try? fileManager.moveItem(
                    at: sibling,
                    to: URL(fileURLWithPath: quarantineURL.path + suffix)
                )
            }
        }
    }

    private func writeCheckpointRows(sourceID: UUID, entries: [String: WatchedFileStamp]) throws {
        guard !entries.isEmpty else { return }
        let insert = try prepare(
            "REPLACE INTO Checkpoint(source_id, rel_path, size, mtime_ns, ctime_ns) VALUES (?, ?, ?, ?, ?)"
        )
        defer { sqlite3_finalize(insert) }
        for (relPath, stamp) in entries {
            sqlite3_bind_text(insert, 1, sourceID.uuidString, -1, Self.sqliteTransient)
            sqlite3_bind_text(insert, 2, relPath, -1, Self.sqliteTransient)
            sqlite3_bind_int64(insert, 3, stamp.sizeBytes)
            sqlite3_bind_int64(insert, 4, stamp.mtimeNanoseconds)
            sqlite3_bind_int64(insert, 5, stamp.ctimeNanoseconds)
            guard sqlite3_step(insert) == SQLITE_DONE else {
                throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
            }
            sqlite3_reset(insert)
        }
    }

    private func executeBoundDelete(_ sql: String, id: UUID) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, id.uuidString, -1, Self.sqliteTransient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
        }
    }

    private func inImmediateTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw WatchedSourceDatabaseError.databaseClosed }
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw WatchedSourceDatabaseError.executionFailed(lastErrorMessage())
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else { throw WatchedSourceDatabaseError.databaseClosed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            throw WatchedSourceDatabaseError.prepareFailed(lastErrorMessage())
        }
        return statement
    }

    private func scalarString(_ sql: String) throws -> String {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else {
            throw WatchedSourceDatabaseError.stepFailed(lastErrorMessage())
        }
        return Self.columnString(statement, 0) ?? ""
    }

    private func lastErrorMessage() -> String {
        Self.errorMessage(from: database)
    }

    private static func errorMessage(from database: OpaquePointer?) -> String {
        if let database, let message = sqlite3_errmsg(database) {
            return String(cString: message)
        }
        return "Unknown SQLite error"
    }

    private static func columnString(_ statement: OpaquePointer?, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}
