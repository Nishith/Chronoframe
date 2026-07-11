import Foundation

/// Everything an Apple Photos "Review & Import" needs to run without touching
/// Setup, profile, or manual-bookmark state.
///
/// Like `WatchedImportContext`, the context pins the run's identity at the
/// moment the user clicks import: the Chronoframe-owned staging directory that
/// the selected originals were exported into (used as the run source) and the
/// destination that was active at click time plus its security-scoped bookmark
/// keys. The run configuration is built from this context — never from Setup —
/// so selecting Photos assets while a profile is active can never retarget the
/// import to a restored manual destination. Before the transfer starts the
/// coordinator revalidates that the active destination still matches
/// `destinationPath`; a mismatch cancels with a clear message rather than
/// retargeting.
///
/// The staging directory is app-owned (inside the container's Application
/// Support), so the source needs no security-scoped bookmark — only the
/// destination does. It is deleted once the run finishes, fails, or is
/// cancelled; the Photos library itself is never modified.
public struct PhotosImportContext: Equatable, Sendable {
    public let importID: UUID
    /// The populated staging directory that serves as the run's `sourcePath`.
    public let stagingDirectoryURL: URL
    public let destinationPath: String
    public let destinationBookmarkKeys: [String]
    /// The Photos asset identifiers the user selected, retained for records
    /// and diagnostics. Not used to re-fetch during the transfer — staging is
    /// already populated by the time the context exists.
    public let assetIDs: [String]

    public init(
        importID: UUID,
        stagingDirectoryURL: URL,
        destinationPath: String,
        destinationBookmarkKeys: [String],
        assetIDs: [String]
    ) {
        self.importID = importID
        self.stagingDirectoryURL = stagingDirectoryURL
        self.destinationPath = destinationPath
        self.destinationBookmarkKeys = destinationBookmarkKeys
        self.assetIDs = assetIDs
    }
}
