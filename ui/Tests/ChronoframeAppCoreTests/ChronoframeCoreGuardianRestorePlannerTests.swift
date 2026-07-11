import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreGuardianRestorePlannerTests: XCTestCase {
    private let planner = GuardianRestorePlanner()

    private func report(_ findings: [GuardianIntegrityFinding]) -> GuardianIntegrityReport {
        GuardianIntegrityReport(libraryRoot: "/lib", findings: findings)
    }

    private func mirrorObs(_ path: String, size: Int64, digest: String?, outcome: GuardianProbeOutcome = .hashed) -> GuardianFileObservation {
        GuardianFileObservation(relativePath: path, size: size, modificationTime: 0, digest: digest, outcome: outcome)
    }

    private func corruptFinding(_ path: String, trusted: FileIdentity, observed: FileIdentity) -> GuardianIntegrityFinding {
        GuardianIntegrityFinding(relativePath: path, status: .corrupt, trustState: .changedPendingReview,
                                 expectedIdentity: trusted, observedIdentity: observed)
    }

    private func missingFinding(_ path: String, trusted: FileIdentity) -> GuardianIntegrityFinding {
        GuardianIntegrityFinding(relativePath: path, status: .missing, trustState: .changedPendingReview,
                                 expectedIdentity: trusted)
    }

    func testRestoresCorruptPrimaryWhenMirrorMatchesTrustedDigest() {
        let trusted = FileIdentity(size: 10, digest: "good")
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([corruptFinding("a.jpg", trusted: trusted, observed: FileIdentity(size: 10, digest: "rot"))]),
            mirrorObservations: [mirrorObs("a.jpg", size: 10, digest: "good")]
        )
        XCTAssertEqual(plan.restorable.count, 1)
        XCTAssertEqual(plan.restorable.first?.reason, .primaryCorrupt)
        XCTAssertEqual(plan.restorable.first?.trustedIdentity, trusted)
        XCTAssertEqual(plan.restorable.first?.expectedCurrentPrimaryIdentity, FileIdentity(size: 10, digest: "rot"))
    }

    func testRestoresMissingPrimaryWhenMirrorMatches() {
        let trusted = FileIdentity(size: 5, digest: "g")
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([missingFinding("gone.jpg", trusted: trusted)]),
            mirrorObservations: [mirrorObs("gone.jpg", size: 5, digest: "g")]
        )
        XCTAssertEqual(plan.restorable.first?.reason, .primaryMissing)
        XCTAssertNil(plan.restorable.first?.expectedCurrentPrimaryIdentity)
    }

    func testCorruptOnBothSidesIsBlockedNeverRestored() {
        let trusted = FileIdentity(size: 10, digest: "good")
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([corruptFinding("a.jpg", trusted: trusted, observed: FileIdentity(size: 10, digest: "rot"))]),
            mirrorObservations: [mirrorObs("a.jpg", size: 10, digest: "ALSO-ROTTEN")]
        )
        XCTAssertTrue(plan.restorable.isEmpty, "must never restore from a mirror copy that fails verification")
        XCTAssertEqual(plan.blocked.first?.reason, .mirrorDivergent)
    }

    func testMissingMirrorCopyIsBlocked() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([missingFinding("gone.jpg", trusted: FileIdentity(size: 5, digest: "g"))]),
            mirrorObservations: []
        )
        XCTAssertTrue(plan.restorable.isEmpty)
        XCTAssertEqual(plan.blocked.first?.reason, .mirrorMissing)
    }

    func testUnreadableMirrorCopyIsBlocked() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([corruptFinding("a.jpg", trusted: FileIdentity(size: 10, digest: "good"), observed: FileIdentity(size: 10, digest: "rot"))]),
            mirrorObservations: [mirrorObs("a.jpg", size: 0, digest: nil, outcome: .unreadable)]
        )
        XCTAssertTrue(plan.restorable.isEmpty)
        XCTAssertEqual(plan.blocked.first?.reason, .mirrorUnreadable)
    }

    func testVerifiedAndNewFindingsAreIgnored() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([
                GuardianIntegrityFinding(relativePath: "ok.jpg", status: .verified, trustState: .trusted,
                                         expectedIdentity: FileIdentity(size: 1, digest: "x")),
                GuardianIntegrityFinding(relativePath: "new.jpg", status: .new, trustState: .unprotected,
                                         observedIdentity: FileIdentity(size: 2, digest: "y")),
            ]),
            mirrorObservations: [mirrorObs("ok.jpg", size: 1, digest: "x")]
        )
        XCTAssertTrue(plan.restorable.isEmpty)
        XCTAssertTrue(plan.blocked.isEmpty)
    }
}
