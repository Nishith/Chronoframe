import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreDeduplicateReviewRestorerTests: XCTestCase {
    private let savedAt = Date(timeIntervalSince1970: 1_700_000_000)
    private let configuration = DeduplicateConfiguration(destinationPath: "/lib")

    private func identity(_ name: String) -> FileIdentity {
        FileIdentity(size: 100, digest: "digest-\(name)")
    }

    private func cluster(_ paths: [String], id: UUID = UUID()) -> DuplicateCluster {
        DuplicateCluster(
            id: id,
            kind: .exactDuplicate,
            members: paths.map { PhotoCandidate(path: $0, size: 100, modificationTime: 1) },
            suggestedKeeperIDs: [paths[0]],
            bytesIfPruned: 100
        )
    }

    private struct Fixture {
        var clusterA: DuplicateCluster
        var clusterB: DuplicateCluster
        var scan: DeduplicateScanSnapshot
        var suggested: DedupeDecisions
        var clusters: [DuplicateCluster] { [clusterA, clusterB] }
    }

    private func makeFixture() -> Fixture {
        let a = cluster(["/lib/a1.jpg", "/lib/a2.jpg"])
        let b = cluster(["/lib/b1.jpg", "/lib/b2.jpg"])
        var identities: [String: FileIdentity] = [:]
        for path in ["a1", "a2", "b1", "b2"] {
            identities["/lib/\(path).jpg"] = identity(path)
        }
        return Fixture(
            clusterA: a,
            clusterB: b,
            scan: DeduplicateScanSnapshot(identitiesByPath: identities),
            suggested: DedupeDecisions(byPath: [
                "/lib/a1.jpg": .keep, "/lib/a2.jpg": .delete,
                "/lib/b1.jpg": .keep, "/lib/b2.jpg": .delete,
            ])
        )
    }

    private func key(_ names: [String]) -> String {
        DeduplicateReviewKeys.groupKey(memberIdentities: names.map(identity))
    }

    private func snapshot(
        decisions: [DeduplicateSavedDecision] = [],
        approvals: [DeduplicateSavedGroupApproval] = [],
        focus: String? = nil,
        fingerprint: String? = nil
    ) -> DeduplicateReviewSnapshot {
        DeduplicateReviewSnapshot(
            folderPath: "/lib",
            savedAt: savedAt,
            configurationFingerprint: fingerprint ?? configuration.reviewFingerprint,
            decisions: decisions,
            approvals: approvals,
            focusGroupKey: focus
        )
    }

    private func restore(_ saved: DeduplicateReviewSnapshot, _ fixture: Fixture) -> DeduplicateReviewRestoration {
        DeduplicateReviewRestorer.restore(
            snapshot: saved,
            clusters: fixture.clusters,
            scanSnapshot: fixture.scan,
            suggested: fixture.suggested,
            currentFingerprint: configuration.reviewFingerprint
        )
    }

    // AGENTS-INVARIANT: 29
    func testRestoresDecisionOnlyWhenIdentityMatches() {
        let fixture = makeFixture()
        let saved = snapshot(decisions: [
            DeduplicateSavedDecision(path: "/lib/a2.jpg", identity: identity("a2"), decision: .keep),
            DeduplicateSavedDecision(path: "/lib/b2.jpg", identity: identity("b2-old"), decision: .keep),
        ])

        let result = restore(saved, fixture)

        XCTAssertEqual(result.decisions.byPath["/lib/a2.jpg"], .keep)
        XCTAssertEqual(result.decisions.byPath["/lib/b2.jpg"], .delete, "changed content must not carry a saved choice")
        XCTAssertEqual(result.restoredDecisionCount, 1)
        XCTAssertEqual(result.droppedDecisionCount, 1)
        XCTAssertEqual(result.savedAt, savedAt)
    }

    func testDroppedDecisionIsCountedAndSuggestionKept() {
        let fixture = makeFixture()
        let saved = snapshot(decisions: [
            // Path no longer in the scan.
            DeduplicateSavedDecision(path: "/lib/gone.jpg", identity: identity("gone"), decision: .delete),
            // Identity known to the scan but the path is not a cluster member.
            DeduplicateSavedDecision(path: "/lib/solo.jpg", identity: identity("solo"), decision: .delete),
            // Differing identity.
            DeduplicateSavedDecision(path: "/lib/a1.jpg", identity: identity("a1-old"), decision: .delete),
        ])
        var scan = fixture.scan
        var identities = scan.identitiesByPath
        identities["/lib/solo.jpg"] = identity("solo")
        scan = DeduplicateScanSnapshot(identitiesByPath: identities)
        var f = fixture
        f.scan = scan

        let result = restore(saved, f)

        XCTAssertEqual(result.decisions, fixture.suggested)
        XCTAssertNil(result.decisions.byPath["/lib/gone.jpg"])
        XCTAssertNil(result.decisions.byPath["/lib/solo.jpg"])
        XCTAssertEqual(result.restoredDecisionCount, 0)
        XCTAssertEqual(result.droppedDecisionCount, 3)
    }

    func testApprovalRestoresWhenMemberIdentitiesUnchanged() {
        let fixture = makeFixture()
        let saved = snapshot(
            decisions: [
                DeduplicateSavedDecision(path: "/lib/a1.jpg", identity: identity("a1"), decision: .keep),
                DeduplicateSavedDecision(path: "/lib/a2.jpg", identity: identity("a2"), decision: .delete),
            ],
            approvals: [DeduplicateSavedGroupApproval(groupKey: key(["a1", "a2"]), memberCount: 2)]
        )

        let result = restore(saved, fixture)

        XCTAssertEqual(result.approvedClusterIDs, [fixture.clusterA.id])
        XCTAssertEqual(result.restoredGroupCount, 1)
        XCTAssertEqual(result.changedGroupCount, 0)
    }

    // AGENTS-INVARIANT: 29
    func testApprovalNotRestoredWhenAMemberChanged() {
        var fixture = makeFixture()
        let saved = snapshot(
            decisions: [DeduplicateSavedDecision(path: "/lib/a2.jpg", identity: identity("a2"), decision: .delete)],
            approvals: [DeduplicateSavedGroupApproval(groupKey: key(["a1", "a2"]), memberCount: 2)]
        )
        var identities = fixture.scan.identitiesByPath
        identities["/lib/a2.jpg"] = identity("a2-edited")
        fixture.scan = DeduplicateScanSnapshot(identitiesByPath: identities)
        fixture.suggested.byPath["/lib/a2.jpg"] = .keep

        let result = restore(saved, fixture)

        XCTAssertTrue(result.approvedClusterIDs.isEmpty)
        XCTAssertEqual(result.restoredGroupCount, 0)
        XCTAssertEqual(result.changedGroupCount, 1)
        XCTAssertEqual(result.decisions.byPath["/lib/a2.jpg"], .keep, "a stale Delete must not survive an edit")
        XCTAssertEqual(result.droppedDecisionCount, 1)
    }

    func testApprovalNotRestoredWhenMembershipGrew() {
        var fixture = makeFixture()
        let saved = snapshot(approvals: [
            DeduplicateSavedGroupApproval(groupKey: key(["a1", "a2"]), memberCount: 2),
        ])
        fixture.clusterA = cluster(["/lib/a1.jpg", "/lib/a2.jpg", "/lib/a3.jpg"], id: fixture.clusterA.id)
        var identities = fixture.scan.identitiesByPath
        identities["/lib/a3.jpg"] = identity("a3")
        fixture.scan = DeduplicateScanSnapshot(identitiesByPath: identities)

        let result = restore(saved, fixture)

        XCTAssertTrue(result.approvedClusterIDs.isEmpty)
        XCTAssertEqual(result.restoredGroupCount, 0)
        XCTAssertEqual(result.changedGroupCount, 1)
    }

    func testGroupWithDroppedDecisionIsNotApproved() {
        let fixture = makeFixture()
        // Hand-built: the approval key matches current identities, but one of the
        // group's saved decisions carries a stale identity and is dropped.
        let saved = snapshot(
            decisions: [
                DeduplicateSavedDecision(path: "/lib/a2.jpg", identity: identity("a2-stale"), decision: .delete),
                DeduplicateSavedDecision(path: "/lib/b1.jpg", identity: identity("b1"), decision: .keep),
                DeduplicateSavedDecision(path: "/lib/b2.jpg", identity: identity("b2"), decision: .keep),
            ],
            approvals: [
                DeduplicateSavedGroupApproval(groupKey: key(["a1", "a2"]), memberCount: 2),
                DeduplicateSavedGroupApproval(groupKey: key(["b1", "b2"]), memberCount: 2),
            ]
        )

        let result = restore(saved, fixture)

        XCTAssertEqual(result.approvedClusterIDs, [fixture.clusterB.id])
        XCTAssertEqual(result.restoredGroupCount, 1)
        XCTAssertEqual(result.changedGroupCount, 1)
        XCTAssertEqual(result.restoredDecisionCount, 2)
        XCTAssertEqual(result.droppedDecisionCount, 1)
    }

    // AGENTS-INVARIANT: 29
    func testApprovalNotRestoredWhenAMemberPathChanged() {
        // Saved: delete A, keep B. Since then B was renamed to C (same content).
        let shared = identity("same-content")
        let other = identity("other-content")
        let a = cluster(["/lib/A.jpg", "/lib/C.jpg"])
        let scan = DeduplicateScanSnapshot(identitiesByPath: ["/lib/A.jpg": other, "/lib/C.jpg": shared])
        let key = DeduplicateReviewKeys.groupKey(memberIdentities: [other, shared])
        let saved = snapshot(
            decisions: [
                DeduplicateSavedDecision(path: "/lib/A.jpg", identity: other, decision: .delete),
                DeduplicateSavedDecision(path: "/lib/B.jpg", identity: shared, decision: .keep),
            ],
            approvals: [DeduplicateSavedGroupApproval(groupKey: key, memberCount: 2)]
        )

        let result = DeduplicateReviewRestorer.restore(
            snapshot: saved,
            clusters: [a],
            scanSnapshot: scan,
            suggested: DedupeDecisions(byPath: ["/lib/A.jpg": .keep, "/lib/C.jpg": .delete]),
            currentFingerprint: configuration.reviewFingerprint
        )

        XCTAssertTrue(result.approvedClusterIDs.isEmpty, "choices the user never made must not be approved")
        XCTAssertEqual(result.decisions.byPath["/lib/A.jpg"], .delete)
        XCTAssertEqual(result.decisions.byPath["/lib/C.jpg"], .delete)
        XCTAssertEqual(result.restoredGroupCount, 0)
        XCTAssertEqual(result.changedGroupCount, 1)
    }

    func testApprovalNotRestoredForSecondClusterSharingIdentities() {
        let shared1 = identity("s1")
        let shared2 = identity("s2")
        let first = cluster(["/lib/x1.jpg", "/lib/x2.jpg"])
        let second = cluster(["/lib/y1.jpg", "/lib/y2.jpg"])
        let scan = DeduplicateScanSnapshot(identitiesByPath: [
            "/lib/x1.jpg": shared1, "/lib/x2.jpg": shared2,
            "/lib/y1.jpg": shared1, "/lib/y2.jpg": shared2,
        ])
        let saved = snapshot(
            decisions: [
                DeduplicateSavedDecision(path: "/lib/x1.jpg", identity: shared1, decision: .keep),
                DeduplicateSavedDecision(path: "/lib/x2.jpg", identity: shared2, decision: .delete),
            ],
            approvals: [DeduplicateSavedGroupApproval(
                groupKey: DeduplicateReviewKeys.groupKey(memberIdentities: [shared1, shared2]),
                memberCount: 2
            )]
        )

        let result = DeduplicateReviewRestorer.restore(
            snapshot: saved,
            clusters: [first, second],
            scanSnapshot: scan,
            suggested: DedupeDecisions(byPath: [
                "/lib/x1.jpg": .keep, "/lib/x2.jpg": .delete,
                "/lib/y1.jpg": .keep, "/lib/y2.jpg": .delete,
            ]),
            currentFingerprint: configuration.reviewFingerprint
        )

        XCTAssertEqual(result.approvedClusterIDs, [first.id])
        XCTAssertEqual(result.restoredGroupCount, 1)
        XCTAssertEqual(result.changedGroupCount, 0)
    }

    func testApprovalNotRestoredWhenAMemberHasNoSavedDecision() {
        let fixture = makeFixture()
        let saved = snapshot(
            decisions: [DeduplicateSavedDecision(path: "/lib/a1.jpg", identity: identity("a1"), decision: .keep)],
            approvals: [DeduplicateSavedGroupApproval(groupKey: key(["a1", "a2"]), memberCount: 2)]
        )

        let result = restore(saved, fixture)

        XCTAssertTrue(result.approvedClusterIDs.isEmpty)
        XCTAssertEqual(result.restoredGroupCount, 0)
        XCTAssertEqual(result.changedGroupCount, 1)
    }

    func testFocusMapsToMatchingCluster() {
        let fixture = makeFixture()

        let matched = restore(snapshot(focus: key(["b1", "b2"])), fixture)
        XCTAssertEqual(matched.focusClusterID, fixture.clusterB.id)

        let unmatched = restore(snapshot(focus: key(["z1", "z2"])), fixture)
        XCTAssertNil(unmatched.focusClusterID)

        let none = restore(snapshot(focus: nil), fixture)
        XCTAssertNil(none.focusClusterID)
    }

    func testSettingsChangedFlag() {
        let fixture = makeFixture()
        let same = restore(snapshot(), fixture)
        XCTAssertFalse(same.settingsChanged)

        let differs = restore(snapshot(fingerprint: "another-fingerprint"), fixture)
        XCTAssertTrue(differs.settingsChanged)
    }

    func testCaptureOmitsDecisionsWithoutIdentity() {
        let fixture = makeFixture()
        var decisions = fixture.suggested
        decisions.byPath["/lib/unknown.jpg"] = .delete

        let captured = DeduplicateReviewRestorer.capture(
            folderPath: "/lib",
            savedAt: savedAt,
            configuration: configuration,
            decisions: decisions,
            approvedClusterIDs: [],
            clusters: fixture.clusters,
            scanSnapshot: fixture.scan,
            focusClusterID: nil
        )

        XCTAssertEqual(captured.decisions.count, 4)
        XCTAssertFalse(captured.decisions.contains { $0.path == "/lib/unknown.jpg" })
        XCTAssertEqual(captured.folderPath, "/lib")
        XCTAssertEqual(captured.savedAt, savedAt)
        XCTAssertEqual(captured.configurationFingerprint, configuration.reviewFingerprint)
        XCTAssertEqual(captured.version, DeduplicateReviewSnapshot.version)
    }

    func testCaptureThenRestoreIsIdentityOnUnchangedScan() {
        let fixture = makeFixture()
        var live = fixture.suggested
        live.byPath["/lib/a2.jpg"] = .keep
        let captured = DeduplicateReviewRestorer.capture(
            folderPath: "/lib",
            savedAt: savedAt,
            configuration: configuration,
            decisions: live,
            approvedClusterIDs: [fixture.clusterA.id],
            clusters: fixture.clusters,
            scanSnapshot: fixture.scan,
            focusClusterID: fixture.clusterA.id
        )
        XCTAssertEqual(captured.approvals, [DeduplicateSavedGroupApproval(groupKey: key(["a1", "a2"]), memberCount: 2)])
        XCTAssertEqual(captured.focusGroupKey, key(["a1", "a2"]))

        // A fresh scan of unchanged content: same members, new cluster UUIDs.
        let rescanA = cluster(["/lib/a1.jpg", "/lib/a2.jpg"])
        let rescanB = cluster(["/lib/b1.jpg", "/lib/b2.jpg"])
        let result = DeduplicateReviewRestorer.restore(
            snapshot: captured,
            clusters: [rescanA, rescanB],
            scanSnapshot: fixture.scan,
            suggested: fixture.suggested,
            currentFingerprint: configuration.reviewFingerprint
        )

        XCTAssertEqual(result.decisions, live)
        XCTAssertEqual(result.approvedClusterIDs, [rescanA.id])
        XCTAssertEqual(result.focusClusterID, rescanA.id)
        XCTAssertEqual(result.restoredDecisionCount, 2, "counts cover the reviewed group only (C-10)")
        XCTAssertEqual(result.droppedDecisionCount, 0)
        XCTAssertEqual(result.restoredGroupCount, 1)
        XCTAssertEqual(result.changedGroupCount, 0)
        XCTAssertFalse(result.settingsChanged)
    }

    // AGENTS-INVARIANT: 12
    func testRestoreNeverSetsHardDelete() {
        var fixture = makeFixture()
        fixture.suggested.hardDelete = true
        fixture.suggested.pairKeepOverrides = ["/lib/partner.mov"]
        let saved = snapshot(
            decisions: [DeduplicateSavedDecision(path: "/lib/a2.jpg", identity: identity("a2"), decision: .delete)]
        )

        let result = restore(saved, fixture)

        XCTAssertFalse(result.decisions.hardDelete)
        XCTAssertEqual(result.decisions.pairKeepOverrides, ["/lib/partner.mov"])
        XCTAssertFalse(String(decoding: (try? JSONEncoder().encode(saved)) ?? Data(), as: UTF8.self).contains("hardDelete"))
    }

    private func captureWithClusterAReviewed(_ fixture: Fixture) -> DeduplicateReviewSnapshot {
        DeduplicateReviewRestorer.capture(
            folderPath: "/lib",
            savedAt: savedAt,
            configuration: configuration,
            decisions: fixture.suggested,
            approvedClusterIDs: [fixture.clusterA.id],
            clusters: fixture.clusters,
            scanSnapshot: fixture.scan,
            focusClusterID: nil
        )
    }

    func testCaptureMarksOnlyDecisionsInReviewedGroups() {
        let fixture = makeFixture()

        let captured = captureWithClusterAReviewed(fixture)

        XCTAssertEqual(captured.decisions.count, 4, "every decision is still saved")
        let reviewedByPath = Dictionary(uniqueKeysWithValues: captured.decisions.map { ($0.path, $0.inReviewedGroup) })
        XCTAssertEqual(reviewedByPath, [
            "/lib/a1.jpg": true, "/lib/a2.jpg": true,
            "/lib/b1.jpg": false, "/lib/b2.jpg": false,
        ])
        XCTAssertEqual(captured.reviewedDecisionCount, 2)
    }

    func testRestoredAndDroppedCountsIgnoreUnreviewedGroups() {
        var fixture = makeFixture()
        var saved = captureWithClusterAReviewed(fixture)
        // Change one file in each group since the save.
        var identities = fixture.scan.identitiesByPath
        identities["/lib/a2.jpg"] = identity("a2-edited")
        identities["/lib/b2.jpg"] = identity("b2-edited")
        fixture.scan = DeduplicateScanSnapshot(identitiesByPath: identities)
        saved = DeduplicateReviewSnapshot(
            folderPath: saved.folderPath, savedAt: saved.savedAt,
            configurationFingerprint: saved.configurationFingerprint,
            decisions: saved.decisions.map {
                DeduplicateSavedDecision(path: $0.path, identity: $0.identity, decision: .keep, inReviewedGroup: $0.inReviewedGroup)
            },
            approvals: saved.approvals, focusGroupKey: nil
        )

        let result = restore(saved, fixture)

        XCTAssertEqual(result.restoredDecisionCount, 1, "only a1 of the reviewed group")
        XCTAssertEqual(result.droppedDecisionCount, 1, "only a2 of the reviewed group")
        XCTAssertEqual(result.decisions.byPath["/lib/a1.jpg"], .keep)
        XCTAssertEqual(result.decisions.byPath["/lib/b1.jpg"], .keep)
        XCTAssertEqual(result.decisions.byPath["/lib/a2.jpg"], fixture.suggested.byPath["/lib/a2.jpg"])
        XCTAssertEqual(result.decisions.byPath["/lib/b2.jpg"], fixture.suggested.byPath["/lib/b2.jpg"])
    }

    func testUnreviewedDecisionsAreStillRestored() {
        let fixture = makeFixture()
        let saved = snapshot(decisions: [
            DeduplicateSavedDecision(path: "/lib/a1.jpg", identity: identity("a1"), decision: .delete, inReviewedGroup: false),
            DeduplicateSavedDecision(path: "/lib/a2.jpg", identity: identity("a2"), decision: .keep, inReviewedGroup: false),
            DeduplicateSavedDecision(path: "/lib/b1.jpg", identity: identity("b1"), decision: .delete, inReviewedGroup: false),
            DeduplicateSavedDecision(path: "/lib/b2.jpg", identity: identity("b2"), decision: .keep, inReviewedGroup: false),
        ])

        let result = restore(saved, fixture)

        XCTAssertEqual(result.decisions.byPath, [
            "/lib/a1.jpg": .delete, "/lib/a2.jpg": .keep,
            "/lib/b1.jpg": .delete, "/lib/b2.jpg": .keep,
        ])
        XCTAssertEqual(result.restoredDecisionCount, 0)
        XCTAssertEqual(result.droppedDecisionCount, 0)
        XCTAssertTrue(result.approvedClusterIDs.isEmpty)
    }
}
