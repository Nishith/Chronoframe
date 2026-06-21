import Foundation
import XCTest
@testable import ChronoframeCore

final class MutationRecoveryCoordinatorTests: XCTestCase {
    private final class PresenceStub: FilesystemPresenceChecking, @unchecked Sendable {
        var overrides: [String: FilesystemPresence] = [:]
        private let fallback = POSIXFilesystemPresenceChecker()
        func presence(at path: String) -> FilesystemPresence {
            overrides[path] ?? fallback.presence(at: path)
        }
    }

    private func makeDestination() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("MutationRecovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: url.appendingPathComponent(".organize_logs", isDirectory: true),
            withIntermediateDirectories: true
        )
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writePendingReceipt(
        destination: URL,
        originalPath: String,
        size: Int64
    ) throws -> URL {
        let url = destination.appendingPathComponent(".organize_logs/dedupe_audit_receipt_test.json")
        let receipt = DeduplicateAuditReceipt(
            createdAt: Date(),
            destinationRoot: destination.path,
            items: [DeduplicateAuditReceipt.Item(
                originalPath: originalPath,
                sizeBytes: size,
                trashURL: nil,
                method: .trash,
                clusterID: UUID(),
                clusterKind: .exactDuplicate
            )],
            bytesReclaimed: 0
        )
        try ReceiptDurability.durablyWrite(data: try JSONEncoder.dedupe.encode(receipt), to: url)
        return url
    }

    private func writeJournal(_ record: DeduplicateSpoolRecord, receiptURL: URL) throws {
        let spoolURL = DeduplicateExecutor.spoolURL(for: receiptURL)
        var data = try JSONEncoder.dedupeSpool.encode(record)
        data.append(Data("\n".utf8))
        try data.write(to: spoolURL)
    }

    private func writePendingReorganizeReceipt(
        destination: URL,
        items: [ReorganizeAuditReceipt.Item],
        recordedDestinationRoot: String? = nil
    ) throws -> URL {
        let url = destination.appendingPathComponent(
            ".organize_logs/reorganize_audit_receipt_test.json"
        )
        let receipt = ReorganizeAuditReceipt(
            schemaVersion: 2,
            runID: UUID(),
            operation: "reorganize",
            status: "PENDING",
            startedAt: Date(),
            finishedAt: nil,
            destinationRoot: recordedDestinationRoot ?? destination.path,
            items: items,
            abortReason: nil
        )
        try ReceiptDurability.durablyWrite(data: try JSONEncoder().encode(receipt), to: url)
        return url
    }

    func testLegacyJournalRecordDecodesAsCompleted() throws {
        let data = Data(#"{"originalPath":"/a.jpg","trashURL":"file:///Trash/a.jpg"}"#.utf8)
        let record = try JSONDecoder.dedupe.decode(DeduplicateSpoolRecord.self, from: data)
        XCTAssertEqual(record.schemaVersion, 1)
        XCTAssertEqual(record.state, .trashed)
        XCTAssertEqual(record.actualTrashURL, "file:///Trash/a.jpg")
    }

    func testQuarantineIsRestoredAndRepeatedRecoveryIsIdempotent() throws {
        let destination = try makeDestination()
        let original = destination.appendingPathComponent("photo.jpg")
        let quarantine = destination.appendingPathComponent(".chronoframe-quarantine-photo.jpg")
        try Data([1, 2, 3]).write(to: quarantine)
        let identity = try FileIdentityHasher().hashIdentity(at: quarantine)
        let receiptURL = try writePendingReceipt(
            destination: destination,
            originalPath: original.path,
            size: identity.size
        )
        try writeJournal(DeduplicateSpoolRecord(
            state: .quarantined,
            originalPath: original.path,
            quarantinePath: quarantine.path,
            expectedIdentity: identity
        ), receiptURL: receiptURL)

        let coordinator = MutationRecoveryCoordinator()
        let first = coordinator.recover(destinationRoot: destination)
        let second = coordinator.recover(destinationRoot: destination)

        XCTAssertEqual(first.recoveredItemCount, 1)
        XCTAssertEqual(second.recoveredItemCount, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: quarantine.path))
        let receipt = try JSONDecoder.dedupe.decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.status, "ABORTED")
        XCTAssertTrue(receipt.items.isEmpty)
    }

    func testSandboxDeniedTrashBecomesUnverifiedAndRetainsJournal() throws {
        let destination = try makeDestination()
        let original = destination.appendingPathComponent("gone.jpg")
        let quarantine = destination.appendingPathComponent(".chronoframe-quarantine-gone.jpg")
        let predicted = URL(fileURLWithPath: "/Users/test/.Trash/gone.jpg")
        let receiptURL = try writePendingReceipt(destination: destination, originalPath: original.path, size: 3)
        try writeJournal(DeduplicateSpoolRecord(
            state: .quarantined,
            originalPath: original.path,
            quarantinePath: quarantine.path,
            expectedIdentity: FileIdentity(size: 3, digest: "abc"),
            predictedTrashURL: predicted.absoluteString
        ), receiptURL: receiptURL)
        let presence = PresenceStub()
        presence.overrides[predicted.path] = .inaccessible

        let report = MutationRecoveryCoordinator(presenceChecker: presence)
            .recover(destinationRoot: destination)

        XCTAssertEqual(report.recoveryState, .trashLocationUnverified)
        XCTAssertTrue(FileManager.default.fileExists(atPath: DeduplicateExecutor.spoolURL(for: receiptURL).path))
        let receipt = try JSONDecoder.dedupe.decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.status, "ABORTED")
        XCTAssertEqual(receipt.recoveryState, .trashLocationUnverified)
    }

    func testInaccessibleExternalDestinationReportsNeedsVolume() {
        let destination = URL(fileURLWithPath: "/Volumes/Chronoframe Offline", isDirectory: true)
        let presence = PresenceStub()
        presence.overrides[destination.appendingPathComponent(".organize_logs").path] = .inaccessible

        let report = MutationRecoveryCoordinator(presenceChecker: presence)
            .recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(
            report.recoveryState,
            .needsVolume(volumeName: "Chronoframe Offline", volumeIdentifier: nil)
        )
    }

    func testPendingDedupeWithoutSpoolClassifiesUntouchedAndMissingPaths() throws {
        let destination = try makeDestination()
        let untouched = destination.appendingPathComponent("untouched.jpg")
        try Data("original".utf8).write(to: untouched)
        let receiptURL = try writePendingReceipt(
            destination: destination,
            originalPath: untouched.path,
            size: 8
        )

        let first = MutationRecoveryCoordinator().recover(destinationRoot: destination)
        XCTAssertEqual(first.recoveredItemCount, 1)
        XCTAssertNil(first.recoveryState)
        var receipt = try JSONDecoder.dedupe.decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.status, "ABORTED")
        XCTAssertTrue(receipt.items.isEmpty)

        receipt.status = "PENDING"
        receipt.finishedAt = nil
        receipt.items = [DeduplicateAuditReceipt.Item(
            originalPath: destination.appendingPathComponent("missing.jpg").path,
            sizeBytes: 4,
            trashURL: nil,
            method: .trash,
            clusterID: UUID(),
            clusterKind: .exactDuplicate
        )]
        try ReceiptDurability.durablyWrite(data: try JSONEncoder.dedupe.encode(receipt), to: receiptURL)

        let second = MutationRecoveryCoordinator().recover(destinationRoot: destination)
        XCTAssertEqual(second.pendingItemCount, 1)
        XCTAssertEqual(second.recoveryState, .manualActionRequired)
    }

    func testTransferRecoveryFinalizesMatchingCopyAndPreservesMismatch() throws {
        let destination = try makeDestination()
        let matching = destination.appendingPathComponent("matching.jpg")
        let mismatch = destination.appendingPathComponent("mismatch.jpg")
        let expectedMismatch = destination.appendingPathComponent("expected-mismatch.jpg")
        try Data("matching".utf8).write(to: matching)
        try Data("unexpected".utf8).write(to: mismatch)
        try Data("expected".utf8).write(to: expectedMismatch)
        let matchingIdentity = try FileIdentityHasher().hashIdentity(at: matching)
        let mismatchIdentity = try FileIdentityHasher().hashIdentity(at: expectedMismatch)

        let database = try OrganizerDatabase(
            url: destination.appendingPathComponent(".organize_cache.db")
        )
        try database.enqueueQueuedJobs([
            QueuedCopyJob(
                sourcePath: "/source/matching.jpg",
                destinationPath: matching.path,
                hash: matchingIdentity.rawValue,
                status: .pending,
                runID: UUID(),
                intendedDestinationPath: matching.path,
                actualDestinationPath: matching.path,
                mutationState: .finalized
            ),
            QueuedCopyJob(
                sourcePath: "/source/mismatch.jpg",
                destinationPath: mismatch.path,
                hash: mismatchIdentity.rawValue,
                status: .pending,
                runID: UUID(),
                intendedDestinationPath: mismatch.path,
                actualDestinationPath: mismatch.path,
                mutationState: .finalized
            ),
        ])
        database.close()

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.recoveredItemCount, 1)
        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(report.recoveryState, .manualActionRequired)
        let verificationDatabase = try OrganizerDatabase(
            url: destination.appendingPathComponent(".organize_cache.db")
        )
        defer { verificationDatabase.close() }
        let jobs = try verificationDatabase.loadQueuedJobs(orderByInsertion: true)
        XCTAssertEqual(jobs[0].status, .copied)
        XCTAssertEqual(jobs[1].status, .pending)
    }

    func testTransferRecoveryKeepsMissingAndInaccessibleDestinationsPending() throws {
        let destination = try makeDestination()
        let missing = destination.appendingPathComponent("missing-copy.jpg")
        let inaccessible = "/Volumes/Offline Drive/inaccessible-copy.jpg"
        let database = try OrganizerDatabase(
            url: destination.appendingPathComponent(".organize_cache.db")
        )
        try database.enqueueQueuedJobs([
            QueuedCopyJob(
                sourcePath: "/source/missing.jpg",
                destinationPath: missing.path,
                hash: FileIdentity(size: 1, digest: "one").rawValue,
                status: .pending,
                intendedDestinationPath: missing.path,
                mutationState: .intended
            ),
            QueuedCopyJob(
                sourcePath: "/source/inaccessible.jpg",
                destinationPath: inaccessible,
                hash: FileIdentity(size: 1, digest: "two").rawValue,
                status: .pending,
                intendedDestinationPath: inaccessible,
                mutationState: .intended
            ),
        ])
        database.close()
        let presence = PresenceStub()
        presence.overrides[inaccessible] = .inaccessible

        let report = MutationRecoveryCoordinator(presenceChecker: presence)
            .recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 2)
        XCTAssertEqual(
            report.recoveryState,
            .needsVolume(volumeName: "Offline Drive", volumeIdentifier: nil)
        )
    }

    func testReorganizeRecoveryReconcilesUntouchedAndMovedItems() throws {
        let destination = try makeDestination()
        let source = destination.appendingPathComponent("source.jpg")
        let absentDestination = destination.appendingPathComponent("future/source.jpg")
        let movedDestination = destination.appendingPathComponent("moved.jpg")
        try Data("source".utf8).write(to: source)
        try Data("moved".utf8).write(to: movedDestination)
        let movedIdentity = try FileIdentityHasher().hashIdentity(at: movedDestination)
        let receiptURL = try writePendingReorganizeReceipt(destination: destination, items: [
            ReorganizeAuditReceipt.Item(
                sourcePath: source.path,
                destinationPath: absentDestination.path,
                hash: try FileIdentityHasher().hashIdentity(at: source).rawValue,
                completed: false,
                mutationState: .intended
            ),
            ReorganizeAuditReceipt.Item(
                sourcePath: destination.appendingPathComponent("old-moved.jpg").path,
                destinationPath: movedDestination.path,
                hash: movedIdentity.rawValue,
                completed: false,
                mutationState: .intended
            ),
        ])

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.recoveredItemCount, 2)
        XCTAssertNil(report.recoveryState)
        let receipt = try JSONDecoder().decode(
            ReorganizeAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.status, "ABORTED")
        XCTAssertEqual(receipt.items[0].mutationState, .intended)
        XCTAssertEqual(receipt.items[1].mutationState, .moved)
        XCTAssertTrue(receipt.items[1].completed)
    }

    func testReorganizeRecoveryPreservesMismatchForManualAction() throws {
        let destination = try makeDestination()
        let movedDestination = destination.appendingPathComponent("wrong.jpg")
        try Data("wrong".utf8).write(to: movedDestination)
        let receiptURL = try writePendingReorganizeReceipt(destination: destination, items: [
            ReorganizeAuditReceipt.Item(
                sourcePath: destination.appendingPathComponent("gone.jpg").path,
                destinationPath: movedDestination.path,
                hash: FileIdentity(size: 5, digest: "expected").rawValue,
                completed: false,
                mutationState: .intended
            ),
        ])

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(report.recoveryState, .manualActionRequired)
        let receipt = try JSONDecoder().decode(
            ReorganizeAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.items[0].mutationState, .failed)
    }

    func testTransferRecoveryRejectsMalformedExpectedIdentity() throws {
        let destination = try makeDestination()
        let finalURL = destination.appendingPathComponent("malformed-hash.jpg")
        try Data("copy".utf8).write(to: finalURL)
        let database = try OrganizerDatabase(
            url: destination.appendingPathComponent(".organize_cache.db")
        )
        try database.enqueueQueuedJobs([
            QueuedCopyJob(
                sourcePath: "/source/malformed-hash.jpg",
                destinationPath: finalURL.path,
                hash: "not-a-file-identity",
                status: .pending,
                runID: UUID(),
                intendedDestinationPath: nil,
                actualDestinationPath: nil,
                mutationState: .finalized
            ),
        ])
        database.close()

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(report.recoveryState, .manualActionRequired)
    }

    func testReorganizeInaccessibleDriveRemainsPending() throws {
        let destination = try makeDestination()
        let source = "/Volumes/Offline Drive/source.jpg"
        let final = "/Volumes/Offline Drive/final.jpg"
        let receiptURL = try writePendingReorganizeReceipt(
            destination: destination,
            items: [ReorganizeAuditReceipt.Item(
                sourcePath: source,
                destinationPath: final,
                hash: FileIdentity(size: 1, digest: "expected").rawValue,
                completed: false,
                mutationState: .intended
            )],
            recordedDestinationRoot: "/Volumes/Offline Drive"
        )
        let presence = PresenceStub()
        presence.overrides[source] = .inaccessible
        presence.overrides[final] = .inaccessible

        let report = MutationRecoveryCoordinator(presenceChecker: presence)
            .recover(destinationRoot: destination)

        XCTAssertEqual(
            report.recoveryState,
            .needsVolume(volumeName: "Offline Drive", volumeIdentifier: nil)
        )
        let receipt = try JSONDecoder().decode(
            ReorganizeAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.status, "PENDING")
        XCTAssertNil(receipt.finishedAt)
    }

    func testReorganizeAmbiguousDoublePresenceRequiresManualAction() throws {
        let destination = try makeDestination()
        let source = destination.appendingPathComponent("both-source.jpg")
        let final = destination.appendingPathComponent("both-final.jpg")
        try Data("source".utf8).write(to: source)
        try Data("final".utf8).write(to: final)
        _ = try writePendingReorganizeReceipt(destination: destination, items: [
            ReorganizeAuditReceipt.Item(
                sourcePath: source.path,
                destinationPath: final.path,
                hash: try FileIdentityHasher().hashIdentity(at: source).rawValue,
                completed: false,
                mutationState: .intended
            ),
        ])

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(report.recoveryState, .manualActionRequired)
    }

    func testDedupeIntendedRecordWithOriginalPresentIsUntouched() throws {
        let destination = try makeDestination()
        let original = destination.appendingPathComponent("never-mutated.jpg")
        try Data("safe".utf8).write(to: original)
        let receiptURL = try writePendingReceipt(
            destination: destination,
            originalPath: original.path,
            size: 4
        )
        try writeJournal(DeduplicateSpoolRecord(
            state: .intent,
            originalPath: original.path,
            quarantinePath: nil,
            expectedIdentity: try FileIdentityHasher().hashIdentity(at: original)
        ), receiptURL: receiptURL)

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.recoveredItemCount, 1)
        XCTAssertNil(report.recoveryState)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: DeduplicateExecutor.spoolURL(for: receiptURL).path
        ))
    }

    func testDedupeQuarantineAndOriginalBothPresentRequireManualAction() throws {
        let destination = try makeDestination()
        let original = destination.appendingPathComponent("recreated.jpg")
        let quarantine = destination.appendingPathComponent(".chronoframe-quarantine-recreated.jpg")
        try Data("original".utf8).write(to: original)
        try Data("quarantine".utf8).write(to: quarantine)
        let receiptURL = try writePendingReceipt(
            destination: destination,
            originalPath: original.path,
            size: 10
        )
        try writeJournal(DeduplicateSpoolRecord(
            state: .quarantined,
            originalPath: original.path,
            quarantinePath: quarantine.path,
            expectedIdentity: try FileIdentityHasher().hashIdentity(at: quarantine)
        ), receiptURL: receiptURL)

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(report.recoveryState, .manualActionRequired)
        XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: quarantine.path))
    }

    func testDedupeTrashIdentityMismatchRequiresManualAction() throws {
        let destination = try makeDestination()
        let original = destination.appendingPathComponent("gone-mismatch.jpg")
        let trash = destination.appendingPathComponent("unexpected-trash.jpg")
        let expectedFile = destination.appendingPathComponent("expected-trash.jpg")
        try Data("unexpected".utf8).write(to: trash)
        try Data("expected".utf8).write(to: expectedFile)
        let receiptURL = try writePendingReceipt(
            destination: destination,
            originalPath: original.path,
            size: 8
        )
        try writeJournal(DeduplicateSpoolRecord(
            state: .trashed,
            originalPath: original.path,
            expectedIdentity: try FileIdentityHasher().hashIdentity(at: expectedFile),
            actualTrashURL: trash.absoluteString
        ), receiptURL: receiptURL)

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(report.recoveryState, .manualActionRequired)
        XCTAssertTrue(FileManager.default.fileExists(atPath: trash.path))
    }

    func testLegacyTrashedJournalFinalizesAccessibleTrash() throws {
        let destination = try makeDestination()
        let original = destination.appendingPathComponent("legacy.jpg")
        let trash = destination.appendingPathComponent("legacy-trash.jpg")
        try Data("legacy".utf8).write(to: trash)
        let receiptURL = try writePendingReceipt(
            destination: destination,
            originalPath: original.path,
            size: 6
        )
        let legacy = Data(
            "{\"originalPath\":\"\(original.path)\",\"trashURL\":\"\(trash.absoluteString)\"}\n".utf8
        )
        try legacy.write(to: DeduplicateExecutor.spoolURL(for: receiptURL))

        let report = MutationRecoveryCoordinator().recover(destinationRoot: destination)

        XCTAssertEqual(report.recoveredItemCount, 1)
        XCTAssertNil(report.recoveryState)
        let receipt = try JSONDecoder.dedupe.decode(
            DeduplicateAuditReceipt.self,
            from: Data(contentsOf: receiptURL)
        )
        XCTAssertEqual(receipt.items.first?.trashURL, trash.absoluteString)
    }

    func testDedupeInaccessibleOriginalWithoutSpoolNeedsDrive() throws {
        let destination = try makeDestination()
        let original = "/Volumes/Archive Drive/offline.jpg"
        _ = try writePendingReceipt(
            destination: destination,
            originalPath: original,
            size: 10
        )
        let presence = PresenceStub()
        presence.overrides[original] = .inaccessible

        let report = MutationRecoveryCoordinator(presenceChecker: presence)
            .recover(destinationRoot: destination)

        XCTAssertEqual(report.pendingItemCount, 1)
        XCTAssertEqual(
            report.recoveryState,
            .needsVolume(volumeName: "Archive Drive", volumeIdentifier: nil)
        )
    }
}
