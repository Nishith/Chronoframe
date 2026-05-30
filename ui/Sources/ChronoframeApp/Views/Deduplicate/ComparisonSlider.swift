import CoreGraphics
import Foundation

/// Pure geometry/step math for the slider comparison divider, extracted so the
/// keyboard, VoiceOver, and drag paths all share one clamped implementation and
/// it can be unit-tested without a view.
enum ComparisonSlider {
    /// Fraction the divider moves per keyboard / VoiceOver step.
    static let step: CGFloat = 0.05

    /// Clamps a divider fraction to the valid 0...1 range.
    static func clamped(_ position: CGFloat) -> CGFloat {
        min(1, max(0, position))
    }

    /// Returns `position` moved by `delta`, clamped to 0...1.
    static func adjusted(_ position: CGFloat, by delta: CGFloat) -> CGFloat {
        clamped(position + delta)
    }

    /// Maps a horizontal drag location to a clamped divider fraction.
    static func fraction(forLocationX x: CGFloat, width: CGFloat) -> CGFloat {
        guard width > 0 else { return 0 }
        return clamped(x / width)
    }

    /// Spoken/announced value for the divider position.
    static func accessibilityValue(_ position: CGFloat) -> String {
        "\(Int((clamped(position) * 100).rounded()))% keeper"
    }
}

/// Outcome of a rapid-triage horizontal swipe, decided purely from the drag
/// translation so the threshold logic can be unit-tested.
enum TriageSwipeOutcome: Equatable {
    case accept
    case skip
    case none
}

enum RapidTriageSwipe {
    /// Horizontal distance (points) past which a swipe commits.
    static let threshold: CGFloat = 100

    static func outcome(forTranslationWidth width: CGFloat) -> TriageSwipeOutcome {
        if width > threshold { return .accept }
        if width < -threshold { return .skip }
        return .none
    }
}

enum DedupeReviewKeyboard {
    static func clusterIndex(afterMoving delta: Int, from currentIndex: Int?, count: Int) -> Int? {
        guard count > 0 else { return nil }
        let base = min(max(currentIndex ?? 0, 0), count - 1)
        return min(max(base + delta, 0), count - 1)
    }
}

enum FlickerComparisonPlayback {
    static let automaticIntervalMilliseconds = 900

    static func effectiveIsPlaying(requestedPlaying: Bool, reduceMotion: Bool) -> Bool {
        requestedPlaying && !reduceMotion
    }

    static func accessibilityValue(isShowingKeeper: Bool, isPlaying: Bool) -> String {
        let side = isShowingKeeper ? "showing keeper" : "showing compare"
        return isPlaying
            ? "Playing, \(side), alternating every \(Double(automaticIntervalMilliseconds) / 1000) seconds"
            : "Paused, \(side)"
    }
}
