import Foundation
import XCTest
@testable import ChronoframeCore

/// Milestone 2b — `DedupeVideoFeatures` persistence. Pure SQLite, no
/// AVFoundation, fully deterministic: round-trip, four-state status caching,
/// frame-slot serialization (incl. nil slots), version/size/mtime invalidation,
/// and pruning isolation from the photo table.
final class DedupeVideoFeatureCacheTests: XCTestCase {

    private func makeDatabase() throws -> (OrganizerDatabase, URL) {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VideoFeatureCache-\(UUID().uuidString).db")
        let db = try OrganizerDatabase(url: url)
        try db.ensureDedupeVideoFeaturesSchema()
        return (db, url)
    }

    private func feature(
        _ path: String,
        size: Int64 = 1000,
        mtime: TimeInterval = 123.5,
        frames: [UInt64?] = [1, nil, 3, 4, nil],
        status: VideoDecodeStatus = .ready
    ) -> VideoPerceptualFeatures {
        VideoPerceptualFeatures(
            path: path,
            size: size,
            modificationTime: mtime,
            durationSeconds: 12.34,
            transformedWidth: 1920,
            transformedHeight: 1080,
            frameHashes: frames,
            status: status,
            folderRoot: "/lib"
        )
    }

    // MARK: - Frame-hash serialization

    func testFrameHashEncodingRoundTripsIncludingNilSlots() {
        let cases: [[UInt64?]] = [
            [1, 2, 3, 4, 5],
            [nil, 2, nil, 4, nil],
            [nil, nil, nil, nil, nil],
            [0xFFFF_FFFF_FFFF_FFFF, nil, 0, nil, 7],
            [],
        ]
        for hashes in cases {
            let data = DedupeVideoFeatureRecord.encodeFrameHashes(hashes)
            XCTAssertEqual(DedupeVideoFeatureRecord.decodeFrameHashes(data), hashes, "round-trip failed for \(hashes)")
        }
    }

    // MARK: - Round-trip

    func testSaveAndLoadRoundTrip() throws {
        let (db, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        let record = DedupeVideoFeatureRecord(features: feature("/lib/a.mp4"))
        try db.saveDedupeVideoFeatureRecords([record])

        let loaded = try db.loadDedupeVideoFeatureRecords()
        XCTAssertEqual(loaded["/lib/a.mp4"], record)
        XCTAssertEqual(loaded["/lib/a.mp4"]?.features.frameHashes, [1, nil, 3, 4, nil])
        XCTAssertEqual(loaded["/lib/a.mp4"]?.features.status, .ready)
    }

    func testNonReadyStatusesArePersisted() throws {
        let (db, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        try db.saveDedupeVideoFeatureRecords([
            DedupeVideoFeatureRecord(features: feature("/lib/u.mkv", frames: [], status: .unsupported)),
            DedupeVideoFeatureRecord(features: feature("/lib/f.mp4", frames: [], status: .decodeFailed)),
            DedupeVideoFeatureRecord(features: feature("/lib/s.mp4", frames: [1, nil, nil, nil, nil], status: .insufficientVisualEvidence)),
        ])

        let loaded = try db.loadDedupeVideoFeatureRecords()
        XCTAssertEqual(loaded["/lib/u.mkv"]?.features.status, .unsupported)
        XCTAssertEqual(loaded["/lib/f.mp4"]?.features.status, .decodeFailed)
        XCTAssertEqual(loaded["/lib/s.mp4"]?.features.status, .insufficientVisualEvidence)
    }

    // MARK: - Invalidation

    func testIsValidTracksSizeMtimeAndVersions() {
        let record = DedupeVideoFeatureRecord(features: feature("/lib/a.mp4", size: 1000, mtime: 50))
        XCTAssertTrue(record.isValid(size: 1000, modificationTime: 50))
        XCTAssertFalse(record.isValid(size: 1001, modificationTime: 50), "size change invalidates")
        XCTAssertFalse(record.isValid(size: 1000, modificationTime: 51), "mtime change invalidates")

        let staleAnalyzer = DedupeVideoFeatureRecord(
            features: feature("/lib/a.mp4", size: 1000, mtime: 50),
            analyzerVersion: VideoPerceptualAnalysis.analyzerVersion - 1
        )
        XCTAssertFalse(staleAnalyzer.isValid(size: 1000, modificationTime: 50), "older analyzer version invalidates")

        let staleStrategy = DedupeVideoFeatureRecord(
            features: feature("/lib/a.mp4", size: 1000, mtime: 50),
            sampleStrategyVersion: VideoPerceptualAnalysis.sampleStrategyVersion + 1
        )
        XCTAssertFalse(staleStrategy.isValid(size: 1000, modificationTime: 50), "different sample-strategy version invalidates")
    }

    // MARK: - Prune isolation

    func testPruneRemovesOnlyMissingPathsAndLeavesPhotoTableAlone() throws {
        let (db, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }
        try db.ensureDedupeFeaturesSchema()
        try db.saveDedupeFeatureRecords([DedupeFeatureRecord(path: "/lib/photo.jpg", size: 10, modificationTime: 1)])

        try db.saveDedupeVideoFeatureRecords([
            DedupeVideoFeatureRecord(features: feature("/lib/keep.mp4")),
            DedupeVideoFeatureRecord(features: feature("/lib/gone.mp4")),
        ])

        try db.pruneDedupeVideoFeatureRecords(notIn: ["/lib/keep.mp4"])

        let videos = try db.loadDedupeVideoFeatureRecords()
        XCTAssertNotNil(videos["/lib/keep.mp4"])
        XCTAssertNil(videos["/lib/gone.mp4"])
        // Photo table untouched by the video prune.
        XCTAssertNotNil(try db.loadDedupeFeatureRecords()["/lib/photo.jpg"])
    }

    func testReplaceUpdatesExistingRow() throws {
        let (db, url) = try makeDatabase()
        defer { try? FileManager.default.removeItem(at: url) }

        try db.saveDedupeVideoFeatureRecords([DedupeVideoFeatureRecord(features: feature("/lib/a.mp4", status: .ready))])
        try db.saveDedupeVideoFeatureRecords([DedupeVideoFeatureRecord(features: feature("/lib/a.mp4", frames: [], status: .decodeFailed))])

        let loaded = try db.loadDedupeVideoFeatureRecords()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded["/lib/a.mp4"]?.features.status, .decodeFailed)
    }
}
