import Foundation

// MARK: - Guardian mirror planner (Phase 2)
//
// Pure single source of truth for the verified-mirror executor. Given a library
// integrity report (which files are currently verified against their trusted
// digest) and a probe of the mirror, it decides exactly what to copy — and,
// just as importantly, what NOT to touch.

public struct GuardianMirrorPlanner: Sendable {
    public init() {}

    public func plan(
        libraryRoot: String,
        mirrorRoot: String,
        libraryReport: GuardianIntegrityReport,
        mirrorObservations: [GuardianFileObservation]
    ) -> GuardianMirrorPlan {
        var mirrorByPath: [String: GuardianFileObservation] = [:]
        for observation in mirrorObservations where mirrorByPath[observation.relativePath] == nil {
            mirrorByPath[observation.relativePath] = observation
        }

        var copies: [GuardianMirrorCopy] = []
        var blocked: [GuardianMirrorBlock] = []
        var alreadyMirrored: [String] = []
        var coveredMirrorPaths = Set<String>()

        for finding in libraryReport.findings {
            switch finding.status {
            case .verified:
                // Only a verified primary (trusted + matching) may be a copy source.
                // Fail closed if the trusted identity is somehow absent.
                guard let trusted = finding.expectedIdentity else {
                    blocked.append(GuardianMirrorBlock(relativePath: finding.relativePath, reason: .primaryNotVerified))
                    continue
                }
                coveredMirrorPaths.insert(finding.relativePath)
                classifyVerified(
                    relativePath: finding.relativePath,
                    trusted: trusted,
                    mirror: mirrorByPath[finding.relativePath],
                    copies: &copies,
                    blocked: &blocked,
                    alreadyMirrored: &alreadyMirrored
                )

            case .missing:
                // The library file is gone — retain the mirror copy, never delete it.
                blocked.append(GuardianMirrorBlock(relativePath: finding.relativePath, reason: .primaryMissing))

            case .corrupt, .modified, .new, .dataless, .unreadable, .changedDuringScan:
                // Not currently verified: never copy over the mirror; preserve it.
                blocked.append(GuardianMirrorBlock(relativePath: finding.relativePath, reason: .primaryNotVerified))
            }
        }

        // Deletion retention: any mirror file without a verified library counterpart
        // is kept. A backup that silently propagated deletions would not be a backup.
        var retainedExtras: [String] = []
        for observation in mirrorObservations where !coveredMirrorPaths.contains(observation.relativePath) {
            retainedExtras.append(observation.relativePath)
        }
        retainedExtras.sort()

        copies.sort { $0.relativePath < $1.relativePath }
        blocked.sort { $0.relativePath < $1.relativePath }
        alreadyMirrored.sort()

        return GuardianMirrorPlan(
            libraryRoot: libraryRoot,
            mirrorRoot: mirrorRoot,
            copies: copies,
            blocked: blocked,
            retainedExtras: retainedExtras,
            alreadyMirrored: alreadyMirrored
        )
    }

    private func classifyVerified(
        relativePath: String,
        trusted: FileIdentity,
        mirror: GuardianFileObservation?,
        copies: inout [GuardianMirrorCopy],
        blocked: inout [GuardianMirrorBlock],
        alreadyMirrored: inout [String]
    ) {
        guard let mirror else {
            copies.append(GuardianMirrorCopy(relativePath: relativePath, expectedIdentity: trusted, kind: .create))
            return
        }

        switch mirror.outcome {
        case .hashed:
            if mirror.digest == trusted.digest && mirror.size == trusted.size {
                alreadyMirrored.append(relativePath)
            } else {
                let divergent = mirror.digest.map { FileIdentity(size: mirror.size, digest: $0) }
                copies.append(
                    GuardianMirrorCopy(
                        relativePath: relativePath,
                        expectedIdentity: trusted,
                        kind: .replaceDivergent,
                        divergentMirrorIdentity: divergent
                    )
                )
            }
        case .dataless, .unreadable, .changedDuringScan:
            // Cannot compare the mirror copy — leave it untouched rather than risk
            // overwriting a copy we could not verify.
            blocked.append(GuardianMirrorBlock(relativePath: relativePath, reason: .mirrorUnreadable))
        }
    }
}
