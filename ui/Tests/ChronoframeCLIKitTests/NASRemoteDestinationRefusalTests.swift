@testable import ChronoframeCLIKit
import ChronoframeCore
import Foundation
import XCTest

final class NASRemoteDestinationRefusalTests: XCTestCase {
    private var temporaryDirectory: URL!
    private var originalProfilesPath: String?

    override func setUpWithError() throws {
        try super.setUpWithError()
        originalProfilesPath = ProcessInfo.processInfo.environment["CHRONOFRAME_PROFILES_PATH"]
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASRemoteDestinationRefusalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        // Never read the user's real profiles file.
        setenv("CHRONOFRAME_PROFILES_PATH", temporaryDirectory.appendingPathComponent("no-profiles.yaml").path, 1)
    }

    override func tearDownWithError() throws {
        ChronoframeCLI.volumeClassifier = .live
        if let originalProfilesPath {
            setenv("CHRONOFRAME_PROFILES_PATH", originalProfilesPath, 1)
        } else {
            unsetenv("CHRONOFRAME_PROFILES_PATH")
        }
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
        try super.tearDownWithError()
    }

    // MARK: - Classifier fixtures

    private static let remoteSnapshot = NASStatfsSnapshot(
        fileSystemType: "smbfs",
        mountedOn: "/Volumes/photo",
        mountedFrom: "//nishith@diskstation.local/photo",
        flags: 0,
        fileSystemID: 7
    )

    private static let localSnapshot = NASStatfsSnapshot(
        fileSystemType: "apfs",
        mountedOn: "/",
        mountedFrom: "/dev/disk3s1",
        flags: UInt32(MNT_LOCAL),
        fileSystemID: 1
    )

    private static let allRemote = NASVolumeClassifier { _ in remoteSnapshot }
    private static let allLocal = NASVolumeClassifier { _ in localSnapshot }
    private static let allUnknown = NASVolumeClassifier { _ in nil }

    // MARK: - Tests

    // AGENTS-INVARIANT: 28
    @MainActor
    func testTransferToRemoteDestinationIsRefusedBeforeAnyWrite() async throws {
        let source = try makeDirectory("source")
        let destination = try makeDirectory("destination")
        try writeFile(source.appendingPathComponent("IMG_20240501_120000.jpg"), contents: "transfer")
        ChronoframeCLI.volumeClassifier = Self.allRemote

        let options = CLIOptions(
            sourcePath: source.path,
            destinationPath: destination.path,
            workerCount: 1,
            assumeYes: true
        )
        do {
            _ = try await ChronoframeCLI.run(options: options, output: { _ in })
            XCTFail("A transfer to a remote destination must be refused")
        } catch let error as CLIError {
            XCTAssertEqual(error, .remoteDestinationUnsupported(path: destination.path))
        }

        assertNothingWritten(in: destination)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), [])
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testDryRunToRemoteDestinationIsRefused() async throws {
        let source = try makeDirectory("source")
        let destination = try makeDirectory("destination")
        try writeFile(source.appendingPathComponent("IMG_20240501_120000.jpg"), contents: "dry")
        ChronoframeCLI.volumeClassifier = Self.allRemote

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: ["--source", source.path, "--dest", destination.path, "--dry-run", "--workers", "1"],
            output: recorder.append
        )

        XCTAssertEqual(exitCode, 2)
        assertNothingWritten(in: destination)
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testRebuildCacheOnRemoteDestinationIsRefused() async throws {
        let destination = try makeDirectory("destination")
        ChronoframeCLI.volumeClassifier = Self.allRemote

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: ["--rebuild-cache", "--dest", destination.path],
            output: recorder.append
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertFalse(recorder.lines.joined().contains("Rebuilt hash cache"))
        assertNothingWritten(in: destination)
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testStartFreshOnRemoteDestinationIsRefused() async throws {
        let source = try makeDirectory("source")
        let destination = try makeDirectory("destination")
        try writeFile(source.appendingPathComponent("IMG_20240501_120000.jpg"), contents: "fresh")
        ChronoframeCLI.volumeClassifier = Self.allRemote

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: [
                "--source", source.path, "--dest", destination.path,
                "--start-fresh", "--yes", "--workers", "1",
            ],
            output: recorder.append
        )

        XCTAssertEqual(exitCode, 2)
        assertNothingWritten(in: destination)
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testRevertOnRemoteDestinationIsRefused() async throws {
        let destination = try makeDirectory("destination")
        let copiedFile = destination.appendingPathComponent("2024/08/05/2024-08-05_001.jpg")
        try writeFile(copiedFile, contents: "copied")
        let identity = try FileIdentityHasher().hashIdentity(at: copiedFile)
        let receipt = RevertReceipt(
            timestamp: "2026-05-16T12:00:00",
            status: "COMPLETED",
            totalJobs: 1,
            transfers: [
                RevertReceiptTransfer(source: "/source/photo.jpg", dest: copiedFile.path, hash: identity.rawValue),
            ]
        )
        let logs = destination.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let receiptURL = logs.appendingPathComponent("audit_receipt_20260516_120000.json")
        try JSONEncoder().encode(receipt).write(to: receiptURL)
        ChronoframeCLI.volumeClassifier = Self.allRemote

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: ["--revert", receiptURL.path],
            output: recorder.append
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: copiedFile.path), "Revert must not touch files")
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: logs.path),
            [receiptURL.lastPathComponent],
            "Revert must not create a lock or any other artifact"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.appendingPathComponent(".organize_cache.db").path))
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testProfileDestinationOnRemoteVolumeIsRefused() async throws {
        let source = try makeDirectory("source")
        let destination = try makeDirectory("destination")
        try writeFile(source.appendingPathComponent("IMG_20240602_080000.jpg"), contents: "profile")
        let profilesURL = temporaryDirectory.appendingPathComponent("profiles.yaml")
        try """
        camera:
          source: "\(source.path)"
          dest: "\(destination.path)"

        """.write(to: profilesURL, atomically: true, encoding: .utf8)
        setenv("CHRONOFRAME_PROFILES_PATH", profilesURL.path, 1)
        ChronoframeCLI.volumeClassifier = Self.allRemote

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: ["--profile", "camera", "--dry-run", "--workers", "1"],
            output: recorder.append
        )

        XCTAssertEqual(exitCode, 2)
        XCTAssertTrue(recorder.lines.joined(separator: "\n").contains(destination.path))
        assertNothingWritten(in: destination)
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testProfileWithLocalDestOverrideStillRefusesRemoteProfileDestination() async throws {
        let source = try makeDirectory("source")
        let remoteProfileDestination = try makeDirectory("remote-profile-dest")
        let localDestination = try makeDirectory("local-dest")
        try writeFile(source.appendingPathComponent("IMG_20240602_080000.jpg"), contents: "profile")
        let profilesURL = temporaryDirectory.appendingPathComponent("profiles.yaml")
        try """
        nas:
          source: "\(source.path)"
          dest: "\(remoteProfileDestination.path)"

        """.write(to: profilesURL, atomically: true, encoding: .utf8)
        setenv("CHRONOFRAME_PROFILES_PATH", profilesURL.path, 1)
        ChronoframeCLI.volumeClassifier = NASVolumeClassifier { path in
            path.contains("remote-profile-dest") ? Self.remoteSnapshot : Self.localSnapshot
        }

        let argumentSets: [[String]] = [
            ["--profile", "nas", "--dest", localDestination.path, "--dry-run", "--workers", "1"],
            ["--profile", "nas", "--dest", localDestination.path, "--yes", "--workers", "1"],
            ["--rebuild-cache", "--profile", "nas", "--dest", localDestination.path],
        ]
        for arguments in argumentSets {
            let recorder = LineRecorder()
            let exitCode = await ChronoframeCLI.run(arguments: arguments, output: recorder.append)

            XCTAssertEqual(exitCode, 2, "\(arguments)")
            XCTAssertEqual(
                recorder.lines,
                [CLIError.remoteDestinationUnsupported(path: remoteProfileDestination.path).localizedDescription],
                "The refusal must name the profile's network destination: \(arguments)"
            )
            assertNothingWritten(in: remoteProfileDestination)
            assertNothingWritten(in: localDestination)
        }
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testUnknownVolumeIsRefused() async throws {
        let source = try makeDirectory("source")
        let destination = try makeDirectory("destination")
        try writeFile(source.appendingPathComponent("IMG_20240501_120000.jpg"), contents: "unknown")
        ChronoframeCLI.volumeClassifier = Self.allUnknown

        XCTAssertEqual(
            ChronoframeCLI.remoteDestinationRefusal(destinationPath: destination.path, classifier: Self.allUnknown),
            .remoteDestinationUnsupported(path: destination.path)
        )

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: ["--source", source.path, "--dest", destination.path, "--dry-run", "--workers", "1"],
            output: recorder.append
        )

        XCTAssertEqual(exitCode, 2)
        assertNothingWritten(in: destination)
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testRemoteSourceWithLocalDestinationIsAllowed() async throws {
        let source = try makeDirectory("remote-source")
        let destination = try makeDirectory("local-destination")
        try writeFile(source.appendingPathComponent("IMG_20240501_120000.jpg"), contents: "nas-source")

        XCTAssertNil(
            ChronoframeCLI.remoteDestinationRefusal(destinationPath: destination.path, classifier: Self.allLocal)
        )

        // Source lives on a "remote" volume; the destination is local. Only the destination is classified.
        let sourceIsRemote = NASVolumeClassifier { path in
            path.contains("remote-source") ? Self.remoteSnapshot : Self.localSnapshot
        }
        XCTAssertNil(
            ChronoframeCLI.remoteDestinationRefusal(destinationPath: destination.path, classifier: sourceIsRemote)
        )
        ChronoframeCLI.volumeClassifier = sourceIsRemote

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: ["--source", source.path, "--dest", destination.path, "--dry-run", "--workers", "1"],
            output: recorder.append
        )

        XCTAssertEqual(exitCode, 0)
    }

    // AGENTS-INVARIANT: 28
    @MainActor
    func testRefusalMessageAndExitCode() async throws {
        let source = try makeDirectory("source")
        let destination = try makeDirectory("destination")
        ChronoframeCLI.volumeClassifier = Self.allRemote

        let expected = "Chronoframe's command-line tool can't write to a network folder in this version: "
            + "\(destination.path). Use the Chronoframe app for NAS destinations. Nothing was changed."
        XCTAssertEqual(
            CLIError.remoteDestinationUnsupported(path: destination.path).errorDescription,
            expected
        )

        let recorder = LineRecorder()
        let exitCode = await ChronoframeCLI.run(
            arguments: ["--source", source.path, "--dest", destination.path, "--dry-run"],
            output: recorder.append
        )
        // Same exit code as CLIError.usage.
        let usageRecorder = LineRecorder()
        let usageExit = await ChronoframeCLI.run(arguments: ["--bogus"], output: usageRecorder.append)

        XCTAssertEqual(exitCode, 2)
        XCTAssertEqual(exitCode, usageExit)
        XCTAssertEqual(recorder.lines, [expected])
    }

    // MARK: - Helpers

    private func assertNothingWritten(in destination: URL, file: StaticString = #filePath, line: UInt = #line) {
        let fileManager = FileManager.default
        XCTAssertFalse(
            fileManager.fileExists(atPath: destination.appendingPathComponent(".organize_logs").path),
            "A refused run must not create .organize_logs", file: file, line: line
        )
        XCTAssertFalse(
            fileManager.fileExists(atPath: destination.appendingPathComponent(".organize_cache.db").path),
            "A refused run must not create .organize_cache.db", file: file, line: line
        )
    }

    private func makeDirectory(_ name: String) throws -> URL {
        let url = temporaryDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }
}

private final class LineRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    var lines: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ line: String) {
        lock.lock()
        storage.append(line)
        lock.unlock()
    }
}
