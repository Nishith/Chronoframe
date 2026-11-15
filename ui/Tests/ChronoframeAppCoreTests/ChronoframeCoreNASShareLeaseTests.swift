import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreNASShareLeaseTests: XCTestCase {
    private var rootURL: URL!
    private var leaseDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeCoreNASShareLeaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        leaseDirectory = rootURL.appendingPathComponent("leases", isDirectory: true)
        NASRemoteLeaseConfiguration.leaseDirectory = leaseDirectory
        DestinationOperationLock.shareRootFileIDProvider = { _ in 4242 }
    }

    override func tearDownWithError() throws {
        NASRemoteLeaseConfiguration.leaseDirectory = nil
        DestinationOperationLock.volumeClassifierProvider = nil
        DestinationOperationLock.shareRootFileIDProvider = nil
        if let rootURL {
            try? FileManager.default.removeItem(at: rootURL)
        }
        rootURL = nil
        leaseDirectory = nil
        try super.tearDownWithError()
    }

    private func makeDestination(_ name: String) throws -> URL {
        let url = rootURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func remoteVolume(
        share: String = "photo",
        host: String = "diskstation.local",
        mountPoint: String = "/Volumes/photo",
        fileSystemID: UInt64 = 77
    ) -> NASVolumeObservation {
        NASVolumeObservation(
            kind: .remote,
            fileSystemType: "smbfs",
            mountPoint: mountPoint,
            serverHost: host,
            shareName: share,
            fileSystemID: fileSystemID,
            observedPath: mountPoint
        )
    }

    private func localVolume() -> NASVolumeObservation {
        NASVolumeObservation(
            kind: .local,
            fileSystemType: "apfs",
            mountPoint: "/",
            serverHost: nil,
            shareName: nil,
            fileSystemID: 1,
            observedPath: "/"
        )
    }

    private func companionLockURL(for volume: NASVolumeObservation) -> URL {
        let key = NASShareLeaseKey.key(volume: volume, shareRootFileID: 4242)
        return leaseDirectory.appendingPathComponent("\(key).lock")
    }

    private func inRootLockURL(_ destination: URL) -> URL {
        destination
            .appendingPathComponent(".organize_logs", isDirectory: true)
            .appendingPathComponent(DestinationOperationLock.filename)
    }

    private func acquire(_ destination: URL, surface: String = "test") throws -> DestinationOperationLease {
        try DestinationOperationLock.acquire(destinationRoot: destination, surface: surface, operation: "transfer")
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testRemoteDestinationsOnSameShareSerialize() throws {
        let volume = remoteVolume()
        DestinationOperationLock.volumeClassifierProvider = { _ in volume }
        let first = try makeDestination("library-a")
        let second = try makeDestination("library-b")

        let lease = try acquire(first, surface: "first host")
        XCTAssertThrowsError(try acquire(second, surface: "second host")) { error in
            XCTAssertTrue(error is DestinationBusyError, "got \(error)")
            XCTAssertEqual((error as? DestinationBusyError)?.diagnostic?.surface, "first host")
        }

        lease.release()
        let retry = try acquire(second, surface: "second host")
        retry.release()
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testMountAliasesShareOneLease() throws {
        let alias1 = remoteVolume(share: "Photo", host: "diskstation.local", mountPoint: "/Volumes/photo")
        let alias2 = remoteVolume(share: "photo", host: "192.168.1.20", mountPoint: "/Volumes/photo-1")
        let first = try makeDestination("via-name")
        let second = try makeDestination("via-ip")
        let firstPath = first.standardizedFileURL.path
        DestinationOperationLock.volumeClassifierProvider = { url in
            url.standardizedFileURL.path.hasPrefix(firstPath) ? alias1 : alias2
        }

        let lease = try acquire(first)
        defer { lease.release() }
        XCTAssertThrowsError(try acquire(second)) { error in
            XCTAssertTrue(error is DestinationBusyError, "got \(error)")
        }
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testDifferentSharesDoNotSerialize() throws {
        let photo = remoteVolume(share: "photo")
        let video = remoteVolume(share: "video", mountPoint: "/Volumes/video")
        let first = try makeDestination("photo-library")
        let second = try makeDestination("video-library")
        let firstPath = first.standardizedFileURL.path
        DestinationOperationLock.volumeClassifierProvider = { url in
            url.standardizedFileURL.path.hasPrefix(firstPath) ? photo : video
        }

        let firstLease = try acquire(first)
        defer { firstLease.release() }
        let secondLease = try acquire(second)
        secondLease.release()
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testLocalDestinationsNeverTakeCompanionLease() throws {
        let volume = localVolume()
        DestinationOperationLock.volumeClassifierProvider = { _ in volume }
        let destination = try makeDestination("local-library")

        let lease = try acquire(destination)
        defer { lease.release() }

        XCTAssertFalse(FileManager.default.fileExists(atPath: leaseDirectory.path), "a local destination must not create the lease directory")
        XCTAssertTrue(FileManager.default.fileExists(atPath: inRootLockURL(destination).path))
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testNoLeaseDirectoryRefusesRemoteDestinationBeforeTouchingIt() throws {
        NASRemoteLeaseConfiguration.leaseDirectory = nil
        let volume = remoteVolume()
        DestinationOperationLock.volumeClassifierProvider = { _ in volume }
        let destination = try makeDestination("library-a")

        XCTAssertThrowsError(try acquire(destination)) { error in
            XCTAssertEqual(error as? NASShareLeaseError, .leaseDirectoryNotConfigured(destinationPath: destination.path))
            XCTAssertEqual(
                (error as? NASShareLeaseError)?.errorDescription,
                "Chronoframe couldn't set up its safeguards for network folders, so it didn't start. Restart Chronoframe and try again. Nothing was changed."
            )
        }

        XCTAssertFalse(
            FileManager.default.fileExists(atPath: inRootLockURL(destination).deletingLastPathComponent().path),
            "A refused acquire must not create the destination's .organize_logs"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: leaseDirectory.path))
    }

    // AGENTS-INVARIANT: 28
    func testNoLeaseDirectoryStillAllowsLocalDestination() throws {
        NASRemoteLeaseConfiguration.leaseDirectory = nil
        let volume = localVolume()
        DestinationOperationLock.volumeClassifierProvider = { _ in volume }
        let destination = try makeDestination("local-library")

        let lease = try acquire(destination)
        lease.release()
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testCompanionReleasedWhenInRootLockFails() throws {
        let volume = remoteVolume()
        DestinationOperationLock.volumeClassifierProvider = { _ in volume }
        let destination = try makeDestination("library-a")

        // Another holder owns only the in-root lock (no companion).
        let rootHolder = try DestinationOperationLock.acquire(
            lockFileURL: inRootLockURL(destination),
            surface: "other",
            operation: "transfer"
        )
        defer { rootHolder.release() }

        XCTAssertThrowsError(try acquire(destination)) { error in
            XCTAssertTrue(error is DestinationBusyError, "got \(error)")
        }

        // The companion taken before the failure must be free again.
        let companion = try DestinationOperationLock.acquire(
            lockFileURL: companionLockURL(for: volume),
            surface: "probe",
            operation: "probe"
        )
        companion.release()
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testReleaseReleasesBothLocks() throws {
        let volume = remoteVolume()
        DestinationOperationLock.volumeClassifierProvider = { _ in volume }
        let destination = try makeDestination("library-a")

        let lease = try acquire(destination)
        XCTAssertThrowsError(try DestinationOperationLock.acquire(
            lockFileURL: companionLockURL(for: volume), surface: "probe", operation: "probe"
        )) { error in
            XCTAssertTrue(error is DestinationBusyError, "the companion is held while the lease is held: \(error)")
        }

        lease.release()

        let companion = try DestinationOperationLock.acquire(
            lockFileURL: companionLockURL(for: volume), surface: "probe", operation: "probe"
        )
        companion.release()
        let inRoot = try DestinationOperationLock.acquire(
            lockFileURL: inRootLockURL(destination), surface: "probe", operation: "probe"
        )
        inRoot.release()

        lease.release() // idempotent
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testLiveClassifierKeepsLocalTemporaryDestinationsOffTheShareLease() throws {
        DestinationOperationLock.volumeClassifierProvider = nil
        let destination = try makeDestination("live-local-library")

        let lease = try acquire(destination)
        defer { lease.release() }

        let leaseFiles = (try? FileManager.default.contentsOfDirectory(atPath: leaseDirectory.path)) ?? []
        XCTAssertTrue(
            leaseFiles.filter { $0.hasSuffix(".lock") }.isEmpty,
            "a local temp destination must not take a share lease: \(leaseFiles)"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: inRootLockURL(destination).path))
    }

    // AGENTS-INVARIANT: 28
    // AGENTS-INVARIANT: 19
    func testLiveShareRootFileIDComesFromTheMountPoint() throws {
        DestinationOperationLock.shareRootFileIDProvider = nil
        let mountDirectory = try makeDestination("fake-mount-point")
        var status = stat()
        XCTAssertEqual(lstat(mountDirectory.path, &status), 0)
        let expectedID = UInt64(status.st_ino)
        XCTAssertNotEqual(expectedID, 0)

        let volume = remoteVolume(mountPoint: mountDirectory.path)
        DestinationOperationLock.volumeClassifierProvider = { _ in volume }
        let destination = try makeDestination("library-on-share")

        let lease = try acquire(destination)
        let expectedKey = NASShareLeaseKey.key(volume: volume, shareRootFileID: expectedID)
        let expectedLock = leaseDirectory.appendingPathComponent("\(expectedKey).lock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedLock.path), "expected \(expectedLock.path)")
        lease.release()

        // A mount point that does not exist falls back to file ID 0.
        let missingMount = rootURL.appendingPathComponent("no-such-mount", isDirectory: true).path
        let missingVolume = remoteVolume(share: "other", mountPoint: missingMount)
        DestinationOperationLock.volumeClassifierProvider = { _ in missingVolume }
        let secondDestination = try makeDestination("library-on-missing-mount")

        let secondLease = try acquire(secondDestination)
        let zeroKey = NASShareLeaseKey.key(volume: missingVolume, shareRootFileID: 0)
        let zeroLock = leaseDirectory.appendingPathComponent("\(zeroKey).lock")
        XCTAssertTrue(FileManager.default.fileExists(atPath: zeroLock.path), "expected \(zeroLock.path)")
        secondLease.release()
    }
}
