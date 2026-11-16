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
            return String(localized: "Scan incomplete. Some folders couldn't be read, so results are partial. ", bundle: .module)
                + verifiedClause(summary)
        }
        if summary.corrupt == 0 && summary.missing == 0 && summary.modified == 0 {
            return String(localized: "Library healthy. ", bundle: .module) + verifiedClause(summary) + String(localized: " No problems found.", bundle: .module)
        }
        var parts: [String] = [verifiedClause(summary)]
        if summary.corrupt > 0 {
            parts.append(String(localized: "\(String(summary.corrupt)) \(fileNoun(summary.corrupt)) with suspected bit rot", bundle: .module))
        }
        if summary.missing > 0 {
            parts.append(String(localized: "\(String(summary.missing)) missing", bundle: .module))
        }
        if summary.modified > 0 {
            parts.append(String(localized: "\(String(summary.modified)) changed", bundle: .module))
        }
        return parts.joined(separator: ", ") + String(localized: ". Review needed.", bundle: .module)
    }

    /// The spoken description of one finding row.
    static func finding(_ finding: GuardianIntegrityFinding) -> String {
        let name = URL(fileURLWithPath: finding.relativePath).lastPathComponent
        switch finding.status {
        case .verified:
            return String(localized: "\(String(name)), verified against the trusted copy.", bundle: .module)
        case .corrupt:
            return String(localized: "\(String(name)), suspected bit rot: the bytes changed but the size and date did not. Restore from the mirror or accept the new version.", bundle: .module)
        case .modified:
            return String(localized: "\(String(name)), changed since it was trusted. Accept the new version or restore the trusted copy.", bundle: .module)
        case .missing:
            return String(localized: "\(String(name)), missing from the library. Restore it from the mirror or acknowledge the deletion.", bundle: .module)
        case .new:
            return String(localized: "\(String(name)), new and not yet trusted.", bundle: .module)
        case .dataless:
            return String(localized: "\(String(name)), stored in iCloud and not downloaded, so it was skipped.", bundle: .module)
        case .unreadable:
            return String(localized: "\(String(name)), couldn't be read this scan.", bundle: .module)
        case .changedDuringScan:
            return String(localized: "\(String(name)), changed while it was being checked, so it will be re-checked next scan.", bundle: .module)
        }
    }

    /// The spoken description of one restore-review row.
    static func restoreAction(_ action: GuardianRestoreAction, isSelected: Bool) -> String {
        let name = URL(fileURLWithPath: action.relativePath).lastPathComponent
        let reason: String
        switch action.reason {
        case .primaryCorrupt:
            reason = String(localized: "healing suspected bit rot", bundle: .module)
        case .primaryMissing:
            reason = String(localized: "restoring a missing file", bundle: .module)
        }
        let state = isSelected ? String(localized: "selected for restore", bundle: .module) : String(localized: "not selected", bundle: .module)
        return String(localized: "\(String(name)), \(String(reason)) from the verified mirror copy, \(String(state)).", bundle: .module)
    }

    // MARK: - Helpers

    private static func verifiedClause(_ summary: GuardianStore.ScanSummary) -> String {
        String(localized: "\(String(summary.verified)) \(fileNoun(summary.verified)) verified", bundle: .module)
    }

    private static func fileNoun(_ count: Int) -> String {
        count == 1 ? String(localized: "file", bundle: .module) : String(localized: "files", bundle: .module)
    }
}
