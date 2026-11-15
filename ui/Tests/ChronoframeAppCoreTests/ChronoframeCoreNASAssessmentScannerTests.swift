import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

// MARK: - Test doubles

private final class ScannerFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Bool
    init(_ initial: Bool = false) { value = initial }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

private final class ScannerCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var value: Int { lock.lock(); defer { lock.unlock() }; return count }
    func increment() { lock.lock(); count += 1; lock.unlock() }
}

private final class ScannerFakeActivity: NASActivityProviding, @unchecked Sendable {
    private let lock = NSLock()
    private var begun: [String] = []
    private var ended = 0
    var beginCount: Int { lock.lock(); defer { lock.unlock() }; return begun.count }
    var endCount: Int { lock.lock(); defer { lock.unlock() }; return ended }
    var reasons: [String] { lock.lock(); defer { lock.unlock() }; return begun }

    func begin(reason: String) -> NSObjectProtocol {
        lock.lock(); begun.append(reason); lock.unlock()
        return NSObject()
    }

    func end(_ token: NSObjectProtocol) {
        lock.lock(); ended += 1; lock.unlock()
    }
}

/// Wraps the live POSIX seam so tests can count opens, track in-flight reads and inject failures.
private final class ScannerReaderProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var fdPaths: [Int32: String] = [:]
    private var opened: [String] = []
    private var inFlight = 0
    private var maxInFlightValue = 0
    private var forcedErrno: Int32 = 0

    var readDelayMicroseconds: UInt32 = 0
    /// 1-based open call that fails with `failErrno`.
    var failOpenNumber: Int?
    var failErrno: Int32 = EIO
    /// Reads of paths ending with this suffix report a size one byte larger than expected.
    var sizeMismatchSuffix: String?
    var onOpen: (@Sendable () -> Void)?

    var openedPaths: [String] { lock.lock(); defer { lock.unlock() }; return opened }
    var openCount: Int { openedPaths.count }
    var maxInFlight: Int { lock.lock(); defer { lock.unlock() }; return maxInFlightValue }

    func makeReader() -> NASMeteredFileReader {
        let live = NASMeteredFileReader.SystemCalls.live
        return NASMeteredFileReader(systemCalls: NASMeteredFileReader.SystemCalls(
            open: { [self] path in
                lock.lock()
                opened.append(path)
                let number = opened.count
                forcedErrno = 0
                lock.unlock()
                onOpen?()
                if let failOpenNumber, failOpenNumber == number {
                    lock.lock(); forcedErrno = failErrno; lock.unlock()
                    return -1
                }
                let descriptor = live.open(path)
                if descriptor >= 0 {
                    lock.lock()
                    fdPaths[descriptor] = path
                    inFlight += 1
                    maxInFlightValue = max(maxInFlightValue, inFlight)
                    lock.unlock()
                }
                return descriptor
            },
            fstat: { [self] descriptor in
                guard var stat = live.fstat(descriptor) else { return nil }
                lock.lock()
                let path = fdPaths[descriptor]
                lock.unlock()
                if let suffix = sizeMismatchSuffix, let path, path.hasSuffix(suffix) {
                    stat.size += 1
                }
                return stat
            },
            read: { [self] descriptor, buffer, count in
                if readDelayMicroseconds > 0 { usleep(readDelayMicroseconds) }
                return live.read(descriptor, buffer, count)
            },
            close: { [self] descriptor in
                lock.lock()
                if fdPaths.removeValue(forKey: descriptor) != nil { inFlight -= 1 }
                lock.unlock()
                live.close(descriptor)
            },
            lastError: { [self] in
                lock.lock(); let forced = forcedErrno; lock.unlock()
                return forced != 0 ? forced : live.lastError()
            }
        ))
    }
}

private func hookedFileSystem(
    list: @escaping @Sendable (String, [String]) throws -> [String] = { _, names in names },
    entry: @escaping @Sendable (String, NASScanFileSystem.Entry?) -> NASScanFileSystem.Entry? = { _, value in value }
) -> NASScanFileSystem {
    let live = NASScanFileSystem.live
    return NASScanFileSystem(
        listDirectory: { path in try list(path, try live.listDirectory(path)) },
        entry: { path in entry(path, live.entry(path)) }
    )
}

private func bytes(_ value: UInt8, count: Int) -> Data { Data(repeating: value, count: count) }

private struct ScanResult {
    var events: [NASAssessmentEvent]
    var error: Error?
    var summary: NASScanSummary? {
        for event in events.reversed() {
            if case let .finished(summary) = event { return summary }
        }
        return nil
    }
    var issues: [NASIssue] {
        events.compactMap { event in
            if case let .issue(issue) = event { return issue }
            return nil
        }
    }
}

// MARK: - Tests

final class ChronoframeCoreNASAssessmentScannerTests: XCTestCase {
    private let libraryUUID = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"

    private func makeFixture(_ nodes: [NASFixtureBuilder.Node]) throws -> NASFixtureBuilder {
        let fixture = try NASFixtureBuilder(nodes)
        addTeardownBlock { fixture.tearDown() }
        return fixture
    }

    private func makeStore(_ fixture: NASFixtureBuilder) throws -> NASAssessmentStore {
        let store = try NASAssessmentStore(url: fixture.stateURL, libraryUUID: libraryUUID)
        addTeardownBlock { store.close() }
        return store
    }

    private func run(
        _ fixture: NASFixtureBuilder,
        store: NASAssessmentStore,
        workerCount: Int = 2,
        reader: NASMeteredFileReader = NASMeteredFileReader(),
        fileSystem: NASScanFileSystem = .live,
        activity: any NASActivityProviding = ScannerFakeActivity(),
        stateURL: URL? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) async -> ScanResult {
        let scanner = NASAssessmentScanner(store: store, reader: reader, fileSystem: fileSystem, activity: activity)
        let configuration = NASAssessmentConfiguration(
            rootURL: fixture.rootURL,
            stateURL: stateURL ?? fixture.stateURL,
            workerCount: workerCount
        )
        var events: [NASAssessmentEvent] = []
        var failure: Error?
        do {
            for try await event in scanner.run(configuration, isCancelled: isCancelled) {
                events.append(event)
            }
        } catch {
            failure = error
        }
        return ScanResult(events: events, error: failure)
    }

    // Three identical files at different depths, one same-name decoy with different bytes, one unique size.
    private var duplicateNodes: [NASFixtureBuilder.Node] {
        [
            .file("Curated/2018 Japan/a.jpg", bytes(1, count: 4096)),
            .file("Backup Copy/Photos/b.JPG", bytes(1, count: 4096)),
            .file("Old Mac/x.heic", bytes(1, count: 4096)),
            .file("Decoy/a.jpg", bytes(2, count: 4096)),
            .file("Unique/only.jpg", bytes(3, count: 777)),
        ]
    }

    func testRecursiveAssessmentFindsCrossFolderDuplicates() async throws {
        let fixture = try makeFixture(duplicateNodes)
        let store = try makeStore(fixture)
        let result = await run(fixture, store: store)

        XCTAssertNil(result.error)
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .complete)
        let groups = try store.exactGroups(generation: summary.generation)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.memberRelativePaths, [
            "Backup Copy/Photos/b.JPG",
            "Curated/2018 Japan/a.jpg",
            "Old Mac/x.heic",
        ])
        XCTAssertEqual(groups.first?.size, 4096)
        XCTAssertEqual(summary.exactGroupCount, 1)
        XCTAssertEqual(summary.redundantLogicalBytes, 8192)
        XCTAssertFalse(groups.flatMap(\.memberRelativePaths).contains("Decoy/a.jpg"))

        guard case .started = result.events.first, case .phaseStarted(.enumerating) = result.events[1] else {
            return XCTFail("Stream must begin with started and the enumerating phase.")
        }
        XCTAssertTrue(result.events.contains(.phaseStarted(.hashing)))
        XCTAssertTrue(result.events.contains(.phaseStarted(.grouping)))
    }

    func testUniqueSizeFilesAreNeverRead() async throws {
        let fixture = try makeFixture([
            .file("a.jpg", bytes(1, count: 10)),
            .file("b.jpg", bytes(2, count: 20)),
            .file("c.jpg", bytes(3, count: 30)),
            .file("d/one.jpg", bytes(4, count: 40)),
            .file("d/two.jpg", bytes(5, count: 40)),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let result = await run(fixture, store: store, reader: probe.makeReader())

        XCTAssertNil(result.error)
        XCTAssertEqual(probe.openCount, 2)
        XCTAssertEqual(Set(probe.openedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }), ["one.jpg", "two.jpg"])
        XCTAssertEqual(result.summary?.counts.candidateFiles, 2)
        XCTAssertEqual(result.summary?.counts.mediaFiles, 5)
    }

    func testCleanBytesEqualCandidateBytesOnColdScanAndWithinBudget() async throws {
        let fixture = try makeFixture(duplicateNodes)
        let store = try makeStore(fixture)
        let result = await run(fixture, store: store)

        let ledger = try XCTUnwrap(result.summary?.ledger)
        // Four files share the 4096-byte size: H = 4 * 4096.
        XCTAssertEqual(ledger.candidateBytesH, 4 * 4096)
        XCTAssertEqual(ledger.bytesReadClean, ledger.candidateBytesH)
        XCTAssertEqual(ledger.bytesReadUnresolved, 0)
        XCTAssertEqual(ledger.cacheHits, 0)
        XCTAssertTrue(ledger.isWithinBudget)
    }

    func testZeroByteFilesAreEmptyNotGrouped() async throws {
        let fixture = try makeFixture([
            .file("empty1.jpg", Data()),
            .file("Sub/empty2.jpg", Data()),
            .file("Sub/empty3.mov", Data()),
            .file("real.jpg", bytes(1, count: 100)),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let result = await run(fixture, store: store, reader: probe.makeReader())

        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .complete)
        XCTAssertEqual(summary.counts.emptyFiles, 3)
        XCTAssertEqual(summary.counts.candidateFiles, 0)
        XCTAssertEqual(summary.ledger.candidateBytesH, 0)
        XCTAssertEqual(summary.exactGroupCount, 0)
        XCTAssertEqual(probe.openCount, 0)
        XCTAssertEqual(try store.exactGroups(generation: summary.generation), [])
    }

    func testSynologyContainersExcludedAndReported() async throws {
        let payload = bytes(7, count: 2048)
        let fixture = try makeFixture([
            .file("Photos/keep.jpg", payload),
            .file("Photos/copy.jpg", payload),
            .file("Photos/@eaDir/keep.jpg/SYNOPHOTO_THUMB_XL.jpg", payload),
            .file("#recycle/deleted.jpg", payload),
            .file("#snapshot/GMT-2026/old.jpg", payload),
            .file("My #recycle notes/real.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let result = await run(fixture, store: store, reader: probe.makeReader())

        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .complete)
        let members = try store.exactGroups(generation: summary.generation).flatMap(\.memberRelativePaths)
        XCTAssertEqual(Set(members), ["Photos/keep.jpg", "Photos/copy.jpg", "My #recycle notes/real.jpg"])
        XCTAssertEqual(probe.openCount, 3)

        let issues = try store.issues(generation: summary.generation)
        let excluded = issues.filter { $0.category == .excludedSystemContainer }.map(\.relativePath)
        XCTAssertEqual(Set(excluded), ["Photos/@eaDir", "#recycle", "#snapshot"])
        XCTAssertEqual(issues.count, 3)
        let rows = try store.directoryRows(generation: summary.generation)
        XCTAssertEqual(rows.first { $0.relativePath == "#recycle" }?.status, .excludedSystem)
        XCTAssertNil(rows.first { $0.relativePath == "#recycle/deleted.jpg" })
    }

    func testSymlinksPackagesAndSpecialFilesAreReportedNotTraversed() async throws {
        let payload = bytes(9, count: 1500)
        let fixture = try makeFixture([
            .file("Real/a.jpg", payload),
            .file("Real/b.jpg", payload),
            .symlink("LinkedFolder", target: "Real"),
            .symlink("linked.jpg", target: "Real/a.jpg"),
            .fifo("pipe.jpg"),
            .file("Tool.app/Contents/hidden.jpg", payload),
            .file("Holiday.photoslibrary/originals/y.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let fileSystem = hookedFileSystem(entry: { path, entry in
            guard var entry, path.hasSuffix(".photoslibrary") else { return entry }
            entry.isPackage = true
            return entry
        })
        let result = await run(fixture, store: store, reader: probe.makeReader(), fileSystem: fileSystem)

        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .complete)
        let groups = try store.exactGroups(generation: summary.generation)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.memberRelativePaths, ["Real/a.jpg", "Real/b.jpg"])
        XCTAssertEqual(probe.openCount, 2, "Neither the FIFO nor anything behind a link or package may be opened.")

        let byCategory = Dictionary(grouping: try store.issues(generation: summary.generation), by: \.category)
        XCTAssertEqual(Set(byCategory[.skippedLink]?.map(\.relativePath) ?? []), ["LinkedFolder", "linked.jpg"])
        XCTAssertEqual(byCategory[.specialFile]?.map(\.relativePath), ["pipe.jpg"])
        XCTAssertEqual(Set(byCategory[.skippedPackage]?.map(\.relativePath) ?? []), ["Tool.app", "Holiday.photoslibrary"])
        let rows = try store.directoryRows(generation: summary.generation)
        XCTAssertEqual(rows.first { $0.relativePath == "Tool.app" }?.status, .skippedPackage)
        XCTAssertNil(rows.first { $0.relativePath.hasPrefix("LinkedFolder") })
    }

    func testNestedMountIsNotCrossed() async throws {
        let payload = bytes(4, count: 900)
        let fixture = try makeFixture([
            .file("Local/a.jpg", payload),
            .file("Local/b.jpg", payload),
            .file("Mounted/inside.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let fileSystem = hookedFileSystem(entry: { path, entry in
            guard var entry, path.hasSuffix("/Mounted") else { return entry }
            entry.deviceID = entry.deviceID &+ 1
            return entry
        })
        let result = await run(fixture, store: store, reader: probe.makeReader(), fileSystem: fileSystem)

        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .complete)
        XCTAssertEqual(probe.openCount, 2)
        let issues = try store.issues(generation: summary.generation)
        XCTAssertEqual(issues.filter { $0.category == .nestedMount }.map(\.relativePath), ["Mounted"])
        let rows = try store.directoryRows(generation: summary.generation)
        XCTAssertEqual(rows.first { $0.relativePath == "Mounted" }?.status, .nestedMount)
        XCTAssertNil(rows.first { $0.relativePath == "Mounted/inside.jpg" })
    }

    func testUnreadableDirectoryMakesAssessmentIncomplete() async throws {
        let payload = bytes(5, count: 600)
        let fixture = try makeFixture([
            .file("Open/a.jpg", payload),
            .file("Open/b.jpg", payload),
            .file("Locked/c.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let fileSystem = hookedFileSystem(list: { path, names in
            if path.hasSuffix("/Locked") { throw CocoaError(.fileReadNoPermission) }
            return names
        })
        let result = await run(fixture, store: store, fileSystem: fileSystem)

        XCTAssertNil(result.error)
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .completedWithGaps)
        let issues = try store.issues(generation: summary.generation)
        XCTAssertEqual(issues.filter { $0.category == .unreadableDirectory }.map(\.relativePath), ["Locked"])
        XCTAssertFalse(issues.contains { $0.detail.contains("NSCocoaError") || $0.detail.contains("errno") })
        let rows = try store.directoryRows(generation: summary.generation)
        XCTAssertEqual(rows.first { $0.relativePath == "Locked" }?.status, .unreadable)
        XCTAssertEqual(summary.counts.issueCount, 1)
    }

    func testExclusionsAloneKeepAssessmentComplete() async throws {
        let payload = bytes(6, count: 800)
        let fixture = try makeFixture([
            .file("a.jpg", payload),
            .file("b.jpg", payload),
            .file("@eaDir/thumb.jpg", payload),
            .file("Thing.app/x.jpg", payload),
            .symlink("link.jpg", target: "a.jpg"),
            .fifo("pipe.jpg"),
            .file("Mount/m.jpg", payload),
            .file("notes.txt", bytes(1, count: 5)),
        ])
        let store = try makeStore(fixture)
        let fileSystem = hookedFileSystem(entry: { path, entry in
            guard var entry, path.hasSuffix("/Mount") else { return entry }
            entry.deviceID = entry.deviceID &+ 1
            return entry
        })
        let result = await run(fixture, store: store, fileSystem: fileSystem)

        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .complete)
        XCTAssertEqual(summary.counts.issueCount, 5)
        XCTAssertEqual(summary.counts.unsupportedFiles, 1)
        XCTAssertEqual(summary.exactGroupCount, 1)
    }

    func testUnresolvedCandidateMakesAssessmentIncomplete() async throws {
        let payload = bytes(8, count: 1200)
        let fixture = try makeFixture([
            .file("one.jpg", payload),
            .file("two.jpg", payload),
            .file("three.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        probe.sizeMismatchSuffix = "/two.jpg"
        let result = await run(fixture, store: store, reader: probe.makeReader())

        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .completedWithGaps)
        XCTAssertEqual(summary.counts.unresolvedFiles, 1)
        XCTAssertEqual(summary.counts.hashedFiles, 2)
        XCTAssertEqual(summary.ledger.bytesReadUnresolved, 0)
        XCTAssertEqual(summary.ledger.bytesReadClean, 2400)
        let issues = try store.issues(generation: summary.generation)
        XCTAssertEqual(issues.count, 1)
        XCTAssertEqual(issues.first?.category, .unresolvedCandidate)
        XCTAssertEqual(issues.first?.relativePath, "two.jpg")
        XCTAssertEqual(issues.first?.detail, NASUnresolvedReason.sizeChangedBeforeRead.rawValue)
        XCTAssertEqual(try store.exactGroups(generation: summary.generation).first?.memberRelativePaths, ["one.jpg", "three.jpg"])
    }

    func testVolumeLossEndsWithInterruptedOutcome() async throws {
        let payload = bytes(2, count: 1000)
        let fixture = try makeFixture((0..<6).map { .file("f\($0).jpg", payload) })
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let lost = ScannerFlag()
        probe.failOpenNumber = 1
        probe.failErrno = EIO
        probe.onOpen = { lost.set() }
        let rootPath = fixture.rootPath
        let fileSystem = hookedFileSystem(entry: { path, entry in
            (path == rootPath && lost.isSet) ? nil : entry
        })
        let activity = ScannerFakeActivity()
        let result = await run(fixture, store: store, workerCount: 1, reader: probe.makeReader(), fileSystem: fileSystem, activity: activity)

        XCTAssertNil(result.error, "A lost volume finishes with a summary instead of throwing.")
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .interruptedVolumeUnavailable)
        XCTAssertEqual(probe.openCount, 1, "No further reads may be scheduled after the volume is lost.")
        XCTAssertEqual(activity.beginCount, 1)
        XCTAssertEqual(activity.endCount, 1)
        XCTAssertEqual(try store.scanSummary(generation: summary.generation)?.outcome, .interruptedVolumeUnavailable)
    }

    func testCancellationFinishesWithCancelledSummary() async throws {
        let payload = bytes(3, count: 500)
        let fixture = try makeFixture([
            .file("A/a.jpg", payload),
            .file("B/b.jpg", payload),
            .file("C/c.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let cancel = ScannerFlag()
        let rootPath = fixture.rootPath
        let fileSystem = hookedFileSystem(list: { path, names in
            if path != rootPath { cancel.set() }
            return names
        })
        let result = await run(fixture, store: store, reader: probe.makeReader(), fileSystem: fileSystem, isCancelled: { cancel.isSet })

        XCTAssertNil(result.error, "Cancellation must not throw.")
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .cancelled)
        XCTAssertNotNil(summary.finishedAt)
        XCTAssertEqual(probe.openCount, 0)
        XCTAssertEqual(try store.scanSummary(generation: summary.generation)?.outcome, .cancelled)
    }

    func testWarmScanReusesDigestsWithoutReads() async throws {
        let fixture = try makeFixture(duplicateNodes)
        let store = try makeStore(fixture)
        let first = await run(fixture, store: store)
        let firstSummary = try XCTUnwrap(first.summary)
        XCTAssertEqual(firstSummary.ledger.cacheHits, 0)

        let probe = ScannerReaderProbe()
        let second = await run(fixture, store: store, reader: probe.makeReader())
        let secondSummary = try XCTUnwrap(second.summary)

        XCTAssertEqual(probe.openCount, 0)
        XCTAssertEqual(secondSummary.generation, firstSummary.generation + 1)
        XCTAssertEqual(secondSummary.ledger.cacheHits, secondSummary.counts.candidateFiles)
        XCTAssertEqual(secondSummary.counts.candidateFiles, 4)
        XCTAssertEqual(secondSummary.ledger.bytesReadClean, 0)
        XCTAssertEqual(secondSummary.counts.hashedFiles, 4)
        XCTAssertEqual(secondSummary.outcome, .complete)
        XCTAssertEqual(secondSummary.exactGroupCount, firstSummary.exactGroupCount)
        XCTAssertEqual(
            try store.exactGroups(generation: secondSummary.generation),
            try store.exactGroups(generation: firstSummary.generation)
        )
    }

    func testChangedFileIsRehashedOnWarmScan() async throws {
        let fixture = try makeFixture(duplicateNodes)
        let store = try makeStore(fixture)
        let first = await run(fixture, store: store)
        XCTAssertEqual(first.summary?.exactGroupCount, 1)

        // Same size, new bytes, new modification time.
        let changed = fixture.rootURL.appendingPathComponent("Old Mac/x.heic")
        try bytes(0xEE, count: 4096).write(to: changed)
        try FileManager.default.setAttributes(
            [.modificationDate: Date(timeIntervalSinceNow: 3600)],
            ofItemAtPath: changed.path
        )

        let probe = ScannerReaderProbe()
        let second = await run(fixture, store: store, reader: probe.makeReader())
        let summary = try XCTUnwrap(second.summary)

        XCTAssertEqual(probe.openedPaths.map { URL(fileURLWithPath: $0).lastPathComponent }, ["x.heic"])
        XCTAssertEqual(summary.ledger.cacheHits, 3)
        XCTAssertEqual(summary.ledger.bytesReadClean, 4096)
        let groups = try store.exactGroups(generation: summary.generation)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.memberRelativePaths, ["Backup Copy/Photos/b.JPG", "Curated/2018 Japan/a.jpg"])
    }

    func testConcurrencyNeverExceedsWorkerCount() async throws {
        let payload = bytes(1, count: 300)
        let fixture = try makeFixture((0..<12).map { .file("f\($0).jpg", payload) })
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        probe.readDelayMicroseconds = 30_000
        let result = await run(fixture, store: store, workerCount: 3, reader: probe.makeReader())

        XCTAssertEqual(result.summary?.outcome, .complete)
        XCTAssertEqual(probe.openCount, 12)
        XCTAssertLessThanOrEqual(probe.maxInFlight, 3)
        XCTAssertGreaterThanOrEqual(probe.maxInFlight, 2, "Workers should overlap when more than one is configured.")
    }

    // AGENTS-INVARIANT: 27
    func testAssessmentDoesNotWriteInsideReadOnlyRoot() async throws {
        let fixture = try makeFixture(duplicateNodes + [
            .symlink("link.jpg", target: "Unique/only.jpg"),
            .fifo("pipe.jpg"),
            .file("@eaDir/t.jpg", bytes(1, count: 4096)),
            .file("notes.txt", bytes(1, count: 3)),
        ])
        try fixture.makeReadOnly()
        XCTAssertFalse(
            FileManager.default.createFile(atPath: fixture.rootURL.appendingPathComponent("write-probe").path, contents: Data()),
            "The fixture root must really be read-only for this test to mean anything."
        )
        let before = try fixture.snapshot()
        let store = try makeStore(fixture)
        let result = await run(fixture, store: store)

        XCTAssertNil(result.error)
        XCTAssertEqual(result.summary?.outcome, .complete)
        XCTAssertEqual(result.summary?.exactGroupCount, 1)
        let after = try fixture.snapshot()
        XCTAssertEqual(before, after)
    }

    // AGENTS-INVARIANT: 27
    func testAssessmentLeavesWritableRootByteIdentical() async throws {
        let fixture = try makeFixture(duplicateNodes + [
            .file(".hidden.jpg", bytes(1, count: 4096)),
            .file("Old Mac/._x.heic", bytes(1, count: 4096)),
            .file(".DS_Store", bytes(9, count: 12)),
            .symlink("link.jpg", target: "Unique/only.jpg"),
        ])
        let before = try fixture.snapshot()
        let store = try makeStore(fixture)
        let result = await run(fixture, store: store)

        XCTAssertEqual(result.summary?.outcome, .complete)
        let after = try fixture.snapshot()
        XCTAssertEqual(before, after, "Sizes, modification times, inodes and modes must match, with no new entries.")
        XCTAssertEqual(Set(before.keys), Set(after.keys))
        // Dot-prefixed names are skipped silently and never counted (D-NAS-14).
        XCTAssertEqual(result.summary?.counts.mediaFiles, 5)
        XCTAssertEqual(result.summary?.exactGroupCount, 1)
    }

    // AGENTS-INVARIANT: 27
    func testRefusesStateInsideRoot() async throws {
        let fixture = try makeFixture(duplicateNodes)
        let store = try makeStore(fixture)
        let before = try fixture.snapshot()
        let insideState = fixture.rootURL.appendingPathComponent(".nas-state/assessment.sqlite")
        let activity = ScannerFakeActivity()
        let result = await run(fixture, store: store, activity: activity, stateURL: insideState)

        XCTAssertTrue(result.events.isEmpty, "A refused run must not yield any event.")
        XCTAssertEqual(
            result.error as? NASAssessmentError,
            .stateInsideLibrary(statePath: insideState.standardizedFileURL.path, rootPath: fixture.rootPath)
        )
        XCTAssertEqual(activity.beginCount, 0)
        XCTAssertNil(try store.latestGeneration())
        XCTAssertEqual(try fixture.snapshot(), before)

        // The root itself and a path that only shares a name prefix are different cases.
        let rootItself = await run(fixture, store: store, stateURL: fixture.rootURL)
        XCTAssertEqual(
            rootItself.error as? NASAssessmentError,
            .stateInsideLibrary(statePath: fixture.rootPath, rootPath: fixture.rootPath)
        )
        let sibling = URL(fileURLWithPath: fixture.rootPath + "-state/assessment.sqlite")
        let allowed = await run(fixture, store: store, stateURL: sibling)
        XCTAssertNil(allowed.error)
    }

    func testRefusesSymlinkRoot() async throws {
        let fixture = try makeFixture(duplicateNodes)
        let store = try makeStore(fixture)
        let linkURL = fixture.containerURL.appendingPathComponent("library-link")
        try FileManager.default.createSymbolicLink(atPath: linkURL.path, withDestinationPath: fixture.rootURL.path)

        let scanner = NASAssessmentScanner(store: store, activity: ScannerFakeActivity())
        let configuration = NASAssessmentConfiguration(rootURL: linkURL, stateURL: fixture.stateURL)
        var events = 0
        var failure: Error?
        do {
            for try await _ in scanner.run(configuration, isCancelled: { false }) { events += 1 }
        } catch {
            failure = error
        }
        XCTAssertEqual(events, 0)
        XCTAssertEqual(failure as? NASAssessmentError, .rootIsLink(path: linkURL.standardizedFileURL.path))
        XCTAssertNil(try store.latestGeneration())

        // A missing root and a file root are unavailable, not links.
        let missing = fixture.containerURL.appendingPathComponent("does-not-exist")
        var missingFailure: Error?
        do {
            for try await _ in scanner.run(NASAssessmentConfiguration(rootURL: missing, stateURL: fixture.stateURL), isCancelled: { false }) {}
        } catch {
            missingFailure = error
        }
        XCTAssertEqual(missingFailure as? NASAssessmentError, .rootUnavailable(path: missing.standardizedFileURL.path))
    }

    func testUnicodeAndCaseCollisionPathsAreDistinct() async throws {
        // Part A: an NFD-named file on disk is reported under its NFC relative path and is still readable.
        let decomposed = "Cafe\u{301}.jpg"
        let composed = "Caf\u{E9}.jpg"
        XCTAssertNotEqual(decomposed.unicodeScalars.count, composed.unicodeScalars.count)
        let fixture = try makeFixture([
            .file(decomposed, bytes(1, count: 2000)),
            .file("Other/b.jpg", bytes(1, count: 2000)),
            .file("Other/Caf\u{E9}-2.jpg", bytes(2, count: 2000)),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let result = await run(fixture, store: store, reader: probe.makeReader())
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .complete)
        let groups = try store.exactGroups(generation: summary.generation)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.memberRelativePaths, [composed, "Other/b.jpg"])
        XCTAssertTrue(groups.first?.memberRelativePaths.allSatisfy { $0 == $0.precomposedStringWithCanonicalMapping } ?? false)
        XCTAssertEqual(summary.counts.unresolvedFiles, 0)

        // Part B: two names that only differ by normalization (possible on NAS file systems) are never
        // merged silently. The second one is reported, which keeps the assessment honest about coverage.
        let collisionRoot = fixture.rootPath
        // Swift string equality is canonical, so match the two spellings by their UTF-8 bytes.
        let sizes: [(name: String, size: Int64)] = [(composed, 10), (decomposed, 11)]
        let collisionFS = NASScanFileSystem(
            listDirectory: { path in path == collisionRoot ? [decomposed, composed] : [] },
            entry: { path in
                if path == collisionRoot {
                    return NASScanFileSystem.Entry(name: "library", isDirectory: true, isRegularFile: false, isSymbolicLink: false, isPackage: false, size: 0, modificationTime: 1, fileID: 1, deviceID: 7)
                }
                let name = String(path.dropFirst(collisionRoot.count + 1))
                guard let size = sizes.first(where: { Array($0.name.utf8) == Array(name.utf8) })?.size else { return nil }
                return NASScanFileSystem.Entry(name: name, isDirectory: false, isRegularFile: true, isSymbolicLink: false, isPackage: false, size: size, modificationTime: 1, fileID: UInt64(size), deviceID: 7)
            }
        )
        let collisionStoreURL = fixture.stateDirectoryURL.appendingPathComponent("collision.sqlite")
        let collisionStore = try NASAssessmentStore(url: collisionStoreURL, libraryUUID: libraryUUID)
        addTeardownBlock { collisionStore.close() }
        let collision = await run(fixture, store: collisionStore, fileSystem: collisionFS)
        let collisionSummary = try XCTUnwrap(collision.summary)
        XCTAssertEqual(collisionSummary.counts.mediaFiles, 1)
        XCTAssertEqual(collisionSummary.outcome, .completedWithGaps)
        XCTAssertEqual(collision.issues.filter { $0.category == .unreadableItem }.map(\.relativePath), [composed])

        // Part C: names that differ only by case stay separate items on a case-sensitive volume.
        let probeDirectory = fixture.stateDirectoryURL.appendingPathComponent("caseprobe")
        try Data().write(to: probeDirectory)
        let caseInsensitive = FileManager.default.fileExists(atPath: fixture.stateDirectoryURL.appendingPathComponent("CASEPROBE").path)
        try XCTSkipIf(
            caseInsensitive,
            "The temporary volume is case-insensitive, so IMG.jpg and img.jpg cannot coexist here; only the case pair was skipped."
        )
        let caseFixture = try makeFixture([
            .file("IMG.jpg", bytes(1, count: 3000)),
            .file("img.jpg", bytes(2, count: 3000)),
            .file("Copy/x.jpg", bytes(1, count: 3000)),
        ])
        let caseStore = try makeStore(caseFixture)
        let caseResult = await run(caseFixture, store: caseStore)
        let caseSummary = try XCTUnwrap(caseResult.summary)
        XCTAssertEqual(caseSummary.counts.mediaFiles, 3)
        XCTAssertEqual(try caseStore.exactGroups(generation: caseSummary.generation).first?.memberRelativePaths, ["Copy/x.jpg", "IMG.jpg"])
    }

    func testSleepActivityBeginsAndEndsOnceForEveryOutcome() async throws {
        let payload = bytes(1, count: 400)

        // Complete.
        let completeFixture = try makeFixture([.file("a.jpg", payload), .file("b.jpg", payload)])
        let completeStore = try makeStore(completeFixture)
        let completeActivity = ScannerFakeActivity()
        let complete = await run(completeFixture, store: completeStore, activity: completeActivity)
        XCTAssertEqual(complete.summary?.outcome, .complete)
        XCTAssertEqual(completeActivity.beginCount, 1)
        XCTAssertEqual(completeActivity.endCount, 1)
        XCTAssertEqual(completeActivity.reasons, ["Chronoframe: assessing a NAS library"])

        // Cancelled.
        let cancelFixture = try makeFixture([.file("a.jpg", payload), .file("b.jpg", payload)])
        let cancelStore = try makeStore(cancelFixture)
        let cancelActivity = ScannerFakeActivity()
        let cancelled = await run(cancelFixture, store: cancelStore, activity: cancelActivity, isCancelled: { true })
        XCTAssertEqual(cancelled.summary?.outcome, .cancelled)
        XCTAssertEqual(cancelActivity.beginCount, 1)
        XCTAssertEqual(cancelActivity.endCount, 1)

        // Interrupted.
        let lostFixture = try makeFixture([.file("a.jpg", payload), .file("b.jpg", payload)])
        let lostStore = try makeStore(lostFixture)
        let lostActivity = ScannerFakeActivity()
        let lost = ScannerFlag()
        let lostRoot = lostFixture.rootPath
        let lostFS = hookedFileSystem(entry: { path, entry in (path == lostRoot && lost.isSet) ? nil : entry })
        let probe = ScannerReaderProbe()
        probe.failOpenNumber = 1
        probe.onOpen = { lost.set() }
        let interrupted = await run(lostFixture, store: lostStore, workerCount: 1, reader: probe.makeReader(), fileSystem: lostFS, activity: lostActivity)
        XCTAssertEqual(interrupted.summary?.outcome, .interruptedVolumeUnavailable)
        XCTAssertEqual(lostActivity.beginCount, 1)
        XCTAssertEqual(lostActivity.endCount, 1)
    }

    // MARK: - Additional coverage

    private func runWithBatches(
        _ fixture: NASFixtureBuilder,
        store: NASAssessmentStore,
        directoryBatch: Int,
        hashBatch: Int
    ) async -> ScanResult {
        let scanner = NASAssessmentScanner(store: store, activity: ScannerFakeActivity())
        let configuration = NASAssessmentConfiguration(
            rootURL: fixture.rootURL,
            stateURL: fixture.stateURL,
            checkpointDirectoryBatch: directoryBatch,
            hashResultBatch: hashBatch
        )
        var events: [NASAssessmentEvent] = []
        var failure: Error?
        do {
            for try await event in scanner.run(configuration, isCancelled: { false }) {
                events.append(event)
            }
        } catch {
            failure = error
        }
        return ScanResult(events: events, error: failure)
    }

    // AGENTS-INVARIANT: 27
    func testCancellationDuringHashingFinishesCancelled() async throws {
        let payload = bytes(4, count: 900)
        let fixture = try makeFixture((0..<6).map { .file("f\($0).jpg", payload) })
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        let cancel = ScannerFlag()
        probe.onOpen = { cancel.set() }
        let activity = ScannerFakeActivity()
        let result = await run(
            fixture,
            store: store,
            workerCount: 1,
            reader: probe.makeReader(),
            activity: activity,
            isCancelled: { cancel.isSet }
        )

        XCTAssertNil(result.error, "Cancellation during hashing must not throw.")
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .cancelled)
        XCTAssertNotEqual(summary.outcome, .complete)
        XCTAssertEqual(probe.openCount, 1, "No further hashes may start once the first in-flight hash has seen the cancel.")
        XCTAssertEqual(try store.scanSummary(generation: summary.generation)?.outcome, .cancelled)
        XCTAssertEqual(activity.beginCount, 1)
        XCTAssertEqual(activity.endCount, 1)
    }

    // AGENTS-INVARIANT: 27
    func testUnreadableEntryMakesAssessmentIncomplete() async throws {
        let payload = bytes(6, count: 700)
        let fixture = try makeFixture([
            .file("Open/a.jpg", payload),
            .file("Open/b.jpg", payload),
            .file("Open/bad.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let fileSystem = hookedFileSystem(entry: { path, entry in
            path.hasSuffix("/Open/bad.jpg") ? nil : entry
        })
        let result = await run(fixture, store: store, fileSystem: fileSystem)

        XCTAssertNil(result.error)
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .completedWithGaps)
        let issues = try store.issues(generation: summary.generation)
        XCTAssertEqual(issues.filter { $0.category == .unreadableItem }.map(\.relativePath), ["Open/bad.jpg"])
        XCTAssertEqual(summary.counts.mediaFiles, 2, "The unreadable entry must not be counted as assessed media.")
        XCTAssertFalse(issues.contains { $0.detail.contains("errno") || $0.detail.contains("POSIX") })
    }

    // AGENTS-INVARIANT: 27
    func testRepeatedEntryFailuresWithRootGoneEndInterruptedNotGaps() async throws {
        let fixture = try makeFixture((0..<12).map { .file("Open/f\($0).jpg", bytes(UInt8($0), count: 700 + $0)) })
        let store = try makeStore(fixture)
        let rootPath = fixture.rootPath
        let lost = ScannerFlag()
        let childLookups = ScannerCounter()
        // The share drops as soon as the first child is looked up: every later lstat fails,
        // including the one on the root, while the folder listing itself already succeeded.
        let fileSystem = hookedFileSystem(entry: { path, entry in
            if path == rootPath { return lost.isSet ? nil : entry }
            if path.hasSuffix(".jpg") {
                lost.set()
                childLookups.increment()
                return nil
            }
            return entry
        })
        let result = await run(fixture, store: store, fileSystem: fileSystem)

        XCTAssertNil(result.error)
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .interruptedVolumeUnavailable)
        XCTAssertLessThan(childLookups.value, 12, "The scan must stop looking at entries once the root is gone.")
        XCTAssertEqual(try store.scanSummary(generation: summary.generation)?.outcome, .interruptedVolumeUnavailable)
    }

    // AGENTS-INVARIANT: 27
    func testRepeatedEntryFailuresWithRootPresentStayGapsNotInterrupted() async throws {
        let fixture = try makeFixture((0..<12).map { .file("Open/f\($0).jpg", bytes(UInt8($0), count: 700 + $0)) })
        let store = try makeStore(fixture)
        let fileSystem = hookedFileSystem(entry: { path, entry in
            path.hasSuffix(".jpg") ? nil : entry
        })
        let result = await run(fixture, store: store, fileSystem: fileSystem)

        XCTAssertNil(result.error)
        let summary = try XCTUnwrap(result.summary)
        XCTAssertEqual(summary.outcome, .completedWithGaps)
        let issues = try store.issues(generation: summary.generation)
        XCTAssertEqual(issues.filter { $0.category == .unreadableItem }.count, 12, "Every unreadable entry is still reported when the root is reachable.")
    }

    func testRootThatIsAFileIsRefused() async throws {
        let fixture = try makeFixture([.file("single.jpg", bytes(1, count: 100))])
        let store = try makeStore(fixture)
        let fileRoot = fixture.rootURL.appendingPathComponent("single.jpg")

        let scanner = NASAssessmentScanner(store: store, activity: ScannerFakeActivity())
        let configuration = NASAssessmentConfiguration(rootURL: fileRoot, stateURL: fixture.stateURL)
        var events = 0
        var failure: Error?
        do {
            for try await _ in scanner.run(configuration, isCancelled: { false }) { events += 1 }
        } catch {
            failure = error
        }

        XCTAssertEqual(events, 0)
        XCTAssertEqual(failure as? NASAssessmentError, .rootUnavailable(path: fileRoot.standardizedFileURL.path))
        XCTAssertNil(try store.latestGeneration())
    }

    func testSmallCheckpointBatchesPersistEveryRow() async throws {
        let defaultFixture = try makeFixture(duplicateNodes)
        let defaultStore = try makeStore(defaultFixture)
        let defaults = await runWithBatches(defaultFixture, store: defaultStore, directoryBatch: 200, hashBatch: 200)

        let smallFixture = try makeFixture(duplicateNodes)
        let smallStore = try makeStore(smallFixture)
        let small = await runWithBatches(smallFixture, store: smallStore, directoryBatch: 1, hashBatch: 1)

        XCTAssertNil(defaults.error)
        XCTAssertNil(small.error)
        let defaultSummary = try XCTUnwrap(defaults.summary)
        let smallSummary = try XCTUnwrap(small.summary)
        XCTAssertEqual(smallSummary.outcome, .complete)
        XCTAssertEqual(smallSummary.outcome, defaultSummary.outcome)
        XCTAssertEqual(smallSummary.counts, defaultSummary.counts)
        XCTAssertEqual(smallSummary.exactGroupCount, defaultSummary.exactGroupCount)
        XCTAssertEqual(smallSummary.redundantLogicalBytes, defaultSummary.redundantLogicalBytes)
        XCTAssertEqual(smallSummary.ledger.candidateBytesH, defaultSummary.ledger.candidateBytesH)
        XCTAssertEqual(
            try smallStore.exactGroups(generation: smallSummary.generation),
            try defaultStore.exactGroups(generation: defaultSummary.generation)
        )
        XCTAssertEqual(
            try smallStore.directoryRows(generation: smallSummary.generation).map(\.relativePath).sorted(),
            try defaultStore.directoryRows(generation: defaultSummary.generation).map(\.relativePath).sorted()
        )
    }

    func testStoreFailureDuringHashingThrowsAndNeverReportsComplete() async throws {
        let payload = bytes(9, count: 1100)
        let fixture = try makeFixture([
            .file("a.jpg", payload),
            .file("b.jpg", payload),
            .file("c.jpg", payload),
        ])
        let store = try makeStore(fixture)
        let probe = ScannerReaderProbe()
        probe.onOpen = { store.close() }
        let result = await run(fixture, store: store, workerCount: 1, reader: probe.makeReader())

        XCTAssertNotNil(result.error, "A store that fails mid-hash must fail the stream.")
        XCTAssertTrue(result.error is NASAssessmentError, "got \(String(describing: result.error))")
        XCTAssertNil(result.summary, "No finished summary may be reported when progress could not be saved.")
        XCTAssertFalse(result.events.contains { event in
            if case let .finished(summary) = event { return summary.outcome == .complete }
            return false
        })
    }
}
