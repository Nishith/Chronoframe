import Foundation
import Darwin
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreFileIdentityHasherTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeCoreFileIdentityHasherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testHashIdentityMatchesChronoframeFastHashReference() throws {
        let fileURL = try writeFile(named: "alpha.jpg", contents: "alpha")

        let identity = try FileIdentityHasher().hashIdentity(at: fileURL)

        XCTAssertEqual(
            identity.rawValue,
            "5_1a486e31c373793e04ad3981405201d7b52e8e85c07bcc79c51704918e6a1a311dc9ceebba0eb132e2d638b3ae09fd4ad9913a75674f59fabf5287fa0c436fd6"
        )
    }

    func testProcessFileReusesCachedIdentityWhenSizeAndMtimeMatch() throws {
        let fileURL = try writeFile(named: "cached.mov", contents: "alpha")
        let metadata = try fileMetadata(for: fileURL)
        let cachedRecord = FileCacheRecord(
            namespace: .source,
            path: fileURL.path,
            identity: FileIdentity(size: 5, digest: "cached-digest"),
            size: metadata.size,
            modificationTime: metadata.modificationTime
        )

        let outcome = FileIdentityHasher().processFile(at: fileURL.path, cachedRecord: cachedRecord)

        XCTAssertEqual(outcome.identity, cachedRecord.identity)
        XCTAssertEqual(outcome.size, metadata.size)
        XCTAssertEqual(outcome.modificationTime, metadata.modificationTime, accuracy: 0.000_1)
        XCTAssertFalse(outcome.wasHashed)
    }

    func testProcessFileRehashesWhenMetadataChanges() throws {
        let fileURL = try writeFile(named: "rehash.jpg", contents: "alpha")
        let staleRecord = FileCacheRecord(
            namespace: .source,
            path: fileURL.path,
            identity: FileIdentity(size: 5, digest: "stale"),
            size: 5,
            modificationTime: 0
        )

        let outcome = FileIdentityHasher().processFile(at: fileURL.path, cachedRecord: staleRecord)

        XCTAssertTrue(outcome.wasHashed)
        XCTAssertEqual(
            outcome.identity?.rawValue,
            "5_1a486e31c373793e04ad3981405201d7b52e8e85c07bcc79c51704918e6a1a311dc9ceebba0eb132e2d638b3ae09fd4ad9913a75674f59fabf5287fa0c436fd6"
        )
    }

    func testHashIdentityFromDescriptorMatchesPathHash() throws {
        let fileURL = try writeFile(named: "descriptor.jpg", contents: "alpha")
        let descriptor = Darwin.open(fileURL.path, O_RDONLY | O_CLOEXEC)
        XCTAssertGreaterThanOrEqual(descriptor, 0)
        defer { Darwin.close(descriptor) }

        let identity = try FileIdentityHasher().hashIdentity(descriptor: descriptor, size: 5)

        XCTAssertEqual(
            identity.rawValue,
            "5_1a486e31c373793e04ad3981405201d7b52e8e85c07bcc79c51704918e6a1a311dc9ceebba0eb132e2d638b3ae09fd4ad9913a75674f59fabf5287fa0c436fd6"
        )
    }

    func testHashIdentityFromInvalidDescriptorThrowsReadError() {
        XCTAssertThrowsError(try FileIdentityHasher().hashIdentity(descriptor: -1, size: 0)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSPOSIXErrorDomain)
            XCTAssertEqual(nsError.code, Int(EBADF))
            XCTAssertEqual(nsError.userInfo[NSFilePathErrorKey] as? String, "<fd:-1>")
            XCTAssertTrue(nsError.localizedDescription.contains("Could not read file"))
        }
    }

    func testProcessFileReturnsMissingResultWhenRegularFileCannotBeOpened() throws {
        let fileURL = try writeFile(named: "unreadable.jpg", contents: "alpha")
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: fileURL.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path) }

        let outcome = FileIdentityHasher().processFile(at: fileURL.path, cachedRecord: nil)

        XCTAssertNil(outcome.identity)
        XCTAssertEqual(outcome.size, 0)
        XCTAssertEqual(outcome.modificationTime, 0)
        XCTAssertFalse(outcome.wasHashed)
    }

    func testProcessFileReturnsMissingResultForUnreadablePath() {
        let outcome = FileIdentityHasher().processFile(
            at: temporaryDirectoryURL.appendingPathComponent("missing.jpg").path,
            cachedRecord: nil
        )

        XCTAssertNil(outcome.identity)
        XCTAssertEqual(outcome.size, 0)
        XCTAssertEqual(outcome.modificationTime, 0)
        XCTAssertFalse(outcome.wasHashed)
    }

    func testHashIdentityThrowsSwiftErrorForDirectoryReadFailure() throws {
        let directoryURL = temporaryDirectoryURL.appendingPathComponent("looks-like-photo.jpg", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(try FileIdentityHasher().hashIdentity(at: directoryURL)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSPOSIXErrorDomain)
            XCTAssertEqual(nsError.userInfo[NSFilePathErrorKey] as? String, directoryURL.path)
        }
    }

    func testProcessFileReturnsMissingResultForDirectoryReadFailure() throws {
        let directoryURL = temporaryDirectoryURL.appendingPathComponent("looks-like-photo.jpg", isDirectory: true)
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let outcome = FileIdentityHasher().processFile(at: directoryURL.path, cachedRecord: nil)

        XCTAssertNil(outcome.identity)
        XCTAssertEqual(outcome.size, 0)
        XCTAssertEqual(outcome.modificationTime, 0)
        XCTAssertFalse(outcome.wasHashed)
    }

    private func writeFile(named name: String, contents: String) throws -> URL {
        let fileURL = temporaryDirectoryURL.appendingPathComponent(name)
        try Data(contents.utf8).write(to: fileURL)
        return fileURL
    }

    private func fileMetadata(for url: URL) throws -> (size: Int64, modificationTime: TimeInterval) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modificationTime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return (size, modificationTime)
    }
}
