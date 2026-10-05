import Foundation

/// An import date pinned to the exact exported bytes. Both preview and the
/// execution re-plan consume this snapshot, never staging filesystem dates.
public struct SourceDateHint: Equatable, Codable, Sendable {
    public let identity: FileIdentity
    public let resolvedDate: ResolvedMediaDate

    public init(identity: FileIdentity, resolvedDate: ResolvedMediaDate) {
        self.identity = identity
        self.resolvedDate = resolvedDate
    }

    /// Foundation discovery and path construction can spell the same macOS
    /// temp root as /private/var and /var. Use one lexical key in snapshots.
    public static func pathKey(for path: String) -> String {
        URL(fileURLWithPath: path).standardizedFileURL.path
    }
}

enum SourceDateHintError: LocalizedError {
    case changed
    var errorDescription: String? {
        "A prepared Photos original changed. Select the items in Photos and prepare the import again. Your Photos library was not changed."
    }
}
