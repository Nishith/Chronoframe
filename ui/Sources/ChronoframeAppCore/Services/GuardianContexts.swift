#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Guardian action contexts (Phase 4)
//
// Mirror and restore both touch two roots (the library and the mirror). A
// scheduled or manual action pins BOTH roots — resolved URL, security-scoped
// bookmark, and the library identity — at the moment the user (or the scheduler)
// initiates it, mirroring the `WatchedImportContext` pattern. The engine builds
// its run entirely from the context, so a run in flight can never be retargeted
// by a later preference/bookmark change; if the pinned roots no longer resolve to
// what the context recorded, the run is cancelled rather than redirected.

/// Everything a verified-mirror run needs, pinned at action time.
public struct GuardianMirrorContext: Equatable, Sendable {
    public let libraryIdentity: GuardianLibraryIdentity
    public let libraryURL: URL
    public let libraryBookmark: FolderBookmark
    public let mirrorURL: URL
    public let mirrorBookmark: FolderBookmark

    public init(
        libraryIdentity: GuardianLibraryIdentity,
        libraryURL: URL,
        libraryBookmark: FolderBookmark,
        mirrorURL: URL,
        mirrorBookmark: FolderBookmark
    ) {
        self.libraryIdentity = libraryIdentity
        self.libraryURL = libraryURL
        self.libraryBookmark = libraryBookmark
        self.mirrorURL = mirrorURL
        self.mirrorBookmark = mirrorBookmark
    }
}

/// Everything a verified-restore run needs, pinned at action time. The plan is an
/// immutable snapshot; `selectedPaths` is the review-gated subset the user chose
/// to heal — the executor touches nothing outside it.
public struct GuardianRestoreContext: Equatable, Sendable {
    public let libraryIdentity: GuardianLibraryIdentity
    public let libraryURL: URL
    public let libraryBookmark: FolderBookmark
    public let mirrorURL: URL
    public let mirrorBookmark: FolderBookmark
    public let plan: GuardianRestorePlan
    public let selectedPaths: Set<String>

    public init(
        libraryIdentity: GuardianLibraryIdentity,
        libraryURL: URL,
        libraryBookmark: FolderBookmark,
        mirrorURL: URL,
        mirrorBookmark: FolderBookmark,
        plan: GuardianRestorePlan,
        selectedPaths: Set<String>
    ) {
        self.libraryIdentity = libraryIdentity
        self.libraryURL = libraryURL
        self.libraryBookmark = libraryBookmark
        self.mirrorURL = mirrorURL
        self.mirrorBookmark = mirrorBookmark
        self.plan = plan
        self.selectedPaths = selectedPaths
    }

    /// The restorable actions the user actually selected, in plan order.
    public var selectedActions: [GuardianRestoreAction] {
        plan.restorable.filter { selectedPaths.contains($0.relativePath) }
    }
}
