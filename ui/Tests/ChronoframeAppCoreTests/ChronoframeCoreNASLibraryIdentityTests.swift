import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreNASLibraryIdentityTests: XCTestCase {
    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASLibraryIdentityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tempRoot {
            try? FileManager.default.removeItem(at: tempRoot)
        }
    }

    // MARK: - Fixtures

    private func volume(
        kind: NASVolumeKind = .remote,
        fileSystemType: String = "smbfs",
        mountPoint: String = "/Volumes/photo",
        serverHost: String? = "diskstation.local",
        shareName: String? = "photo",
        fileSystemID: UInt64 = 42
    ) -> NASVolumeObservation {
        NASVolumeObservation(
            kind: kind,
            fileSystemType: fileSystemType,
            mountPoint: mountPoint,
            serverHost: serverHost,
            shareName: shareName,
            fileSystemID: fileSystemID,
            observedPath: mountPoint + "/Family"
        )
    }

    private func observation(
        volume: NASVolumeObservation? = nil,
        rootRelativePath: String = "Family",
        rootFileID: UInt64 = 1001,
        shareRootFileID: UInt64 = 2,
        rootCreationTime: TimeInterval? = 1_700_000_000
    ) -> NASLibraryObservation {
        NASLibraryObservation(
            volume: volume ?? self.volume(),
            rootRelativePath: rootRelativePath,
            rootFileID: rootFileID,
            shareRootFileID: shareRootFileID,
            rootCreationTime: rootCreationTime
        )
    }

    // MARK: - compare

    func testSameObservationIsSame() {
        XCTAssertEqual(NASLibraryIdentity.compare(recorded: observation(), observed: observation()), .same)
    }

    func testDifferentMountPointIsRemounted() {
        let remounted = observation(volume: volume(mountPoint: "/Volumes/photo-1"))
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: remounted),
            .remounted(newMountPoint: "/Volumes/photo-1")
        )
    }

    func testLocalDirectoryAtOldMountPathIsMismatchNotRemote() {
        let local = observation(volume: volume(kind: .local, fileSystemType: "apfs", serverHost: nil, shareName: nil))
        guard case .mismatch(let reasons) = NASLibraryIdentity.compare(recorded: observation(), observed: local) else {
            return XCTFail("A local directory at the old mount path must be a mismatch")
        }
        XCTAssertTrue(reasons.contains(.notRemote))
        XCTAssertTrue(reasons.contains(.fileSystemTypeChanged))
    }

    func testReplacedShareWithSameNameIsMismatchByRootFileID() {
        let replaced = observation(rootFileID: 9999, shareRootFileID: 2)
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: replaced),
            .mismatch([.rootFileIDChanged])
        )
    }

    func testShareNameCompareIsCaseInsensitive() {
        let upper = observation(volume: volume(shareName: "PHOTO"))
        XCTAssertEqual(NASLibraryIdentity.compare(recorded: observation(), observed: upper), .same)

        let different = observation(volume: volume(shareName: "video"))
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: different),
            .mismatch([.shareNameChanged])
        )
    }

    func testRootRelativePathCompareIsNFCAndCaseInsensitive() {
        let nfc = "Caf\u{00E9}/Photos"
        let nfd = "Cafe\u{0301}/photos"
        XCTAssertNotEqual(Array(nfc.utf8), Array(nfd.utf8))
        XCTAssertEqual(
            NASLibraryIdentity.compare(
                recorded: observation(rootRelativePath: nfc),
                observed: observation(rootRelativePath: nfd)
            ),
            .same
        )
        XCTAssertEqual(
            NASLibraryIdentity.compare(
                recorded: observation(rootRelativePath: nfc),
                observed: observation(rootRelativePath: "Other")
            ),
            .mismatch([.rootRelativePathChanged])
        )
    }

    func testServerHostChangeIsAmbiguous() {
        let otherHost = observation(volume: volume(serverHost: "192.168.1.20"))
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: otherHost),
            .ambiguous([.serverHostChanged])
        )
    }

    func testMissingShareNameIsAmbiguous() {
        let noShare = observation(volume: volume(shareName: nil))
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: noShare),
            .ambiguous([.missingShareName])
        )
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: noShare, observed: observation()),
            .ambiguous([.missingShareName])
        )
    }

    func testMismatchTakesPrecedenceOverAmbiguous() {
        let observed = observation(
            volume: volume(fileSystemType: "nfs", serverHost: "other.local", shareName: "PHOTO"),
            rootRelativePath: "Elsewhere",
            rootFileID: 5,
            shareRootFileID: 3,
            rootCreationTime: 1_700_000_100
        )
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: observed),
            .mismatch([
                .fileSystemTypeChanged,
                .rootRelativePathChanged,
                .rootFileIDChanged,
                .shareRootFileIDChanged,
                .rootCreationTimeChanged,
            ])
        )

        // Ambiguous reasons (missing share, host change) never appear next to a mismatch.
        let mixed = observation(
            volume: volume(serverHost: "other.local", shareName: nil),
            rootFileID: 5
        )
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: mixed),
            .mismatch([.rootFileIDChanged])
        )

        // notRemote comes first.
        let local = observation(
            volume: volume(kind: .local, fileSystemType: "apfs", serverHost: nil, shareName: nil),
            rootFileID: 5
        )
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: local),
            .mismatch([.notRemote, .fileSystemTypeChanged, .rootFileIDChanged])
        )

        // Ambiguous reasons keep contract order: missingShareName before serverHostChanged.
        let ambiguous = observation(volume: volume(serverHost: "other.local", shareName: nil))
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(), observed: ambiguous),
            .ambiguous([.missingShareName, .serverHostChanged])
        )
    }

    func testZeroShareRootFileIDIsNotCompared() {
        XCTAssertEqual(
            NASLibraryIdentity.compare(recorded: observation(shareRootFileID: 0), observed: observation(shareRootFileID: 77)),
            .same
        )
    }

    func testCreationTimeWithinOneSecondIsIgnored() {
        XCTAssertEqual(
            NASLibraryIdentity.compare(
                recorded: observation(rootCreationTime: 1_700_000_000),
                observed: observation(rootCreationTime: 1_700_000_001)
            ),
            .same
        )
        XCTAssertEqual(
            NASLibraryIdentity.compare(
                recorded: observation(rootCreationTime: 1_700_000_000),
                observed: observation(rootCreationTime: nil)
            ),
            .same
        )
    }

    func testCreationTimeChangeIsMismatch() {
        XCTAssertEqual(
            NASLibraryIdentity.compare(
                recorded: observation(rootCreationTime: 1_700_000_000),
                observed: observation(rootCreationTime: 1_700_000_001.5)
            ),
            .mismatch([.rootCreationTimeChanged])
        )
    }

    // MARK: - observe

    private func fakeClassifier(mountPoint: String) -> NASVolumeClassifier {
        NASVolumeClassifier { _ in
            NASStatfsSnapshot(
                fileSystemType: "smbfs",
                mountedOn: mountPoint,
                mountedFrom: "//nishith@DiskStation.local/photo",
                flags: 0,
                fileSystemID: 42
            )
        }
    }

    func testObserveComputesRootRelativePath() {
        let statuses: [String: NASLibraryIdentity.FileStatus] = [
            "/Volumes/photo/Family": .init(fileID: 11, isDirectory: true, isSymbolicLink: false, birthTime: 1_700_000_000),
            "/Volumes/photo": .init(fileID: 5, isDirectory: true, isSymbolicLink: false, birthTime: 0),
        ]
        let classifier = fakeClassifier(mountPoint: "/Volumes/photo")

        let nested = NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo/Family"),
            classifier: classifier,
            lstat: { statuses[$0] }
        )
        XCTAssertEqual(nested?.rootRelativePath, "Family")
        XCTAssertEqual(nested?.rootFileID, 11)
        XCTAssertEqual(nested?.shareRootFileID, 5)
        XCTAssertEqual(nested?.rootCreationTime, 1_700_000_000)
        XCTAssertEqual(nested?.volume.shareName, "photo")

        let atMount = NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo"),
            classifier: classifier,
            lstat: { statuses[$0] }
        )
        XCTAssertEqual(atMount?.rootRelativePath, "")
        XCTAssertEqual(atMount?.rootFileID, 5)
        XCTAssertNil(atMount?.rootCreationTime, "A zero birth time means the filesystem did not report one")

        // A sibling whose name merely starts with the mount point must not be treated as inside it.
        let sibling = NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo2/Family"),
            classifier: classifier,
            lstat: { _ in .init(fileID: 1, isDirectory: true, isSymbolicLink: false, birthTime: 1) }
        )
        XCTAssertEqual(sibling?.rootRelativePath, "Volumes/photo2/Family")
        XCTAssertEqual(sibling?.shareRootFileID, 1)

        // NFC normalisation of the stored relative path.
        let decomposed = NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo/Cafe\u{0301}"),
            classifier: classifier,
            lstat: { _ in .init(fileID: 1, isDirectory: true, isSymbolicLink: false, birthTime: 1) }
        )
        XCTAssertEqual(Array(decomposed?.rootRelativePath.utf8 ?? "".utf8), Array("Caf\u{00E9}".utf8))

        // Unreachable mount point leaves the share root ID at 0.
        let noMountStatus = NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo/Family"),
            classifier: classifier,
            lstat: { $0 == "/Volumes/photo/Family" ? statuses[$0] : nil }
        )
        XCTAssertEqual(noMountStatus?.shareRootFileID, 0)

        // Unknown volume (empty mount point): full path without the leading slash, share root 0.
        let unknown = NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo/Family"),
            classifier: NASVolumeClassifier { _ in nil },
            lstat: { statuses[$0] }
        )
        XCTAssertEqual(unknown?.rootRelativePath, "Volumes/photo/Family")
        XCTAssertEqual(unknown?.shareRootFileID, 0)
    }

    func testObserveRejectsSymlinkRoot() throws {
        let target = tempRoot.appendingPathComponent("target", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let link = tempRoot.appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        let result = NASLibraryIdentity.observe(
            rootURL: link,
            classifier: fakeClassifier(mountPoint: tempRoot.path)
        )
        XCTAssertNil(result)

        let injected = NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo/Family"),
            classifier: fakeClassifier(mountPoint: "/Volumes/photo"),
            lstat: { _ in .init(fileID: 1, isDirectory: true, isSymbolicLink: true, birthTime: 1) }
        )
        XCTAssertNil(injected)

        // A real directory is accepted by the live lstat.
        let real = NASLibraryIdentity.observe(
            rootURL: target,
            classifier: fakeClassifier(mountPoint: tempRoot.path)
        )
        XCTAssertEqual(real?.rootRelativePath, "target")
        XCTAssertNotNil(real)
        XCTAssertNotEqual(real?.rootFileID, 0)
    }

    func testObserveRejectsFileRoot() throws {
        let file = tempRoot.appendingPathComponent("plain.txt")
        try Data("x".utf8).write(to: file)

        XCTAssertNil(NASLibraryIdentity.observe(
            rootURL: file,
            classifier: fakeClassifier(mountPoint: tempRoot.path)
        ))
        XCTAssertNil(NASLibraryIdentity.observe(
            rootURL: tempRoot.appendingPathComponent("missing", isDirectory: true),
            classifier: fakeClassifier(mountPoint: tempRoot.path)
        ))
        XCTAssertNil(NASLibraryIdentity.observe(
            rootURL: URL(fileURLWithPath: "/Volumes/photo/Family"),
            classifier: fakeClassifier(mountPoint: "/Volumes/photo"),
            lstat: { _ in .init(fileID: 1, isDirectory: false, isSymbolicLink: false, birthTime: 1) }
        ))
    }

    // MARK: - share lease key

    func testLeaseKeyIgnoresServerHost() {
        let byName = NASShareLeaseKey.key(volume: volume(serverHost: "diskstation.local"), shareRootFileID: 2)
        let byIP = NASShareLeaseKey.key(volume: volume(serverHost: "192.168.1.20"), shareRootFileID: 2)
        let noHost = NASShareLeaseKey.key(volume: volume(serverHost: nil), shareRootFileID: 2)
        XCTAssertEqual(byName, byIP)
        XCTAssertEqual(byName, noHost)
        XCTAssertEqual(byName, NASShareLeaseKey.key(volume: volume(shareName: "PHOTO"), shareRootFileID: 2))
    }

    func testLeaseKeyDiffersByShareAndShareRootFileID() {
        let base = NASShareLeaseKey.key(volume: volume(), shareRootFileID: 2)
        XCTAssertNotEqual(base, NASShareLeaseKey.key(volume: volume(shareName: "video"), shareRootFileID: 2))
        XCTAssertNotEqual(base, NASShareLeaseKey.key(volume: volume(), shareRootFileID: 3))
        XCTAssertNotEqual(base, NASShareLeaseKey.key(volume: volume(fileSystemType: "nfs"), shareRootFileID: 2))
        // Without a share name the file system ID separates volumes.
        let noShareA = NASShareLeaseKey.key(volume: volume(shareName: nil, fileSystemID: 1), shareRootFileID: 2)
        let noShareB = NASShareLeaseKey.key(volume: volume(shareName: nil, fileSystemID: 2), shareRootFileID: 2)
        XCTAssertNotEqual(noShareA, noShareB)
    }

    func testLeaseKeyIsThirtyTwoLowercaseHex() {
        let key = NASShareLeaseKey.key(volume: volume(shareName: "Photo"), shareRootFileID: 2)
        XCTAssertEqual(key.count, 32)
        XCTAssertTrue(key.allSatisfy { "0123456789abcdef".contains($0) })

        var hasher = BLAKE2bHasher()
        hasher.update(Data("v1|smbfs|photo|2".utf8))
        XCTAssertEqual(key, String(hasher.finalizeHexDigest().prefix(32)))

        var fsidHasher = BLAKE2bHasher()
        fsidHasher.update(Data("v1|smbfs|fsid:42|2".utf8))
        XCTAssertEqual(
            NASShareLeaseKey.key(volume: volume(shareName: nil), shareRootFileID: 2),
            String(fsidHasher.finalizeHexDigest().prefix(32))
        )
    }
}
