import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

final class DeduplicateExecutorQuarantineTests: XCTestCase {
    private final class TestTrashOps: DeduplicateFileOperations, @unchecked Sendable {
        let root: URL
        var failingOriginalName: String?
        var failingQuarantineOriginalName: String?
        var nilTrashOriginalName: String?
        var failingMoveSourceName: String?
        var failMovesIntoTrash = false
        var recreateOriginalPathBeforeQuarantineFailure: URL?
        var swapOnQuarantine: Data?

        init(root: URL) { self.root = root }

        func removeItem(at url: URL) throws { try FileManager.default.removeItem(at: url) }
        func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
        }
        func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
            if let failingMoveSourceName, sourceURL.lastPathComponent.hasSuffix(failingMoveSourceName) {
                throw CocoaError(.fileWriteNoPermission)
            }
            if failMovesIntoTrash,
               destinationURL.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path
            {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        }
        func quarantineItem(at sourceURL: URL, to quarantineURL: URL) throws {
            if let failingQuarantineOriginalName,
               sourceURL.lastPathComponent == failingQuarantineOriginalName
            {
                if let recreateOriginalPathBeforeQuarantineFailure {
                    try Data("recreated".utf8).write(to: recreateOriginalPathBeforeQuarantineFailure)
                }
                throw CocoaError(.fileWriteNoPermission)
            }
            if let swapOnQuarantine {
                try swapOnQuarantine.write(to: sourceURL)
                self.swapOnQuarantine = nil
            }
            let result = sourceURL.path.withCString { source in
                quarantineURL.path.withCString { destination in Darwin.rename(source, destination) }
            }
            guard result == 0 else { throw CocoaError(.fileWriteUnknown) }
        }
        func trashItem(at url: URL) throws -> URL? {
            if let failingOriginalName, url.lastPathComponent.hasSuffix(failingOriginalName) {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let target = root.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: target)
            if let nilTrashOriginalName, url.lastPathComponent.hasSuffix(nilTrashOriginalName) {
                return nil
            }
            return target
        }
    }

    private func makeRoot() throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("QuarantineTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func item(
        _ url: URL,
        clusterID: UUID,
        pairOrigin: DeduplicationPlan.PairOrigin? = nil,
        unitID: UUID? = nil,
        sidecarOwners: Set<String> = []
    ) -> DeduplicationPlan.Item {
        let identity = try! FileIdentityHasher().hashIdentity(at: url)
        return DeduplicationPlan.Item(
            path: url.path,
            sizeBytes: identity.size,
            owningClusterID: clusterID,
            owningClusterKind: .exactDuplicate,
            pairOrigin: pairOrigin,
            expectedIdentity: identity,
            mutationUnitID: unitID,
            sidecarOwnerPaths: sidecarOwners
        )
    }

    private func commit(
        plan: DeduplicationPlan,
        root: URL,
        operations: TestTrashOps
    ) async throws -> [DeduplicateCommitEvent] {
        var events: [DeduplicateCommitEvent] = []
        for try await event in DeduplicateExecutor(fileOperations: operations).commit(
            plan: plan,
            destinationRoot: root.path,
            hardDelete: false,
            runID: UUID()
        ) { events.append(event) }
        return events
    }

    /// If the Trash rename fails and the journal cannot be pointed back at the
    /// hidden name, the journal's latest `.trashed` record would name a Trash
    /// location that never existed and the receipt would inherit it. The run
    /// must stop and put the file back instead of leaving it unfindable.
    // AGENTS-INVARIANT: 9
    // AGENTS-INVARIANT: 12
    func testFailedTrashRenameWithUnwritableJournalRestoresTheFile() throws {
        try assertJournalFailureRestoresFile(failingAppend: 4, failRename: true)
    }

    /// A journal append that fails before the rename may leave a partial
    /// line, so it stops the run like every other journal failure.
    // AGENTS-INVARIANT: 9
    // AGENTS-INVARIANT: 12
    func testUnwritableJournalBeforeTrashRenameRestoresTheFile() throws {
        try assertJournalFailureRestoresFile(failingAppend: 3, failRename: false)
    }

    private func assertJournalFailureRestoresFile(failingAppend: Int, failRename: Bool) throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("IMG_1.JPG")
        try Data([4, 2]).write(to: file)
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.failMovesIntoTrash = failRename
        var appended: [DeduplicateSpoolRecord] = []

        XCTAssertThrowsError(try DeduplicateExecutor.quarantineValidateAndTrash(
            items: [item(file, clusterID: UUID())],
            fileOperations: operations,
            prepareJournal: { item, quarantineURL in
                try DeduplicateExecutor.makeIntentRecord(item: item, quarantineURL: quarantineURL)
            },
            recordJournal: { record in
                // intent is prepared separately; appends here are quarantined,
                // trashed (hidden), trashed (visible), then the corrective one.
                appended.append(record)
                if appended.count == failingAppend { throw CocoaError(.fileWriteOutOfSpace) }
            }
        ))

        XCTAssertEqual(try Data(contentsOf: file), Data([4, 2]), "the file must be back at its original path")
        let leftInTrash = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("Trash").path)) ?? []
        XCTAssertTrue(leftInTrash.isEmpty, "nothing may be stranded in the Trash: \(leftInTrash)")
    }

    /// A rename that fails with a working journal leaves the item in the Trash
    /// under its hidden name, and the receipt and Revert use that location.
    // AGENTS-INVARIANT: 12
    // AGENTS-INVARIANT: 20
    func testFailedTrashRenameKeepsHiddenNameInReceiptAndRevertRestores() async throws {
        let root = try makeRoot()
        let file = root.appendingPathComponent("IMG_2.JPG")
        try Data([7, 7]).write(to: file)
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.failMovesIntoTrash = true

        let events = try await commit(
            plan: DeduplicationPlan(items: [item(file, clusterID: UUID())]),
            root: root,
            operations: operations
        )

        var trashURL: URL?
        var receiptPath: String?
        for event in events {
            if case let .itemTrashed(_, url, _) = event { trashURL = url }
            if case let .complete(summary) = event { receiptPath = summary.receiptPath }
        }
        let trashed = try XCTUnwrap(trashURL)
        XCTAssertTrue(trashed.lastPathComponent.contains(".chronoframe-quarantine-"))
        XCTAssertEqual(try Data(contentsOf: trashed), Data([7, 7]))
        let receiptURL = URL(fileURLWithPath: try XCTUnwrap(receiptPath))
        let receipt = try JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: Data(contentsOf: receiptURL))
        XCTAssertEqual(receipt.items.first?.trashURL.flatMap(URL.init(string:))?.standardizedFileURL, trashed.standardizedFileURL)

        operations.failMovesIntoTrash = false
        for try await _ in DeduplicateExecutor(fileOperations: operations).revert(receiptURL: receiptURL) {}
        XCTAssertEqual(try Data(contentsOf: file), Data([7, 7]))
    }

    /// A crash between journaling the visible Trash name and renaming to it
    /// leaves the journal naming a location that does not exist yet. Reading
    /// the journal must fall back to the hidden name the item still has.
    // AGENTS-INVARIANT: 9
    // AGENTS-INVARIANT: 20
    func testJournalNamingMissingVisibleTrashNameFallsBackToHiddenName() throws {
        let root = try makeRoot()
        let hidden = root.appendingPathComponent(".chronoframe-quarantine-X-IMG_3.JPG")
        try Data([3]).write(to: hidden)
        let visible = root.appendingPathComponent("IMG_3.JPG")
        let record = DeduplicateSpoolRecord(
            state: .trashed,
            originalPath: root.appendingPathComponent("elsewhere/IMG_3.JPG").path,
            quarantinePath: hidden.path,
            predictedTrashURL: hidden.absoluteString,
            actualTrashURL: visible.absoluteString
        )
        let spool = root.appendingPathComponent("journal.spool")
        var line = try JSONEncoder.dedupeSpool.encode(record)
        line.append(Data("\n".utf8))
        try line.write(to: spool)

        XCTAssertEqual(try DeduplicateExecutor.loadSpoolRecords(from: spool)[record.originalPath], hidden.absoluteString)

        try Data([3]).write(to: visible) // once the rename has happened, the visible name wins
        XCTAssertEqual(try DeduplicateExecutor.loadSpoolRecords(from: spool)[record.originalPath], visible.absoluteString)
    }

    // AGENTS-INVARIANT: 18
    func testPairMemberContentChangeRestoresWholeMutationUnit() async throws {
        let root = try makeRoot()
        let still = root.appendingPathComponent("IMG.HEIC")
        let movie = root.appendingPathComponent("IMG.MOV")
        try Data([1, 1, 1]).write(to: still)
        try Data([2, 2, 2]).write(to: movie)
        let clusterID = UUID(), unitID = UUID()
        let plan = DeduplicationPlan(items: [
            item(still, clusterID: clusterID, unitID: unitID),
            item(movie, clusterID: clusterID, pairOrigin: .livePhoto, unitID: unitID),
        ])
        try Data([9, 9, 9]).write(to: movie) // same size; content is authoritative

        let events = try await commit(
            plan: plan,
            root: root,
            operations: TestTrashOps(root: root.appendingPathComponent("Trash"))
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: still.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: movie.path))
        XCTAssertFalse(events.contains { if case .itemTrashed = $0 { true } else { false } })
    }

    func testPartialPairTrashFailureRollsBackEveryMember() async throws {
        let root = try makeRoot()
        let raw = root.appendingPathComponent("IMG.CR2")
        let jpeg = root.appendingPathComponent("IMG.JPG")
        try Data([1]).write(to: raw)
        try Data([2]).write(to: jpeg)
        let clusterID = UUID(), unitID = UUID()
        let plan = DeduplicationPlan(items: [
            item(raw, clusterID: clusterID, unitID: unitID),
            item(jpeg, clusterID: clusterID, pairOrigin: .rawJpeg, unitID: unitID),
        ])
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.failingOriginalName = "IMG.JPG"

        _ = try await commit(plan: plan, root: root, operations: operations)

        XCTAssertTrue(FileManager.default.fileExists(atPath: raw.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: jpeg.path))
    }

    func testNewBasenameOwnerAfterScanKeepsSidecar() async throws {
        let root = try makeRoot()
        let owner = root.appendingPathComponent("A.jpg")
        let sidecar = root.appendingPathComponent("A.xmp")
        try Data([1]).write(to: owner)
        try Data([2]).write(to: sidecar)
        let clusterID = UUID()
        let plan = DeduplicationPlan(items: [
            item(owner, clusterID: clusterID),
            item(sidecar, clusterID: clusterID, pairOrigin: .sidecar, sidecarOwners: [owner.path]),
        ])
        try Data([3]).write(to: root.appendingPathComponent("A.heic"))

        let events = try await commit(
            plan: plan,
            root: root,
            operations: TestTrashOps(root: root.appendingPathComponent("Trash"))
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
        XCTAssertTrue(events.contains {
            if case let .itemStale(path, reason) = $0 { return path == sidecar.path && reason.contains("new photo") }
            return false
        })
    }

    func testStaleParentKeepsPlannedSidecar() async throws {
        let root = try makeRoot()
        let owner = root.appendingPathComponent("parent.jpg")
        let sidecar = root.appendingPathComponent("parent.xmp")
        try Data([1, 1]).write(to: owner)
        try Data([2, 2]).write(to: sidecar)
        let clusterID = UUID()
        let plan = DeduplicationPlan(items: [
            item(owner, clusterID: clusterID),
            item(sidecar, clusterID: clusterID, pairOrigin: .sidecar, sidecarOwners: [owner.path]),
        ])
        try Data([9, 9]).write(to: owner)

        _ = try await commit(
            plan: plan,
            root: root,
            operations: TestTrashOps(root: root.appendingPathComponent("Trash"))
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: owner.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path))
    }

    func testChangedSidecarIsRestoredAfterParentTrash() async throws {
        let root = try makeRoot()
        let owner = root.appendingPathComponent("edited.jpg")
        let sidecar = root.appendingPathComponent("edited.xmp")
        try Data([1]).write(to: owner)
        try Data([2]).write(to: sidecar)
        let clusterID = UUID()
        let plan = DeduplicationPlan(items: [
            item(owner, clusterID: clusterID),
            item(sidecar, clusterID: clusterID, pairOrigin: .sidecar, sidecarOwners: [owner.path]),
        ])
        try Data([8]).write(to: sidecar)

        let events = try await commit(
            plan: plan,
            root: root,
            operations: TestTrashOps(root: root.appendingPathComponent("Trash"))
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: owner.path))
        XCTAssertEqual(try Data(contentsOf: sidecar), Data([8]))
        XCTAssertTrue(events.contains {
            if case let .itemStale(path, _) = $0 { return path == sidecar.path }
            return false
        })
    }

    func testSwapBetweenPreflightAndRenameIsCaughtByDescriptorHash() async throws {
        let root = try makeRoot()
        let target = root.appendingPathComponent("swap.jpg")
        try Data([1, 1, 1, 1]).write(to: target)
        let plan = DeduplicationPlan(items: [item(target, clusterID: UUID())])
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.swapOnQuarantine = Data([9, 9, 9, 9])

        let events = try await commit(plan: plan, root: root, operations: operations)

        XCTAssertEqual(try Data(contentsOf: target), Data([9, 9, 9, 9]))
        XCTAssertTrue(events.contains { if case .itemStale = $0 { true } else { false } })
    }

    func testMissingSymlinkAndDirectoryFailCheapPreflight() async throws {
        let root = try makeRoot()
        let missing = root.appendingPathComponent("missing.jpg")
        let symlink = root.appendingPathComponent("symlink.jpg")
        let directory = root.appendingPathComponent("directory.jpg")
        let target = root.appendingPathComponent("target.jpg")
        try Data([1]).write(to: missing)
        try Data([2]).write(to: symlink)
        try Data([3]).write(to: directory)
        try Data([4]).write(to: target)
        let missingItem = item(missing, clusterID: UUID())
        let symlinkItem = item(symlink, clusterID: UUID())
        let directoryItem = item(directory, clusterID: UUID())
        try FileManager.default.removeItem(at: missing)
        try FileManager.default.removeItem(at: symlink)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: target)
        try FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)

        let events = try await commit(
            plan: DeduplicationPlan(items: [missingItem, symlinkItem, directoryItem]),
            root: root,
            operations: TestTrashOps(root: root.appendingPathComponent("Trash"))
        )

        let staleReasons = events.compactMap { event -> String? in
            if case let .itemStale(_, reason) = event { return reason }
            return nil
        }
        XCTAssertEqual(staleReasons.count, 3)
        XCTAssertTrue(staleReasons.contains { $0.contains("no longer exists") })
        XCTAssertTrue(staleReasons.contains { $0.contains("symlink") })
        XCTAssertTrue(staleReasons.contains { $0.contains("regular file") })
    }

    func testSecondQuarantineFailureRestoresFirstMemberAndReportsOriginalError() async throws {
        let root = try makeRoot()
        let first = root.appendingPathComponent("FIRST.JPG")
        let second = root.appendingPathComponent("SECOND.JPG")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let unitID = UUID()
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.failingQuarantineOriginalName = second.lastPathComponent
        let events = try await commit(
            plan: DeduplicationPlan(items: [
                item(first, clusterID: UUID(), unitID: unitID),
                item(second, clusterID: UUID(), unitID: unitID),
            ]),
            root: root,
            operations: operations
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.path))
        XCTAssertTrue(events.contains {
            if case let .itemFailed(path, message) = $0 {
                return path == second.path && message.contains("quarantine")
            }
            return false
        })
    }

    func testRecreatedOriginalDuringQuarantineRollbackPreservesBothObjects() async throws {
        let root = try makeRoot()
        let first = root.appendingPathComponent("FIRST-RECREATED.JPG")
        let second = root.appendingPathComponent("SECOND-FAIL.JPG")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let unitID = UUID()
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.failingQuarantineOriginalName = second.lastPathComponent
        operations.recreateOriginalPathBeforeQuarantineFailure = first

        let events = try await commit(
            plan: DeduplicationPlan(items: [
                item(first, clusterID: UUID(), unitID: unitID),
                item(second, clusterID: UUID(), unitID: unitID),
            ]),
            root: root,
            operations: operations
        )

        XCTAssertEqual(try Data(contentsOf: first), Data("recreated".utf8))
        XCTAssertTrue(events.contains {
            if case let .itemFailed(path, message) = $0 {
                return path == first.path && message.contains("Manual recovery")
            }
            return false
        })
    }

    func testMissingTrashRecoveryURLReportsManualRecoveryForPair() async throws {
        let root = try makeRoot()
        let first = root.appendingPathComponent("NO-TRASH-URL.JPG")
        let second = root.appendingPathComponent("TRASH-FAIL.JPG")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let unitID = UUID()
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.nilTrashOriginalName = first.lastPathComponent
        operations.failingOriginalName = second.lastPathComponent

        let events = try await commit(
            plan: DeduplicationPlan(items: [
                item(first, clusterID: UUID(), unitID: unitID),
                item(second, clusterID: UUID(), unitID: unitID),
            ]),
            root: root,
            operations: operations
        )

        XCTAssertTrue(events.contains {
            if case let .itemFailed(path, message) = $0 {
                return path == first.path && message.contains("Manual recovery")
            }
            return false
        })
    }

    func testRollbackMoveFailureReportsPreservedRecoveryPath() async throws {
        let root = try makeRoot()
        let first = root.appendingPathComponent("ROLLBACK-MOVE.JPG")
        let second = root.appendingPathComponent("ROLLBACK-FAIL.JPG")
        try Data([1]).write(to: first)
        try Data([2]).write(to: second)
        let unitID = UUID()
        let operations = TestTrashOps(root: root.appendingPathComponent("Trash"))
        operations.failingOriginalName = second.lastPathComponent
        operations.failingMoveSourceName = first.lastPathComponent

        let events = try await commit(
            plan: DeduplicationPlan(items: [
                item(first, clusterID: UUID(), unitID: unitID),
                item(second, clusterID: UUID(), unitID: unitID),
            ]),
            root: root,
            operations: operations
        )

        XCTAssertTrue(events.contains {
            if case let .itemFailed(path, message) = $0 {
                return path == first.path && message.contains("Recover the preserved item")
            }
            return false
        })
    }
}
