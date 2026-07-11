import Foundation
import SQLite3

// MARK: - Guardian manifest store (Phase 1)
//
// The trusted-baseline manifest for one library, persisted as SQLite. It lives in
// Application Support keyed by the library's identity — never inside the library —
// so scrub and mirror never write into a library whose bytes must stay untouched.
//
// The store records its digest algorithm, digest-format version, and path
// normalization in a Meta table. A manifest whose recorded algorithm/format does
// not match today's is rejected (`incompatibleManifest`) rather than silently
// reinterpreted with different rules.

public enum GuardianManifestStoreError: LocalizedError, Sendable, Equatable {
    case openFailed(String)
    case executionFailed(String)
    case prepareFailed(String)
    case stepFailed(String)
    case databaseClosed
    /// The on-disk manifest was written with a digest algorithm/format or path
    /// normalization this build does not understand. It is quarantined, not reused.
    case incompatibleManifest(String)

    public var errorDescription: String? {
        switch self {
        case let .openFailed(message):
            return "Chronoframe could not open its library-protection records. Check that the disk is available, then try again. Details: \(message)"
        case let .executionFailed(message):
            return "Chronoframe could not update its library-protection records. Details: \(message)"
        case let .prepareFailed(message):
            return "Chronoframe could not prepare its library-protection records. Details: \(message)"
        case let .stepFailed(message):
            return "Chronoframe could not read its library-protection records. Details: \(message)"
        case .databaseClosed:
            return "Chronoframe lost access to its library-protection records. Try again."
        case let .incompatibleManifest(message):
            return "Chronoframe found library-protection records in a format this version does not understand, so it left them untouched. Details: \(message)"
        }
    }
}

public final class GuardianManifestStore: @unchecked Sendable {
    private var database: OpaquePointer?

    /// Open (creating if needed) the manifest at `url`, associating it with
    /// `libraryIdentity` on first creation. Throws `incompatibleManifest` if an
    /// existing manifest was written with an unknown digest algorithm/format.
    public init(url: URL, libraryIdentity: GuardianLibraryIdentity) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = Self.errorMessage(from: handle)
            sqlite3_close(handle)
            throw GuardianManifestStoreError.openFailed(message)
        }
        database = handle

        try execute("PRAGMA busy_timeout=30000;")
        try execute("PRAGMA journal_mode=WAL;")
        try execute("PRAGMA synchronous=FULL;")
        try initializeSchema()
        try reconcileMeta(libraryIdentity: libraryIdentity)
    }

    deinit { close() }

    public func close() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    // MARK: - Schema & meta

    private func initializeSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS Meta (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS ManifestEntries (
                relative_path TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                mtime REAL NOT NULL,
                digest TEXT NOT NULL,
                trust_state TEXT NOT NULL,
                provenance TEXT,
                first_observed_at REAL NOT NULL,
                last_verified_at REAL
            );
            """
        )
    }

    private func reconcileMeta(libraryIdentity: GuardianLibraryIdentity) throws {
        let algorithm = try metaValue(forKey: "digest_algorithm")
        if let algorithm {
            // Existing manifest: verify it matches this build's understanding.
            guard algorithm == GuardianManifestVersion.digestAlgorithm else {
                throw GuardianManifestStoreError.incompatibleManifest("digest algorithm \(algorithm)")
            }
            let format = try metaValue(forKey: "digest_format_version")
            guard format == String(GuardianManifestVersion.digestFormatVersion) else {
                throw GuardianManifestStoreError.incompatibleManifest("digest format \(format ?? "nil")")
            }
            let normalization = try metaValue(forKey: "path_normalization")
            guard normalization == GuardianManifestVersion.pathNormalization else {
                throw GuardianManifestStoreError.incompatibleManifest("path normalization \(normalization ?? "nil")")
            }
            return
        }

        // Fresh manifest: stamp the versioning and identity.
        try setMeta("schema_version", String(GuardianManifestVersion.schema))
        try setMeta("digest_algorithm", GuardianManifestVersion.digestAlgorithm)
        try setMeta("digest_format_version", String(GuardianManifestVersion.digestFormatVersion))
        try setMeta("path_normalization", GuardianManifestVersion.pathNormalization)
        try setMeta("library_uuid", libraryIdentity.libraryUUID)
        if let volume = libraryIdentity.volumeIdentifier {
            try setMeta("volume_identifier", volume)
        }
    }

    public func libraryIdentity() throws -> GuardianLibraryIdentity {
        GuardianLibraryIdentity(
            libraryUUID: (try metaValue(forKey: "library_uuid")) ?? "",
            volumeIdentifier: try metaValue(forKey: "volume_identifier")
        )
    }

    // MARK: - Entries

    /// Insert or replace the given entries in one transaction.
    public func upsert(_ entries: [GuardianManifestEntry]) throws {
        guard !entries.isEmpty else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let statement = try prepare(
                """
                INSERT INTO ManifestEntries
                    (relative_path, size, mtime, digest, trust_state, provenance, first_observed_at, last_verified_at)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(relative_path) DO UPDATE SET
                    size = excluded.size,
                    mtime = excluded.mtime,
                    digest = excluded.digest,
                    trust_state = excluded.trust_state,
                    provenance = excluded.provenance,
                    first_observed_at = excluded.first_observed_at,
                    last_verified_at = excluded.last_verified_at;
                """
            )
            defer { sqlite3_finalize(statement) }
            for entry in entries {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bindText(statement, 1, entry.relativePath)
                sqlite3_bind_int64(statement, 2, entry.size)
                sqlite3_bind_double(statement, 3, entry.modificationTime)
                bindText(statement, 4, entry.digest)
                bindText(statement, 5, entry.trustState.rawValue)
                if let provenance = entry.provenance {
                    bindText(statement, 6, provenance.rawValue)
                } else {
                    sqlite3_bind_null(statement, 6)
                }
                sqlite3_bind_double(statement, 7, entry.firstObservedAt.timeIntervalSince1970)
                if let verified = entry.lastVerifiedAt {
                    sqlite3_bind_double(statement, 8, verified.timeIntervalSince1970)
                } else {
                    sqlite3_bind_null(statement, 8)
                }
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw GuardianManifestStoreError.stepFailed(lastErrorMessage())
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    /// Remove entries by canonical relative path (used only for explicit,
    /// acknowledged deletions — the scan path never deletes rows on its own).
    public func delete(relativePaths: [String]) throws {
        guard !relativePaths.isEmpty else { return }
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            let statement = try prepare("DELETE FROM ManifestEntries WHERE relative_path = ?;")
            defer { sqlite3_finalize(statement) }
            for path in relativePaths {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bindText(statement, 1, path)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw GuardianManifestStoreError.stepFailed(lastErrorMessage())
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func loadAll() throws -> [GuardianManifestEntry] {
        let statement = try prepare(
            "SELECT relative_path, size, mtime, digest, trust_state, provenance, first_observed_at, last_verified_at FROM ManifestEntries;"
        )
        defer { sqlite3_finalize(statement) }

        var entries: [GuardianManifestEntry] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw GuardianManifestStoreError.stepFailed(lastErrorMessage())
            }
            guard
                let path = Self.columnText(statement, 0),
                let digest = Self.columnText(statement, 3),
                let trustRaw = Self.columnText(statement, 4),
                let trustState = GuardianTrustState(rawValue: trustRaw)
            else {
                throw GuardianManifestStoreError.stepFailed("damaged manifest row")
            }
            let provenanceRaw: String? = Self.columnText(statement, 5)
            let provenance: GuardianTrustProvenance? = provenanceRaw.flatMap(GuardianTrustProvenance.init(rawValue:))
            let lastVerified: Date?
            if sqlite3_column_type(statement, 7) == SQLITE_NULL {
                lastVerified = nil
            } else {
                lastVerified = Date(timeIntervalSince1970: sqlite3_column_double(statement, 7))
            }
            entries.append(
                GuardianManifestEntry(
                    relativePath: path,
                    size: sqlite3_column_int64(statement, 1),
                    modificationTime: sqlite3_column_double(statement, 2),
                    digest: digest,
                    trustState: trustState,
                    provenance: provenance,
                    firstObservedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
                    lastVerifiedAt: lastVerified
                )
            )
        }
        return entries
    }

    /// Convenience: the manifest keyed by canonical relative path.
    public func loadKeyed() throws -> [String: GuardianManifestEntry] {
        var keyed: [String: GuardianManifestEntry] = [:]
        for entry in try loadAll() {
            keyed[entry.relativePath] = entry
        }
        return keyed
    }

    // MARK: - Meta helpers

    private func metaValue(forKey key: String) throws -> String? {
        let statement = try prepare("SELECT value FROM Meta WHERE key = ?;")
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, key)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return nil }
        guard step == SQLITE_ROW else {
            throw GuardianManifestStoreError.stepFailed(lastErrorMessage())
        }
        return Self.columnText(statement, 0)
    }

    private func setMeta(_ key: String, _ value: String) throws {
        let statement = try prepare(
            "INSERT INTO Meta(key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;"
        )
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, key)
        bindText(statement, 2, value)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw GuardianManifestStoreError.stepFailed(lastErrorMessage())
        }
    }

    // MARK: - Low-level SQLite

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw GuardianManifestStoreError.databaseClosed }
        var errorPointer: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorPointer)
            throw GuardianManifestStoreError.executionFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else { throw GuardianManifestStoreError.databaseClosed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = lastErrorMessage()
            sqlite3_finalize(statement)
            throw GuardianManifestStoreError.prepareFailed(message)
        }
        return statement
    }

    private func lastErrorMessage() -> String {
        Self.errorMessage(from: database)
    }

    private static func errorMessage(from handle: OpaquePointer?) -> String {
        guard let handle, let cString = sqlite3_errmsg(handle) else { return "unknown error" }
        return String(cString: cString)
    }

    private static func columnText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }
}
