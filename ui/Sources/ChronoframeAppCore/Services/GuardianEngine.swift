#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Guardian engine seam (Phase 4)
//
// `GuardianEngine` is the AppCore boundary between the Guardian store/UI and the
// pure `ChronoframeCore` engine (probe → classifier → planners → executors). It
// is deliberately not `@MainActor`: its methods do heavy filesystem I/O and hash
// work, so they run off the main actor and the store awaits them. `SwiftGuardianEngine`
// is the concrete implementation; `MockGuardianEngine` (in the test target) is the
// double.
//
// Two small protocols keep AppCore free of any dependency on the App target while
// still letting the App own security-scoped bookmarks and user notifications:
// `GuardianBookmarkResolving` and `GuardianNotifying` are implemented in
// `ChronoframeApp`.

/// The result of one integrity scan: the immutable report plus the identity it was
/// run against.
public struct GuardianScanOutcome: Equatable, Sendable {
    public let report: GuardianIntegrityReport
    public let libraryIdentity: GuardianLibraryIdentity

    public init(report: GuardianIntegrityReport, libraryIdentity: GuardianLibraryIdentity) {
        self.report = report
        self.libraryIdentity = libraryIdentity
    }
}

public enum GuardianEngineError: LocalizedError {
    /// A pinned root no longer resolves to the volume/path the context recorded, so
    /// the run was cancelled rather than retargeted.
    case rootRetargeted(String)
    /// The mirror volume is not currently available.
    case mirrorOffline
    case io(String)

    public var errorDescription: String? {
        switch self {
        case .rootRetargeted:
            return "The library or mirror folder changed since this action started, so Chronoframe stopped to avoid working on the wrong folder. Nothing was changed."
        case .mirrorOffline:
            return "The mirror drive isn't connected right now. Reconnect it and try again. Nothing was changed."
        case let .io(message):
            return UserFacingErrorMessage.withDetails(
                "Chronoframe couldn't complete the Guardian operation. Your files were not changed.",
                details: message
            )
        }
    }
}

/// Resolve Guardian's security-scoped bookmarks. Implemented in the App target so
/// AppCore never depends on `ChronoframeApp`.
public protocol GuardianBookmarkResolving: Sendable {
    /// Resolve a stored bookmark to a URL and start accessing it. Returns nil if it
    /// no longer resolves (drive detached, folder deleted, permission lost).
    func resolveAndBeginAccess(_ bookmark: FolderBookmark) -> URL?
    /// Balance a successful `resolveAndBeginAccess`.
    func endAccess(_ url: URL)
}

/// Deliver Guardian's user-facing notifications (e.g. bit rot found). Implemented
/// in the App target, which already conforms to `UNUserNotificationCenterDelegate`.
public protocol GuardianNotifying: Sendable {
    func notifyBitRotDetected(libraryName: String, corruptCount: Int)
}

public protocol GuardianEngine: Sendable {
    /// Read-only integrity scan: probe the library, classify against the manifest,
    /// and persist scan-driven manifest upserts (new files → `unprotected`, still-
    /// matching trusted files refreshed, changed trusted files demoted to
    /// `changedPendingReview`). Never advances trust and never writes the library.
    func scan(
        libraryURL: URL,
        libraryIdentity: GuardianLibraryIdentity,
        isCancelled: @escaping @Sendable () -> Bool
    ) async throws -> GuardianScanOutcome

    /// Explicit user acceptance: promote the given paths to `trusted`, recording the
    /// currently observed identity as the new known-good baseline.
    func acceptTrust(
        relativePaths: Set<String>,
        report: GuardianIntegrityReport,
        libraryIdentity: GuardianLibraryIdentity
    ) async throws

    /// Acknowledge intentional deletions: mark the given missing paths `retired`.
    func acknowledgeDeletions(
        relativePaths: Set<String>,
        report: GuardianIntegrityReport,
        libraryIdentity: GuardianLibraryIdentity
    ) async throws

    /// Build a verified-mirror plan from the latest library report and a fresh probe
    /// of the mirror. Copies only from currently-verified primaries; never deletes.
    func planMirror(
        context: GuardianMirrorContext,
        libraryReport: GuardianIntegrityReport
    ) async throws -> GuardianMirrorPlan

    /// Execute a verified-mirror plan. Writes only the mirror; the library is read.
    func runMirror(
        context: GuardianMirrorContext,
        plan: GuardianMirrorPlan
    ) async throws -> GuardianMirrorExecutionResult

    /// Build a verified-restore plan: a corrupt/missing primary is restorable only
    /// if the mirror copy still hashes to the trusted digest.
    func planRestore(
        libraryURL: URL,
        mirrorURL: URL,
        libraryReport: GuardianIntegrityReport
    ) async throws -> GuardianRestorePlan

    /// Execute a verified-restore run. Overwrites the library only from a mirror copy
    /// that re-verifies against the trusted digest at commit time.
    func runRestore(context: GuardianRestoreContext) async throws -> GuardianRestoreExecutionResult
}
