import Foundation

// MARK: - Guardian mirror models (Phase 2)
//
// A verified mirror is an incrementally maintained, bit-for-bit second copy of the
// library on another volume. `GuardianMirrorPlanner` is the single source of truth
// for what the executor will write, and every mutation carries the expected trusted
// identity so the executor can fail closed.
//
// Two rules the plan encodes:
//   * copy only FROM a currently-verified primary — an unverified/corrupt/missing
//     library file never overwrites its mirror copy;
//   * never propagate a deletion — a mirror file with no verified library
//     counterpart is retained, not removed.

public enum GuardianMirrorActionKind: String, Codable, Sendable {
    /// No mirror copy exists yet.
    case create
    /// A mirror copy exists but does not match the trusted digest; it is quarantined
    /// (not erased) before a fresh verified copy is written.
    case replaceDivergent
}

/// One file to copy into the mirror, with the trusted identity to verify against.
public struct GuardianMirrorCopy: Equatable, Codable, Sendable {
    public var relativePath: String
    /// The trusted (library-side) identity the mirror copy must end up matching.
    public var expectedIdentity: FileIdentity
    public var kind: GuardianMirrorActionKind
    /// For `replaceDivergent`: the identity of the mirror copy being quarantined.
    public var divergentMirrorIdentity: FileIdentity?

    public init(
        relativePath: String,
        expectedIdentity: FileIdentity,
        kind: GuardianMirrorActionKind,
        divergentMirrorIdentity: FileIdentity? = nil
    ) {
        self.relativePath = relativePath
        self.expectedIdentity = expectedIdentity
        self.kind = kind
        self.divergentMirrorIdentity = divergentMirrorIdentity
    }
}

public enum GuardianMirrorBlockReason: String, Codable, Sendable {
    /// The library file is not currently trusted-and-matching, so it must not be
    /// copied over the mirror.
    case primaryNotVerified
    /// The library file is gone; the mirror copy is retained, not deleted.
    case primaryMissing
    /// The existing mirror copy could not be read to compare it, so it is left alone.
    case mirrorUnreadable
}

public struct GuardianMirrorBlock: Equatable, Codable, Sendable {
    public var relativePath: String
    public var reason: GuardianMirrorBlockReason

    public init(relativePath: String, reason: GuardianMirrorBlockReason) {
        self.relativePath = relativePath
        self.reason = reason
    }
}

/// Immutable mirror plan. `copies` are the only mutations; everything else is
/// preserved (blocked items keep their existing mirror copy, extras are retained).
public struct GuardianMirrorPlan: Equatable, Codable, Sendable {
    public var libraryRoot: String
    public var mirrorRoot: String
    public var copies: [GuardianMirrorCopy]
    public var blocked: [GuardianMirrorBlock]
    /// Present in the mirror with no verified library counterpart — retained.
    public var retainedExtras: [String]
    /// Already matches the trusted digest in the mirror — no action.
    public var alreadyMirrored: [String]

    public init(
        libraryRoot: String,
        mirrorRoot: String,
        copies: [GuardianMirrorCopy],
        blocked: [GuardianMirrorBlock],
        retainedExtras: [String],
        alreadyMirrored: [String]
    ) {
        self.libraryRoot = libraryRoot
        self.mirrorRoot = mirrorRoot
        self.copies = copies
        self.blocked = blocked
        self.retainedExtras = retainedExtras
        self.alreadyMirrored = alreadyMirrored
    }

    public var isEmpty: Bool { copies.isEmpty }
}
