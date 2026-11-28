import Foundation
import XCTest
@testable import ChronoframeCore

final class DeduplicatePairDetectorTests: XCTestCase {

    private actor RecordingMetadataLoader: LivePhotoMetadataLoading {
        private(set) var callCount = 0
        func loadIdentifiers(for movieURLs: [URL]) async -> LivePhotoMetadataBatchResult {
            callCount += 1
            return LivePhotoMetadataBatchResult()
        }

        nonisolated func cancelAll() {}
    }

    func testDetectRawJpegPairs() async {
        let paths = [
            "/dest/IMG_0001.JPG",
            "/dest/IMG_0001.CR2",
            "/dest/IMG_0002.JPG",
        ]

        let pairs = await DeduplicatePairDetector.detectPairs(in: paths, includeLivePhotos: false)

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs["/dest/IMG_0001.JPG"]?.primaryPath, "/dest/IMG_0001.CR2")
        XCTAssertEqual(pairs["/dest/IMG_0001.JPG"]?.secondaryPath, "/dest/IMG_0001.JPG")
        XCTAssertEqual(pairs["/dest/IMG_0001.JPG"]?.kind, .rawJpeg)
        XCTAssertEqual(pairs["/dest/IMG_0001.CR2"]?.primaryPath, "/dest/IMG_0001.CR2")
        XCTAssertEqual(pairs["/dest/IMG_0001.CR2"]?.secondaryPath, "/dest/IMG_0001.JPG")
        XCTAssertEqual(pairs["/dest/IMG_0001.CR2"]?.kind, .rawJpeg)
    }

    func testDetectsAdvertisedCr3AndRw2RawPairs() async {
        let paths = [
            "/dest/canon/IMG_1001.CR3",
            "/dest/canon/IMG_1001.JPG",
            "/dest/panasonic/P1000420.RW2",
            "/dest/panasonic/P1000420.jpeg",
        ]

        let pairs = await DeduplicatePairDetector.detectPairs(in: paths, includeLivePhotos: false)

        XCTAssertEqual(pairs["/dest/canon/IMG_1001.CR3"]?.secondaryPath, "/dest/canon/IMG_1001.JPG")
        XCTAssertEqual(pairs["/dest/canon/IMG_1001.JPG"]?.primaryPath, "/dest/canon/IMG_1001.CR3")
        XCTAssertEqual(pairs["/dest/panasonic/P1000420.RW2"]?.secondaryPath, "/dest/panasonic/P1000420.jpeg")
        XCTAssertEqual(pairs["/dest/panasonic/P1000420.jpeg"]?.primaryPath, "/dest/panasonic/P1000420.RW2")
    }

    func testLivePhotoPairingDisabledDoesNotLoadMovieMetadata() async {
        let loader = RecordingMetadataLoader()
        _ = await DeduplicatePairDetector.detectPairs(
            in: ["/dest/IMG.HEIC", "/dest/IMG.MOV"],
            includeLivePhotos: false,
            movieMetadataLoader: loader
        )
        let callCount = await loader.callCount
        XCTAssertEqual(callCount, 0)
    }

    // MARK: - Sidecar detection (PR D)

    /// Runs `body` with `sidecarFileExists` reporting exactly `existing` as
    /// present, then restores the production probe.
    private func withSidecars(_ existing: Set<String>, _ body: () -> Void) {
        let original = DeduplicatePairDetector.sidecarFileExists
        defer { DeduplicatePairDetector.sidecarFileExists = original }
        DeduplicatePairDetector.sidecarFileExists = { existing.contains($0) }
        body()
    }

    func testDetectSidecarsMatchesReplacedAndAppendedExtensionForms() {
        // photo.xmp (replaced) for the RAW, IMG_0002.JPG.xmp (appended) for the JPEG.
        withSidecars(["/dest/IMG_0001.xmp", "/dest/IMG_0002.JPG.xmp"]) {
            let sidecars = DeduplicatePairDetector.detectSidecars(for: [
                "/dest/IMG_0001.CR2",
                "/dest/IMG_0002.JPG",
                "/dest/IMG_0003.JPG", // no sidecar on disk
            ])
            XCTAssertEqual(sidecars["/dest/IMG_0001.CR2"], ["/dest/IMG_0001.xmp"])
            XCTAssertEqual(sidecars["/dest/IMG_0002.JPG"], ["/dest/IMG_0002.JPG.xmp"])
            XCTAssertNil(sidecars["/dest/IMG_0003.JPG"])
        }
    }

    func testDetectSidecarsSharesABasenameSidecarAcrossRawAndJpeg() {
        // A single IMG_0001.xmp is the sidecar for both halves of the pair.
        withSidecars(["/dest/IMG_0001.xmp"]) {
            let sidecars = DeduplicatePairDetector.detectSidecars(for: [
                "/dest/IMG_0001.CR2",
                "/dest/IMG_0001.JPG",
            ])
            XCTAssertEqual(sidecars["/dest/IMG_0001.CR2"], ["/dest/IMG_0001.xmp"])
            XCTAssertEqual(sidecars["/dest/IMG_0001.JPG"], ["/dest/IMG_0001.xmp"])
        }
    }

    func testDetectSidecarsReturnsEmptyWhenNoneOnDisk() {
        withSidecars([]) {
            let sidecars = DeduplicatePairDetector.detectSidecars(for: ["/dest/IMG_0001.JPG"])
            XCTAssertTrue(sidecars.isEmpty)
        }
    }

    // MARK: - .aae sidecars (edit preservation WP-02)

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeduplicatePairDetectorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: directory) }
        return directory
    }

    private func touch(_ names: [String], in directory: URL) throws {
        for name in names {
            XCTAssertTrue(
                FileManager.default.createFile(atPath: directory.appendingPathComponent(name).path, contents: Data("x".utf8))
            )
        }
    }

    // AGENTS-INVARIANT: 14
    func testAAEReplacedExtensionFormIsDetected() throws {
        let directory = try makeTemporaryDirectory()
        try touch(["IMG_0001.HEIC", "IMG_0001.AAE"], in: directory)

        let media = directory.appendingPathComponent("IMG_0001.HEIC").path
        let sidecars = DeduplicatePairDetector.detectSidecars(for: [media])

        // Returned with the on-disk spelling (iPhone writes `.AAE`).
        XCTAssertEqual(sidecars[media], [directory.appendingPathComponent("IMG_0001.AAE").path])
    }

    // AGENTS-INVARIANT: 14
    func testAAEAppendedExtensionFormIsDetected() throws {
        let directory = try makeTemporaryDirectory()
        try touch(["IMG_0002.HEIC", "IMG_0002.HEIC.AAE"], in: directory)

        let media = directory.appendingPathComponent("IMG_0002.HEIC").path
        let sidecars = DeduplicatePairDetector.detectSidecars(for: [media])

        XCTAssertEqual(sidecars[media], [directory.appendingPathComponent("IMG_0002.HEIC.AAE").path])
    }

    // AGENTS-INVARIANT: 14
    func testIMGEDigitsMapToEditedAAEExactly() throws {
        let directory = try makeTemporaryDirectory()
        try touch(["IMG_1234.HEIC", "IMG_E1234.AAE", "IMG_1234.JPG"], in: directory)

        let heic = directory.appendingPathComponent("IMG_1234.HEIC").path
        let jpg = directory.appendingPathComponent("IMG_1234.JPG").path
        let edited = directory.appendingPathComponent("IMG_E1234.AAE").path
        let sidecars = DeduplicatePairDetector.detectSidecars(for: [heic, jpg])

        XCTAssertEqual(sidecars[heic], [edited])
        // The edited sidecar is shared by every owner with the same digits.
        XCTAssertEqual(sidecars[jpg], [edited])
    }

    // AGENTS-INVARIANT: 14
    func testIMGEDoesNotMatchDifferentDigits() throws {
        let directory = try makeTemporaryDirectory()
        try touch(
            ["IMG_123.HEIC", "IMG_1234.HEIC", "IMG_E1234.AAE"],
            in: directory
        )

        let shorter = directory.appendingPathComponent("IMG_123.HEIC").path
        let exact = directory.appendingPathComponent("IMG_1234.HEIC").path
        let sidecars = DeduplicatePairDetector.detectSidecars(for: [shorter, exact])

        XCTAssertNil(sidecars[shorter], "IMG_123 must not own IMG_E1234.AAE (prefix)")
        XCTAssertEqual(sidecars[exact], [directory.appendingPathComponent("IMG_E1234.AAE").path])

        // A longer digit string must not claim the shorter edit sidecar either.
        let otherDirectory = try makeTemporaryDirectory()
        try touch(["IMG_12345.HEIC", "IMG_E1234.AAE"], in: otherDirectory)
        let longer = otherDirectory.appendingPathComponent("IMG_12345.HEIC").path
        XCTAssertNil(
            DeduplicatePairDetector.detectSidecars(for: [longer])[longer],
            "IMG_12345 must not own IMG_E1234.AAE (substring)"
        )

        // An edit sidecar in a different directory is never matched.
        let elsewhere = try makeTemporaryDirectory()
        try touch(["IMG_1234.HEIC"], in: elsewhere)
        let lonely = elsewhere.appendingPathComponent("IMG_1234.HEIC").path
        XCTAssertNil(DeduplicatePairDetector.detectSidecars(for: [lonely])[lonely])
    }

    // AGENTS-INVARIANT: 14
    func testXMPBehaviorUnchanged() {
        // Fake directory: `.xmp` is probed through `sidecarFileExists` exactly
        // as before (replaced form, then appended form) and `.aae` adds no probes.
        let existing: Set<String> = ["/dest/A.xmp", "/dest/A.JPG.xmp", "/dest/B.JPG.xmp"]
        let probed = LockedProbeLog()
        let original = DeduplicatePairDetector.sidecarFileExists
        defer { DeduplicatePairDetector.sidecarFileExists = original }
        DeduplicatePairDetector.sidecarFileExists = { path in
            probed.append(path)
            return existing.contains(path)
        }

        let sidecars = DeduplicatePairDetector.detectSidecars(for: ["/dest/A.JPG", "/dest/B.JPG"])

        XCTAssertEqual(sidecars["/dest/A.JPG"], ["/dest/A.xmp", "/dest/A.JPG.xmp"])
        XCTAssertEqual(sidecars["/dest/B.JPG"], ["/dest/B.JPG.xmp"])
        XCTAssertEqual(
            probed.values,
            ["/dest/A.xmp", "/dest/A.JPG.xmp", "/dest/B.xmp", "/dest/B.JPG.xmp"]
        )
    }

    private final class LockedProbeLog: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        func append(_ value: String) { lock.lock(); storage.append(value); lock.unlock() }
        var values: [String] { lock.lock(); defer { lock.unlock() }; return storage }
    }
}
