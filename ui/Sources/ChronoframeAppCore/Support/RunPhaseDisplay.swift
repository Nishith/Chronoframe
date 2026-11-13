#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// Plain-language phase names for the app. `RunPhase.title` and
/// `RunPhase.runningTitle` stay as they are because the command-line tool
/// prints them.
public extension RunPhase {
    var displayTitle: String {
        switch self {
        case .discovery:
            return "Find Files"
        case .sourceHashing:
            return "Read Originals"
        case .destinationIndexing:
            return "Check Destination"
        case .classification:
            return "Sort by Date"
        case .copy:
            return "Copy"
        case .revert:
            return "Undo"
        case .reorganize:
            return "Reorganize"
        }
    }

    var displayRunningTitle: String {
        switch self {
        case .discovery:
            return "Finding files…"
        case .sourceHashing:
            return "Reading your originals…"
        case .destinationIndexing:
            return "Checking the destination…"
        case .classification:
            return "Sorting by date…"
        case .copy:
            return "Copying files…"
        case .revert:
            return "Undoing…"
        case .reorganize:
            return "Reorganizing files…"
        }
    }
}
