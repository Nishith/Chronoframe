import Foundation

// MARK: - Guardian integrity classifier (Phase 1)
//
// The pure, deterministic half of a scrub: it takes a manifest snapshot and the
// raw observations produced by `GuardianLibraryProbe` and classifies every file.
// It performs no I/O, so it is fully unit-testable and is the coverage-gated unit.
//
// Trust rule enforced here: a mismatch is only ever judged `corrupt`/`modified`
// against a *trusted* (or already-flagged) baseline. This classifier never returns
// a `trusted` trust state that the manifest did not already hold — it can only keep
// or demote trust, never advance it. Promotion to `trusted` is an explicit,
// user-driven (or receipt-derived) step elsewhere.

public struct GuardianIntegrityClassifier: Sendable {
    /// Files whose recorded and observed mtime differ by less than this are treated
    /// as unchanged in time — the same tolerance `FileIdentityHasher` uses.
    public static let modificationTimeTolerance: TimeInterval = 0.001

    public init() {}

    /// Classify one scan. `manifest` is keyed by canonical (NFC) relative path.
    public func classify(
        libraryRoot: String,
        manifest: [String: GuardianManifestEntry],
        observations: [GuardianFileObservation],
        partialScan: Bool,
        now: Date = Date()
    ) -> GuardianIntegrityReport {
        var findings: [GuardianIntegrityFinding] = []
        findings.reserveCapacity(observations.count)
        var observedKeys = Set<String>()

        for observation in observations {
            observedKeys.insert(observation.relativePath)
            findings.append(finding(for: observation, entry: manifest[observation.relativePath]))
        }

        // Manifest entries with no observation are missing on disk. A `retired`
        // entry is an acknowledged deletion, so it is not re-flagged. During a
        // partial scan a subtree may simply not have been read, so absence is not
        // reported as `missing` — that would be a false alarm.
        if !partialScan {
            for (key, entry) in manifest where !observedKeys.contains(key) {
                guard entry.trustState != .retired else { continue }
                findings.append(
                    GuardianIntegrityFinding(
                        relativePath: key,
                        status: .missing,
                        trustState: entry.trustState == .trusted ? .changedPendingReview : entry.trustState,
                        expectedIdentity: entry.identity,
                        observedIdentity: nil
                    )
                )
            }
        }

        findings.sort { $0.relativePath < $1.relativePath }
        return GuardianIntegrityReport(
            generatedAt: now,
            libraryRoot: libraryRoot,
            findings: findings,
            partialScan: partialScan
        )
    }

    private func finding(
        for observation: GuardianFileObservation,
        entry: GuardianManifestEntry?
    ) -> GuardianIntegrityFinding {
        let expectedIdentity = entry?.identity

        switch observation.outcome {
        case .dataless:
            return GuardianIntegrityFinding(
                relativePath: observation.relativePath,
                status: .dataless,
                trustState: entry?.trustState ?? .unprotected,
                expectedIdentity: expectedIdentity,
                observedModificationTime: observation.modificationTime
            )
        case .unreadable:
            return GuardianIntegrityFinding(
                relativePath: observation.relativePath,
                status: .unreadable,
                trustState: entry?.trustState ?? .unprotected,
                expectedIdentity: expectedIdentity,
                observedModificationTime: observation.modificationTime
            )
        case .changedDuringScan:
            return GuardianIntegrityFinding(
                relativePath: observation.relativePath,
                status: .changedDuringScan,
                trustState: entry?.trustState ?? .unprotected,
                expectedIdentity: expectedIdentity,
                observedModificationTime: observation.modificationTime
            )
        case .hashed:
            let observedIdentity = observation.digest.map { FileIdentity(size: observation.size, digest: $0) }
            guard let entry else {
                // On disk, not in the manifest: new and not yet known-good.
                return GuardianIntegrityFinding(
                    relativePath: observation.relativePath,
                    status: .new,
                    trustState: .unprotected,
                    expectedIdentity: nil,
                    observedIdentity: observedIdentity,
                    observedModificationTime: observation.modificationTime
                )
            }
            return hashedFinding(observation: observation, entry: entry, observedIdentity: observedIdentity)
        }
    }

    private func hashedFinding(
        observation: GuardianFileObservation,
        entry: GuardianManifestEntry,
        observedIdentity: FileIdentity?
    ) -> GuardianIntegrityFinding {
        let matchesBaseline = observation.digest == entry.digest

        let observedModificationTime = observation.modificationTime

        switch entry.trustState {
        case .unprotected, .retired:
            // No trusted baseline (or an acknowledged deletion that reappeared):
            // report as not-yet-protected rather than corruption.
            return GuardianIntegrityFinding(
                relativePath: observation.relativePath,
                status: .new,
                trustState: .unprotected,
                expectedIdentity: entry.identity,
                observedIdentity: observedIdentity,
                observedModificationTime: observedModificationTime
            )
        case .trusted:
            if matchesBaseline {
                return GuardianIntegrityFinding(
                    relativePath: observation.relativePath,
                    status: .verified,
                    trustState: .trusted,
                    expectedIdentity: entry.identity,
                    observedIdentity: observedIdentity,
                    observedModificationTime: observedModificationTime
                )
            }
            return GuardianIntegrityFinding(
                relativePath: observation.relativePath,
                status: corruptionStatus(observation: observation, entry: entry),
                trustState: .changedPendingReview,
                expectedIdentity: entry.identity,
                observedIdentity: observedIdentity,
                observedModificationTime: observedModificationTime
            )
        case .changedPendingReview:
            // Already flagged: keep it flagged until the user acts. Even if the bytes
            // now match the recorded baseline again, trust is not re-advanced here.
            let status: GuardianIntegrityStatus = matchesBaseline
                ? .verified
                : corruptionStatus(observation: observation, entry: entry)
            return GuardianIntegrityFinding(
                relativePath: observation.relativePath,
                status: status,
                trustState: .changedPendingReview,
                expectedIdentity: entry.identity,
                observedIdentity: observedIdentity,
                observedModificationTime: observedModificationTime
            )
        }
    }

    /// Silent corruption keeps size and mtime; anything else looks like an edit.
    private func corruptionStatus(
        observation: GuardianFileObservation,
        entry: GuardianManifestEntry
    ) -> GuardianIntegrityStatus {
        let sizeUnchanged = observation.size == entry.size
        let mtimeUnchanged = abs(observation.modificationTime - entry.modificationTime) < Self.modificationTimeTolerance
        return (sizeUnchanged && mtimeUnchanged) ? .corrupt : .modified
    }
}
