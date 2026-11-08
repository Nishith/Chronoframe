import Foundation
import SQLite3

/// Local SQLite store for NAS exact-duplicate assessments (C-06).
///
/// The file always lives on this Mac (Application Support), never on the
/// assessed library, so WAL is allowed here.
public final class NASAssessmentStore: @unchecked Sendable {
    public static let algorithmVersion = 1

    private var database: OpaquePointer?
    private let lock = NSLock()

    public init(url: URL, libraryUUID: String) throws {
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw NASAssessmentError.storeFailed(message: error.localizedDescription)
        }

        // Same anchor sequence as OrganizerDatabase: open without following
        // links, then confirm SQLite opened that same file.
        let anchor = try DestinationMetadataFile.openAnchor(at: url)

        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = Self.errorMessage(from: handle)
            sqlite3_close(handle)
            throw NASAssessmentError.storeFailed(message: message)
        }

        do {
            try anchor.confirmPathStillRefersToFile()
        } catch {
            sqlite3_close(handle)
            throw error
        }

        database = handle

        do {
            try execute("PRAGMA busy_timeout=30000;")
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=FULL;")
            try execute("PRAGMA foreign_keys=ON;")
            try initializeSchema()
            try bindLibrary(libraryUUID)
        } catch {
            close()
            throw error
        }
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        defer { lock.unlock() }
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    // MARK: - Scans

    public func beginScan(mode: NASScanMode, startedAt: Date) throws -> Int64 {
        try locked {
            try inTransaction {
                let next = try queryOne("SELECT COALESCE(MAX(generation), 0) + 1 FROM Scans;", []) { Self.int64($0, 0) } ?? 1
                try run(
                    "INSERT INTO Scans (generation, mode, algorithmVersion, startedAt, outcome) VALUES (?, ?, ?, ?, ?);",
                    [.int(next), .text(mode.rawValue), .int(Int64(Self.algorithmVersion)), .double(startedAt.timeIntervalSince1970), .text(NASScanOutcome.running.rawValue)]
                )
                return next
            }
        }
    }

    public func latestGeneration(excluding generation: Int64? = nil) throws -> Int64? {
        try locked {
            if let generation {
                return try queryOne("SELECT MAX(generation) FROM Scans WHERE generation != ?;", [.int(generation)]) { Self.optionalInt64($0, 0) } ?? nil
            }
            return try queryOne("SELECT MAX(generation) FROM Scans;", []) { Self.optionalInt64($0, 0) } ?? nil
        }
    }

    public func finishScan(
        generation: Int64,
        outcome: NASScanOutcome,
        counts: NASScanCounts,
        ledger: NASByteLedger,
        finishedAt: Date
    ) throws {
        let countsJSON = try Self.encode(counts)
        let ledgerJSON = try Self.encode(ledger)
        try locked {
            try run(
                "UPDATE Scans SET outcome = ?, countsJSON = ?, ledgerJSON = ?, finishedAt = ? WHERE generation = ?;",
                [.text(outcome.rawValue), .text(countsJSON), .text(ledgerJSON), .double(finishedAt.timeIntervalSince1970), .int(generation)]
            )
        }
    }

    public func scanSummary(generation: Int64) throws -> NASScanSummary? {
        try locked {
            struct ScanRow {
                var mode: String
                var startedAt: Double
                var finishedAt: Double?
                var outcome: String
                var countsJSON: String
                var ledgerJSON: String
            }
            let row = try queryOne(
                "SELECT mode, startedAt, finishedAt, outcome, countsJSON, ledgerJSON FROM Scans WHERE generation = ?;",
                [.int(generation)]
            ) { statement in
                ScanRow(
                    mode: Self.text(statement, 0) ?? "",
                    startedAt: sqlite3_column_double(statement, 1),
                    finishedAt: sqlite3_column_type(statement, 2) == SQLITE_NULL ? nil : sqlite3_column_double(statement, 2),
                    outcome: Self.text(statement, 3) ?? "",
                    countsJSON: Self.text(statement, 4) ?? "{}",
                    ledgerJSON: Self.text(statement, 5) ?? "{}"
                )
            }
            guard let row else { return nil }
            guard let mode = NASScanMode(rawValue: row.mode), let outcome = NASScanOutcome(rawValue: row.outcome) else {
                throw NASAssessmentError.storeFailed(message: "Unrecognized scan values for generation \(generation).")
            }
            let counts: NASScanCounts = try Self.decode(row.countsJSON, defaultIfEmpty: NASScanCounts())
            let ledger: NASByteLedger = try Self.decode(row.ledgerJSON, defaultIfEmpty: NASByteLedger())
            let groups = try exactGroupsUnlocked(generation: generation)
            return NASScanSummary(
                generation: generation,
                mode: mode,
                startedAt: Date(timeIntervalSince1970: row.startedAt),
                finishedAt: row.finishedAt.map { Date(timeIntervalSince1970: $0) },
                outcome: outcome,
                counts: counts,
                ledger: ledger,
                exactGroupCount: groups.count,
                redundantLogicalBytes: groups.reduce(Int64(0)) { $0 + $1.redundantLogicalBytes }
            )
        }
    }

    public func incrementPreviewRequests(generation: Int64) throws {
        try locked {
            try run("UPDATE Scans SET previewRequests = previewRequests + 1 WHERE generation = ?;", [.int(generation)])
        }
    }

    public func pruneGenerations(keepingLatest count: Int) throws {
        try locked {
            try inTransaction {
                let keep = Int64(max(count, 0))
                let cutoffSQL = "SELECT generation FROM Scans ORDER BY generation DESC LIMIT ?"
                for table in ["Items", "Directories", "Issues"] {
                    try run("DELETE FROM \(table) WHERE generation NOT IN (\(cutoffSQL));", [.int(keep)])
                }
                try run("DELETE FROM Scans WHERE generation NOT IN (\(cutoffSQL));", [.int(keep)])
            }
        }
    }

    // MARK: - Directories, items, issues

    public func recordDirectories(_ rows: [NASDirectoryRow], generation: Int64) throws {
        try locked {
            try inTransaction {
                try runBatch(
                    "INSERT OR REPLACE INTO Directories (generation, relativePath, status, mediaFileCount, mediaBytes, unsupportedFileCount) VALUES (?, ?, ?, ?, ?, ?);",
                    rows.map { row in
                        [.int(generation), .text(row.relativePath), .text(row.status.rawValue), .int(Int64(row.mediaFileCount)), .int(row.mediaBytes), .int(Int64(row.unsupportedFileCount))]
                    }
                )
            }
        }
    }

    public func recordItems(_ rows: [NASItemRow], generation: Int64) throws {
        try locked {
            try inTransaction {
                try runBatch(
                    "INSERT OR REPLACE INTO Items (generation, relativePath, kind, size, modificationTime, fileID, digest, hashState, unresolvedReason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
                    rows.map { row in
                        [
                            .int(generation), .text(row.relativePath), .text(row.kind.rawValue), .int(row.size),
                            .double(row.modificationTime), .int(Int64(bitPattern: row.fileID)),
                            row.digest.map { .text($0) } ?? .null, .text(row.hashState.rawValue),
                            row.unresolvedReason.map { .text($0.rawValue) } ?? .null,
                        ]
                    }
                )
            }
        }
    }

    public func recordIssues(_ issues: [NASIssue], generation: Int64) throws {
        try locked {
            try inTransaction {
                try runBatch(
                    "INSERT INTO Issues (generation, relativePath, category, detail) VALUES (?, ?, ?, ?);",
                    issues.map { [.int(generation), .text($0.relativePath), .text($0.category.rawValue), .text($0.detail)] }
                )
            }
        }
    }

    public func markCandidates(generation: Int64) throws -> (candidateFiles: Int, candidateBytesH: Int64, emptyFiles: Int) {
        try locked {
            try inTransaction {
                // Only rows that have not been hashed or resolved are (re)classified.
                try run(
                    "UPDATE Items SET hashState = 'emptyFile' WHERE generation = ? AND size = 0 AND hashState IN ('notCandidate', 'pending', 'emptyFile');",
                    [.int(generation)]
                )
                try run(
                    """
                    UPDATE Items SET hashState = 'pending'
                    WHERE generation = ? AND size > 0 AND hashState IN ('notCandidate', 'pending')
                      AND size IN (SELECT size FROM Items WHERE generation = ? AND size > 0 GROUP BY size HAVING COUNT(size) >= 2);
                    """,
                    [.int(generation), .int(generation)]
                )
                let candidates = try queryOne(
                    """
                    SELECT COUNT(*), COALESCE(SUM(size), 0) FROM Items
                    WHERE generation = ? AND size > 0
                      AND size IN (SELECT size FROM Items WHERE generation = ? AND size > 0 GROUP BY size HAVING COUNT(size) >= 2);
                    """,
                    [.int(generation), .int(generation)]
                ) { (Int(Self.int64($0, 0)), Self.int64($0, 1)) } ?? (0, 0)
                let empty = try queryOne(
                    "SELECT COUNT(*) FROM Items WHERE generation = ? AND size = 0;",
                    [.int(generation)]
                ) { Int(Self.int64($0, 0)) } ?? 0
                return (candidates.0, candidates.1, empty)
            }
        }
    }

    public func pendingItems(generation: Int64) throws -> [NASItemRow] {
        try locked {
            try itemRows(
                where: "generation = ? AND hashState = 'pending'",
                orderBy: "size DESC, relativePath",
                [.int(generation)]
            )
        }
    }

    public func reusableDigests(generation: Int64) throws -> [String: NASItemRow] {
        try locked {
            let rows = try itemRows(where: "generation = ? AND hashState = 'hashed'", orderBy: "relativePath", [.int(generation)])
            return Dictionary(rows.map { ($0.relativePath, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func updateHashResults(_ rows: [NASItemRow], generation: Int64) throws {
        try locked {
            try inTransaction {
                try runBatch(
                    "UPDATE Items SET digest = ?, hashState = ?, unresolvedReason = ? WHERE generation = ? AND relativePath = ?;",
                    rows.map { row in
                        [
                            row.digest.map { .text($0) } ?? .null, .text(row.hashState.rawValue),
                            row.unresolvedReason.map { .text($0.rawValue) } ?? .null,
                            .int(generation), .text(row.relativePath),
                        ]
                    }
                )
            }
        }
    }

    public func exactGroups(generation: Int64) throws -> [NASExactGroup] {
        try locked { try exactGroupsUnlocked(generation: generation) }
    }

    public func directoryRows(generation: Int64) throws -> [NASDirectoryRow] {
        try locked {
            try query(
                "SELECT relativePath, status, mediaFileCount, mediaBytes, unsupportedFileCount FROM Directories WHERE generation = ? ORDER BY relativePath;",
                [.int(generation)]
            ) { statement in
                guard let status = NASDirectoryStatus(rawValue: Self.text(statement, 1) ?? "") else {
                    throw NASAssessmentError.storeFailed(message: "Unrecognized directory status.")
                }
                return NASDirectoryRow(
                    relativePath: Self.text(statement, 0) ?? "",
                    status: status,
                    mediaFileCount: Int(Self.int64(statement, 2)),
                    mediaBytes: Self.int64(statement, 3),
                    unsupportedFileCount: Int(Self.int64(statement, 4))
                )
            }
        }
    }

    public func issues(generation: Int64) throws -> [NASIssue] {
        try locked {
            try query(
                "SELECT category, relativePath, detail FROM Issues WHERE generation = ? ORDER BY rowid;",
                [.int(generation)]
            ) { statement in
                guard let category = NASIssueCategory(rawValue: Self.text(statement, 0) ?? "") else {
                    throw NASAssessmentError.storeFailed(message: "Unrecognized issue category.")
                }
                return NASIssue(category: category, relativePath: Self.text(statement, 1) ?? "", detail: Self.text(statement, 2) ?? "")
            }
        }
    }

    // MARK: - Review

    public func saveChoice(_ choice: NASReviewChoice) throws {
        try locked {
            try run(
                "INSERT OR REPLACE INTO ReviewChoices (digest, size, keeperRelativePath, reviewedAt) VALUES (?, ?, ?, ?);",
                [.text(choice.digest), .int(choice.size), choice.keeperRelativePath.map { .text($0) } ?? .null, .double(choice.reviewedAt.timeIntervalSince1970)]
            )
        }
    }

    public func choices() throws -> [String: NASReviewChoice] {
        try locked {
            let rows = try query("SELECT digest, size, keeperRelativePath, reviewedAt FROM ReviewChoices;", []) { statement in
                NASReviewChoice(
                    digest: Self.text(statement, 0) ?? "",
                    size: Self.int64(statement, 1),
                    keeperRelativePath: Self.text(statement, 2),
                    reviewedAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 3))
                )
            }
            return Dictionary(rows.map { ($0.digest, $0) }, uniquingKeysWith: { first, _ in first })
        }
    }

    public func setReviewState(_ value: String?, forKey key: String) throws {
        try locked {
            if let value {
                try run("INSERT OR REPLACE INTO ReviewState (key, value) VALUES (?, ?);", [.text(key), .text(value)])
            } else {
                try run("DELETE FROM ReviewState WHERE key = ?;", [.text(key)])
            }
        }
    }

    public func reviewState(forKey key: String) throws -> String? {
        try locked {
            try queryOne("SELECT value FROM ReviewState WHERE key = ?;", [.text(key)]) { Self.text($0, 0) } ?? nil
        }
    }

    // MARK: - Internals

    private enum Value {
        case int(Int64)
        case double(Double)
        case text(String)
        case null
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        guard database != nil else {
            throw NASAssessmentError.storeFailed(message: "The assessment store is closed.")
        }
        return try body()
    }

    private func inTransaction<T>(_ body: () throws -> T) throws -> T {
        try execute("BEGIN IMMEDIATE;")
        do {
            let result = try body()
            try execute("COMMIT;")
            return result
        } catch {
            sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
            throw error
        }
    }

    private func initializeSchema() throws {
        let statements = [
            "CREATE TABLE IF NOT EXISTS Meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
            """
            CREATE TABLE IF NOT EXISTS Scans (
              generation INTEGER PRIMARY KEY,
              mode TEXT NOT NULL,
              algorithmVersion INTEGER NOT NULL,
              startedAt REAL NOT NULL,
              finishedAt REAL,
              outcome TEXT NOT NULL,
              countsJSON TEXT NOT NULL DEFAULT '{}',
              ledgerJSON TEXT NOT NULL DEFAULT '{}',
              previewRequests INTEGER NOT NULL DEFAULT 0
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS Directories (
              generation INTEGER NOT NULL,
              relativePath TEXT NOT NULL,
              status TEXT NOT NULL,
              mediaFileCount INTEGER NOT NULL DEFAULT 0,
              mediaBytes INTEGER NOT NULL DEFAULT 0,
              unsupportedFileCount INTEGER NOT NULL DEFAULT 0,
              PRIMARY KEY (generation, relativePath)
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS Items (
              generation INTEGER NOT NULL,
              relativePath TEXT NOT NULL,
              kind TEXT NOT NULL,
              size INTEGER NOT NULL,
              modificationTime REAL NOT NULL,
              fileID INTEGER NOT NULL,
              digest TEXT,
              hashState TEXT NOT NULL,
              unresolvedReason TEXT,
              PRIMARY KEY (generation, relativePath)
            );
            """,
            "CREATE INDEX IF NOT EXISTS ItemsBySize ON Items(generation, size);",
            "CREATE INDEX IF NOT EXISTS ItemsByDigest ON Items(generation, digest);",
            "CREATE TABLE IF NOT EXISTS Issues (generation INTEGER NOT NULL, relativePath TEXT NOT NULL, category TEXT NOT NULL, detail TEXT NOT NULL);",
            "CREATE TABLE IF NOT EXISTS ReviewChoices (digest TEXT PRIMARY KEY, size INTEGER NOT NULL, keeperRelativePath TEXT, reviewedAt REAL NOT NULL);",
            "CREATE TABLE IF NOT EXISTS ReviewState (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
        ]
        try inTransaction {
            for statement in statements {
                try execute(statement)
            }
            try run("INSERT OR IGNORE INTO Meta (key, value) VALUES ('schemaVersion', '1');", [])
        }
    }

    private func bindLibrary(_ libraryUUID: String) throws {
        let existing = try queryOne("SELECT value FROM Meta WHERE key = 'libraryUUID';", []) { Self.text($0, 0) } ?? nil
        if let existing {
            guard existing == libraryUUID else {
                throw NASAssessmentError.storeLibraryMismatch(expected: libraryUUID, found: existing)
            }
        } else {
            try run("INSERT INTO Meta (key, value) VALUES ('libraryUUID', ?);", [.text(libraryUUID)])
        }
    }

    private func exactGroupsUnlocked(generation: Int64) throws -> [NASExactGroup] {
        struct Member {
            var digest: String
            var size: Int64
            var kind: NASItemKind
            var relativePath: String
        }
        let members = try query(
            """
            SELECT digest, size, kind, relativePath FROM Items
            WHERE generation = ? AND hashState = 'hashed' AND digest IS NOT NULL
              AND digest IN (SELECT digest FROM Items WHERE generation = ? AND hashState = 'hashed' AND digest IS NOT NULL GROUP BY digest HAVING COUNT(*) >= 2)
            ORDER BY digest, relativePath;
            """,
            [.int(generation), .int(generation)]
        ) { statement -> Member in
            guard let kind = NASItemKind(rawValue: Self.text(statement, 2) ?? "") else {
                throw NASAssessmentError.storeFailed(message: "Unrecognized item kind.")
            }
            return Member(digest: Self.text(statement, 0) ?? "", size: Self.int64(statement, 1), kind: kind, relativePath: Self.text(statement, 3) ?? "")
        }

        var groups: [NASExactGroup] = []
        for member in members {
            if let last = groups.last, last.digest == member.digest {
                groups[groups.count - 1].memberRelativePaths.append(member.relativePath)
            } else {
                groups.append(NASExactGroup(digest: member.digest, size: member.size, kind: member.kind, memberRelativePaths: [member.relativePath]))
            }
        }
        return groups.sorted {
            if $0.redundantLogicalBytes != $1.redundantLogicalBytes {
                return $0.redundantLogicalBytes > $1.redundantLogicalBytes
            }
            return $0.digest < $1.digest
        }
    }

    private func itemRows(where condition: String, orderBy: String, _ values: [Value]) throws -> [NASItemRow] {
        try query(
            "SELECT relativePath, kind, size, modificationTime, fileID, digest, hashState, unresolvedReason FROM Items WHERE \(condition) ORDER BY \(orderBy);",
            values
        ) { statement in
            guard let kind = NASItemKind(rawValue: Self.text(statement, 1) ?? ""),
                  let hashState = NASItemHashState(rawValue: Self.text(statement, 6) ?? "")
            else {
                throw NASAssessmentError.storeFailed(message: "Unrecognized item values.")
            }
            let reason: NASUnresolvedReason?
            if let raw = Self.text(statement, 7) {
                guard let parsed = NASUnresolvedReason(rawValue: raw) else {
                    throw NASAssessmentError.storeFailed(message: "Unrecognized unresolved reason.")
                }
                reason = parsed
            } else {
                reason = nil
            }
            return NASItemRow(
                relativePath: Self.text(statement, 0) ?? "",
                kind: kind,
                size: Self.int64(statement, 2),
                modificationTime: sqlite3_column_double(statement, 3),
                fileID: UInt64(bitPattern: Self.int64(statement, 4)),
                digest: Self.text(statement, 5),
                hashState: hashState,
                unresolvedReason: reason
            )
        }
    }

    // MARK: SQLite plumbing

    private func execute(_ sql: String) throws {
        var errorPointer: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? Self.errorMessage(from: database)
            sqlite3_free(errorPointer)
            throw NASAssessmentError.storeFailed(message: message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let message = Self.errorMessage(from: database)
            sqlite3_finalize(statement)
            throw NASAssessmentError.storeFailed(message: message)
        }
        return statement
    }

    private func bind(_ values: [Value], to statement: OpaquePointer) throws {
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let status: Int32
            switch value {
            case let .int(number): status = sqlite3_bind_int64(statement, index, number)
            case let .double(number): status = sqlite3_bind_double(statement, index, number)
            case let .text(string): status = sqlite3_bind_text(statement, index, string, -1, transient)
            case .null: status = sqlite3_bind_null(statement, index)
            }
            guard status == SQLITE_OK else {
                throw NASAssessmentError.storeFailed(message: Self.errorMessage(from: database))
            }
        }
    }

    private func run(_ sql: String, _ values: [Value]) throws {
        try runBatch(sql, [values])
    }

    private func runBatch(_ sql: String, _ batch: [[Value]]) throws {
        guard !batch.isEmpty else { return }
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for values in batch {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            try bind(values, to: statement)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw NASAssessmentError.storeFailed(message: Self.errorMessage(from: database))
            }
        }
    }

    private func query<T>(_ sql: String, _ values: [Value], row: (OpaquePointer) throws -> T) throws -> [T] {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        try bind(values, to: statement)
        var results: [T] = []
        while true {
            let status = sqlite3_step(statement)
            if status == SQLITE_ROW {
                results.append(try row(statement))
            } else if status == SQLITE_DONE {
                return results
            } else {
                throw NASAssessmentError.storeFailed(message: Self.errorMessage(from: database))
            }
        }
    }

    private func queryOne<T>(_ sql: String, _ values: [Value], row: (OpaquePointer) throws -> T) throws -> T? {
        try query(sql, values, row: row).first
    }

    private static func errorMessage(from handle: OpaquePointer?) -> String {
        guard let handle, let message = sqlite3_errmsg(handle) else { return "Unknown SQLite error." }
        return String(cString: message)
    }

    private static func text(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let pointer = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: pointer)
    }

    private static func int64(_ statement: OpaquePointer, _ column: Int32) -> Int64 {
        sqlite3_column_int64(statement, column)
    }

    private static func optionalInt64(_ statement: OpaquePointer, _ column: Int32) -> Int64? {
        sqlite3_column_type(statement, column) == SQLITE_NULL ? nil : sqlite3_column_int64(statement, column)
    }

    private static func encode<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        do {
            return String(decoding: try encoder.encode(value), as: UTF8.self)
        } catch {
            throw NASAssessmentError.storeFailed(message: "Could not encode scan data: \(error.localizedDescription)")
        }
    }

    private static func decode<T: Decodable>(_ json: String, defaultIfEmpty: T) throws -> T {
        if json == "{}" { return defaultIfEmpty }
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            throw NASAssessmentError.storeFailed(message: "Could not read scan data: \(error.localizedDescription)")
        }
    }
}
