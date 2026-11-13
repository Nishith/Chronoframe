import CryptoKit
import Foundation

public struct DeduplicateSavedDecision: Equatable, Codable, Sendable {
    public let path: String
    public let identity: FileIdentity        // content at the time of the decision
    public let decision: DedupeDecision
    /// The path belonged to a group marked reviewed when the save was captured. Only these count as the user's choices.
    public let inReviewedGroup: Bool

    public init(path: String, identity: FileIdentity, decision: DedupeDecision, inReviewedGroup: Bool = true) {
        self.path = path
        self.identity = identity
        self.decision = decision
        self.inReviewedGroup = inReviewedGroup
    }

    private enum CodingKeys: String, CodingKey {
        case path, identity, decision, inReviewedGroup
    }

    /// A value saved before the flag existed decodes as reviewed (the earlier counting behaviour).
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        path = try container.decode(String.self, forKey: .path)
        identity = try container.decode(FileIdentity.self, forKey: .identity)
        decision = try container.decode(DedupeDecision.self, forKey: .decision)
        inReviewedGroup = try container.decodeIfPresent(Bool.self, forKey: .inReviewedGroup) ?? true
    }
}

/// A reviewed group, keyed by the sorted member identities so it survives new cluster UUIDs.
public struct DeduplicateSavedGroupApproval: Equatable, Codable, Sendable {
    public let groupKey: String              // DeduplicateReviewKeys.groupKey(memberIdentities:)
    public let memberCount: Int

    public init(groupKey: String, memberCount: Int) {
        self.groupKey = groupKey
        self.memberCount = memberCount
    }
}

public struct DeduplicateReviewSnapshot: Equatable, Codable, Sendable {
    public static let version = 1

    public let version: Int
    public let folderPath: String            // standardized path of the dedupe root
    public let savedAt: Date
    public let configurationFingerprint: String   // DeduplicateConfiguration.reviewFingerprint
    public let decisions: [DeduplicateSavedDecision]
    public let approvals: [DeduplicateSavedGroupApproval]
    public let focusGroupKey: String?        // where the user was

    public init(
        folderPath: String,
        savedAt: Date,
        configurationFingerprint: String,
        decisions: [DeduplicateSavedDecision],
        approvals: [DeduplicateSavedGroupApproval],
        focusGroupKey: String?
    ) {
        self.version = Self.version
        self.folderPath = folderPath
        self.savedAt = savedAt
        self.configurationFingerprint = configurationFingerprint
        self.decisions = decisions
        self.approvals = approvals
        self.focusGroupKey = focusGroupKey
    }

    /// Nothing the user did: no approvals and no decision in a reviewed group. Untouched suggestions
    /// captured alongside do not make a review worth saving (D-DDP-123).
    public var isEmpty: Bool { approvals.isEmpty && !decisions.contains(where: \.inReviewedGroup) }

    /// Saved decisions whose group was marked reviewed; the count shown to the user.
    public var reviewedDecisionCount: Int { decisions.filter(\.inReviewedGroup).count }
}

public enum DeduplicateReviewKeys {
    /// Sorted `FileIdentity.rawValue`s joined by "\n". Deterministic for any member order.
    public static func groupKey(memberIdentities: [FileIdentity]) -> String {
        memberIdentities.map(\.rawValue).sorted().joined(separator: "\n")
    }

    /// nil when any member lacks an identity in the snapshot (such a group can never be approved from a save).
    public static func groupKey(for cluster: DuplicateCluster, snapshot: DeduplicateScanSnapshot) -> String? {
        guard !cluster.members.isEmpty else { return nil }
        var identities: [FileIdentity] = []
        identities.reserveCapacity(cluster.members.count)
        for member in cluster.members {
            guard let identity = snapshot.identitiesByPath[member.path] else { return nil }
            identities.append(identity)
        }
        return groupKey(memberIdentities: identities)
    }

    /// SHA-256 hex of the standardized dedupe root path, the key for the on-disk file (see C-03).
    /// Fixed length, so a deeply nested folder never exceeds the filename limit.
    public static func folderKey(for folderPath: String) -> String {
        let standardized = URL(fileURLWithPath: folderPath).standardizedFileURL.path
        return SHA256.hash(data: Data(standardized.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public extension DeduplicateConfiguration {
    /// Stable text of every field except `workerCount`, joined by "|" in declaration order; SHA-256 hex via CryptoKit.
    var reviewFingerprint: String {
        let sources = additionalSources
            .map { "\($0.path)\u{1F}\($0.priority)\u{1F}\($0.label ?? "")" }
            .joined(separator: "\u{1E}")
        let video = videoPerceptualMatchConfiguration
        let fields: [String] = [
            destinationPath,
            String(timeWindowSeconds),
            String(burstModeEnabled),
            String(similarityThreshold),
            String(dhashHammingThreshold),
            String(treatRawJpegPairsAsUnit),
            String(treatLivePhotoPairsAsUnit),
            String(enableExactDuplicateGroup),
            String(autoAcceptHighConfidence),
            String(detectEditVariants),
            sources,
            String(perceptualVideoMatchingEnabled),
            String(video.durationToleranceSeconds),
            String(video.frameHammingThreshold),
            String(video.aggregateMedianThreshold),
            String(video.aspectRatioTolerance),
        ]
        let digest = SHA256.hash(data: Data(fields.joined(separator: "|").utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
