import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreMediaDiscoveryTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeCoreMediaDiscoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testDiscoverMediaFilesUsesSortedTraversalAndSupportedExtensionsOnly() throws {
        try writeFile("zeta/IMG_20240102_111111.jpg")
        try writeFile("alpha/VID_20240101_010101.mov")
        try writeFile("alpha/notes.txt")
        try writeFile("alpha/beta/PANO_20231225_090000.jpg")

        let discovered = try MediaDiscovery.discoverMediaFiles(at: temporaryDirectoryURL)

        XCTAssertEqual(
            normalize(discovered),
            [
                "alpha/VID_20240101_010101.mov",
                "alpha/beta/PANO_20231225_090000.jpg",
                "zeta/IMG_20240102_111111.jpg",
            ]
        )
    }

    func testDiscoverMediaFilesSkipsHiddenEntriesAndSkipFiles() throws {
        try writeFile(".hidden/IMG_20240101_010101.jpg")
        try writeFile("visible/.ignored.mov")
        try writeFile("visible/profiles.yaml")
        try writeFile("visible/README.md")
        try writeFile("visible/IMG_20240101_010101.jpg")

        let discovered = try MediaDiscovery.discoverMediaFiles(at: temporaryDirectoryURL)

        XCTAssertEqual(normalize(discovered), ["visible/IMG_20240101_010101.jpg"])
    }

    func testWalkEntriesIncludesVisibleDirectoriesInDeterministicOrder() throws {
        try writeFile("b-dir/IMG_20240102_111111.jpg")
        try writeFile("a-dir/nested/VID_20240101_010101.mov")

        let entries = try MediaDiscovery.walkEntries(at: temporaryDirectoryURL)

        XCTAssertEqual(
            entries.map { "\(normalize($0.path)):\($0.isDirectory ? "dir" : "file")" },
            [
                "a-dir:dir",
                "a-dir/nested:dir",
                "a-dir/nested/VID_20240101_010101.mov:file",
                "b-dir:dir",
                "b-dir/IMG_20240102_111111.jpg:file",
            ]
        )
    }

    func testDirectoryIssueInitializerKeepsPathAndMessage() {
        let issue = MediaDiscovery.DirectoryIssue(path: "/photos/raw", message: "Skipped unreadable folder")

        XCTAssertEqual(issue.path, "/photos/raw")
        XCTAssertEqual(issue.message, "Skipped unreadable folder")
    }

    private func writeFile(_ relativePath: String) throws {
        let url = temporaryDirectoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("chronoframe".utf8).write(to: url)
    }

    private func normalize(_ paths: [String]) -> [String] {
        paths.map(normalize)
    }

    /// Phase 1 finding #9 regression: the drop-manifest path used to
    /// descend into any directory the manifest named — including
    /// symbolic links, app bundles, and `.photoslibrary` packages —
    /// because `walk()` only filtered the children, not the root it
    /// was given. The fix applies the same symlink/package screen to
    /// each manifest entry and emits a `DirectoryIssue` for skipped
    /// ones.
    func testDropManifestSkipsPackageDirectoriesAndEmitsDirectoryIssue() throws {
        // Build a fake `.photoslibrary` package containing a JPEG that
        // would be discovered if the manifest were honored blindly.
        let library = temporaryDirectoryURL.appendingPathComponent("Fake Library.photoslibrary", isDirectory: true)
        let originals = library.appendingPathComponent("originals", isDirectory: true)
        try FileManager.default.createDirectory(at: originals, withIntermediateDirectories: true)
        try Data("payload".utf8).write(
            to: originals.appendingPathComponent("IMG_20240101_010101.jpg")
        )

        // Stage a manifest pointing at the package as a directory.
        let stagingDir = temporaryDirectoryURL.appendingPathComponent("stage", isDirectory: true)
        try FileManager.default.createDirectory(at: stagingDir, withIntermediateDirectories: true)
        let manifest: [String: Any] = [
            "items": [
                ["path": library.path, "isDirectory": true]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: stagingDir.appendingPathComponent(".chronoframe_drop_manifest.json"))

        let discovered = try MediaDiscovery.discoverMediaFiles(
            at: stagingDir,
            onDirectoryIssue: { issue in
                Task { @MainActor in /* keep signature sendable; no-op store */ }
                _ = issue
            }
        )
        XCTAssertTrue(discovered.isEmpty,
            "Package entries in the drop manifest must not produce discovered files")

        // Re-run with a synchronous collector to verify the issue is emitted.
        let collected = LockedIssues()
        _ = try MediaDiscovery.discoverMediaFiles(
            at: stagingDir,
            onDirectoryIssue: { collected.append($0) }
        )
        let issuePaths = collected.values.map(\.path)
        XCTAssertTrue(
            issuePaths.contains { $0.hasSuffix("Fake Library.photoslibrary") },
            "Expected a DirectoryIssue for the skipped .photoslibrary; got \(issuePaths)"
        )
        XCTAssertTrue(
            collected.values.allSatisfy { $0.message.contains("package") || $0.message.contains("symlink") || $0.message.contains("photo libraries") },
            "Issue message should explain why the entry was skipped"
        )
    }

    func testDropManifestRejectsEntriesOutsideSelectedRootByDefault() throws {
        let outsideDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeMediaDiscoveryOutside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: outsideDirectory) }

        let outsideImage = outsideDirectory.appendingPathComponent("IMG_20240101_010101.jpg")
        try Data("outside".utf8).write(to: outsideImage)

        let manifest: [String: Any] = [
            "items": [
                ["path": outsideImage.path, "isDirectory": false]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: temporaryDirectoryURL.appendingPathComponent(".chronoframe_drop_manifest.json"))

        let collected = LockedIssues()
        let discovered = try MediaDiscovery.discoverMediaFiles(
            at: temporaryDirectoryURL,
            onDirectoryIssue: { collected.append($0) }
        )

        XCTAssertTrue(discovered.isEmpty)
        XCTAssertEqual(collected.values.map(\.path), [outsideImage.path])
        XCTAssertTrue(collected.values[0].message.contains("outside source root"))
    }

    func testDropManifestDiscoversOnlySupportedVisibleFilesOnce() throws {
        try writeFile("IMG_20240101_010101.jpg")
        try writeFile(".hidden.jpg")
        try writeFile("notes.txt")

        let imageURL = temporaryDirectoryURL.appendingPathComponent("IMG_20240101_010101.jpg")
        let hiddenURL = temporaryDirectoryURL.appendingPathComponent(".hidden.jpg")
        let notesURL = temporaryDirectoryURL.appendingPathComponent("notes.txt")
        let manifest: [String: Any] = [
            "items": [
                ["path": imageURL.path, "isDirectory": false],
                ["path": imageURL.path, "isDirectory": false],
                ["path": hiddenURL.path, "isDirectory": false],
                ["path": notesURL.path, "isDirectory": false]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: manifest)
        try data.write(to: temporaryDirectoryURL.appendingPathComponent(".chronoframe_drop_manifest.json"))

        let discovered = try MediaDiscovery.discoverMediaFiles(at: temporaryDirectoryURL)

        XCTAssertEqual(discovered, [imageURL.path])
    }

    func testDropManifestReportsCorruptJSONInsteadOfSilentlyReturningEmptyWalk() throws {
        let manifestURL = temporaryDirectoryURL.appendingPathComponent(".chronoframe_drop_manifest.json")
        try Data("{ nope".utf8).write(to: manifestURL)

        let collected = LockedIssues()
        let discovered = try MediaDiscovery.discoverMediaFiles(
            at: temporaryDirectoryURL,
            onDirectoryIssue: { collected.append($0) }
        )

        XCTAssertTrue(discovered.isEmpty)
        XCTAssertEqual(collected.values.count, 1)
        XCTAssertEqual(collected.values[0].path, manifestURL.path)
        XCTAssertTrue(collected.values[0].message.contains("Drop manifest could not be read"))
    }

    private func normalize(_ path: String) -> String {
        let absolute = URL(fileURLWithPath: path).standardizedFileURL.path
        let root = temporaryDirectoryURL.standardizedFileURL.path + "/"
        return absolute.replacingOccurrences(of: root, with: "")
    }
}

/// Thread-safe issue collector for the @Sendable callback boundary.
private final class LockedIssues: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [MediaDiscovery.DirectoryIssue] = []

    var values: [MediaDiscovery.DirectoryIssue] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func append(_ issue: MediaDiscovery.DirectoryIssue) {
        lock.lock()
        storage.append(issue)
        lock.unlock()
    }
}
