import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

/// Wrapper so the bare `stat` struct name stays usable in the test class.
private func lstatPath(_ path: UnsafePointer<CChar>, _ status: inout stat) -> Int32 {
    lstat(path, &status)
}

/// Thread-safe counter used by the injected system-call seams.
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    @discardableResult
    func increment() -> Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

final class ChronoframeCoreNASMeteredFileReaderTests: XCTestCase {
    private typealias Reader = NASMeteredFileReader
    private typealias Calls = NASMeteredFileReader.SystemCalls

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASMeteredFileReaderTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    // MARK: - Fixtures

    private func makeFile(named name: String = UUID().uuidString, size: Int) throws -> URL {
        let url = tempRoot.appendingPathComponent(name)
        var bytes = [UInt8](repeating: 0, count: size)
        for index in 0..<size {
            bytes[index] = UInt8(truncatingIfNeeded: (index &* 31) &+ (index >> 8) &+ 7)
        }
        try Data(bytes).write(to: url)
        return url
    }

    private func metadata(of url: URL) -> (size: Int64, modificationTime: TimeInterval) {
        var status = stat()
        let result = url.path.withCString { lstatPath($0, &status) }
        XCTAssertEqual(result, 0)
        let mtime = TimeInterval(status.st_mtimespec.tv_sec)
            + TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000
        return (Int64(status.st_size), mtime)
    }

    private func counters(of outcome: NASHashOutcome) -> NASReadCounters {
        switch outcome {
        case let .hashed(_, _, counters): return counters
        case let .unresolved(_, _, counters): return counters
        }
    }

    private func unresolved(_ outcome: NASHashOutcome) -> (NASUnresolvedReason, Int32?, NASReadCounters)? {
        if case let .unresolved(reason, code, counters) = outcome {
            return (reason, code, counters)
        }
        return nil
    }

    /// Runs the live reader against a real file, wrapping the live seams.
    private func run(
        url: URL,
        expectedSize: Int64? = nil,
        expectedModificationTime: TimeInterval? = nil,
        customize: (inout Calls) -> Void = { _ in }
    ) -> NASHashOutcome {
        let meta = metadata(of: url)
        var calls = Calls.live
        customize(&calls)
        return Reader(systemCalls: calls).hash(
            path: url.path,
            expectedSize: expectedSize ?? meta.size,
            expectedModificationTime: expectedModificationTime ?? meta.modificationTime
        )
    }

    // MARK: - Tests

    func testDigestMatchesFileIdentityHasherForBoundarySizes() throws {
        let mib = 1024 * 1024
        for size in [1, mib - 1, mib, mib + 1, 3 * mib + 7] {
            let url = try makeFile(size: size)
            let expected = try FileIdentityHasher().hashIdentity(at: url)
            let outcome = run(url: url)
            guard case let .hashed(identity, modificationTime, counters) = outcome else {
                XCTFail("size \(size): expected hashed, got \(outcome)")
                continue
            }
            XCTAssertEqual(identity, expected, "size \(size)")
            XCTAssertEqual(identity.digest, expected.digest, "size \(size)")
            XCTAssertEqual(identity.size, Int64(size))
            XCTAssertEqual(counters.bytesRead, Int64(size))
            XCTAssertEqual(modificationTime, metadata(of: url).modificationTime, accuracy: 0.001)
        }
    }

    func testCountsExactlyFileSizeBytes() throws {
        let size = 2 * 1024 * 1024 + 123
        let url = try makeFile(size: size)
        let outcome = run(url: url)
        guard case let .hashed(_, _, counters) = outcome else {
            return XCTFail("expected hashed, got \(outcome)")
        }
        XCTAssertEqual(counters.bytesRead, Int64(size))
        // 2 full chunks + 1 partial chunk + 1 EOF read.
        XCTAssertEqual(counters.readCalls, 4)
    }

    func testShortReadsAreCountedByReturnedBytes() throws {
        let size = 10_500
        let url = try makeFile(size: size)
        let expected = try FileIdentityHasher().hashIdentity(at: url)
        let issued = Counter()
        let outcome = run(url: url) { calls in
            let liveRead = calls.read
            calls.read = { fd, buffer, count in
                issued.increment()
                return liveRead(fd, buffer, min(count, 1000))
            }
        }
        guard case let .hashed(identity, _, counters) = outcome else {
            return XCTFail("expected hashed, got \(outcome)")
        }
        XCTAssertEqual(identity, expected)
        XCTAssertEqual(counters.bytesRead, Int64(size))
        XCTAssertEqual(counters.readCalls, 12) // 10 full + 1 partial (500) + EOF
        XCTAssertEqual(counters.readCalls, issued.count)
    }

    func testEINTRIsRetried() throws {
        let size = 5000
        let url = try makeFile(size: size)
        let expected = try FileIdentityHasher().hashIdentity(at: url)
        let reads = Counter()
        let outcome = run(url: url) { calls in
            let liveRead = calls.read
            calls.read = { fd, buffer, count in
                if reads.increment() == 1 { return -1 }
                return liveRead(fd, buffer, count)
            }
            let liveLastError = calls.lastError
            calls.lastError = { reads.count == 1 ? EINTR : liveLastError() }
        }
        guard case let .hashed(identity, _, counters) = outcome else {
            return XCTFail("expected hashed, got \(outcome)")
        }
        XCTAssertEqual(identity, expected)
        XCTAssertEqual(counters.bytesRead, Int64(size))
        XCTAssertEqual(counters.readCalls, 3) // EINTR + data + EOF
    }

    func testSizeChangedBeforeReadIsUnresolvedWithZeroBytes() throws {
        let url = try makeFile(size: 4000)
        let meta = metadata(of: url)
        let reads = Counter()
        let outcome = run(url: url, expectedSize: meta.size - 1) { calls in
            let liveRead = calls.read
            calls.read = { fd, buffer, count in
                reads.increment()
                return liveRead(fd, buffer, count)
            }
        }
        let result = unresolved(outcome)
        XCTAssertEqual(result?.0, .sizeChangedBeforeRead)
        XCTAssertNil(result?.1)
        XCTAssertEqual(result?.2, NASReadCounters())
        XCTAssertEqual(reads.count, 0)
    }

    func testGrowthDuringReadIsBytesConsumedMismatch() throws {
        let url = try makeFile(size: 5000)
        let outcome = run(url: url, expectedSize: 3000) { calls in
            let liveFstat = calls.fstat
            calls.fstat = { fd in
                guard var stat = liveFstat(fd) else { return nil }
                stat.size = 3000 // descriptor claims the expected size; file really has more
                return stat
            }
            let liveRead = calls.read
            calls.read = { fd, buffer, count in liveRead(fd, buffer, min(count, 1000)) }
        }
        let result = unresolved(outcome)
        XCTAssertEqual(result?.0, .bytesConsumedMismatch)
        XCTAssertNil(result?.1)
        // Stops as soon as bytesRead exceeds the expected size: 4 reads of 1000.
        XCTAssertEqual(result?.2, NASReadCounters(bytesRead: 4000, readCalls: 4))
    }

    func testTruncationDuringReadIsUnresolved() throws {
        let url = try makeFile(size: 3000)
        let outcome = run(url: url, expectedSize: 5000) { calls in
            let liveFstat = calls.fstat
            calls.fstat = { fd in
                guard var stat = liveFstat(fd) else { return nil }
                stat.size = 5000 // descriptor claims more than the file holds: early EOF
                return stat
            }
        }
        let result = unresolved(outcome)
        XCTAssertEqual(result?.0, .bytesConsumedMismatch)
        XCTAssertNil(result?.1)
        XCTAssertEqual(result?.2, NASReadCounters(bytesRead: 3000, readCalls: 2))
    }

    func testPostReadSizeChangeIsUnresolved() throws {
        let size = 4000
        let url = try makeFile(size: size)
        let stats = Counter()
        let outcome = run(url: url) { calls in
            let liveFstat = calls.fstat
            calls.fstat = { fd in
                guard var stat = liveFstat(fd) else { return nil }
                if stats.increment() >= 2 { stat.size += 1 }
                return stat
            }
        }
        let result = unresolved(outcome)
        XCTAssertEqual(result?.0, .sizeChangedDuringRead)
        XCTAssertNil(result?.1)
        XCTAssertEqual(result?.2.bytesRead, Int64(size))
    }

    func testModificationTimeChangeIsUnresolved() throws {
        let url = try makeFile(size: 4000)
        let meta = metadata(of: url)

        // Before read: enumerated mtime differs from the descriptor's.
        let beforeReads = Counter()
        let before = run(url: url, expectedModificationTime: meta.modificationTime + 5) { calls in
            let liveRead = calls.read
            calls.read = { fd, buffer, count in
                beforeReads.increment()
                return liveRead(fd, buffer, count)
            }
        }
        let beforeResult = unresolved(before)
        XCTAssertEqual(beforeResult?.0, .modificationTimeChanged)
        XCTAssertNil(beforeResult?.1)
        XCTAssertEqual(beforeResult?.2, NASReadCounters())
        XCTAssertEqual(beforeReads.count, 0)

        // During read: second fstat reports a new mtime.
        let stats = Counter()
        let during = run(url: url) { calls in
            let liveFstat = calls.fstat
            calls.fstat = { fd in
                guard var stat = liveFstat(fd) else { return nil }
                if stats.increment() >= 2 { stat.modificationTime += 2 }
                return stat
            }
        }
        let duringResult = unresolved(during)
        XCTAssertEqual(duringResult?.0, .modificationTimeChanged)
        XCTAssertNil(duringResult?.1)
        XCTAssertEqual(duringResult?.2.bytesRead, 4000)

        // Differences under 1 ms are tolerated.
        let tolerated = run(url: url, expectedModificationTime: meta.modificationTime + 0.0004)
        if case .hashed = tolerated {} else { XCTFail("sub-millisecond difference should hash: \(tolerated)") }
    }

    func testSymlinkIsNotFollowed() throws {
        let target = try makeFile(named: "target.bin", size: 2000)
        let link = tempRoot.appendingPathComponent("link.bin")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let meta = metadata(of: target)

        let outcome = Reader().hash(
            path: link.path,
            expectedSize: meta.size,
            expectedModificationTime: meta.modificationTime
        )
        let result = unresolved(outcome)
        XCTAssertEqual(result?.0, .openFailed)
        XCTAssertEqual(result?.1, ELOOP)
        XCTAssertEqual(result?.2, NASReadCounters())
    }

    func testVolumeUnavailableErrnoMapping() throws {
        let url = try makeFile(size: 4000)

        // open ENOTCONN -> volumeUnavailable
        var openCalls = Calls.live
        openCalls.open = { _ in -1 }
        openCalls.lastError = { ENOTCONN }
        let openOutcome = Reader(systemCalls: openCalls).hash(path: url.path, expectedSize: 4000, expectedModificationTime: 0)
        let openResult = unresolved(openOutcome)
        XCTAssertEqual(openResult?.0, .volumeUnavailable)
        XCTAssertEqual(openResult?.1, ENOTCONN)
        XCTAssertEqual(openResult?.2, NASReadCounters())

        // open with a non-volume errno -> openFailed
        openCalls.lastError = { EACCES }
        let deniedResult = unresolved(Reader(systemCalls: openCalls).hash(path: url.path, expectedSize: 4000, expectedModificationTime: 0))
        XCTAssertEqual(deniedResult?.0, .openFailed)
        XCTAssertEqual(deniedResult?.1, EACCES)

        // read ETIMEDOUT -> volumeUnavailable (counters so far retained)
        let timeout = run(url: url) { calls in
            calls.read = { _, _, _ in -1 }
            calls.lastError = { ETIMEDOUT }
        }
        let timeoutResult = unresolved(timeout)
        XCTAssertEqual(timeoutResult?.0, .volumeUnavailable)
        XCTAssertEqual(timeoutResult?.1, ETIMEDOUT)
        XCTAssertEqual(timeoutResult?.2, NASReadCounters(bytesRead: 0, readCalls: 1))

        // read EIO -> readFailed
        let io = run(url: url) { calls in
            calls.read = { _, _, _ in -1 }
            calls.lastError = { EIO }
        }
        let ioResult = unresolved(io)
        XCTAssertEqual(ioResult?.0, .readFailed)
        XCTAssertEqual(ioResult?.1, EIO)

        // The documented set is exactly the contract's.
        XCTAssertEqual(
            Reader.volumeUnavailableErrorCodes,
            [ENXIO, ENOTCONN, ETIMEDOUT, ESTALE, ENODEV, EHOSTDOWN, EHOSTUNREACH, ENETDOWN, ENETUNREACH]
        )
        XCTAssertEqual(Reader.chunkByteCount, 1024 * 1024)
    }

    func testDescriptorClosedExactlyOnceOnEveryPath() throws {
        let url = try makeFile(size: 5000)
        let directory = tempRoot.appendingPathComponent("a-directory", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let meta = metadata(of: url)

        struct Scenario {
            var name: String
            var path: String
            var expectedSize: Int64
            var expectedMTime: TimeInterval
            var customize: (inout Calls) -> Void
            var expectOpenSucceeds: Bool
        }

        let scenarios: [Scenario] = [
            Scenario(name: "success", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { _ in }, expectOpenSucceeds: true),
            Scenario(name: "sizeChangedBeforeRead", path: url.path, expectedSize: meta.size + 1, expectedMTime: meta.modificationTime, customize: { _ in }, expectOpenSucceeds: true),
            Scenario(name: "mtimeBeforeRead", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime + 9, customize: { _ in }, expectOpenSucceeds: true),
            Scenario(name: "notRegular", path: directory.path, expectedSize: 0, expectedMTime: 0, customize: { _ in }, expectOpenSucceeds: true),
            Scenario(name: "preFstatNil", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { $0.fstat = { _ in nil } }, expectOpenSucceeds: true),
            Scenario(name: "readEIO", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { $0.read = { _, _, _ in -1 }; $0.lastError = { EIO } }, expectOpenSucceeds: true),
            Scenario(name: "readTimeout", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { $0.read = { _, _, _ in -1 }; $0.lastError = { ETIMEDOUT } }, expectOpenSucceeds: true),
            Scenario(name: "growth", path: url.path, expectedSize: 3000, expectedMTime: meta.modificationTime, customize: { calls in
                let liveFstat = calls.fstat
                calls.fstat = { fd in
                    guard var stat = liveFstat(fd) else { return nil }
                    stat.size = 3000
                    return stat
                }
            }, expectOpenSucceeds: true),
            Scenario(name: "truncation", path: url.path, expectedSize: 9000, expectedMTime: meta.modificationTime, customize: { calls in
                let liveFstat = calls.fstat
                calls.fstat = { fd in
                    guard var stat = liveFstat(fd) else { return nil }
                    stat.size = 9000
                    return stat
                }
            }, expectOpenSucceeds: true),
            Scenario(name: "postSizeChange", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { calls in
                let liveFstat = calls.fstat
                let stats = Counter()
                calls.fstat = { fd in
                    guard var stat = liveFstat(fd) else { return nil }
                    if stats.increment() >= 2 { stat.size += 1 }
                    return stat
                }
            }, expectOpenSucceeds: true),
            Scenario(name: "postFstatNil", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { calls in
                let liveFstat = calls.fstat
                let stats = Counter()
                calls.fstat = { fd in stats.increment() >= 2 ? nil : liveFstat(fd) }
            }, expectOpenSucceeds: true),
            Scenario(name: "postMtimeChange", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { calls in
                let liveFstat = calls.fstat
                let stats = Counter()
                calls.fstat = { fd in
                    guard var stat = liveFstat(fd) else { return nil }
                    if stats.increment() >= 2 { stat.modificationTime += 3 }
                    return stat
                }
            }, expectOpenSucceeds: true),
            Scenario(name: "openENOENT", path: tempRoot.appendingPathComponent("missing").path, expectedSize: 1, expectedMTime: 0, customize: { _ in }, expectOpenSucceeds: false),
            Scenario(name: "openENOTCONN", path: url.path, expectedSize: meta.size, expectedMTime: meta.modificationTime, customize: { $0.open = { _ in -1 }; $0.lastError = { ENOTCONN } }, expectOpenSucceeds: false),
        ]

        for scenario in scenarios {
            let opens = Counter()
            let closes = Counter()
            var calls = Calls.live
            let liveOpen = calls.open
            let liveClose = calls.close
            calls.open = { path in
                let fd = liveOpen(path)
                if fd >= 0 { opens.increment() }
                return fd
            }
            calls.close = { fd in
                closes.increment()
                liveClose(fd)
            }
            scenario.customize(&calls)

            _ = Reader(systemCalls: calls).hash(
                path: scenario.path,
                expectedSize: scenario.expectedSize,
                expectedModificationTime: scenario.expectedMTime
            )

            if scenario.expectOpenSucceeds {
                XCTAssertEqual(opens.count, 1, "\(scenario.name): opens")
                XCTAssertEqual(closes.count, 1, "\(scenario.name): closes")
            } else {
                XCTAssertEqual(closes.count, 0, "\(scenario.name): close after failed open")
            }
        }
    }

    func testNonRegularFileIsUnresolved() throws {
        let directory = tempRoot.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let meta = metadata(of: directory)

        let reads = Counter()
        var calls = Calls.live
        let liveRead = calls.read
        calls.read = { fd, buffer, count in
            reads.increment()
            return liveRead(fd, buffer, count)
        }
        let outcome = Reader(systemCalls: calls).hash(
            path: directory.path,
            expectedSize: meta.size,
            expectedModificationTime: meta.modificationTime
        )
        let result = unresolved(outcome)
        XCTAssertEqual(result?.0, .notRegularFile)
        XCTAssertNil(result?.1)
        XCTAssertEqual(result?.2, NASReadCounters())
        XCTAssertEqual(reads.count, 0)
    }
}
