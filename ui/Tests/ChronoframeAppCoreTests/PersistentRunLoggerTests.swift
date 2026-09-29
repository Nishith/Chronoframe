import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

/// The run log lives at a fixed name in the user-selected destination root,
/// so a planted link or hard link there must never redirect its writes.
final class PersistentRunLoggerTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("PersistentRunLogger-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeSentinel(in directory: URL) throws -> URL {
        let sentinel = directory.appendingPathComponent("sentinel-\(UUID().uuidString).txt")
        try Data("SENTINEL".utf8).write(to: sentinel)
        return sentinel
    }

    private func logURL(in destination: URL) -> URL {
        destination.appendingPathComponent(".organize_log.txt")
    }

    private func assertOpenRejected(
        _ logger: PersistentRunLogger,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try logger.open(), file: file, line: line) { error in
            XCTAssertEqual(
                error as? DestinationMetadataUnsafeError,
                DestinationMetadataUnsafeError(itemName: ".organize_log.txt"),
                "expected DestinationMetadataUnsafeError, got \(error)",
                file: file,
                line: line
            )
        }
        logger.log("must not be written anywhere")
        logger.close()
    }

    func testSymlinkedRunLogIsRejectedAndItsTargetIsUntouched() throws {
        let destination = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        try FileManager.default.createSymbolicLink(at: logURL(in: destination), withDestinationURL: sentinel)

        assertOpenRejected(PersistentRunLogger(logURL: logURL(in: destination)))

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
    }

    func testHardLinkedRunLogIsRejectedAndTheSharedFileIsUntouched() throws {
        let destination = try makeDirectory()
        let sentinel = try makeSentinel(in: destination)
        try FileManager.default.linkItem(at: sentinel, to: logURL(in: destination))

        assertOpenRejected(PersistentRunLogger(logURL: logURL(in: destination)))

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
    }

    func testNonRegularRunLogIsRejectedWithoutBlocking() throws {
        let destination = try makeDirectory()
        XCTAssertEqual(mkfifo(logURL(in: destination).path, S_IRUSR | S_IWUSR), 0)

        assertOpenRejected(PersistentRunLogger(logURL: logURL(in: destination)))
    }

    func testSocketInPlaceOfRunLogIsRejectedAsUnsafe() throws {
        // Unix socket paths are length-limited, so bind in a short directory.
        let shortDirectory = URL(fileURLWithPath: "/tmp/pl-\(UInt32.random(in: 0...UInt32.max))", isDirectory: true)
        try FileManager.default.createDirectory(at: shortDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: shortDirectory) }

        let socketDescriptor = socket(AF_UNIX, SOCK_STREAM, 0)
        XCTAssertGreaterThanOrEqual(socketDescriptor, 0)
        defer { _ = Darwin.close(socketDescriptor) }
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = logURL(in: shortDirectory).path
        _ = withUnsafeMutableBytes(of: &address.sun_path) { buffer in
            path.withCString { strncpy(buffer.baseAddress!.assumingMemoryBound(to: CChar.self), $0, buffer.count - 1) }
        }
        let bindResult = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        XCTAssertEqual(bindResult, 0)

        assertOpenRejected(PersistentRunLogger(logURL: logURL(in: shortDirectory)))
    }

    func testOpenedRunLogDoesNotStayNonBlocking() throws {
        let destination = try makeDirectory()
        let handle = try DestinationMetadataFile.openForAppending(at: logURL(in: destination))
        defer { try? handle.close() }

        XCTAssertEqual(fcntl(handle.fileDescriptor, F_GETFL) & O_NONBLOCK, 0)
    }

    func testDirectoryInPlaceOfRunLogIsRejected() throws {
        let destination = try makeDirectory()
        try FileManager.default.createDirectory(at: logURL(in: destination), withIntermediateDirectories: true)

        assertOpenRejected(PersistentRunLogger(logURL: logURL(in: destination)))
    }

    func testRunLogIsCreatedAndLaterRunsAppend() throws {
        let destination = try makeDirectory()

        let first = PersistentRunLogger(logURL: logURL(in: destination))
        try first.open()
        first.log("first run")
        first.close()

        let second = PersistentRunLogger(logURL: logURL(in: destination))
        try second.open()
        second.log("second run")
        second.close()

        let contents = try String(contentsOf: logURL(in: destination), encoding: .utf8)
        XCTAssertTrue(contents.contains("first run"), contents)
        XCTAssertTrue(contents.contains("second run"), contents)
        XCTAssertLessThan(
            try XCTUnwrap(contents.range(of: "first run")).lowerBound,
            try XCTUnwrap(contents.range(of: "second run")).lowerBound
        )
    }

    func testOversizedRunLogIsRotatedBeforeAppending() throws {
        let destination = try makeDirectory()
        let oversized = Data(repeating: UInt8(ascii: "x"), count: Int(PersistentRunLogger.maxLogBytes) + 1)
        try oversized.write(to: logURL(in: destination))

        let logger = PersistentRunLogger(logURL: logURL(in: destination))
        try logger.open()
        logger.log("after rotation")
        logger.close()

        let rotated = logURL(in: destination).appendingPathExtension("1")
        XCTAssertEqual(try Data(contentsOf: rotated).count, oversized.count)
        XCTAssertTrue(try String(contentsOf: logURL(in: destination), encoding: .utf8).contains("after rotation"))
    }

    func testUnsafeMetadataErrorIsPlainLanguage() {
        let message = DestinationMetadataUnsafeError(itemName: ".organize_log.txt").errorDescription ?? ""
        XCTAssertTrue(message.contains("“.organize_log.txt”"))
        XCTAssertTrue(message.contains("Nothing was changed"))
    }
}
