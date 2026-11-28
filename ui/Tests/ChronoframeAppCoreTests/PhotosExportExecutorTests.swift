#if canImport(Photos)
import Photos
#endif
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

private enum ExporterTestError: Error { case boom }

/// Read-only test double. It records every call so tests can assert exactly
/// which seam methods ran — and, crucially, the seam itself has NO mutating
/// method, so an "import writes back to the library" bug is unrepresentable.
private final class RecordingExporter: PhotosResourceExporting, @unchecked Sendable {
    enum CallKind: Equatable { case list, write, editedList, unsupportedCheck }
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
    /// Edited still renders by asset (edit-preservation).
    var editedByAsset: [String: PhotosExportableResource] = [:]
    var editedListFailures: Set<String> = []
    var editedWriteFailures: Set<String> = []
    var unsupportedEditedAssets: Set<String> = []
    /// Roles of every resource written, in order.
    private(set) var writtenRoles: [PhotosExportableResource.Role] = []

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

    /// Content that names its own asset and resource, so a test can tell whose
    /// bytes ended up in a staged file.
    static func bytes(for resource: PhotosExportableResource) -> String {
        "bytes:\(resource.assetID):\(resource.resourceIndex):\(resource.fileExtension)"
    }

    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource] {
        calls.append(Call(kind: .list, assetID: id))
        if listFailures.contains(id) { throw ExporterTestError.boom }
        return resourcesByAsset[id] ?? []
    }

    func editedStillResource(forAssetID id: String) async throws -> PhotosExportableResource? {
        calls.append(Call(kind: .editedList, assetID: id))
        if editedListFailures.contains(id) { throw ExporterTestError.boom }
        return editedByAsset[id]
    }

    func hasUnsupportedEditedRender(forAssetID id: String) async throws -> Bool {
        calls.append(Call(kind: .unsupportedCheck, assetID: id))
        return unsupportedEditedAssets.contains(id)
    }

    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws {
        calls.append(Call(kind: .write, assetID: resource.assetID))
        writtenRoles.append(resource.role)
        if resource.role == .editedRender, editedWriteFailures.contains(resource.assetID) {
            throw ExporterTestError.boom
        }
        if resource.role == .original, writeFailures.contains(resource.assetID) || writeFailureExtensions.contains(resource.fileExtension) {
            throw ExporterTestError.boom
        }
        try Data(Self.bytes(for: resource).utf8).write(to: destinationURL)
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

    /// Every staged file must hold the bytes its own asset's resource wrote,
    /// not another asset's that landed on the same on-disk name.
    private func assertStagedBytesBelongToOwnAssets(
        _ receipt: PhotosExportReceipt,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        for staged in receipt.exportedFiles {
            let text = String(decoding: try Data(contentsOf: URL(fileURLWithPath: staged.path)), as: UTF8.self)
            XCTAssertTrue(
                text.hasPrefix("bytes:\(staged.assetID):"),
                "\(staged.path) holds \(text), which is not asset \(staged.assetID)'s content",
                file: file,
                line: line
            )
        }
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
        case let .editedVersionSaved(id, _): return "editedSaved:\(id)"
        case let .editedVersionFailed(id): return "editedFailed:\(id)"
        case let .editedVersionNotIncluded(id): return "editedNotIncluded:\(id)"
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
    func testFallbackNameNeverLandsOnAnotherAssetsFile() async throws {
        // "IMG_0001" with two JPEG resources falls back to "IMG_0001-2.jpg" for
        // the second one, which is exactly the first asset's published name.
        let exporter = RecordingExporter(resourcesByAsset: [
            "p": [resource("p", index: 0, ext: "jpg")],
            "q": [resource("q", index: 0, ext: "jpg"), resource("q", index: 2, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("p", stem: "IMG_0001-2"), entry("q", stem: "IMG_0001")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names.count, 3)
        XCTAssertEqual(Set(names).count, 3, "every staged file needs its own name: \(names)")
        XCTAssertEqual(try stagedNames().count, 3, "three files must exist in staging")
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    // AGENTS-INVARIANT: 22
    func testNamesDifferingOnlyByCaseDoNotShareAFile() async throws {
        // Staging is usually a case-insensitive volume, where these two stems
        // would be one file.
        let exporter = RecordingExporter(resourcesByAsset: [
            "upper": [resource("upper", index: 0, ext: "jpg")],
            "lower": [resource("lower", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("upper", stem: "IMG_0001"), entry("lower", stem: "img_0001")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(Set(names.map { $0.lowercased() }).count, 2, "names must differ by more than case: \(names)")
        XCTAssertEqual(try stagedNames().count, 2, "two files must exist in staging")
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    // AGENTS-INVARIANT: 22
    func testReservedFilenameIsMatchedIgnoringCase() async throws {
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let publishedURL = stagingRoot.appendingPathComponent("img_0001.jpg")
        try Data("published".utf8).write(to: publishedURL)
        let exporter = RecordingExporter(resourcesByAsset: [
            "new": [resource("new", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("new", stem: "IMG_0001")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            reservedFilenames: ["img_0001.jpg"]
        )

        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names, ["IMG_0001-0.jpg"])
        XCTAssertEqual(try Data(contentsOf: publishedURL), Data("published".utf8), "The reserved file is untouched")
    }

    // AGENTS-INVARIANT: 22
    func testStemsDifferingOnlyByUnicodeNormalizationDoNotShareAFile() async throws {
        // APFS and HFS+ treat precomposed and decomposed "é" as the same name.
        let composed = "Caf\u{E9}"
        let decomposed = "Cafe\u{301}"
        let exporter = RecordingExporter(resourcesByAsset: [
            "composed": [resource("composed", index: 0, ext: "jpg")],
            "decomposed": [resource("decomposed", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("composed", stem: composed), entry("decomposed", stem: decomposed)])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.failures, [])
        XCTAssertEqual(try stagedNames().count, 2, "two files must exist in staging")
        let fold: (String) -> String = {
            $0.decomposedStringWithCanonicalMapping.folding(options: [.caseInsensitive], locale: nil)
        }
        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(Set(names.map(fold)).count, 2, "names must differ by more than normalization: \(names)")
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    // AGENTS-INVARIANT: 22
    func testStemsThatFoldTogetherButDoNotLowercaseTogetherDoNotShareAFile() async throws {
        // Greek small sigma and final sigma are one name on a case-insensitive
        // APFS volume (case folding), yet lowercased() leaves them different.
        let exporter = RecordingExporter(resourcesByAsset: [
            "sigma": [resource("sigma", index: 0, ext: "jpg")],
            "final": [resource("final", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("sigma", stem: "\u{3C3}"), entry("final", stem: "\u{3C2}")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.failures, [])
        XCTAssertEqual(try stagedNames().count, 2, "two files must exist in staging")
        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(
            Set(names.map { $0.folding(options: [.caseInsensitive], locale: nil) }).count,
            2,
            "names must differ by more than case folding: \(names)"
        )
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    // AGENTS-INVARIANT: 22
    func testReservedFilenameIsMatchedAcrossUnicodeNormalization() async throws {
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let publishedURL = stagingRoot.appendingPathComponent("Caf\u{E9}.jpg")
        try Data("published".utf8).write(to: publishedURL)
        let exporter = RecordingExporter(resourcesByAsset: [
            "new": [resource("new", index: 0, ext: "jpg")],
        ])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: PhotosExportPlan(entries: [entry("new", stem: "Cafe\u{301}")]),
            to: stagingRoot,
            reservedFilenames: ["Caf\u{E9}.jpg"]
        )

        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names, ["Cafe\u{301}-0.jpg"])
        XCTAssertEqual(try Data(contentsOf: publishedURL), Data("published".utf8), "The reserved file is untouched")
    }

    func testDiacriticsAreNotFoldedAway() async throws {
        // "Cafe" and "Café" are different files on APFS, so neither is renamed.
        let exporter = RecordingExporter(resourcesByAsset: [
            "plain": [resource("plain", index: 0, ext: "jpg")],
            "accent": [resource("accent", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("plain", stem: "Cafe"), entry("accent", stem: "Caf\u{E9}")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        let names = receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names, ["Cafe.jpg", "Caf\u{E9}.jpg"])
        XCTAssertEqual(try stagedNames().count, 2)
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    // AGENTS-INVARIANT: 22
    func testUnreservedStagedFileOfCaseVariantNameSurvivesByteForByte() async throws {
        // Not in reservedFilenames, so the executor can't know about it from
        // the caller; the write itself must refuse to replace it.
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let lowerURL = stagingRoot.appendingPathComponent("img_0001.jpg")
        let exactURL = stagingRoot.appendingPathComponent("IMG_0002.jpg")
        let lowerBytes = Data("precious-lower".utf8)
        let exactBytes = Data("precious-exact".utf8)
        try lowerBytes.write(to: lowerURL)
        try exactBytes.write(to: exactURL)
        let exporter = RecordingExporter(resourcesByAsset: [
            "one": [resource("one", index: 0, ext: "jpg")],
            "two": [resource("two", index: 0, ext: "jpg")],
        ])
        let plan = PhotosExportPlan(entries: [entry("one", stem: "IMG_0001"), entry("two", stem: "IMG_0002")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)

        XCTAssertEqual(receipt.failures, [])
        XCTAssertEqual(try Data(contentsOf: lowerURL), lowerBytes, "the case-variant staged file is untouched")
        XCTAssertEqual(try Data(contentsOf: exactURL), exactBytes, "the same-name staged file is untouched")
        XCTAssertEqual(receipt.stagedFileCount, 2)
        XCTAssertEqual(try stagedNames().count, 4, "both new files sit beside the two existing ones")
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    // AGENTS-INVARIANT: 22
    func testRollbackNeverRemovesAFileTheExecutorDidNotCreate() async throws {
        try FileManager.default.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        let existingURL = stagingRoot.appendingPathComponent("IMG_0001.jpg")
        try Data("precious".utf8).write(to: existingURL)
        let exporter = RecordingExporter(resourcesByAsset: [
            "bad": [resource("bad", index: 0, ext: "jpg")],
        ])
        exporter.writeFailures = ["bad"]

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: PhotosExportPlan(entries: [entry("bad", stem: "IMG_0001")]),
            to: stagingRoot
        )

        XCTAssertEqual(receipt.failures.map(\.assetID), ["bad"])
        XCTAssertEqual(try Data(contentsOf: existingURL), Data("precious".utf8))
        XCTAssertEqual(try stagedNames(), ["IMG_0001.jpg"], "the failed asset's claimed name is rolled back")
    }

    // AGENTS-INVARIANT: 22
    func testExhaustedNameAttemptsFailOnlyThatAsset() async throws {
        // With every candidate name taken the search must stop, not spin.
        let exporter = RecordingExporter(resourcesByAsset: [
            "stuck": [resource("stuck", index: 0, ext: "jpg")],
            "fine": [resource("fine", index: 0, ext: "jpg")],
        ])
        var executor = PhotosExportExecutor(exporter: exporter)
        executor.maxNameAttempts = 3
        let plan = PhotosExportPlan(entries: [entry("stuck", stem: "A"), entry("fine", stem: "B")])

        let receipt = try await executor.export(
            plan: plan,
            to: stagingRoot,
            reservedFilenames: ["A.jpg", "A-0.jpg", "A-0-2.jpg"]
        )

        XCTAssertEqual(receipt.failures.map(\.assetID), ["stuck"])
        XCTAssertEqual(receipt.exportedAssetIDs, ["fine"])
        XCTAssertEqual(try stagedNames(), ["B.jpg"])
        XCTAssertEqual(exporter.calls.filter { $0.kind == .write && $0.assetID == "stuck" }, [], "nothing is written for the stuck asset")
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

    // MARK: - Edited still export (edit-preservation C-04)

    private func editedResource(_ assetID: String, index: Int = 3, ext: String = "jpg", filename: String? = nil) -> PhotosExportableResource {
        PhotosExportableResource(
            assetID: assetID,
            resourceIndex: index,
            fileExtension: ext,
            originalFilename: filename ?? "FullSizeRender.\(ext)",
            role: .editedRender
        )
    }

    private func stagedBytes(_ path: String) throws -> Data {
        try Data(contentsOf: URL(fileURLWithPath: path))
    }

    // AGENTS-INVARIANT: 22
    func testOriginalsOnlyWhenOptionOffMatchesPreviousBehavior() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "heic")],
            "b": [resource("b", index: 0, ext: "heic"), resource("b", index: 1, ext: "mov")],
        ])
        // An edit and an unsupported edit exist, but the option is off.
        exporter.editedByAsset = ["a": editedResource("a")]
        exporter.unsupportedEditedAssets = ["b"]
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])
        let log = EventLog()

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            onEvent: { log.append($0) }
        )

        XCTAssertEqual(try stagedNames(), ["A.heic", "B.heic", "B.mov"])
        XCTAssertEqual(exporter.calls.filter { $0.kind == .editedList || $0.kind == .unsupportedCheck }, [],
                       "With the option off the exporter is never asked about edits")
        XCTAssertEqual(exporter.writtenRoles, [.original, .original, .original])
        XCTAssertEqual(receipt.editedFiles, [])
        XCTAssertEqual(receipt.variantFailures, [])
        XCTAssertEqual(receipt.editedNotIncludedCount, 0)
        XCTAssertEqual(log.events.map(shape), [
            "started:a:0/2", "completed:a:1", "started:b:1/2", "completed:b:2",
        ])
    }

    func testEditedStillExportedAsSeparateDistinctlyNamedFile() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "heic")],
        ])
        exporter.editedByAsset = ["a": editedResource("a", ext: "jpg")]
        let plan = PhotosExportPlan(entries: [entry("a", stem: "IMG_0001")])
        let log = EventLog()

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            includeEditedVersions: true,
            onEvent: { log.append($0) }
        )

        XCTAssertEqual(try stagedNames(), ["IMG_0001-edited.jpg", "IMG_0001.heic"])
        XCTAssertEqual(receipt.exportedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["IMG_0001.heic", "IMG_0001-edited.jpg"])
        XCTAssertEqual(receipt.editedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }, ["IMG_0001-edited.jpg"])
        XCTAssertEqual(receipt.editedFiles.first?.assetID, "a")
        XCTAssertEqual(receipt.editedFiles.first?.stagingStem, "IMG_0001")
        XCTAssertEqual(receipt.variantFailures, [])
        XCTAssertEqual(receipt.sourceDateHints.count, 2, "The edited file has its own content-bound hint")
        XCTAssertEqual(log.events.map(shape), ["started:a:0/1", "editedSaved:a", "completed:a:2"])
        XCTAssertEqual(exporter.writtenRoles, [.original, .editedRender])
    }

    // AGENTS-INVARIANT: 22
    func testOriginalBytesAndNameUnchangedWhenEditedExported() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "heic")],
        ])
        let original = resource("a", index: 0, ext: "heic")
        exporter.editedByAsset = ["a": editedResource("a")]
        let plan = PhotosExportPlan(entries: [entry("a", stem: "IMG_0001")])

        let off = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot)
        let offBytes = try stagedBytes(try XCTUnwrap(off.exportedFiles.first).path)
        try FileManager.default.removeItem(at: stagingRoot)

        let on = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot, includeEditedVersions: true)

        let originalFile = try XCTUnwrap(on.exportedFiles.first)
        XCTAssertEqual(URL(fileURLWithPath: originalFile.path).lastPathComponent, "IMG_0001.heic")
        XCTAssertEqual(try stagedBytes(originalFile.path), offBytes)
        XCTAssertEqual(String(decoding: offBytes, as: UTF8.self), RecordingExporter.bytes(for: original))
        let edited = try XCTUnwrap(on.editedFiles.first)
        XCTAssertEqual(String(decoding: try stagedBytes(edited.path), as: UTF8.self), RecordingExporter.bytes(for: editedResource("a")))
        XCTAssertNotEqual(edited.path, originalFile.path)
    }

    // AGENTS-INVARIANT: 22
    func testEditedStemClaimedThroughSharedUniqueSet() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "heic")],
            "b": [resource("b", index: 0, ext: "heic")],
        ])
        exporter.editedByAsset = ["a": editedResource("a", index: 3, ext: "JPG"), "b": editedResource("b", index: 3, ext: "jpg")]
        // Another asset already owns the name, differing only in case, and a
        // reserved name (a resumed import's file) takes the other.
        let plan = PhotosExportPlan(entries: [entry("a", stem: "x"), entry("b", stem: "y")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            reservedFilenames: ["X-EDITED.jpg", "y-edited.JPG"],
            includeEditedVersions: true
        )

        let names = receipt.editedFiles.map { URL(fileURLWithPath: $0.path).lastPathComponent }
        XCTAssertEqual(names, ["x-edited-3.jpg", "y-edited-3.jpg"], "Disambiguated, never the reserved name or a case variant of it")
        XCTAssertEqual(Set(try stagedNames().map(PhotosExportExecutor.nameKey)).count, 4, "No two staged files share a name key")
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    func testEditedNameDoesNotCollideWithAnotherAssetsOriginal() async throws {
        // Asset b's original is literally named like a's edited file.
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "heic")],
            "b": [resource("b", index: 0, ext: "jpg")],
        ])
        exporter.editedByAsset = ["a": editedResource("a", ext: "jpg")]
        let plan = PhotosExportPlan(entries: [entry("a", stem: "x"), entry("b", stem: "X-Edited")])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot, includeEditedVersions: true)

        XCTAssertEqual(receipt.failures, [])
        XCTAssertEqual(Set(receipt.exportedFiles.map { PhotosExportExecutor.nameKey(URL(fileURLWithPath: $0.path).lastPathComponent) }).count, 3)
        try assertStagedBytesBelongToOwnAssets(receipt)
    }

    // AGENTS-INVARIANT: 22
    func testEditedRenderFailureRecordedAndOriginalStillCompleted() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "list": [resource("list", index: 0, ext: "heic")],
            "write": [resource("write", index: 0, ext: "heic")],
            "ok": [resource("ok", index: 0, ext: "heic")],
        ])
        exporter.editedListFailures = ["list"]
        exporter.editedByAsset = ["write": editedResource("write"), "ok": editedResource("ok")]
        exporter.editedWriteFailures = ["write"]
        let plan = PhotosExportPlan(entries: [entry("list", stem: "L"), entry("write", stem: "W"), entry("ok", stem: "O")])
        let log = EventLog()

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            includeEditedVersions: true,
            onEvent: { log.append($0) }
        )

        XCTAssertEqual(receipt.failures, [], "A lost edit never fails the asset")
        XCTAssertEqual(receipt.exportedAssetIDs, ["list", "write", "ok"])
        XCTAssertEqual(try stagedNames(), ["L.heic", "O-edited.jpg", "O.heic", "W.heic"],
                       "Only the edited file is rolled back; originals and the good edit stay")
        XCTAssertEqual(receipt.variantFailures, [
            PhotosVariantFailure(assetID: "list", reason: .editedRenderUnavailable),
            PhotosVariantFailure(assetID: "write", reason: .editedRenderUnavailable),
        ])
        XCTAssertEqual(receipt.editedFiles.map(\.assetID), ["ok"])
        XCTAssertEqual(log.events.map(shape), [
            "started:list:0/3", "editedFailed:list", "completed:list:1",
            "started:write:1/3", "editedFailed:write", "completed:write:1",
            "started:ok:2/3", "editedSaved:ok", "completed:ok:2",
        ])
    }

    func testVideoAndLivePhotoEditedRendersNotExported() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "live": [resource("live", index: 0, ext: "heic"), resource("live", index: 1, ext: "mov")],
            "clip": [resource("clip", index: 0, ext: "mov")],
        ])
        // Even a (wrongly) returned render is not exported when the asset's
        // edit is unsupported.
        exporter.editedByAsset = ["live": editedResource("live")]
        exporter.unsupportedEditedAssets = ["live", "clip"]
        let plan = PhotosExportPlan(entries: [entry("live", stem: "L"), entry("clip", stem: "C", kind: .video)])
        let log = EventLog()

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(
            plan: plan,
            to: stagingRoot,
            includeEditedVersions: true,
            onEvent: { log.append($0) }
        )

        XCTAssertEqual(try stagedNames(), ["C.mov", "L.heic", "L.mov"])
        XCTAssertEqual(receipt.editedFiles, [])
        XCTAssertEqual(receipt.variantFailures, [])
        XCTAssertEqual(exporter.writtenRoles.filter { $0 == .editedRender }, [])
        XCTAssertEqual(log.events.map(shape), [
            "started:live:0/2", "editedNotIncluded:live", "completed:live:2",
            "started:clip:1/2", "editedNotIncluded:clip", "completed:clip:1",
        ])
    }

    func testSummaryCountsUnsupportedEditedVideos() async throws {
        let exporter = RecordingExporter(resourcesByAsset: [
            "live": [resource("live", index: 0, ext: "heic"), resource("live", index: 1, ext: "mov")],
            "clip": [resource("clip", index: 0, ext: "mov")],
            "still": [resource("still", index: 0, ext: "heic")],
            "plain": [resource("plain", index: 0, ext: "heic")],
        ])
        exporter.unsupportedEditedAssets = ["live", "clip"]
        exporter.editedByAsset = ["still": editedResource("still")]
        let plan = PhotosExportPlan(entries: [
            entry("live", stem: "L"), entry("clip", stem: "C", kind: .video), entry("still", stem: "S"), entry("plain", stem: "P"),
        ])

        let receipt = try await PhotosExportExecutor(exporter: exporter).export(plan: plan, to: stagingRoot, includeEditedVersions: true)

        XCTAssertEqual(receipt.editedNotIncludedCount, 2)
        XCTAssertEqual(receipt.editedFiles.map(\.assetID), ["still"])
        XCTAssertEqual(receipt.variantFailures, [])
    }

    func testEditedFileInheritsOriginalDateHint() async throws {
        let capture = Date(timeIntervalSince1970: 1_500_000_000)
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "heic")],
        ])
        exporter.editedByAsset = ["a": editedResource("a")]
        let plan = PhotosExportPlan(entries: [
            PhotosAssetExportEntry(assetID: "a", mediaKind: .photo, stagingStem: "A", creationDate: capture),
        ])

        let receipt = try await PhotosExportExecutor(
            exporter: exporter,
            timeZone: TimeZone(secondsFromGMT: 0) ?? .current
        ).export(plan: plan, to: stagingRoot, includeEditedVersions: true)

        let original = try XCTUnwrap(receipt.exportedFiles.first { !$0.path.contains("-edited") })
        let edited = try XCTUnwrap(receipt.editedFiles.first)
        let originalHint = try XCTUnwrap(receipt.sourceDateHints[SourceDateHint.pathKey(for: original.path)])
        let editedHint = try XCTUnwrap(receipt.sourceDateHints[SourceDateHint.pathKey(for: edited.path)])
        XCTAssertEqual(originalHint.resolvedDate.date, capture)
        XCTAssertEqual(editedHint.resolvedDate, originalHint.resolvedDate, "Both land in the same date folder")
        XCTAssertNotEqual(editedHint.identity, originalHint.identity, "The hint is bound to the edited file's own bytes")
    }

    // AGENTS-INVARIANT: 22
    func testCancellationRollsBackEditedFileWithItsAsset() async throws {
        let cancelFlag = CancelFlag()
        let exporter = RecordingExporter(resourcesByAsset: [
            "a": [resource("a", index: 0, ext: "heic")],
            "b": [resource("b", index: 0, ext: "heic")],
        ])
        exporter.editedByAsset = ["a": editedResource("a"), "b": editedResource("b")]
        // Cancel right after b's edited file is written: b is in flight.
        exporter.afterWrite = { resource in
            if resource.assetID == "b", resource.role == .editedRender { cancelFlag.set() }
        }
        let plan = PhotosExportPlan(entries: [entry("a", stem: "A"), entry("b", stem: "B")])
        let log = EventLog()

        do {
            _ = try await PhotosExportExecutor(exporter: exporter).export(
                plan: plan,
                to: stagingRoot,
                includeEditedVersions: true,
                isCancelled: { cancelFlag.isSet },
                onEvent: { log.append($0) }
            )
            XCTFail("expected cancellation")
        } catch is CancellationError {
            // expected
        } catch {
            XCTFail("expected CancellationError, got \(error)")
        }

        XCTAssertEqual(try stagedNames(), ["A-edited.jpg", "A.heic"], "Asset a and its edit stay; asset b, original and edit, is rolled back")
        XCTAssertEqual(log.events.map(shape), ["started:a:0/2", "editedSaved:a", "completed:a:2", "started:b:1/2"])
    }

    #if canImport(Photos)
    // AGENTS-INVARIANT: 22
    func testEditedStillTypeAcceptsOnlyFullSizePhotoAndClassifiesUnsupportedEdits() {
        XCTAssertTrue(PhotosResourceExportService.isEditedStillType(.fullSizePhoto))
        for type: PHAssetResourceType in [.photo, .video, .pairedVideo, .fullSizeVideo, .fullSizePairedVideo, .adjustmentData, .alternatePhoto] {
            XCTAssertFalse(PhotosResourceExportService.isEditedStillType(type), "\(type.rawValue)")
        }
        // An edited still alone is exportable; edited videos and Live Photos are not.
        XCTAssertFalse(PhotosResourceExportService.hasUnsupportedEditedRender(types: [.photo, .fullSizePhoto, .adjustmentData]))
        XCTAssertFalse(PhotosResourceExportService.hasUnsupportedEditedRender(types: [.photo]))
        XCTAssertTrue(PhotosResourceExportService.hasUnsupportedEditedRender(types: [.video, .fullSizeVideo, .adjustmentData]))
        XCTAssertTrue(PhotosResourceExportService.hasUnsupportedEditedRender(types: [.photo, .pairedVideo, .fullSizePhoto]))
        XCTAssertTrue(PhotosResourceExportService.hasUnsupportedEditedRender(types: [.photo, .pairedVideo, .fullSizePairedVideo]))
        XCTAssertFalse(PhotosResourceExportService.hasUnsupportedEditedRender(types: [.photo, .pairedVideo]), "An unedited Live Photo has nothing unsupported")
    }
    #endif

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
