import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class GuardianSchedulerTests: XCTestCase {
    private let scheduler = GuardianScheduler()
    private let t0 = Date(timeIntervalSince1970: 1_000_000)

    private func report(_ statuses: [GuardianIntegrityStatus], partial: Bool = false) -> GuardianIntegrityReport {
        var findings: [GuardianIntegrityFinding] = []
        for (index, status) in statuses.enumerated() {
            findings.append(GuardianIntegrityFinding(relativePath: "f\(index)", status: status, trustState: .trusted))
        }
        return GuardianIntegrityReport(libraryRoot: "/lib", findings: findings, partialScan: partial)
    }

    // MARK: - scrubDecision

    func testDisabledWhenAutoScrubOff() {
        XCTAssertEqual(
            scheduler.scrubDecision(state: GuardianScheduleState(), interval: 3_600, autoScrubEnabled: false, now: t0),
            .disabled
        )
    }

    func testDisabledWhenIntervalNonPositive() {
        XCTAssertEqual(
            scheduler.scrubDecision(state: GuardianScheduleState(), interval: 0, autoScrubEnabled: true, now: t0),
            .disabled
        )
    }

    func testRunsWhenNeverScheduled() {
        XCTAssertEqual(
            scheduler.scrubDecision(state: GuardianScheduleState(), interval: 3_600, autoScrubEnabled: true, now: t0),
            .run
        )
    }

    func testWaitsWhenNextRunIsInFuture() {
        let state = GuardianScheduleState(nextRunAt: t0.addingTimeInterval(3_600))
        XCTAssertEqual(
            scheduler.scrubDecision(state: state, interval: 3_600, autoScrubEnabled: true, now: t0),
            .waitUntil(t0.addingTimeInterval(3_600))
        )
    }

    func testRunsWhenDue() {
        let state = GuardianScheduleState(nextRunAt: t0)
        XCTAssertEqual(
            scheduler.scrubDecision(state: state, interval: 3_600, autoScrubEnabled: true, now: t0.addingTimeInterval(1)),
            .run
        )
    }

    func testCatchUpAMissedRunCollapsesToASingleRun() {
        // The app was quit for many intervals; the decision is a single .run, and
        // advancing re-anchors next-run to now + interval (no back-to-back backlog).
        let longAgo = t0.addingTimeInterval(-100 * 3_600)
        let state = GuardianScheduleState(nextRunAt: longAgo)
        XCTAssertEqual(
            scheduler.scrubDecision(state: state, interval: 3_600, autoScrubEnabled: true, now: t0),
            .run
        )
        let advanced = scheduler.advance(state: state, interval: 3_600, attemptedAt: t0, succeeded: true)
        XCTAssertEqual(advanced.nextRunAt, t0.addingTimeInterval(3_600))
        XCTAssertEqual(
            scheduler.scrubDecision(state: advanced, interval: 3_600, autoScrubEnabled: true, now: t0),
            .waitUntil(t0.addingTimeInterval(3_600))
        )
    }

    // MARK: - advance

    func testAdvanceRecordsSuccessTimestamps() {
        let advanced = scheduler.advance(state: GuardianScheduleState(), interval: 3_600, attemptedAt: t0, succeeded: true)
        XCTAssertEqual(advanced.lastAttemptedAt, t0)
        XCTAssertEqual(advanced.lastSucceededAt, t0)
        XCTAssertEqual(advanced.nextRunAt, t0.addingTimeInterval(3_600))
    }

    func testAdvanceRecordsAttemptButNotSuccessOnFailure() {
        let advanced = scheduler.advance(state: GuardianScheduleState(), interval: 3_600, attemptedAt: t0, succeeded: false)
        XCTAssertEqual(advanced.lastAttemptedAt, t0)
        XCTAssertNil(advanced.lastSucceededAt)
        XCTAssertEqual(advanced.nextRunAt, t0.addingTimeInterval(3_600))
    }

    // MARK: - shouldAutoMirror

    func testAutoMirrorRunsAfterCleanCompleteScrub() {
        XCTAssertTrue(scheduler.shouldAutoMirror(
            report: report([.verified, .verified, .new]),
            autoMirrorEnabled: true,
            mirrorOnline: true
        ))
    }

    func testAutoMirrorSkippedWhenDisabled() {
        XCTAssertFalse(scheduler.shouldAutoMirror(report: report([.verified]), autoMirrorEnabled: false, mirrorOnline: true))
    }

    func testAutoMirrorSkippedWhenMirrorOffline() {
        XCTAssertFalse(scheduler.shouldAutoMirror(report: report([.verified]), autoMirrorEnabled: true, mirrorOnline: false))
    }

    func testAutoMirrorSkippedWhenScanPartial() {
        XCTAssertFalse(scheduler.shouldAutoMirror(
            report: report([.verified], partial: true),
            autoMirrorEnabled: true,
            mirrorOnline: true
        ))
    }

    func testAutoMirrorSkippedWhenLibraryHasCorruption() {
        XCTAssertFalse(scheduler.shouldAutoMirror(
            report: report([.verified, .corrupt]),
            autoMirrorEnabled: true,
            mirrorOnline: true
        ))
    }

    func testAutoMirrorSkippedWhenAnyFileWasUnreadable() {
        XCTAssertFalse(scheduler.shouldAutoMirror(
            report: report([.verified, .unreadable]),
            autoMirrorEnabled: true,
            mirrorOnline: true
        ))
    }
}
