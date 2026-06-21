import Foundation
import XCTest
import ChronoframeCore

/// Regression tests for PHASE2_FINDINGS.md NEW15 — every existing
/// "integration" test invokes `ChronoframeCLI.run` in-process, so the
/// actual binary surface (`main.swift`, `CommandLine.arguments` parsing,
/// `Foundation.exit`, stdout/stderr separation, `print` buffering) was
/// never exercised. These tests spawn the built `chronoframe` binary
/// via `Process` and assert real-process behavior.
final class CLIProcessBoundaryTests: XCTestCase {

    /// Locates the SwiftPM-built `chronoframe` executable. We add
    /// `ChronoframeCLI` as a dependency of this test target in
    /// `Package.swift` so `swift test` forces a build of the binary;
    /// in environments where the binary isn't on disk the test skips
    /// rather than failing.
    private func locateExecutable() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["CHRONOFRAME_CLI_PATH"] {
            return URL(fileURLWithPath: override)
        }
        // SwiftPM lays the build product down next to the running
        // xctest bundle.
        let bundleURL = Bundle(for: type(of: self)).bundleURL
        // Bundles in SwiftPM live at `.build/<arch>/debug/*.xctest` so
        // the sibling executable is in the same directory. SwiftPM
        // names the binary after the executable target (`ChronoframeCLI`).
        let candidates = [
            bundleURL.deletingLastPathComponent().appendingPathComponent("ChronoframeCLI"),
            bundleURL.deletingLastPathComponent().appendingPathComponent("chronoframe"),
        ]
        for candidate in candidates where FileManager.default.isExecutableFile(atPath: candidate.path) {
            return candidate
        }
        throw XCTSkip("CLI binary not found at \(candidates.map(\.path).joined(separator: ", ")); run `swift build` first or set CHRONOFRAME_CLI_PATH")
    }

    private struct ProcessOutput {
        var exitCode: Int32
        var stdout: String
        var stderr: String
    }

    private func runProcess(_ executable: URL, args: [String]) throws -> ProcessOutput {
        let process = Process()
        process.executableURL = executable
        process.arguments = args
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        try process.run()
        process.waitUntilExit()
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        return ProcessOutput(
            exitCode: process.terminationStatus,
            stdout: String(decoding: stdoutData, as: UTF8.self),
            stderr: String(decoding: stderrData, as: UTF8.self)
        )
    }

    func testCLIBinaryHelpExitsZeroAndPrintsUsage() throws {
        let executable = try locateExecutable()
        let result = try runProcess(executable, args: ["--help"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.contains("Usage:"),
            "Help output should start with 'Usage:'; got stdout=\(result.stdout)")
        XCTAssertTrue(result.stdout.contains("--source"),
            "Help output should list the --source option")
    }

    func testCLIBinaryUnknownFlagExitsTwoAndReportsTheFlag() throws {
        let executable = try locateExecutable()
        let result = try runProcess(executable, args: ["--no-such-flag"])
        XCTAssertEqual(result.exitCode, 2)
        XCTAssertTrue(
            result.stdout.contains("--no-such-flag") || result.stderr.contains("--no-such-flag"),
            "Error message should reference the offending flag; stdout=\(result.stdout), stderr=\(result.stderr)"
        )
    }

    func testCLIBinaryJSONParseErrorEmitsJSONOnStdoutAtSubprocessBoundary() throws {
        let executable = try locateExecutable()
        let result = try runProcess(executable, args: ["--json", "--workers", "not-an-int"])
        XCTAssertEqual(result.exitCode, 2)
        let trimmed = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let firstLine = trimmed.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let parsed = try JSONSerialization.jsonObject(with: Data(firstLine.utf8))
        guard let dict = parsed as? [String: Any] else {
            XCTFail("Expected a JSON object on stdout, got \(firstLine)")
            return
        }
        XCTAssertEqual(dict["type"] as? String, "error")
        XCTAssertEqual(dict["event_version"] as? Int, 1)
        XCTAssertEqual(dict["kind"] as? String, "usage")
    }

    func testCLILosesDestinationRaceImmediatelyAndMutatesNoMedia() throws {
        let executable = try locateExecutable()
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CLILockRace-\(UUID().uuidString)", isDirectory: true)
        let source = root.appendingPathComponent("source", isDirectory: true)
        let destination = root.appendingPathComponent("destination", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("photo".utf8).write(to: source.appendingPathComponent("photo.jpg"))

        let lease = try DestinationOperationLock.acquire(
            destinationRoot: destination,
            surface: "active test host",
            operation: "transfer"
        )
        defer { lease.release() }
        let started = Date()
        let result = try runProcess(executable, args: [
            "--source", source.path,
            "--dest", destination.path,
            "--yes",
        ])

        XCTAssertEqual(result.exitCode, 1)
        XCTAssertLessThan(Date().timeIntervalSince(started), 2)
        XCTAssertTrue(result.stdout.localizedCaseInsensitiveContains("already"))
        let media = try FileManager.default.contentsOfDirectory(atPath: destination.path)
            .filter { !$0.hasPrefix(".") }
        XCTAssertTrue(media.isEmpty)
    }
}
