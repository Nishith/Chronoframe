import Foundation
import SQLite3

/// Cached perceptual analysis for one video, persisted in the same
/// `.organize_cache.db` as the photo feature and file-identity caches. A row is
/// valid only while the file's `(size, mtime)` is unchanged **and** the
/// analyzer / sample-strategy versions match — bumping either version
/// deliberately invalidates every row so a change to how frames are sampled or
/// hashed forces re-analysis.
///
/// Critically this also caches non-`ready` outcomes: an `unsupported` container
/// or an `insufficientVisualEvidence` clip (too short / too static) is recorded
/// once and skipped on later scans, so the expensive decode + low-variance
/// discard is not retried every run.
public struct DedupeVideoFeatureRecord: Equatable, Sendable {
    public var features: VideoPerceptualFeatures
    public var analyzerVersion: Int
    public var sampleStrategyVersion: Int

    public init(
        features: VideoPerceptualFeatures,
        analyzerVersion: Int = VideoPerceptualAnalysis.analyzerVersion,
        sampleStrategyVersion: Int = VideoPerceptualAnalysis.sampleStrategyVersion
    ) {
        self.features = features
        self.analyzerVersion = analyzerVersion
        self.sampleStrategyVersion = sampleStrategyVersion
    }

    /// Whether this cached row can be trusted for the file currently on disk.
    public func isValid(size: Int64, modificationTime: TimeInterval) -> Bool {
        features.size == size
            && abs(features.modificationTime - modificationTime) < 0.001
            && analyzerVersion == VideoPerceptualAnalysis.analyzerVersion
            && sampleStrategyVersion == VideoPerceptualAnalysis.sampleStrategyVersion
    }

    // MARK: - Frame-hash serialization

    /// Encode positionally-aligned frame slots into a compact blob: a presence
    /// bitmask byte, a slot-count byte, then 8 little-endian bytes per present
    /// slot. Nil slots (discarded low-variance / failed frames) are preserved so
    /// the matcher can keep aligning copies by fraction.
    public static func encodeFrameHashes(_ hashes: [UInt64?]) -> Data {
        precondition(hashes.count <= 8, "frame-hash bitmask supports up to 8 slots")
        var data = Data()
        var mask: UInt8 = 0
        for (index, value) in hashes.enumerated() where value != nil {
            mask |= (1 << UInt8(index))
        }
        data.append(mask)
        data.append(UInt8(hashes.count))
        for value in hashes {
            guard var little = value?.littleEndian else { continue }
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        return data
    }

    public static func decodeFrameHashes(_ data: Data) -> [UInt64?] {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return [] }
        let mask = bytes[0]
        let count = Int(bytes[1])
        var result: [UInt64?] = []
        result.reserveCapacity(count)
        var offset = 2
        for index in 0..<count {
            if (mask & (1 << UInt8(index % 8))) != 0 {
                guard offset + 8 <= bytes.count else { result.append(nil); continue }
                var value: UInt64 = 0
                for byteIndex in 0..<8 {
                    value |= UInt64(bytes[offset + byteIndex]) << (8 * byteIndex)
                }
                result.append(UInt64(littleEndian: value))
                offset += 8
            } else {
                result.append(nil)
            }
        }
        return result
    }
}

extension OrganizerDatabase {
    /// Idempotent — adds the `DedupeVideoFeatures` table if absent. Kept
    /// separate from `DedupeFeatures` so the video pruning lane never touches
    /// photo rows (and vice versa).
    public func ensureDedupeVideoFeaturesSchema() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS DedupeVideoFeatures (
                path TEXT PRIMARY KEY,
                size INTEGER NOT NULL,
                mtime REAL NOT NULL,
                duration REAL NOT NULL,
                transformed_width INTEGER NOT NULL,
                transformed_height INTEGER NOT NULL,
                status TEXT NOT NULL,
                analyzer_version INTEGER NOT NULL,
                sample_strategy_version INTEGER NOT NULL,
                frame_hashes BLOB,
                folder_root TEXT,
                estimated_data_rate REAL NOT NULL DEFAULT 0,
                metadata_completeness INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        // Additive migration for caches created by the exact/perceptual MVP.
        // Duplicate-column errors simply mean the cache is already current.
        try? execute("ALTER TABLE DedupeVideoFeatures ADD COLUMN estimated_data_rate REAL NOT NULL DEFAULT 0;")
        try? execute("ALTER TABLE DedupeVideoFeatures ADD COLUMN metadata_completeness INTEGER NOT NULL DEFAULT 0;")
    }

    public func loadDedupeVideoFeatureRecords() throws -> [String: DedupeVideoFeatureRecord] {
        var rows: [String: DedupeVideoFeatureRecord] = [:]
        let statement = try prepare(
            """
            SELECT path, size, mtime, duration, transformed_width, transformed_height,
                   status, analyzer_version, sample_strategy_version, frame_hashes, folder_root,
                   estimated_data_rate, metadata_completeness
            FROM DedupeVideoFeatures
            """
        )
        defer { sqlite3_finalize(statement) }

        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw OrganizerDatabaseError.stepFailed(lastErrorMessage())
            }
            guard let path = OrganizerDatabase.sqliteString(statement, column: 0),
                  let statusRaw = OrganizerDatabase.sqliteString(statement, column: 6),
                  let status = VideoDecodeStatus(rawValue: statusRaw)
            else { continue }

            let size = sqlite3_column_int64(statement, 1)
            let mtime = sqlite3_column_double(statement, 2)
            let duration = sqlite3_column_double(statement, 3)
            let width = Int(sqlite3_column_int64(statement, 4))
            let height = Int(sqlite3_column_int64(statement, 5))
            let analyzerVersion = Int(sqlite3_column_int64(statement, 7))
            let sampleVersion = Int(sqlite3_column_int64(statement, 8))

            var frameHashes: [UInt64?] = []
            if sqlite3_column_type(statement, 9) == SQLITE_BLOB,
               let pointer = sqlite3_column_blob(statement, 9) {
                let count = Int(sqlite3_column_bytes(statement, 9))
                frameHashes = DedupeVideoFeatureRecord.decodeFrameHashes(Data(bytes: pointer, count: count))
            }

            let folderRoot = OrganizerDatabase.sqliteString(statement, column: 10)
            let estimatedDataRate = sqlite3_column_double(statement, 11)
            let metadataCompleteness = Int(sqlite3_column_int64(statement, 12))

            rows[path] = DedupeVideoFeatureRecord(
                features: VideoPerceptualFeatures(
                    path: path,
                    size: size,
                    modificationTime: mtime,
                    durationSeconds: duration,
                    transformedWidth: width,
                    transformedHeight: height,
                    estimatedDataRate: estimatedDataRate,
                    metadataCompleteness: metadataCompleteness,
                    frameHashes: frameHashes,
                    status: status,
                    folderRoot: folderRoot
                ),
                analyzerVersion: analyzerVersion,
                sampleStrategyVersion: sampleVersion
            )
        }
        return rows
    }

    public func saveDedupeVideoFeatureRecords<S: Sequence>(_ records: S) throws where S.Element == DedupeVideoFeatureRecord {
        let statement = try prepare(
            """
            REPLACE INTO DedupeVideoFeatures
            (path, size, mtime, duration, transformed_width, transformed_height,
             status, analyzer_version, sample_strategy_version, frame_hashes, folder_root,
             estimated_data_rate, metadata_completeness)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
        )
        defer { sqlite3_finalize(statement) }

        var wroteAny = false
        do {
            for record in records {
                if !wroteAny {
                    try execute("BEGIN IMMEDIATE TRANSACTION;")
                    wroteAny = true
                }
                let f = record.features
                sqlite3_reset(statement)
                sqlite3_clear_bindings(statement)
                sqlite3_bind_text(statement, 1, f.path, -1, OrganizerDatabase.sqliteTransient)
                sqlite3_bind_int64(statement, 2, f.size)
                sqlite3_bind_double(statement, 3, f.modificationTime)
                sqlite3_bind_double(statement, 4, f.durationSeconds)
                sqlite3_bind_int64(statement, 5, Int64(f.transformedWidth))
                sqlite3_bind_int64(statement, 6, Int64(f.transformedHeight))
                sqlite3_bind_text(statement, 7, f.status.rawValue, -1, OrganizerDatabase.sqliteTransient)
                sqlite3_bind_int64(statement, 8, Int64(record.analyzerVersion))
                sqlite3_bind_int64(statement, 9, Int64(record.sampleStrategyVersion))
                let blob = DedupeVideoFeatureRecord.encodeFrameHashes(f.frameHashes)
                _ = blob.withUnsafeBytes { rawBuffer in
                    sqlite3_bind_blob(statement, 10, rawBuffer.baseAddress, Int32(blob.count), OrganizerDatabase.sqliteTransient)
                }
                if let folderRoot = f.folderRoot {
                    sqlite3_bind_text(statement, 11, folderRoot, -1, OrganizerDatabase.sqliteTransient)
                } else {
                    sqlite3_bind_null(statement, 11)
                }
                sqlite3_bind_double(statement, 12, f.estimatedDataRate)
                sqlite3_bind_int64(statement, 13, Int64(f.metadataCompleteness))
                guard sqlite3_step(statement) == SQLITE_DONE else {
                    throw OrganizerDatabaseError.stepFailed(lastErrorMessage())
                }
            }
            if wroteAny {
                try execute("COMMIT;")
            }
        } catch {
            if wroteAny {
                try? execute("ROLLBACK;")
            }
            throw error
        }
    }

    /// Delete rows for any path no longer present in `currentPaths`. Only the
    /// video table is touched — photo features are pruned separately.
    public func pruneDedupeVideoFeatureRecords(notIn currentPaths: Set<String>) throws {
        let statement = try prepare("SELECT path FROM DedupeVideoFeatures")
        defer { sqlite3_finalize(statement) }

        var stale: [String] = []
        while true {
            let stepResult = sqlite3_step(statement)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw OrganizerDatabaseError.stepFailed(lastErrorMessage())
            }
            guard let path = OrganizerDatabase.sqliteString(statement, column: 0) else { continue }
            if !currentPaths.contains(path) { stale.append(path) }
        }
        guard !stale.isEmpty else { return }

        let deleteStatement = try prepare("DELETE FROM DedupeVideoFeatures WHERE path = ?")
        defer { sqlite3_finalize(deleteStatement) }

        try execute("BEGIN IMMEDIATE TRANSACTION;")
        do {
            for path in stale {
                sqlite3_reset(deleteStatement)
                sqlite3_clear_bindings(deleteStatement)
                sqlite3_bind_text(deleteStatement, 1, path, -1, OrganizerDatabase.sqliteTransient)
                guard sqlite3_step(deleteStatement) == SQLITE_DONE else {
                    throw OrganizerDatabaseError.stepFailed(lastErrorMessage())
                }
            }
            try execute("COMMIT;")
        } catch {
            try? execute("ROLLBACK;")
            throw error
        }
    }
}
