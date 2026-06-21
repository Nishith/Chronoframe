# Chronoframe Production-Readiness Certification

Certification date: 2026-06-20
Candidate branch: `codex/production-readiness-remediation`
Baseline: `origin/main` at `081e00f`

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
| App-layer test guard | PENDING | The guard compares committed PR diffs and reported “no commits beyond origin/main”; affected App/AppCore behavior has regression tests, but rerun after commits exist |
| `git diff --check` | PASS | No whitespace errors on 2026-06-20 |
| Meaningful Swift coverage ≥95% | PASS | 95.51% (14,581 / 15,267 meaningful lines), including destination locking, mutation recovery, and bounded Live Photo metadata |
| Warning-clean Xcode Debug build | PASS | Universal macOS Debug build succeeded with `CODE_SIGNING_ALLOWED=NO`; no compiler warnings |
| macOS UI/accessibility suite | PASS | 21/21 tests passed, including all-scenario accessibility audit; xcresult: `.tmp/ChronoframeXcodeTestDerivedData/Logs/Test/Test-Chronoframe-2026.06.20_23-09-37--0700.xcresult` |
| CI-like arm64 Swift build | PASS | `swift build --package-path ui --product ChronoframeApp --arch arm64 --disable-index-store` |
| CodeQL and all hosted CI checks | PENDING | Local CodeQL build path passes; hosted analysis requires a pushed PR/CI run |

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
| Candidate-index recall | 100% | PENDING |
| Pair recall | 100% | PENDING |
| Pair precision | ≥99% | PENDING |
| Hard-negative false positives | ≤0.1% | PENDING |
| Warm/cold stability | identical decisions | PENDING |

The repository does not contain the labeled video corpus, so this gate cannot be certified from a clean checkout.

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
