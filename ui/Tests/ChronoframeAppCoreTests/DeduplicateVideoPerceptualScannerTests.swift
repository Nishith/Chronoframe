import Foundation
import XCTest
@testable import ChronoframeCore

/// Milestone 2b-3 — scanner wiring for the opt-in perceptual video lane.
/// Exercised end-to-end through `DeduplicateScanner.scan` with an **injected
/// fake** `VideoFeatureProviding`, so no real decoding happens: the tests
/// assert orchestration (opt-in gating, exact-group exclusivity, cache reuse,
/// prune scoping, honest summary counts), not pixel behavior.
final class DeduplicateVideoPerceptualScannerTests: XCTestCase {

    func testVideoDecodePacingRespondsToPowerAndThermalPressure() {
        XCTAssertEqual(DeduplicateScanner.videoDecodePacingDelay(lowPowerMode: false, thermalState: .nominal), 0)
        XCTAssertGreaterThan(DeduplicateScanner.videoDecodePacingDelay(lowPowerMode: true, thermalState: .nominal), 0)
        XCTAssertGreaterThan(
            DeduplicateScanner.videoDecodePacingDelay(lowPowerMode: false, thermalState: .serious),
            DeduplicateScanner.videoDecodePacingDelay(lowPowerMode: false, thermalState: .fair)
        )
    }

    // MARK: - Opt-in gating

    func testPerceptualLaneOffByDefaultDoesNotDecodeOrReport() async throws {
        let dir = try makeTempDir("PerceptualOff")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Two distinct-size videos that *would* match perceptually if the lane ran.
        try writeVideo(dir, "a.mp4", byte: 0x11, size: 1000)
        try writeVideo(dir, "b.mp4", byte: 0x22, size: 1001)

        let provider = FakeVideoFeatureProvider(specs: [
            "a.mp4": .ready(hashes: matchingHashes),
            "b.mp4": .ready(hashes: matchingHashes),
        ])
        // Default configuration → perceptualVideoMatchingEnabled == false.
        let result = try await scan(dir, provider: provider, perceptual: false)

        XCTAssertEqual(provider.totalCalls, 0, "lane off must never decode")
        XCTAssertEqual(provider.totalProbes, 0, "lane off must never inspect video metadata")
        XCTAssertNil(result.summary.videoPerceptualMetrics, "lane off must not report metrics")
        XCTAssertTrue(result.clusters.allSatisfy { $0.kind != .nearDuplicate })
    }

    func testPerceptualLaneOnClustersIdenticalVideos() async throws {
        let dir = try makeTempDir("PerceptualOn")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "a.mp4", byte: 0x11, size: 1000)
        try writeVideo(dir, "b.mp4", byte: 0x22, size: 1001)

        let provider = FakeVideoFeatureProvider(specs: [
            "a.mp4": .ready(hashes: matchingHashes),
            "b.mp4": .ready(hashes: matchingHashes),
        ])
        let result = try await scan(dir, provider: provider, perceptual: true)

        let near = result.clusters.filter { $0.kind == .nearDuplicate }
        XCTAssertEqual(near.count, 1)
        let cluster = try XCTUnwrap(near.first)
        XCTAssertEqual(Set(cluster.members.map { lastComponent($0.path) }), ["a.mp4", "b.mp4"])
        XCTAssertTrue(cluster.members.allSatisfy { $0.mediaKind == .video })
        // Always review-only: medium confidence, never auto-commit eligible.
        XCTAssertEqual(cluster.annotation?.confidence, .medium)
        XCTAssertFalse(DeduplicationPlanner.isAutomaticCommitEligible(cluster))

        let metrics = try XCTUnwrap(result.summary.videoPerceptualMetrics)
        XCTAssertEqual(metrics.analyzed, 2)
        XCTAssertEqual(metrics.cacheMisses, 2)
        XCTAssertEqual(metrics.cacheHits, 0)
    }

    func testPerceptualLaneReportsDedicatedProgressPhase() async throws {
        let dir = try makeTempDir("PerceptualProgress")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "a.mp4", byte: 0x11, size: 1000)
        try writeVideo(dir, "b.mp4", byte: 0x22, size: 1001)
        let provider = FakeVideoFeatureProvider(specs: [
            "a.mp4": .ready(hashes: matchingHashes),
            "b.mp4": .ready(hashes: matchingHashes),
        ])
        let scanner = DeduplicateScanner(imageAnalyzer: NoopImageAnalyzer(), videoFeatureProvider: provider)
        let config = DeduplicateConfiguration(destinationPath: dir.path, perceptualVideoMatchingEnabled: true)
        var startedTotal: Int?
        var finalProgress: (Int, Int)?
        var completed = false

        for try await event in scanner.scan(configuration: config) {
            switch event {
            case let .phaseStarted(.videoAnalysis, total): startedTotal = total
            case let .phaseProgress(.videoAnalysis, count, total): finalProgress = (count, total)
            case .phaseCompleted(.videoAnalysis): completed = true
            default: break
            }
        }

        XCTAssertEqual(startedTotal, 2)
        XCTAssertEqual(finalProgress?.0, 2)
        XCTAssertEqual(finalProgress?.1, 2)
        XCTAssertTrue(completed)
    }

    // MARK: - Exact-group exclusivity

    func testExactGroupVideosAreExcludedFromPerceptualLane() async throws {
        let dir = try makeTempDir("PerceptualExclusivity")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Byte-identical pair → exact-duplicate cluster (same bytes & size).
        try writeVideo(dir, "exact1.mp4", byte: 0xAA, size: 2048)
        try writeVideo(dir, "exact2.mp4", byte: 0xAA, size: 2048)
        // Distinct-size pair that should match perceptually.
        try writeVideo(dir, "sim1.mp4", byte: 0x31, size: 1500)
        try writeVideo(dir, "sim2.mp4", byte: 0x32, size: 1501)

        let provider = FakeVideoFeatureProvider(specs: [
            // Even if the exact pair would "match", they must be held out.
            "exact1.mp4": .ready(hashes: matchingHashes),
            "exact2.mp4": .ready(hashes: matchingHashes),
            "sim1.mp4": .ready(hashes: matchingHashes),
            "sim2.mp4": .ready(hashes: matchingHashes),
        ])
        let result = try await scan(dir, provider: provider, perceptual: true)

        // Exact pair clustered exactly; perceptual lane never saw them.
        XCTAssertEqual(result.clusters.filter { $0.kind == .exactDuplicate }.count, 1)
        XCTAssertEqual(provider.calls(for: "exact1.mp4"), 0)
        XCTAssertEqual(provider.calls(for: "exact2.mp4"), 0)
        XCTAssertEqual(provider.probes(for: "exact1.mp4"), 0)
        XCTAssertEqual(provider.probes(for: "exact2.mp4"), 0)

        let near = result.clusters.filter { $0.kind == .nearDuplicate }
        XCTAssertEqual(near.count, 1)
        XCTAssertEqual(Set(try XCTUnwrap(near.first).members.map { lastComponent($0.path) }), ["sim1.mp4", "sim2.mp4"])

        let metrics = try XCTUnwrap(result.summary.videoPerceptualMetrics)
        XCTAssertEqual(metrics.deferredPendingExactCleanup, 2)
        XCTAssertEqual(metrics.analyzed, 2)

        // No path appears in two emitted clusters.
        assertNoDoubleMembership(result.clusters)
    }

    // MARK: - Cache reuse + non-ready caching

    func testSecondScanServesVideoFeaturesFromCache() async throws {
        let dir = try makeTempDir("PerceptualCache")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "a.mp4", byte: 0x11, size: 1000)
        try writeVideo(dir, "b.mp4", byte: 0x22, size: 1001)

        let provider = FakeVideoFeatureProvider(specs: [
            "a.mp4": .ready(hashes: matchingHashes),
            "b.mp4": .ready(hashes: matchingHashes),
        ])
        let first = try await scan(dir, provider: provider, perceptual: true)
        XCTAssertEqual(try XCTUnwrap(first.summary.videoPerceptualMetrics).cacheMisses, 2)
        XCTAssertEqual(provider.totalCalls, 2)

        let second = try await scan(dir, provider: provider, perceptual: true)
        let metrics = try XCTUnwrap(second.summary.videoPerceptualMetrics)
        XCTAssertEqual(metrics.cacheHits, 2, "warm scan reuses cached video features")
        XCTAssertEqual(metrics.cacheMisses, 0)
        XCTAssertEqual(provider.totalCalls, 2, "provider not re-invoked on a warm scan")
        // Clustering still works from cached features.
        XCTAssertEqual(second.clusters.filter { $0.kind == .nearDuplicate }.count, 1)
    }

    func testNonReadyOutcomeIsCachedAndNotReDecoded() async throws {
        let dir = try makeTempDir("PerceptualUnsupported")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "weird.mp4", byte: 0x55, size: 700)

        let provider = FakeVideoFeatureProvider(specs: [
            "weird.mp4": .unsupportedSpec,
        ])
        let first = try await scan(dir, provider: provider, perceptual: true)
        XCTAssertEqual(try XCTUnwrap(first.summary.videoPerceptualMetrics).unsupported, 1)
        XCTAssertEqual(provider.totalCalls, 0)
        XCTAssertEqual(provider.totalProbes, 1)

        let second = try await scan(dir, provider: provider, perceptual: true)
        let metrics = try XCTUnwrap(second.summary.videoPerceptualMetrics)
        XCTAssertEqual(metrics.cacheHits, 1)
        XCTAssertEqual(metrics.unsupported, 1, "cached unsupported outcome is reused")
        XCTAssertEqual(provider.totalCalls, 0, "unsupported video is never frame-decoded")
        XCTAssertEqual(provider.totalProbes, 1, "unsupported metadata outcome is cached")
    }

    func testMetadataPrefilterSkipsFrameDecodeWithoutPlausibleNeighbor() async throws {
        let dir = try makeTempDir("PerceptualMetadataPrefilter")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "short.mp4", byte: 0x61, size: 801)
        try writeVideo(dir, "long.mp4", byte: 0x62, size: 802)

        let provider = FakeVideoFeatureProvider(specs: [
            "short.mp4": .ready(hashes: matchingHashes, duration: 10),
            "long.mp4": .ready(hashes: matchingHashes, duration: 40),
        ])
        let result = try await scan(dir, provider: provider, perceptual: true)
        let metrics = try XCTUnwrap(result.summary.videoPerceptualMetrics)

        XCTAssertEqual(provider.totalProbes, 2)
        XCTAssertEqual(provider.totalCalls, 0, "unique-duration videos must not decode sample frames")
        XCTAssertEqual(metrics.prefilteredNoNeighbor, 2)
        XCTAssertEqual(metrics.analyzed, 0)
    }

    func testCancelledExtractionDoesNotCacheDecodeFailure() async throws {
        let dir = try makeTempDir("PerceptualCancellation")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "cancelled.mp4", byte: 0x56, size: 701)
        try writeVideo(dir, "peer.mp4", byte: 0x57, size: 702)

        let provider = FakeVideoFeatureProvider(specs: [
            "cancelled.mp4": .decodeFailedSpec,
            "peer.mp4": .decodeFailedSpec,
        ])
        let scanner = DeduplicateScanner(
            imageAnalyzer: NoopImageAnalyzer(),
            videoFeatureProvider: provider
        )
        provider.runOnceOnNextExtraction { scanner.cancel() }
        let config = DeduplicateConfiguration(
            destinationPath: dir.path,
            similarityThreshold: 1.0,
            dhashHammingThreshold: 5,
            perceptualVideoMatchingEnabled: true
        )

        var cancelledScanCompleted = false
        for try await event in scanner.scan(configuration: config) {
            if case .complete = event { cancelledScanCompleted = true }
        }
        XCTAssertFalse(cancelledScanCompleted)
        XCTAssertEqual(provider.totalCalls, 1)

        let database = try OrganizerDatabase(url: dir.appendingPathComponent(".organize_cache.db"))
        XCTAssertTrue(
            try database.loadDedupeVideoFeatureRecords().isEmpty,
            "cancellation must not persist its synthetic decode failure"
        )
        database.close()

        var resumedSummary: DeduplicateSummary?
        for try await event in scanner.scan(configuration: config) {
            if case let .complete(summary) = event { resumedSummary = summary }
        }
        let metrics = try XCTUnwrap(resumedSummary?.videoPerceptualMetrics)
        XCTAssertEqual(metrics.cacheHits, 0)
        XCTAssertEqual(metrics.cacheMisses, 2)
        XCTAssertEqual(metrics.decodeFailed, 2)
        XCTAssertEqual(provider.totalCalls, 3, "the next scan must retry both uncached videos")
    }

    // MARK: - Prune scoping

    func testPerceptualOffScanDoesNotPruneVideoFeatureCache() async throws {
        let dir = try makeTempDir("PerceptualPruneScope")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "a.mp4", byte: 0x11, size: 1000)
        try writeVideo(dir, "b.mp4", byte: 0x22, size: 1001)

        let provider = FakeVideoFeatureProvider(specs: [
            "a.mp4": .ready(hashes: matchingHashes),
            "b.mp4": .ready(hashes: matchingHashes),
        ])
        // Warm the video cache with a perceptual-on scan.
        _ = try await scan(dir, provider: provider, perceptual: true)
        let db1 = try OrganizerDatabase(url: dir.appendingPathComponent(".organize_cache.db"))
        XCTAssertEqual(try db1.loadDedupeVideoFeatureRecords().count, 2)
        db1.close()

        // A perceptual-off scan must leave the video cache untouched (no prune).
        _ = try await scan(dir, provider: provider, perceptual: false)
        let db2 = try OrganizerDatabase(url: dir.appendingPathComponent(".organize_cache.db"))
        XCTAssertEqual(
            try db2.loadDedupeVideoFeatureRecords().count, 2,
            "perceptual-off scan must not prune the video feature cache"
        )
        db2.close()
    }

    func testPerceptualOnWithNoCandidateVideosReportsEmptyMetrics() async throws {
        let dir = try makeTempDir("PerceptualNoVideos")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Photos only — no videos to analyze, but the lane still "ran".
        try Data(repeating: 0x10, count: 128).write(to: dir.appendingPathComponent("p1.jpg"))
        try Data(repeating: 0x11, count: 128).write(to: dir.appendingPathComponent("p2.jpg"))

        let provider = FakeVideoFeatureProvider(specs: [:])
        let result = try await scan(dir, provider: provider, perceptual: true)

        XCTAssertEqual(provider.totalCalls, 0)
        let metrics = try XCTUnwrap(result.summary.videoPerceptualMetrics)
        XCTAssertEqual(metrics.totalConsidered, 0)
        XCTAssertEqual(metrics.deferredPendingExactCleanup, 0)
        XCTAssertTrue(result.clusters.allSatisfy { $0.kind != .nearDuplicate })
    }

    func testManyVideoMissesFlushInBatches() async throws {
        let dir = try makeTempDir("PerceptualFlush")
        defer { try? FileManager.default.removeItem(at: dir) }
        // Enough distinct-size videos to cross the in-loop flush threshold (25).
        var specs: [String: FakeVideoFeatureProvider.Spec] = [:]
        for index in 0..<26 {
            let name = "clip\(index).mp4"
            try writeVideo(dir, name, byte: UInt8(index + 1), size: 1000 + index)
            specs[name] = .ready(hashes: matchingHashes)
        }
        let provider = FakeVideoFeatureProvider(specs: specs)
        let result = try await scan(dir, provider: provider, perceptual: true)

        let metrics = try XCTUnwrap(result.summary.videoPerceptualMetrics)
        XCTAssertEqual(metrics.cacheMisses, 26)
        XCTAssertEqual(metrics.analyzed, 26)
        // All persisted despite the mid-loop flush — a warm rescan is all hits.
        let second = try await scan(dir, provider: provider, perceptual: true)
        XCTAssertEqual(try XCTUnwrap(second.summary.videoPerceptualMetrics).cacheHits, 26)
        XCTAssertEqual(provider.totalCalls, 26, "warm rescan re-decodes nothing")
        // 26 identical-hash videos merge into a single perceptual cluster.
        XCTAssertEqual(result.clusters.filter { $0.kind == .nearDuplicate }.count, 1)
    }

    // MARK: - Summary count consistency

    func testSummaryVideoCountsAreConsistent() async throws {
        let dir = try makeTempDir("PerceptualCounts")
        defer { try? FileManager.default.removeItem(at: dir) }
        try writeVideo(dir, "ready1.mp4", byte: 0x31, size: 1500)
        try writeVideo(dir, "ready2.mp4", byte: 0x32, size: 1501)
        try writeVideo(dir, "weird.mp4", byte: 0x55, size: 700)
        try writeVideo(dir, "short.mp4", byte: 0x56, size: 701)

        let provider = FakeVideoFeatureProvider(specs: [
            "ready1.mp4": .ready(hashes: matchingHashes),
            "ready2.mp4": .ready(hashes: matchingHashes),
            "weird.mp4": .unsupportedSpec,
            "short.mp4": .insufficientSpec,
        ])
        let result = try await scan(dir, provider: provider, perceptual: true)
        let m = try XCTUnwrap(result.summary.videoPerceptualMetrics)

        XCTAssertEqual(m.analyzed, 2)
        XCTAssertEqual(m.unsupported, 1)
        XCTAssertEqual(m.insufficientVisualEvidence, 1)
        XCTAssertEqual(m.decodeFailed, 0)
        XCTAssertEqual(m.deferredPendingExactCleanup, 0)
        // The four decode outcomes partition the considered set, which equals
        // hits + misses.
        XCTAssertEqual(m.totalConsidered, 4)
        XCTAssertEqual(m.cacheHits + m.cacheMisses, m.totalConsidered)
    }

    // MARK: - Fixtures

    private let matchingHashes: [UInt64?] = [0x1, 0x2, 0x4, 0x8, 0x10]

    private struct ScanResult {
        var clusters: [DuplicateCluster]
        var summary: DeduplicateSummary
    }

    private func scan(
        _ dir: URL,
        provider: FakeVideoFeatureProvider,
        perceptual: Bool
    ) async throws -> ScanResult {
        let scanner = DeduplicateScanner(
            imageAnalyzer: NoopImageAnalyzer(),
            videoFeatureProvider: provider
        )
        let config = DeduplicateConfiguration(
            destinationPath: dir.path,
            similarityThreshold: 1.0,
            dhashHammingThreshold: 5,
            perceptualVideoMatchingEnabled: perceptual
        )
        var clusters: [DuplicateCluster] = []
        var summary: DeduplicateSummary?
        for try await event in scanner.scan(configuration: config) {
            switch event {
            case let .clusterDiscovered(cluster): clusters.append(cluster)
            case let .complete(value): summary = value
            default: break
            }
        }
        return ScanResult(clusters: clusters, summary: try XCTUnwrap(summary))
    }

    private func makeTempDir(_ label: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Write a placeholder video file. The fake provider supplies features, so
    /// the bytes only matter for size (exact-duplicate prefiltering) and
    /// discovery-by-extension — they are never decoded.
    private func writeVideo(_ dir: URL, _ name: String, byte: UInt8, size: Int) throws {
        try Data(repeating: byte, count: size).write(to: dir.appendingPathComponent(name))
    }

    private func lastComponent(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    private func assertNoDoubleMembership(_ clusters: [DuplicateCluster], file: StaticString = #filePath, line: UInt = #line) {
        var seen = Set<String>()
        for cluster in clusters {
            for member in cluster.members {
                XCTAssertTrue(seen.insert(member.path).inserted, "\(member.path) appears in more than one cluster", file: file, line: line)
            }
        }
    }
}

// MARK: - Test doubles

/// Returns canned `VideoPerceptualFeatures` keyed by file name, embedding the
/// real `(size, mtime, folderRoot)` the scanner passes so the cache layer can
/// validate the row on a warm rescan. Counts calls per path.
private final class FakeVideoFeatureProvider: VideoFeatureProviding, @unchecked Sendable {
    struct Spec {
        var status: VideoDecodeStatus
        var frameHashes: [UInt64?]
        var duration: Double
        var width: Int
        var height: Int

        static func ready(hashes: [UInt64?], duration: Double = 10, width: Int = 1920, height: Int = 1080) -> Spec {
            Spec(status: .ready, frameHashes: hashes, duration: duration, width: width, height: height)
        }
        static let unsupportedSpec = Spec(status: .unsupported, frameHashes: [nil, nil, nil, nil, nil], duration: 0, width: 0, height: 0)
        static let decodeFailedSpec = Spec(status: .decodeFailed, frameHashes: [nil, nil, nil, nil, nil], duration: 10, width: 1920, height: 1080)
        static let insufficientSpec = Spec(status: .insufficientVisualEvidence, frameHashes: [0x1, nil, nil, nil, nil], duration: 10, width: 1920, height: 1080)
    }

    private let lock = NSLock()
    private let specs: [String: Spec]
    private var callCounts: [String: Int] = [:]
    private var probeCounts: [String: Int] = [:]
    private var nextExtractionAction: (@Sendable () -> Void)?

    init(specs: [String: Spec]) {
        self.specs = specs
    }

    func probeMetadata(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        folderRoot: String?,
        isCancelled: @Sendable () -> Bool
    ) -> VideoMetadataProbe {
        let name = URL(fileURLWithPath: path).lastPathComponent
        lock.lock()
        probeCounts[name, default: 0] += 1
        lock.unlock()
        let spec = specs[name] ?? Spec.unsupportedSpec
        return VideoMetadataProbe(
            path: path,
            size: size,
            modificationTime: modificationTime,
            durationSeconds: spec.duration,
            transformedWidth: spec.width,
            transformedHeight: spec.height,
            folderRoot: folderRoot,
            status: spec.status == .unsupported ? .unsupported : .ready
        )
    }

    func extractFeatures(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        folderRoot: String?,
        isCancelled: @Sendable () -> Bool
    ) -> VideoPerceptualFeatures {
        let name = URL(fileURLWithPath: path).lastPathComponent
        lock.lock()
        callCounts[name, default: 0] += 1
        let action = nextExtractionAction
        nextExtractionAction = nil
        lock.unlock()
        action?()
        let spec = specs[name] ?? Spec.unsupportedSpec
        return VideoPerceptualFeatures(
            path: path,
            size: size,
            modificationTime: modificationTime,
            durationSeconds: spec.duration,
            transformedWidth: spec.width,
            transformedHeight: spec.height,
            frameHashes: spec.frameHashes,
            status: spec.status,
            folderRoot: folderRoot
        )
    }

    func cancelAll() {}

    func runOnceOnNextExtraction(_ action: @escaping @Sendable () -> Void) {
        lock.lock()
        nextExtractionAction = action
        lock.unlock()
    }

    func calls(for name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return callCounts[name, default: 0]
    }

    func probes(for name: String) -> Int {
        lock.lock(); defer { lock.unlock() }
        return probeCounts[name, default: 0]
    }

    var totalProbes: Int {
        lock.lock(); defer { lock.unlock() }
        return probeCounts.values.reduce(0, +)
    }

    var totalCalls: Int {
        lock.lock(); defer { lock.unlock() }
        return callCounts.values.reduce(0, +)
    }
}

/// Image analyzer that returns empty analysis — videos never reach it, and the
/// placeholder photo-less libraries in these tests don't need real analysis.
private final class NoopImageAnalyzer: DedupeImageAnalyzing, @unchecked Sendable {
    func analyze(url: URL, size: Int64) -> DedupeImageAnalysis {
        DedupeImageAnalysis(
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
