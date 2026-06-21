import AVFoundation
import Foundation
import XCTest
@testable import ChronoframeCore

final class LivePhotoMetadataLoaderTests: XCTestCase {
    private final class InvocationProbe: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: Set<String> = []

        func record(_ path: String) {
            lock.lock()
            paths.insert(path)
            lock.unlock()
        }

        func contains(_ path: String) -> Bool {
            lock.lock()
            defer { lock.unlock() }
            return paths.contains(path)
        }
    }

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

    private static func delayIgnoringTaskCancellation(for interval: TimeInterval) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().asyncAfter(deadline: .now() + interval) {
                continuation.resume()
            }
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
        let loader = BoundedLivePhotoMetadataLoader(
            workerCount: 4,
            timeoutSeconds: 10,
            circuitBreakerTimeoutCount: 4,
            identifierLoader: { _ in
                await Self.delayIgnoringTaskCancellation(for: 2)
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
        XCTAssertEqual(loader.outstandingLoadCount, 0)
    }

    func testCancelledGenerationDoesNotBlockNextMetadataLoad() async {
        let probe = InvocationProbe()
        let firstURL = URL(fileURLWithPath: "/tmp/chronoframe-live-photo-stuck.mov")
        let secondURL = URL(fileURLWithPath: "/tmp/chronoframe-live-photo-next.mov")
        let loader = BoundedLivePhotoMetadataLoader(
            workerCount: 1,
            timeoutSeconds: 10,
            circuitBreakerTimeoutCount: 1,
            identifierLoader: { asset in
                probe.record(asset.url.path)
                if asset.url.path == firstURL.path {
                    await Self.delayIgnoringTaskCancellation(for: 0.5)
                    return nil
                }
                return "next-generation-identifier"
            }
        )

        let firstLoad = Task {
            await loader.loadIdentifiers(for: [firstURL])
        }

        for _ in 0..<100 where !probe.contains(firstURL.path) {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
        XCTAssertTrue(probe.contains(firstURL.path))

        firstLoad.cancel()
        _ = await firstLoad.value
        XCTAssertEqual(loader.outstandingLoadCount, 0)

        let secondResult = await loader.loadIdentifiers(for: [secondURL])

        XCTAssertEqual(
            secondResult.identifiersByPath[secondURL.path],
            "next-generation-identifier"
        )
        XCTAssertFalse(secondResult.unsupportedPaths.contains(secondURL.path))
        XCTAssertTrue(probe.contains(secondURL.path))
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
