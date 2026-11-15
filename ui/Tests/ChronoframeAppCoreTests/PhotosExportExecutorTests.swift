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
    /// Fail the write for any resource whose extension is in this set — lets a
    /// test fail one half of a multi-resource asset (e.g. a Live Photo movie).
    var writeFailureExtensions: Set<String> = []
    /// Fractions reported through the progress-capable write, in order.
    var progressFractions: [Double] = []
    /// Runs after each successful write; lets a test flip cancellation mid-asset.
    var afterWrite: (@Sendable (PhotosExportableResource) -> Void)?

    init(resourcesByAsset: [String: [PhotosExportableResource]]) {
        self.resourcesByAsset = resourcesByAsset
    }

    func writeResource(
        _ resource: PhotosExportableResource,
        to destinationURL: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        for fraction in progressFractions { onProgress(fraction) }
        try await writeResource(resource, to: destinationURL)
    }

    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        calls.append(Call(kind: .list, assetID: id))
        if listFailures.contains(id) { throw ExporterTestError.boom }
        return resourcesByAsset[id] ?? []
    }

    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        calls.append(Call(kind: .write, assetID: resource.assetID))
        if writeFailures.contains(resource.assetID) || writeFailureExtensions.contains(resource.fileExtension) {
            throw ExporterTestError.boom
        }
        try Data("bytes:\(resource.fileExtension)".utf8).write(to: destinationURL)
        afterWrite?(resource)
    }
}

/// Implements only the two-argument seam method, like every pre-existing
/// double, so the protocol's default progress method is what the executor hits.
private final class TwoArgumentOnlyExporter: PhotosResourceExporting, @unchecked Sendable {
    private(set) var writtenAssetIDs: [String] = []

    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        [PhotosExportableResource(assetID: id, resourceIndex: 0, fileExtension: "jpg", originalFilename: "\(id).jpg")]
    }

    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        writtenAssetIDs.append(resource.assetID)
        try Data("x".utf8).write(to: destinationURL)
    }
}

/// Thread-safe sink for the executor's `@Sendable` callbacks.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [PhotosExportEvent] = []

    func append(_ event: PhotosExportEvent) {
        lock.lock(); defer { lock.unlock() }
        stored.append(event)
    }

    var events: [PhotosExportEvent] {
        lock.lock(); defer { lock.unlock() }
        return stored
    }
}

private final class FreeSpaceScript: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [Int64?]
    private(set) var callCount = 0

    init(_ values: [Int64?]) { remaining = values }

    func next() -> Int64? {
        lock.lock(); defer { lock.unlock() }
        callCount += 1
        return remaining.count > 1 ? remaining.removeFirst() : remaining.first ?? nil
    }
}

private final class CancelFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.lock(); value = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
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

    private func resource(_ assetID: String, index: Int, ext: String, fileSize: Int64? = nil) -> PhotosExportableResource {
        PhotosExportableResource(
            assetID: assetID,
            resourceIndex: index,
            fileExtension: ext,
            originalFilename: "\(assetID).\(ext)",
            fileSize: fileSize
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

    func testLivePhotoPartialWriteRollsBackWholeAsset() async throws {
        // The still writes, the paired movie fails: the asset must be rolled
        // back so the transfer pipeline never sees a half-exported Live Photo.
        let exporter = RecordingExporter(resourcesByAsset: [
            "live": [resource("live", index: 0, ext: "heic"), resource("live", index: 1, ext: "mov")],
            "ok": [resource("ok", index: 0, ext: "jpg")],
        ])
        exporter.writeFailureExtensions = ["mov"]
        let plan = PhotosExportPlan(entries: [entry("live", stem: "IMG_0001"), entry("ok", stem: "OK")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.failures.map(\.assetID), ["live"], "The Live Photo is a failure")
        XCTAssertEqual(receipt.exportedAssetIDs, ["ok"], "Only the complete asset is published")
        XCTAssertEqual(try stagedNames(), ["OK.jpg"], "The already-written still is rolled back from staging")
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

    // MARK: - Resume support: events, reserved names, free-space floor

    private static let oneGiB: Int64 = 1024 * 1024 * 1024

    private func shape(_ event: PhotosExportEvent) -> String {
        switch event {
        case let .assetStarted(id, index, total): return "started:\(id):\(index)/\(total)"
        case let .resourceProgress(id, fraction): return "progress:\(id):\(fraction)"
        case let .assetCompleted(id, files, _): return "completed:\(id):\(files.count)"
        case let .assetFailed(id, _): return "failed:\(id)"
        }
    }

    func testEventsFollowStartedProgressCompletedOrderPerAsset() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg")],
            "b": [resource("b", index: 0, ext: "heic"), resource("b", index: 1, ext: "mov")],
        ])
        exporter.progressFractions = [0.5, 1.0]
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])
        let log = EventLog()

        _ = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            onEvent: { log.append($0) }
        )

        XCTAssertEqual(log.events.map(shape), [
            "started:a:0/2",
            "progress:a:0.5",
            "progress:a:1.0",
            "completed:a:1",
            "started:b:1/2",
            "progress:b:0.5",
            "progress:b:1.0",
            "progress:b:0.5",
            "progress:b:1.0",
            "completed:b:2",
        ])
    }

    func testAssetCompletedEventCarriesFilesAndHints() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg")],
            "b": [resource("b", index: 0, ext: "heic"), resource("b", index: 1, ext: "mov")],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])
        let log = EventLog()

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            onEvent: { log.append($0) }
        )

        var completed: [String: (files: [PhotosExportedFile], hints: [String: SourceDateHint])] = [:]
        for case let .assetCompleted(id, files, hints) in log.events {
            completed[id] = (files, hints)
        }
        XCTAssertEqual(Set(completed.keys), ["a", "b"])
        for id in ["a", "b"] {
            let expectedFiles = receipt.exportedFiles.filter { $0.assetID == id }
            let expectedKeys = Set(expectedFiles.map { SourceDateHint.pathKey(for: $0.path) })
            XCTAssertEqual(completed[id]?.files, expectedFiles)
            XCTAssertEqual(
                completed[id]?.hints,
                receipt.sourceDateHints.filter { expectedKeys.contains($0.key) }
            )
            XCTAssertEqual(completed[id]?.hints.count, expectedFiles.count)
        }
        let allHints = completed.values.reduce(into: [String: SourceDateHint]()) { $0.merge($1.hints) { _, new in new } }
        XCTAssertEqual(allHints, receipt.sourceDateHints, "The receipt is unchanged: it holds exactly what the events carried")
    }

    func testFailedAssetEmitsAssetFailedWithReceiptMessage() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "bad": [resource("bad", index: 0, ext: "jpg")],
            "good": [resource("good", index: 0, ext: "jpg")],
        ])
        exporter.writeFailures = ["bad"]
        let plan = PhotosExportPlan(entries: [entry("bad", stem: "BAD"), entry("good", stem: "GOOD")])
        let log = EventLog()

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            onEvent: { log.append($0) }
        )

        let failure = try XCTUnwrap(receipt.failures.first)
        XCTAssertEqual(receipt.failures.count, 1)
        XCTAssertEqual(log.events.map(shape), [
            "started:bad:0/2",
            "failed:bad",
            "started:good:1/2",
            "completed:good:1",
        ])
        XCTAssertEqual(log.events[1], .assetFailed(assetID: "bad", message: failure.message))
    }

    func testReservedFilenamesAreNeverReused() async throws {
        // A resumed export must not reuse a completed asset's staged name.
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let publishedURL = stagingRoot.appendingPathComponent("IMG_0001.jpg")
        try Data("published".utf8).write(to: publishedURL)
        let exporter = RecordingExporter(resourcesByAsset: [
            "new": [resource("new", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("new", stem: "IMG_0001")])
        let reserved: Set<String> = ["IMG_0001.jpg"]

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            reservedFilenames: reserved
        )

        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names, ["IMG_0001-0.jpg"])
        XCTAssertTrue(names.allSatisfy { !reserved.contains($0) })
        XCTAssertEqual(try Data(contentsOf: publishedURL), Data("published".utf8), "The reserved file is untouched")
    }

    // AGENTS-INVARIANT: 22
    func testLowSpaceStopsBeforeFirstWriteOfNextAsset() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg")],
            "b": [resource("b", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])
        let space = FreeSpaceScript([10 * Self.oneGiB, Self.oneGiB])
        let log = EventLog()
        let executor = PhotosExportExecutor(
            exporter: exporter,
            freeSpaceFloorBytes: 2 * Self.oneGiB,
            freeSpaceProvider: { _ in space.next() }
        )

        do {
            _ = try await executor.export(plan: plan, to: stagingRoot, onEvent: { log.append($0) })
            XCTFail("expected a low-space stop")
        } catch let stop as PhotosExportStop {
            XCTAssertEqual(stop, .lowStagingSpace(freeBytes: Self.oneGiB, floorBytes: 2 * Self.oneGiB))
        } catch {
            XCTFail("expected PhotosExportStop, got \(error)")
        }

        XCTAssertEqual(space.callCount, 2)
        XCTAssertEqual(exporter.calls.filter { $0.assetID == "b" }, [], "Asset b is never listed or written")
        XCTAssertEqual(log.events.map(shape), ["started:a:0/2", "completed:a:1"])
        XCTAssertEqual(try stagedNames(), ["A.jpg"], "The completed asset's published file is kept")
    }

    // AGENTS-INVARIANT: 22
    func testLowSpaceThresholdIncludesTheAssetsKnownSize() async throws {
        // 6 GiB free clears the 2 GiB floor, but not floor + the 5 GiB video.
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg")],
            "v": [resource("v", index: 0, ext: "mov", fileSize: 5 * Self.oneGiB)],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("v", stem: "V", kind: .video)])
        let space = FreeSpaceScript([6 * Self.oneGiB])
        let executor = PhotosExportExecutor(
            exporter: exporter,
            freeSpaceFloorBytes: 2 * Self.oneGiB,
            freeSpaceProvider: { _ in space.next() }
        )

        do {
            _ = try await executor.export(plan: plan, to: stagingRoot)
            XCTFail("expected a low-space stop")
        } catch let stop as PhotosExportStop {
            XCTAssertEqual(stop, .lowStagingSpace(freeBytes: 6 * Self.oneGiB, floorBytes: 7 * Self.oneGiB))
        } catch {
            XCTFail("expected PhotosExportStop, got \(error)")
        }

        XCTAssertEqual(exporter.calls.filter { $0.kind == .write && $0.assetID == "v" }, [], "The large video is never written")
        XCTAssertEqual(try stagedNames(), ["A.jpg"], "The completed asset is kept and nothing of the video is left behind")
    }

    func testLowSpaceThresholdStillPassesWhenTheAssetFits() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "v": [resource("v", index: 0, ext: "mov", fileSize: 5 * Self.oneGiB)],
        ])
        let plan = PhotosExportPlan(entries: [entry("v", stem: "V", kind: .video)])
        let executor = PhotosExportExecutor(
            exporter: exporter,
            freeSpaceFloorBytes: 2 * Self.oneGiB,
            freeSpaceProvider: { _ in 7 * Self.oneGiB }
        )

        let receipt = try await executor.export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.exportedAssetIDs, ["v"])
    }

    func testNilFreeSpaceNeverStopsExport() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg")],
            "b": [resource("b", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])
        let space = FreeSpaceScript([nil])
        let executor = PhotosExportExecutor(
            exporter: exporter,
            freeSpaceFloorBytes: Int64.max,
            freeSpaceProvider: { _ in space.next() }
        )

        let receipt = try await executor.export(plan: plan, to: stagingRoot)

        XCTAssertEqual(space.callCount, 2, "Free space is consulted before every asset")
        XCTAssertEqual(receipt.exportedAssetIDs, ["a", "b"])
        XCTAssertEqual(try stagedNames(), ["A.jpg", "B.jpg"])
    }

    // AGENTS-INVARIANT: 22
    func testCancellationStillRollsBackOnlyInFlightAsset() async throws {
        let cancelFlag = CancelFlag()
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "jpg")],
            "b": [resource("b", index: 0, ext: "heic"), resource("b", index: 1, ext: "mov")],
        ])
        // Cancel after asset b's first resource is on disk: b is in flight.
        exporter.afterWrite = { resource in
            if resource.assetID == "b", resource.resourceIndex == 0 { cancelFlag.set() }
        }
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])
        let log = EventLog()

        do {
            _ = try await PhotosExportExecutor(exporter: exporter).export(
                plan: plan,
                to: stagingRoot,
                isCancelled: { cancelFlag.isSet },
                onEvent: { log.append($0) }
            )
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        XCTAssertEqual(try stagedNames(), ["A.jpg"], "Completed asset a stays; in-flight asset b is rolled back")
        XCTAssertEqual(log.events.map(shape), ["started:a:0/2", "completed:a:1", "started:b:1/2"])
    }

    func testDefaultProtocolProgressMethodForwardsToTwoArgumentWrite() async throws {
        let exporter = TwoArgumentOnlyExporter()
        let seam: any PhotosResourceExporting = exporter
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-default-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: target) }
        let resource = PhotosExportableResource(assetID: "x", resourceIndex: 0, fileExtension: "jpg", originalFilename: "x.jpg")

        try await seam.writeResource(resource, to: target, onProgress: { _ in })

        XCTAssertEqual(exporter.writtenAssetIDs, ["x"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))

        // The executor drives the same double through the progress-capable seam.
        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: PhotosExportPlan(entries: [entry("y", stem: "Y")]),
            to: stagingRoot
        )
        XCTAssertEqual(exporter.writtenAssetIDs, ["x", "y"])
        XCTAssertEqual(receipt.exportedAssetIDs, ["y"])
    }
}
