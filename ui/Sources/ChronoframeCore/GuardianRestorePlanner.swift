import Foundation

// MARK: - Guardian verified-restore planner (Phase 3)
//
// Pure single source of truth for the restore executor. Given a library integrity
// report (which files are corrupt or missing) and a probe of the mirror, it decides
// which files can be safely healed — only those whose mirror copy still hashes to
// the trusted digest. Everything else is reported as blocked and never touched.

public struct GuardianRestorePlanner: Sendable {
    public init() {}

    public func plan(
        libraryRoot: String,
        mirrorRoot: String,
        libraryReport: GuardianIntegrityReport,
        mirrorObservations: [GuardianFileObservation]
    ) -> GuardianRestorePlan {
        var mirrorByPath: [String: GuardianFileObservation] = [:]
        for observation in mirrorObservations where mirrorByPath[observation.relativePath] == nil {
            mirrorByPath[observation.relativePath] = observation
        }

        var restorable: [GuardianRestoreAction] = []
        var blocked: [GuardianRestoreBlock] = []

        for finding in libraryReport.findings {
            let reason: GuardianRestoreReason
            switch finding.status {
            case .corrupt:
                reason = .primaryCorrupt
            case .missing:
                reason = .primaryMissing
            default:
                continue
            }

            // The trusted baseline the restored file must match. For corrupt/missing
            // findings the classifier records this as the manifest identity.
            guard let trusted = finding.expectedIdentity else {
                blocked.append(GuardianRestoreBlock(relativePath: finding.relativePath, reason: .noTrustedBaseline))
                continue
            }

            guard let mirror = mirrorByPath[finding.relativePath] else {
                blocked.append(GuardianRestoreBlock(relativePath: finding.relativePath, reason: .mirrorMissing))
                continue
            }

            switch mirror.outcome {
            case .hashed:
                if mirror.digest == trusted.digest && mirror.size == trusted.size {
                    restorable.append(
                        GuardianRestoreAction(
                            relativePath: finding.relativePath,
                            trustedIdentity: trusted,
                            reason: reason,
                            expectedCurrentPrimaryIdentity: reason == .primaryCorrupt ? finding.observedIdentity : nil
                        )
                    )
                } else {
                    // Corrupt on both sides — never restore from bad bytes.
                    blocked.append(GuardianRestoreBlock(relativePath: finding.relativePath, reason: .mirrorDivergent))
                }
            case .dataless, .unreadable, .changedDuringScan:
                blocked.append(GuardianRestoreBlock(relativePath: finding.relativePath, reason: .mirrorUnreadable))
            }
        }

        restorable.sort { $0.relativePath < $1.relativePath }
        blocked.sort { $0.relativePath < $1.relativePath }

        return GuardianRestorePlan(
            libraryRoot: libraryRoot,
            mirrorRoot: mirrorRoot,
            restorable: restorable,
            blocked: blocked
        )
    }
}
