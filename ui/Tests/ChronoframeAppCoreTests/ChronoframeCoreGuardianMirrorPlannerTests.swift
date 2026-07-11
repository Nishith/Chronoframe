import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreGuardianMirrorPlannerTests: XCTestCase {
    private let planner = GuardianMirrorPlanner()

    private func verifiedFinding(_ path: String, size: Int64, digest: String) -> GuardianIntegrityFinding {
        GuardianIntegrityFinding(
            relativePath: path,
            status: .verified,
            trustState: .trusted,
            expectedIdentity: FileIdentity(size: size, digest: digest),
            observedIdentity: FileIdentity(size: size, digest: digest)
        )
    }

    private func report(_ findings: [GuardianIntegrityFinding]) -> GuardianIntegrityReport {
        GuardianIntegrityReport(libraryRoot: "/lib", findings: findings)
    }

    private func mirrorObs(_ path: String, size: Int64, digest: String?, outcome: GuardianProbeOutcome = .hashed) -> GuardianFileObservation {
        GuardianFileObservation(relativePath: path, size: size, modificationTime: 0, digest: digest, outcome: outcome)
    }

    func testCreatesCopyForVerifiedFileMissingFromMirror() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([verifiedFinding("a.jpg", size: 10, digest: "good")]),
            mirrorObservations: []
        )
        XCTAssertEqual(plan.copies.count, 1)
        XCTAssertEqual(plan.copies.first?.kind, .create)
        XCTAssertEqual(plan.copies.first?.expectedIdentity, FileIdentity(size: 10, digest: "good"))
    }

    func testAlreadyMirroredWhenMirrorMatchesTrustedDigest() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([verifiedFinding("a.jpg", size: 10, digest: "good")]),
            mirrorObservations: [mirrorObs("a.jpg", size: 10, digest: "good")]
        )
        XCTAssertTrue(plan.copies.isEmpty)
        XCTAssertEqual(plan.alreadyMirrored, ["a.jpg"])
    }

    func testReplacesDivergentMirrorFromVerifiedPrimary() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([verifiedFinding("a.jpg", size: 10, digest: "good")]),
            mirrorObservations: [mirrorObs("a.jpg", size: 10, digest: "STALE")]
        )
        XCTAssertEqual(plan.copies.first?.kind, .replaceDivergent)
        XCTAssertEqual(plan.copies.first?.divergentMirrorIdentity, FileIdentity(size: 10, digest: "STALE"))
    }

    func testUnverifiedPrimaryNeverOverwritesMirror() {
        // Corrupt/modified/new library files must be blocked, not copied.
        let findings = [
            GuardianIntegrityFinding(relativePath: "corrupt.jpg", status: .corrupt, trustState: .changedPendingReview,
                                     expectedIdentity: FileIdentity(size: 10, digest: "good"),
                                     observedIdentity: FileIdentity(size: 10, digest: "rot")),
            GuardianIntegrityFinding(relativePath: "new.jpg", status: .new, trustState: .unprotected,
                                     observedIdentity: FileIdentity(size: 3, digest: "n")),
        ]
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report(findings),
            mirrorObservations: [mirrorObs("corrupt.jpg", size: 10, digest: "good")]
        )
        XCTAssertTrue(plan.copies.isEmpty, "an unverified primary must never be a copy source")
        XCTAssertEqual(Set(plan.blocked.map(\.reason)), [.primaryNotVerified])
    }

    func testMissingPrimaryRetainsMirrorCopy() {
        let findings = [
            GuardianIntegrityFinding(relativePath: "gone.jpg", status: .missing, trustState: .changedPendingReview,
                                     expectedIdentity: FileIdentity(size: 5, digest: "g")),
        ]
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report(findings),
            mirrorObservations: [mirrorObs("gone.jpg", size: 5, digest: "g")]
        )
        XCTAssertTrue(plan.copies.isEmpty)
        XCTAssertEqual(plan.blocked.first?.reason, .primaryMissing)
        // Deletion is never propagated: the mirror-only file is retained.
        XCTAssertEqual(plan.retainedExtras, ["gone.jpg"])
    }

    func testExtraMirrorFilesAreRetainedNotDeleted() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([verifiedFinding("a.jpg", size: 10, digest: "good")]),
            mirrorObservations: [
                mirrorObs("a.jpg", size: 10, digest: "good"),
                mirrorObs("orphan.jpg", size: 4, digest: "o"),
            ]
        )
        XCTAssertEqual(plan.retainedExtras, ["orphan.jpg"])
    }

    func testUnreadableMirrorCopyIsLeftUntouched() {
        let plan = planner.plan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            libraryReport: report([verifiedFinding("a.jpg", size: 10, digest: "good")]),
            mirrorObservations: [mirrorObs("a.jpg", size: 0, digest: nil, outcome: .unreadable)]
        )
        XCTAssertTrue(plan.copies.isEmpty)
        XCTAssertEqual(plan.blocked.first?.reason, .mirrorUnreadable)
    }
}
