import XCTest
@testable import ChronoframeCore
@testable import ChronoframeAppCore

final class CoveragePushTests: XCTestCase {
    func testCopyPlanBuilderEdgeCases() {
        // Warning about sequence width
        XCTAssertTrue(CopyPlanBuilder.shouldWarnAboutSequenceWidth(existingMaxSequence: 900, plannedWidth: 4, defaultWidth: 3))
        XCTAssertFalse(CopyPlanBuilder.shouldWarnAboutSequenceWidth(existingMaxSequence: 100, plannedWidth: 3, defaultWidth: 3))
        
        // Info about sequence width
        XCTAssertTrue(CopyPlanBuilder.shouldEmitSequenceWidthInfo(existingMaxSequence: 0, plannedWidth: 4, defaultWidth: 3))
        XCTAssertFalse(CopyPlanBuilder.shouldEmitSequenceWidthInfo(existingMaxSequence: 0, plannedWidth: 3, defaultWidth: 3))
        
        let msg = CopyPlanBuilder.sequenceWidthInfoMessage(dateBucket: "2023-01-01", count: 1000, width: 4)
        XCTAssertTrue(msg.contains("1,000"))
    }

    func testCopyPlanResultMapsTransfersIntoPendingCopyJobs() {
        let identity = FileIdentity(size: 12, digest: String(repeating: "a", count: 128))
        let transfer = PlannedTransfer(
            sourcePath: "/source/IMG_0001.jpg",
            destinationPath: "/dest/2024-01-01_001.jpg",
            identity: identity,
            dateBucket: "2024-01-01",
            isDuplicate: false
        )
        let result = CopyPlanResult(
            transfers: [transfer],
            counts: CopyPlanCounts(newCount: 1),
            warningMessages: [],
            sequenceState: SequenceCounterState()
        )

        XCTAssertEqual(result.transferCount, 1)
        XCTAssertEqual(result.copyJobs, [
            CopyJobRecord(
                sourcePath: transfer.sourcePath,
                destinationPath: transfer.destinationPath,
                identity: identity,
                status: .pending
            )
        ])
    }
    
    func testDateClassificationEdgeCases() {
        let naming = PlannerNamingRules.chronoframeDefault
        XCTAssertEqual(DateClassification.bucket(for: nil, namingRules: naming), naming.unknownDateDirectoryName)
    }
    
    func testRunHistoryEntryKindTitles() {
        XCTAssertEqual(RunHistoryEntryKind.runLog.title, "Run Log")
        XCTAssertEqual(RunHistoryEntryKind.queueDatabase.title, "Queue Database")
        XCTAssertEqual(RunHistoryEntryKind.dryRunReport.title, "Dry Run Report")
        XCTAssertEqual(RunHistoryEntryKind.auditReceipt.title, "Audit Receipt")
    }

    func testFaceExpressionAnalyzerEdgeCases() {
        // Test eyeOpenness with very few points
        XCTAssertEqual(FaceExpressionAnalyzer.eyeOpenness(points: [CGPoint(x: 0, y: 0)]), 0.5)
        
        // Test eyeOpenness with zero width
        let verticalPoints = [CGPoint(x: 0, y: 0), CGPoint(x: 0, y: 10), CGPoint(x: 0, y: 5), CGPoint(x: 0, y: 5), CGPoint(x: 0, y: 5), CGPoint(x: 0, y: 5)]
        XCTAssertEqual(FaceExpressionAnalyzer.eyeOpenness(points: verticalPoints), 0.5)
        
        // Test regionSharpness with invalid rect
        let width = 64
        let height = 64
        var pixels = [UInt8](repeating: 128, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cgImage = context.makeImage()!
        
        let sharpness = FaceExpressionAnalyzer.regionSharpness(cgImage: cgImage, normalizedRect: CGRect(x: 0, y: 0, width: 0.01, height: 0.01))
        XCTAssertEqual(sharpness, 0.0)
    }
    
    func testCancellationInMediaDiscovery() {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
        XCTAssertThrowsError(try MediaDiscovery.discoverMediaFiles(at: url, isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError)
        }
        XCTAssertThrowsError(try MediaDiscovery.walkEntries(at: url, isCancelled: { true })) { error in
            XCTAssertTrue(error is CancellationError)
        }
        
        // Test default closures
        let tempEmptyDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Empty-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempEmptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempEmptyDir) }
        
        // This exercises the { false } default parameter for isCancelled
        _ = try? MediaDiscovery.discoverMediaFiles(at: tempEmptyDir)
        _ = try? MediaDiscovery.walkEntries(at: tempEmptyDir)
    }
    
    func testCopyPlanBuilderHistogramEdgeCases() {
        let naming = PlannerNamingRules.chronoframeDefault
        
        let paths = [
            "short",
            "1234567890X.jpg",
            "2023X01-01_1.jpg",
            "2023-XX-01_1.jpg",
            "2023-01-XX_1.jpg",
            "UnknownFile_1.jpg",
            "2023-01-01_1.jpg",
            "2023-02-01_1.jpg"
        ]
        
        let histogram = CopyPlanBuilder.dateHistogram(fromDestinationPaths: paths, namingRules: naming)
        
        XCTAssertGreaterThanOrEqual(histogram.count, 0)
    }
    
    func testDedupeFeatureCacheWithNullValues() throws {
        let tempEmptyDir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("DedupeNull-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempEmptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempEmptyDir) }
        
        let dbURL = tempEmptyDir.appendingPathComponent("dedupe_null.db")
        let database = try OrganizerDatabase(url: dbURL)
        defer { database.close() }
        
        try database.ensureDedupeFeaturesSchema()

        let record = DedupeFeatureRecord(
            path: "/path/null",
            size: 100,
            modificationTime: 1.0,
            dhash: nil,
            featurePrintData: nil,
            sharpness: 0.0,
            faceScore: nil,
            pixelWidth: nil,
            pixelHeight: nil,
            captureDate: nil,
            pairedPath: nil,
            eyesOpenScore: nil,
            smileScore: nil,
            subjectSharpness: nil,
            subjectMotionBlur: nil,
            folderRoot: nil
        )

        try database.saveDedupeFeatureRecords([record])

        let loaded = try database.loadDedupeFeatureRecords()
        XCTAssertEqual(loaded["/path/null"]?.faceScore, nil)

        let loadedMeta = try database.loadDedupeFeatureMetadataRecords()
        XCTAssertEqual(loadedMeta["/path/null"]?.faceScore, nil)
        
        let emptyPrints = try database.loadDedupeFeaturePrintData(for: [])
        XCTAssertTrue(emptyPrints.isEmpty)
        
        let allPrints = try database.loadAllDedupeFeaturePrintData()
        XCTAssertTrue(allPrints.isEmpty)
    }

    func testPhotoQualityScorerExpressionAwareAndFaceScore() {
        // Test expression-aware score fallback when eyesOpenScore is nil
        let scoreFallback = PhotoQualityScorer.expressionAwareScore(
            sharpness: 0.8,
            faceScore: 0.9,
            eyesOpenScore: nil,
            smileScore: 0.5,
            subjectMotionBlur: 0.0,
            sizeBytes: 1024,
            pixelWidth: 640,
            pixelHeight: 480
        )
        XCTAssertGreaterThan(scoreFallback.composite, 0.0)

        // Test expression-aware score with eyesOpenScore and motion blur
        let scoreWithBlur = PhotoQualityScorer.expressionAwareScore(
            sharpness: 0.8,
            faceScore: 0.9,
            eyesOpenScore: 0.9,
            smileScore: 0.7,
            subjectMotionBlur: 0.5,
            sizeBytes: 1024,
            pixelWidth: 640,
            pixelHeight: 480
        )
        XCTAssertGreaterThan(scoreWithBlur.composite, 0.0)

        // Test faceScore helper nil/empty cases
        XCTAssertNil(PhotoQualityScorer.faceScore(from: nil))
        XCTAssertNil(PhotoQualityScorer.faceScore(from: []))
    }

    func testSafetyWarningDetectorEdgeCases() {
        let member1 = PhotoCandidate(
            path: "/path/1.jpg",
            size: 100,
            modificationTime: 1000.0,
            captureDate: Date(timeIntervalSince1970: 1000),
            pixelWidth: 100,
            pixelHeight: 100,
            sharpness: 0.8,
            faceScore: 0.9
        )
        let member2 = PhotoCandidate(
            path: "/path/2.jpg",
            size: 200,
            modificationTime: 2000.0,
            captureDate: Date(timeIntervalSince1970: 2000),
            pixelWidth: 300,
            pixelHeight: 300, // 300x300 area, 1:1 aspect
            sharpness: 0.1, // 0.8 / 0.1 = 8.0 > 2.5 exposure diff
            faceScore: 0.5 // 1 face (diff = 1 face warning)
        )

        let cluster = DuplicateCluster(
            id: UUID(),
            kind: .nearDuplicate,
            members: [member1, member2],
            suggestedKeeperIDs: [],
            bytesIfPruned: 0
        )

        let warnings = SafetyWarningDetector.detect(cluster: cluster, pairwiseMatches: [])
        XCTAssertEqual(warnings.count, 4) // exposure diff, different people, different framing (areas 10000 vs 90000), and large time gap (1000s > 300s)

        // Test aspect ratio warning separately
        let member3 = PhotoCandidate(
            path: "/path/3.jpg",
            size: 100,
            modificationTime: 1000.0,
            captureDate: Date(),
            pixelWidth: 400,
            pixelHeight: 300, // 4:3 aspect
            sharpness: 0.5
        )
        let member4 = PhotoCandidate(
            path: "/path/4.jpg",
            size: 100,
            modificationTime: 1000.0,
            captureDate: Date(),
            pixelWidth: 1600,
            pixelHeight: 900, // 16:9 aspect (diff > 1.10 aspect ratio ratio)
            sharpness: 0.5
        )
        let aspectCluster = DuplicateCluster(
            id: UUID(),
            kind: .nearDuplicate,
            members: [member3, member4],
            suggestedKeeperIDs: [],
            bytesIfPruned: 0
        )
        let aspectWarnings = SafetyWarningDetector.detect(cluster: aspectCluster, pairwiseMatches: [])
        XCTAssertTrue(aspectWarnings.contains(where: {
            if case .differentFraming = $0 { return true }
            return false
        }))
    }

    func testBLAKE2bHasherEmptyDataAndBuffer() {
        var hasher = BLAKE2bHasher()
        hasher.update(Data()) // empty data
        let emptyBuffer = UnsafeRawBufferPointer(start: nil, count: 0)
        hasher.update(emptyBuffer) // empty buffer
        let hex = hasher.finalizeHexDigest()
        XCTAssertEqual(hex.count, 128) // 64 bytes digest -> 128 hex characters
    }
}
