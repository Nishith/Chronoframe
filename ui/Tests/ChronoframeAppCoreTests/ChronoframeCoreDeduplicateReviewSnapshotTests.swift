import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreDeduplicateReviewSnapshotTests: XCTestCase {
    private func identity(_ name: String, size: Int64 = 100) -> FileIdentity {
        FileIdentity(size: size, digest: "digest-\(name)")
    }

    private func candidate(_ path: String) -> PhotoCandidate {
        PhotoCandidate(path: path, size: 100, modificationTime: 1)
    }

    func testGroupKeyIsOrderIndependent() {
        let a = identity("a")
        let b = identity("b", size: 7)
        let c = identity("c", size: 50_000)

        let forward = DeduplicateReviewKeys.groupKey(memberIdentities: [a, b, c])
        let shuffled = DeduplicateReviewKeys.groupKey(memberIdentities: [c, a, b])

        XCTAssertEqual(forward, shuffled)
        XCTAssertEqual(forward, [a, b, c].map(\.rawValue).sorted().joined(separator: "\n"))
        XCTAssertNotEqual(forward, DeduplicateReviewKeys.groupKey(memberIdentities: [a, b]))
    }

    func testGroupKeyIsNilWhenAMemberLacksIdentity() {
        let cluster = DuplicateCluster(
            kind: .exactDuplicate,
            members: [candidate("/lib/a.jpg"), candidate("/lib/b.jpg")],
            suggestedKeeperIDs: ["/lib/a.jpg"],
            bytesIfPruned: 100
        )
        let complete = DeduplicateScanSnapshot(identitiesByPath: [
            "/lib/a.jpg": identity("a"),
            "/lib/b.jpg": identity("b"),
        ])
        let partial = DeduplicateScanSnapshot(identitiesByPath: ["/lib/a.jpg": identity("a")])

        XCTAssertEqual(
            DeduplicateReviewKeys.groupKey(for: cluster, snapshot: complete),
            DeduplicateReviewKeys.groupKey(memberIdentities: [identity("a"), identity("b")])
        )
        XCTAssertNil(DeduplicateReviewKeys.groupKey(for: cluster, snapshot: partial))
    }

    func testFolderKeyIsStableAcrossTrailingSlashAndDotSegments() {
        let canonical = DeduplicateReviewKeys.folderKey(for: "/Users/example/Photos")

        XCTAssertEqual(canonical, DeduplicateReviewKeys.folderKey(for: "/Users/example/Photos/"))
        XCTAssertEqual(canonical, DeduplicateReviewKeys.folderKey(for: "/Users/example/./Photos"))
        XCTAssertEqual(canonical, DeduplicateReviewKeys.folderKey(for: "/Users/example/Other/../Photos"))
        XCTAssertNotEqual(canonical, DeduplicateReviewKeys.folderKey(for: "/Users/example/Photos2"))

        // base64url of the standardized path, no padding, filename-safe.
        let expected = Data("/Users/example/Photos".utf8).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        XCTAssertEqual(canonical, expected)
        XCTAssertFalse(canonical.contains("/"))
        XCTAssertFalse(canonical.contains("+"))
        XCTAssertFalse(canonical.contains("="))
    }

    func testFingerprintIgnoresWorkerCountAndChangesWithThreshold() {
        let base = DeduplicateConfiguration(destinationPath: "/lib", similarityThreshold: 0.35, workerCount: 2)
        var moreWorkers = base
        moreWorkers.workerCount = 16
        var stricter = base
        stricter.similarityThreshold = 0.20
        var burstOff = base
        burstOff.burstModeEnabled = false
        var withSource = base
        withSource.additionalSources = [CrossFolderSource(path: "/other", priority: 1, label: "Other")]
        var videoTuned = base
        videoTuned.videoPerceptualMatchConfiguration.frameHammingThreshold = 3

        XCTAssertEqual(base.reviewFingerprint, moreWorkers.reviewFingerprint)
        XCTAssertNotEqual(base.reviewFingerprint, stricter.reviewFingerprint)
        XCTAssertNotEqual(base.reviewFingerprint, burstOff.reviewFingerprint)
        XCTAssertNotEqual(base.reviewFingerprint, withSource.reviewFingerprint)
        XCTAssertNotEqual(base.reviewFingerprint, videoTuned.reviewFingerprint)

        // SHA-256 hex, deterministic.
        XCTAssertEqual(base.reviewFingerprint.count, 64)
        XCTAssertTrue(base.reviewFingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase })
        XCTAssertEqual(base.reviewFingerprint, DeduplicateConfiguration(destinationPath: "/lib", workerCount: 9).reviewFingerprint)
    }

    func testSnapshotRoundTripsThroughJSON() throws {
        let snapshot = DeduplicateReviewSnapshot(
            folderPath: "/Users/example/Photos",
            savedAt: Date(timeIntervalSince1970: 1_700_000_123.5),
            configurationFingerprint: "abc123",
            decisions: [
                DeduplicateSavedDecision(path: "/lib/a.jpg", identity: identity("a"), decision: .keep),
                DeduplicateSavedDecision(path: "/lib/b.jpg", identity: identity("b"), decision: .delete),
            ],
            approvals: [DeduplicateSavedGroupApproval(groupKey: "k", memberCount: 2)],
            focusGroupKey: "k"
        )

        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(DeduplicateReviewSnapshot.self, from: data)

        XCTAssertEqual(decoded, snapshot)
        XCTAssertEqual(decoded.version, DeduplicateReviewSnapshot.version)
        XCTAssertEqual(DeduplicateReviewSnapshot.version, 1)
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("hardDelete"))
    }

    func testEmptySnapshotIsEmpty() {
        func make(decisions: [DeduplicateSavedDecision], approvals: [DeduplicateSavedGroupApproval], focus: String?) -> DeduplicateReviewSnapshot {
            DeduplicateReviewSnapshot(
                folderPath: "/lib", savedAt: Date(timeIntervalSince1970: 0),
                configurationFingerprint: "f", decisions: decisions, approvals: approvals, focusGroupKey: focus
            )
        }

        XCTAssertTrue(make(decisions: [], approvals: [], focus: nil).isEmpty)
        // Focus alone is not worth saving.
        XCTAssertTrue(make(decisions: [], approvals: [], focus: "k").isEmpty)
        XCTAssertFalse(make(
            decisions: [DeduplicateSavedDecision(path: "/lib/a.jpg", identity: identity("a"), decision: .delete)],
            approvals: [], focus: nil
        ).isEmpty)
        XCTAssertFalse(make(
            decisions: [], approvals: [DeduplicateSavedGroupApproval(groupKey: "k", memberCount: 2)], focus: nil
        ).isEmpty)
    }
}
