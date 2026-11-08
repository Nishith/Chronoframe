import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

// MARK: - Shared NAS test builders (used by the WP-10 test files)

func nasTestObservation(
    kind: NASVolumeKind = .remote,
    fileSystemType: String = "smbfs",
    mountPoint: String = "/Volumes/photo",
    serverHost: String? = "nas.local",
    shareName: String? = "photo",
    relativePath: String = "Photos",
    rootFileID: UInt64 = 100,
    shareRootFileID: UInt64 = 2,
    creationTime: TimeInterval? = 1_000
) -> NASLibraryObservation {
    NASLibraryObservation(
        volume: NASVolumeObservation(
            kind: kind,
            fileSystemType: fileSystemType,
            mountPoint: mountPoint,
            serverHost: serverHost,
            shareName: shareName,
            fileSystemID: 7,
            observedPath: mountPoint + "/" + relativePath
        ),
        rootRelativePath: relativePath,
        rootFileID: rootFileID,
        shareRootFileID: shareRootFileID,
        rootCreationTime: creationTime
    )
}

func nasTestRecord(
    uuid: String = UUID().uuidString,
    name: String = "Photos",
    observation: NASLibraryObservation = nasTestObservation()
) -> NASLibraryRecord {
    NASLibraryRecord(
        libraryUUID: uuid,
        displayName: name,
        bookmark: FolderBookmark(key: "nasLibrary", path: "/Volumes/photo/Photos", data: Data("bookmark-bytes".utf8)),
        lastObservation: observation,
        lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

// MARK: - Registry

final class NASLibraryRegistryTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASRegistryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private var registryURL: URL { directory.appendingPathComponent("nas/libraries.json") }

    func testLoadMissingFileIsEmpty() throws {
        let registry = NASLibraryRegistry(url: registryURL)
        XCTAssertEqual(try registry.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: registryURL.path), "Loading must not create the file")
    }

    func testUpsertReplacesByUUIDAndPersists() throws {
        let registry = NASLibraryRegistry(url: registryURL)
        let first = nasTestRecord(uuid: "A", name: "Family")
        let second = nasTestRecord(uuid: "B", name: "Travel")
        try registry.upsert(first)
        try registry.upsert(second)

        var renamed = first
        renamed.displayName = "Family Photos"
        renamed.lastValidatedAt = Date(timeIntervalSince1970: 1_800_000_000)
        try registry.upsert(renamed)

        // A fresh instance proves the records were written, not just cached.
        let reloaded = try NASLibraryRegistry(url: registryURL).load()
        XCTAssertEqual(reloaded.map(\.libraryUUID), ["A", "B"])
        XCTAssertEqual(reloaded.first?.displayName, "Family Photos")
        XCTAssertEqual(reloaded.first, renamed)

        try registry.remove(libraryUUID: "A")
        XCTAssertEqual(try NASLibraryRegistry(url: registryURL).load().map(\.libraryUUID), ["B"])
        try registry.remove(libraryUUID: "missing")
        XCTAssertEqual(try registry.load().map(\.libraryUUID), ["B"])
    }

    func testRegistryFileNeverContainsUserInfo() throws {
        let parsed = NASVolumeClassifier.parseMountedFrom("//alice:s3cretpw@NAS.local/photo", fileSystemType: "smbfs")
        XCTAssertEqual(parsed.serverHost, "nas.local")
        let observation = nasTestObservation(serverHost: parsed.serverHost, shareName: parsed.shareName)
        let registry = NASLibraryRegistry(url: registryURL)
        try registry.upsert(nasTestRecord(observation: observation))

        let text = try String(contentsOf: registryURL, encoding: .utf8)
        XCTAssertFalse(text.contains("alice"))
        XCTAssertFalse(text.contains("s3cretpw"))
        XCTAssertFalse(text.contains("@"))
        XCTAssertTrue(text.contains("nas.local"))
    }
}

// MARK: - Startup and paths

final class NASStartupTests: XCTestCase {
    private var directory: URL!
    private var savedLeaseDirectory: URL?

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASStartupTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        savedLeaseDirectory = NASRemoteLeaseConfiguration.leaseDirectory
        NASPaths.applicationSupportOverride = directory
    }

    override func tearDown() {
        NASPaths.applicationSupportOverride = nil
        NASRemoteLeaseConfiguration.leaseDirectory = savedLeaseDirectory
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    func testConfigureSetsLeaseDirectoryIdempotently() throws {
        NASRemoteLeaseConfiguration.leaseDirectory = nil

        NASStartup.configure()
        XCTAssertEqual(NASRemoteLeaseConfiguration.leaseDirectory, NASPaths.leaseDirectory)
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: NASPaths.leaseDirectory.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)

        NASStartup.configure()
        XCTAssertEqual(NASRemoteLeaseConfiguration.leaseDirectory, NASPaths.leaseDirectory)
        XCTAssertTrue(FileManager.default.fileExists(atPath: NASPaths.leaseDirectory.path))
        XCTAssertTrue(NASPaths.leaseDirectory.path.hasPrefix(directory.path), "Paths must follow the injected root")
    }

    func testPathsFollowTheContractLayout() throws {
        XCTAssertEqual(NASPaths.root.lastPathComponent, "nas")
        let rootPath = NASPaths.root.path
        XCTAssertEqual(NASPaths.registryURL.path, rootPath + "/libraries.json")
        XCTAssertEqual(NASPaths.libraryDirectory("U1").path, rootPath + "/libraries/U1")
        XCTAssertEqual(NASPaths.assessmentStoreURL("U1").path, rootPath + "/libraries/U1/assessment.db")
        XCTAssertEqual(NASPaths.leaseDirectory.path, rootPath + "/leases")

        try NASPaths.ensureDirectories(for: "U1")
        XCTAssertTrue(FileManager.default.fileExists(atPath: NASPaths.libraryDirectory("U1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: NASPaths.leaseDirectory.path))
        try NASPaths.ensureDirectories(for: nil)
    }
}
