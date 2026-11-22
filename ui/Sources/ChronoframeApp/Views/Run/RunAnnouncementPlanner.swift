import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

/// Decides what (if anything) VoiceOver should announce when a run's state
/// changes. Kept as a pure function over a small snapshot so the throttling,
/// wording, and interruption priority can be unit-tested without a running run
/// loop or VoiceOver.
///
/// Priority order, so a single transition produces at most one announcement:
/// 1. A terminal status change (finished / failed / cancelled / …).
/// 2. A phase change (Discover → Hash Source → …).
/// 3. Crossing a coarse copy-progress bucket (every 25%).
enum RunAnnouncementPlanner {

    /// Minimal view of run state the planner reasons about.
    struct Snapshot: Equatable {
        var status: RunStatus
        var phase: RunPhase?
        var progress: Double
        /// The user asked to stop and the run has not stopped yet.
        var isCancelling: Bool
        /// The finished run reported failed, errored or unreadable files.
        var hasOutcomeIssues: Bool

        init(
            status: RunStatus,
            phase: RunPhase?,
            progress: Double,
            isCancelling: Bool = false,
            hasOutcomeIssues: Bool = false
        ) {
            self.status = status
            self.phase = phase
            self.progress = progress
            self.isCancelling = isCancelling
            self.hasOutcomeIssues = hasOutcomeIssues
        }
    }

    /// How assertively VoiceOver should deliver an announcement. The view maps
    /// these to `NSAccessibilityPriorityLevel`; kept AppKit-free here so the
    /// planner stays a pure, unit-testable value type.
    ///
    /// Only terminal outcomes interrupt what the user is doing. Routine progress
    /// is the lowest priority so a screen-reader user sweeping the UI isn't
    /// talked over every 25%.
    enum Priority: Equatable {
        /// Terminal outcomes (complete / failed / cancelled / …) — may interrupt.
        case high
        /// Phase transitions — announced but yielding to the user.
        case medium
        /// Coarse copy progress — never interrupts; dropped if VoiceOver is busy.
        case low
    }

    /// A planned announcement: what to say and how assertively to say it.
    struct Announcement: Equatable {
        let message: String
        let priority: Priority
    }

    /// Announce copy progress at these granularity steps (percent).
    static let progressBucketPercent = 25

    /// Spoken string for a transition, or `nil` when nothing should be said.
    /// Thin wrapper over ``detailedAnnouncement(from:to:)`` for callers that
    /// only need the text.
    static func announcement(from old: Snapshot, to new: Snapshot) -> String? {
        detailedAnnouncement(from: old, to: new)?.message
    }

    /// Spoken string *and* delivery priority for a transition, or `nil` when
    /// nothing should be said.
    static func detailedAnnouncement(from old: Snapshot, to new: Snapshot) -> Announcement? {
        // 1. Terminal status changes win — they're the most important to hear,
        //    and the only ones important enough to interrupt the user.
        if new.status != old.status, let message = terminalMessage(for: new.status) {
            if new.status == .finished, new.hasOutcomeIssues {
                return Announcement(
                    message: String(localized: "Copy finished with problems. Your original files were left untouched.", bundle: .module),
                    priority: .high
                )
            }
            return Announcement(message: message, priority: .high)
        }

        // 1b. Stop requested: say so once, so the silence while the engine
        //     finishes its receipt is not mistaken for a hang.
        if new.status == .running, new.isCancelling, !old.isCancelling {
            return Announcement(message: String(localized: "Stopping…", bundle: .module), priority: .medium)
        }

        // 2. Phase changes during an active run.
        if new.phase != old.phase, let phase = new.phase, new.status == .running {
            return Announcement(message: phase.displayTitle, priority: .medium)
        }

        // 3. Coarse copy-progress buckets, only while copying. Lowest priority:
        //    routine progress must not talk over a user reading the UI.
        if new.status == .running, new.phase == .copy {
            let oldBucket = bucket(for: old.progress)
            let newBucket = bucket(for: new.progress)
            if newBucket > oldBucket, newBucket > 0, newBucket < bucketsPerWhole {
                return Announcement(message: String(localized: "\(String(newBucket * progressBucketPercent)) percent copied", bundle: .module), priority: .low)
            }
        }

        return nil
    }

    // MARK: - Helpers

    private static var bucketsPerWhole: Int { 100 / progressBucketPercent }

    private static func bucket(for progress: Double) -> Int {
        let clamped = min(1, max(0, progress))
        return Int(clamped * 100) / progressBucketPercent
    }

    private static func terminalMessage(for status: RunStatus) -> String? {
        switch status {
        case .finished:
            return String(localized: "Copy complete.", bundle: .module)
        case .dryRunFinished:
            return String(localized: "Preview ready for review.", bundle: .module)
        case .nothingToCopy:
            return String(localized: "Nothing new to copy.", bundle: .module)
        case .failed:
            return String(localized: "Chronoframe could not finish. Your original files were left untouched.", bundle: .module)
        case .cancelled:
            return String(localized: "Stopped. Your original files were left untouched.", bundle: .module)
        case .reverted:
            return String(localized: "Undo complete.", bundle: .module)
        case .revertEmpty:
            return String(localized: "Nothing to undo.", bundle: .module)
        case .reorganized:
            return String(localized: "Layout updated.", bundle: .module)
        case .nothingToReorganize:
            return String(localized: "Layout already matches.", bundle: .module)
        case .idle, .preflighting, .running:
            return nil
        }
    }
}
