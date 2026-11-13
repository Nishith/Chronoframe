import Foundation

public struct DeduplicateReviewRestoration: Equatable, Sendable {
    public let decisions: DedupeDecisions           // suggested decisions overlaid with restored ones
    public let approvedClusterIDs: Set<UUID>
    public let focusClusterID: UUID?
    public let restoredDecisionCount: Int
    public let droppedDecisionCount: Int            // path missing from scan, or identity differs
    public let restoredGroupCount: Int
    public let changedGroupCount: Int               // saved approval whose groupKey no longer matches any cluster
    public let settingsChanged: Bool                // fingerprint differs
    public let savedAt: Date
}

public enum DeduplicateReviewRestorer {
    /// Rules:
    /// 1. Start from `suggested` (the store's suggestedDecisions(for:)).
    /// 2. For each saved decision: if `snapshot.identitiesByPath[path] == identity` and the path is a member of some cluster → set byPath[path] = decision, restored += 1; else dropped += 1.
    /// 3. For each cluster: key = groupKey(for:snapshot:); if key != nil and approvals contains key with the same memberCount → approvedClusterIDs.insert(cluster.id), restoredGroup += 1.
    ///    changedGroupCount = approvals.count − restoredGroupCount.
    /// 4. A cluster is approved only if every member that had a saved decision was restored; if any member's decision was dropped, the cluster is NOT approved (it needs another look) even if its key matched. (Keys are identity-based so this can only happen with duplicate paths; implement it anyway.)
    ///    Also (D-DDP-101): every member path of the cluster must have a restored saved decision, so a renamed or moved member cannot ride on a matching key.
    /// 5. focusClusterID = the cluster whose key == focusGroupKey, else nil.
    /// 6. `hardDelete` stays false; `pairKeepOverrides` stays as in `suggested`.
    public static func restore(
        snapshot saved: DeduplicateReviewSnapshot,
        clusters: [DuplicateCluster],
        scanSnapshot: DeduplicateScanSnapshot,
        suggested: DedupeDecisions,
        currentFingerprint: String
    ) -> DeduplicateReviewRestoration {
        let memberPaths = Set(clusters.flatMap { $0.members.map(\.path) })

        var byPath = suggested.byPath
        var restoredDecisionCount = 0
        var droppedDecisionCount = 0
        var droppedPaths: Set<String> = []
        var restoredPaths: Set<String> = []
        for savedDecision in saved.decisions {
            if scanSnapshot.identitiesByPath[savedDecision.path] == savedDecision.identity,
               memberPaths.contains(savedDecision.path) {
                byPath[savedDecision.path] = savedDecision.decision
                restoredPaths.insert(savedDecision.path)
                if savedDecision.inReviewedGroup { restoredDecisionCount += 1 }
            } else {
                if savedDecision.inReviewedGroup { droppedDecisionCount += 1 }
                droppedPaths.insert(savedDecision.path)
            }
        }

        var approvalCountsByKey: [String: Set<Int>] = [:]
        for approval in saved.approvals {
            approvalCountsByKey[approval.groupKey, default: []].insert(approval.memberCount)
        }

        var approvedClusterIDs: Set<UUID> = []
        var focusClusterID: UUID?
        for cluster in clusters {
            guard let key = DeduplicateReviewKeys.groupKey(for: cluster, snapshot: scanSnapshot) else { continue }
            if let focusKey = saved.focusGroupKey, focusClusterID == nil, key == focusKey {
                focusClusterID = cluster.id
            }
            guard approvalCountsByKey[key]?.contains(cluster.members.count) == true else { continue }
            guard !cluster.members.contains(where: { droppedPaths.contains($0.path) }) else { continue }
            // Identity is content-only, so a matching key says nothing about paths: every
            // member must also carry a restored saved decision for its own path.
            guard cluster.members.allSatisfy({ restoredPaths.contains($0.path) }) else { continue }
            approvedClusterIDs.insert(cluster.id)
        }

        return DeduplicateReviewRestoration(
            decisions: DedupeDecisions(byPath: byPath, pairKeepOverrides: suggested.pairKeepOverrides),
            approvedClusterIDs: approvedClusterIDs,
            focusClusterID: focusClusterID,
            restoredDecisionCount: restoredDecisionCount,
            droppedDecisionCount: droppedDecisionCount,
            restoredGroupCount: approvedClusterIDs.count,
            changedGroupCount: max(0, saved.approvals.count - approvedClusterIDs.count),
            settingsChanged: saved.configurationFingerprint != currentFingerprint,
            savedAt: saved.savedAt
        )
    }

    /// Inverse: build a snapshot from live state. Decisions without an identity in the scan snapshot are omitted (they could never be restored).
    public static func capture(
        folderPath: String,
        savedAt: Date,
        configuration: DeduplicateConfiguration,
        decisions: DedupeDecisions,
        approvedClusterIDs: Set<UUID>,
        clusters: [DuplicateCluster],
        scanSnapshot: DeduplicateScanSnapshot,
        focusClusterID: UUID?
    ) -> DeduplicateReviewSnapshot {
        let reviewedPaths = Set(
            clusters.filter { approvedClusterIDs.contains($0.id) }.flatMap { $0.members.map(\.path) }
        )
        let savedDecisions: [DeduplicateSavedDecision] = decisions.byPath
            .sorted { $0.key < $1.key }
            .compactMap { path, decision in
                guard let identity = scanSnapshot.identitiesByPath[path] else { return nil }
                return DeduplicateSavedDecision(
                    path: path,
                    identity: identity,
                    decision: decision,
                    inReviewedGroup: reviewedPaths.contains(path)
                )
            }

        var approvals: [DeduplicateSavedGroupApproval] = []
        var focusGroupKey: String?
        for cluster in clusters {
            guard let key = DeduplicateReviewKeys.groupKey(for: cluster, snapshot: scanSnapshot) else { continue }
            if approvedClusterIDs.contains(cluster.id) {
                approvals.append(DeduplicateSavedGroupApproval(groupKey: key, memberCount: cluster.members.count))
            }
            if cluster.id == focusClusterID {
                focusGroupKey = key
            }
        }

        return DeduplicateReviewSnapshot(
            folderPath: URL(fileURLWithPath: folderPath).standardizedFileURL.path,
            savedAt: savedAt,
            configurationFingerprint: configuration.reviewFingerprint,
            decisions: savedDecisions,
            approvals: approvals,
            focusGroupKey: focusGroupKey
        )
    }
}
