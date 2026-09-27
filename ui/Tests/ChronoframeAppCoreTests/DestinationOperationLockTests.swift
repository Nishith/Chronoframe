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

    private func makeSentinel(in directory: URL, contents: String = "SENTINEL") throws -> URL {
        let sentinel = directory.appendingPathComponent("sentinel-\(UUID().uuidString).txt")
        try Data(contents.utf8).write(to: sentinel)
        return sentinel
    }

    private func lockURL(in destination: URL) -> URL {
        destination
            .appendingPathComponent(".organize_logs", isDirectory: true)
            .appendingPathComponent(DestinationOperationLock.filename)
    }

    private func assertUnsafeLockRejected(
        _ destination: URL,
        offendingName: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "test host",
            operation: "transfer"
        ), file: file, line: line) { error in
            let unsafe = error as? DestinationLockUnsafeError
            XCTAssertNotNil(unsafe, "expected DestinationLockUnsafeError, got \(error)", file: file, line: line)
            XCTAssertEqual(unsafe?.itemName, offendingName, file: file, line: line)
        }
    }

    // AGENTS-INVARIANT: 19
    func testSymlinkedLockFileIsRejectedAndItsTargetIsUntouched() throws {
        let destination = try makeDestination()
        let outside = try makeDestination()
        let sentinel = try makeSentinel(in: outside)
        try FileManager.default.createDirectory(
            at: lockURL(in: destination).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: lockURL(in: destination), withDestinationURL: sentinel)

        assertUnsafeLockRejected(destination, offendingName: DestinationOperationLock.filename)
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
    }

    // AGENTS-INVARIANT: 19
    func testSymlinkedLogsDirectoryIsRejectedAndNothingIsWrittenThroughIt() throws {
        let destination = try makeDestination()
        let outside = try makeDestination()
        try FileManager.default.createSymbolicLink(
            at: destination.appendingPathComponent(".organize_logs", isDirectory: true),
            withDestinationURL: outside
        )

        assertUnsafeLockRejected(destination, offendingName: ".organize_logs")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: outside.path), [])
    }

    // AGENTS-INVARIANT: 19
    func testHardLinkedLockFileIsRejectedAndTheSharedFileIsUntouched() throws {
        let destination = try makeDestination()
        let sentinel = try makeSentinel(in: destination)
        try FileManager.default.createDirectory(
            at: lockURL(in: destination).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.linkItem(at: sentinel, to: lockURL(in: destination))

        assertUnsafeLockRejected(destination, offendingName: DestinationOperationLock.filename)
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
    }

    // AGENTS-INVARIANT: 19
    func testNonRegularLockFileIsRejectedWithoutBlocking() throws {
        let destination = try makeDestination()
        try FileManager.default.createDirectory(
            at: lockURL(in: destination).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        XCTAssertEqual(mkfifo(lockURL(in: destination).path, S_IRUSR | S_IWUSR), 0)

        assertUnsafeLockRejected(destination, offendingName: DestinationOperationLock.filename)
    }

    // AGENTS-INVARIANT: 19
    func testRegularFileInPlaceOfLogsDirectoryIsRejected() throws {
        let destination = try makeDestination()
        try Data("not a directory".utf8).write(
            to: destination.appendingPathComponent(".organize_logs", isDirectory: false)
        )

        assertUnsafeLockRejected(destination, offendingName: ".organize_logs")
    }

    // AGENTS-INVARIANT: 19
    func testFifoInPlaceOfLogsDirectoryIsRejected() throws {
        let destination = try makeDestination()
        let logsPath = destination.appendingPathComponent(".organize_logs", isDirectory: false).path
        XCTAssertEqual(mkfifo(logsPath, S_IRUSR | S_IWUSR), 0)

        assertUnsafeLockRejected(destination, offendingName: ".organize_logs")
    }

    func testDirectoryInPlaceOfLockFileIsRejected() throws {
        let destination = try makeDestination()
        try FileManager.default.createDirectory(at: lockURL(in: destination), withIntermediateDirectories: true)

        assertUnsafeLockRejected(destination, offendingName: DestinationOperationLock.filename)
    }

    func testExistingRegularLockFileFromAnEarlierRunIsReused() throws {
        let destination = try makeDestination()
        try FileManager.default.createDirectory(
            at: lockURL(in: destination).deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("stale diagnostic".utf8).write(to: lockURL(in: destination))

        let lease = try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "test host",
            operation: "transfer"
        )
        defer { lease.release() }
        let data = try Data(contentsOf: lockURL(in: destination))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        XCTAssertEqual(try decoder.decode(DestinationOperationDiagnostic.self, from: data).operation, "transfer")
    }

    func testUnsafeLockErrorIsPlainLanguage() {
        let message = DestinationLockUnsafeError(itemName: ".organize_logs").errorDescription ?? ""
        XCTAssertTrue(message.contains("“.organize_logs”"))
        XCTAssertTrue(message.contains("Nothing was changed"))
    }

    func testIsRemoteVolumeTreatsUnknownVolumeAsLocal() throws {
        // A path that does not exist has no readable volume attribute; the
        // helper must fail toward "local" so the app never warns spuriously.
        let missing = URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)/folder", isDirectory: true)
        XCTAssertFalse(DestinationOperationLock.isRemoteVolume(missing))

        // A real local temp directory is local.
        let local = try makeDestination()
        XCTAssertFalse(DestinationOperationLock.isRemoteVolume(local))
    }

    func testIsRemoteVolumeHonorsDebugProviderSeam() throws {
        let destination = try makeDestination()
        DestinationOperationLock.isRemoteVolumeProvider = { _ in true }
        defer { DestinationOperationLock.isRemoteVolumeProvider = nil }
        XCTAssertTrue(DestinationOperationLock.isRemoteVolume(destination))
    }
}
