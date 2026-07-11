#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Guardian in-app + catch-up scheduling (Phase 4, pure decision logic)
//
// v1 Guardian scheduling is deliberately modest: it is NOT a persistent
// wall-clock daemon. It fires only while Chronoframe is running, persists a
// per-library next-run plus last-attempted / last-succeeded timestamps, and on
// launch/wake catches up *one* missed run (never a burst of back-to-back runs
// for every interval that elapsed while the app was quit). A true launch-agent
// helper that scrubs while the app is closed is a documented fast-follow.
//
// This type is pure and deterministic — every decision is a function of the
// persisted state, the configured interval, and an injected `now`, so the whole
// contract is unit-testable without timers or the filesystem.

/// Persisted, per-library scheduling state. Lives in Application Support keyed by
/// library identity — never inside the protected library.
public struct GuardianScheduleState: Equatable, Codable, Sendable {
    /// When the next automatic scrub should fire. `nil` means "never scheduled";
    /// the first eligible tick establishes the cadence.
    public var nextRunAt: Date?
    /// The last time an automatic scrub was *attempted* (whether or not it
    /// succeeded). Distinct from `lastSucceededAt` so the UI can distinguish a
    /// run that failed from one that never ran.
    public var lastAttemptedAt: Date?
    /// The last time an automatic scrub completed successfully (no unreadable
    /// subtrees). Auto-mirror is gated on a clean, complete scrub.
    public var lastSucceededAt: Date?

    public init(
        nextRunAt: Date? = nil,
        lastAttemptedAt: Date? = nil,
        lastSucceededAt: Date? = nil
    ) {
        self.nextRunAt = nextRunAt
        self.lastAttemptedAt = lastAttemptedAt
        self.lastSucceededAt = lastSucceededAt
    }
}

/// What the scheduler wants the app to do for a library's automatic scrub.
public enum GuardianScrubDecision: Equatable, Sendable {
    /// Auto-scrub is off (disabled preference or non-positive interval).
    case disabled
    /// A scrub is due now — either the scheduled time has passed, one was missed
    /// while the app was quit (a single catch-up run), or no baseline exists yet.
    case run
    /// Not due yet; the next automatic scrub is scheduled for this instant.
    case waitUntil(Date)
}

public struct GuardianScheduler: Sendable {
    public init() {}

    /// Decide whether an automatic scrub should fire for a library right now.
    ///
    /// A `nextRunAt` in the past collapses to a single `.run` regardless of how
    /// many intervals elapsed while the app was closed — catch-up is one run, not
    /// a backlog. Auto-scrub never depends on the mirror being online (a scrub is
    /// a read-only integrity check of the library itself); only auto-mirror does.
    public func scrubDecision(
        state: GuardianScheduleState,
        interval: TimeInterval,
        autoScrubEnabled: Bool,
        now: Date
    ) -> GuardianScrubDecision {
        guard autoScrubEnabled, interval > 0 else { return .disabled }
        guard let nextRunAt = state.nextRunAt else { return .run }
        if now >= nextRunAt { return .run }
        return .waitUntil(nextRunAt)
    }

    /// Fold the result of an attempt back into the persisted state. `nextRunAt` is
    /// always re-anchored to `attemptedAt + interval`, so a catch-up run resets the
    /// cadence forward from when it actually ran and cannot immediately re-fire.
    public func advance(
        state: GuardianScheduleState,
        interval: TimeInterval,
        attemptedAt: Date,
        succeeded: Bool
    ) -> GuardianScheduleState {
        var updated = state
        updated.lastAttemptedAt = attemptedAt
        if succeeded { updated.lastSucceededAt = attemptedAt }
        updated.nextRunAt = attemptedAt.addingTimeInterval(max(interval, 0))
        return updated
    }

    /// Whether an automatic mirror may run after a scrub. Auto-mirror is fail-safe:
    /// it runs only when auto-mirror is enabled, the mirror volume is online, the
    /// scrub was **complete** (no unreadable subtrees), and the library has no
    /// corruption or ambiguous readings. A corrupt, partial, or partially-
    /// unreadable library is skipped so Guardian never propagates bad or
    /// half-verified bytes to the mirror. Restore is never auto-run.
    public func shouldAutoMirror(
        report: GuardianIntegrityReport,
        autoMirrorEnabled: Bool,
        mirrorOnline: Bool
    ) -> Bool {
        guard autoMirrorEnabled, mirrorOnline, !report.partialScan else { return false }
        for finding in report.findings {
            switch finding.status {
            case .corrupt, .unreadable, .changedDuringScan:
                return false
            case .verified, .modified, .missing, .new, .dataless:
                continue
            }
        }
        return true
    }
}
