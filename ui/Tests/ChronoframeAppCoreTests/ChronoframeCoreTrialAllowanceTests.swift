import Foundation
import XCTest
@testable import ChronoframeCore

/// Pins the pure metered-tier policy.
///
/// Every reservation decision in the app funnels through
/// `TrialAllowancePolicy.decide`, so the boundary cases here are the boundary
/// cases a customer actually hits: the run that exactly fills the allowance, the
/// run that exceeds it by one, and the empty run that must never be refused.
final class ChronoframeCoreTrialAllowanceTests: XCTestCase {
    private let caps = TrialAllowanceCaps(organizeFiles: 500, dedupeFiles: 100)

    private func balance(organizeUsed: Int = 0, dedupeUsed: Int = 0) -> TrialBalance {
        TrialBalance(
            caps: caps,
            usage: TrialUsage(organizeUsed: organizeUsed, dedupeUsed: dedupeUsed)
        )
    }

    // MARK: - Caps and usage lookup

    func testStandardCapsMatchSettledPolicy() {
        XCTAssertEqual(TrialAllowanceCaps.standard.organizeFiles, 500)
        XCTAssertEqual(TrialAllowanceCaps.standard.dedupeFiles, 100)
        XCTAssertEqual(TrialAllowanceCaps.standard.cap(for: .organize), 500)
        XCTAssertEqual(TrialAllowanceCaps.standard.cap(for: .dedupe), 100)
    }

    func testMetersAreExactlyOrganizeAndDedupe() {
        XCTAssertEqual(TrialMeter.allCases, [.organize, .dedupe])
        XCTAssertEqual(TrialMeter.organize.rawValue, "organize")
        XCTAssertEqual(TrialMeter.dedupe.rawValue, "dedupe")
    }

    func testUsageLookupIsPerMeter() {
        let usage = TrialUsage(organizeUsed: 7, dedupeUsed: 3)
        XCTAssertEqual(usage.used(for: .organize), 7)
        XCTAssertEqual(usage.used(for: .dedupe), 3)
        XCTAssertEqual(TrialUsage.none.used(for: .organize), 0)
        XCTAssertEqual(TrialUsage.none.used(for: .dedupe), 0)
    }

    // MARK: - Remaining

    func testPartialSpendLeavesTheRemainder() {
        let balance = balance(organizeUsed: 120, dedupeUsed: 40)
        XCTAssertEqual(balance.remaining(for: .organize), 380)
        XCTAssertEqual(balance.remaining(for: .dedupe), 60)
    }

    func testUsageExceedingTheCapReadsAsZeroNotNegative() {
        let balance = balance(organizeUsed: 900, dedupeUsed: 250)
        XCTAssertEqual(balance.remaining(for: .organize), 0)
        XCTAssertEqual(balance.remaining(for: .dedupe), 0)
    }

    func testUnspentAndExhaustedBalances() {
        XCTAssertEqual(TrialBalance.unspent(caps: caps).remaining(for: .organize), 500)
        XCTAssertEqual(TrialBalance.unspent(caps: caps).remaining(for: .dedupe), 100)
        XCTAssertEqual(TrialBalance.exhausted(caps: caps).remaining(for: .organize), 0)
        XCTAssertEqual(TrialBalance.exhausted(caps: caps).remaining(for: .dedupe), 0)
    }

    /// Usage is stored cumulatively, so raising a cap has to reach customers who
    /// already spent some of the old one without any migration.
    func testRaisingACapDoesNotChangeStoredUsage() {
        let usage = TrialUsage(organizeUsed: 400, dedupeUsed: 90)
        let before = TrialBalance(caps: caps, usage: usage)
        let after = TrialBalance(
            caps: TrialAllowanceCaps(organizeFiles: 1_000, dedupeFiles: 200),
            usage: usage
        )
        XCTAssertEqual(before.usage, after.usage)
        XCTAssertEqual(before.remaining(for: .organize), 100)
        XCTAssertEqual(after.remaining(for: .organize), 600)
        XCTAssertEqual(after.remaining(for: .dedupe), 110)
    }

    // MARK: - Decisions

    func testSpendWithinRemainingIsPermitted() {
        let decision = TrialAllowancePolicy.decide(
            requested: 100,
            meter: .organize,
            balance: balance(organizeUsed: 120)
        )
        XCTAssertEqual(decision, .permitted)
        XCTAssertTrue(decision.isPermitted)
        XCTAssertNil(decision.refusal)
    }

    func testExactBoundarySpendIsPermitted() {
        XCTAssertEqual(
            TrialAllowancePolicy.decide(requested: 380, meter: .organize, balance: balance(organizeUsed: 120)),
            .permitted
        )
        XCTAssertEqual(
            TrialAllowancePolicy.decide(requested: 60, meter: .dedupe, balance: balance(dedupeUsed: 40)),
            .permitted
        )
    }

    func testOverSpendByOneIsRefusedAndCarriesTheNumbers() {
        let decision = TrialAllowancePolicy.decide(
            requested: 381,
            meter: .organize,
            balance: balance(organizeUsed: 120)
        )
        XCTAssertEqual(
            decision,
            .refused(TrialRefusal(meter: .organize, requested: 381, remaining: 380))
        )
        XCTAssertFalse(decision.isPermitted)
        XCTAssertEqual(decision.refusal?.meter, .organize)
        XCTAssertEqual(decision.refusal?.requested, 381)
        XCTAssertEqual(decision.refusal?.remaining, 380)
    }

    func testRefusalOnAnExhaustedMeterReportsZeroRemaining() {
        let decision = TrialAllowancePolicy.decide(
            requested: 1,
            meter: .dedupe,
            balance: balance(dedupeUsed: 250)
        )
        XCTAssertEqual(
            decision,
            .refused(TrialRefusal(meter: .dedupe, requested: 1, remaining: 0))
        )
    }

    /// A run whose plan turns out empty must complete even for a customer with
    /// nothing left, so a non-positive request is never refused.
    func testZeroRequestIsPermittedEvenWhenExhausted() {
        XCTAssertEqual(
            TrialAllowancePolicy.decide(requested: 0, meter: .organize, balance: .exhausted(caps: caps)),
            .permitted
        )
    }

    func testNegativeRequestIsPermittedEvenWhenExhausted() {
        XCTAssertEqual(
            TrialAllowancePolicy.decide(requested: -5, meter: .dedupe, balance: .exhausted(caps: caps)),
            .permitted
        )
    }

    func testMetersAreIndependent() {
        let balance = balance(organizeUsed: 500, dedupeUsed: 0)
        XCTAssertEqual(TrialAllowancePolicy.decide(requested: 1, meter: .dedupe, balance: balance), .permitted)
        XCTAssertEqual(
            TrialAllowancePolicy.decide(requested: 1, meter: .organize, balance: balance),
            .refused(TrialRefusal(meter: .organize, requested: 1, remaining: 0))
        )
    }

    func testMeterCodesRoundTripForPersistence() throws {
        let encoded = try JSONEncoder().encode(TrialMeter.allCases)
        XCTAssertEqual(try JSONDecoder().decode([TrialMeter].self, from: encoded), TrialMeter.allCases)
        XCTAssertEqual(String(data: encoded, encoding: .utf8), #"["organize","dedupe"]"#)
    }
}
