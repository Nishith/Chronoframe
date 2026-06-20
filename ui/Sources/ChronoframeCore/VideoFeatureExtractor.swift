import AVFoundation
import CoreGraphics
import Foundation

// MARK: - Extraction configuration

/// Tuning for the AVFoundation frame extractor. Deliberately separate from
/// `VideoPerceptualMatchConfiguration` (which only governs how two already-
/// extracted feature vectors are *compared*) so the decode-side knobs —
/// memory cap, low-variance discard, bounded resample — can be calibrated
/// independently in Milestone 2c without touching the pure matcher.
public struct VideoFeatureExtractionConfiguration: Sendable, Equatable {
    /// Hard cap on the decode target's longest edge, in pixels. The image
    /// generator never holds a frame larger than this, so a 4K/ProRes source
    /// is downscaled inside the decoder rather than after — this is the memory
    /// bound. 64 keeps each frame at ~4 KB.
    public var maximumDecodeDimension: Int
    /// Grayscale luma variance below which a sampled frame is treated as
    /// near-uniform (black, fade, solid title card) and discarded — its slot
    /// becomes `nil`. Calibrated against a labeled corpus in Milestone 2c.
    public var lowVarianceThreshold: Double
    /// When a sample fails to decode or is discarded as low-variance, retry at
    /// a small ± offset of this fraction of duration. Bounded so the sampler
    /// stays near its intended fraction and never drifts toward partial-clip
    /// matching (explicitly out of scope).
    public var resampleOffsetFraction: Double
    /// Maximum number of bounded resample attempts per slot after the first.
    public var maxResampleAttempts: Int
    /// Square edge (pixels) of the tiny grayscale buffer used for the
    /// low-variance check. Independent of the dHash grid.
    public var varianceProbeDimension: Int

    public init(
        maximumDecodeDimension: Int = 64,
        lowVarianceThreshold: Double = 12.0,
        resampleOffsetFraction: Double = 0.025,
        maxResampleAttempts: Int = 2,
        varianceProbeDimension: Int = 16
    ) {
        self.maximumDecodeDimension = maximumDecodeDimension
        self.lowVarianceThreshold = lowVarianceThreshold
        self.resampleOffsetFraction = resampleOffsetFraction
        self.maxResampleAttempts = maxResampleAttempts
        self.varianceProbeDimension = varianceProbeDimension
    }
}

// MARK: - Provider seam

/// The decode seam. The scanner depends only on this protocol so it can be
/// unit-tested with a fake that returns canned `VideoPerceptualFeatures`
/// without ever decoding a real file. `AVFoundationVideoFeatureExtractor` is
/// the production conformer.
public protocol VideoFeatureProviding: Sendable {
    /// Read only the cheap comparison metadata needed to decide whether this
    /// video has a plausible neighbor. This must not decode sample frames.
    func probeMetadata(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        folderRoot: String?,
        isCancelled: @Sendable () -> Bool
    ) -> VideoMetadataProbe

    /// Extract perceptual features for one video. Must honor `isCancelled()`
    /// promptly and return the appropriate `VideoDecodeStatus` on any failure
    /// path (never throw). The returned features carry the supplied
    /// `size`/`modificationTime` verbatim so the cache layer can validate them.
    func extractFeatures(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        folderRoot: String?,
        isCancelled: @Sendable () -> Bool
    ) -> VideoPerceptualFeatures

    /// Extract using an already-loaded metadata probe. Test doubles may rely on
    /// the default implementation; the AVFoundation provider avoids reloading
    /// track metadata.
    func extractFeatures(
        metadata: VideoMetadataProbe,
        isCancelled: @Sendable () -> Bool
    ) -> VideoPerceptualFeatures

    /// Cancel all in-flight generation immediately.
    func cancelAll()
}

public extension VideoFeatureProviding {
    func extractFeatures(
        metadata: VideoMetadataProbe,
        isCancelled: @Sendable () -> Bool
    ) -> VideoPerceptualFeatures {
        extractFeatures(
            path: metadata.path,
            size: metadata.size,
            modificationTime: metadata.modificationTime,
            folderRoot: metadata.folderRoot,
            isCancelled: isCancelled
        )
    }
}

/// Cheap, frame-free metadata used by the cold-scan candidate index.
public struct VideoMetadataProbe: Sendable, Equatable {
    public var path: String
    public var size: Int64
    public var modificationTime: TimeInterval
    public var durationSeconds: Double
    public var transformedWidth: Int
    public var transformedHeight: Int
    public var estimatedDataRate: Double
    public var metadataCompleteness: Int
    public var folderRoot: String?
    public var status: VideoDecodeStatus

    public init(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        durationSeconds: Double,
        transformedWidth: Int,
        transformedHeight: Int,
        estimatedDataRate: Double = 0,
        metadataCompleteness: Int = 0,
        folderRoot: String? = nil,
        status: VideoDecodeStatus = .ready
    ) {
        self.path = path
        self.size = size
        self.modificationTime = modificationTime
        self.durationSeconds = durationSeconds
        self.transformedWidth = transformedWidth
        self.transformedHeight = transformedHeight
        self.estimatedDataRate = estimatedDataRate
        self.metadataCompleteness = metadataCompleteness
        self.folderRoot = folderRoot
        self.status = status
    }

    public var aspectRatio: Double {
        guard transformedHeight > 0 else { return 0 }
        return Double(transformedWidth) / Double(transformedHeight)
    }
}

// MARK: - Pure decision helpers

/// Deterministic, decode-free helpers split out so they can be unit-tested
/// without AVFoundation. Everything here is a pure function of its inputs.
public enum VideoFrameAnalysis {
    /// Display dimensions after applying the track's `preferredTransform`. A
    /// rotation swaps width and height; the absolute value handles the sign
    /// flips a rotation/mirror introduces. Matches what
    /// `appliesPreferredTrackTransform` produces at decode time so a
    /// rotation-flagged copy and a baked-in-rotation copy report equal dims.
    public static func transformedDimensions(
        naturalSize: CGSize,
        transform: CGAffineTransform
    ) -> (width: Int, height: Int) {
        let rect = CGRect(origin: .zero, size: naturalSize).applying(transform)
        return (Int(abs(rect.width).rounded()), Int(abs(rect.height).rounded()))
    }

    /// Population variance of an 8-bit grayscale buffer. 0 for a uniform frame.
    public static func lumaVariance(_ pixels: [UInt8]) -> Double {
        guard !pixels.isEmpty else { return 0 }
        var sum = 0.0
        for value in pixels { sum += Double(value) }
        let mean = sum / Double(pixels.count)
        var squared = 0.0
        for value in pixels {
            let delta = Double(value) - mean
            squared += delta * delta
        }
        return squared / Double(pixels.count)
    }

    /// Whether a sampled frame is too near-uniform to carry useful signal.
    public static func isLowVariance(_ pixels: [UInt8], threshold: Double) -> Bool {
        lumaVariance(pixels) < threshold
    }

    /// Map raw per-slot outcomes onto the four-state decode status.
    /// - `usableSamples`: slots that yielded an informative (non-discarded) hash.
    /// - `generatedSamples`: slots where the decoder produced *any* frame,
    ///   regardless of whether it was later discarded as low-variance.
    ///
    /// `ready` requires enough usable frames. Otherwise: if the decoder never
    /// produced a single frame the file is effectively undecodable
    /// (`decodeFailed`); if it produced frames but too few survived the
    /// low-variance discard, the file decoded fine but lacks visual evidence
    /// (`insufficientVisualEvidence`). Both non-ready outcomes are cached so the
    /// expensive decode is not retried every scan.
    public static func status(
        usableSamples: Int,
        generatedSamples: Int,
        durationSeconds: Double? = nil
    ) -> VideoDecodeStatus {
        let minimum = durationSeconds.map { VideoPerceptualAnalysis.minimumUsableSamples(forDuration: $0) }
            ?? VideoPerceptualAnalysis.minimumUsableSamples
        if usableSamples >= minimum {
            return .ready
        }
        return generatedSamples == 0 ? .decodeFailed : .insufficientVisualEvidence
    }

    /// Bounded resample offsets (as fractions of duration) to try for one slot:
    /// the intended fraction first (offset 0), then alternating ± steps. Pure so
    /// the cancellation/resample loop can be reasoned about without decoding.
    public static func resampleOffsets(
        attempts: Int,
        step: Double
    ) -> [Double] {
        var offsets: [Double] = [0]
        var magnitude = step
        var index = 0
        while index < attempts {
            // Alternate +, − around the target so a single bad neighbor (a
            // cut, a flash) is escaped symmetrically.
            offsets.append(index % 2 == 0 ? magnitude : -magnitude)
            if index % 2 == 1 { magnitude += step }
            index += 1
        }
        return offsets
    }
}

// MARK: - AVFoundation implementation

/// Production `VideoFeatureProviding`. Turns a file on disk into a
/// `VideoPerceptualFeatures` by sampling a handful of frames via
/// `AVAssetImageGenerator`, hashing each with the shared `PerceptualHash.dhash`
/// (parity with photos), and aligning the results to
/// `VideoPerceptualAnalysis.sampleFractions`. Decodes as little as possible
/// (tolerances wide open, decode size capped) and cancels instantly.
public final class AVFoundationVideoFeatureExtractor: VideoFeatureProviding, @unchecked Sendable {
    private let configuration: VideoFeatureExtractionConfiguration
    private let registry = GeneratorRegistry()

    public init(configuration: VideoFeatureExtractionConfiguration = VideoFeatureExtractionConfiguration()) {
        self.configuration = configuration
    }

    public func cancelAll() {
        registry.cancelAll()
    }

    public func probeMetadata(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        folderRoot: String?,
        isCancelled: @Sendable () -> Bool
    ) -> VideoMetadataProbe {
        guard !isCancelled() else {
            return VideoMetadataProbe(
                path: path,
                size: size,
                modificationTime: modificationTime,
                durationSeconds: 0,
                transformedWidth: 0,
                transformedHeight: 0,
                folderRoot: folderRoot,
                status: .decodeFailed
            )
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        guard let metadata = Self.loadTrackMetadata(asset: asset),
              metadata.duration.isFinite, metadata.duration > 0 else {
            return VideoMetadataProbe(
                path: path,
                size: size,
                modificationTime: modificationTime,
                durationSeconds: 0,
                transformedWidth: 0,
                transformedHeight: 0,
                folderRoot: folderRoot,
                status: .unsupported
            )
        }
        let dimensions = VideoFrameAnalysis.transformedDimensions(
            naturalSize: metadata.naturalSize,
            transform: metadata.transform
        )
        var completeness = 1 // duration
        if dimensions.width > 0, dimensions.height > 0 { completeness += 1 }
        if metadata.estimatedDataRate > 0 { completeness += 1 }
        return VideoMetadataProbe(
            path: path,
            size: size,
            modificationTime: modificationTime,
            durationSeconds: metadata.duration,
            transformedWidth: dimensions.width,
            transformedHeight: dimensions.height,
            estimatedDataRate: metadata.estimatedDataRate,
            metadataCompleteness: completeness,
            folderRoot: folderRoot,
            status: .ready
        )
    }

    public func extractFeatures(
        path: String,
        size: Int64,
        modificationTime: TimeInterval,
        folderRoot: String?,
        isCancelled: @Sendable () -> Bool
    ) -> VideoPerceptualFeatures {
        let metadata = probeMetadata(
            path: path,
            size: size,
            modificationTime: modificationTime,
            folderRoot: folderRoot,
            isCancelled: isCancelled
        )
        return extractFeatures(metadata: metadata, isCancelled: isCancelled)
    }

    public func extractFeatures(
        metadata: VideoMetadataProbe,
        isCancelled: @Sendable () -> Bool
    ) -> VideoPerceptualFeatures {
        let path = metadata.path
        let size = metadata.size
        let modificationTime = metadata.modificationTime
        let folderRoot = metadata.folderRoot
        let slotCount = VideoPerceptualAnalysis.sampleFractions.count

        func makeFeatures(
            status: VideoDecodeStatus,
            duration: Double = 0,
            width: Int = 0,
            height: Int = 0,
            frameHashes: [UInt64?] = Array(repeating: nil, count: VideoPerceptualAnalysis.sampleFractions.count)
        ) -> VideoPerceptualFeatures {
            VideoPerceptualFeatures(
                path: path,
                size: size,
                modificationTime: modificationTime,
                durationSeconds: duration,
                transformedWidth: width,
                transformedHeight: height,
                estimatedDataRate: metadata.estimatedDataRate,
                metadataCompleteness: metadata.metadataCompleteness,
                frameHashes: frameHashes,
                status: status,
                folderRoot: folderRoot
            )
        }

        if isCancelled() { return makeFeatures(status: .decodeFailed) }

        guard metadata.status == .ready else {
            return makeFeatures(status: metadata.status)
        }
        let asset = AVURLAsset(url: URL(fileURLWithPath: path))
        let duration = metadata.durationSeconds
        let width = metadata.transformedWidth
        let height = metadata.transformedHeight

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        // We want *a* nearby frame, not an exact PTS — far cheaper to decode.
        generator.requestedTimeToleranceBefore = .positiveInfinity
        generator.requestedTimeToleranceAfter = .positiveInfinity
        // Memory cap: decode straight to a tiny target, never hold a full frame.
        let edge = CGFloat(configuration.maximumDecodeDimension)
        generator.maximumSize = CGSize(width: edge, height: edge)

        // Register under the lock; if a cancel already fired, abort before
        // generating a single frame (closes the register-after-cancel race).
        guard registry.register(generator, isCancelled: isCancelled) else {
            return makeFeatures(status: .decodeFailed, duration: duration, width: width, height: height)
        }
        defer { registry.unregister(generator) }

        var slots: [UInt64?] = Array(repeating: nil, count: slotCount)
        var generatedSamples = 0
        let offsets = VideoFrameAnalysis.resampleOffsets(
            attempts: configuration.maxResampleAttempts,
            step: configuration.resampleOffsetFraction
        )

        for (index, fraction) in VideoPerceptualAnalysis.sampleFractions.enumerated() {
            if isCancelled() {
                return makeFeatures(status: .decodeFailed, duration: duration, width: width, height: height)
            }
            let outcome = sampleSlot(
                generator: generator,
                duration: duration,
                fraction: fraction,
                offsets: offsets,
                isCancelled: isCancelled
            )
            if outcome.didGenerate { generatedSamples += 1 }
            slots[index] = outcome.hash
        }

        let usable = slots.reduce(0) { $0 + ($1 == nil ? 0 : 1) }
        let status = VideoFrameAnalysis.status(
            usableSamples: usable,
            generatedSamples: generatedSamples,
            durationSeconds: duration
        )
        return makeFeatures(
            status: status,
            duration: duration,
            width: width,
            height: height,
            frameHashes: slots
        )
    }

    // MARK: - Per-slot sampling

    private struct SlotOutcome {
        var hash: UInt64?
        /// Whether the decoder produced *any* frame for this slot, even one
        /// later discarded as low-variance. Feeds the decodeFailed vs.
        /// insufficientVisualEvidence distinction.
        var didGenerate: Bool
    }

    private func sampleSlot(
        generator: AVAssetImageGenerator,
        duration: Double,
        fraction: Double,
        offsets: [Double],
        isCancelled: @Sendable () -> Bool
    ) -> SlotOutcome {
        var didGenerate = false
        for offset in offsets {
            if isCancelled() { return SlotOutcome(hash: nil, didGenerate: didGenerate) }
            let target = min(max((fraction + offset) * duration, 0), duration)
            let time = CMTime(seconds: target, preferredTimescale: 600)

            guard let image = try? generator.copyCGImage(at: time, actualTime: nil) else {
                continue // decode failed at this offset; try the next bounded neighbor
            }
            didGenerate = true

            // Low-variance discard: probe a tiny grayscale render. A near-
            // uniform frame (black, fade, solid card) carries no signal, so try
            // a bounded neighbor instead of poisoning the slot.
            if let probe = Self.grayscaleBuffer(from: image, dimension: configuration.varianceProbeDimension),
               VideoFrameAnalysis.isLowVariance(probe, threshold: configuration.lowVarianceThreshold) {
                continue
            }

            if let hash = PerceptualHash.dhash(from: image) {
                return SlotOutcome(hash: hash, didGenerate: true)
            }
            // dHash render failed despite a decoded frame — treat as a decode
            // hiccup for this offset and try the next neighbor.
        }
        return SlotOutcome(hash: nil, didGenerate: didGenerate)
    }

    /// Render a CGImage into a small square 8-bit grayscale buffer for the
    /// low-variance probe. Mirrors `PerceptualHash`'s drawing approach.
    static func grayscaleBuffer(from cgImage: CGImage, dimension: Int) -> [UInt8]? {
        let side = max(1, dimension)
        var pixels = [UInt8](repeating: 0, count: side * side)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return nil
        }
        context.interpolationQuality = .low
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))
        return pixels
    }

    /// Load duration + first-video-track geometry using the modern async
    /// AVFoundation API, bridged to this synchronous decode path with a
    /// semaphore (the extractor runs off the main thread on a worker queue, the
    /// same pattern `DeduplicatePairDetector` uses). Returns `nil` on any
    /// failure — the caller maps that to `.unsupported`.
    private static func loadTrackMetadata(asset: AVURLAsset) -> TrackMetadata? {
        let box = LoadedTrackMetadataBox()
        let semaphore = DispatchSemaphore(value: 0)
        Task.detached {
            defer { semaphore.signal() }
            do {
                guard let track = try await asset.loadTracks(withMediaType: .video).first else { return }
                let duration = try await asset.load(.duration)
                let naturalSize = try await track.load(.naturalSize)
                let transform = try await track.load(.preferredTransform)
                let estimatedDataRate = (try? await track.load(.estimatedDataRate)) ?? 0
                box.value = TrackMetadata(
                    duration: CMTimeGetSeconds(duration),
                    naturalSize: naturalSize,
                    transform: transform,
                    estimatedDataRate: Double(estimatedDataRate)
                )
            } catch {
                // Leave box.value nil → caller treats as unsupported.
            }
        }
        semaphore.wait()
        return box.value
    }

    private struct TrackMetadata {
        var duration: Double
        var naturalSize: CGSize
        var transform: CGAffineTransform
        var estimatedDataRate: Double
    }

    private final class LoadedTrackMetadataBox: @unchecked Sendable {
        var value: TrackMetadata?
    }
}

// MARK: - Generator registry (cancellation)

/// Tracks active image generators so `cancelAll()` can stop every in-flight
/// decode immediately. The `cancelled` flag closes the register-after-cancel
/// race: a generator created *after* `cancelAll` iterated would otherwise run
/// uncancelled. `register` resets the flag on the first call of a fresh scan
/// (detected via the scan's `isCancelled()` reading false) so a single reused
/// extractor instance survives a cancel-then-rescan.
private final class GeneratorRegistry: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    private var active: [ObjectIdentifier: AVAssetImageGenerator] = [:]

    func cancelAll() {
        lock.lock()
        cancelled = true
        let generators = Array(active.values)
        lock.unlock()
        // Cancel outside the lock — cancellation can call back synchronously.
        for generator in generators {
            generator.cancelAllCGImageGeneration()
        }
    }

    /// Register a generator. Returns `false` (and cancels the generator) when a
    /// cancel is in effect, signalling the caller to abort before generating.
    func register(_ generator: AVAssetImageGenerator, isCancelled: () -> Bool) -> Bool {
        lock.lock()
        // A fresh scan (external flag reading false) clears a stale cancel left
        // over from a prior cancelled scan on this reused instance.
        if cancelled && !isCancelled() {
            cancelled = false
        }
        if cancelled {
            lock.unlock()
            generator.cancelAllCGImageGeneration()
            return false
        }
        active[ObjectIdentifier(generator)] = generator
        lock.unlock()
        return true
    }

    func unregister(_ generator: AVAssetImageGenerator) {
        lock.lock()
        active[ObjectIdentifier(generator)] = nil
        lock.unlock()
    }
}
