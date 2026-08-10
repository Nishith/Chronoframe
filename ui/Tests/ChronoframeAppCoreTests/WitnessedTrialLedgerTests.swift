import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

/// Covers the witness that stops "delete `ledger.db`" from being a free
/// allowance reset, and — just as importantly — stops it from breaking the
/// legitimate ways usage goes back down.
final class WitnessedTrialLedgerTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private let account = "app-txn-1"
    private let otherAccount = "app-txn-2"
    private let caps = TrialAllowanceCaps(organizeFiles: 10, dedupeFiles: 4)

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("WitnessedTrialLedgerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    private var ledgerURL: URL {
        temporaryDirectoryURL.appendingPathComponent("ledger.db")
    }

    private func makeDatabase() throws -> TrialLedgerDatabase {
        try TrialLedgerDatabase(url: ledgerURL, caps: caps)
    }

    /// Remove the database the way a user would — including the WAL sidecars, so
    /// the reopened ledger is genuinely empty rather than recovered.
    private func deleteLedgerFiles() throws {
        try FileManager.default.removeItem(at: ledgerURL)
        for suffix in ["-wal", "-shm"] {
            let sidecar = URL(fileURLWithPath: ledgerURL.path + suffix)
            try? FileManager.default.removeItem(at: sidecar)
        }
    }

    // MARK: - The reset it exists to stop

    func testDeletingTheLedgerDoesNotRestoreASpentAllowance() throws {
        let witness = InMemoryTrialUsageWitness()

        do {
            let database = try makeDatabase()
            let ledger = WitnessedTrialLedger(base: database, witness: witness)
            let runID = UUID()
            _ = try ledger.reserve(
                runID: runID,
                accountKey: account,
                meter: .organize,
                count: 8,
                destinationRoot: nil
            )
            try ledger.finalize(runID: runID, actualCount: 8)
            XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 2)
            database.close()
        }

        // Quit the app, delete the database, relaunch.
        try deleteLedgerFiles()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ledgerURL.path))

        let reopened = WitnessedTrialLedger(base: try makeDatabase(), witness: witness)
        XCTAssertEqual(try reopened.balance(accountKey: account).usage.organizeUsed, 8)
        XCTAssertEqual(try reopened.balance(accountKey: account).remaining(for: .organize), 2)
        XCTAssertEqual(
            try reopened.reserve(
                runID: UUID(),
                accountKey: account,
                meter: .organize,
                count: 5,
                destinationRoot: nil
            ),
            .refused(TrialRefusal(meter: .organize, requested: 5, remaining: 2))
        )
    }

    /// The witness must not become a second, permanent allowance for a
    /// customer who never spent one.
    func testWitnessDoesNotAffectAnAccountItHasNotSeen() throws {
        let witness = InMemoryTrialUsageWitness()
        let ledger = WitnessedTrialLedger(base: try makeDatabase(), witness: witness)
        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: nil)
        try ledger.finalize(runID: runID, actualCount: 6)

        XCTAssertEqual(try ledger.balance(accountKey: otherAccount).remaining(for: .organize), 10)
        XCTAssertEqual(try ledger.balance(accountKey: otherAccount).remaining(for: .dedupe), 4)
    }

    // MARK: - Legitimate decreases still work

    /// A pure high-water mark would break the settled "revert refunds
    /// allowance" policy. The witness is written through on refund, so it does
    /// not.
    func testARefundStillLowersUsageThroughTheWitness() throws {
        let witness = InMemoryTrialUsageWitness()
        let database = try makeDatabase()
        let ledger = WitnessedTrialLedger(base: database, witness: witness)

        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 4, destinationRoot: nil)
        try ledger.finalize(runID: runID, actualCount: 4)
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 4)

        try ledger.refund(
            receiptRunID: runID,
            accountKey: account,
            meter: .organize,
            itemPaths: ["/dest/a.jpg", "/dest/b.jpg", "/dest/c.jpg", "/dest/d.jpg"]
        )

        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 0)
        XCTAssertEqual(witness.recordedUsage(accountKey: account)?.organizeUsed, 0)
        // And it survives a restart at the lower value.
        database.close()
        let reopened = WitnessedTrialLedger(base: try makeDatabase(), witness: witness)
        XCTAssertEqual(try reopened.balance(accountKey: account).remaining(for: .organize), 10)
    }

    func testFinalizingBelowTheReservationLowersTheWitness() throws {
        let witness = InMemoryTrialUsageWitness()
        let ledger = WitnessedTrialLedger(base: try makeDatabase(), witness: witness)

        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 9, destinationRoot: nil)
        XCTAssertEqual(witness.recordedUsage(accountKey: account)?.organizeUsed, 9)

        try ledger.finalize(runID: runID, actualCount: 2)

        XCTAssertEqual(witness.recordedUsage(accountKey: account)?.organizeUsed, 2)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 8)
    }

    func testReleasingAReservationLowersTheWitness() throws {
        let witness = InMemoryTrialUsageWitness()
        let ledger = WitnessedTrialLedger(base: try makeDatabase(), witness: witness)

        let runID = UUID()
        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .dedupe, count: 4, destinationRoot: nil)
        XCTAssertEqual(witness.recordedUsage(accountKey: account)?.dedupeUsed, 4)

        try ledger.release(runID: runID)

        XCTAssertEqual(witness.recordedUsage(accountKey: account)?.dedupeUsed, 0)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .dedupe), 4)
    }

    // MARK: - Crash posture

    /// An open reservation is charged in full, and the witness records that, so
    /// a crash before finalize keeps the allowance spent even if the database
    /// is then removed.
    func testAnOpenReservationIsWitnessedAtItsFullReservedAmount() throws {
        let witness = InMemoryTrialUsageWitness()
        let database = try makeDatabase()
        let ledger = WitnessedTrialLedger(base: database, witness: witness)

        _ = try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 7, destinationRoot: "/d")
        XCTAssertEqual(witness.recordedUsage(accountKey: account)?.organizeUsed, 7)

        database.close()
        try deleteLedgerFiles()
        let reopened = WitnessedTrialLedger(base: try makeDatabase(), witness: witness)
        XCTAssertEqual(try reopened.balance(accountKey: account).remaining(for: .organize), 3)
    }

    // MARK: - Failure posture

    /// A Keychain that cannot be read must degrade to the ledger's own numbers,
    /// never to a lockout.
    func testAnUnavailableWitnessDegradesToTheLedgerAlone() throws {
        let ledger = WitnessedTrialLedger(base: try makeDatabase(), witness: NullTrialUsageWitness())

        let balance = try ledger.balance(accountKey: account)
        XCTAssertEqual(balance.remaining(for: .organize), 10)
        XCTAssertEqual(balance.remaining(for: .dedupe), 4)

        let runID = UUID()
        XCTAssertEqual(
            try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 10, destinationRoot: nil),
            .permitted
        )
        try ledger.finalize(runID: runID, actualCount: 10)
        XCTAssertEqual(try ledger.balance(accountKey: account).remaining(for: .organize), 0)
    }

    // MARK: - Pass-through

    func testTheWrapperDoesNotChangeOrdinaryLedgerBehaviour() throws {
        let ledger = WitnessedTrialLedger(
            base: try makeDatabase(),
            witness: InMemoryTrialUsageWitness()
        )
        let runID = UUID()

        _ = try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: "/d")
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [runID])
        // Re-reserving still does not stack.
        XCTAssertEqual(
            try ledger.reserve(runID: runID, accountKey: account, meter: .organize, count: 6, destinationRoot: "/d"),
            .permitted
        )
        XCTAssertEqual(try ledger.balance(accountKey: account).usage.organizeUsed, 6)
        // Refusals still write nothing.
        XCTAssertEqual(
            try ledger.reserve(runID: UUID(), accountKey: account, meter: .organize, count: 5, destinationRoot: nil),
            .refused(TrialRefusal(meter: .organize, requested: 5, remaining: 4))
        )
        XCTAssertEqual(try ledger.openReservations().count, 1)
        // A no-op run is never refused, even with only 4 left.
        let emptyRun = UUID()
        XCTAssertEqual(
            try ledger.reserve(runID: emptyRun, accountKey: account, meter: .organize, count: 0, destinationRoot: nil),
            .permitted
        )
        try ledger.finalize(runID: runID, actualCount: 6)
        XCTAssertEqual(try ledger.openReservations().map(\.runID), [emptyRun])
    }

    func testInMemoryWitnessRoundTripsPerAccount() {
        let witness = InMemoryTrialUsageWitness()
        XCTAssertNil(witness.recordedUsage(accountKey: account))

        witness.record(usage: TrialUsage(organizeUsed: 3, dedupeUsed: 1), accountKey: account)
        witness.record(usage: TrialUsage(organizeUsed: 9, dedupeUsed: 2), accountKey: otherAccount)

        XCTAssertEqual(witness.recordedUsage(accountKey: account), TrialUsage(organizeUsed: 3, dedupeUsed: 1))
        XCTAssertEqual(witness.recordedUsage(accountKey: otherAccount), TrialUsage(organizeUsed: 9, dedupeUsed: 2))

        // It is a record of current truth, so it accepts a lower value.
        witness.record(usage: TrialUsage(organizeUsed: 0, dedupeUsed: 0), accountKey: account)
        XCTAssertEqual(witness.recordedUsage(accountKey: account), TrialUsage.none)
    }
}
