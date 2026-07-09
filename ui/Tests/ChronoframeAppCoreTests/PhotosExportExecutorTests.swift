import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

private enum ExporterTestError: Error { case boom }

/// Read-only test double. It records every call so tests can assert exactly
/// which seam methods ran — and, crucially, the seam itself has NO mutating
/// method, so an "import writes back to the library" bug is unrepresentable.
private final class RecordingExporter: PhotosResourceExporting, @unchecked Sendable {
    enum CallKind: Equatable { case list, write }
    struct Call: Equatable {
        let kind: CallKind
        let assetID: String
    }

    // The executor awaits each call before the next, so access is serial and
    // needs no lock (an async context can't use NSLock in Swift 6 anyway).
    private(set) var calls: [Call] = []

    var resourcesByAsset: [String: [PhotosExportableResource]]
    var listFailures: Set<String> = []
    var writeFailures: Set<String> = []

    init(resourcesByAsset: [String: [PhotosExportableResource]]) {
        self.resourcesByAsset = resourcesByAsset
    }

    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        calls.append(Call(kind: .list, assetID: id))
        if listFailures.contains(id) { throw ExporterTestError.boom }
        return resourcesByAsset[id] ?? []
    }

    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        calls.append(Call(kind: .write, assetID: resource.assetID))
        if writeFailures.contains(resource.assetID) { throw ExporterTestError.boom }
        try Data("bytes:\(resource.fileExtension)".utf8).write(to: destinationURL)
    }
}

final class PhotosExportExecutorTests: XCTestCase {
    private var stagingRoot: URL!

    override func setUpWithError() throws {
        stagingRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-export-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let stagingRoot { try? FileManager.default.removeItem(at: stagingRoot) }
    }

    private func resource(_ assetID: String, index: Int, ext: String) -> PhotosExportableResource {
        PhotosExportableResource(
            assetID: assetID,
            resourceIndex: index,
            fileExtension: ext,
            originalFilename: "\(assetID).\(ext)"
        )
    }

    private func entry(_ assetID: String, stem: String, kind: PhotosAssetSummary.MediaKind = .photo) -> PhotosAssetExportEntry {
        PhotosAssetExportEntry(assetID: assetID, mediaKind: kind, stagingStem: stem)
    }

    private func stagedNames() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: stagingRoot.path).sorted()
    }

    func testExportsLivePhotoPairAndVideoWithStems() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            // Live Photo: still + paired movie, same stem, different extensions.
            "live": [resource("live", index: 0, ext: "heic"), resource("live", index: 1, ext: "mov")],
            "clip": [resource("clip", index: 0, ext: "mov")],
        ])
        let plan = PhotosExportPlan(entries: [
            entry("live", stem: "IMG_0001"),
            entry("clip", stem: "MOV_0002", kind: .video),
        ])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.failures, [])
        XCTAssertEqual(receipt.stagedFileCount, 3)
        XCTAssertEqual(try stagedNames(), ["IMG_0001.heic", "IMG_0001.mov", "MOV_0002.mov"])
        XCTAssertEqual(receipt.exportedAssetIDs, ["live", "clip"])
    }

    func testAssetWithNoOriginalsBecomesFailureNotStaged() async throws {
        let exporter = RecordingExporter(resourcesByAsset: ["a": []])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertTrue(receipt.isEmpty)
        XCTAssertEqual(receipt.failures.map(\.assetID), ["a"])
        XCTAssertTrue(try stagedNames().isEmpty)
    }

    func testListFailureIsRecordedAndOthersStillExport() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "good": [resource("good", index: 0, ext: "jpg")],
            "bad": [resource("bad", index: 0, ext: "jpg")],
        ])
        exporter.listFailures = ["bad"]
        let plan = PhotosExportPlan(entries: [entry("bad", stem: "BAD"), entry("good", stem: "GOOD")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.failures.map(\.assetID), ["bad"])
        XCTAssertEqual(receipt.exportedAssetIDs, ["good"])
        XCTAssertEqual(try stagedNames(), ["GOOD.jpg"])
    }

    func testWriteFailureIsRecordedAsFailure() async throws {
        let exporter = RecordingExporter(resourcesByAsset: ["a": [resource("a", index: 0, ext: "jpg")]])
        exporter.writeFailures = ["a"]
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.failures.map(\.assetID), ["a"])
        XCTAssertTrue(receipt.isEmpty)
    }

    func testNormalizesExtensionCaseAndLeadingDot() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [PhotosExportableResource(assetID: "a", resourceIndex: 0, fileExtension: ".HEIC", originalFilename: "a.HEIC")],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "Photo")])

        _ = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(try stagedNames(), ["Photo.heic"])
    }

    func testSameExtensionResourcesOnOneAssetGetDistinctNames() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg"), resource("a", index: 1, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "Dup")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.stagedFileCount, 2)
        let names = try stagedNames()
        XCTAssertEqual(Set(names).count, 2, "same-extension resources must not collide: \(names)")
    }

    func testCancellationBeforeAssetThrows() async {
        let exporter = RecordingExporter(resourcesByAsset: ["a": [resource("a", index: 0, ext: "jpg")]])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A")])

        do {
            _ = try await PhotosExportExecutor(exporter: exporter).export(
                plan: plan,
                to: stagingRoot,
                isCancelled: { true }
            )
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testCancellationBetweenResourcesThrows() async {
        // isCancelled returns false at the loop top, then true before the
        // first resource write — exercising the mid-asset cancellation path.
        final class Gate: @unchecked Sendable {
            private let lock = NSLock()
            private var count = 0
            func fire() -> Bool {
                lock.lock(); defer { lock.unlock() }
                count += 1
                return count > 1
            }
        }
        let gate = Gate()
        let exporter = RecordingExporter(resourcesByAsset: ["a": [resource("a", index: 0, ext: "jpg")]])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A")])

        do {
            _ = try await PhotosExportExecutor(exporter: exporter).export(
                plan: plan,
                to: stagingRoot,
                isCancelled: { gate.fire() }
            )
            XCTFail("expected cancellation")
        } catch is CancellationError {
            XCTAssertTrue(try! stagedNames().isEmpty)
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }
    }

    func testResourceWithoutExtensionStagesBareStem() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [PhotosExportableResource(assetID: "a", resourceIndex: 0, fileExtension: "", originalFilename: "a")],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "Bare")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.stagedFileCount, 1)
        XCTAssertEqual(try stagedNames(), ["Bare"])
    }

    func testCreateDirectoryFailurePropagates() async {
        // Make the staging *parent* a file so createDirectory throws.
        let blocker = stagingRoot.deletingLastPathComponent()
            .appendingPathComponent("blocker-\(UUID().uuidString)")
        try? Data("x".utf8).write(to: blocker)
        defer { try? FileManager.default.removeItem(at: blocker) }
        let nested = blocker.appendingPathComponent("staging")

        let exporter = RecordingExporter(resourcesByAsset: [:])
        let plan = PhotosExportPlan(entries: [])

        do {
            _ = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: nested)
            XCTFail("expected createDirectory to throw")
        } catch is CancellationError {
            XCTFail("unexpected cancellation")
        } catch {
            // expected: a filesystem error
        }
    }

    // AGENTS-INVARIANT: 22
    func testImportPathIsReadOnlyAgainstLibrary() async throws {
        // The export runs entirely through the `PhotosResourceExporting` seam,
        // whose surface has NO mutating method — the executor cannot reach a
        // PhotoKit change request even in principle. This test pins that the
        // executor only ever *lists* and *reads* (writes copies OUT to
        // staging) and never touches the source library.
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg")],
            "b": [resource("b", index: 0, ext: "heic"), resource("b", index: 1, ext: "mov")],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        // Only read-shaped calls happened: list per asset, write per resource.
        // (`.write` copies bytes OUT to a Chronoframe staging URL; it never
        // writes into the Photos library.)
        for call in exporter.calls {
            XCTAssertTrue(call.kind == .list || call.kind == .write)
        }
        XCTAssertEqual(exporter.calls.filter { $0.kind == .list }.map(\.assetID), ["a", "b"])
        XCTAssertEqual(receipt.stagedFileCount, 3)
    }
}
