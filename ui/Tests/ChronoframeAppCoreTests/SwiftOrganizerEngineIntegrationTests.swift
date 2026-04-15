import Foundation
import XCTest
@testable import ChronoframeAppCore

final class SwiftOrganizerEngineIntegrationTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SwiftOrganizerEngineIntegrationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    @MainActor
    func testPreflightResolvesProfileAndCountsPendingJobs() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let database = try OrganizerDatabase(url: destinationURL.appendingPathComponent(".organize_cache.db"))
        try database.enqueueJobs([
            CopyJobRecord(
                sourcePath: "/tmp/a.jpg",
                destinationPath: "/tmp/b.jpg",
                identity: FileIdentity(size: 1, digest: "pending"),
                status: .pending
            )
        ])
        database.close()

        let repository = TestProfilesRepository(
            profiles: [
                Profile(name: "camera", sourcePath: sourceURL.path, destinationPath: destinationURL.path),
            ],
            profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
        )
        let engine = SwiftOrganizerEngine(profilesRepository: repository)

        let preflight = try await engine.preflight(
            RunConfiguration(mode: .preview, profileName: "camera", useFastDestinationScan: true)
        )

        XCTAssertEqual(preflight.resolvedSourcePath, sourceURL.path)
        XCTAssertEqual(preflight.resolvedDestinationPath, destinationURL.path)
        XCTAssertEqual(preflight.pendingJobCount, 1)
        XCTAssertEqual(preflight.missingDependencies, [])
        XCTAssertEqual(preflight.profilesFilePath, repository.profilesFileURL().path)
    }

    @MainActor
    func testStartPreviewStreamsPlannerEventsAndWritesArtifacts() async throws {
        let sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationURL = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)

        let fileURL = sourceURL.appendingPathComponent("camera/IMG_20240102_101010.jpg")
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("alpha".utf8).write(to: fileURL)

        let engine = SwiftOrganizerEngine(
            profilesRepository: TestProfilesRepository(
                profiles: [],
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )

        let stream = try engine.start(
            RunConfiguration(
                mode: .preview,
                sourcePath: sourceURL.path,
                destinationPath: destinationURL.path,
                useFastDestinationScan: false
            )
        )
        let events = try await Self.collect(stream)

        XCTAssertEqual(Self.render(events), [
            "startup",
            "phaseStarted:discovery",
            "phaseCompleted:discovery",
            "phaseStarted:dest_hash",
            "phaseCompleted:dest_hash",
            "phaseStarted:src_hash",
            "phaseCompleted:src_hash",
            "phaseStarted:classification",
            "phaseCompleted:classification",
            "copyPlanReady:1",
            "complete:dryRunFinished",
        ])

        guard case let .complete(summary)? = events.last else {
            return XCTFail("Expected complete event")
        }

        XCTAssertEqual(summary.metrics.discoveredCount, 1)
        XCTAssertEqual(summary.metrics.plannedCount, 1)
        XCTAssertEqual(summary.status, .dryRunFinished)
        XCTAssertEqual(summary.title, "Preview complete")
        XCTAssertEqual(summary.artifacts.destinationRoot, destinationURL.path)

        guard let reportPath = summary.artifacts.reportPath else {
            return XCTFail("Missing report path")
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: reportPath))
        let reportContents = try String(contentsOfFile: reportPath, encoding: .utf8)
        XCTAssertTrue(reportContents.contains("Source,Destination,Hash,Status"))
        XCTAssertTrue(reportContents.contains(fileURL.path))
        XCTAssertTrue(reportContents.contains("PENDING"))

        XCTAssertEqual(
            summary.artifacts.logsDirectoryPath,
            destinationURL.appendingPathComponent(".organize_logs", isDirectory: true).path
        )
        XCTAssertEqual(
            summary.artifacts.logFilePath,
            destinationURL.appendingPathComponent(".organize_log.txt").path
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: summary.artifacts.logFilePath ?? ""))
    }

    private static func collect(_ stream: AsyncThrowingStream<RunEvent, Error>) async throws -> [RunEvent] {
        var events: [RunEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private static func render(_ events: [RunEvent]) -> [String] {
        events.map {
            switch $0 {
            case .startup:
                return "startup"
            case let .phaseStarted(phase, _):
                return "phaseStarted:\(phase.rawValue)"
            case let .phaseCompleted(phase, _):
                return "phaseCompleted:\(phase.rawValue)"
            case let .copyPlanReady(count):
                return "copyPlanReady:\(count)"
            case let .complete(summary):
                return "complete:\(summary.status.rawValue)"
            case let .issue(issue):
                return "issue:\(issue.message)"
            case let .phaseProgress(phase, completed, total, _, _):
                return "phaseProgress:\(phase.rawValue):\(completed)/\(total)"
            case let .prompt(message):
                return "prompt:\(message)"
            }
        }
    }
}

private final class TestProfilesRepository: ProfilesRepositorying {
    private var profiles: [Profile]
    private let storedProfilesFileURL: URL

    init(profiles: [Profile], profilesFileURL: URL) {
        self.profiles = profiles
        self.storedProfilesFileURL = profilesFileURL
    }

    func profilesFileURL() -> URL {
        storedProfilesFileURL
    }

    func loadProfiles() throws -> [Profile] {
        profiles
    }

    func save(profile: Profile) throws {
        profiles.removeAll { $0.name == profile.name }
        profiles.append(profile)
    }

    func deleteProfile(named name: String) throws {
        profiles.removeAll { $0.name == name }
    }
}
