import Foundation
import XCTest
@testable import ChronoframeApp

/// Finding #8: receipt verification must not leak file descriptors when hashing
/// fails. A directory destination makes `hashIdentity` throw (a directory fd
/// can't be read → EISDIR), exercising the former leak path; with the `defer`
/// close the process descriptor count stays bounded across many failures.
final class ReceiptVerificationTests: XCTestCase {
    func testVerifyStatusClosesDescriptorEvenWhenHashingThrows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-fd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Sanity: this destination drives the throwing catch path.
        XCTAssertEqual(
            ReceiptDetailSheet.verifyStatus(forDestination: directory.path, expectedHash: "deadbeef"),
            .mismatch
        )

        let before = Self.openDescriptorCount()
        for _ in 0..<600 {
            _ = ReceiptDetailSheet.verifyStatus(forDestination: directory.path, expectedHash: "deadbeef")
        }
        let after = Self.openDescriptorCount()

        XCTAssertLessThan(
            after - before,
            50,
            "Descriptors must not grow across repeated hash failures (before=\(before), after=\(after))"
        )
    }

    func testVerifyStatusReportsMissingAndEmptyHashWithoutOpening() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).jpg")
        XCTAssertEqual(ReceiptDetailSheet.verifyStatus(forDestination: missing.path, expectedHash: "x"), .missing)

        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("present-\(UUID().uuidString).jpg")
        try Data("hi".utf8).write(to: real)
        defer { try? FileManager.default.removeItem(at: real) }
        // An empty receipt hash is treated as a match without opening the file.
        XCTAssertEqual(ReceiptDetailSheet.verifyStatus(forDestination: real.path, expectedHash: ""), .matching)
    }

    private static func openDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }
}
