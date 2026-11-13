import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreNASVolumeClassifierTests: XCTestCase {
    private let localFlag = UInt32(MNT_LOCAL)

    private func classifier(
        fileSystemType: String,
        mountedFrom: String,
        flags: UInt32,
        mountedOn: String = "/Volumes/Share",
        fileSystemID: UInt64 = 7
    ) -> NASVolumeClassifier {
        NASVolumeClassifier { _ in
            NASStatfsSnapshot(
                fileSystemType: fileSystemType,
                mountedOn: mountedOn,
                mountedFrom: mountedFrom,
                flags: flags,
                fileSystemID: fileSystemID
            )
        }
    }

    func testParsesSMBMountedFromWithUser() {
        let parsed = NASVolumeClassifier.parseMountedFrom("//nishith@DiskStation._smb._tcp.local/photo", fileSystemType: "smbfs")
        XCTAssertEqual(parsed.serverHost, "diskstation._smb._tcp.local")
        XCTAssertEqual(parsed.shareName, "photo")
    }

    func testParsesSMBMountedFromWithDomainPasswordPortAndPercentEncoding() {
        let value = "//WORKGROUP;nishith:secret@192.168.1.20:445/Family%20Archive"
        let parsed = NASVolumeClassifier.parseMountedFrom(value, fileSystemType: "smbfs")
        XCTAssertEqual(parsed.serverHost, "192.168.1.20")
        XCTAssertEqual(parsed.shareName, "Family Archive")

        let observation = classifier(fileSystemType: "smbfs", mountedFrom: value, flags: 0)
            .classify(URL(fileURLWithPath: "/Volumes/Share/Photos"))
        XCTAssertEqual(observation.serverHost, "192.168.1.20")
        XCTAssertEqual(observation.shareName, "Family Archive")
        let description = String(describing: observation)
        XCTAssertFalse(description.contains("nishith"))
        XCTAssertFalse(description.contains("secret"))
    }

    func testParsesSMBMountedFromWithNoUser() {
        let value = "//DiskStation.local/photo"
        let parsed = NASVolumeClassifier.parseMountedFrom(value, fileSystemType: "smbfs")
        XCTAssertEqual(parsed.serverHost, "diskstation.local")
        XCTAssertEqual(parsed.shareName, "photo")

        let observation = classifier(fileSystemType: "smbfs", mountedFrom: value, flags: 0)
            .classify(URL(fileURLWithPath: "/Volumes/Share/Photos"))
        XCTAssertEqual(observation.serverHost, "diskstation.local")
        XCTAssertEqual(observation.shareName, "photo")
    }

    func testParsesSMBMountedFromWithoutShareSegmentOrWithDomainAfterUser() {
        let hostOnly = NASVolumeClassifier.parseMountedFrom("//DiskStation.local", fileSystemType: "smbfs")
        XCTAssertEqual(hostOnly.serverHost, "diskstation.local")
        XCTAssertNil(hostOnly.shareName)

        let domainAfterUser = NASVolumeClassifier.parseMountedFrom("//nishith@WORKGROUP;DiskStation.local/photo", fileSystemType: "smbfs")
        XCTAssertEqual(domainAfterUser.serverHost, "diskstation.local")
        XCTAssertEqual(domainAfterUser.shareName, "photo")
    }

    func testParsesSMBMountedFromWithDomainAndUserButNoPassword() {
        let value = "//WORKGROUP;nishith@DiskStation.local/photo"
        let parsed = NASVolumeClassifier.parseMountedFrom(value, fileSystemType: "smbfs")
        XCTAssertEqual(parsed.serverHost, "diskstation.local")
        XCTAssertEqual(parsed.shareName, "photo")

        let observation = classifier(fileSystemType: "smbfs", mountedFrom: value, flags: 0)
            .classify(URL(fileURLWithPath: "/Volumes/Share/Photos"))
        XCTAssertEqual(observation.serverHost, "diskstation.local")
        XCTAssertEqual(observation.shareName, "photo")
        let description = String(describing: observation)
        XCTAssertFalse(description.contains("nishith"), "The user name must not be kept: \(description)")
        XCTAssertFalse(description.lowercased().contains("workgroup"), "The domain must not be kept: \(description)")
    }

    func testParsesSMBMountedFromWithEmptyShare() {
        let parsed = NASVolumeClassifier.parseMountedFrom("//guest@nas/", fileSystemType: "smbfs")
        XCTAssertEqual(parsed.serverHost, "nas")
        XCTAssertNil(parsed.shareName)
    }

    func testParsesNFSMountedFrom() {
        let parsed = NASVolumeClassifier.parseMountedFrom("nas.local:/volume1/photo", fileSystemType: "nfs")
        XCTAssertEqual(parsed.serverHost, "nas.local")
        XCTAssertEqual(parsed.shareName, "volume1/photo")
    }

    func testLocalDeviceHasNoServerOrShare() {
        let parsed = NASVolumeClassifier.parseMountedFrom("/dev/disk3s1", fileSystemType: "apfs")
        XCTAssertNil(parsed.serverHost)
        XCTAssertNil(parsed.shareName)

        let observation = classifier(fileSystemType: "apfs", mountedFrom: "/dev/disk3s1", flags: localFlag, mountedOn: "/")
            .classify(URL(fileURLWithPath: "/Users"))
        XCTAssertNil(observation.serverHost)
        XCTAssertNil(observation.shareName)
    }

    func testRemoteFileSystemTypeIsRemoteEvenWithLocalFlag() {
        let observation = classifier(fileSystemType: "smbfs", mountedFrom: "//u@nas/photo", flags: localFlag)
            .classify(URL(fileURLWithPath: "/Volumes/Share"))
        XCTAssertEqual(observation.kind, .remote)
        XCTAssertEqual(observation.fileSystemType, "smbfs")
        XCTAssertEqual(observation.mountPoint, "/Volumes/Share")
        XCTAssertEqual(observation.serverHost, "nas")
        XCTAssertEqual(observation.shareName, "photo")
    }

    func testMissingLocalFlagIsRemote() {
        let observation = classifier(fileSystemType: "mystery", mountedFrom: "//u@nas/photo", flags: 0)
            .classify(URL(fileURLWithPath: "/Volumes/Mystery"))
        XCTAssertEqual(observation.kind, .remote)
        // Not in remoteFileSystemTypes: no server or share is parsed.
        XCTAssertNil(observation.serverHost)
        XCTAssertNil(observation.shareName)
    }

    func testLocalAPFSIsLocal() {
        let observation = classifier(fileSystemType: "apfs", mountedFrom: "/dev/disk3s1", flags: localFlag, mountedOn: "/", fileSystemID: 99)
            .classify(URL(fileURLWithPath: "/Users"))
        XCTAssertEqual(observation.kind, .local)
        XCTAssertEqual(observation.fileSystemType, "apfs")
        XCTAssertEqual(observation.mountPoint, "/")
        XCTAssertEqual(observation.fileSystemID, 99)
        XCTAssertEqual(observation.observedPath, "/Users")
    }

    func testWalksToNearestExistingAncestor() {
        let snapshot = NASStatfsSnapshot(fileSystemType: "apfs", mountedOn: "/", mountedFrom: "/dev/disk3s1", flags: localFlag, fileSystemID: 1)
        let queried = QueryRecorder()
        let classifier = NASVolumeClassifier { path in
            queried.append(path)
            return path == "/Volumes/Share/Photos" ? snapshot : nil
        }
        let observation = classifier.classify(URL(fileURLWithPath: "/Volumes/Share/Photos/New/Leaf"))
        XCTAssertEqual(observation.kind, .local)
        XCTAssertEqual(observation.observedPath, "/Volumes/Share/Photos")
        XCTAssertEqual(queried.values, ["/Volumes/Share/Photos/New/Leaf", "/Volumes/Share/Photos/New", "/Volumes/Share/Photos"])
    }

    func testAllStatfsFailuresAreUnknown() {
        let observation = NASVolumeClassifier { _ in nil }.classify(URL(fileURLWithPath: "/Volumes/Gone/Photos"))
        XCTAssertEqual(observation.kind, .unknown)
        XCTAssertEqual(observation, NASVolumeObservation.unknown(observedPath: "/Volumes/Gone/Photos"))
    }

    func testLiveClassifierOnTemporaryDirectoryIsLocal() {
        let observation = NASVolumeClassifier.live.classify(FileManager.default.temporaryDirectory)
        XCTAssertEqual(observation.kind, .local)
        XCTAssertFalse(observation.fileSystemType.isEmpty)
        XCTAssertFalse(observation.mountPoint.isEmpty)
        XCTAssertNil(observation.serverHost)
        XCTAssertNil(observation.shareName)
    }

    func testFileSystemIDPacksBothWords() {
        let path = FileManager.default.temporaryDirectory.standardizedFileURL.path
        var raw = Darwin.statfs()
        XCTAssertEqual(rawStatfs(path, &raw), 0)
        let expected = UInt64(UInt32(bitPattern: raw.f_fsid.val.0)) | (UInt64(UInt32(bitPattern: raw.f_fsid.val.1)) << 32)
        let snapshot = NASVolumeClassifier.live.statfs(path)
        XCTAssertEqual(snapshot?.fileSystemID, expected)
        XCTAssertEqual(snapshot?.fileSystemID, UInt64(UInt32(bitPattern: raw.f_fsid.val.0)) + (UInt64(UInt32(bitPattern: raw.f_fsid.val.1)) << 32))
    }
}

private final class QueryRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func append(_ value: String) {
        lock.lock(); defer { lock.unlock() }
        storage.append(value)
    }

    var values: [String] {
        lock.lock(); defer { lock.unlock() }
        return storage
    }
}

private func rawStatfs(_ path: String, _ buffer: inout Darwin.statfs) -> Int32 {
    statfs(path, &buffer)
}
