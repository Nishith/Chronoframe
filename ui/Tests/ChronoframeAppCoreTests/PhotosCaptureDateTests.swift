import AVFoundation
import Foundation
import ImageIO
import UniformTypeIdentifiers
import XCTest
@testable import ChronoframeCore
@testable import ChronoframeAppCore

/// Every fixture is encoded locally from pixels and synthetic metadata.
final class PhotosCaptureDateTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("PhotosDates-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        root = root.resolvingSymlinksInPath()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testNativeMovieDateUsesRecordedLocalDayBeforeFilenameOrFilesystem() throws {
        let url = root.appendingPathComponent("VID_20261005_120000.mov")
        try writeMovie(at: url, date: "2026-01-30T23:59:59-0800")
        let resolved = FileDateResolver().resolveResolvedDate(for: url.path)
        XCTAssertEqual(DateClassification.bucket(for: resolved.date, timeZoneOffsetSeconds: resolved.bucketTimeZoneOffsetSeconds), "2026-01-30")
        XCTAssertEqual(resolved.confidence, .high)
    }

    @MainActor
    func testExportThroughVerifiedTransferKeepsMidnightLivePhotoTogether() async throws {
        try await assertPairDate(stillDate: "2026:08:01 00:00:00", offset: "+05:30",
                                 movieDate: "2026-07-31T23:59:59+0530", assetDate: "2026-10-05T12:00:00Z", folder: "2026/08/01")
        try await assertPairDate(stillDate: "2026:08:01 23:59:59", offset: "-07:00",
                                 movieDate: "2026-08-02T00:00:01-0700", assetDate: nil, folder: "2026/08/01")
    }

    @MainActor
    func testPairFallsBackTogetherFromInvalidStillToMovieThenAssetThenUnknown() async throws {
        try await assertPairDate(stillDate: "not a date", offset: nil,
                                 movieDate: "2026-01-30T23:59:59-0800", assetDate: "2026-10-05T12:00:00Z", folder: "2026/01/30")
        try await assertPairDate(stillDate: nil, offset: nil,
                                 movieDate: "invalid", assetDate: "2026-07-17T08:09:10Z", folder: "2026/07/17")
        try await assertPairDate(stillDate: nil, offset: nil,
                                 movieDate: nil, assetDate: nil, folder: "Unknown_Date")
    }

    @MainActor
    private func assertPairDate(stillDate: String?, offset: String?, movieDate: String?, assetDate: String?, folder: String) async throws {
        let testRoot = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: testRoot, withIntermediateDirectories: true)
        let still = testRoot.appendingPathComponent("original.heic")
        try writeStill(at: still, date: stillDate, offset: offset)
        // Use the exact synthetic ID ImageIO encoded (its MakerApple field may be padded).
        let identifier = try XCTUnwrap(DeduplicatePairDetector.livePhotoIdentifier(forImageAt: still))
        let movie = testRoot.appendingPathComponent("original.mov")
        try writeMovie(at: movie, date: movieDate, identifier: identifier)
        let originalBytes = try [Data(contentsOf: still), Data(contentsOf: movie)]
        let staging = testRoot.appendingPathComponent("staging")
        let destination = testRoot.appendingPathComponent("destination")
        let exporter = FixturePhotosExporter(urls: [still, movie])
        let plan = PhotosExportPlanner.plan(for: [PhotosAssetSummary(
            id: "synthetic-live", mediaKind: .photo,
            creationDate: assetDate.flatMap { ISO8601DateFormatter().date(from: $0) },
            pixelWidth: 16, pixelHeight: 16, originalFilename: "IMG_0001.HEIC",
            isFavorite: false, isCloudStoredOnly: false
        )])
        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: staging)
        XCTAssertEqual(receipt.failures, [])
        XCTAssertEqual(Set(try MediaDiscovery.discoverMediaFiles(at: staging).map(SourceDateHint.pathKey(for:))), Set(receipt.sourceDateHints.keys))
        for (path, hint) in receipt.sourceDateHints {
            XCTAssertEqual(try FileIdentityHasher().hashIdentity(at: URL(fileURLWithPath: path)), hint.identity)
        }
        let result = try await DryRunPlanner().planAsync(sourceRoot: staging, destinationRoot: destination, sourceDateHints: receipt.sourceDateHints)
        XCTAssertEqual(result.copyJobs.count, 2)
        for job in result.copyJobs {
            XCTAssertEqual(URL(fileURLWithPath: job.destinationPath).deletingLastPathComponent().path, destination.appendingPathComponent(folder).path)
        }
        let finalReceipt = try await transfer(staging: staging, destination: destination, hints: receipt.sourceDateHints)
        XCTAssertEqual(Set(finalReceipt.transfers.map(\.dest)), Set(result.copyJobs.map(\.destinationPath)))
        for item in finalReceipt.transfers {
            XCTAssertEqual(try Data(contentsOf: URL(fileURLWithPath: item.source)), try Data(contentsOf: URL(fileURLWithPath: item.dest)))
            XCTAssertEqual(try FileIdentityHasher().hashIdentity(at: URL(fileURLWithPath: item.dest)).rawValue, item.hash)
        }
        XCTAssertEqual(try Data(contentsOf: still), originalBytes[0])
        XCTAssertEqual(try Data(contentsOf: movie), originalBytes[1])
        let pairs = await DeduplicatePairDetector.detectPairs(in: finalReceipt.transfers.map(\.dest), includeLivePhotos: true)
        XCTAssertEqual(pairs.count, 2, "Final renamed files must still pair by their embedded identifiers")
    }

    @MainActor
    private func transfer(staging: URL, destination: URL, hints: [String: SourceDateHint]) async throws -> RevertReceipt {
        let engine = SwiftOrganizerEngine(authorizer: UnrestrictedTrialAuthorizer(), profilesRepository: FixtureProfiles(url: root.appendingPathComponent("profiles.yaml")))
        var configuration = RunConfiguration(mode: .preview, sourcePath: staging.path, destinationPath: destination.path, sourceDateHints: hints)
        for try await event in try engine.start(configuration) {
            if case let .complete(summary) = event { XCTAssertEqual(summary.status, .dryRunFinished) }
        }
        configuration.mode = .transfer
        for try await event in try engine.start(configuration) {
            if case let .complete(summary) = event {
                XCTAssertEqual(summary.status, .finished)
                XCTAssertEqual(summary.metrics.failedCount, 0)
                XCTAssertEqual(summary.metrics.copiedCount, hints.count)
            }
        }
        let logs = destination.appendingPathComponent(".organize_logs")
        let receiptURL = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("audit_receipt_") })
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: Data(contentsOf: receiptURL))
        XCTAssertEqual(receipt.status, "COMPLETED")
        return receipt
    }

    func testVideoMetadataParserRejectsInvalidCalendarAndOffsetValues() {
        for value in ["", "invalid", "2026-02-30T00:00:00Z", "2026-08-01T24:00:00Z", "1904-00-00T00:00:00Z", "0000-01-01T00:00:00Z", "2026-08-01T00:00:00+1460", "2026-08-01T00:00:00+1401", "2026-08-01T00:00:00+ab05:30"] {
            XCTAssertNil(VideoMetadataDateReader.parse(value), value)
        }
        for (value, folder, offset) in [
            ("2026-01-30T23:59:59-0800", "2026-01-30", -28800),
            ("2026-08-01T00:00:00.125+05:30", "2026-08-01", 19800),
            ("2026-07-17T08:09:10Z", "2026-07-17", 0),
        ] {
            let date = VideoMetadataDateReader.parse(value)
            XCTAssertNotNil(date)
            XCTAssertEqual(date?.bucketTimeZoneOffsetSeconds, offset)
            XCTAssertEqual(DateClassification.bucket(for: date?.date, timeZoneOffsetSeconds: date?.bucketTimeZoneOffsetSeconds), folder)
        }
        XCTAssertNil(VideoMetadataDateReader.parse("2026-08-01T00:00:00")?.bucketTimeZoneOffsetSeconds)
        XCTAssertNil(NativeMediaMetadataDateReader.offsetSeconds(from: "+ab05:30"))
    }

    func testMovieMetadataDeadlineAndCancellationDoNotWaitForAnUnresponsiveLoad() {
        let url = root.appendingPathComponent("slow.mov")
        let start = Date()
        let result = VideoMetadataDateReader.read(at: url, timeoutSeconds: 0.01, loader: { _ in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return nil
        })
        XCTAssertNil(result)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        final class Gate: @unchecked Sendable {
            let lock = NSLock()
            var started = false
            func start() { lock.withLock { started = true } }
            func cancelled() -> Bool { lock.withLock { started } }
        }
        let gate = Gate()
        let cancelStart = Date()
        let cancelled = VideoMetadataDateReader.read(at: url, isCancelled: { gate.cancelled() }, loader: { _ in
            gate.start()
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            return nil
        })
        XCTAssertNil(cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(cancelStart), 1)
    }

    @MainActor
    func testStandaloneVideosRetainCaptureDaysAndOriginalBytesThroughTransfer() async throws {
        for (timestamp, folder) in [("2026-01-30T12:34:56-0800", "2026/01/30"), ("2026-07-17T08:09:10Z", "2026/07/17")] {
            let clip = root.appendingPathComponent("original-\(UUID().uuidString).mov")
            try writeMovie(at: clip, date: timestamp)
            let staging = root.appendingPathComponent("stage-\(UUID().uuidString)")
            let destination = root.appendingPathComponent("dest-\(UUID().uuidString)")
            let plan = PhotosExportPlanner.plan(for: [PhotosAssetSummary(id: "clip", mediaKind: .video,
                creationDate: Date(), pixelWidth: 16, pixelHeight: 16, originalFilename: "VID_20261005_120000.MOV", isFavorite: false, isCloudStoredOnly: false)])
            let exported = try await PhotosExportExecutor(exporter: FixturePhotosExporter(urls: [clip])).export(plan: plan, to: staging)
            let receipt = try await transfer(staging: staging, destination: destination, hints: exported.sourceDateHints)
            let item = try XCTUnwrap(receipt.transfers.first)
            XCTAssertEqual(URL(fileURLWithPath: item.dest).deletingLastPathComponent().path, destination.appendingPathComponent(folder).path)
            XCTAssertEqual(try Data(contentsOf: clip), try Data(contentsOf: URL(fileURLWithPath: item.dest)))
        }
    }

    func testMissingMovieMetadataUsesFilenameBeforeAssetAndNeverStagingDates() async throws {
        let clip = root.appendingPathComponent("original.mov")
        try writeMovie(at: clip, date: "2026-02-30T00:00:00Z")
        let staging = root.appendingPathComponent("staging")
        let exported = try await PhotosExportExecutor(exporter: FixturePhotosExporter(urls: [clip])).export(plan: PhotosExportPlan(entries: [
            PhotosAssetExportEntry(assetID: "clip", mediaKind: .video, stagingStem: "VID_20240717_120000", creationDate: Date()),
        ]), to: staging)
        let result = try DryRunPlanner().plan(sourceRoot: staging, destinationRoot: root.appendingPathComponent("destination"), sourceDateHints: exported.sourceDateHints)
        XCTAssertEqual(result.previewReviewItems.first?.dateSource, .filename)
        XCTAssertTrue(try XCTUnwrap(result.copyJobs.first).destinationPath.contains("2024/07/17"))
    }

    func testPlanningRejectsChangedPreparedBytesEvenWhenSizeAndMtimeMatch() async throws {
        let staging = root.appendingPathComponent("staging")
        let clip = root.appendingPathComponent("source.mov")
        try Data("original".utf8).write(to: clip)
        let receipt = try await PhotosExportExecutor(exporter: FixturePhotosExporter(urls: [clip])).export(plan: PhotosExportPlan(entries: [
            PhotosAssetExportEntry(assetID: "clip", mediaKind: .video, stagingStem: "clip", creationDate: Date()),
        ]), to: staging)
        let destination = root.appendingPathComponent("destination")
        _ = try DryRunPlanner().plan(sourceRoot: staging, destinationRoot: destination, sourceDateHints: receipt.sourceDateHints)
        let path = try XCTUnwrap(receipt.exportedFiles.first?.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        try Data("replaced".utf8).write(to: URL(fileURLWithPath: path))
        try FileManager.default.setAttributes([.modificationDate: attributes[.modificationDate]!], ofItemAtPath: path)
        XCTAssertThrowsError(try DryRunPlanner().plan(sourceRoot: staging, destinationRoot: destination, sourceDateHints: receipt.sourceDateHints)) { error in
            XCTAssertTrue(error.localizedDescription.contains("prepare the import again"))
        }
    }

    func testUserDateOverrideStillWinsOverImportSnapshot() throws {
        let staging = root.appendingPathComponent("staging")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let file = staging.appendingPathComponent("photo.jpg")
        try Data("synthetic".utf8).write(to: file)
        let identity = try FileIdentityHasher().hashIdentity(at: file)
        let hint = SourceDateHint(identity: identity, resolvedDate: ResolvedMediaDate(
            date: ISO8601DateFormatter().date(from: "2026-08-01T12:00:00Z"), source: .photosAsset, confidence: .medium))
        let destination = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let database = try OrganizerDatabase(url: destination.appendingPathComponent(".organize_cache.db"))
        try database.saveReviewOverride(ReviewOverride(identity: identity, sourcePath: file.path,
            captureDate: ISO8601DateFormatter().date(from: "2024-07-17T00:00:00Z")))
        database.close()
        let result = try DryRunPlanner().plan(sourceRoot: staging, destinationRoot: destination,
            sourceDateHints: [SourceDateHint.pathKey(for: file.path): hint])
        XCTAssertEqual(result.previewReviewItems.first?.dateSource, .userOverride)
        XCTAssertTrue(try XCTUnwrap(result.copyJobs.first).destinationPath.contains("2024/07/17"))
    }

    func testInvalidAssetDateBecomesUnknownAndConfigurationSnapshotRoundTrips() async throws {
        let clip = root.appendingPathComponent("original.mov")
        try Data("no metadata".utf8).write(to: clip)
        let staging = root.appendingPathComponent("staging")
        let receipt = try await PhotosExportExecutor(exporter: FixturePhotosExporter(urls: [clip])).export(plan: PhotosExportPlan(entries: [
            PhotosAssetExportEntry(assetID: "clip", mediaKind: .video, stagingStem: "clip",
                creationDate: ISO8601DateFormatter().date(from: "1800-01-01T00:00:00Z")),
        ]), to: staging)
        XCTAssertEqual(receipt.sourceDateHints.values.first?.resolvedDate, .unknown)
        let configuration = RunConfiguration(mode: .preview, sourcePath: staging.path, sourceDateHints: receipt.sourceDateHints)
        XCTAssertEqual(try JSONDecoder().decode(RunConfiguration.self, from: JSONEncoder().encode(configuration)), configuration)
        let legacy = try JSONDecoder().decode(RunConfiguration.self, from: Data(#"{"mode":"preview"}"#.utf8))
        XCTAssertEqual(legacy.sourceDateHints, [:])
    }

    private func writeStill(at url: URL, date: String?, offset: String?) throws {
        let bytes = Data(repeating: 0xFF, count: 16 * 16 * 4)
        let image = try XCTUnwrap(CGImage(width: 16, height: 16, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: 64, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: CGDataProvider(data: bytes as CFData)!, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let output = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil))
        var exif: [CFString: Any] = [:]
        if let date { exif[kCGImagePropertyExifDateTimeOriginal] = date }
        if let offset { exif[kCGImagePropertyExifOffsetTimeOriginal] = offset }
        CGImageDestinationAddImage(output, image, [
            kCGImagePropertyExifDictionary: exif,
            kCGImagePropertyMakerAppleDictionary: ["17": "11111111-2222-3333-4444-555555555555"],
        ] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(output))
    }

    private func writeMovie(at url: URL, date: String?, identifier: String? = nil) throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        writer.metadata = [("com.apple.quicktime.creationdate", date), ("com.apple.quicktime.content.identifier", identifier)].compactMap { key, value in
            guard let value else { return nil }
            let item = AVMutableMetadataItem()
            item.keySpace = .quickTimeMetadata
            item.key = key as NSString
            item.value = value as NSString
            item.dataType = "com.apple.metadata.datatype.UTF-8"
            return item
        }
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 16, AVVideoHeightKey: 16,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 16, kCVPixelBufferHeightKey as String: 16,
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var buffer: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(kCFAllocatorDefault, 16, 16, kCVPixelFormatType_32BGRA, nil, &buffer), kCVReturnSuccess)
        let pixels = try XCTUnwrap(buffer)
        CVPixelBufferLockBaseAddress(pixels, [])
        memset(CVPixelBufferGetBaseAddress(pixels), 0, CVPixelBufferGetDataSize(pixels))
        CVPixelBufferUnlockBaseAddress(pixels, [])
        let deadline = Date().addingTimeInterval(2)
        while !input.isReadyForMoreMediaData && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        XCTAssertTrue(adaptor.append(pixels, withPresentationTime: .zero))
        input.markAsFinished()
        let done = XCTestExpectation(description: "Generated movie finished")
        writer.finishWriting { done.fulfill() }
        wait(for: [done], timeout: 5)
        XCTAssertEqual(writer.status, .completed)
    }
}

private struct FixturePhotosExporter: PhotosResourceExporting {
    let urls: [URL]
    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        urls.enumerated().map { index, url in
            PhotosExportableResource(assetID: id, resourceIndex: index, fileExtension: url.pathExtension, originalFilename: url.lastPathComponent)
        }
    }
    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        try FileManager.default.copyItem(at: urls[resource.resourceIndex], to: destinationURL)
    }
}

private final class FixtureProfiles: ProfilesRepositorying {
    let url: URL
    init(url: URL) { self.url = url }
    func profilesFileURL() -> URL { url }
    func loadProfiles() throws -> [Profile] { [] }
    func save(profile: Profile) throws {}
    func deleteProfile(named name: String) throws {}
}
