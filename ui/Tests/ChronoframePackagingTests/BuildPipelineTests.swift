import Foundation
import XCTest

final class BuildPipelineTests: XCTestCase {
    func testSwiftAppSourcesAreListedInXcodeProject() throws {
        let packageRoot = try Self.packageRoot()
        let projectFile = packageRoot.appendingPathComponent("Chronoframe.xcodeproj/project.pbxproj")
        let sourcesRoot = packageRoot.appendingPathComponent("Sources", isDirectory: true)
        let project = try String(contentsOf: projectFile, encoding: .utf8)

        // PBXFileSystemSynchronizedRootGroup targets are auto-discovered by Xcode at build time;
        // individual files are never listed in project.pbxproj, so skip the filename check for them.
        let syncedTargets: Set<String> = Set(
            project.components(separatedBy: "\n").compactMap { line -> String? in
                guard line.contains("PBXFileSystemSynchronizedRootGroup"),
                      let pathStart = line.range(of: "path = "),
                      let pathEnd = line[pathStart.upperBound...].range(of: ";") else { return nil }
                return String(line[pathStart.upperBound..<pathEnd.lowerBound])
            }
        )

        let enumerator = FileManager.default.enumerator(
            at: sourcesRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        var missing: [String] = []

        while let url = enumerator?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            let relative = url.path.replacingOccurrences(of: sourcesRoot.path + "/", with: "")
            let topLevelTarget = relative.split(separator: "/").first.map(String.init)
            if ["ChronoframeCLI", "ChronoframeCLIKit", "ChronoframePackaging", "ChronoframePackagingTool", "ChronoframeIconTool", "ChronoframeVideoCalibrationTool"].contains(topLevelTarget) {
                continue
            }
            if let target = topLevelTarget, syncedTargets.contains(target) {
                continue
            }
            if !project.contains(url.lastPathComponent) {
                missing.append("ui/Sources/\(relative)")
            }
        }

        XCTAssertEqual(missing.sorted(), [])
    }

    func testBuildScriptFailurePointsToXcodebuildLog() throws {
        let packageRoot = try Self.packageRoot()
        let logURL = packageRoot.appendingPathComponent("build/xcodebuild.log")
        let fakeBinURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildPipelineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeBinURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fakeBinURL) }

        let fakeXcodebuildURL = fakeBinURL.appendingPathComponent("xcodebuild")
        try """
        #!/bin/sh
        echo 'fake xcodebuild failure from test harness' >&2
        exit 42
        """.write(to: fakeXcodebuildURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeXcodebuildURL.path)

        let result = run(
            "/bin/bash",
            arguments: ["build.sh"],
            currentDirectory: packageRoot,
            environment: ["PATH": fakeBinURL.path + ":" + (ProcessInfo.processInfo.environment["PATH"] ?? "")]
        )

        XCTAssertNotEqual(result.returnCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: logURL.path), logURL.path)
        XCTAssertTrue((result.standardOutput + result.standardError).contains("xcodebuild.log"))
        let log = try String(contentsOf: logURL, encoding: .utf8)
        XCTAssertTrue(log.contains("fake xcodebuild failure from test harness"))
    }

    func testStampVersionKeepsMarketingVersionSeparateFromBuildNumber() throws {
        let packageRoot = try Self.packageRoot()
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("StampVersionTests-\(UUID().uuidString)", isDirectory: true)
        let buildRoot = tempRoot.appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let plistURL = buildRoot.appendingPathComponent("Info.plist")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>CFBundleShortVersionString</key>
            <string>0</string>
            <key>CFBundleVersion</key>
            <string>0</string>
        </dict>
        </plist>
        """.write(to: plistURL, atomically: true, encoding: .utf8)

        let scriptURL = packageRoot.appendingPathComponent("Packaging/stamp_version.sh")
        let result = run(
            "/bin/sh",
            arguments: [scriptURL.path],
            currentDirectory: packageRoot,
            environment: [
                "CHRONOFRAME_BUILD_NUMBER": "292",
                "CURRENT_PROJECT_VERSION": "1",
                "INFOPLIST_PATH": "Info.plist",
                "MARKETING_VERSION": "1.1",
                "SRCROOT": packageRoot.path,
                "TARGET_BUILD_DIR": buildRoot.path,
            ]
        )

        XCTAssertEqual(result.returnCode, 0, result.standardError)
        let data = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: String])
        XCTAssertEqual(plist["CFBundleShortVersionString"], "1.1")
        XCTAssertEqual(plist["CFBundleVersion"], "292")
    }

    private static func packageRoot() throws -> URL {
        var url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<5 {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path),
               FileManager.default.fileExists(atPath: url.appendingPathComponent("Chronoframe.xcodeproj").path) {
                return url
            }
            url.deleteLastPathComponent()
        }
        throw NSError(domain: "BuildPipelineTests", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to locate ui package root",
        ])
    }

    private func run(
        _ executable: String,
        arguments: [String],
        currentDirectory: URL,
        environment: [String: String] = [:]
    ) -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = currentDirectory
        process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new }

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return CommandResult(returnCode: 127, standardError: String(describing: error))
        }

        return CommandResult(
            returnCode: process.terminationStatus,
            standardOutput: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            standardError: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        )
    }

    private struct CommandResult {
        var returnCode: Int32
        var standardOutput: String = ""
        var standardError: String = ""
    }
}
