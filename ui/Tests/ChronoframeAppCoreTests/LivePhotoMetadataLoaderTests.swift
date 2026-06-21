import AVFoundation
import Foundation
import XCTest
@testable import ChronoframeCore

final class LivePhotoMetadataLoaderTests: XCTestCase {
    private final class BlockingProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var active = 0
        private(set) var maximum = 0

        func block(for interval: TimeInterval) {
            lock.lock()
            active += 1
            maximum = max(maximum, active)
            lock.unlock()
            Thread.sleep(forTimeInterval: interval)
            lock.lock()
            active -= 1
            lock.unlock()
        }

        func maxActive() -> Int {
            lock.lock(); defer { lock.unlock() }
            return maximum
        }
    }

    func testTimeoutCircuitBreakerKeepsOutstandingWorkBounded() async {
        let probe = BlockingProbe()
        let loader = BoundedLivePhotoMetadataLoader(
            workerCount: 4,
            timeoutSeconds: 0.03,
            circuitBreakerTimeoutCount: 4,
            identifierLoader: { _ in
                probe.block(for: 0.3)
                return nil
            }
        )
        let urls = (0..<12).map { URL(fileURLWithPath: "/tmp/video-\($0).mov") }
        let result = await loader.loadIdentifiers(for: urls)

        XCTAssertEqual(result.unsupportedPaths.count, urls.count)
        XCTAssertLessThanOrEqual(probe.maxActive(), 4)
        XCTAssertEqual(loader.observedTimeoutCount, 4)
        XCTAssertLessThanOrEqual(loader.outstandingLoadCount, 4)
    }

    func testCancellationReturnsPromptlyAndCancelsOutstandingLoads() async {
        let probe = BlockingProbe()
        let loader = BoundedLivePhotoMetadataLoader(
            workerCount: 4,
            timeoutSeconds: 10,
            circuitBreakerTimeoutCount: 4,
            identifierLoader: { _ in
                probe.block(for: 2)
                return nil
            }
        )
        let started = Date()
        let task = Task {
            await loader.loadIdentifiers(for: (0..<4).map { URL(fileURLWithPath: "/tmp/cancel-\($0).mov") })
        }
        try? await Task.sleep(nanoseconds: 30_000_000)
        task.cancel()
        _ = await task.value
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        XCTAssertLessThanOrEqual(loader.outstandingLoadCount, 4)
    }

    func testMetadataAssetsForbidExternalReferencesAndDisablePreciseTiming() {
        let asset = BoundedLivePhotoMetadataLoader.makeMetadataAsset(
            url: URL(fileURLWithPath: "/tmp/metadata.mov")
        )
        XCTAssertEqual(asset.referenceRestrictions, .forbidAll)
        let preciseTiming = BoundedLivePhotoMetadataLoader.metadataAssetOptions[
            AVURLAssetPreferPreciseDurationAndTimingKey
        ] as? Bool
        XCTAssertEqual(preciseTiming, false)
    }
}
