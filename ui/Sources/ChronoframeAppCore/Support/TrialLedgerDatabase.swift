#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import SQLite3

// MARK: - SQLite-backed reservation ledger (free-trial step 3)
//
// One database per Mac, at `…/Application Support/Chronoframe/trial/ledger.db`,
// with rows scoped by Apple Account key.
//
// CONCURRENCY. WAL plus `BEGIN IMMEDIATE` gives cross-process write
// serialization, and every mutating operation below is exactly one transaction.
// There is deliberately NO separate advisory lock file: it would add a deadlock
// surface and buy nothing SQLite does not already provide. Where a destination
// lease and a ledger transaction are both needed, the order is destination lease
// first, then ledger — and a ledger transaction is never held across filesystem
// work.

public final class TrialLedgerDatabase: TrialLedger, @unchecked Sendable {
    private var database: OpaquePointer?
    private let caps: TrialAllowanceCaps
    private let lock = NSLock()

    public init(url: URL, caps: TrialAllowanceCaps = .standard) throws {
        self.caps = caps

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        } catch {
            throw TrialLedgerError.openFailed(error.localizedDescription)
        }

        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = Self.errorMessage(from: handle)
            sqlite3_close(handle)
            throw TrialLedgerError.openFailed(message)
        }
        database = handle

        // A corrupt or foreign file opens lazily and only fails here, on the
        // first real statement. That failure must propagate: the caller turns it
        // into a fail-closed, zero-remaining balance rather than a fresh one.
        do {
            try execute("PRAGMA busy_timeout=30000;")
            try execute("PRAGMA journal_mode=WAL;")
            try execute("PRAGMA synchronous=FULL;")
            try initializeSchema()
        } catch {
            close()
            throw TrialLedgerError.unreadable(Self.message(from: error))
        }
    }

    deinit { close() }

    public func close() {
        if let database {
            sqlite3_close(database)
            self.database = nil
        }
    }

    // MARK: - Schema

    /// Schema version. Bump only alongside a migration.
    public static let schemaVersion: Int32 = 1

    private func initializeSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS Reservations (
                run_id           TEXT PRIMARY KEY,
                account_key      TEXT NOT NULL,
                meter            TEXT NOT NULL,
                reserved_count   INTEGER NOT NULL,
                finalized_count  INTEGER,
                state            TEXT NOT NULL,
                destination_root TEXT,
                created_at       TEXT NOT NULL,
                updated_at       TEXT NOT NULL
            );
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_reservations_state ON Reservations(state);")
        try execute("CREATE INDEX IF NOT EXISTS idx_reservations_account ON Reservations(account_key);")

        // Item-level, NOT one row per receipt. Reverts are routinely partial:
        // the invariant "revert deletes only destination files whose current
        // hash still matches the receipt" means a changed or unavailable file is
        // preserved and skipped. A per-receipt row with INSERT OR IGNORE would
        // freeze the first partial refund forever, so a later revert that
        // restores the remaining items would be silently dropped. Recording each
        // restored item makes repeat and partial reverts exact, and still
        // idempotent.
        try execute(
            """
            CREATE TABLE IF NOT EXISTS RefundedItems (
                receipt_run_id  TEXT NOT NULL,
                item_path       TEXT NOT NULL,
                account_key     TEXT NOT NULL,
                meter           TEXT NOT NULL,
                created_at      TEXT NOT NULL,
                PRIMARY KEY (receipt_run_id, item_path)
            );
            """
        )
        try execute("CREATE INDEX IF NOT EXISTS idx_refunded_account ON RefundedItems(account_key, meter);")
        try execute("PRAGMA user_version = \(Self.schemaVersion);")
    }

    // MARK: - Reading

    public func balance(accountKey: String) throws -> TrialBalance {
        lock.lock()
        defer { lock.unlock() }
        return try balanceLocked(accountKey: accountKey)
    }

    private func balanceLocked(accountKey: String) throws -> TrialBalance {
        TrialBalance(
            caps: caps,
            usage: TrialUsage(
                organizeUsed: try usedLocked(accountKey: accountKey, meter: .organize),
                dedupeUsed: try usedLocked(accountKey: accountKey, meter: .dedupe)
            )
        )
    }

    /// Usage for one account and meter: each reservation's charge, less the
    /// items that reservation's own revert gave back, summed.
    ///
    /// Two clauses carry the whole design and neither may be "simplified":
    ///
    /// `COALESCE(finalized_count, reserved_count)` over
    /// `state IN ('open','finalized')` is the fail-closed mechanism, and the
    /// reason there is no crash-handling branch anywhere in this file: an OPEN
    /// reservation — which is what a crash leaves behind — counts at its FULL
    /// reserved amount until reconciliation finalizes it with the count that
    /// actually happened.
    ///
    /// Refunds are netted PER RESERVATION and floored at zero, rather than
    /// summed across the account and subtracted at the end. That difference is
    /// load-bearing in two directions:
    ///
    ///   - A refund for a receipt with no charged reservation contributes
    ///     nothing. An account-wide subtraction would let a revert of unmetered
    ///     work — a run from before enforcement shipped, or a receipt whose
    ///     reservation was released — bank a credit that silently enlarged the
    ///     next real run's allowance.
    ///   - A reservation can never be refunded past what it was charged, so the
    ///     floor here is a proof rather than a defensive clamp: every term is
    ///     `MAX(0, charge − refunds)`, so the sum cannot go negative and cannot
    ///     borrow headroom from a sibling reservation.
    private func usedLocked(accountKey: String, meter: TrialMeter) throws -> Int {
        try scalar(
            """
            SELECT COALESCE(SUM(MAX(0,
                COALESCE(finalized_count, reserved_count) - (
                    SELECT COUNT(*) FROM RefundedItems ri
                    WHERE ri.receipt_run_id = Reservations.run_id
                      AND ri.account_key = Reservations.account_key
                      AND ri.meter = Reservations.meter
                )
            )), 0)
            FROM Reservations
            WHERE account_key = ? AND meter = ? AND state IN ('open','finalized');
            """,
            accountKey,
            meter.rawValue
        )
    }

    public func openReservations() throws -> [OpenReservation] {
        lock.lock()
        defer { lock.unlock() }

        let statement = try prepare(
            """
            SELECT run_id, account_key, meter, reserved_count, destination_root, created_at
            FROM Reservations WHERE state = 'open' ORDER BY created_at, run_id;
            """
        )
        defer { sqlite3_finalize(statement) }

        var reservations: [OpenReservation] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            guard step == SQLITE_ROW else {
                throw TrialLedgerError.unreadable(lastErrorMessage())
            }
            guard
                let runIDText = Self.columnText(statement, 0),
                let runID = UUID(uuidString: runIDText),
                let accountKey = Self.columnText(statement, 1),
                let meterRaw = Self.columnText(statement, 2),
                let meter = TrialMeter(rawValue: meterRaw),
                let createdAtText = Self.columnText(statement, 5),
                let createdAt = Self.date(from: createdAtText)
            else {
                // A row we cannot interpret is not silently dropped from the
                // charge — `usedLocked` still counts it. Skipping it here only
                // means reconciliation cannot resolve it, which is the
                // fail-closed direction.
                continue
            }
            reservations.append(
                OpenReservation(
                    runID: runID,
                    accountKey: accountKey,
                    meter: meter,
                    reservedCount: Int(sqlite3_column_int64(statement, 3)),
                    destinationRoot: Self.columnText(statement, 4),
                    createdAt: createdAt
                )
            )
        }
        return reservations
    }

    // MARK: - Writing

    public func reserve(
        runID: UUID,
        accountKey: String,
        meter: TrialMeter,
        count: Int,
        destinationRoot: String?
    ) throws -> ReservationDecision {
        lock.lock()
        defer { lock.unlock() }

        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            // Re-reserving a runID returns the stored decision unchanged. Only
            // permitted reservations are ever written, so an existing row means
            // this run was already permitted — a resumed transfer or a retried
            // gate must not stack a second charge on the same work.
            if try rowExistsLocked(runID: runID) {
                try execute("COMMIT;")
                return .permitted
            }

            let decision = TrialAllowancePolicy.decide(
                requested: count,
                meter: meter,
                balance: try balanceLocked(accountKey: accountKey)
            )
            guard decision.isPermitted else {
                // A refusal writes NOTHING. Rolling back rather than committing
                // makes that structural instead of a promise.
                try execute("ROLLBACK;")
                return decision
            }

            let now = Self.timestamp(Date())
            let statement = try prepare(
                """
                INSERT INTO Reservations
                    (run_id, account_key, meter, reserved_count, finalized_count,
                     state, destination_root, created_at, updated_at)
                VALUES (?, ?, ?, ?, NULL, 'open', ?, ?, ?);
                """
            )
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, runID.uuidString)
            bindText(statement, 2, accountKey)
            bindText(statement, 3, meter.rawValue)
            sqlite3_bind_int64(statement, 4, Int64(max(0, count)))
            if let destinationRoot {
                bindText(statement, 5, destinationRoot)
            } else {
                sqlite3_bind_null(statement, 5)
            }
            bindText(statement, 6, now)
            bindText(statement, 7, now)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TrialLedgerError.writeFailed(lastErrorMessage())
            }

            try execute("COMMIT;")
            return .permitted
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    public func finalize(runID: UUID, actualCount: Int) throws {
        lock.lock()
        defer { lock.unlock() }

        // `state = 'open'` in the WHERE clause is what makes this idempotent:
        // a second finalize, or a finalize racing a release, matches no row.
        // The clamp keeps a miscounted executor from charging more than was
        // authorized at the gate, or from crediting a negative count.
        try inTransaction {
            let statement = try prepare(
                """
                UPDATE Reservations
                SET finalized_count = MAX(0, MIN(?, reserved_count)),
                    state = 'finalized',
                    updated_at = ?
                WHERE run_id = ? AND state = 'open';
                """
            )
            defer { sqlite3_finalize(statement) }
            sqlite3_bind_int64(statement, 1, Int64(actualCount))
            bindText(statement, 2, Self.timestamp(Date()))
            bindText(statement, 3, runID.uuidString)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TrialLedgerError.writeFailed(lastErrorMessage())
            }
        }
    }

    public func release(runID: UUID) throws {
        lock.lock()
        defer { lock.unlock() }

        try inTransaction {
            let statement = try prepare(
                """
                UPDATE Reservations
                SET finalized_count = 0, state = 'released', updated_at = ?
                WHERE run_id = ? AND state = 'open';
                """
            )
            defer { sqlite3_finalize(statement) }
            bindText(statement, 1, Self.timestamp(Date()))
            bindText(statement, 2, runID.uuidString)
            guard sqlite3_step(statement) == SQLITE_DONE else {
                throw TrialLedgerError.writeFailed(lastErrorMessage())
            }
        }
    }

    public func refund(
        receiptRunID: UUID,
        accountKey: String,
        meter: TrialMeter,
        itemPaths: [String]
    ) throws {
        guard !itemPaths.isEmpty else { return }

        lock.lock()
        defer { lock.unlock() }

        try inTransaction {
            let statement = try prepare(
                """
                INSERT OR IGNORE INTO RefundedItems
                    (receipt_run_id, item_path, account_key, meter, created_at)
                VALUES (?, ?, ?, ?, ?);
                """
            )
            defer { sqlite3_finalize(statement) }
            let now = Self.timestamp(Date())
            for path in itemPaths {
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                bindText(statement, 1, receiptRunID.uuidString)
                bindText(statement, 2, path)
                bindText(statement, 3, accountKey)
                bindText(statement, 4, meter.rawValue)
                bindText(statement, 5, now)
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw TrialLedgerError.writeFailed(lastErrorMessage())
                }
            }
        }
    }

    public func accountKey(forRunID runID: UUID) throws -> String? {
        lock.lock()
        defer { lock.unlock() }

        let statement = try prepare(
            "SELECT account_key FROM Reservations WHERE run_id = ? LIMIT 1;"
        )
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, runID.uuidString)

        let step = sqlite3_step(statement)
        if step == SQLITE_ROW {
            return Self.columnText(statement, 0)
        }
        guard step == SQLITE_DONE else {
            throw TrialLedgerError.unreadable(lastErrorMessage())
        }
        return nil
    }

    // MARK: - Low-level SQLite

    private func rowExistsLocked(runID: UUID) throws -> Bool {
        let statement = try prepare("SELECT 1 FROM Reservations WHERE run_id = ? LIMIT 1;")
        defer { sqlite3_finalize(statement) }
        bindText(statement, 1, runID.uuidString)
        let step = sqlite3_step(statement)
        if step == SQLITE_ROW { return true }
        guard step == SQLITE_DONE else {
            throw TrialLedgerError.unreadable(lastErrorMessage())
        }
        return false
    }

    private func inTransaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            try body()
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }

    private func scalar(_ sql: String, _ arguments: String...) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        for (offset, argument) in arguments.enumerated() {
            bindText(statement, Int32(offset + 1), argument)
        }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else {
            throw TrialLedgerError.unreadable(lastErrorMessage())
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    private static let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    private func bindText(_ statement: OpaquePointer?, _ index: Int32, _ value: String) {
        sqlite3_bind_text(statement, index, value, -1, Self.sqliteTransient)
    }

    private func execute(_ sql: String) throws {
        guard let database else { throw TrialLedgerError.databaseClosed }
        var errorPointer: UnsafeMutablePointer<Int8>?
        guard sqlite3_exec(database, sql, nil, nil, &errorPointer) == SQLITE_OK else {
            let message = errorPointer.map { String(cString: $0) } ?? "unknown error"
            sqlite3_free(errorPointer)
            throw TrialLedgerError.writeFailed(message)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        guard let database else { throw TrialLedgerError.databaseClosed }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK else {
            let message = lastErrorMessage()
            sqlite3_finalize(statement)
            throw TrialLedgerError.unreadable(message)
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

    private static func message(from error: Error) -> String {
        if let ledgerError = error as? TrialLedgerError {
            switch ledgerError {
            case let .openFailed(message),
                 let .unreadable(message),
                 let .writeFailed(message):
                return message
            case .databaseClosed:
                return "database closed"
            }
        }
        return error.localizedDescription
    }

    // MARK: - Timestamps

    // Built per call rather than shared: `ISO8601DateFormatter` is not
    // `Sendable`, and the ledger writes rarely enough that the allocation is
    // irrelevant next to the SQLite transaction around it.
    private static func timestampFormatter() -> ISO8601DateFormatter {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }

    private static func timestamp(_ date: Date) -> String {
        timestampFormatter().string(from: date)
    }

    /// Parses the fractional-second form this file writes, and falls back to the
    /// plain internet date-time form so a row written by any other tooling still
    /// reconciles instead of being skipped.
    private static func date(from text: String) -> Date? {
        if let parsed = timestampFormatter().date(from: text) { return parsed }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        plain.timeZone = TimeZone(secondsFromGMT: 0)
        return plain.date(from: text)
    }
}
