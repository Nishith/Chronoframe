import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class DeduplicateReviewSnapshotStoreTests: XCTestCase {
    private var directory: URL!

    override func setUp() {
        super.setUp()
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeduplicateReviewSnapshotStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDown() {
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        directory = nil
        super.tearDown()
    }

    private func makeSnapshot(folderPath: String = "/lib/photos", empty: Bool = false) -> DeduplicateReviewSnapshot {
        let identity = FileIdentity(size: 100, digest: "digest-a")
        return DeduplicateReviewSnapshot(
            folderPath: folderPath,
            savedAt: Date(timeIntervalSince1970: 1_700_000_000),
            configurationFingerprint: "fingerprint",
            decisions: empty ? [] : [
                DeduplicateSavedDecision(path: "/lib/photos/a.jpg", identity: identity, decision: .delete),
            ],
            approvals: empty ? [] : [
                DeduplicateSavedGroupApproval(
                    groupKey: DeduplicateReviewKeys.groupKey(memberIdentities: [identity]),
                    memberCount: 2
                ),
            ],
            focusGroupKey: empty ? nil : "focus"
        )
    }

    private func fileURL(for folderPath: String) -> URL {
        directory
            .appendingPathComponent(DeduplicateReviewKeys.folderKey(for: folderPath))
            .appendingPathExtension("json")
    }

    func testSaveLoadRoundTrip() throws {
        let store = DeduplicateReviewFileSnapshotStore(directory: directory)
        let snapshot = makeSnapshot()

        try store.save(snapshot)

        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(for: snapshot.folderPath).path))
        XCTAssertEqual(store.load(folderPath: snapshot.folderPath), snapshot)
        // The key is the standardized folder, so a trailing slash finds the same file.
        XCTAssertEqual(store.load(folderPath: snapshot.folderPath + "/"), snapshot)
        XCTAssertNil(store.load(folderPath: "/lib/other"))

        store.remove(folderPath: snapshot.folderPath)
        XCTAssertNil(store.load(folderPath: snapshot.folderPath))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(for: snapshot.folderPath).path))
    }

    func testLoadNilOnMissingCorruptWrongVersion() throws {
        let store = DeduplicateReviewFileSnapshotStore(directory: directory)
        let snapshot = makeSnapshot()
        let url = fileURL(for: snapshot.folderPath)

        // Missing directory and file.
        XCTAssertNil(store.load(folderPath: snapshot.folderPath))

        // Corrupt.
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{ not json".utf8).write(to: url)
        XCTAssertNil(store.load(folderPath: snapshot.folderPath))

        // Well-formed JSON of the wrong shape.
        try Data("[1, 2, 3]".utf8).write(to: url)
        XCTAssertNil(store.load(folderPath: snapshot.folderPath))

        // Wrong version.
        try store.save(snapshot)
        let data = try Data(contentsOf: url)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["version"] as? Int, DeduplicateReviewSnapshot.version)
        object["version"] = DeduplicateReviewSnapshot.version + 1
        try JSONSerialization.data(withJSONObject: object).write(to: url)
        XCTAssertNil(store.load(folderPath: snapshot.folderPath))
    }

    func testSavingEmptySnapshotRemovesFile() throws {
        let store = DeduplicateReviewFileSnapshotStore(directory: directory)
        let full = makeSnapshot()
        try store.save(full)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL(for: full.folderPath).path))

        let empty = makeSnapshot(empty: true)
        XCTAssertTrue(empty.isEmpty)
        try store.save(empty)

        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL(for: full.folderPath).path))
        XCTAssertNil(store.load(folderPath: full.folderPath))

        // Saving an empty snapshot when nothing exists is not an error and creates nothing.
        XCTAssertNoThrow(try store.save(empty))
    }

    func testDirectoryIsCreated() throws {
        let nested = directory.appendingPathComponent("nested/dedupe_reviews", isDirectory: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: nested.path))
        let store = DeduplicateReviewFileSnapshotStore(directory: nested)

        try store.save(makeSnapshot())

        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory))
        XCTAssertTrue(isDirectory.boolValue)
        XCTAssertNotNil(store.load(folderPath: "/lib/photos"))
    }
}
