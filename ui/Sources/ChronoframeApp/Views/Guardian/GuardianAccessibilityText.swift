import Foundation
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif

/// Composes the spoken VoiceOver descriptions for the Library Guardian surfaces —
/// the scan summary, individual findings, and the restore review list.
///
/// Kept as pure functions (no view state) so the wording can be unit-tested
/// without a running UI. Trust and integrity are always spoken in the plain,
/// reassuring vocabulary the UI uses ("verified", "bit rot", "missing"), never in
/// raw enum or technical terms.
enum GuardianAccessibilityText {
    /// One spoken line summarizing a completed scan.
    static func scanSummary(_ summary: GuardianStore.ScanSummary) -> String {
        if summary.partialScan {
            return "Scan incomplete. Some folders couldn't be read, so results are partial. "
                + verifiedClause(summary)
        }
        if summary.corrupt == 0 && summary.missing == 0 && summary.modified == 0 {
            return "Library healthy. " + verifiedClause(summary) + " No problems found."
        }
        var parts: [String] = [verifiedClause(summary)]
        if summary.corrupt > 0 {
            parts.append("\(summary.corrupt) \(pluralize(summary.corrupt, "file")) with suspected bit rot")
        }
        if summary.missing > 0 {
            parts.append("\(summary.missing) missing")
        }
        if summary.modified > 0 {
            parts.append("\(summary.modified) changed")
        }
        return parts.joined(separator: ", ") + ". Review needed."
    }

    /// The spoken description of one finding row.
    static func finding(_ finding: GuardianIntegrityFinding) -> String {
        let name = URL(fileURLWithPath: finding.relativePath).lastPathComponent
        switch finding.status {
        case .verified:
            return "\(name), verified against the trusted copy."
        case .corrupt:
            return "\(name), suspected bit rot: the bytes changed but the size and date did not. Restore from the mirror or accept the new version."
        case .modified:
            return "\(name), changed since it was trusted. Accept the new version or restore the trusted copy."
        case .missing:
            return "\(name), missing from the library. Restore it from the mirror or acknowledge the deletion."
        case .new:
            return "\(name), new and not yet trusted."
        case .dataless:
            return "\(name), stored in iCloud and not downloaded, so it was skipped."
        case .unreadable:
            return "\(name), couldn't be read this scan."
        case .changedDuringScan:
            return "\(name), changed while it was being checked, so it will be re-checked next scan."
        }
    }

    /// The spoken description of one restore-review row.
    static func restoreAction(_ action: GuardianRestoreAction, isSelected: Bool) -> String {
        let name = URL(fileURLWithPath: action.relativePath).lastPathComponent
        let reason: String
        switch action.reason {
        case .primaryCorrupt:
            reason = "healing suspected bit rot"
        case .primaryMissing:
            reason = "restoring a missing file"
        }
        let state = isSelected ? "selected for restore" : "not selected"
        return "\(name), \(reason) from the verified mirror copy, \(state)."
    }

    // MARK: - Helpers

    private static func verifiedClause(_ summary: GuardianStore.ScanSummary) -> String {
        "\(summary.verified) \(pluralize(summary.verified, "file")) verified"
    }

    private static func pluralize(_ count: Int, _ noun: String) -> String {
        count == 1 ? noun : noun + "s"
    }
}
