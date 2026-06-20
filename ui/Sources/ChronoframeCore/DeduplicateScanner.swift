import Foundation
import CoreImage
import ImageIO
import Vision

/// Orchestrates a deduplicate scan against an organized destination. Streams
/// `DeduplicateEvent`s as it works through discovery → identity hashing →
/// feature extraction → clustering. Per-file feature data (Vision feature
/// print, dHash, quality score, capture date, pixel dimensions, pair link)
/// is persisted to the existing `.organize_cache.db` so subsequent scans
/// only hash and feature-print files whose `(size, mtime)` changed.
public final class DeduplicateScanner: @unchecked Sendable {
    private let dateResolver: FileDateResolver
    private let identityHasher: FileIdentityHasher
    private let imageAnalyzer: any DedupeImageAnalyzing
    private let videoFeatureProvider: any VideoFeatureProviding
    private var cancelFlag = ManagedAtomicBool()

    public init(
        dateResolver: FileDateResolver = FileDateResolver(),
        identityHasher: FileIdentityHasher = FileIdentityHasher()
    ) {
        self.dateResolver = dateResolver
        self.identityHasher = identityHasher
        self.imageAnalyzer = DefaultDedupeImageAnalyzer(dateResolver: dateResolver)
        self.videoFeatureProvider = AVFoundationVideoFeatureExtractor()
    }

    init(
        dateResolver: FileDateResolver = FileDateResolver(),
        identityHasher: FileIdentityHasher = FileIdentityHasher(),
        imageAnalyzer: any DedupeImageAnalyzing,
        videoFeatureProvider: any VideoFeatureProviding = AVFoundationVideoFeatureExtractor()
    ) {
        self.dateResolver = dateResolver
        self.identityHasher = identityHasher
        self.imageAnalyzer = imageAnalyzer
        self.videoFeatureProvider = videoFeatureProvider
    }

    public func cancel() {
        // Order matters: raise the scan-wide flag first, then cancel in-flight
        // video generation, so a worker that registers a generator between
        // these two calls sees the flag and aborts (see GeneratorRegistry).
        cancelFlag.set(true)
        videoFeatureProvider.cancelAll()
    }

    public func scan(configuration: DeduplicateConfiguration) -> AsyncThrowingStream<DeduplicateEvent, Error> {
        cancelFlag.set(false)
        let identityHasher = self.identityHasher
        let imageAnalyzer = self.imageAnalyzer
        let videoFeatureProvider = self.videoFeatureProvider
        let cancelFlag = self.cancelFlag

        return AsyncThrowingStream { continuation in
            Task.detached {
                let started = Date()
                continuation.yield(.startup)

                do {
                    // 1. Discovery — image files only for v1; .mov files are
                    // tracked separately for Live Photo pair linking.
                    let rootURL = URL(fileURLWithPath: configuration.destinationPath)
                    let scanRoots = Self.scanRoots(for: configuration)
                    var allPaths: [String] = []
                    var seenPaths = Set<String>()
                    var folderRootByPath: [String: String] = [:]
                    for scanRoot in scanRoots {
                        try MediaDiscovery.enumerateMediaFiles(at: scanRoot.url) { path in
                            let standardizedPath = URL(fileURLWithPath: path).standardizedFileURL.path
                            guard seenPaths.insert(standardizedPath).inserted else { return }
                            allPaths.append(path)
                            folderRootByPath[path] = scanRoot.path
                            folderRootByPath[standardizedPath] = scanRoot.path
                        }
                    }
                    if cancelFlag.get() { continuation.finish(); return }

                    let imagePaths = allPaths.filter { MediaLibraryRules.isPhotoFile(path: $0) }
                    let movPaths = allPaths.filter {
                        let ext = MediaLibraryRules.normalizedExtension(for: $0)
                        return ext == ".mov" || ext == ".m4v"
                    }
                    // 2. Open the cache database in the destination root.
                    let dbURL = rootURL.appendingPathComponent(".organize_cache.db")
                    let database = try OrganizerDatabase(url: dbURL)
                    try database.ensureDedupeFeaturesSchema()
                    let cache = try database.loadDedupeFeatureMetadataRecords()

                    // 3. Pair detection.
                    let pairs = DeduplicatePairDetector.detectPairs(in: imagePaths + movPaths)

                    // Standalone videos for the exact-duplicate lane: every
                    // discovered video file except the .mov half of a Live
                    // Photo (those stay paired to their still and are handled
                    // by pair-as-unit fanout, never as independently
                    // deletable video duplicates).
                    let videoPaths = allPaths.filter {
                        MediaLibraryRules.isVideoFile(path: $0) && pairs[$0]?.kind != .livePhoto
                    }
                    continuation.yield(.phaseStarted(
                        phase: .discovery,
                        total: imagePaths.count + videoPaths.count
                    ))
                    continuation.yield(.phaseCompleted(phase: .discovery))

                    let videoExactCollisionPaths = configuration.enableExactDuplicateGroup
                        ? Self.videoExactCollisionPaths(in: videoPaths)
                        : []
                    let identityHashTotal = imagePaths.count + videoExactCollisionPaths.count

                    // 4. Identity hashing — finds exact duplicates, reuses
                    // FileCache rows when (size, mtime) match.
                    continuation.yield(.phaseStarted(phase: .identityHashing, total: identityHashTotal))
                    let cacheRecords = (try? database.loadCacheRecords(namespace: .destination)) ?? []
                    let cacheIndex = Dictionary(uniqueKeysWithValues: cacheRecords.map { ($0.path, $0) })
                    let identityResults = try await Self.processIdentityHashes(
                        paths: imagePaths,
                        cacheIndex: cacheIndex,
                        identityHasher: identityHasher,
                        workerCount: configuration.workerCount,
                        cancelFlag: cancelFlag,
                        continuation: continuation,
                        progressTotal: identityHashTotal
                    )
                    if cancelFlag.get() { continuation.finish(); return }

                    var identityByPath: [String: FileIdentity] = [:]
                    for (index, path) in imagePaths.enumerated() {
                        if let identity = identityResults[index].identity {
                            identityByPath[path] = identity
                        }
                    }

                    // Video exact-duplicate lane (Milestone 1). Videos never
                    // enter the image-analysis lane below; a photo and a video
                    // can never share a FileIdentity, so video candidates
                    // simply join exact clustering. Size-prefiltered so a
                    // video with a unique size is never read.
                    let videoLane = try await Self.processVideoExactLane(
                        collisionPaths: videoExactCollisionPaths,
                        cacheIndex: cacheIndex,
                        folderRootByPath: folderRootByPath,
                        identityHasher: identityHasher,
                        workerCount: configuration.workerCount,
                        cancelFlag: cancelFlag,
                        continuation: continuation,
                        progressOffset: imagePaths.count,
                        progressTotal: identityHashTotal
                    )
                    for (path, identity) in videoLane.identityByPath {
                        identityByPath[path] = identity
                    }
                    // Checkpoint newly hashed video identities so dedicated
                    // dedupe folders / additional sources don't re-read every
                    // size-collision video on the next scan.
                    if !videoLane.newCacheRecords.isEmpty {
                        try? database.saveCacheRecords(videoLane.newCacheRecords)
                    }
                    if cancelFlag.get() { continuation.finish(); return }
                    continuation.yield(.phaseCompleted(phase: .identityHashing))

                    // 5. Per-file feature extraction (dHash + Vision feature
                    // print + quality scores), with cache reuse.
                    continuation.yield(.phaseStarted(phase: .featureExtraction, total: imagePaths.count))
                    var freshRecords: [DedupeFeatureRecord] = []
                    var candidatesByPath: [String: PhotoCandidate] = [:]
                    var analysisRequests: [DedupeAnalysisRequest] = []
                    // Fold exact-video identity-hash cache outcomes into the
                    // analysis cache snapshot. Size-unique videos do not incur
                    // hashing work and therefore do not affect these metrics.
                    var cacheHits = videoLane.cacheHits
                    var cacheMisses = videoLane.cacheMisses

                    // Batch-stat all image files upfront to avoid per-file
                    // FileManager.attributesOfItem calls in the loop below.
                    struct FileAttrs {
                        var size: Int64
                        var mtime: TimeInterval
                    }
                    var batchedAttrs: [String: FileAttrs] = [:]
                    batchedAttrs.reserveCapacity(imagePaths.count)
                    for path in imagePaths {
                        var st = stat()
                        if lstat(path, &st) == 0 {
                            batchedAttrs[path] = FileAttrs(
                                size: Int64(st.st_size),
                                mtime: Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
                            )
                        }
                    }

                    for (offset, path) in imagePaths.enumerated() {
                        if cancelFlag.get() { continuation.finish(); return }
                        let url = URL(fileURLWithPath: path)
                        let attrs = batchedAttrs[path]
                        let size = attrs?.size ?? 0
                        let mtime = attrs?.mtime ?? 0
                        let pairedPath = pairs[path].map { pair in
                            pair.primaryPath == path ? pair.secondaryPath : pair.primaryPath
                        }
                        let folderRoot = folderRootByPath[path]

                        // Cache hit when (size, mtime) match exactly.
                        if let cached = Self.cachedFeatureRecord(for: path, in: cache),
                           cached.size == size,
                           abs(cached.modificationTime - mtime) < 0.001 {
                            cacheHits += 1
                            let quality = PhotoQualityScorer.expressionAwareScore(
                                sharpness: cached.sharpness,
                                faceScore: cached.faceScore,
                                eyesOpenScore: cached.eyesOpenScore,
                                smileScore: cached.smileScore,
                                subjectMotionBlur: cached.subjectMotionBlur,
                                sizeBytes: size,
                                pixelWidth: cached.pixelWidth,
                                pixelHeight: cached.pixelHeight
                            )
                            let candidate = PhotoCandidate(
                                path: path,
                                size: size,
                                modificationTime: mtime,
                                captureDate: cached.captureDate,
                                pixelWidth: cached.pixelWidth,
                                pixelHeight: cached.pixelHeight,
                                dhash: cached.dhash,
                                featurePrintData: nil,
                                qualityScore: quality.composite,
                                sharpness: cached.sharpness,
                                faceScore: cached.faceScore,
                                isRaw: DeduplicatePairDetector.rawExtensions.contains(MediaLibraryRules.normalizedExtension(for: path)),
                                isLivePhotoStill: pairs[path]?.kind == .livePhoto,
                                pairedPath: pairedPath,
                                eyesOpenScore: cached.eyesOpenScore,
                                smileScore: cached.smileScore,
                                subjectSharpness: cached.subjectSharpness,
                                subjectMotionBlur: cached.subjectMotionBlur,
                                folderRoot: cached.folderRoot ?? folderRoot
                            )
                            candidatesByPath[path] = candidate
                            if (offset + 1) % 50 == 0 || offset == imagePaths.count - 1 {
                                continuation.yield(.phaseProgress(phase: .featureExtraction, completed: offset + 1, total: imagePaths.count))
                            }
                            continue
                        }

                        cacheMisses += 1
                        analysisRequests.append(
                            DedupeAnalysisRequest(
                                offset: offset,
                                path: path,
                                url: url,
                                size: size,
                                modificationTime: mtime,
                                pairedPath: pairedPath,
                                isRaw: DeduplicatePairDetector.rawExtensions.contains(MediaLibraryRules.normalizedExtension(for: path)),
                                isLivePhotoStill: pairs[path]?.kind == .livePhoto,
                                folderRoot: folderRoot
                            )
                        )
                    }

                    let analysisResults = try await Self.processAnalysisRequests(
                        analysisRequests,
                        analyzer: imageAnalyzer,
                        workerCount: configuration.workerCount,
                        cancelFlag: cancelFlag
                    )
                    if cancelFlag.get() { continuation.finish(); return }

                    for request in analysisRequests.sorted(by: { $0.offset < $1.offset }) {
                        guard let analysis = analysisResults[request.offset] else { continue }
                        if let message = analysis.featurePrintFailureMessage {
                            continuation.yield(.issue(DeduplicateIssue(severity: .warning, path: request.path, message: message)))
                        }
                        let candidate = PhotoCandidate(
                            path: request.path,
                            size: request.size,
                            modificationTime: request.modificationTime,
                            captureDate: analysis.captureDate,
                            pixelWidth: analysis.pixelWidth,
                            pixelHeight: analysis.pixelHeight,
                            dhash: analysis.dhash,
                            featurePrintData: analysis.featurePrintData,
                            qualityScore: analysis.quality.composite,
                            sharpness: analysis.quality.sharpness,
                            faceScore: analysis.quality.faceScore,
                            isRaw: request.isRaw,
                            isLivePhotoStill: request.isLivePhotoStill,
                            pairedPath: request.pairedPath,
                            eyesOpenScore: analysis.eyesOpenScore,
                            smileScore: analysis.smileScore,
                            subjectSharpness: analysis.subjectSharpness,
                            subjectMotionBlur: analysis.subjectMotionBlur,
                            folderRoot: request.folderRoot
                        )
                        candidatesByPath[request.path] = candidate
                        freshRecords.append(
                            DedupeFeatureRecord(
                                path: request.path,
                                size: request.size,
                                modificationTime: request.modificationTime,
                                dhash: analysis.dhash,
                                featurePrintData: analysis.featurePrintData,
                                sharpness: analysis.quality.sharpness,
                                faceScore: analysis.quality.faceScore,
                                pixelWidth: analysis.pixelWidth,
                                pixelHeight: analysis.pixelHeight,
                                captureDate: analysis.captureDate,
                                pairedPath: request.pairedPath,
                                eyesOpenScore: analysis.eyesOpenScore,
                                smileScore: analysis.smileScore,
                                subjectSharpness: analysis.subjectSharpness,
                                subjectMotionBlur: analysis.subjectMotionBlur,
                                folderRoot: request.folderRoot
                            )
                        )

                        if (request.offset + 1) % 25 == 0 || request.offset == imagePaths.count - 1 {
                            continuation.yield(.phaseProgress(phase: .featureExtraction, completed: request.offset + 1, total: imagePaths.count))
                            // Flush to disk in batches so a long scan that
                            // gets cancelled or crashes still preserves work.
                            if !freshRecords.isEmpty {
                                try? database.saveDedupeFeatureRecords(freshRecords)
                                freshRecords.removeAll(keepingCapacity: true)
                            }
                        }
                    }

                    if !freshRecords.isEmpty {
                        try? database.saveDedupeFeatureRecords(freshRecords)
                    }
                    try? database.pruneDedupeFeatureRecords(notIn: Set(imagePaths))
                    continuation.yield(.phaseCompleted(phase: .featureExtraction))

                    // 6. Clustering. Photo candidates carry dHash/feature
                    // prints and feed both exact and near clustering; video
                    // candidates carry neither, so they participate only in
                    // exact (identity-based) clustering and are skipped by the
                    // dHash-driven near clusterer.
                    continuation.yield(.phaseStarted(phase: .clustering, total: nil))
                    let candidates = Array(candidatesByPath.values) + videoLane.candidates

                    // Source-folder priority for keeper selection (lower number
                    // = higher priority). The destination is the implicit
                    // primary at priority 0; additional sources use their
                    // configured priority. Keyed by standardized scan-root path
                    // to match candidate `folderRoot`.
                    var folderPriority: [String: Int] = [
                        URL(fileURLWithPath: configuration.destinationPath).standardizedFileURL.path: 0
                    ]
                    for source in configuration.additionalSources {
                        folderPriority[URL(fileURLWithPath: source.path).standardizedFileURL.path] = source.priority
                    }

                    var clusters: [DuplicateCluster] = []
                    if configuration.enableExactDuplicateGroup {
                        var byIdentity: [FileIdentity: [PhotoCandidate]] = [:]
                        for candidate in candidates {
                            guard let identity = identityByPath[candidate.path] else { continue }
                            byIdentity[identity, default: []].append(candidate)
                        }
                        clusters.append(contentsOf: DuplicateClusterer.exactDuplicateClusters(
                            candidatesByIdentity: byIdentity,
                            folderPriority: folderPriority
                        ))
                    }

                    // Pre-load all feature prints in one bulk query to
                    // avoid per-path DB round-trips during O(N^2) clustering.
                    let preloadedPrints = (try? database.loadAllDedupeFeaturePrintData()) ?? [:]
                    let near = DuplicateClusterer.cluster(
                        candidates: candidates,
                        configuration: configuration,
                        featurePrintDataProvider: { path in
                            preloadedPrints[path]
                                ?? preloadedPrints[URL(fileURLWithPath: path).standardizedFileURL.path]
                        }
                    )
                    clusters.append(contentsOf: near)

                    // Drop near-duplicate clusters that are entirely byte-
                    // identical to an exact-duplicate cluster we already
                    // emitted (the exact group supersedes them).
                    let exactPaths = Set(clusters.filter { $0.kind == .exactDuplicate }.flatMap { $0.members.map(\.path) })
                    let dedupedClusters = clusters.filter { cluster in
                        if cluster.kind == .exactDuplicate { return true }
                        return !cluster.members.allSatisfy { exactPaths.contains($0.path) }
                    }
                    continuation.yield(.phaseCompleted(phase: .clustering))

                    // 6b. Perceptual video lane (Milestone 2b) — opt-in, always
                    // review-only. Skipped entirely when off (no decode).
                    // Exclusivity: any video already in an exact-duplicate
                    // cluster is held out (exact wins). Runs after exact/near
                    // clustering so the exclusion set is final.
                    let perceptualVideoLane = Self.processVideoPerceptualLane(
                        videoPaths: videoPaths,
                        exactClusterPaths: exactPaths,
                        folderRootByPath: folderRootByPath,
                        folderPriority: folderPriority,
                        database: database,
                        provider: videoFeatureProvider,
                        configuration: configuration,
                        cancelFlag: cancelFlag,
                        continuation: continuation
                    )
                    if cancelFlag.get() { continuation.finish(); return }

                    let emittedClusters = dedupedClusters + perceptualVideoLane.clusters

                    for cluster in emittedClusters {
                        if cancelFlag.get() { continuation.finish(); return }
                        continuation.yield(.clusterDiscovered(cluster))
                    }
                    // 7. Summary.
                    var counts: [ClusterKind: Int] = [:]
                    for cluster in emittedClusters {
                        counts[cluster.kind, default: 0] += 1
                    }
                    let defaultPlan = DeduplicationPlanner.plan(
                        decisions: DedupeDecisions(),
                        clusters: emittedClusters,
                        configuration: configuration
                    )
                    continuation.yield(.complete(DeduplicateSummary(
                        clusterCounts: counts,
                        totalRecoverableBytes: defaultPlan.totalBytes,
                        totalCandidatesScanned: imagePaths.count + videoPaths.count,
                        scanDuration: Date().timeIntervalSince(started),
                        cacheMetrics: DedupeCacheMetrics(hits: cacheHits, misses: cacheMisses),
                        videoPerceptualMetrics: perceptualVideoLane.metrics
                    )))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private static func scanRoots(
        for configuration: DeduplicateConfiguration
    ) -> [(path: String, url: URL)] {
        var roots: [(path: String, url: URL)] = []
        var seen = Set<String>()
        let rootPaths = [configuration.destinationPath] + configuration.additionalSources.map(\.path)
        for path in rootPaths {
            let url = URL(fileURLWithPath: path).standardizedFileURL
            let standardizedPath = url.path
            guard seen.insert(standardizedPath).inserted else { continue }
            roots.append((path: standardizedPath, url: url))
        }
        return roots
    }

    fileprivate static func imageDimensions(at url: URL) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return nil
        }
        let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        guard let width, let height else { return nil }
        return (width, height)
    }

    private static func processIdentityHashes(
        paths: [String],
        cacheIndex: [String: FileCacheRecord],
        identityHasher: FileIdentityHasher,
        workerCount: Int,
        cancelFlag: ManagedAtomicBool,
        continuation: AsyncThrowingStream<DeduplicateEvent, Error>.Continuation,
        emitProgress: Bool = true,
        progressOffset: Int = 0,
        progressTotal: Int? = nil
    ) async throws -> [ProcessedFileIdentity] {
        guard !paths.isEmpty else { return [] }
        let maxWorkers = max(1, workerCount)
        if maxWorkers == 1 || paths.count == 1 {
            var results: [ProcessedFileIdentity] = []
            results.reserveCapacity(paths.count)
            for (offset, path) in paths.enumerated() {
                if cancelFlag.get() {
                    results.append(ProcessedFileIdentity(identity: nil, size: 0, modificationTime: 0, wasHashed: false))
                    continue
                }
                results.append(identityHasher.processFile(at: path, cachedRecord: cacheIndex[path]))
                if emitProgress, (offset + 1) % 50 == 0 || offset == paths.count - 1 {
                    continuation.yield(.phaseProgress(
                        phase: .identityHashing,
                        completed: progressOffset + offset + 1,
                        total: progressTotal ?? progressOffset + paths.count
                    ))
                }
            }
            return results
        }

        let results = OrderedIdentityResults(count: paths.count)

        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeTasks = 0
            for (index, path) in paths.enumerated() {
                if cancelFlag.get() {
                    break
                }

                if activeTasks >= maxWorkers {
                    _ = try await group.next()
                    activeTasks -= 1
                }

                activeTasks += 1
                let cachedRecord = cacheIndex[path]

                group.addTask {
                    if cancelFlag.get() {
                        _ = results.store(
                            ProcessedFileIdentity(identity: nil, size: 0, modificationTime: 0, wasHashed: false),
                            at: index
                        )
                        return
                    }
                    let processed = identityHasher.processFile(at: path, cachedRecord: cachedRecord)
                    let completed = results.store(processed, at: index)
                    if emitProgress, completed % 50 == 0 || completed == paths.count {
                        continuation.yield(.phaseProgress(
                            phase: .identityHashing,
                            completed: progressOffset + completed,
                            total: progressTotal ?? progressOffset + paths.count
                        ))
                    }
                }
            }

            while activeTasks > 0 {
                _ = try await group.next()
                activeTasks -= 1
            }
        }

        return results.values()
    }

    /// Exact-duplicate analysis for standalone videos. Builds `PhotoCandidate`s
    /// with `mediaKind == .video` and **no** photo-quality signals — the
    /// `DefaultDedupeImageAnalyzer` is never invoked. Size-prefiltered: only
    /// files that share a size with another candidate are hashed, so a
    /// unique-size video is never read from disk.
    struct VideoExactLaneResult {
        var candidates: [PhotoCandidate] = []
        var identityByPath: [String: FileIdentity] = [:]
        /// Newly hashed identities to checkpoint into FileCache so subsequent
        /// scans of the same size-collision videos are served from cache.
        var newCacheRecords: [FileCacheRecord] = []
        /// Identity-hash cache hits/misses for these videos, folded into the
        /// scan's `DedupeCacheMetrics`. Only the hashed (size-collision) videos
        /// are counted; size-unique videos are skipped by the prefilter.
        var cacheHits: Int = 0
        var cacheMisses: Int = 0
    }

    static func processVideoExactLane(
        collisionPaths: [String],
        cacheIndex: [String: FileCacheRecord],
        folderRootByPath: [String: String],
        identityHasher: FileIdentityHasher,
        workerCount: Int,
        cancelFlag: ManagedAtomicBool,
        continuation: AsyncThrowingStream<DeduplicateEvent, Error>.Continuation,
        progressOffset: Int = 0,
        progressTotal: Int? = nil
    ) async throws -> VideoExactLaneResult {
        guard !collisionPaths.isEmpty else { return VideoExactLaneResult() }

        var pathsBySize: [Int64: [String]] = [:]
        for path in collisionPaths {
            var st = stat()
            guard lstat(path, &st) == 0 else { continue }
            pathsBySize[Int64(st.st_size), default: []].append(path)
        }
        let validatedCollisionPaths = pathsBySize.values
            .filter { $0.count > 1 }
            .flatMap { $0 }
            .sorted()

        let identities = try await processIdentityHashes(
            paths: validatedCollisionPaths,
            cacheIndex: cacheIndex,
            identityHasher: identityHasher,
            workerCount: workerCount,
            cancelFlag: cancelFlag,
            continuation: continuation,
            progressOffset: progressOffset,
            progressTotal: progressTotal
        )

        var result = VideoExactLaneResult()
        for (index, path) in validatedCollisionPaths.enumerated() {
            guard index < identities.count, let identity = identities[index].identity else { continue }
            let processed = identities[index]
            result.identityByPath[path] = identity
            if processed.wasHashed {
                result.cacheMisses += 1
                result.newCacheRecords.append(FileCacheRecord(
                    namespace: .destination,
                    path: path,
                    identity: identity,
                    size: processed.size,
                    modificationTime: processed.modificationTime
                ))
            } else {
                result.cacheHits += 1
            }
            result.candidates.append(PhotoCandidate(
                path: path,
                size: processed.size,
                modificationTime: processed.modificationTime,
                folderRoot: folderRootByPath[path],
                mediaKind: .video
            ))
        }
        return result
    }

    static func videoExactCollisionPaths(in videoPaths: [String]) -> [String] {
        var pathsBySize: [Int64: [String]] = [:]
        for path in videoPaths {
            var st = stat()
            guard lstat(path, &st) == 0 else { continue }
            pathsBySize[Int64(st.st_size), default: []].append(path)
        }
        return pathsBySize.values
            .filter { $0.count > 1 }
            .flatMap { $0 }
            .sorted()
    }

    private static func cachedFeatureRecord(
        for path: String,
        in cache: [String: DedupeFeatureRecord]
    ) -> DedupeFeatureRecord? {
        cache[path] ?? cache[URL(fileURLWithPath: path).standardizedFileURL.path]
    }

    /// Opt-in perceptual video lane (Milestone 2b). Decodes/loads cached
    /// features for every candidate video, runs the pure perceptual matcher,
    /// and returns review-only `.nearDuplicate` clusters plus honest per-status
    /// accounting. Decodes nothing — and touches no DB — when the flag is off.
    struct VideoPerceptualLaneResult {
        var clusters: [DuplicateCluster] = []
        /// `nil` when the lane did not run (flag off), so the summary can stay
        /// silent rather than report all-zero counts.
        var metrics: VideoPerceptualAnalysisMetrics?
    }

    /// How many freshly-extracted records to accumulate before flushing to the
    /// cache, so a long video scan that is cancelled or crashes preserves the
    /// expensive decode work done so far (mirrors the photo feature loop).
    private static let videoFeatureFlushBatch = 25

    static func processVideoPerceptualLane(
        videoPaths: [String],
        exactClusterPaths: Set<String>,
        folderRootByPath: [String: String],
        folderPriority: [String: Int],
        database: OrganizerDatabase,
        provider: any VideoFeatureProviding,
        configuration: DeduplicateConfiguration,
        cancelFlag: ManagedAtomicBool,
        continuation: AsyncThrowingStream<DeduplicateEvent, Error>.Continuation
    ) -> VideoPerceptualLaneResult {
        // Off by default: no decode, no DB mutation, no metrics.
        guard configuration.perceptualVideoMatchingEnabled else {
            return VideoPerceptualLaneResult(clusters: [], metrics: nil)
        }

        // Exclusivity (exact wins): hold out every video already in an
        // exact-duplicate cluster — including the kept one. A transcode of an
        // exact group resurfaces only after the user cleans exacts and rescans.
        let candidatePaths = videoPaths.filter { !exactClusterPaths.contains($0) }
        let deferred = videoPaths.count - candidatePaths.count

        var metrics = VideoPerceptualAnalysisMetrics(deferredPendingExactCleanup: deferred)
        continuation.yield(.phaseStarted(phase: .videoAnalysis, total: candidatePaths.count))

        // Nothing to analyze: report the lane ran but leave the cache untouched
        // (never prune to an empty set — that would drop still-present deferred
        // videos' cached features and force a cold re-decode after cleanup).
        guard !candidatePaths.isEmpty else {
            continuation.yield(.phaseCompleted(phase: .videoAnalysis))
            return VideoPerceptualLaneResult(clusters: [], metrics: metrics)
        }

        try? database.ensureDedupeVideoFeaturesSchema()
        let cached = (try? database.loadDedupeVideoFeatureRecords()) ?? [:]

        var readyFeatures: [VideoPerceptualFeatures] = []
        var freshRecords: [DedupeVideoFeatureRecord] = []
        var probes: [VideoMetadataProbe] = []
        var pendingExtractions: [VideoMetadataProbe] = []
        var completed = 0

        func reportProgress() {
            completed += 1
            continuation.yield(.phaseProgress(
                phase: .videoAnalysis,
                completed: completed,
                total: candidatePaths.count
            ))
        }

        func checkpoint(_ features: VideoPerceptualFeatures) {
            freshRecords.append(DedupeVideoFeatureRecord(features: features))
            if freshRecords.count >= videoFeatureFlushBatch {
                try? database.saveDedupeVideoFeatureRecords(freshRecords)
                freshRecords.removeAll(keepingCapacity: true)
            }
        }

        func probe(from features: VideoPerceptualFeatures) -> VideoMetadataProbe {
            VideoMetadataProbe(
                path: features.path,
                size: features.size,
                modificationTime: features.modificationTime,
                durationSeconds: features.durationSeconds,
                transformedWidth: features.transformedWidth,
                transformedHeight: features.transformedHeight,
                estimatedDataRate: features.estimatedDataRate,
                metadataCompleteness: features.metadataCompleteness,
                folderRoot: features.folderRoot,
                status: features.status
            )
        }

        func tally(_ status: VideoDecodeStatus) {
            switch status {
            case .ready: metrics.analyzed += 1
            case .unsupported: metrics.unsupported += 1
            case .decodeFailed: metrics.decodeFailed += 1
            case .insufficientVisualEvidence: metrics.insufficientVisualEvidence += 1
            }
        }

        for path in candidatePaths {
            if cancelFlag.get() { break }
            var st = stat()
            guard lstat(path, &st) == 0 else {
                metrics.decodeFailed += 1
                reportProgress()
                continue
            }
            let size = Int64(st.st_size)
            let mtime = Double(st.st_mtimespec.tv_sec) + Double(st.st_mtimespec.tv_nsec) / 1_000_000_000
            let folderRoot = folderRootByPath[path]

            // Cache hit: reuse the stored features (including non-ready
            // outcomes, which are recorded so undecodable/insufficient videos
            // are not re-decoded every scan).
            if let record = cached[path] ?? cached[URL(fileURLWithPath: path).standardizedFileURL.path],
               record.isValid(size: size, modificationTime: mtime) {
                metrics.cacheHits += 1
                var features = record.features
                features.folderRoot = folderRoot
                tally(features.status)
                if features.status == .ready {
                    readyFeatures.append(features)
                    probes.append(probe(from: features))
                }
                reportProgress()
                continue
            }

            // Cache miss: first read cheap track metadata. Full frame extraction
            // happens only after all probes establish a plausible neighbor.
            metrics.cacheMisses += 1
            let metadata = provider.probeMetadata(
                path: path,
                size: size,
                modificationTime: mtime,
                folderRoot: folderRoot,
                isCancelled: { cancelFlag.get() }
            )
            guard !cancelFlag.get() else { break }
            if metadata.status == .ready {
                probes.append(metadata)
                pendingExtractions.append(metadata)
            } else {
                let features = VideoPerceptualFeatures(
                    path: path,
                    size: size,
                    modificationTime: mtime,
                    durationSeconds: metadata.durationSeconds,
                    transformedWidth: metadata.transformedWidth,
                    transformedHeight: metadata.transformedHeight,
                    estimatedDataRate: metadata.estimatedDataRate,
                    metadataCompleteness: metadata.metadataCompleteness,
                    frameHashes: Array(repeating: nil, count: VideoPerceptualAnalysis.sampleFractions.count),
                    status: metadata.status,
                    folderRoot: folderRoot
                )
                tally(features.status)
                checkpoint(features)
                reportProgress()
            }
        }

        let decodePaths = VideoPerceptualMatcher.metadataCandidatePaths(
            probes: probes,
            configuration: configuration.videoPerceptualMatchConfiguration
        )
        for metadata in pendingExtractions {
            if cancelFlag.get() { break }
            if decodePaths.contains(metadata.path) {
                let pacingDelay = videoDecodePacingDelay(
                    lowPowerMode: ProcessInfo.processInfo.isLowPowerModeEnabled,
                    thermalState: ProcessInfo.processInfo.thermalState
                )
                if pacingDelay > 0 { Thread.sleep(forTimeInterval: pacingDelay) }
                let features = provider.extractFeatures(
                    metadata: metadata,
                    isCancelled: { cancelFlag.get() }
                )
                guard !cancelFlag.get() else { break }
                tally(features.status)
                if features.status == .ready { readyFeatures.append(features) }
                checkpoint(features)
            } else {
                metrics.prefilteredNoNeighbor += 1
            }
            reportProgress()
        }

        if !freshRecords.isEmpty {
            try? database.saveDedupeVideoFeatureRecords(freshRecords)
        }
        // Prune only here — the perceptual lane is the only writer/owner of the
        // video feature cache, so an exact-only / perceptual-off scan must
        // never reach this and cold-evict the rows.
        try? database.pruneDedupeVideoFeatureRecords(notIn: Set(videoPaths))

        let clusters = VideoPerceptualMatcher.cluster(
            features: readyFeatures,
            configuration: configuration.videoPerceptualMatchConfiguration,
            folderPriority: folderPriority
        )
        continuation.yield(.phaseCompleted(phase: .videoAnalysis))
        return VideoPerceptualLaneResult(clusters: clusters, metrics: metrics)
    }

    static func videoDecodePacingDelay(
        lowPowerMode: Bool,
        thermalState: ProcessInfo.ThermalState
    ) -> TimeInterval {
        let thermalDelay: TimeInterval
        switch thermalState {
        case .nominal: thermalDelay = 0
        case .fair: thermalDelay = 0.01
        case .serious, .critical: thermalDelay = 0.05
        @unknown default: thermalDelay = 0.05
        }
        return max(thermalDelay, lowPowerMode ? 0.025 : 0)
    }

    private static func processAnalysisRequests(
        _ requests: [DedupeAnalysisRequest],
        analyzer: any DedupeImageAnalyzing,
        workerCount: Int,
        cancelFlag: ManagedAtomicBool
    ) async throws -> [Int: DedupeImageAnalysis] {
        guard !requests.isEmpty else { return [:] }
        let maxWorkers = max(1, workerCount)
        if maxWorkers == 1 || requests.count == 1 {
            var results: [Int: DedupeImageAnalysis] = [:]
            for request in requests {
                if cancelFlag.get() { break }
                results[request.offset] = analyzer.analyze(url: request.url, size: request.size)
            }
            return results
        }

        let results = AnalysisResults()

        try await withThrowingTaskGroup(of: Void.self) { group in
            var activeTasks = 0
            for request in requests {
                if cancelFlag.get() {
                    break
                }

                if activeTasks >= maxWorkers {
                    _ = try await group.next()
                    activeTasks -= 1
                }

                activeTasks += 1

                group.addTask {
                    guard !cancelFlag.get() else { return }
                    let analysis = analyzer.analyze(url: request.url, size: request.size)
                    results.store(analysis, at: request.offset)
                }
            }

            while activeTasks > 0 {
                _ = try await group.next()
                activeTasks -= 1
            }
        }

        return results.values()
    }
}

struct DedupeImageAnalysis: Sendable {
    var captureDate: Date?
    var pixelWidth: Int?
    var pixelHeight: Int?
    var dhash: UInt64?
    var featurePrintData: Data?
    var featurePrintFailureMessage: String?
    var quality: PhotoQualityScore
    var eyesOpenScore: Double? = nil
    var smileScore: Double? = nil
    var subjectSharpness: Double? = nil
    var subjectMotionBlur: Double? = nil
}

protocol DedupeImageAnalyzing: Sendable {
    func analyze(url: URL, size: Int64) -> DedupeImageAnalysis
}

struct DefaultDedupeImageAnalyzer: DedupeImageAnalyzing {
    var dateResolver: FileDateResolver
    private let resources = DedupeImageAnalyzerResources()

    func analyze(url: URL, size: Int64) -> DedupeImageAnalysis {
        let metadata = Self.imageMetadata(at: url)
        let vision = Self.visionAnalysis(at: url)
        let quality = PhotoQualityScorer.score(
            at: url,
            sizeBytes: size,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            ciContext: resources.ciContext,
            faceScore: vision.faceScore
        )
        let expressionAwareQuality = PhotoQualityScorer.expressionAwareScore(
            sharpness: quality.sharpness,
            faceScore: vision.faceScore,
            eyesOpenScore: vision.eyesOpenScore,
            smileScore: vision.smileScore,
            subjectMotionBlur: vision.subjectMotionBlur,
            sizeBytes: size,
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight
        )
        return DedupeImageAnalysis(
            captureDate: dateResolver.resolveDate(for: url.path, precomputedPhotoMetadataDate: metadata.captureDate),
            pixelWidth: metadata.pixelWidth,
            pixelHeight: metadata.pixelHeight,
            dhash: metadata.dhash,
            featurePrintData: vision.featurePrintData,
            featurePrintFailureMessage: vision.featurePrintFailureMessage,
            quality: expressionAwareQuality,
            eyesOpenScore: vision.eyesOpenScore,
            smileScore: vision.smileScore,
            subjectSharpness: vision.subjectSharpness,
            subjectMotionBlur: vision.subjectMotionBlur
        )
    }

    private static func imageMetadata(at url: URL) -> DedupeImageMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return DedupeImageMetadata()
        }

        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        let captureDate = properties.flatMap(captureDate(from:))
        let dhash = thumbnailDHash(from: source)

        return DedupeImageMetadata(
            pixelWidth: width,
            pixelHeight: height,
            dhash: dhash,
            captureDate: captureDate
        )
    }

    private static func captureDate(from properties: [CFString: Any]) -> Date? {
        if
            let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any],
            let rawValue = exif[kCGImagePropertyExifDateTimeOriginal] as? String,
            let parsed = NativeMediaMetadataDateReader.parseImagePropertyDate(rawValue)
        {
            return parsed
        }

        if
            let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any],
            let rawValue = tiff[kCGImagePropertyTIFFDateTime] as? String,
            let parsed = NativeMediaMetadataDateReader.parseImagePropertyDate(rawValue)
        {
            return parsed
        }

        return nil
    }

    private static func thumbnailDHash(from source: CGImageSource) -> UInt64? {
        let options: [CFString: Any] = [
            kCGImageSourceShouldCache: false,
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return PerceptualHash.dhash(from: thumbnail)
    }

    private static func visionAnalysis(at url: URL) -> DedupeVisionAnalysis {
        let featureRequest = VNGenerateImageFeaturePrintRequest()
        featureRequest.imageCropAndScaleOption = .scaleFill
        let faceRequest = VNDetectFaceLandmarksRequest()
        let handler = VNImageRequestHandler(url: url, options: [:])

        do {
            try handler.perform([featureRequest, faceRequest])
        } catch {
            return DedupeVisionAnalysis(
                featurePrintData: nil,
                featurePrintFailureMessage: "Feature print failed: \(error.localizedDescription)",
                faceScore: nil
            )
        }

        let featurePrintData: Data?
        let featurePrintFailureMessage: String?
        if let observation = featureRequest.results?.first as? VNFeaturePrintObservation {
            do {
                featurePrintData = try NSKeyedArchiver.archivedData(
                    withRootObject: observation,
                    requiringSecureCoding: true
                )
                featurePrintFailureMessage = nil
            } catch {
                featurePrintData = nil
                featurePrintFailureMessage = "Feature print failed: \(error.localizedDescription)"
            }
        } else {
            featurePrintData = nil
            featurePrintFailureMessage = "Feature print failed: no observation produced"
        }

        let expression = faceRequest.results.flatMap { faces -> FaceExpressionAnalyzer.Result? in
            guard
                let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else {
                return nil
            }
            return FaceExpressionAnalyzer.analyze(cgImage: cgImage, faceObservations: faces)
        }

        return DedupeVisionAnalysis(
            featurePrintData: featurePrintData,
            featurePrintFailureMessage: featurePrintFailureMessage,
            faceScore: PhotoQualityScorer.faceScore(from: faceRequest.results),
            eyesOpenScore: expression?.eyesOpenConfidence,
            smileScore: expression?.smileConfidence,
            subjectSharpness: expression?.subjectSharpness,
            subjectMotionBlur: expression?.subjectMotionBlur
        )
    }
}

private final class DedupeImageAnalyzerResources: @unchecked Sendable {
    let ciContext = CIContext(options: [.useSoftwareRenderer: false])
}

private struct DedupeImageMetadata {
    var pixelWidth: Int?
    var pixelHeight: Int?
    var dhash: UInt64?
    var captureDate: Date?

    init(
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        dhash: UInt64? = nil,
        captureDate: Date? = nil
    ) {
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.dhash = dhash
        self.captureDate = captureDate
    }
}

private struct DedupeVisionAnalysis {
    var featurePrintData: Data?
    var featurePrintFailureMessage: String?
    var faceScore: Double?
    var eyesOpenScore: Double? = nil
    var smileScore: Double? = nil
    var subjectSharpness: Double? = nil
    var subjectMotionBlur: Double? = nil
}

private struct DedupeAnalysisRequest: Sendable {
    var offset: Int
    var path: String
    var url: URL
    var size: Int64
    var modificationTime: TimeInterval
    var pairedPath: String?
    var isRaw: Bool
    var isLivePhotoStill: Bool
    var folderRoot: String?
}

private final class OrderedIdentityResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [ProcessedFileIdentity?]
    private var completedCount = 0

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    func store(_ result: ProcessedFileIdentity, at index: Int) -> Int {
        lock.lock()
        storage[index] = result
        completedCount += 1
        let completed = completedCount
        lock.unlock()
        return completed
    }

    func values() -> [ProcessedFileIdentity] {
        lock.lock()
        let values = storage.map {
            $0 ?? ProcessedFileIdentity(identity: nil, size: 0, modificationTime: 0, wasHashed: false)
        }
        lock.unlock()
        return values
    }
}

private final class AnalysisResults: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [Int: DedupeImageAnalysis] = [:]

    func store(_ result: DedupeImageAnalysis, at index: Int) {
        lock.lock()
        storage[index] = result
        lock.unlock()
    }

    func values() -> [Int: DedupeImageAnalysis] {
        lock.lock()
        let values = storage
        lock.unlock()
        return values
    }
}


/// Lock-free atomic Bool wrapper (uses OSAllocatedUnfairLock under the hood).
/// Used to signal cancellation across the detached scan task.
final class ManagedAtomicBool: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool = false

    func set(_ newValue: Bool) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
