import Darwin
import Foundation
import SQLite3
import XCTest
@testable import ChronoframeCore

/// WP-09 / C-14: probe, corpus generator and parity check. Everything runs in
/// throwaway directories under the system temporary directory.
final class ChronoframeCoreNASProbeTests: XCTestCase {
    private var createdRoots: [URL] = []

    override func tearDown() {
        for url in createdRoots {
            try? FileManager.default.removeItem(at: url)
        }
        createdRoots = []
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeTempDirectory(_ label: String = "NASProbeTests") throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(label)-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        createdRoots.append(url)
        return url
    }

    private func contents(of url: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: url.path).sorted()
    }

    /// Keeps the held-writer window short for tests that do not measure it.
    private func fastProbe(
        trashItem: (@Sendable (URL) throws -> URL?)? = nil
    ) -> NASProbe {
        if let trashItem {
            return NASProbe(trashItem: trashItem, writerHoldSeconds: 0.2)
        }
        return NASProbe(writerHoldSeconds: 0.2)
    }

    private func result(_ id: String, in results: [NASProbeResult], file: StaticString = #filePath, line: UInt = #line) throws -> NASProbeResult {
        try XCTUnwrap(results.first { $0.id == id }, "Missing probe result \(id)", file: file, line: line)
    }

    /// Extracts `<label>: rc=<n> elapsedMs=<m>` from a P07 detail string.
    private func heldWriterMetric(_ label: String, in detail: String) throws -> (rc: Int, elapsedMs: Int) {
        let pattern = "\(label): rc=(-?\\d+) elapsedMs=(\\d+)"
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(detail.startIndex..., in: detail)
        let match = try XCTUnwrap(regex.firstMatch(in: detail, range: range), "No \(label) metric in: \(detail)")
        let rc = try XCTUnwrap(Int(detail[Range(match.range(at: 1), in: detail)!]))
        let elapsed = try XCTUnwrap(Int(detail[Range(match.range(at: 2), in: detail)!]))
        return (rc, elapsed)
    }

    private struct TreeEntry: Equatable {
        var size: Int64
        var mtime: TimeInterval
        var isDirectory: Bool
    }

    /// lstat of every entry below `root`, dot files included.
    private func snapshot(of root: URL) throws -> [String: TreeEntry] {
        var result: [String: TreeEntry] = [:]
        func walk(_ path: String, _ relative: String) throws {
            var info = Darwin.stat()
            guard Darwin.lstat(path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
            let isDirectory = (info.st_mode & S_IFMT) == S_IFDIR
            result[relative] = TreeEntry(
                size: Int64(info.st_size),
                mtime: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000,
                isDirectory: isDirectory
            )
            guard isDirectory else { return }
            for name in try FileManager.default.contentsOfDirectory(atPath: path) {
                try walk(path + "/" + name, relative.isEmpty ? name : relative + "/" + name)
            }
        }
        try walk(root.path, "")
        return result
    }

    private func generateCorpus(
        files: Int = 80,
        duplicatePercent: Int = 20,
        seed: UInt64 = 42
    ) throws -> (destination: URL, manifestURL: URL, manifest: NASCorpusManifest) {
        let container = try makeTempDirectory("NASCorpusTests")
        let destination = container.appendingPathComponent("corpus", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let manifestURL = container.appendingPathComponent("manifest.json")
        let manifest = try NASCorpusGenerator.generate(
            destination: destination,
            manifestURL: manifestURL,
            fileCount: files,
            duplicatePercent: duplicatePercent,
            seed: seed
        )
        return (destination, manifestURL, manifest)
    }

    // MARK: - Probe

    func testProbeRefusesNonEmptyTestDirectory() throws {
        let testDirectory = try makeTempDirectory()
        try Data("not mine".utf8).write(to: testDirectory.appendingPathComponent("photo.jpg"))

        XCTAssertThrowsError(try fastProbe().run(testDirectory: testDirectory, includeTrash: false)) { error in
            XCTAssertEqual(error as? NASProbeError, .testDirectoryNotEmpty(path: testDirectory.path))
        }
        XCTAssertEqual(try contents(of: testDirectory), ["photo.jpg"], "A refused probe must create nothing.")
    }

    func testProbeOnLocalVolumeRecordsAllChecksAndCleansUp() throws {
        let testDirectory = try makeTempDirectory()

        let results = try fastProbe().run(testDirectory: testDirectory, includeTrash: false)

        XCTAssertEqual(results.map(\.id), ["P01", "P02", "P03", "P04", "P05", "P06", "P07"])
        for id in ["P03", "P04", "P05"] {
            let probe = try result(id, in: results)
            XCTAssertEqual(probe.status, .pass, "\(id): \(probe.detail)")
        }
        XCTAssertEqual(try result("P01", in: results).status, .pass)
        let fullSync = try result("P02", in: results)
        XCTAssertEqual(fullSync.status, .pass, fullSync.detail)
        let journal = try result("P06", in: results)
        XCTAssertEqual(journal.status, .pass, journal.detail)
        XCTAssertTrue(journal.detail.contains("sqliteVersion="), journal.detail)
        XCTAssertTrue(journal.detail.contains("enableLockingStyle="), journal.detail)
        XCTAssertTrue(journal.detail.contains("vfs="), journal.detail)
        XCTAssertTrue(journal.detail.contains("journalMode=delete"), journal.detail)
        XCTAssertTrue(journal.detail.contains("synchronous=2"), journal.detail)
        XCTAssertEqual(try contents(of: testDirectory), [], "The probe workspace must be removed.")
    }

    func testProbeExclusiveRenameOntoExistingKeepsBytes() throws {
        let testDirectory = try makeTempDirectory()

        let results = try fastProbe().run(testDirectory: testDirectory, includeTrash: false)

        let probe = try result("P04", in: results)
        XCTAssertEqual(probe.status, .pass, probe.detail)
        XCTAssertEqual(probe.errorCode, EEXIST)
        XCTAssertTrue(probe.detail.contains("existingDigestUnchanged=true"), probe.detail)
        XCTAssertTrue(probe.detail.contains("sourceStillPresent=true"), probe.detail)
    }

    func testProbeHeldWriterRecordsLatencyAndBusy() throws {
        let testDirectory = try makeTempDirectory()

        let results = try NASProbe().run(testDirectory: testDirectory, includeTrash: false)

        let probe = try result("P07", in: results)
        XCTAssertEqual(probe.status, .pass, probe.detail)
        let patient = try heldWriterMetric("timeout30000", in: probe.detail)
        XCTAssertEqual(patient.rc, Int(SQLITE_OK))
        XCTAssertGreaterThanOrEqual(patient.elapsedMs, 1500, probe.detail)
        let impatient = try heldWriterMetric("timeout0", in: probe.detail)
        XCTAssertEqual(impatient.rc, Int(SQLITE_BUSY), probe.detail)
        XCTAssertEqual(try contents(of: testDirectory), [])
    }

    func testTrashProbeOnlyRunsWithFlag() throws {
        let testDirectory = try makeTempDirectory()
        let fakeTrash = try makeTempDirectory("NASFakeTrash")
        let calls = TrashCallRecorder()
        let probe = fastProbe(trashItem: { url in
            calls.record(url)
            let destination = fakeTrash.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        })

        let withoutFlag = try probe.run(testDirectory: testDirectory, includeTrash: false)
        XCTAssertEqual(calls.count, 0, "Trash must never be touched without the flag.")
        XCTAssertNil(withoutFlag.first { $0.id == "P08" })

        let withFlag = try probe.run(testDirectory: testDirectory, includeTrash: true)
        XCTAssertEqual(calls.count, 1)
        let trash = try result("P08", in: withFlag)
        XCTAssertEqual(trash.status, .pass, trash.detail)
        XCTAssertTrue(trash.detail.contains("digestAtTrashMatches=true"), trash.detail)
        XCTAssertTrue(trash.detail.contains("restored=true"), trash.detail)
        XCTAssertEqual(try contents(of: testDirectory), [])
        XCTAssertEqual(try contents(of: fakeTrash), [], "The probe file must be moved back out of the trash.")
        // Only a file the probe created inside its own workspace was offered to the trash.
        XCTAssertTrue(calls.urls[0].path.contains("/.chronoframe-nas-probe-"))
    }

    // MARK: - Corpus

    func testCorpusGeneratorIsDeterministicAndManifestMatchesDisk() throws {
        let first = try generateCorpus(files: 60, duplicatePercent: 20, seed: 7)
        let second = try generateCorpus(files: 60, duplicatePercent: 20, seed: 7)

        XCTAssertEqual(first.manifest, second.manifest)
        XCTAssertEqual(try Data(contentsOf: first.manifestURL), try Data(contentsOf: second.manifestURL))
        let other = try generateCorpus(files: 60, duplicatePercent: 20, seed: 8)
        XCTAssertNotEqual(first.manifest, other.manifest)

        XCTAssertEqual(first.manifest.files.count, 60)
        let hasher = FileIdentityHasher()
        var onDisk = 0
        let enumerator = FileManager.default.enumerator(atPath: first.destination.path)
        while let relative = enumerator?.nextObject() as? String {
            var isDirectory: ObjCBool = false
            FileManager.default.fileExists(atPath: first.destination.appendingPathComponent(relative).path, isDirectory: &isDirectory)
            if !isDirectory.boolValue { onDisk += 1 }
        }
        XCTAssertEqual(onDisk, first.manifest.files.count, "Manifest must list every file on disk.")
        for file in first.manifest.files {
            let url = URL(fileURLWithPath: first.destination.path + "/" + file.relativePath)
            let identity = try hasher.hashIdentity(at: url)
            XCTAssertEqual(identity.size, file.size, file.relativePath)
            XCTAssertEqual(identity.digest, file.digest, file.relativePath)
        }
    }

    func testCorpusIncludesRequiredCases() throws {
        let corpus = try generateCorpus(files: 200, duplicatePercent: 20, seed: 42)
        let files = corpus.manifest.files

        XCTAssertTrue(files.contains { $0.size == 0 }, "A zero-byte file is required.")

        let assessed = files.filter { !$0.excluded && $0.size > 0 }
        let bySize = Dictionary(grouping: assessed, by: \.size)
        XCTAssertTrue(
            bySize.values.contains { Set($0.map(\.digest)).count > 1 },
            "Same-size-different-bytes files are required."
        )

        XCTAssertTrue(
            // Swift String equality ignores canonical equivalence, so compare scalars.
            files.contains { Array($0.relativePath.unicodeScalars) != Array($0.relativePath.precomposedStringWithCanonicalMapping.unicodeScalars) },
            "A decomposed (NFD) Unicode name is required."
        )

        let extensions = Set(files.map { URL(fileURLWithPath: $0.relativePath).pathExtension.lowercased() })
        XCTAssertTrue(extensions.isSuperset(of: ["jpg", "heic", "mov"]))

        for container in ["@eaDir", "#recycle"] {
            let excluded = files.filter { $0.relativePath.split(separator: "/").contains(Substring(container)) }
            XCTAssertGreaterThanOrEqual(excluded.count, 2, "\(container) must hold files.")
            XCTAssertTrue(excluded.allSatisfy(\.excluded))
            let excludedDigests = excluded.map(\.digest)
            let assessedDigests = Set(assessed.map(\.digest))
            XCTAssertTrue(
                Set(excludedDigests).count < excludedDigests.count || excludedDigests.contains { assessedDigests.contains($0) },
                "\(container) must hold duplicates that the assessment has to exclude."
            )
            let members = Set(corpus.manifest.expectedGroups.flatMap { $0 })
            XCTAssertTrue(excluded.allSatisfy { !members.contains($0.relativePath.precomposedStringWithCanonicalMapping) })
        }

        XCTAssertFalse(corpus.manifest.expectedGroups.isEmpty)
        XCTAssertTrue(corpus.manifest.expectedGroups.allSatisfy { $0.count >= 2 && $0 == $0.sorted() })
    }

    func testCorpusRefusesNonEmptyDestinationAndManifestInsideIt() throws {
        let container = try makeTempDirectory("NASCorpusTests")
        let destination = container.appendingPathComponent("corpus", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: destination.appendingPathComponent("existing.jpg"))

        XCTAssertThrowsError(try NASCorpusGenerator.generate(
            destination: destination,
            manifestURL: container.appendingPathComponent("m.json"),
            fileCount: 40, duplicatePercent: 20, seed: 1
        )) { XCTAssertEqual($0 as? NASCorpusError, .destinationNotEmpty(path: destination.path)) }
        XCTAssertEqual(try contents(of: destination), ["existing.jpg"])

        let emptyDestination = container.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyDestination, withIntermediateDirectories: true)
        let insideManifest = emptyDestination.appendingPathComponent("manifest.json")
        XCTAssertThrowsError(try NASCorpusGenerator.generate(
            destination: emptyDestination,
            manifestURL: insideManifest,
            fileCount: 40, duplicatePercent: 20, seed: 1
        )) { XCTAssertEqual($0 as? NASCorpusError, .manifestInsideDestination(path: insideManifest.path)) }
        XCTAssertEqual(try contents(of: emptyDestination), [])
    }

    // MARK: - Parity

    // AGENTS-INVARIANT: 27
    func testParityCheckPassesOnGeneratedCorpus() async throws {
        let corpus = try generateCorpus(files: 80, duplicatePercent: 20, seed: 42)
        let state = try makeTempDirectory("NASParityState")
        let before = try snapshot(of: corpus.destination)

        let report = try await NASParityCheck().run(rootURL: corpus.destination, stateDirectory: state)

        XCTAssertTrue(report.parity, report.differences.joined(separator: "\n"))
        XCTAssertEqual(report.differences, [])
        XCTAssertEqual(report.exhaustiveGroupCount, corpus.manifest.expectedGroups.count)
        XCTAssertEqual(report.scannerGroupCount, corpus.manifest.expectedGroups.count)
        XCTAssertTrue(report.ledger.isWithinBudget)
        XCTAssertTrue(report.withinBudget)
        XCTAssertEqual(report.budgetBytes, report.ledger.cleanReadBudget)
        XCTAssertEqual(report.summary.outcome, .complete)
        XCTAssertGreaterThan(report.ruMaxrss, 0)
        XCTAssertGreaterThanOrEqual(report.wallSeconds, 0)

        // Scanner groups equal the manifest's expected groups, not just the exhaustive pass.
        let againstManifest = try await NASParityCheck().run(
            rootURL: corpus.destination,
            stateDirectory: try makeTempDirectory("NASParityState"),
            exhaustiveGroupsOverride: corpus.manifest.expectedGroups
        )
        XCTAssertTrue(againstManifest.parity, againstManifest.differences.joined(separator: "\n"))

        XCTAssertEqual(try snapshot(of: corpus.destination), before, "The assessed root must stay untouched.")
    }

    func testParityCheckDetectsDifference() async throws {
        let corpus = try generateCorpus(files: 80, duplicatePercent: 20, seed: 42)
        var manipulated = corpus.manifest.expectedGroups
        XCTAssertGreaterThan(manipulated.count, 1)
        manipulated.removeFirst()
        manipulated.append(["not/a/real/file-1.jpg", "not/a/real/file-2.jpg"])

        let report = try await NASParityCheck().run(
            rootURL: corpus.destination,
            stateDirectory: try makeTempDirectory("NASParityState"),
            exhaustiveGroupsOverride: manipulated
        )

        XCTAssertFalse(report.parity)
        XCTAssertGreaterThanOrEqual(report.differences.count, 2)
    }

    // AGENTS-INVARIANT: 27
    func testParityRefusesStateInsideRoot() async throws {
        let corpus = try generateCorpus(files: 40, duplicatePercent: 20, seed: 3)
        let insideState = corpus.destination.appendingPathComponent("parity-state", isDirectory: true)
        let before = try snapshot(of: corpus.destination)

        do {
            _ = try await NASParityCheck().run(rootURL: corpus.destination, stateDirectory: insideState)
            XCTFail("Expected the parity check to refuse state inside the root.")
        } catch {
            guard case NASAssessmentError.stateInsideLibrary = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        XCTAssertEqual(try snapshot(of: corpus.destination), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: insideState.path))
    }
}

private final class TrashCallRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []
    func record(_ url: URL) { lock.lock(); recorded.append(url); lock.unlock() }
    var urls: [URL] { lock.lock(); defer { lock.unlock() }; return recorded }
    var count: Int { urls.count }
}
