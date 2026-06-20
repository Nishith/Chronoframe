import ChronoframeCore
import Foundation

/// Pure builder for the payload behind the Run History `ShareLink`. We share the
/// receipt/report/log file that already exists on disk rather than synthesizing
/// a new export format, so the shared artifact is byte-identical to what the app
/// wrote. Kept free of SwiftUI so the URL/title policy is unit-tested.
public enum RunArtifactShare {
    /// The on-disk file to share for a history entry.
    public static func fileURL(for entry: RunHistoryEntry) -> URL {
        URL(fileURLWithPath: entry.path)
    }

    /// Human-readable title surfaced by the share sheet.
    public static func shareTitle(for entry: RunHistoryEntry) -> String {
        entry.title
    }
}
