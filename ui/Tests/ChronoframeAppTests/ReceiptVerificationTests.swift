import Foundation
import ChronoframeAppCore
import ChronoframeCore
import XCTest
@testable import ChronoframeApp

/// Finding #8: receipt verification must not leak file descriptors when hashing
/// fails. A directory destination makes `hashIdentity` throw (a directory fd
/// can't be read → EISDIR), exercising the former leak path; with the `defer`
/// close the process descriptor count stays bounded across many failures.
final class ReceiptVerificationTests: XCTestCase {
    func testLargeReceiptAsyncLoadPreservesAllItemsAndStatus() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("large-receipt-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let items = (0..<10_000).map { index in
            RevertReceiptTransfer(source: "source/\(index).jpg", dest: "destination/\(index).jpg", hash: "hash-\(index)")
        }
        let receipt = RevertReceipt(schemaVersion: 3, timestamp: "2026-10-17T06:40:20Z", status: "COMPLETED", totalJobs: 10_000, transfers: items)
        try JSONEncoder().encode(receipt).write(to: file)
        let entry = RunHistoryEntry(kind: .auditReceipt, title: "Large receipt", path: file.path, createdAt: .distantPast)
        let result = try await ReceiptDetailSheet.readReceipt(entry: entry)
        XCTAssertEqual(result.metadata.totalFiles, 10_000)
        XCTAssertEqual(result.metadata.status, "COMPLETED")
        XCTAssertEqual(result.metadata.timestamp, ISO8601DateFormatter().date(from: "2026-10-17T06:40:20Z"))
        XCTAssertEqual(result.transfers.first?.source, items.first?.source)
        XCTAssertEqual(result.transfers.last?.hash, items.last?.hash)
        XCTAssertEqual(Set(result.transfers.map(\.id)).count, 10_000)
    }

    func testEmptyLegacyReceiptLoadsAndMalformedReceiptThrows() throws {
        let entry = RunHistoryEntry(kind: .auditReceipt, title: "Receipt", path: "/unused", createdAt: .distantPast)
        let empty = try ReceiptDetailSheet.decodeReceipt(data: Data("{\"transfers\":[]}".utf8), entry: entry)
        XCTAssertEqual(empty.metadata.totalFiles, 0)
        XCTAssertEqual(empty.metadata.status, "COMPLETED")
        XCTAssertTrue(empty.transfers.isEmpty)
        XCTAssertThrowsError(try ReceiptDetailSheet.decodeReceipt(data: Data("invalid".utf8), entry: entry))
    }

    func testOtherReceiptKindsKeepTheirMetadataAndItemPaths() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let dedupe = DeduplicateAuditReceipt(createdAt: date, destinationRoot: "/archive", items: [
            DeduplicateAuditReceipt.Item(originalPath: "/archive/photo.jpg", sizeBytes: 123,
                trashURL: nil, method: .trash, clusterID: UUID(), clusterKind: .exactDuplicate)
        ], bytesReclaimed: 123)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let dedupeEntry = RunHistoryEntry(kind: .dedupeAuditReceipt, title: "Receipt", path: "/unused", createdAt: date)
        let result = try ReceiptDetailSheet.decodeReceipt(data: encoder.encode(dedupe), entry: dedupeEntry)
        XCTAssertEqual(result.metadata.title, "Deduplication Run Details")
        XCTAssertEqual(result.metadata.bytesReclaimed, 123)
        XCTAssertEqual(result.transfers.first?.dest, "/archive/photo.jpg")

        let reorganizeData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 2, "runID": UUID().uuidString, "operation": "reorganize", "status": "COMPLETED",
            "startedAt": "2026-10-17T06:40:20Z", "destinationRoot": "/archive",
            "items": [["sourcePath": "/archive/old.jpg", "destinationPath": "/archive/new.jpg", "hash": "identity", "completed": true]]
        ])
        let reorganizeEntry = RunHistoryEntry(kind: .reorganizeAuditReceipt, title: "Receipt", path: "/unused", createdAt: date)
        let moved = try ReceiptDetailSheet.decodeReceipt(data: reorganizeData, entry: reorganizeEntry)
        XCTAssertEqual(moved.metadata.status, "COMPLETED")
        XCTAssertEqual(moved.transfers.first?.source, "/archive/old.jpg")
        XCTAssertEqual(moved.transfers.first?.dest, "/archive/new.jpg")
        XCTAssertEqual(moved.transfers.first?.hash, "identity")
    }

    @MainActor
    func testReceiptInspectionReacquiresHistoryDestinationInsteadOfSourceAccess() {
        let harness = AppStateHarness()
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.source", path: "/Volumes/Card", data: Data([1])
        ))
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.destination", path: "/Volumes/Archive", data: Data([2])
        ))
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "deduplicate.destination", path: "/Volumes/Dedupe", data: Data([3])
        ))
        let appState = harness.makeAppState(performInitialBootstrap: false)
        harness.historyStore.setDestinationRoot("/Volumes/Dedupe")
        harness.folderAccessService.scopedAccessRequests.removeAll()

        let scope = appState.historyArtifactSecurityScope()
        defer { scope?.close() }

        XCTAssertNotNil(scope)
        let keys = harness.folderAccessService.scopedAccessRequests.flatMap { $0 }
        XCTAssertTrue(keys.contains(PreferencesStore.historyDestinationBookmarkKey(for: "/Volumes/Dedupe")))
        XCTAssertFalse(keys.contains("manual.source"))
        XCTAssertFalse(keys.contains("manual.destination"))
    }

    @MainActor
    func testHistoryRetainsOriginalDestinationAfterSetupBookmarkReplacementAndRelaunch() {
        let harness = AppStateHarness()
        let original = FolderBookmark(key: "manual.destination", path: "/Volumes/Original", data: Data([1]))
        harness.preferencesStore.storeBookmark(original)
        harness.preferencesStore.storeBookmark(FolderBookmark(
            key: "manual.destination", path: "/Volumes/New", data: Data([2])
        ))
        // Recreate the preference facade to prove this is persistent, not a
        // lease held accidentally by an earlier app session.
        let restored = PreferencesStore(defaults: harness.defaults)
        let key = PreferencesStore.historyDestinationBookmarkKey(for: original.path)
        XCTAssertEqual(restored.bookmark(for: key)?.data, original.data)
        let appState = harness.makeAppState(performInitialBootstrap: false)
        harness.historyStore.setDestinationRoot(original.path)
        harness.folderAccessService.scopedAccessRequests.removeAll()
        let scope = appState.historyArtifactSecurityScope()
        defer { scope?.close() }
        XCTAssertEqual(harness.folderAccessService.scopedAccessRequests, [[key]])
    }

    @MainActor
    func testReconnectRejectsDifferentFolderAndCancellationWithoutSwitchingArchive() async {
        let harness = AppStateHarness()
        let appState = harness.makeAppState(performInitialBootstrap: false)
        harness.historyStore.setDestinationRoot("/Volumes/Original")
        harness.folderAccessService.nextChosenFolder = URL(fileURLWithPath: "/Volumes/Other")
        await appState.reconnectHistoryFolder()
        XCTAssertEqual(harness.historyStore.destinationRoot, "/Volumes/Original")
        XCTAssertTrue(harness.historyStore.reconnectError?.contains("archive was not switched") == true)
        XCTAssertNil(harness.preferencesStore.bookmark(for: PreferencesStore.historyDestinationBookmarkKey(for: "/Volumes/Other")))
        harness.folderAccessService.nextChosenFolder = nil
        await appState.reconnectHistoryFolder()
        XCTAssertEqual(harness.historyStore.destinationRoot, "/Volumes/Original")
        XCTAssertNil(harness.historyStore.reconnectError)
    }

    @MainActor
    func testReconnectSavesPermissionAndReloadsHistoryWithoutRetargetingSetup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let logs = root.appendingPathComponent(".organize_logs")
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: logs.appendingPathComponent("audit_receipt_test.json"))
        let harness = AppStateHarness()
        let appState = harness.makeAppState(performInitialBootstrap: false)
        harness.setupStore.destinationPath = "/Volumes/OtherSetupDestination"
        let alias = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: root)
        defer { try? FileManager.default.removeItem(at: alias) }
        harness.historyStore.setDestinationRoot(alias.path)
        harness.folderAccessService.nextChosenFolder = root
        await appState.reconnectHistoryFolder()
        XCTAssertNil(harness.historyStore.lastRefreshError)
        XCTAssertEqual(harness.historyStore.destinationRoot, alias.path)
        XCTAssertEqual(harness.historyStore.entries.filter { $0.kind == .auditReceipt }.count, 1)
        XCTAssertEqual(harness.setupStore.destinationPath, "/Volumes/OtherSetupDestination")
        XCTAssertNotNil(harness.preferencesStore.bookmark(for: PreferencesStore.historyDestinationBookmarkKey(for: root.path)))
    }

    func testVerifyStatusClosesDescriptorEvenWhenHashingThrows() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("verify-fd-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        // Sanity: this destination drives the throwing catch path.
        XCTAssertEqual(
            ReceiptDetailSheet.verifyStatus(forDestination: directory.path, expectedHash: "deadbeef"),
            .mismatch
        )

        let before = Self.openDescriptorCount()
        for _ in 0..<600 {
            _ = ReceiptDetailSheet.verifyStatus(forDestination: directory.path, expectedHash: "deadbeef")
        }
        let after = Self.openDescriptorCount()

        XCTAssertLessThan(
            after - before,
            50,
            "Descriptors must not grow across repeated hash failures (before=\(before), after=\(after))"
        )
    }

    func testVerifyStatusReportsMissingAndEmptyHashWithoutOpening() throws {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("missing-\(UUID().uuidString).jpg")
        XCTAssertEqual(ReceiptDetailSheet.verifyStatus(forDestination: missing.path, expectedHash: "x"), .missing)

        let real = FileManager.default.temporaryDirectory
            .appendingPathComponent("present-\(UUID().uuidString).jpg")
        try Data("hi".utf8).write(to: real)
        defer { try? FileManager.default.removeItem(at: real) }
        // An empty receipt hash is treated as a match without opening the file.
        XCTAssertEqual(ReceiptDetailSheet.verifyStatus(forDestination: real.path, expectedHash: ""), .matching)
    }

    private static func openDescriptorCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? 0
    }
}
