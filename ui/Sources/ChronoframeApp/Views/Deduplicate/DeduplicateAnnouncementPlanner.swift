#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// Pure VoiceOver announcement policy for Deduplicate state changes.
///
/// Progress is intentionally not announced here: scanning, commit, and restore
/// progress is exposed as an accessibility value on the progress control so a
/// VoiceOver user can query it on demand without hearing per-file noise.
enum DeduplicateAnnouncementPlanner {
    struct Snapshot: Equatable {
        var status: DeduplicateSessionStore.Status
        var phase: DeduplicatePhase?
        var clusterCount: Int
        var commitSummary: DeduplicateCommitSummary?

        init(
            status: DeduplicateSessionStore.Status,
            phase: DeduplicatePhase?,
            clusterCount: Int,
            commitSummary: DeduplicateCommitSummary?
        ) {
            self.status = status
            self.phase = phase
            self.clusterCount = clusterCount
            self.commitSummary = commitSummary
        }
    }

    static func announcement(from old: Snapshot, to new: Snapshot) -> String? {
        if new.status != old.status, let message = statusMessage(for: new) {
            return message
        }

        if new.status == .scanning,
           new.phase != old.phase,
           let phase = new.phase {
            return phase.title
        }

        return nil
    }

    private static func statusMessage(for snapshot: Snapshot) -> String? {
        switch snapshot.status {
        case .readyToReview:
            let count = snapshot.clusterCount
            return "Deduplicate scan complete. \(count) group\(count == 1 ? "" : "s") ready for review."
        case .completed:
            let count = snapshot.commitSummary?.deletedCount ?? 0
            return "Deduplicate complete. \(count) file\(count == 1 ? "" : "s") moved to Trash."
        case .reverted:
            let count = snapshot.commitSummary?.deletedCount ?? 0
            return "Restore complete. \(count) file\(count == 1 ? "" : "s") restored from Trash."
        case .failed:
            return "Deduplicate failed. Your original files were left untouched."
        case .idle, .scanning, .committing, .reverting:
            return nil
        }
    }
}
