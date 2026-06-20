import Foundation
import XCTest
@testable import ChronoframeCore

final class DeduplicatePairDetectorTests: XCTestCase {

    func testDetectRawJpegPairs() {
        let paths = [
            "/dest/IMG_0001.JPG",
            "/dest/IMG_0001.CR2",
            "/dest/IMG_0002.JPG",
        ]

        let pairs = DeduplicatePairDetector.detectPairs(in: paths)

        XCTAssertEqual(pairs.count, 2)
        XCTAssertEqual(pairs["/dest/IMG_0001.JPG"]?.primaryPath, "/dest/IMG_0001.CR2")
        XCTAssertEqual(pairs["/dest/IMG_0001.JPG"]?.secondaryPath, "/dest/IMG_0001.JPG")
        XCTAssertEqual(pairs["/dest/IMG_0001.JPG"]?.kind, .rawJpeg)
        XCTAssertEqual(pairs["/dest/IMG_0001.CR2"]?.primaryPath, "/dest/IMG_0001.CR2")
        XCTAssertEqual(pairs["/dest/IMG_0001.CR2"]?.secondaryPath, "/dest/IMG_0001.JPG")
        XCTAssertEqual(pairs["/dest/IMG_0001.CR2"]?.kind, .rawJpeg)
    }

    func testDetectsAdvertisedCr3AndRw2RawPairs() {
        let paths = [
            "/dest/canon/IMG_1001.CR3",
            "/dest/canon/IMG_1001.JPG",
            "/dest/panasonic/P1000420.RW2",
            "/dest/panasonic/P1000420.jpeg",
        ]

        let pairs = DeduplicatePairDetector.detectPairs(in: paths)

        XCTAssertEqual(pairs["/dest/canon/IMG_1001.CR3"]?.secondaryPath, "/dest/canon/IMG_1001.JPG")
        XCTAssertEqual(pairs["/dest/canon/IMG_1001.JPG"]?.primaryPath, "/dest/canon/IMG_1001.CR3")
        XCTAssertEqual(pairs["/dest/panasonic/P1000420.RW2"]?.secondaryPath, "/dest/panasonic/P1000420.jpeg")
        XCTAssertEqual(pairs["/dest/panasonic/P1000420.jpeg"]?.primaryPath, "/dest/panasonic/P1000420.RW2")
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
}
