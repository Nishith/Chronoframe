# Chronoframe Production-Readiness Certification

Certification date: 2026-06-20
Candidate branch: `codex/production-readiness-remediation`
Baseline: `origin/main` at `081e00f`
Implementation evidence commit: `80ff492`

## Release decision

**BLOCKED — do not ship this candidate until every mandatory row below is PASS.**

This report intentionally distinguishes implementation evidence from environment-backed certification. A missing credential, corpus, external drive, or capacity fixture is not treated as a pass.

## Certification environment

| Field | Value |
|---|---|
| Hardware | Mac mini, Apple M4 Pro, 14 cores, 64 GB RAM |
| macOS | 26.5.1 (25F80) |
| Xcode | 26.5 (17F42) |
| Workspace volume free space | 454 GiB at certification start |

## Automated gates

| Gate | Status | Evidence |
|---|---|---|
| Clean `origin/main` baseline | PASS | 941 Swift tests passed before remediation began |
| Full SwiftPM suite after remediation | PASS | `script/run_swift_test_suites.sh`; every discovered XCTest suite passed in five-suite shards |
| Invariant guard | PASS | All 19 `AGENTS-INVARIANT` bullets have tagged tests |
| Animation guard | PASS | No raw reduce-motion-bypassing view animations |
| App-layer test guard | PASS | Hosted PR run `27896063597` passed against the committed PR diff |
| `git diff --check` | PASS | No whitespace errors on 2026-06-20 |
| Meaningful Swift coverage ≥95% | PASS | 95.51% (14,581 / 15,267 meaningful lines), including destination locking, mutation recovery, and bounded Live Photo metadata |
| Warning-clean Xcode Debug build | PASS | Universal macOS Debug build succeeded with `CODE_SIGNING_ALLOWED=NO`; no compiler warnings |
| macOS UI/accessibility suite | PASS | 21/21 local tests passed; hosted UI tests and the accessibility audit also passed in run `27896063597` |
| CI-like arm64 Swift build | PASS | `swift build --package-path ui --product ChronoframeApp --arch arm64 --disable-index-store` |
| Hosted CI checks | PASS | Run `27896063597`: SwiftPM, meaningful coverage, Xcode build, UI tests, accessibility audit, release archive smoke, whitespace, invariant, animation, and app-layer guards all passed |
| Hosted CodeQL | PENDING | Run `27896063603` is analyzing Swift for implementation commit `80ff492`; do not mark PASS until the hosted conclusion is success |

## Implemented hardening evidence

- `DestinationOperationLock` serializes app, CLI, App Intent, scan, commit,
  revert, reorganize, and recovery mutations across processes.
- `DeduplicateScanSnapshot` and `DeduplicationPlan` keep commit preview and
  executor scope immutable and content-verified.
- Deduplicate uses same-directory quarantine, `O_NOFOLLOW` descriptor hashing,
  pair-unit rollback, and a schema-v2 append-only recovery journal.
- `MutationRecoveryCoordinator` reconciles organize, dedupe, and reorganize
  state without treating sandbox denial or disconnected volumes as absence.
- Live Photo movie metadata work is bounded to four workers, has per-item
  deadlines and a timeout circuit breaker, and cancels promptly without
  blocking the cooperative executor in its regression fixture.
- Focused fault-injection, stale-identity, lock-race, process-boundary,
  recovery-state, and user-facing failure-copy tests are present and covered by
  the invariant and app-layer guards.

## Developer ID distribution

| Gate | Status | Evidence / blocker |
|---|---|---|
| Developer ID identity available | BLOCKED | Keychain contains Apple Development and Apple Distribution identities, but no `Developer ID Application` identity required by the Developer ID archive flow |
| Team ID configured | BLOCKED | `CHRONOFRAME_TEAM_ID` is unset |
| Notary profile configured | BLOCKED | `CHRONOFRAME_NOTARY_PROFILE` is unset |
| Hardened-runtime archive | PENDING | `ui/archive.sh` after credentials are installed |
| Notarization accepted | PENDING | Preserve `notarytool` submission ID and result |
| Stapling validation | PENDING | Preserve `stapler validate` output |
| Gatekeeper acceptance | PENDING | Preserve `spctl --assess --type execute --verbose=4` output |
| Signed artifact SHA-256 | PENDING | Preserve `shasum -a 256 <artifact>` output |

## Signed-sandbox matrix

Run against the exact signed/stapled candidate, not an ad hoc build.

| Scenario | Internal APFS | External APFS | External exFAT | Result/evidence |
|---|---:|---:|---:|---|
| Bookmark restore after relaunch | PENDING | PENDING | PENDING | |
| Organize copy + verification | PENDING | PENDING | PENDING | |
| Dedupe Trash + revert | PENDING | PENDING | PENDING | |
| Forced termination after every journal boundary | PENDING | PENDING | PENDING | |
| Drive disconnect during pending recovery | N/A | PENDING | PENDING | |
| Drive reconnect and idempotent recovery | N/A | PENDING | PENDING | |

## Video corpus certification

Corpus details and commit must be recorded with the output from:

```bash
script/video_calibration/run_calibration.sh --corpus <local-corpus> --explode-underscore
```

| Metric | Required | Candidate result |
|---|---:|---:|
| Candidate-index recall | 100% | PASS — 100% |
| Pair recall | 100% | PASS — 100% |
| Pair precision | ≥99% | PASS — 99.1% |
| Hard-negative false positives | ≤0.1% | PASS — 0.1% |
| Warm/cold stability | identical decisions | PASS |

Calibration ran on 2026-06-20 against a local labeled corpus (5 duplicate groups × 7 variants plus 12 hard negatives) using `script/video_calibration/run_calibration.sh --explode-underscore`. The corpus remains local-only, so a clean checkout can reproduce the tooling but not the exact evidence. The chosen thresholds and frame-tolerance rationale are recorded in `AGENTS.md`; a larger hard-negative set remains desirable for stronger threshold confidence.

## 100,000-file / 1-TB certification

The workspace volume had only 454 GiB free, so a real 1-TB corpus could not be constructed here. Sparse files are not acceptable evidence for direct sequential BLAKE2b throughput or filesystem behavior.

| Metric | Required | Candidate result |
|---|---:|---:|
| Dataset | 100,000 files / 1 TB real allocated media | BLOCKED — fixture/storage unavailable |
| Peak RSS | ≤1.5 GB | PENDING |
| Unchanged warm scan | ≤5 minutes | PENDING |
| Cold hashing throughput | ≥70% of direct sequential BLAKE2b | PENDING |
| Cold/warm correctness | no divergence | PENDING |
| Cancellation | <1 second outside active filesystem syscall | PENDING |

Record corpus generation method, filesystem/volume model, direct-hash baseline command, Chronoframe commands, `/usr/bin/time -l` output, and correctness-manifest checksums.

## Required final sign-off

- Engineering owner: PENDING
- Security/privacy review: PENDING
- Accessibility audit: PASS — automated baseline-enforced scenario audit; human release-owner sign-off remains pending
- Release owner: PENDING
- Final candidate commit and artifact checksum: PENDING
