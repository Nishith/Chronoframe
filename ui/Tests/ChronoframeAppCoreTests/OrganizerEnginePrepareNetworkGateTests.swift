import Darwin
import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// `OrganizerEngine.prepare` refuses a preview or transfer into a network destination that
/// cannot guarantee an atomic no-replace install, after recovery and before any planning.
@MainActor
final class OrganizerEnginePrepareNetworkGateTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var sourceURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("OrganizerEnginePrepareNetworkGateTests-\(UUID().uuidString)", isDirectory: true)
        sourceURL = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        sourceURL = nil
        try super.tearDownWithError()
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

    private func makeDestination(_ name: String) throws -> URL {
        let url = temporaryDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeEngine(
        classifier: NASVolumeClassifier,
        rename: @escaping @Sendable (String, String) -> Int32
    ) -> SwiftOrganizerEngine {
        SwiftOrganizerEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            profilesRepository: GateProfilesRepository(
                profilesFileURL: temporaryDirectoryURL.appendingPathComponent("profiles.yaml")
            ),
            copyDestinationQualifier: NASCopyDestinationQualifier(
                classifier: classifier,
                exclusiveRename: rename
            )
        )
    }

    private func configuration(
        mode: RunMode,
        destination: URL
    ) -> RunConfiguration {
        RunConfiguration(mode: mode, sourcePath: sourceURL.path, destinationPath: destination.path)
    }

    private func assertSecondLockAcquisitionSucceeds(_ destination: URL, file: StaticString = #filePath, line: UInt = #line) {
        do {
            let lease = try DestinationOperationLock.acquire(
                destinationRoot: destination,
                surface: "test",
                operation: "verify-release"
            )
            lease.release()
        } catch {
            XCTFail("The refused prepare must release its lease, got \(error)", file: file, line: line)
        }
    }

    func testPreviewPrepareOnUnqualifiedDestinationThrowsAndReleasesLock() async throws {
        let destination = try makeDestination("preview-remote")
        let engine = makeEngine(classifier: Self.remoteClassifier) { _, _ in ENOTSUP }

        do {
            _ = try await engine.prepare(configuration(mode: .preview, destination: destination))
            XCTFail("Expected prepare to refuse the destination")
        } catch let refusal as NASCopyDestinationRefusal {
            XCTAssertEqual(refusal, .noAtomicNoReplace(path: destination.path, errorCode: ENOTSUP))
            XCTAssertEqual(
                refusal.errorDescription,
                "This network folder can't guarantee that a copy never replaces an existing file, so Chronoframe won't organize into it. Choose a folder on this Mac or an attached drive. Nothing was copied, and your originals were untouched."
            )
        }

        assertSecondLockAcquisitionSucceeds(destination)
        let logs = (try? FileManager.default.contentsOfDirectory(
            atPath: destination.appendingPathComponent(".organize_logs").path
        )) ?? []
        XCTAssertFalse(logs.contains { $0.hasPrefix("dry_run_report_") }, "No dry-run report may be written, got \(logs)")
        XCTAssertFalse(logs.contains { $0.hasPrefix(".chronoframe-rename-check-") }, "No probe file may remain, got \(logs)")
    }

    // AGENTS-INVARIANT: 28
    func testTransferPrepareOnUnqualifiedDestinationThrows() async throws {
        let destination = try makeDestination("transfer-remote")
        let engine = makeEngine(classifier: Self.remoteClassifier) { _, _ in ENOTSUP }

        do {
            _ = try await engine.prepare(configuration(mode: .transfer, destination: destination))
            XCTFail("Expected prepare to refuse the destination")
        } catch let refusal as NASCopyDestinationRefusal {
            XCTAssertEqual(refusal, .noAtomicNoReplace(path: destination.path, errorCode: ENOTSUP))
        }

        assertSecondLockAcquisitionSucceeds(destination)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: destination.appendingPathComponent(".organize_cache.db").path),
            "A refused transfer must not create the queue database"
        )
    }

    func testRecoveryRunsBeforeTheGate() async throws {
        let destination = try makeDestination("recovery-remote")
        let logs = destination.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)

        // A dedupe run was interrupted after quarantining photo.jpg.
        let original = destination.appendingPathComponent("photo.jpg")
        let quarantine = destination.appendingPathComponent(".chronoframe-quarantine-photo.jpg")
        try Data([1, 2, 3]).write(to: quarantine)
        let identity = try FileIdentityHasher().hashIdentity(at: quarantine)
        let receiptURL = logs.appendingPathComponent("dedupe_audit_receipt_test.json")
        let receipt = DeduplicateAuditReceipt(
            createdAt: Date(),
            destinationRoot: destination.path,
            items: [DeduplicateAuditReceipt.Item(
                originalPath: original.path,
                sizeBytes: identity.size,
                trashURL: nil,
                method: .trash,
                clusterID: UUID(),
                clusterKind: .exactDuplicate
            )],
            bytesReclaimed: 0
        )
        try ReceiptDurability.durablyWrite(data: try JSONEncoder.dedupe.encode(receipt), to: receiptURL)
        var journal = try JSONEncoder.dedupeSpool.encode(DeduplicateSpoolRecord(
            state: .quarantined,
            originalPath: original.path,
            quarantinePath: quarantine.path,
            expectedIdentity: identity
        ))
        journal.append(Data("\n".utf8))
        try journal.write(to: DeduplicateExecutor.spoolURL(for: receiptURL))

        let engine = makeEngine(classifier: Self.remoteClassifier) { _, _ in ENOTSUP }
        do {
            _ = try await engine.prepare(configuration(mode: .transfer, destination: destination))
            XCTFail("Expected prepare to refuse the destination")
        } catch is NASCopyDestinationRefusal {
            // expected
        }

        XCTAssertTrue(
            FileManager.default.fileExists(atPath: original.path),
            "Recovery must restore the quarantined file even though prepare then refuses"
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantine.path))
        assertSecondLockAcquisitionSucceeds(destination)
    }

    func testLocalDestinationPreparesNormally() async throws {
        let destination = try makeDestination("local")
        let engine = makeEngine(classifier: Self.localClassifier) { _, _ in
            XCTFail("A local destination must not be probed")
            return 0
        }

        for mode in [RunMode.preview, .transfer] {
            let prepared = try await engine.prepare(configuration(mode: mode, destination: destination))
            XCTAssertEqual(prepared.preflight.resolvedDestinationPath, destination.path)
            prepared.lease.release()
        }
    }
}

private final class GateProfilesRepository: ProfilesRepositorying {
    private let storedProfilesFileURL: URL

    init(profilesFileURL: URL) {
        self.storedProfilesFileURL = profilesFileURL
    }

    func profilesFileURL() -> URL { storedProfilesFileURL }
    func loadProfiles() throws -> [Profile] { [] }
    func save(profile: Profile) throws {}
    func deleteProfile(named name: String) throws {}
}
