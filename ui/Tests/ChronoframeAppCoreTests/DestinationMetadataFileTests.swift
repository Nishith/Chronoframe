import Darwin
import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// The helpers every destination record writer is built on: no-follow reads,
/// the exclusive temporary file and atomic replace, the sweep for temporaries a
/// dead process left behind, and the error shape a refused write surfaces as.
final class DestinationMetadataFileTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("DestinationMetadataFile-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            // Some tests make a directory read-only.
            chmod(url.path, 0o755)
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func makeSentinel(in directory: URL) throws -> URL {
        let sentinel = directory.appendingPathComponent("sentinel-\(UUID().uuidString).txt")
        try Data("SENTINEL".utf8).write(to: sentinel)
        return sentinel
    }

    // MARK: - Reading

    // AGENTS-INVARIANT: 26
    func testReadingAJournalRefusesLinksAndSpecialFiles() throws {
        let directory = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())

        let symlink = directory.appendingPathComponent("symlink.tmp")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: sentinel)
        let hardLink = directory.appendingPathComponent("hardlink.tmp")
        try FileManager.default.linkItem(at: sentinel, to: hardLink)
        let fifo = directory.appendingPathComponent("fifo.tmp")
        XCTAssertEqual(mkfifo(fifo.path, S_IRUSR | S_IWUSR), 0)
        let folder = directory.appendingPathComponent("folder.tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)

        for url in [symlink, hardLink, fifo, folder] {
            XCTAssertThrowsError(try DestinationMetadataFile.readContents(at: url), url.lastPathComponent) { error in
                XCTAssertEqual(error as? DestinationMetadataUnsafeError, DestinationMetadataUnsafeError(itemName: url.lastPathComponent))
            }
        }
    }

    func testReadingARegularFileReturnsItsContentsAndAMissingFileIsNotReportedAsUnsafe() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("journal.tmp")
        try Data("one\ntwo\n".utf8).write(to: file)

        XCTAssertEqual(try DestinationMetadataFile.readContents(at: file), Data("one\ntwo\n".utf8))

        XCTAssertThrowsError(try DestinationMetadataFile.readContents(at: directory.appendingPathComponent("missing.tmp"))) { error in
            XCTAssertFalse(error is DestinationMetadataUnsafeError)
            XCTAssertEqual((error as NSError).code, Int(ENOENT))
        }
    }

    // AGENTS-INVARIANT: 26
    func testReadingRefusesAFileThatIsNotTheOneOpenedEarlier() throws {
        let directory = try makeDirectory()
        let file = directory.appendingPathComponent("journal.tmp")
        let handle = try DestinationMetadataFile.openForAppending(at: file)
        try handle.write(contentsOf: Data("mine".utf8))
        let identity = try XCTUnwrap(DestinationMetadataFile.fileID(of: handle))
        try handle.close()

        XCTAssertEqual(try DestinationMetadataFile.readContents(at: file, expecting: identity), Data("mine".utf8))

        try FileManager.default.removeItem(at: file)
        try Data("theirs".utf8).write(to: file)
        XCTAssertThrowsError(try DestinationMetadataFile.readContents(at: file, expecting: identity)) { error in
            XCTAssertTrue(error is DestinationMetadataUnsafeError, "got \(error)")
        }
    }

    // MARK: - Replacing

    // AGENTS-INVARIANT: 26
    func testReplaceFileReplacesALinkAtTheFinalNameWithoutWritingThroughIt() throws {
        let directory = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        let target = directory.appendingPathComponent("report.csv")
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: sentinel)

        try DestinationMetadataFile.replaceFile(at: target) { try $0.write(contentsOf: Data("fresh".utf8)) }

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "fresh")
        XCTAssertNil(try? FileManager.default.destinationOfSymbolicLink(atPath: target.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["report.csv"])
    }

    func testReplaceFileKeepsTheExistingFileAndLeavesNoTemporaryWhenWritingFails() throws {
        struct WriteFailure: Error {}
        let directory = try makeDirectory()
        let target = directory.appendingPathComponent("report.csv")
        try Data("old".utf8).write(to: target)

        XCTAssertThrowsError(
            try DestinationMetadataFile.replaceFile(at: target) { _ in throw WriteFailure() }
        ) { error in
            XCTAssertTrue(error is WriteFailure)
        }

        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["report.csv"])
    }

    // MARK: - Temporaries a dead process left behind

    private func plantTemporary(
        _ name: String,
        in directory: URL,
        age: TimeInterval,
        now: Date
    ) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("partial".utf8).write(to: url)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-age)], ofItemAtPath: url.path)
        return url
    }

    private func orphanName(_ stem: String) -> String {
        "\(stem).\(UUID().uuidString).tmp"
    }

    // AGENTS-INVARIANT: 26
    func testSweepRemovesOnlyOldTemporariesOfTheRecordWritersAndNothingElse() throws {
        let logs = try makeDirectory()
        let now = Date()
        let old: TimeInterval = 2 * 3600

        let swept = [
            try plantTemporary(orphanName("audit_receipt_a.json"), in: logs, age: old, now: now),
            try plantTemporary(orphanName("dry_run_report_a.csv"), in: logs, age: old, now: now),
            try plantTemporary(orphanName("preview_review_a.jsonl"), in: logs, age: old, now: now),
            try plantTemporary(orphanName("dedupe_audit_receipt_a.json").lowercased(), in: logs, age: old, now: now),
        ]
        let kept = [
            // Recent enough that a writer in another process may still be filling it.
            try plantTemporary(orphanName("audit_receipt_b.json"), in: logs, age: 60, now: now),
            // Recovery evidence and records, however old.
            try plantTemporary("audit_receipt_c.transfers.tmp", in: logs, age: old, now: now),
            try plantTemporary("dedupe_audit_receipt_c.json.spool", in: logs, age: old, now: now),
            try plantTemporary("audit_receipt_c.json", in: logs, age: old, now: now),
            // Not one of our names.
            try plantTemporary("notes.json.tmp", in: logs, age: old, now: now),
            try plantTemporary("audit_receipt_d.json.not-a-uuid.tmp", in: logs, age: old, now: now),
            try plantTemporary(orphanName("holiday.mov"), in: logs, age: old, now: now),
        ]
        let sentinel = try makeSentinel(in: try makeDirectory())
        let link = logs.appendingPathComponent(orphanName("audit_receipt_e.json"))
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: sentinel)
        // Age the link itself, so only its type keeps the sweep away from it.
        var linkTimes = [
            timeval(tv_sec: Int(now.timeIntervalSince1970 - old), tv_usec: 0),
            timeval(tv_sec: Int(now.timeIntervalSince1970 - old), tv_usec: 0),
        ]
        XCTAssertEqual(lutimes(link.path, &linkTimes), 0)
        let folder = logs.appendingPathComponent(orphanName("audit_receipt_f.json"), isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-old)], ofItemAtPath: folder.path)

        let removed = DestinationMetadataFile.removeOrphanedTemporaries(in: logs, now: now)

        XCTAssertEqual(removed, swept.count)
        for url in swept {
            XCTAssertFalse(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
        for url in kept {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), url.lastPathComponent)
        }
        XCTAssertNotNil(try? FileManager.default.destinationOfSymbolicLink(atPath: link.path), "A link is left for the user to look at")
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
    }

    func testSweepOfAMissingFolderRemovesNothing() throws {
        let missing = try makeDirectory().appendingPathComponent("not-there", isDirectory: true)
        XCTAssertEqual(DestinationMetadataFile.removeOrphanedTemporaries(in: missing), 0)
    }

    func testTransferCleanupSweepsTheHiddenLogsFolderToo() throws {
        let destination = try makeDirectory()
        let logs = destination.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let now = Date()
        let orphan = try plantTemporary(orphanName("dry_run_report_a.csv"), in: logs, age: 2 * 3600, now: now)
        let spool = try plantTemporary("audit_receipt_a.transfers.tmp", in: logs, age: 2 * 3600, now: now)

        XCTAssertEqual(TransferExecutor().cleanupTemporaryFiles(at: destination), 1)

        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: spool.path), "A transfer spool is recovery evidence, never cleanup")
    }

    // MARK: - Refused writes are reported in plain words

    func testAMissingLogsFolderIsReportedAsAFolderThatIsNoLongerAvailable() throws {
        let missing = try makeDirectory()
            .appendingPathComponent("gone", isDirectory: true)
            .appendingPathComponent("report.csv")

        XCTAssertThrowsError(try DestinationMetadataFile.createTemporary(beside: missing)) { error in
            let nsError = error as NSError
            XCTAssertEqual(nsError.domain, NSPOSIXErrorDomain)
            XCTAssertEqual(nsError.code, Int(ENOENT))
            XCTAssertTrue((nsError.userInfo[NSFilePathErrorKey] as? String)?.contains("report.csv") == true)

            let message = UserFacingErrorMessage.message(for: error)
            XCTAssertTrue(message.contains("no longer available"), message)
            XCTAssertFalse(message.contains("NSPOSIXErrorDomain"), message)
        }
    }

    func testAFolderThatCannotBeWrittenToIsReportedAsBlockedAccess() throws {
        try XCTSkipIf(getuid() == 0, "A read-only folder does not stop root")
        let logs = try makeDirectory()
        XCTAssertEqual(chmod(logs.path, 0o555), 0)

        XCTAssertThrowsError(
            try DestinationMetadataFile.createTemporary(beside: logs.appendingPathComponent("report.csv"))
        ) { error in
            let message = UserFacingErrorMessage.message(for: error)
            XCTAssertTrue(message.contains("blocking access"), message)
            XCTAssertFalse(message.contains("NSPOSIXErrorDomain"), message)
        }
    }

    func testAnUnmappedSystemErrorStillCarriesPlainSystemWordsNotAnErrorNumber() {
        let error = DestinationMetadataFile.posixError(EIO, path: "/dst/.organize_logs/report.csv")

        XCTAssertFalse(error.localizedDescription.contains("NSPOSIXErrorDomain"), error.localizedDescription)
        XCTAssertEqual(error.localizedDescription, String(cString: strerror(EIO)))
        XCTAssertFalse(UserFacingErrorMessage.message(for: error).contains("NSPOSIXErrorDomain"))
    }
}
