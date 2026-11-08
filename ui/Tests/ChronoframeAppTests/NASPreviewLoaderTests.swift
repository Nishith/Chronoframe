#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import AppKit
import CoreGraphics
import XCTest
@testable import ChronoframeApp

private final class RenderRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func record(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var recorded: [URL] { lock.lock(); defer { lock.unlock() }; return urls }
}

private func makeImage() -> CGImage {
    let context = CGContext(
        data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    return context.makeImage()!
}

@MainActor
final class NASPreviewLoaderTests: XCTestCase {
    private var harness: NASViewTestHarness!

    override func setUpWithError() throws {
        harness = try NASViewTestHarness()
    }

    override func tearDown() {
        harness.tearDown()
        harness = nil
    }

    func testPreviewLoaderNotCalledOnSelectionOrAppear() async {
        let recorder = RenderRecorder()
        let image = makeImage()
        let loader = NASPreviewLoader(renderer: { url, _, _ in recorder.record(url); return image })
        let group = NASViewFixtures.group()
        await harness.loadResults(groups: [group])
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: loader)

        await viewModel.viewDidAppear()
        viewModel.select(digest: group.digest)
        viewModel.select(digest: nil)
        viewModel.select(digest: group.digest)
        // Showing the detail pane asks the loader for what it already has; that never renders.
        XCTAssertNil(loader.cachedImage(forDigest: group.digest))

        XCTAssertEqual(recorder.recorded, [], "Selection and appearance must never read media")
        XCTAssertFalse(harness.store.previewRequestedDigests.contains(group.digest))
        XCTAssertFalse(harness.engine.calls.contains("recordPreviewRequest"))
    }

    func testPreviewLoaderRendersOnceAfterExplicitRequestAndCaches() async {
        let recorder = RenderRecorder()
        let image = makeImage()
        let loader = NASPreviewLoader(renderer: { url, _, _ in recorder.record(url); return image })
        let group = NASViewFixtures.group()
        await harness.loadResults(groups: [group])
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: loader)

        await viewModel.loadPreview(for: group)

        XCTAssertEqual(recorder.recorded.map(\.path), ["/Volumes/photo/Photos/2018/a.jpg"])
        XCTAssertTrue(harness.store.previewRequestedDigests.contains(group.digest))
        XCTAssertNotNil(loader.cachedImage(forDigest: group.digest))

        // A second press, and a re-selected group, are served from the cache.
        await viewModel.loadPreview(for: group)
        XCTAssertEqual(recorder.recorded.count, 1)
        XCTAssertEqual(harness.engine.calls.filter { $0 == "recordPreviewRequest" }.count, 1)
    }

    func testPreviewIsNotRenderedWhenTheStoreRefusesTheRequest() async {
        // No results are loaded, so the store ignores the request and nothing may be read.
        let recorder = RenderRecorder()
        let image = makeImage()
        let loader = NASPreviewLoader(renderer: { url, _, _ in recorder.record(url); return image })
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: loader)

        await viewModel.loadPreview(for: NASViewFixtures.group())

        XCTAssertEqual(recorder.recorded, [])
    }

    func testFailedRenderIsRememberedAndNotRetriedImplicitly() async {
        let recorder = RenderRecorder()
        let loader = NASPreviewLoader(renderer: { url, _, _ in recorder.record(url); return nil })
        let group = NASViewFixtures.group()
        await harness.loadResults(groups: [group])
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: loader)

        await viewModel.loadPreview(for: group)

        XCTAssertNil(loader.cachedImage(forDigest: group.digest))
        XCTAssertTrue(loader.failedDigests.contains(group.digest))
        XCTAssertFalse(loader.loadingDigests.contains(group.digest))
    }

    func testCacheIsBoundedAt128ByDefault() {
        XCTAssertEqual(NASPreviewLoader.defaultCountLimit, 128)
    }
}
