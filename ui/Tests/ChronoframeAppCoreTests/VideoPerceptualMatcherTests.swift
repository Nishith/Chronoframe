import Foundation
import XCTest
@testable import ChronoframeCore

/// Milestone 2a — pure perceptual video matching. These tests are fully
/// deterministic: they synthesize frame-hash sequences directly, so there is no
/// AVFoundation decoding and no machine/decoder-dependent flakiness (per the M2
/// plan, bit-for-bit dHash equality is only asserted over synthesized frames).
final class VideoPerceptualMatcherTests: XCTestCase {

    private let config = VideoPerceptualMatchConfiguration()

    // MARK: - Helpers

    private func feature(
        _ path: String,
        duration: Double,
        frames: [UInt64?],
        width: Int = 1920,
        height: Int = 1080,
        folderRoot: String? = nil,
        status: VideoDecodeStatus = .ready
    ) -> VideoPerceptualFeatures {
        VideoPerceptualFeatures(
            path: path,
            size: 1_000,
            modificationTime: 0,
            durationSeconds: duration,
            transformedWidth: width,
            transformedHeight: height,
            frameHashes: frames,
            status: status,
            folderRoot: folderRoot
        )
    }

    /// Five identical, high-information frame hashes (one slot per sample fraction).
    private let framesA: [UInt64?] = [0x0F0F_0F0F, 0x1234_5678, 0xABCD_EF01, 0x7777_1111, 0x9999_AAAA]
    /// Five totally different frame hashes (a different clip).
    private let framesB: [UInt64?] = [0xFFFF_FFFF, 0x0000_0000, 0x5555_5555, 0xAAAA_AAAA, 0xF0F0_F0F0]

    // MARK: - medianOf

    func testMedianOdd() { XCTAssertEqual(VideoPerceptualMatcher.medianOf([1, 9, 3]), 3) }
    func testMedianEven() { XCTAssertEqual(VideoPerceptualMatcher.medianOf([2, 4, 6, 8]), 5) }
    func testMedianEmpty() { XCTAssertEqual(VideoPerceptualMatcher.medianOf([]), 0) }

    // MARK: - compareFrames

    func testCompareIdenticalFramesIsMatch() {
        let result = VideoPerceptualMatcher.compareFrames(framesA, framesA, configuration: config)
        XCTAssertEqual(result?.usableSamples, 5)
        XCTAssertEqual(result?.agreeingSamples, 5)
        XCTAssertEqual(result?.medianHammingDistance, 0)
        XCTAssertEqual(result?.isMatch, true)
    }

    func testCompareDifferentFramesIsNotMatch() {
        let result = VideoPerceptualMatcher.compareFrames(framesA, framesB, configuration: config)
        XCTAssertEqual(result?.isMatch, false)
    }

    func testCompareReturnsNilBelowMinimumSamples() {
        let twoSlots: [UInt64?] = [1, 2]
        XCTAssertNil(VideoPerceptualMatcher.compareFrames(twoSlots, twoSlots, configuration: config))
    }

    func testCompareToleratesSingleOutlierFrame() {
        // One frame differs wildly, the other four are identical → still a match
        // (rule requires max(3, N-1) = 4 of 5 to agree).
        var oneOff = framesA
        oneOff[2] = ~(framesA[2]!) // flip every bit of one frame
        let result = VideoPerceptualMatcher.compareFrames(framesA, oneOff, configuration: config)
        XCTAssertEqual(result?.agreeingSamples, 4)
        XCTAssertEqual(result?.isMatch, true)
    }

    func testFirstSampleOutlierIsStillTolerated() {
        // Codex P2: the outlier-tolerance must not depend on the sample position.
        // A fade/overlay/timestamp at the 15% (first) sample must not reject a
        // pair whose other four samples match.
        var firstOff = framesA
        firstOff[0] = ~(framesA[0]!)
        let result = VideoPerceptualMatcher.compareFrames(framesA, firstOff, configuration: config)
        XCTAssertEqual(result?.agreeingSamples, 4)
        XCTAssertEqual(result?.isMatch, true)
    }

    func testDiscardedSlotsAlignByFractionNotArrayIndex() {
        // Codex P2: two identical clips that discarded *different* low-variance
        // frames (A dropped the 15% sample, B dropped the 85% sample) still
        // align on the three shared fractions and match — comparing by raw array
        // index would have mis-shifted them.
        var a = framesA; a[0] = nil
        var b = framesA; b[4] = nil
        let result = VideoPerceptualMatcher.compareFrames(a, b, configuration: config)
        XCTAssertEqual(result?.usableSamples, 3)
        XCTAssertEqual(result?.isMatch, true)
    }

    func testInsufficientFractionOverlapReturnsNil() {
        // Overlap on a single shared fraction → undecidable.
        var a = framesA; a[0] = nil; a[1] = nil   // keeps slots 2,3,4
        var b = framesA; b[3] = nil; b[4] = nil   // keeps slots 0,1,2
        XCTAssertNil(VideoPerceptualMatcher.compareFrames(a, b, configuration: config))
    }

    // MARK: - aspect compatibility

    func testAspectCompatibleAllowsResolutionDifference() {
        let uhd = feature("/a", duration: 10, frames: framesA, width: 3840, height: 2160)
        let hd = feature("/b", duration: 10, frames: framesA, width: 1920, height: 1080)
        XCTAssertTrue(VideoPerceptualMatcher.aspectCompatible(uhd, hd, tolerance: 0.10))
    }

    func testAspectIncompatibleRejectsOrientationFlip() {
        let landscape = feature("/a", duration: 10, frames: framesA, width: 1920, height: 1080)
        let portrait = feature("/b", duration: 10, frames: framesA, width: 1080, height: 1920)
        XCTAssertFalse(VideoPerceptualMatcher.aspectCompatible(landscape, portrait, tolerance: 0.10))
    }

    // MARK: - cluster

    func testIdenticalVideosWithinToleranceFormOneCluster() {
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/a.mp4", duration: 10.0, frames: framesA),
                feature("/lib/b.mp4", duration: 10.4, frames: framesA),
            ],
            configuration: config
        )
        XCTAssertEqual(clusters.count, 1)
        let cluster = try? XCTUnwrap(clusters.first)
        XCTAssertEqual(cluster?.kind, .nearDuplicate)
        XCTAssertEqual(cluster?.members.count, 2)
        XCTAssertTrue(cluster?.members.allSatisfy { $0.mediaKind == .video } ?? false)
        // Always review-only.
        XCTAssertEqual(cluster?.annotation?.confidence, .medium)
        // Evidence is populated and honest.
        let evidence = cluster?.annotation?.videoEvidence
        XCTAssertEqual(evidence?.agreeingSamples, 5)
        XCTAssertEqual(evidence?.medianHammingDistance, 0)
        XCTAssertEqual(evidence?.durationDeltaSeconds ?? 0, 0.4, accuracy: 0.0001)
    }

    func testDurationOutsideToleranceDoesNotCluster() {
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/a.mp4", duration: 10.0, frames: framesA),
                feature("/lib/b.mp4", duration: 12.0, frames: framesA), // 2.0s apart, T=1.0
            ],
            configuration: config
        )
        XCTAssertTrue(clusters.isEmpty)
    }

    func testBoundaryStraddlingDurationsStillCluster() {
        // The discrete-bucket bug this guards against: 14.98 and 15.02 would land
        // in different buckets but are 0.04s apart, well within ±T.
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/a.mp4", duration: 14.98, frames: framesA),
                feature("/lib/b.mp4", duration: 15.02, frames: framesA),
            ],
            configuration: config
        )
        XCTAssertEqual(clusters.count, 1)
    }

    func testTransitiveClusteringAcrossSlidingWindow() {
        // 10.0—10.8—11.5: ends are 1.5s apart (no direct compare at T=1.0) but
        // the middle bridges them into one component.
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/a.mp4", duration: 10.0, frames: framesA),
                feature("/lib/b.mp4", duration: 10.8, frames: framesA),
                feature("/lib/c.mp4", duration: 11.5, frames: framesA),
            ],
            configuration: config
        )
        XCTAssertEqual(clusters.count, 1)
        XCTAssertEqual(clusters.first?.members.count, 3)
    }

    func testDifferentAspectDoesNotCluster() {
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/land.mp4", duration: 10.0, frames: framesA, width: 1920, height: 1080),
                feature("/lib/port.mp4", duration: 10.0, frames: framesA, width: 1080, height: 1920),
            ],
            configuration: config
        )
        XCTAssertTrue(clusters.isEmpty)
    }

    func testResizedCopyClustersAndKeepsHigherResolution() {
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/hd.mp4", duration: 10.0, frames: framesA, width: 1920, height: 1080),
                feature("/lib/uhd.mp4", duration: 10.0, frames: framesA, width: 3840, height: 2160),
            ],
            configuration: config
        )
        XCTAssertEqual(clusters.count, 1)
        // Keeper is the higher-resolution copy.
        XCTAssertEqual(clusters.first?.suggestedKeeperIDs, ["/lib/uhd.mp4"])
    }

    func testNonReadyFeaturesAreIgnored() {
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/a.mp4", duration: 10.0, frames: framesA, status: .insufficientVisualEvidence),
                feature("/lib/b.mp4", duration: 10.0, frames: framesA, status: .ready),
            ],
            configuration: config
        )
        // Only one ready feature → nothing to cluster.
        XCTAssertTrue(clusters.isEmpty)
    }

    func testDistinctClipsDoNotCluster() {
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/lib/a.mp4", duration: 10.0, frames: framesA),
                feature("/lib/b.mp4", duration: 10.0, frames: framesB),
            ],
            configuration: config
        )
        XCTAssertTrue(clusters.isEmpty)
    }

    func testFolderPriorityWinsKeeperOverResolution() {
        // Priority is consulted before resolution: the preferred-folder copy is
        // kept even though it is lower resolution.
        let clusters = VideoPerceptualMatcher.cluster(
            features: [
                feature("/secondary/hd.mp4", duration: 10.0, frames: framesA, width: 1920, height: 1080, folderRoot: "/secondary"),
                feature("/primary/sd.mp4", duration: 10.0, frames: framesA, width: 1280, height: 720, folderRoot: "/primary"),
            ],
            configuration: config,
            folderPriority: ["/primary": 0, "/secondary": 5]
        )
        XCTAssertEqual(clusters.first?.suggestedKeeperIDs, ["/primary/sd.mp4"])
    }
}
