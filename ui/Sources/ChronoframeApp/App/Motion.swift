import SwiftUI

/// Motion tokens for the Darkroom design language.
///
/// Two opinions, applied consistently:
/// 1. **Time-involving motion** uses an easeInOut curve with filmic duration
///    (~0.45s). Dots rising into the timeline, phases settling into place.
/// 2. **State/status motion** uses linear or a fast spring (response 0.25,
///    damping 0.9). Progress bars, ticker counters, mechanical precision.
enum Motion {

    // MARK: - Durations
    enum Duration {
        /// Instant UI feedback (e.g. toggle).
        static let instant: Double = 0.12
        /// Standard state transition.
        static let fast: Double = 0.22
        /// Filmic timeline motion — the default for most content changes.
        static let filmic: Double = 0.45
        /// Contact-sheet reveal, per-cell stagger base.
        static let reveal: Double = 0.60
        /// Completion "developing wash" sweep.
        static let wash: Double = 1.50
        /// Per-frame copy pulse.
        static let pulse: Double = 0.20
    }

    // MARK: - Animations
    /// Filmic easeInOut for time-involving motion.
    static let filmic = Animation.easeInOut(duration: Duration.filmic)

    /// Mechanical spring for state updates (tickers, progress, status pills).
    static let mechanical = Animation.spring(response: 0.25, dampingFraction: 0.9)

    /// Instant fade for appearance changes.
    static let instant = Animation.easeOut(duration: Duration.instant)

    /// Reveal curve — used for contact-sheet cells.
    static let reveal = Animation.easeOut(duration: Duration.reveal)

    /// The completion "developing wash" sweep animation.
    static let wash = Animation.easeInOut(duration: Duration.wash)

    /// Per-cell stagger for contact-sheet reveals (40ms per cell).
    static func staggered(cellIndex: Int, base: Double = 0.04) -> Animation {
        reveal.delay(base * Double(cellIndex))
    }

    // MARK: - Reduce-motion resolution

    /// Resolves the animation that should actually be applied given the current
    /// Reduce Motion setting: the requested animation when motion is allowed,
    /// `nil` (no animation) when Reduce Motion is on.
    ///
    /// This is the single decision point every motion helper routes through, so
    /// it can be unit-tested in isolation (see `MotionTests`).
    static func resolved(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }

    /// Imperative companion to the `.motion(_:value:)` modifier for call sites
    /// that must drive an explicit state change (e.g. `ScrollViewProxy.scrollTo`
    /// or a drag-resize). Runs `body` inside `withAnimation`, honoring Reduce
    /// Motion via `resolved(_:reduceMotion:)`.
    @MainActor
    static func withMotion<Result>(
        _ animation: Animation,
        reduceMotion: Bool,
        _ body: () throws -> Result
    ) rethrows -> Result {
        try withAnimation(resolved(animation, reduceMotion: reduceMotion), body)
    }
}

// MARK: - Reduce-motion helper

extension View {
    /// Applies `animation` only when Reduce Motion is off; otherwise no animation.
    func motion<V: Equatable>(_ animation: Animation, value: V) -> some View {
        modifier(ReduceMotionAnimationModifier(animation: animation, value: value))
    }
}

private struct ReduceMotionAnimationModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(Motion.resolved(animation, reduceMotion: reduceMotion), value: value)
    }
}
