import AVFoundation
import CoreGraphics
import CoreVideo
import Foundation
import XCTest
@testable import ChronoframeCore

/// Milestone 2b-2 — AVFoundation frame extractor. Two layers of coverage:
///
/// 1. Pure decision helpers (`VideoFrameAnalysis`) tested directly and
///    deterministically — transformed-dimension math, low-variance discard,
///    status mapping, resample offsets.
/// 2. Behavior tests over tiny procedurally-generated clips (written with
///    `AVAssetWriter`) that assert *behavior* — status transitions, slot
///    alignment, rotation-aware dimensions, prompt cancellation — never
///    bit-for-bit dHash equality (decoder-dependent across machines).
final class VideoFeatureExtractorTests: XCTestCase {

    // MARK: - Pure helpers: transformed dimensions

    func testTransformedDimensionsIdentity() {
        let dims = VideoFrameAnalysis.transformedDimensions(
            naturalSize: CGSize(width: 1920, height: 1080),
            transform: .identity
        )
        XCTAssertEqual(dims.width, 1920)
        XCTAssertEqual(dims.height, 1080)
    }

    func testTransformedDimensionsNinetyDegreeRotationSwaps() {
        // A 90° rotation must swap width and height (portrait capture of a
        // landscape sensor) — the abs() handles the sign flip.
        let dims = VideoFrameAnalysis.transformedDimensions(
            naturalSize: CGSize(width: 1920, height: 1080),
            transform: CGAffineTransform(rotationAngle: .pi / 2)
        )
        XCTAssertEqual(dims.width, 1080)
        XCTAssertEqual(dims.height, 1920)
    }

    func testTransformedDimensionsOneEightyKeepsExtent() {
        let dims = VideoFrameAnalysis.transformedDimensions(
            naturalSize: CGSize(width: 640, height: 480),
            transform: CGAffineTransform(rotationAngle: .pi)
        )
        XCTAssertEqual(dims.width, 640)
        XCTAssertEqual(dims.height, 480)
    }

    func testTransformedDimensionsMirrorKeepsPositiveExtent() {
        let dims = VideoFrameAnalysis.transformedDimensions(
            naturalSize: CGSize(width: 800, height: 600),
            transform: CGAffineTransform(scaleX: -1, y: 1)
        )
        XCTAssertEqual(dims.width, 800)
        XCTAssertEqual(dims.height, 600)
    }

    // MARK: - Pure helpers: luma variance / low-variance discard

    func testUniformBufferHasZeroVariance() {
        let uniform = [UInt8](repeating: 17, count: 256)
        XCTAssertEqual(VideoFrameAnalysis.lumaVariance(uniform), 0, accuracy: 1e-9)
        XCTAssertTrue(VideoFrameAnalysis.isLowVariance(uniform, threshold: 12))
    }

    func testEmptyBufferIsTreatedAsLowVariance() {
        XCTAssertEqual(VideoFrameAnalysis.lumaVariance([]), 0, accuracy: 1e-9)
        XCTAssertTrue(VideoFrameAnalysis.isLowVariance([], threshold: 12))
    }

    func testHighContrastBufferExceedsThreshold() {
        // Half black, half white → large variance.
        var pixels = [UInt8](repeating: 0, count: 128)
        pixels += [UInt8](repeating: 255, count: 128)
        XCTAssertGreaterThan(VideoFrameAnalysis.lumaVariance(pixels), 12)
        XCTAssertFalse(VideoFrameAnalysis.isLowVariance(pixels, threshold: 12))
    }

    func testVarianceMatchesKnownTwoValueFormula() {
        // Two equal halves at a and b → variance = ((b-a)/2)^2.
        let pixels = [UInt8](repeating: 10, count: 50) + [UInt8](repeating: 30, count: 50)
        XCTAssertEqual(VideoFrameAnalysis.lumaVariance(pixels), 100, accuracy: 1e-6)
    }

    // MARK: - Pure helpers: status mapping

    func testStatusReadyWhenEnoughUsable() {
        XCTAssertEqual(VideoFrameAnalysis.status(usableSamples: 3, generatedSamples: 5), .ready)
        XCTAssertEqual(VideoFrameAnalysis.status(usableSamples: 5, generatedSamples: 5), .ready)
    }

    func testStatusDecodeFailedWhenNothingGenerated() {
        XCTAssertEqual(VideoFrameAnalysis.status(usableSamples: 0, generatedSamples: 0), .decodeFailed)
    }

    func testStatusInsufficientWhenGeneratedButFewUsable() {
        // Frames decoded but most were discarded as low-variance.
        XCTAssertEqual(VideoFrameAnalysis.status(usableSamples: 2, generatedSamples: 5), .insufficientVisualEvidence)
        XCTAssertEqual(VideoFrameAnalysis.status(usableSamples: 0, generatedSamples: 5), .insufficientVisualEvidence)
    }

    // MARK: - Pure helpers: resample offsets

    func testResampleOffsetsZeroAttemptsIsJustTheTarget() {
        XCTAssertEqual(VideoFrameAnalysis.resampleOffsets(attempts: 0, step: 0.025), [0])
    }

    func testResampleOffsetsAlternateAndGrow() {
        let offsets = VideoFrameAnalysis.resampleOffsets(attempts: 4, step: 0.02)
        // target, +step, -step, +2step, -2step
        XCTAssertEqual(offsets.count, 5)
        XCTAssertEqual(offsets[0], 0, accuracy: 1e-9)
        XCTAssertEqual(offsets[1], 0.02, accuracy: 1e-9)
        XCTAssertEqual(offsets[2], -0.02, accuracy: 1e-9)
        XCTAssertEqual(offsets[3], 0.04, accuracy: 1e-9)
        XCTAssertEqual(offsets[4], -0.04, accuracy: 1e-9)
    }

    // MARK: - Cancellation (deterministic, no timing)

    func testImmediateCancellationShortCircuitsBeforeDecode() {
        let extractor = AVFoundationVideoFeatureExtractor()
        let features = extractor.extractFeatures(
            path: "/nonexistent/never-read.mov",
            size: 0,
            modificationTime: 0,
            folderRoot: nil,
            isCancelled: { true }
        )
        // The top-of-function guard returns before AVFoundation is ever touched.
        XCTAssertEqual(features.status, .decodeFailed)
        XCTAssertEqual(features.path, "/nonexistent/never-read.mov")
        XCTAssertTrue(features.frameHashes.allSatisfy { $0 == nil })
    }

    func testCancellationDuringSlotLoopStopsGeneration() throws {
        let url = try makeTempURL(ext: "mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeClip(to: url, luma: { x, y, frame in UInt8((x + y + frame * 7) & 0xFF) })

        // Returns false for the first two polls (top guard + registry check) so
        // the extractor registers its generator and enters the slot loop, then
        // true forever — the loop's per-slot guard must abort before producing
        // a full set of frames.
        let flag = PollCountingFlag(falseCallsBeforeCancel: 2)
        let extractor = AVFoundationVideoFeatureExtractor()
        let features = extractor.extractFeatures(
            path: url.path,
            size: 1,
            modificationTime: 1,
            folderRoot: nil,
            isCancelled: { flag.poll() }
        )
        XCTAssertNotEqual(features.status, .ready, "cancelled mid-run must not report ready")
        XCTAssertTrue(features.frameHashes.allSatisfy { $0 == nil })
    }

    // MARK: - Behavior over generated clips

    func testNormalClipDecodesToReadyWithAlignedSlots() throws {
        let url = try makeTempURL(ext: "mov")
        defer { try? FileManager.default.removeItem(at: url) }
        // Spatial gradient that shifts each frame → every sampled frame is
        // high-variance and informative.
        try writeClip(to: url, luma: { x, y, frame in UInt8((x * 2 + y + frame * 5) & 0xFF) })

        let extractor = AVFoundationVideoFeatureExtractor()
        let features = extractor.extractFeatures(
            path: url.path, size: 123, modificationTime: 456, folderRoot: "/lib",
            isCancelled: { false }
        )
        XCTAssertEqual(features.status, .ready)
        XCTAssertEqual(features.frameHashes.count, VideoPerceptualAnalysis.sampleFractions.count)
        XCTAssertGreaterThanOrEqual(features.usableSampleCount, VideoPerceptualAnalysis.minimumUsableSamples)
        // Supplied identity is carried through verbatim for the cache layer.
        XCTAssertEqual(features.size, 123)
        XCTAssertEqual(features.modificationTime, 456)
        XCTAssertEqual(features.folderRoot, "/lib")
        XCTAssertGreaterThan(features.durationSeconds, 0)
        XCTAssertGreaterThan(features.transformedWidth, 0)
        XCTAssertGreaterThan(features.transformedHeight, 0)
    }

    func testSolidBlackClipIsInsufficientVisualEvidence() throws {
        let url = try makeTempURL(ext: "mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try writeClip(to: url, luma: { _, _, _ in 0 })

        let extractor = AVFoundationVideoFeatureExtractor()
        let features = extractor.extractFeatures(
            path: url.path, size: 1, modificationTime: 1, folderRoot: nil,
            isCancelled: { false }
        )
        // Frames decode fine but every one is near-uniform → discarded.
        XCTAssertEqual(features.status, .insufficientVisualEvidence)
        XCTAssertTrue(features.frameHashes.allSatisfy { $0 == nil })
    }

    func testRotatedClipReportsSwappedDimensions() throws {
        let url = try makeTempURL(ext: "mov")
        defer { try? FileManager.default.removeItem(at: url) }
        // Landscape 160×120 source with a 90° track transform → the extractor
        // should report portrait (120×160) display dimensions.
        try writeClip(
            to: url,
            width: 160,
            height: 120,
            transform: CGAffineTransform(rotationAngle: .pi / 2),
            luma: { x, y, frame in UInt8((x + y * 2 + frame * 3) & 0xFF) }
        )

        let extractor = AVFoundationVideoFeatureExtractor()
        let features = extractor.extractFeatures(
            path: url.path, size: 1, modificationTime: 1, folderRoot: nil,
            isCancelled: { false }
        )
        XCTAssertEqual(features.transformedWidth, 120)
        XCTAssertEqual(features.transformedHeight, 160)
    }

    func testUnsupportedContainerReportsUnsupported() throws {
        // A file with a video extension that is not actually a decodable movie.
        let url = try makeTempURL(ext: "mov")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a real movie".utf8).write(to: url)

        let extractor = AVFoundationVideoFeatureExtractor()
        let features = extractor.extractFeatures(
            path: url.path, size: 16, modificationTime: 1, folderRoot: nil,
            isCancelled: { false }
        )
        XCTAssertEqual(features.status, .unsupported)
        XCTAssertEqual(features.size, 16)
    }

    // MARK: - Helpers

    private func makeTempURL(ext: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("VideoExtractor-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("clip.\(ext)")
    }

    /// Write a tiny H.264 clip whose per-pixel luma is `luma(x, y, frame)`,
    /// replicated across RGB. Throws `XCTSkip` if this machine can't run the
    /// video writer (so the suite stays green on encoder-less environments).
    private func writeClip(
        to url: URL,
        frameCount: Int = 24,
        fps: Int32 = 8,
        width: Int = 160,
        height: Int = 160,
        transform: CGAffineTransform = .identity,
        luma: @escaping (_ x: Int, _ y: Int, _ frame: Int) -> UInt8
    ) throws {
        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        } catch {
            throw XCTSkip("AVAssetWriter unavailable: \(error.localizedDescription)")
        }

        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = false
        input.transform = transform
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ]
        )
        guard writer.canAdd(input) else { throw XCTSkip("writer can't add video input") }
        writer.add(input)
        guard writer.startWriting() else {
            throw XCTSkip("writer.startWriting failed: \(writer.error?.localizedDescription ?? "unknown")")
        }
        writer.startSession(atSourceTime: .zero)

        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { usleep(500) }
            guard let pool = adaptor.pixelBufferPool else { throw XCTSkip("no pixel buffer pool") }
            var pixelBufferOut: CVPixelBuffer?
            CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferOut)
            guard let pixelBuffer = pixelBufferOut else { throw XCTSkip("no pixel buffer") }
            fill(pixelBuffer, width: width, height: height, frame: frame, luma: luma)
            let time = CMTime(value: CMTimeValue(frame), timescale: fps)
            adaptor.append(pixelBuffer, withPresentationTime: time)
        }

        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()
        guard writer.status == .completed else {
            throw XCTSkip("writer finished with status \(writer.status.rawValue): \(writer.error?.localizedDescription ?? "unknown")")
        }
    }

    private func fill(
        _ pixelBuffer: CVPixelBuffer,
        width: Int,
        height: Int,
        frame: Int,
        luma: (_ x: Int, _ y: Int, _ frame: Int) -> UInt8
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let buffer = base.assumingMemoryBound(to: UInt8.self)
        for y in 0..<height {
            let rowStart = y * bytesPerRow
            for x in 0..<width {
                let value = luma(x, y, frame)
                let pixel = rowStart + x * 4 // BGRA
                buffer[pixel + 0] = value // B
                buffer[pixel + 1] = value // G
                buffer[pixel + 2] = value // R
                buffer[pixel + 3] = 255   // A
            }
        }
    }
}

/// A `@Sendable`-safe cancellation flag that reads `false` for the first
/// `falseCallsBeforeCancel` polls and `true` afterwards, so a test can let the
/// extractor enter its slot loop before cancellation fires — deterministic,
/// no sleeping.
private final class PollCountingFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var polls = 0
    private let falseCallsBeforeCancel: Int

    init(falseCallsBeforeCancel: Int) {
        self.falseCallsBeforeCancel = falseCallsBeforeCancel
    }

    func poll() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        polls += 1
        return polls > falseCallsBeforeCancel
    }
}
