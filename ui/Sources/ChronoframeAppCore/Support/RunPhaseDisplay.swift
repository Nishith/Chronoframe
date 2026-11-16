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
            return CoreL10n.text("Find Files")
        case .sourceHashing:
            return CoreL10n.text("Read Originals")
        case .destinationIndexing:
            return CoreL10n.text("Check Destination")
        case .classification:
            return CoreL10n.text("Sort by Date")
        case .copy:
            return CoreL10n.text("Copy")
        case .revert:
            return CoreL10n.text("Undo")
        case .reorganize:
            return CoreL10n.text("Reorganize")
        }
    }

    var displayRunningTitle: String {
        switch self {
        case .discovery:
            return CoreL10n.text("Finding files…")
        case .sourceHashing:
            return CoreL10n.text("Reading your originals…")
        case .destinationIndexing:
            return CoreL10n.text("Checking the destination…")
        case .classification:
            return CoreL10n.text("Sorting by date…")
        case .copy:
            return CoreL10n.text("Copying files…")
        case .revert:
            return CoreL10n.text("Undoing…")
        case .reorganize:
            return CoreL10n.text("Reorganizing files…")
        }
    }
}

/// Plain-language mode names for the app. `RunMode.title` keeps the engine
/// wording because engine and command-line error text print it.
public extension RunMode {
    var displayTitle: String {
        switch self {
        case .preview:
            return CoreL10n.text("Preview")
        case .transfer:
            return CoreL10n.text("Copy")
        case .revert:
            return CoreL10n.text("Undo")
        case .reorganize:
            return CoreL10n.text("Reorganize")
        }
    }
}
