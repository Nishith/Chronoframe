import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

/// The copy-destination preflight proves that a network destination supports the atomic
/// no-replace install INV-28 requires, before anything is planned or copied.
final class ChronoframeCoreNASCopyDestinationQualifierTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASCopyDestinationQualifierTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private final class CallRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storedCalls: [(from: String, to: String)] = []
        var calls: [(from: String, to: String)] {
            lock.lock(); defer { lock.unlock() }
            return storedCalls
        }
        func record(from: String, to: String) {
            lock.lock(); defer { lock.unlock() }
            storedCalls.append((from, to))
        }
    }

    private static let remoteClassifier = NASVolumeClassifier { _ in
        NASStatfsSnapshot(
            fileSystemType: "smbfs",
            mountedOn: "/Volumes/Share",
            mountedFrom: "//user@nas.local/Share",
            flags: 0,
            fileSystemID: 1
        )
    }

    private static let localClassifier = NASVolumeClassifier { _ in
        NASStatfsSnapshot(
            fileSystemType: "apfs",
            mountedOn: "/",
            mountedFrom: "/dev/disk3s1",
            flags: UInt32(MNT_LOCAL),
            fileSystemID: 2
        )
    }

    private static let unknownClassifier = NASVolumeClassifier { _ in nil }

    private func makeRoot(_ name: String, createLogs: Bool = true) throws -> URL {
        let root = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: createLogs ? root.appendingPathComponent(".organize_logs", isDirectory: true) : root,
            withIntermediateDirectories: true
        )
        return root
    }

    private func logsContents(_ root: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent(".organize_logs", isDirectory: true).path
        )
    }

    private func qualifier(
        _ classifier: NASVolumeClassifier,
        recorder: CallRecorder = CallRecorder(),
        rename: @escaping @Sendable (String, String) -> Int32
    ) -> NASCopyDestinationQualifier {
        NASCopyDestinationQualifier(
            classifier: classifier,
            exclusiveRename: { from, to in
                recorder.record(from: from, to: to)
                return rename(from, to)
            }
        )
    }

    func testLocalDestinationIsNotProbed() throws {
        let root = try makeRoot("local", createLogs: false)
        let recorder = CallRecorder()
        let subject = qualifier(Self.localClassifier, recorder: recorder) { _, _ in
            XCTFail("A local destination must not be probed")
            return 0
        }

        try subject.check(destinationRoot: root)

        XCTAssertTrue(recorder.calls.isEmpty)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".organize_logs").path),
            "A local destination must not get a .organize_logs directory from the preflight"
        )
    }

    // AGENTS-INVARIANT: 28
    func testRemoteDestinationWithoutExclusiveRenameIsRefused() throws {
        let root = try makeRoot("remote-unsupported")
        let subject = qualifier(Self.remoteClassifier) { _, _ in ENOTSUP }

        XCTAssertThrowsError(try subject.check(destinationRoot: root)) { error in
            guard let refusal = error as? NASCopyDestinationRefusal else {
                return XCTFail("Expected NASCopyDestinationRefusal, got \(error)")
            }
            XCTAssertEqual(refusal, .noAtomicNoReplace(path: root.path, errorCode: ENOTSUP))
        }

        let leftovers = try logsContents(root).filter { $0.hasPrefix(".chronoframe-rename-check-") }
        XCTAssertTrue(leftovers.isEmpty, "The probe must clean up after itself, found \(leftovers)")
    }

    func testEinvalAndEnosysAreRefused() throws {
        for code in [EINVAL, ENOSYS] {
            let root = try makeRoot("remote-\(code)")
            let subject = qualifier(Self.remoteClassifier) { _, _ in code }

            XCTAssertThrowsError(try subject.check(destinationRoot: root)) { error in
                XCTAssertEqual(
                    error as? NASCopyDestinationRefusal,
                    .noAtomicNoReplace(path: root.path, errorCode: code)
                )
            }
            XCTAssertTrue(try logsContents(root).isEmpty)
        }
    }

    func testUnknownVolumeIsProbed() throws {
        let root = try makeRoot("unknown")
        let recorder = CallRecorder()
        let subject = qualifier(Self.unknownClassifier, recorder: recorder) { _, _ in ENOTSUP }

        XCTAssertThrowsError(try subject.check(destinationRoot: root)) { error in
            XCTAssertTrue(error is NASCopyDestinationRefusal, "Unknown volumes fail closed, got \(error)")
        }
        XCTAssertEqual(recorder.calls.count, 1)
    }

    func testRemoteDestinationWithExclusiveRenameQualifies() throws {
        let root = try makeRoot("remote-supported")
        let recorder = CallRecorder()
        let subject = qualifier(Self.remoteClassifier, recorder: recorder) { from, to in
            Darwin.rename(from, to) == 0 ? 0 : errno
        }

        try subject.check(destinationRoot: root)

        XCTAssertEqual(recorder.calls.count, 1)
        let call = try XCTUnwrap(recorder.calls.first)
        XCTAssertTrue(URL(fileURLWithPath: call.from).lastPathComponent.hasPrefix(".chronoframe-rename-check-"))
        XCTAssertTrue(call.from.hasSuffix(".src"))
        XCTAssertTrue(call.to.hasSuffix(".dst"))
        XCTAssertTrue(
            call.from.hasPrefix(root.appendingPathComponent(".organize_logs").path + "/"),
            "The probe must run inside .organize_logs"
        )
        XCTAssertTrue(try logsContents(root).isEmpty, "Nothing may be left behind after a qualifying probe")
    }

    func testOtherRenameErrorIsRethrownAsPOSIX() throws {
        let root = try makeRoot("remote-eacces")
        let subject = qualifier(Self.remoteClassifier) { _, _ in EACCES }

        XCTAssertThrowsError(try subject.check(destinationRoot: root)) { error in
            XCTAssertFalse(error is NASCopyDestinationRefusal, "EACCES is not an unsupported-rename answer")
            XCTAssertEqual((error as? POSIXError)?.code, .EACCES)
        }
        XCTAssertTrue(try logsContents(root).isEmpty)
    }

    func testCleanupNeverRemovesForeignFiles() throws {
        let root = try makeRoot("remote-foreign")
        let logs = root.appendingPathComponent(".organize_logs", isDirectory: true)
        let foreignFile = logs.appendingPathComponent(".chronoframe-rename-check-foreign.src")
        let foreignBytes = Data([0xDE, 0xAD, 0xBE, 0xEF])
        try foreignBytes.write(to: foreignFile)
        let foreignDirectory = logs.appendingPathComponent("keep-me", isDirectory: true)
        try FileManager.default.createDirectory(at: foreignDirectory, withIntermediateDirectories: true)
        let nestedFile = foreignDirectory.appendingPathComponent("nested.bin")
        try Data([1, 2, 3]).write(to: nestedFile)

        let unsupported = qualifier(Self.remoteClassifier) { _, _ in ENOTSUP }
        XCTAssertThrowsError(try unsupported.check(destinationRoot: root))
        let supported = qualifier(Self.remoteClassifier) { from, to in
            Darwin.rename(from, to) == 0 ? 0 : errno
        }
        try supported.check(destinationRoot: root)

        XCTAssertEqual(try Data(contentsOf: foreignFile), foreignBytes)
        XCTAssertEqual(try Data(contentsOf: nestedFile), Data([1, 2, 3]))
        XCTAssertEqual(Set(try logsContents(root)), [foreignFile.lastPathComponent, "keep-me"])
    }
}
