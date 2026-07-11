import Foundation

// MARK: - Guardian manifest updater (Phase 1)
//
// Pure functions that turn an integrity report (and explicit user decisions) into
// the manifest rows to persist. This is where the load-bearing trust rule lives:
//
//   The scan-driven path NEVER advances an entry to `trusted`. It only records new
//   files as `unprotected`, refreshes the last-verified time of already-trusted
//   files that still match, and DEMOTES trusted files to `changedPendingReview`
//   when they no longer match — always keeping the good baseline digest, never
//   overwriting it with corrupt bytes.
//
// The only routes to `trusted` are the explicit `accept(...)` (user acceptance) and
// `seedTrusted(...)` (verified-transfer provenance) helpers below, and the only
// route to `retired` is the explicit `acknowledgeDeletions(...)` helper.

public struct GuardianManifestUpdater: Sendable {
    public init() {}

    /// Rows to upsert after a scan. Never deletes (deletion retention) and never
    /// produces a `trusted` entry that was not already trusted.
    public func scanUpserts(
        report: GuardianIntegrityReport,
        manifest: [String: GuardianManifestEntry],
        now: Date = Date()
    ) -> [GuardianManifestEntry] {
        var upserts: [GuardianManifestEntry] = []

        for finding in report.findings {
            let existing = manifest[finding.relativePath]
            switch finding.status {
            case .new:
                // Track newly observed files as unprotected — never trusted.
                guard let observed = finding.observedIdentity else { continue }
                upserts.append(
                    GuardianManifestEntry(
                        relativePath: finding.relativePath,
                        size: observed.size,
                        modificationTime: finding.observedModificationTime ?? existing?.modificationTime ?? 0,
                        digest: observed.digest,
                        trustState: .unprotected,
                        provenance: nil,
                        firstObservedAt: existing?.firstObservedAt ?? now,
                        lastVerifiedAt: existing?.lastVerifiedAt
                    )
                )

            case .verified:
                // Still matches the trusted baseline: refresh last-verified only.
                guard var entry = existing else { continue }
                entry.lastVerifiedAt = now
                upserts.append(entry)

            case .corrupt, .modified, .missing:
                // No longer matches (or is gone): demote a trusted baseline to
                // pending review, keeping the good digest. Never overwrite the
                // baseline with the observed (possibly corrupt) bytes.
                guard var entry = existing, entry.trustState == .trusted else { continue }
                entry.trustState = .changedPendingReview
                upserts.append(entry)

            case .dataless, .unreadable, .changedDuringScan:
                // Ambiguous readings never change trust or the baseline.
                continue
            }
        }

        return upserts
    }

    /// Explicit user acceptance: promote the given paths to `trusted`, recording the
    /// **currently observed** identity from `report` as the new known-good baseline.
    /// A path with no clean current reading is skipped (cannot bless unknown bytes).
    public func accept(
        relativePaths: Set<String>,
        report: GuardianIntegrityReport,
        manifest: [String: GuardianManifestEntry],
        now: Date = Date()
    ) -> [GuardianManifestEntry] {
        var upserts: [GuardianManifestEntry] = []
        let findingsByPath = Dictionary(report.findings.map { ($0.relativePath, $0) }) { first, _ in first }

        for path in relativePaths {
            guard
                let finding = findingsByPath[path],
                let observed = finding.observedIdentity,
                finding.status == .verified || finding.status == .corrupt
                    || finding.status == .modified || finding.status == .new
            else { continue }
            let existing = manifest[path]
            upserts.append(
                GuardianManifestEntry(
                    relativePath: path,
                    size: observed.size,
                    modificationTime: finding.observedModificationTime ?? existing?.modificationTime ?? 0,
                    digest: observed.digest,
                    trustState: .trusted,
                    provenance: .userAccepted,
                    firstObservedAt: existing?.firstObservedAt ?? now,
                    lastVerifiedAt: now
                )
            )
        }
        return upserts
    }

    /// Verified-transfer provenance: promote a path to `trusted` when its current
    /// digest matches a digest Chronoframe itself wrote and verified (e.g. from an
    /// organize/import audit receipt). Only an exact digest match is trusted.
    public func seedTrusted(
        provenanceDigests: [String: FileIdentity],
        report: GuardianIntegrityReport,
        manifest: [String: GuardianManifestEntry],
        now: Date = Date()
    ) -> [GuardianManifestEntry] {
        var upserts: [GuardianManifestEntry] = []

        for finding in report.findings {
            guard
                let observed = finding.observedIdentity,
                let trustedIdentity = provenanceDigests[finding.relativePath],
                observed == trustedIdentity
            else { continue }
            // Do not re-stamp an already-trusted, still-matching entry.
            if let existing = manifest[finding.relativePath],
               existing.trustState == .trusted,
               existing.digest == observed.digest {
                continue
            }
            let existing = manifest[finding.relativePath]
            upserts.append(
                GuardianManifestEntry(
                    relativePath: finding.relativePath,
                    size: observed.size,
                    modificationTime: finding.observedModificationTime ?? existing?.modificationTime ?? 0,
                    digest: observed.digest,
                    trustState: .trusted,
                    provenance: .verifiedTransfer,
                    firstObservedAt: existing?.firstObservedAt ?? now,
                    lastVerifiedAt: now
                )
            )
        }
        return upserts
    }

    /// Explicit acknowledgement that missing files are intentionally gone: mark them
    /// `retired` so future scans stop flagging them. Only paths currently reported
    /// `missing` are retired.
    public func acknowledgeDeletions(
        relativePaths: Set<String>,
        report: GuardianIntegrityReport,
        manifest: [String: GuardianManifestEntry]
    ) -> [GuardianManifestEntry] {
        var upserts: [GuardianManifestEntry] = []
        let missing = Set(report.findings.filter { $0.status == .missing }.map { $0.relativePath })

        for path in relativePaths where missing.contains(path) {
            guard var entry = manifest[path] else { continue }
            entry.trustState = .retired
            upserts.append(entry)
        }
        return upserts
    }
}
