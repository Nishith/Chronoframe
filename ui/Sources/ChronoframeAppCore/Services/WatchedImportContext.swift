import Foundation

/// Everything a watched-source Review & Import needs to run without
/// touching Setup, profile, or manual-bookmark state.
///
/// The context pins the run's identity at click time: the resolved
/// source, its own security-scoped bookmark, the destination that was
/// active when the user clicked, and the freshness stamps captured from
/// the latest complete scan. The run configuration is built from this
/// context — never from Setup — so selecting a watched source while a
/// profile is active can never retarget the import to a restored manual
/// destination. Before the transfer starts the coordinator revalidates
/// that the active destination still matches `destinationPath`; a
/// mismatch cancels with a clear message instead of retargeting.
///
/// `capturedStamps` bounds what a successful import may acknowledge:
/// only these stamps merge into the source's checkpoint, so files that
/// arrive or change after capture stay pending.
public struct WatchedImportContext: Equatable, Sendable {
    public let sourceID: UUID
    public let sourceURL: URL
    public let sourceBookmark: FolderBookmark
    public let destinationPath: String
    public let destinationBookmarkKeys: [String]
    public let capturedStamps: [String: WatchedFileStamp]
    public let scanGeneration: UInt64

    public init(
        sourceID: UUID,
        sourceURL: URL,
        sourceBookmark: FolderBookmark,
        destinationPath: String,
        destinationBookmarkKeys: [String],
        capturedStamps: [String: WatchedFileStamp],
        scanGeneration: UInt64
    ) {
        self.sourceID = sourceID
        self.sourceURL = sourceURL
        self.sourceBookmark = sourceBookmark
        self.destinationPath = destinationPath
        self.destinationBookmarkKeys = destinationBookmarkKeys
        self.capturedStamps = capturedStamps
        self.scanGeneration = scanGeneration
    }
}
