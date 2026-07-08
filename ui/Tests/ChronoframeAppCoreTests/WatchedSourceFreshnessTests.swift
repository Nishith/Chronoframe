import Foundation
import XCTest
@testable import ChronoframeCore

final class WatchedSourceFreshnessTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchedSourceFreshnessTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private func stamp(size: Int64 = 1, mtime: Int64 = 1, ctime: Int64 = 1) -> WatchedFileStamp {
        WatchedFileStamp(sizeBytes: size, mtimeNanoseconds: mtime, ctimeNanoseconds: ctime)
    }

    // MARK: - Pending diff matrix

    func testPendingReportsAddedPaths() {
        let pending = WatchedSourceFreshness.pendingRelativePaths(
            current: ["new.jpg": stamp(), "old.jpg": stamp()],
            acknowledged: ["old.jpg": stamp()]
        )
        XCTAssertEqual(pending, ["new.jpg"])
    }

    func testPendingReportsSizeChange() {
        let pending = WatchedSourceFreshness.pendingRelativePaths(
            current: ["a.jpg": stamp(size: 2)],
            acknowledged: ["a.jpg": stamp(size: 1)]
        )
        XCTAssertEqual(pending, ["a.jpg"])
    }

    func testPendingReportsNanosecondMtimeChange() {
        let pending = WatchedSourceFreshness.pendingRelativePaths(
            current: ["a.jpg": stamp(mtime: 1_000_000_001)],
            acknowledged: ["a.jpg": stamp(mtime: 1_000_000_000)]
        )
        XCTAssertEqual(pending, ["a.jpg"])
    }

    /// A replacement engineered to keep the same size and mtime still
    /// trips the ctime component — ctime cannot be forged with utimes.
    func testPendingReportsCtimeOnlyChange() {
        let pending = WatchedSourceFreshness.pendingRelativePaths(
            current: ["a.jpg": stamp(ctime: 2)],
            acknowledged: ["a.jpg": stamp(ctime: 1)]
        )
        XCTAssertEqual(pending, ["a.jpg"])
    }

    func testPendingNeverCountsRemovals() {
        let pending = WatchedSourceFreshness.pendingRelativePaths(
            current: [:],
            acknowledged: ["gone.jpg": stamp()]
        )
        XCTAssertTrue(pending.isEmpty, "A file the user deleted from the source is not pending work")
    }

    func testPendingIsEmptyForIdenticalSets() {
        let entries = ["a.jpg": stamp(), "b/c.mov": stamp(size: 9, mtime: 9, ctime: 9)]
        XCTAssertTrue(
            WatchedSourceFreshness.pendingRelativePaths(current: entries, acknowledged: entries).isEmpty
        )
    }

    func testPendingWithEmptyAcknowledgedCountsEverything() {
        let pending = WatchedSourceFreshness.pendingRelativePaths(
            current: ["a.jpg": stamp(), "b.jpg": stamp()],
            acknowledged: [:]
        )
        XCTAssertEqual(pending, ["a.jpg", "b.jpg"])
    }

    // MARK: - Checkpoint merge semantics

    /// The heart of "never acknowledge unreviewed work": only stamps
    /// captured when the import was requested may advance the
    /// checkpoint. A file that arrived (or changed) during the transfer
    /// keeps its live stamp and therefore stays pending afterwards.
    func testMergeAcknowledgesOnlyCapturedStampsSoMidRunArrivalsStayPending() {
        let acknowledged: [String: WatchedFileStamp] = ["seen.jpg": stamp()]
        let captured: [String: WatchedFileStamp] = [
            "seen.jpg": stamp(),
            "reviewed.jpg": stamp(mtime: 10)
        ]

        let advanced = WatchedSourceFreshness.merged(acknowledged: acknowledged, acknowledging: captured)

        // Live tree after the run: the reviewed file, plus one that
        // landed mid-transfer, plus one that was rewritten mid-transfer.
        let liveAfterRun: [String: WatchedFileStamp] = [
            "seen.jpg": stamp(),
            "reviewed.jpg": stamp(mtime: 10),
            "arrived-mid-run.jpg": stamp(mtime: 20),
            "rewritten-mid-run.jpg": stamp(mtime: 30)
        ]

        let pending = WatchedSourceFreshness.pendingRelativePaths(
            current: liveAfterRun,
            acknowledged: advanced
        )
        XCTAssertEqual(pending, ["arrived-mid-run.jpg", "rewritten-mid-run.jpg"])
    }

    func testMergeOverwritesStaleAcknowledgedStampWithCapturedOne() {
        let advanced = WatchedSourceFreshness.merged(
            acknowledged: ["a.jpg": stamp(mtime: 1)],
            acknowledging: ["a.jpg": stamp(mtime: 5)]
        )
        XCTAssertEqual(advanced["a.jpg"], stamp(mtime: 5))
    }

    /// Failure and cancellation call no merge at all — modeled here as
    /// the identity: pending is computed against the untouched
    /// checkpoint and still reports everything.
    func testUnmergedCheckpointKeepsEverythingPendingAfterFailedRun() {
        let acknowledged: [String: WatchedFileStamp] = [:]
        let live: [String: WatchedFileStamp] = ["a.jpg": stamp(), "b.jpg": stamp()]
        XCTAssertEqual(
            WatchedSourceFreshness.pendingRelativePaths(current: live, acknowledged: acknowledged),
            ["a.jpg", "b.jpg"]
        )
    }

    func testPrunedDropsAcknowledgedEntriesForRemovedPaths() {
        let pruned = WatchedSourceFreshness.pruned(
            acknowledged: ["kept.jpg": stamp(), "removed.jpg": stamp()],
            retainingKeysIn: ["kept.jpg": stamp(mtime: 99)]
        )
        XCTAssertEqual(Array(pruned.keys), ["kept.jpg"])
        XCTAssertEqual(pruned["kept.jpg"], stamp(), "Prune keeps the acknowledged stamp, not the live one")
    }

    // MARK: - Settling window

    func testSettledEntriesHoldsOutRecentlyModifiedFiles() {
        let now = Date(timeIntervalSince1970: 1_000)
        let oldStamp = stamp(mtime: Int64(990) * 1_000_000_000)     // 10s old
        let freshStamp = stamp(mtime: Int64(999) * 1_000_000_000)   // 1s old

        let settled = WatchedSourceFreshness.settledEntries(
            ["old.jpg": oldStamp, "settling.jpg": freshStamp],
            now: now,
            settlingWindow: 5.0
        )
        XCTAssertEqual(Array(settled.keys), ["old.jpg"])
    }

    func testPendingEstimateAppliesSettlingWindowAndDiff() {
        let now = Date(timeIntervalSince1970: 1_000)
        let oldStamp = stamp(mtime: Int64(990) * 1_000_000_000)
        let freshStamp = stamp(mtime: Int64(999) * 1_000_000_000)

        let estimate = WatchedSourceFreshness.pendingEstimate(
            current: [
                "acknowledged.jpg": oldStamp,
                "new-settled.jpg": oldStamp,
                "new-settling.jpg": freshStamp
            ],
            acknowledged: ["acknowledged.jpg": oldStamp],
            now: now,
            settlingWindow: 5.0
        )
        XCTAssertEqual(estimate, 1, "Only the settled unacknowledged file counts")
    }

    // MARK: - Scan behavior

    func testScanKeysMatchMediaDiscoveryRelativePaths() throws {
        try writeFile("alpha/IMG_0001.jpg")
        try writeFile("alpha/notes.txt")            // unsupported extension
        try writeFile("beta/VID_0002.mov")
        try writeFile(".hidden/IMG_0003.jpg")       // hidden directory
        try writeFile("beta/.ignored.jpg")          // hidden file
        try writeFile("beta/profiles.yaml")         // skip-listed name

        // Symlinked media must not be followed.
        let symlinkURL = temporaryDirectoryURL.appendingPathComponent("link.jpg")
        try FileManager.default.createSymbolicLink(
            at: symlinkURL,
            withDestinationURL: temporaryDirectoryURL.appendingPathComponent("alpha/IMG_0001.jpg")
        )

        // Photo-library packages must not be descended into.
        let packageURL = temporaryDirectoryURL.appendingPathComponent("Library.photoslibrary", isDirectory: true)
        try FileManager.default.createDirectory(at: packageURL, withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: packageURL.appendingPathComponent("inside.jpg"))

        let result = try WatchedSourceFreshness.scan(rootURL: temporaryDirectoryURL)

        let discovered = try MediaDiscovery.discoverMediaFiles(at: temporaryDirectoryURL)
        let rootPrefix = temporaryDirectoryURL.standardizedFileURL.path + "/"
        let expectedRelative = Set(discovered.map {
            String(URL(fileURLWithPath: $0).standardizedFileURL.path.dropFirst(rootPrefix.count))
        })

        XCTAssertEqual(Set(result.entries.keys), expectedRelative,
                       "Freshness scan must count exactly what organize discovery would find")
        XCTAssertEqual(Set(result.entries.keys), ["alpha/IMG_0001.jpg", "beta/VID_0002.mov"])
        XCTAssertTrue(result.completeness.isComplete)
        XCTAssertTrue(result.issues.isEmpty)
    }

    func testScanCapturesSizeAndNonZeroTimestampStamps() throws {
        try writeFile("shot.jpg", contents: "12345678")

        let result = try WatchedSourceFreshness.scan(rootURL: temporaryDirectoryURL)
        let stamp = try XCTUnwrap(result.entries["shot.jpg"])
        XCTAssertEqual(stamp.sizeBytes, 8)
        XCTAssertGreaterThan(stamp.mtimeNanoseconds, 0)
        XCTAssertGreaterThan(stamp.ctimeNanoseconds, 0)
    }

    /// An unreadable subtree must poison completeness: acting on such a
    /// scan could report "caught up" while files sit unseen behind the
    /// permission error.
    func testScanMarksPartialWhenSubtreeIsUnreadable() throws {
        try writeFile("visible/IMG_0001.jpg")
        let lockedDir = temporaryDirectoryURL.appendingPathComponent("locked", isDirectory: true)
        try FileManager.default.createDirectory(at: lockedDir, withIntermediateDirectories: true)
        try Data("jpg".utf8).write(to: lockedDir.appendingPathComponent("IMG_0002.jpg"))
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: lockedDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
        }

        let result = try WatchedSourceFreshness.scan(rootURL: temporaryDirectoryURL)

        guard case .partial(let unreadable) = result.completeness else {
            return XCTFail("Expected partial completeness for unreadable subtree")
        }
        XCTAssertEqual(unreadable, 1)
        XCTAssertEqual(result.issues.count, 1)
        XCTAssertTrue(result.issues[0].path.hasSuffix("/locked"))
        XCTAssertEqual(Array(result.entries.keys), ["visible/IMG_0001.jpg"],
                       "Readable parts of the tree still stamp normally")
    }

    /// Relative keying makes the checkpoint survive a rename of the
    /// watched root itself (same volume): the subtree is unchanged, so
    /// nothing becomes pending.
    func testRelativeKeyingSurvivesRootRename() throws {
        try writeFile("nested/IMG_0001.jpg")
        let before = try WatchedSourceFreshness.scan(rootURL: temporaryDirectoryURL)

        let renamedRoot = temporaryDirectoryURL.deletingLastPathComponent()
            .appendingPathComponent("WatchedSourceFreshnessTests-renamed-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.moveItem(at: temporaryDirectoryURL, to: renamedRoot)
        defer { try? FileManager.default.removeItem(at: renamedRoot) }
        temporaryDirectoryURL = renamedRoot

        let after = try WatchedSourceFreshness.scan(rootURL: renamedRoot)

        XCTAssertEqual(
            WatchedSourceFreshness.pendingRelativePaths(
                current: after.entries,
                acknowledged: before.entries
            ),
            [],
            "Rename of the root must not mark the whole tree as new"
        )
    }

    func testWatchedFileStampCodableRoundTrip() throws {
        let original = stamp(size: 42, mtime: 1_234_567_890_123, ctime: 9_876_543_210_987)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WatchedFileStamp.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScanRespectsCancellation() throws {
        try writeFile("a/IMG_0001.jpg")
        XCTAssertThrowsError(
            try WatchedSourceFreshness.scan(rootURL: temporaryDirectoryURL, isCancelled: { true })
        ) { error in
            XCTAssertTrue(error is CancellationError)
        }
    }

    // MARK: - Helpers

    private func writeFile(_ relativePath: String, contents: String = "data") throws {
        let url = temporaryDirectoryURL.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }
}
