import Foundation
import XCTest
@testable import ChronoframeCore

final class DestinationOperationLockTests: XCTestCase {
    private func makeDestination() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DestinationLock-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    // AGENTS-INVARIANT: 19
    func testSecondLeaseFailsImmediatelyWithOwnerDiagnostic() throws {
        let destination = try makeDestination()
        let first = try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "test host",
            operation: "transfer"
        )
        defer { first.release() }

        XCTAssertThrowsError(try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "second host",
            operation: "deduplicate"
        )) { error in
            let busy = error as? DestinationBusyError
            XCTAssertEqual(busy?.diagnostic?.surface, "test host")
            XCTAssertEqual(busy?.diagnostic?.operation, "transfer")
        }
    }

    func testMalformedDiagnosticFallsBackToGenericBusyMessage() throws {
        let destination = try makeDestination()
        let first = try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "test host",
            operation: "transfer"
        )
        defer { first.release() }
        let lockURL = destination
            .appendingPathComponent(".organize_logs", isDirectory: true)
            .appendingPathComponent(DestinationOperationLock.filename)
        let handle = try FileHandle(forWritingTo: lockURL)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("{".utf8))
        try handle.synchronize()
        try handle.close()

        XCTAssertThrowsError(try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "second host",
            operation: "deduplicate"
        )) { error in
            let busy = error as? DestinationBusyError
            XCTAssertNil(busy?.diagnostic)
            XCTAssertEqual(
                busy?.errorDescription,
                "Another Chronoframe operation is already using this destination. Wait for it to finish, then try again."
            )
        }
    }

    func testExplicitReleaseIsIdempotentAndDeinitReleasesDescriptor() throws {
        let destination = try makeDestination()
        var lease: DestinationOperationLease? = try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "test host",
            operation: "preview"
        )
        lease?.release()
        lease?.release()
        lease = nil

        let next = try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "test host",
            operation: "transfer"
        )
        next.release()
    }
}
