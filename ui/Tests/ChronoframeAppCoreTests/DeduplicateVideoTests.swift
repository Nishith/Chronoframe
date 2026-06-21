import Foundation
import XCTest
@testable import ChronoframeCore

/// Milestone 1 — exact video duplicate detection. Covers the structural
/// guarantees that make videos safe to add to the existing dedupe pipeline:
/// videos never touch the image analyzer, byte-identical videos cluster,
/// keeper choice is deterministic, perceptual video can never auto-delete,
/// and the receipt format evolves tolerantly.
final class DeduplicateVideoTests: XCTestCase {

    // MARK: - Image analyzer isolation

    /// Records every URL handed to the image analyzer so the test can prove
    /// videos are never routed through it.
    private final class RecordingImageAnalyzer: DedupeImageAnalyzing, @unchecked Sendable {
        private let lock = NSLock()
        private(set) var analyzedURLs: [URL] = []

        func analyze(url: URL, size: Int64) -> DedupeImageAnalysis {
            lock.lock()
            analyzedURLs.append(url)
            lock.unlock()
            return DedupeImageAnalysis(
                captureDate: nil,
                pixelWidth: nil,
                pixelHeight: nil,
                dhash: nil,
                featurePrintData: nil,
                featurePrintFailureMessage: nil,
                quality: PhotoQualityScore(composite: 0, sharpness: 0, faceScore: nil)
            )
        }
    }

    // AGENTS-INVARIANT: 1
    // Videos are constructed through a separate minimal lane and must never
    // be passed to `DefaultDedupeImageAnalyzer` (which would mis-decode them
    // and emit warning noise). The source file is also never opened for
    // pixel analysis — only hashed for identity.
    func testVideoCandidatesNeverEnterImageAnalyzer() async throws {
        let dir = try makeTempDir("VideoNotAnalyzed")
        defer { try? FileManager.default.removeItem(at: dir) }

        // Distinct photos (not duplicates of each other) so the only exact
        // cluster comes from the videos.
        try Data(repeating: 0x22, count: 256).write(to: dir.appendingPathComponent("a.jpg"))
        try Data(repeating: 0x23, count: 256).write(to: dir.appendingPathComponent("b.jpg"))
        // Two byte-identical videos plus one unique video.
        try Data(repeating: 0x33, count: 4096).write(to: dir.appendingPathComponent("clip1.mp4"))
        try Data(repeating: 0x33, count: 4096).write(to: dir.appendingPathComponent("clip2.mp4"))
        try Data(repeating: 0x44, count: 8192).write(to: dir.appendingPathComponent("unique.mov"))

        let spy = RecordingImageAnalyzer()
        let scanner = DeduplicateScanner(imageAnalyzer: spy)
        let summary = try await runScan(scanner, destination: dir.path)

        let analyzedExtensions = Set(spy.analyzedURLs.map { $0.pathExtension.lowercased() })
        XCTAssertFalse(analyzedExtensions.contains("mp4"), "videos must not enter the image analyzer")
        XCTAssertFalse(analyzedExtensions.contains("mov"), "videos must not enter the image analyzer")
        XCTAssertTrue(analyzedExtensions.isSubset(of: ["jpg"]))
        // The two identical videos still form an exact-duplicate cluster.
        XCTAssertEqual(summary.clusterCounts[.exactDuplicate], 1)
    }

    // MARK: - Exact video duplicates

    func testExactVideoDuplicatesClusterAndUniqueVideoDoesNot() async throws {
        let dir = try makeTempDir("VideoExact")
        defer { try? FileManager.default.removeItem(at: dir) }

        try Data(repeating: 0x55, count: 2048).write(to: dir.appendingPathComponent("dup_a.mp4"))
        try Data(repeating: 0x55, count: 2048).write(to: dir.appendingPathComponent("dup_b.mp4"))
        try Data(repeating: 0x66, count: 2048).write(to: dir.appendingPathComponent("other.mp4")) // same size, different bytes
        try Data(repeating: 0x77, count: 999).write(to: dir.appendingPathComponent("solo.mkv"))   // unique size

        let scanner = DeduplicateScanner()
        var clusters: [DuplicateCluster] = []
        let stream = scanner.scan(configuration: configuration(destination: dir.path))
        for try await event in stream {
            if case let .clusterDiscovered(cluster) = event { clusters.append(cluster) }
        }

        let exact = clusters.filter { $0.kind == .exactDuplicate }
        XCTAssertEqual(exact.count, 1)
        let cluster = try XCTUnwrap(exact.first)
        XCTAssertEqual(Set(cluster.members.map { URL(fileURLWithPath: $0.path).lastPathComponent }), ["dup_a.mp4", "dup_b.mp4"])
        XCTAssertTrue(cluster.members.allSatisfy { $0.mediaKind == .video })
    }

    func testSummaryCountsUniqueSizeVideosAsScannedCandidates() async throws {
        let dir = try makeTempDir("VideoSummaryCount")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0x11, count: 101).write(to: dir.appendingPathComponent("one.mp4"))
        try Data(repeating: 0x22, count: 202).write(to: dir.appendingPathComponent("two.mkv"))

        let summary = try await runScan(DeduplicateScanner(), destination: dir.path)

        XCTAssertEqual(summary.totalCandidatesScanned, 2)
        XCTAssertEqual(summary.cacheMetrics.hits + summary.cacheMetrics.misses, 0)
    }

    func testDisablingExactGroupsSkipsVideoIdentityHashing() async throws {
        let dir = try makeTempDir("VideoExactDisabled")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0x33, count: 2048).write(to: dir.appendingPathComponent("a.mp4"))
        try Data(repeating: 0x33, count: 2048).write(to: dir.appendingPathComponent("b.mp4"))

        let scanner = DeduplicateScanner()
        let config = DeduplicateConfiguration(
            destinationPath: dir.path,
            enableExactDuplicateGroup: false
        )
        var summary: DeduplicateSummary?
        var exactClusterCount = 0
        for try await event in scanner.scan(configuration: config) {
            if case let .clusterDiscovered(cluster) = event, cluster.kind == .exactDuplicate {
                exactClusterCount += 1
            }
            if case let .complete(value) = event { summary = value }
        }

        XCTAssertEqual(exactClusterCount, 0)
        let completedSummary = try XCTUnwrap(summary)
        XCTAssertEqual(completedSummary.cacheMetrics.hits + completedSummary.cacheMetrics.misses, 0)
    }

    func testExactVideoHashingReportsCombinedProgress() async throws {
        let dir = try makeTempDir("VideoExactProgress")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0x44, count: 2048).write(to: dir.appendingPathComponent("a.mp4"))
        try Data(repeating: 0x44, count: 2048).write(to: dir.appendingPathComponent("b.mp4"))

        var progress: [(Int, Int)] = []
        for try await event in DeduplicateScanner().scan(configuration: configuration(destination: dir.path)) {
            if case let .phaseProgress(.identityHashing, completed, total) = event {
                progress.append((completed, total))
            }
        }

        XCTAssertEqual(progress.last?.0, 2)
        XCTAssertEqual(progress.last?.1, 2)
    }

    func testExactVideoKeeperIsDeterministicLowestPath() {
        let a = PhotoCandidate(path: "/lib/z_copy.mp4", size: 10, modificationTime: 0, mediaKind: .video)
        let b = PhotoCandidate(path: "/lib/a_copy.mp4", size: 10, modificationTime: 0, mediaKind: .video)
        let keepers = DuplicateClusterer.suggestKeeperIDs(for: [a, b])
        XCTAssertEqual(keepers, ["/lib/a_copy.mp4"])
    }

    func testVideoKeeperIgnoresPhotoQualitySignals() {
        // Even if a video accidentally carried a higher quality score, it must
        // not influence the keeper — only deterministic path order applies.
        let high = PhotoCandidate(path: "/lib/b.mp4", size: 10, modificationTime: 0, qualityScore: 999, sharpness: 999, mediaKind: .video)
        let low = PhotoCandidate(path: "/lib/a.mp4", size: 10, modificationTime: 0, qualityScore: 0, sharpness: 0, mediaKind: .video)
        XCTAssertEqual(DuplicateClusterer.suggestKeeperIDs(for: [high, low]), ["/lib/a.mp4"])
    }

    // MARK: - Auto-commit safety guard

    // AGENTS-INVARIANT: 6
    // A non-exact video cluster can never be auto-commit eligible, even if its
    // annotation is (incorrectly) marked high confidence. This is the planner
    // half of the two structural guards keeping perceptual video review-only.
    func testNonExactVideoClusterNeverAutoCommitEligible() {
        for kind in [ClusterKind.nearDuplicate, .burst, .editedVariant] {
            let cluster = videoCluster(kind: kind, confidence: .high)
            XCTAssertFalse(
                DeduplicationPlanner.isAutomaticCommitEligible(cluster),
                "\(kind) video cluster must never be auto-commit eligible even at high confidence"
            )
        }
    }

    func testExactVideoClusterRemainsAutoCommitEligible() {
        let cluster = videoCluster(kind: .exactDuplicate, confidence: .high)
        XCTAssertTrue(DeduplicationPlanner.isAutomaticCommitEligible(cluster))
    }

    func testPhotoNearDuplicateHighConfidenceStillEligible() {
        // The video guard must not change existing photo behavior.
        let photo = PhotoCandidate(path: "/lib/p1.jpg", size: 10, modificationTime: 0)
        let cluster = DuplicateCluster(
            kind: .nearDuplicate,
            members: [photo, PhotoCandidate(path: "/lib/p2.jpg", size: 10, modificationTime: 0)],
            suggestedKeeperIDs: ["/lib/p1.jpg"],
            bytesIfPruned: 10,
            annotation: ClusterAnnotation(confidence: .high, matchReason: MatchReason(kind: .nearDuplicate))
        )
        XCTAssertTrue(DeduplicationPlanner.isAutomaticCommitEligible(cluster))
    }

    // MARK: - Confidence scorer clamp (second structural guard)

    // AGENTS-INVARIANT: 6
    // Even when distance metrics would qualify a cluster for high confidence,
    // a non-exact video cluster is clamped to at most medium so it can never be
    // auto-accepted. This is the scorer half of the two guards.
    func testNonExactVideoClusterClampedToMediumConfidence() {
        let highQualifyingMatch = MatchReason(
            timeDeltaSeconds: 1.0,
            averageVisionDistance: 0.05,
            kind: .nearDuplicate
        )
        let videoCluster = videoCluster(kind: .nearDuplicate, confidence: .medium)
        let level = ClusterConfidenceScorer.score(
            cluster: videoCluster,
            matchReason: highQualifyingMatch,
            warnings: []
        )
        XCTAssertEqual(level, .medium, "non-exact video must never score high")
    }

    func testExactVideoClusterStillScoresHigh() {
        let cluster = videoCluster(kind: .exactDuplicate, confidence: .high)
        let level = ClusterConfidenceScorer.score(
            cluster: cluster,
            matchReason: MatchReason(kind: .exactDuplicate),
            warnings: []
        )
        XCTAssertEqual(level, .high)
    }

    func testPhotoNearDuplicateStillScoresHighWhenQualifying() {
        // The video clamp must not change photo scoring.
        let photoCluster = DuplicateCluster(
            kind: .nearDuplicate,
            members: [
                PhotoCandidate(path: "/lib/p1.jpg", size: 10, modificationTime: 0),
                PhotoCandidate(path: "/lib/p2.jpg", size: 10, modificationTime: 0),
            ],
            suggestedKeeperIDs: ["/lib/p1.jpg"],
            bytesIfPruned: 10
        )
        let level = ClusterConfidenceScorer.score(
            cluster: photoCluster,
            matchReason: MatchReason(timeDeltaSeconds: 1.0, averageVisionDistance: 0.05, kind: .nearDuplicate),
            warnings: []
        )
        XCTAssertEqual(level, .high)
    }

    // MARK: - Keeper source-folder priority

    func testVideoKeeperPrefersHigherPrioritySourceFolder() {
        // Lexicographically larger path, but in the higher-priority folder.
        let preferred = PhotoCandidate(path: "/secondary/z.mp4", size: 10, modificationTime: 0, folderRoot: "/secondary", mediaKind: .video)
        let other = PhotoCandidate(path: "/primary/a.mp4", size: 10, modificationTime: 0, folderRoot: "/primary", mediaKind: .video)
        let priorities = ["/primary": 5, "/secondary": 0] // secondary is higher priority
        let keepers = DuplicateClusterer.suggestKeeperIDs(for: [preferred, other], folderPriority: priorities)
        XCTAssertEqual(keepers, ["/secondary/z.mp4"])
    }

    func testVideoKeeperFallsBackToPathWhenPriorityEqual() {
        let a = PhotoCandidate(path: "/x/a.mp4", size: 10, modificationTime: 0, folderRoot: "/x", mediaKind: .video)
        let b = PhotoCandidate(path: "/x/b.mp4", size: 10, modificationTime: 0, folderRoot: "/x", mediaKind: .video)
        let keepers = DuplicateClusterer.suggestKeeperIDs(for: [a, b], folderPriority: ["/x": 0])
        XCTAssertEqual(keepers, ["/x/a.mp4"])
    }

    // MARK: - Video hash caching + metrics

    func testVideoHashesAreCachedAndMetricsStayConsistent() async throws {
        let dir = try makeTempDir("VideoCache")
        defer { try? FileManager.default.removeItem(at: dir) }
        try Data(repeating: 0x5A, count: 4096).write(to: dir.appendingPathComponent("a.mov"))
        try Data(repeating: 0x5A, count: 4096).write(to: dir.appendingPathComponent("b.mov"))

        let first = try await runScan(DeduplicateScanner(), destination: dir.path)
        // First scan hashes both videos (2 misses), no hits.
        XCTAssertEqual(first.cacheMetrics.misses, 2)
        XCTAssertEqual(first.cacheMetrics.hits, 0)
        XCTAssertEqual(first.cacheMetrics.hits + first.cacheMetrics.misses, first.totalCandidatesScanned)

        let second = try await runScan(DeduplicateScanner(), destination: dir.path)
        // Second scan serves both from the FileCache checkpoint.
        XCTAssertEqual(second.cacheMetrics.hits, 2)
        XCTAssertEqual(second.cacheMetrics.misses, 0)
        XCTAssertEqual(second.cacheMetrics.hits + second.cacheMetrics.misses, second.totalCandidatesScanned)
    }

    // MARK: - Receipt compatibility

    func testReceiptDecodesUnknownFutureClusterAndMediaKinds() throws {
        let json = """
        {
          "kind": "dedupe",
          "schemaVersion": 5,
          "runID": "\(UUID().uuidString)",
          "operation": "deduplicate",
          "status": "COMPLETED",
          "createdAt": "2026-06-17T12:00:00Z",
          "destinationRoot": "/lib",
          "additionalSourceRoots": [],
          "items": [
            {
              "originalPath": "/lib/clip.mp4",
              "sizeBytes": 100,
              "trashURL": "file:///trash/clip.mp4",
              "method": "trash",
              "clusterID": "\(UUID().uuidString)",
              "clusterKind": "futureVideoBurst",
              "mediaKind": "spatial"
            }
          ],
          "bytesReclaimed": 100
        }
        """
        let receipt = try JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: Data(json.utf8))
        let item = try XCTUnwrap(receipt.items.first)
        XCTAssertEqual(item.clusterKind, .unknown("futureVideoBurst"))
        XCTAssertEqual(item.mediaKind, .unknown("spatial"))
        // Revert-relevant fields survive intact regardless of the unknown kinds.
        XCTAssertEqual(item.originalPath, "/lib/clip.mp4")
        XCTAssertEqual(item.method, .trash)
    }

    func testLegacyReceiptWithoutMediaKindDecodes() throws {
        let json = """
        {
          "schemaVersion": 3,
          "runID": "\(UUID().uuidString)",
          "operation": "deduplicate",
          "status": "COMPLETED",
          "createdAt": "2026-06-17T12:00:00Z",
          "destinationRoot": "/lib",
          "items": [
            {
              "originalPath": "/lib/old.jpg",
              "sizeBytes": 10,
              "trashURL": "file:///trash/old.jpg",
              "method": "trash",
              "clusterID": "\(UUID().uuidString)",
              "clusterKind": "burst"
            }
          ],
          "bytesReclaimed": 10
        }
        """
        let receipt = try JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: Data(json.utf8))
        let item = try XCTUnwrap(receipt.items.first)
        XCTAssertEqual(item.clusterKind, .burst)
        XCTAssertNil(item.mediaKind)
    }

    func testVideoReceiptItemRoundTrips() throws {
        let item = DeduplicateAuditReceipt.Item(
            originalPath: "/lib/clip.mp4",
            sizeBytes: 42,
            trashURL: "file:///trash/clip.mp4",
            method: .trash,
            clusterID: UUID(),
            clusterKind: ReceiptClusterKind(.exactDuplicate),
            mediaKind: ReceiptMediaKind(.video)
        )
        let receipt = DeduplicateAuditReceipt(
            createdAt: Date(),
            destinationRoot: "/lib",
            items: [item],
            bytesReclaimed: 42
        )
        let data = try JSONEncoder.dedupe.encode(receipt)
        let decoded = try JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: data)
        XCTAssertEqual(decoded.schemaVersion, 6)
        XCTAssertEqual(decoded.items.first?.clusterKind, .exactDuplicate)
        XCTAssertEqual(decoded.items.first?.mediaKind, .video)
    }

    // MARK: - Media classification source of truth

    func testEveryRegisteredVideoExtensionClassifiesAsVideo() {
        for ext in MediaLibraryRules.videoExtensions {
            XCTAssertTrue(
                MediaLibraryRules.isVideoFile(path: "/lib/sample\(ext)"),
                "\(ext) should be recognized as a video"
            )
            XCTAssertFalse(MediaLibraryRules.isPhotoFile(path: "/lib/sample\(ext)"))
        }
    }

    // MARK: - Helpers

    private func makeTempDir(_ label: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func configuration(destination: String) -> DeduplicateConfiguration {
        DeduplicateConfiguration(
            destinationPath: destination,
            timeWindowSeconds: 30,
            similarityThreshold: 1.0,
            dhashHammingThreshold: 5,
            treatRawJpegPairsAsUnit: true,
            treatLivePhotoPairsAsUnit: true
        )
    }

    private func runScan(_ scanner: DeduplicateScanner, destination: String) async throws -> DeduplicateSummary {
        var summary: DeduplicateSummary?
        for try await event in scanner.scan(configuration: configuration(destination: destination)) {
            if case let .complete(value) = event { summary = value }
        }
        return try XCTUnwrap(summary)
    }

    private func videoCluster(kind: ClusterKind, confidence: ConfidenceLevel) -> DuplicateCluster {
        let members = [
            PhotoCandidate(path: "/lib/v1.mp4", size: 10, modificationTime: 0, mediaKind: .video),
            PhotoCandidate(path: "/lib/v2.mp4", size: 10, modificationTime: 0, mediaKind: .video),
        ]
        return DuplicateCluster(
            kind: kind,
            members: members,
            suggestedKeeperIDs: ["/lib/v1.mp4"],
            bytesIfPruned: 10,
            annotation: ClusterAnnotation(confidence: confidence, matchReason: MatchReason(kind: kind))
        )
    }
}
