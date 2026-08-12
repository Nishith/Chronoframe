import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers the dedupe gate (free-trial step 4, T9).
///
/// The gate lives on `NativeDeduplicateEngine`, not `DeduplicateSessionStore`,
/// because the store is a UI path a caller can route around. These tests go
/// through the engine for the same reason.
final class DeduplicateEngineTrialGateTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private let account = "app-txn-1"

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("DeduplicateEngineTrialGateTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Fixtures

    /// `count` real files in a fresh destination, and a plan that would trash
    /// every one of them.
    private func destinationWithPlan(fileCount: Int) throws -> (root: URL, plan: DeduplicationPlan, files: [URL]) {
        let root = temporaryDirectoryURL.appendingPathComponent("dest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        var files: [URL] = []
        var items: [DeduplicationPlan.Item] = []
        for index in 0..<fileCount {
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
        return (root, DeduplicationPlan(items: items), files)
    }

    /// A locked customer metered against a real ledger, using the production
    /// authorizer so the tests exercise the actual policy.
    @MainActor
    private func meteredEngine(
        ledger: any TrialLedger,
        evidence: any TrialReconciliationEvidence = FileSystemTrialReconciliationEvidence(),
        trashRoot: URL? = nil
    ) -> NativeDeduplicateEngine {
        NativeDeduplicateEngine(
            authorizer: EntitlementTrialAuthorizer(ledger: ledger) { [account] in
                TrialEntitlementSnapshot(state: .locked, accountKey: account)
            },
            executor: DeduplicateExecutor(
                fileOperations: StubTrashOperations(trashRoot: trashRoot ?? FileManager.default.temporaryDirectory
                    .appendingPathComponent("StubTrash-\(UUID().uuidString)", isDirectory: true))
            ),
            reconciliationEvidence: evidence
        )
    }

    private func logsContents(of root: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent(".organize_logs", isDirectory: true),
            includingPropertiesForKeys: nil
        )) ?? []
    }

    private static func drain(
        _ stream: AsyncThrowingStream<DeduplicateCommitEvent, Error>
    ) async throws -> [DeduplicateCommitEvent] {
        var events: [DeduplicateCommitEvent] = []
        for try await event in stream { events.append(event) }
        return events
    }

    // MARK: - Refusal

    /// The T9 acceptance criterion: a refused commit moves nothing to the Trash
    /// and writes no receipt or spool journal.
    ///
    /// The receipt matters as much as the Trash here. `DeduplicateExecutor.commit`
    /// starts a detached task the moment it is CALLED, so it writes the PENDING
    /// receipt and creates the spool whether or not anyone consumes its stream.
    /// A gate placed after that call would leave both artifacts behind for a run
    /// that never had permission to happen.
    @MainActor
    func testRefusedCommitTrashesNothingAndWritesNoReceiptOrSpool() async throws {
        let fixture = try destinationWithPlan(fileCount: 3)

        // Two of allowance against a three-file plan.
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 2))
        let engine = meteredEngine(ledger: ledger)

        let stream = try engine.commit(
            plan: fixture.plan,
            configuration: DeduplicateConfiguration(destinationPath: fixture.root.path)
        )

        do {
            _ = try await Self.drain(stream)
            XCTFail("A refused commit must not run")
        } catch let error as TrialAuthorizationError {
            guard case let .allowanceSpent(refusal) = error.refusal else {
                return XCTFail("A resolved locked customer is told the allowance is spent, got \(error.refusal)")
            }
            XCTAssertEqual(refusal.meter, .dedupe)
            XCTAssertEqual(refusal.requested, 3)
            XCTAssertEqual(refusal.remaining, 2)
        }

        for fileURL in fixture.files {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: fileURL.path),
                "A refused commit must move nothing to the Trash: \(fileURL.lastPathComponent) is gone"
            )
        }

        let logs = logsContents(of: fixture.root)
        XCTAssertTrue(
            logs.filter { $0.lastPathComponent.hasPrefix("dedupe_audit_receipt_") }.isEmpty,
            "A refused commit must write no receipt, got \(logs)"
        )
        XCTAssertTrue(
            logs.filter { $0.pathExtension == "spool" }.isEmpty,
            "A refused commit must write no spool journal, got \(logs)"
        )

        // A refusal writes nothing to the ledger, so the balance is unchanged.
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 0)
        XCTAssertTrue(try ledger.openReservations().isEmpty)
    }

    /// An unwritable destination fails at the destination lock, which `commit`
    /// takes before the gate — so no reservation is taken at all.
    ///
    /// This is why the gate needs no release branch for a pre-mutation failure:
    /// the lock and the receipt preflight both write `.organize_logs`, so the
    /// lock is the one that fails first, and it fails before anything is
    /// charged.
    @MainActor
    func testUnwritableDestinationFailsBeforeAnythingIsCharged() async throws {
        let fixture = try destinationWithPlan(fileCount: 2)
        // `.organize_logs` as a FILE, so neither the lock nor the receipt
        // directory can be created.
        try Data().write(to: fixture.root.appendingPathComponent(".organize_logs"))

        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 10))
        let engine = meteredEngine(ledger: ledger)

        XCTAssertThrowsError(
            try engine.commit(
                plan: fixture.plan,
                configuration: DeduplicateConfiguration(destinationPath: fixture.root.path)
            ),
            "An unwritable destination must abort before the gate"
        )

        for fileURL in fixture.files {
            XCTAssertTrue(FileManager.default.fileExists(atPath: fileURL.path), "Zero files touched")
        }
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 0)
        XCTAssertTrue(try ledger.openReservations().isEmpty)
    }

    // MARK: - Settling

    /// The reservation settles at what the evidence proves reached the Trash,
    /// not at the size of the plan that was authorized.
    @MainActor
    func testCommitSettlesAtTheCountTheEvidenceProves() async throws {
        let fixture = try destinationWithPlan(fileCount: 2)
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 10))
        let engine = meteredEngine(ledger: ledger, evidence: StubEvidence(result: .completed(count: 1)))

        let stream = try engine.commit(
            plan: fixture.plan,
            configuration: DeduplicateConfiguration(destinationPath: fixture.root.path)
        )
        _ = try await Self.drain(stream)

        XCTAssertEqual(
            try ledger.balance(accountKey: account).usage.dedupeUsed, 1,
            "One duplicate is proven trashed, so one is charged — not the two the plan reserved"
        )
        XCTAssertTrue(try ledger.openReservations().isEmpty)
    }

    /// Evidence that is not final settles nothing. A commit whose receipt is
    /// still `PENDING` can have more moves proven from its journal later, and
    /// `finalize` is one-way — so settling now would lock in a count that no
    /// later pass could correct.
    @MainActor
    func testCommitWithUnsettledEvidenceStaysFullyCharged() async throws {
        let fixture = try destinationWithPlan(fileCount: 2)
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 10))
        let engine = meteredEngine(ledger: ledger, evidence: StubEvidence(result: .unsettled))

        let stream = try engine.commit(
            plan: fixture.plan,
            configuration: DeduplicateConfiguration(destinationPath: fixture.root.path)
        )
        _ = try await Self.drain(stream)

        XCTAssertEqual(
            try ledger.balance(accountKey: account).usage.dedupeUsed, 2,
            "An open reservation stays charged in full until evidence settles it"
        )
        XCTAssertEqual(try ledger.openReservations().map(\.runID).count, 1)
    }

    /// End-to-end against the real filesystem evidence: a commit that trashes
    /// both planned files is charged for exactly those two.
    @MainActor
    func testCommitSettlesFromTheReceiptItActuallyWrote() async throws {
        let fixture = try destinationWithPlan(fileCount: 2)
        let ledger = InMemoryTrialLedger(caps: TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 10))

        let stream = try meteredEngine(ledger: ledger).commit(
            plan: fixture.plan,
            configuration: DeduplicateConfiguration(destinationPath: fixture.root.path)
        )
        let events = try await Self.drain(stream)

        let summary = events.compactMap { event -> DeduplicateCommitSummary? in
            if case let .complete(summary) = event { return summary }
            return nil
        }.last
        XCTAssertEqual(summary?.deletedCount, 2)

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.dedupeUsed, 2)
        XCTAssertTrue(try ledger.openReservations().isEmpty)
    }

    /// An unrestricted authorizer is the CLI and Developer ID channel, and must
    /// commit exactly as it did before the gate existed.
    @MainActor
    func testUnrestrictedAuthorizerCommitsWithoutMetering() async throws {
        let fixture = try destinationWithPlan(fileCount: 2)
        let engine = NativeDeduplicateEngine(
            authorizer: UnrestrictedTrialAuthorizer(),
            executor: DeduplicateExecutor(
                fileOperations: StubTrashOperations(
                    trashRoot: temporaryDirectoryURL.appendingPathComponent("trash", isDirectory: true)
                )
            )
        )

        let stream = try engine.commit(
            plan: fixture.plan,
            configuration: DeduplicateConfiguration(destinationPath: fixture.root.path)
        )
        let events = try await Self.drain(stream)

        let summary = events.compactMap { event -> DeduplicateCommitSummary? in
            if case let .complete(summary) = event { return summary }
            return nil
        }.last
        XCTAssertEqual(summary?.deletedCount, 2)
        for fileURL in fixture.files {
            XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
        }
    }
}

/// Pins the reconciliation outcome so settling is tested without staging Trash
/// state the test would then have to keep in sync with the executor.
private struct StubEvidence: TrialReconciliationEvidence {
    let result: TrialReconciliationOutcome

    func outcome(
        for reservation: OpenReservation,
        destinationRoot: URL
    ) -> TrialReconciliationOutcome {
        result
    }
}

/// Moves files into a scratch directory instead of the real Trash, so commits
/// are deterministic in sandboxed and headless environments.
private final class StubTrashOperations: DeduplicateFileOperations, @unchecked Sendable {
    private let trashRoot: URL

    init(trashRoot: URL) {
        self.trashRoot = trashRoot
    }

    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func trashItem(at url: URL) throws -> URL? {
        try FileManager.default.createDirectory(at: trashRoot, withIntermediateDirectories: true)
        let trashURL = trashRoot.appendingPathComponent("\(UUID().uuidString)-\(url.lastPathComponent)")
        try FileManager.default.moveItem(at: url, to: trashURL)
        return trashURL
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }
}
