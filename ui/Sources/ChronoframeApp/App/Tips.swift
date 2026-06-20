import SwiftUI
import TipKit

/// Discoverability tips surfaced via TipKit (macOS 14+).
///
/// Copy lives in `TipCopy` as plain strings so it can be asserted in unit tests
/// without rendering SwiftUI `Text`. The `Tip` conformances below are thin
/// wrappers that build their `Text`/`Image` from that copy.
enum TipCopy {
    enum TimelineScrubbing {
        static let title = "Scrub the timeline"
        static let message = "Drag across the run timeline to peek at the frames being copied at any point in the transfer."
        static let symbol = "hand.draw"
    }

    enum AcceptSafeSuggestions {
        static let title = "Accept safe matches in one step"
        static let message = "High-confidence groups are exact, verified duplicates — accept them together and keep moving. Chronoframe never auto-selects uncertain matches."
        static let symbol = "checkmark.seal"
    }

    enum DeduplicateWorkspace {
        static let title = "Reclaim space from duplicates"
        static let message = "Scan your library for duplicate photos and videos, then review each group before anything moves to the Trash."
        static let symbol = "rectangle.on.rectangle.angled"
    }
}

/// Shown on the run timeline the first time a finished/active timeline appears.
struct TimelineScrubbingTip: Tip {
    var title: Text { Text(TipCopy.TimelineScrubbing.title) }
    var message: Text? { Text(TipCopy.TimelineScrubbing.message) }
    var image: Image? { Image(systemName: TipCopy.TimelineScrubbing.symbol) }
}

/// Shown next to the "accept safe / high-confidence" control in Deduplicate.
struct AcceptSafeSuggestionsTip: Tip {
    var title: Text { Text(TipCopy.AcceptSafeSuggestions.title) }
    var message: Text? { Text(TipCopy.AcceptSafeSuggestions.message) }
    var image: Image? { Image(systemName: TipCopy.AcceptSafeSuggestions.symbol) }
}

/// Shown on the Deduplicate workspace entry point.
struct DeduplicateWorkspaceTip: Tip {
    var title: Text { Text(TipCopy.DeduplicateWorkspace.title) }
    var message: Text? { Text(TipCopy.DeduplicateWorkspace.message) }
    var image: Image? { Image(systemName: TipCopy.DeduplicateWorkspace.symbol) }
}

enum TipConfiguration {
    /// Configures the TipKit datastore. No-ops on failure — a tip that can't be
    /// stored simply doesn't show; it must never block app launch. Skipped
    /// under UI-test scenarios so tip popovers can't intercept automation.
    static func configureIfNeeded(isUITest: Bool) {
        guard !isUITest else { return }
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])
    }
}
