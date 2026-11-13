import Foundation
import XCTest
@testable import ChronoframeAppCore

/// INV-21 for staged (multi-item) sources: the engine compares the manifest's
/// items, not just the staging directory, with the destination.
final class MultiItemSourceOverlapTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var stagingRootURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MultiItemSourceOverlapTests-\(UUID().uuidString)", isDirectory: true)
        stagingRootURL = temporaryDirectoryURL.appendingPathComponent("staging", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingRootURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        stagingRootURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    @MainActor
    private func makeEngine() -> SwiftOrganizerEngine {
        SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: StubProfilesRepository(
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            )
        )
    }

    private func makeDirectory(_ name: String, under parent: URL? = nil) throws -> URL {
        let url = (parent ?? temporaryDirectoryURL).appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Stages the items with the real stager and returns the staging directory.
    private func stage(_ items: [URL]) throws -> URL {
        let staged = try DroppedItemStager(stagingRoot: stagingRootURL).stage(urls: items)
        XCTAssertFalse(staged.wasSingleFolder, "Two items must produce a manifest directory")
        return staged.sourceDirectory
    }

    private func assertOverlapRejected(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case OrganizerEngineError.sourceOverlapsDestination = error else {
            XCTFail("Expected sourceOverlapsDestination, got \(error)", file: file, line: line)
            return
        }
    }

    private func assertListUnreadable(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case OrganizerEngineError.sourceListUnreadable = error else {
            XCTFail("Expected sourceListUnreadable, got \(error)", file: file, line: line)
            return
        }
    }

    private func assertEmpty(_ url: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let contents = try FileManager.default.contentsOfDirectory(atPath: url.path)
        XCTAssertEqual(contents, [], "Nothing may be created under the destination", file: file, line: line)
    }

    // MARK: - Engine entry points

    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightRejectsStagedItemThatContainsDestination() async throws {
        let folderA = try makeDirectory("A")
        let folderB = try makeDirectory("B")
        let destination = try makeDirectory("Organized", under: folderB)
        let stagingDirectory = try stage([folderA, folderB])

        do {
            _ = try await makeEngine().preflight(
                RunConfiguration(mode: .preview, sourcePath: stagingDirectory.path, destinationPath: destination.path)
            )
            XCTFail("Preflight must reject a staged item that contains the destination")
        } catch {
            assertOverlapRejected(error)
        }
        try assertEmpty(destination)
    }

    // AGENTS-INVARIANT: 21
    @MainActor
    func testPreflightRejectsStagedItemInsideDestination() async throws {
        let destination = try makeDirectory("D")
        let inbox = try makeDirectory("Inbox", under: destination)
        let other = try makeDirectory("Other")
        let stagingDirectory = try stage([other, inbox])

        do {
            _ = try await makeEngine().preflight(
                RunConfiguration(mode: .preview, sourcePath: stagingDirectory.path, destinationPath: destination.path)
            )
            XCTFail("Preflight must reject a staged item inside the destination")
        } catch {
            assertOverlapRejected(error)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["Inbox"])
    }

    // AGENTS-INVARIANT: 21
    @MainActor
    func testTransferStartRejectsStagedOverlapToo() throws {
        let folderA = try makeDirectory("A")
        let folderB = try makeDirectory("B")
        let destination = try makeDirectory("Organized", under: folderB)
        let stagingDirectory = try stage([folderA, folderB])
        let configuration = RunConfiguration(
            mode: .transfer,
            sourcePath: stagingDirectory.path,
            destinationPath: destination.path
        )
        let engine = makeEngine()

        XCTAssertThrowsError(try engine.start(configuration)) { error in
            assertOverlapRejected(error)
        }
        XCTAssertThrowsError(try engine.resume(configuration)) { error in
            assertOverlapRejected(error)
        }
        try assertEmpty(destination)
    }

    /// A manifest that cannot be read cannot be checked against the destination,
    /// so every entry point refuses rather than trusting the staging directory alone.
    // AGENTS-INVARIANT: 21
    @MainActor
    func testUnreadableManifestIsRefusedAtPreflightStartAndResume() async throws {
        let folderA = try makeDirectory("A")
        let folderB = try makeDirectory("B")
        let destination = try makeDirectory("Organized")
        let stagingDirectory = try stage([folderA, folderB])
        let manifestURL = stagingDirectory.appendingPathComponent(DroppedItemStager.manifestFilename)
        let garbage = Data("not json".utf8)
        try garbage.write(to: manifestURL)
        let engine = makeEngine()

        do {
            _ = try await engine.preflight(
                RunConfiguration(mode: .preview, sourcePath: stagingDirectory.path, destinationPath: destination.path)
            )
            XCTFail("Preflight must refuse a folder list it cannot read")
        } catch {
            assertListUnreadable(error)
        }

        let configuration = RunConfiguration(
            mode: .transfer,
            sourcePath: stagingDirectory.path,
            destinationPath: destination.path
        )
        XCTAssertThrowsError(try engine.start(configuration)) { assertListUnreadable($0) }
        XCTAssertThrowsError(try engine.resume(configuration)) { assertListUnreadable($0) }
        try assertEmpty(destination)
        XCTAssertEqual(try Data(contentsOf: manifestURL), garbage, "The refusal must not rewrite the manifest")
    }

    @MainActor
    func testUnreadableManifestMessageIsPlainAndReassuring() {
        let text = UserFacingErrorMessage.message(for: OrganizerEngineError.sourceListUnreadable, context: .setup)

        XCTAssertTrue(text.contains("list of folders"))
        XCTAssertTrue(text.contains("No files were changed."))
        XCTAssertFalse(text.lowercased().contains("json"))
        XCTAssertFalse(text.lowercased().contains("manifest"))
    }

    @MainActor
    func testStagedItemsDisjointFromDestinationPassPreflight() async throws {
        let folderA = try makeDirectory("A")
        let folderB = try makeDirectory("B")
        let destination = try makeDirectory("Organized")
        let stagingDirectory = try stage([folderA, folderB])

        let preflight = try await makeEngine().preflight(
            RunConfiguration(mode: .preview, sourcePath: stagingDirectory.path, destinationPath: destination.path)
        )
        XCTAssertEqual(preflight.resolvedSourcePath, stagingDirectory.path)
        XCTAssertEqual(preflight.resolvedDestinationPath, destination.path)
    }

    // MARK: - Core helpers

    func testDropManifestLookupAbsentItemsUnreadable() throws {
        // Absent: a plain folder with no manifest.
        let plain = try makeDirectory("plain")
        XCTAssertEqual(MediaDiscovery.dropManifestLookup(inSourceRoot: plain.path), .absent)

        // Items: a real staged drop lists its item paths in order.
        let folderA = try makeDirectory("A")
        let folderB = try makeDirectory("B")
        let stagingDirectory = try stage([folderA, folderB])
        XCTAssertEqual(
            MediaDiscovery.dropManifestLookup(inSourceRoot: stagingDirectory.path),
            .items([folderA.resolvingSymlinksInPath().path, folderB.resolvingSymlinksInPath().path])
        )

        // Unreadable: a manifest that is not valid JSON. The lookup never rewrites it.
        let broken = try makeDirectory("broken")
        let manifestURL = broken.appendingPathComponent(DroppedItemStager.manifestFilename)
        let garbage = Data("not json".utf8)
        try garbage.write(to: manifestURL)
        XCTAssertEqual(MediaDiscovery.dropManifestLookup(inSourceRoot: broken.path), .unreadable)
        XCTAssertEqual(try Data(contentsOf: manifestURL), garbage)
    }

    func testItemsConflictReturnsFirstConflictInOrder() throws {
        let destination = try makeDirectory("Organized")
        let inside = try makeDirectory("Inbox", under: destination)
        let parent = try makeDirectory("Parent")
        let child = try makeDirectory("Organized2", under: parent)
        let sibling = try makeDirectory("Sibling")

        XCTAssertNil(SourceDestinationDisjointness.conflict(sourceItemPaths: [], destinationPath: destination.path))
        XCTAssertNil(SourceDestinationDisjointness.conflict(
            sourceItemPaths: [sibling.path, parent.path],
            destinationPath: destination.path
        ))
        XCTAssertEqual(
            SourceDestinationDisjointness.conflict(
                sourceItemPaths: [sibling.path, inside.path, destination.path],
                destinationPath: destination.path
            ),
            .sourceInsideDestination
        )
        // Order matters: the first conflicting item decides the result.
        XCTAssertEqual(
            SourceDestinationDisjointness.conflict(
                sourceItemPaths: [sibling.path, parent.path, inside.path],
                destinationPath: child.path
            ),
            .destinationInsideSource
        )
        XCTAssertEqual(
            SourceDestinationDisjointness.conflict(
                sourceItemPaths: [inside.path, parent.path],
                destinationPath: destination.path
            ),
            .sourceInsideDestination
        )
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
