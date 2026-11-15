import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Deduplicate refuses folders that are not on a local volume, inside the
/// engine as well as at the picker, so no caller can route around it.
final class DeduplicateEngineNetworkRefusalTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeduplicateEngineNetworkRefusalTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private static let remote = NASVolumeClassifier { _ in
        NASStatfsSnapshot(
            fileSystemType: "smbfs",
            mountedOn: "/Volumes/Share",
            mountedFrom: "//user@nas.local/Share",
            flags: 0,
            fileSystemID: 1
        )
    }

    @MainActor
    private func remoteEngine() -> NativeDeduplicateEngine {
        let engine = NativeDeduplicateEngine(authorizer: UnrestrictedTrialAuthorizer())
        engine.volumeClassifier = Self.remote
        return engine
    }

    @MainActor
    func testScanOnRemoteFolderThrowsBeforeAcquiringLock() throws {
        let root = temporaryDirectoryURL.appendingPathComponent("remote-scan", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let engine = remoteEngine()
        defer { engine.cancelCurrentScan() }

        XCTAssertThrowsError(try engine.scan(DeduplicateConfiguration(destinationPath: root.path))) { error in
            guard let refusal = error as? NASDeduplicateFolderRefusal else {
                return XCTFail("Expected NASDeduplicateFolderRefusal, got \(error)")
            }
            XCTAssertEqual(refusal, .notLocal(path: root.path, kind: .remote))
        }

        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: root.appendingPathComponent(".organize_logs/.chronoframe-operation.lock").path
            ),
            "A refused scan must not take the destination lock"
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: root.appendingPathComponent(".organize_cache.db").path),
            "A refused scan must not create the cache database"
        )
    }

    // AGENTS-INVARIANT: 12
    @MainActor
    func testCommitOnRemoteFolderThrowsAndTrashesNothing() throws {
        let root = temporaryDirectoryURL.appendingPathComponent("remote-commit", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var files: [URL] = []
        var items: [DeduplicationPlan.Item] = []
        for index in 0..<2 {
            let fileURL = root.appendingPathComponent("duplicate-\(index).jpg")
            try Data(repeating: UInt8(0xA0 + index), count: 16 + index).write(to: fileURL)
            files.append(fileURL)
            items.append(
                DeduplicationPlan.Item(
                    path: fileURL.path,
                    sizeBytes: Int64(16 + index),
                    owningClusterID: UUID(),
                    owningClusterKind: .exactDuplicate,
                    pairOrigin: nil,
                    expectedIdentity: testFileIdentity(at: fileURL)
                )
            )
        }
        let engine = remoteEngine()
        defer { engine.cancelCurrentScan() }

        XCTAssertThrowsError(
            try engine.commit(
                plan: DeduplicationPlan(items: items),
                configuration: DeduplicateConfiguration(destinationPath: root.path)
            )
        ) { error in
            XCTAssertTrue(error is NASDeduplicateFolderRefusal, "Expected NASDeduplicateFolderRefusal, got \(error)")
        }

        for fileURL in files {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fileURL.path),
                "A refused commit must move nothing to the Trash: \(fileURL.lastPathComponent) is gone"
            )
        }
        let logs = (try? FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".organize_logs", isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []
        XCTAssertTrue(logs.isEmpty, "A refused commit must write no receipt, spool or lock, got \(logs)")
    }
}
