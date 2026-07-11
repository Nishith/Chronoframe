import Foundation

// MARK: - Guardian verified-restore models (Phase 3)
//
// Restore heals a corrupt or missing library file from the mirror. The single
// safety rule the plan encodes: a file is restore-eligible ONLY if the mirror copy
// still hashes to the trusted digest. Corrupt-on-both-sides is never "restored"
// from bad bytes — it is reported and left alone. Every restorable action carries
// the trusted identity the restored file must end up matching, and (for a corrupt
// primary) the identity the primary is expected to still have, so the executor can
// fail closed against filesystem races at commit time.

public enum GuardianRestoreReason: String, Codable, Sendable {
    /// The primary is present but its bytes no longer match the trusted digest.
    case primaryCorrupt
    /// The primary is absent.
    case primaryMissing
}

public struct GuardianRestoreAction: Equatable, Codable, Sendable {
    public var relativePath: String
    /// The trusted identity the restored file must hash to (from the manifest).
    public var trustedIdentity: FileIdentity
    public var reason: GuardianRestoreReason
    /// For `primaryCorrupt`: the identity the primary currently has, so the executor
    /// can refuse to overwrite a primary that changed again since planning.
    public var expectedCurrentPrimaryIdentity: FileIdentity?

    public init(
        relativePath: String,
        trustedIdentity: FileIdentity,
        reason: GuardianRestoreReason,
        expectedCurrentPrimaryIdentity: FileIdentity? = nil
    ) {
        self.relativePath = relativePath
        self.trustedIdentity = trustedIdentity
        self.reason = reason
        self.expectedCurrentPrimaryIdentity = expectedCurrentPrimaryIdentity
    }
}

public enum GuardianRestoreBlockReason: String, Codable, Sendable {
    /// No mirror copy exists for this path.
    case mirrorMissing
    /// The mirror copy could not be read to compare it.
    case mirrorUnreadable
    /// The mirror copy exists but does not match the trusted digest (corrupt on both).
    case mirrorDivergent
    /// The manifest has no trusted baseline to restore to.
    case noTrustedBaseline
}

public struct GuardianRestoreBlock: Equatable, Codable, Sendable {
    public var relativePath: String
    public var reason: GuardianRestoreBlockReason

    public init(relativePath: String, reason: GuardianRestoreBlockReason) {
        self.relativePath = relativePath
        self.reason = reason
    }
}

/// Immutable restore plan. `restorable` are the only files the executor may heal;
/// `blocked` are reported and never touched.
public struct GuardianRestorePlan: Equatable, Codable, Sendable {
    public var libraryRoot: String
    public var mirrorRoot: String
    public var restorable: [GuardianRestoreAction]
    public var blocked: [GuardianRestoreBlock]

    public init(
        libraryRoot: String,
        mirrorRoot: String,
        restorable: [GuardianRestoreAction],
        blocked: [GuardianRestoreBlock]
    ) {
        self.libraryRoot = libraryRoot
        self.mirrorRoot = mirrorRoot
        self.restorable = restorable
        self.blocked = blocked
    }

    public var isEmpty: Bool { restorable.isEmpty }
}
