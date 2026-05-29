import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif

/// Decides what (if anything) VoiceOver should announce when a run's state
/// changes. Kept as a pure function over a small snapshot so the throttling and
/// wording can be unit-tested without a running run loop or VoiceOver.
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

        init(status: RunStatus, phase: RunPhase?, progress: Double) {
            self.status = status
            self.phase = phase
            self.progress = progress
        }
    }

    /// Announce copy progress at these granularity steps (percent).
    static let progressBucketPercent = 25

    static func announcement(from old: Snapshot, to new: Snapshot) -> String? {
        // 1. Terminal status changes win — they're the most important to hear.
        if new.status != old.status, let message = terminalMessage(for: new.status) {
            return message
        }

        // 2. Phase changes during an active run.
        if new.phase != old.phase, let phase = new.phase, new.status == .running {
            return phase.title
        }

        // 3. Coarse copy-progress buckets, only while copying.
        if new.status == .running, new.phase == .copy {
            let oldBucket = bucket(for: old.progress)
            let newBucket = bucket(for: new.progress)
            if newBucket > oldBucket, newBucket > 0, newBucket < bucketsPerWhole {
                return "\(newBucket * progressBucketPercent) percent copied"
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
            return "Transfer complete."
        case .dryRunFinished:
            return "Preview ready for review."
        case .nothingToCopy:
            return "Nothing new to copy."
        case .failed:
            return "Run failed. Your original files were left untouched."
        case .cancelled:
            return "Run cancelled. Your original files were left untouched."
        case .reverted:
            return "Revert complete."
        case .revertEmpty:
            return "Nothing to revert."
        case .reorganized:
            return "Reorganize complete."
        case .nothingToReorganize:
            return "Nothing to reorganize."
        case .idle, .preflighting, .running:
            return nil
        }
    }
}
