import Foundation
import XCTest
@testable import ChronoframeAppCore

/// The engine reports sidecar companions in the preview and in the run
/// metrics (EPR WP-04b, C-03.6 and C-03.9). A companion is an ordinary copy
/// job, so nothing here changes how a run copies.
@MainActor
final class CompanionPreviewTests: XCTestCase {
    private var rootURL: URL!
    private var sourceURL: URL!
    private var destinationURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompanionPreviewTests-\(UUID().uuidString)", isDirectory: true)
        sourceURL = rootURL.appendingPathComponent("source", isDirectory: true)
        destinationURL = rootURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        try super.tearDownWithError()
    }

    private func write(_ text: String, _ name: String) throws {
        try Data(text.utf8).write(to: sourceURL.appendingPathComponent(name))
    }

    private func makeEngine() -> SwiftOrganizerEngine {
        SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: StubProfilesRepository(
                profilesFileURL: rootURL.appendingPathComponent("profiles.yaml")
            )
        )
    }

    private func run(_ mode: RunMode) async throws -> [RunEvent] {
        let stream = try makeEngine().start(
            RunConfiguration(mode: mode, sourcePath: sourceURL.path, destinationPath: destinationURL.path)
        )
        var events: [RunEvent] = []
        for try await event in stream {
            events.append(event)
        }
        return events
    }

    private func warnings(in events: [RunEvent]) -> [String] {
        events.compactMap { event in
            if case let .issue(issue) = event, issue.severity == .warning { return issue.message }
            return nil
        }
    }

    private func summary(of events: [RunEvent]) throws -> RunSummary {
        guard case let .complete(summary)? = events.last else {
            XCTFail("Expected a completion summary")
            throw CancellationError()
        }
        return summary
    }

    func testUnresolvedCompanionsListedInPreviewAndDoNotBlockRun() async throws {
        // A RAW+JPEG pair sharing one .xmp, plus an .xmp with no photo.
        try write("raw bytes", "IMG_20240102_101010.dng")
        try write("jpeg bytes", "IMG_20240102_101010.jpg")
        try write("<x:xmpmeta>shared</x:xmpmeta>", "IMG_20240102_101010.xmp")
        try write("<x:xmpmeta>orphan</x:xmpmeta>", "lonely.xmp")

        let preview = try await run(.preview)
        let previewWarnings = warnings(in: preview)
        XCTAssertTrue(previewWarnings.contains("Not copied: IMG_20240102_101010.xmp (matches more than one photo)"), "\(previewWarnings)")
        XCTAssertTrue(previewWarnings.contains("Not copied: lonely.xmp (no matching photo)"), "\(previewWarnings)")

        let previewSummary = try summary(of: preview)
        XCTAssertEqual(previewSummary.status, .dryRunFinished)
        XCTAssertEqual(previewSummary.metrics.plannedCount, 2, "the owners still plan")
        XCTAssertEqual(previewSummary.metrics.plannedCompanionCount, 0)
        XCTAssertEqual(previewSummary.metrics.unresolvedCompanionCount, 2)

        let transfer = try await run(.transfer)
        let transferSummary = try summary(of: transfer)
        XCTAssertEqual(transferSummary.status, .finished)
        XCTAssertEqual(transferSummary.metrics.copiedCount, 2)
        XCTAssertEqual(transferSummary.metrics.copiedCompanionCount, 0)
        XCTAssertEqual(transferSummary.metrics.unresolvedCompanionCount, 2)
        XCTAssertTrue(warnings(in: transfer).contains("Not copied: lonely.xmp (no matching photo)"))

        // Neither unresolved companion reached the destination.
        let copied = FileManager.default.enumerator(atPath: destinationURL.path)?.allObjects as? [String] ?? []
        XCTAssertFalse(copied.contains { $0.lowercased().hasSuffix(".xmp") }, "\(copied)")
    }

    func testPlannedAndCopiedCompanionCountsAreSeparate() async throws {
        try write("owner bytes", "IMG_20240102_101010.jpg")
        try write("<x:xmpmeta>edits</x:xmpmeta>", "IMG_20240102_101010.xmp")
        try write("other photo", "IMG_20240103_101010.jpg")

        let preview = try await run(.preview)
        let previewMetrics = try summary(of: preview).metrics
        XCTAssertEqual(previewMetrics.plannedCount, 3, "companions count as files")
        XCTAssertEqual(previewMetrics.plannedCompanionCount, 1)
        XCTAssertEqual(previewMetrics.unresolvedCompanionCount, 0)
        XCTAssertTrue(warnings(in: preview).isEmpty, "\(warnings(in: preview))")

        let transfer = try await run(.transfer)
        let result = try summary(of: transfer)
        XCTAssertEqual(result.status, .finished)
        XCTAssertEqual(result.metrics.copiedCount, 3)
        XCTAssertEqual(result.metrics.plannedCompanionCount, 1)
        XCTAssertEqual(result.metrics.copiedCompanionCount, 1)
        XCTAssertEqual(result.metrics.unresolvedCompanionCount, 0)
    }

    func testUnresolvedCompanionMessagesUseFileNameOnly() {
        let expected: [(UnresolvedCompanion.Reason, String)] = [
            (.multipleOwners, "Not copied: IMG_1.xmp (matches more than one photo)"),
            (.noOwner, "Not copied: IMG_1.xmp (no matching photo)"),
            (.nameTaken, "Not copied: IMG_1.xmp (that name is already taken in the destination)"),
            (.unreadable, "Not copied: IMG_1.xmp (could not be read)"),
        ]
        for (reason, text) in expected {
            let message = SwiftOrganizerEngine.unresolvedCompanionMessage(
                UnresolvedCompanion(sourcePath: "/a/b/IMG_1.xmp", reason: reason)
            )
            XCTAssertEqual(message, text)
            XCTAssertFalse(message.contains("/a/b"))
        }
    }

    func testRunMetricsDecodesWithoutCompanionCounts() throws {
        let old = Data(#"{"discoveredCount":4,"plannedCount":3,"copiedCount":2}"#.utf8)
        let decoded = try JSONDecoder().decode(RunMetrics.self, from: old)
        XCTAssertEqual(decoded.plannedCount, 3)
        XCTAssertEqual(decoded.plannedCompanionCount, 0)
        XCTAssertEqual(decoded.copiedCompanionCount, 0)
        XCTAssertEqual(decoded.unresolvedCompanionCount, 0)

        let roundTrip = try JSONDecoder().decode(
            RunMetrics.self,
            from: JSONEncoder().encode(RunMetrics(plannedCompanionCount: 2, copiedCompanionCount: 1, unresolvedCompanionCount: 3))
        )
        XCTAssertEqual(roundTrip.plannedCompanionCount, 2)
        XCTAssertEqual(roundTrip.copiedCompanionCount, 1)
        XCTAssertEqual(roundTrip.unresolvedCompanionCount, 3)
    }
}

private final class StubProfilesRepository: ProfilesRepositorying {
    private let storedProfilesFileURL: URL

    init(profilesFileURL: URL) {
        self.storedProfilesFileURL = profilesFileURL
    }

    func profilesFileURL() -> URL { storedProfilesFileURL }
    func loadProfiles() throws -> [Profile] { [] }
    func save(profile: Profile) throws {}
    func deleteProfile(named name: String) throws {}
}
