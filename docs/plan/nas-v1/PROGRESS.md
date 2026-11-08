# NAS v1 progress

Re-read this file, `NAS_AGENT_RULES.md` and `BLOCKED.md` after any context compaction before doing anything else.

## Plan authoring evidence (2026-11-07, before WP-00)
- `swift build --package-path ui --build-tests --disable-sandbox` with the local HOME/module-cache environment on `marketing/phase0-campaign-links` (634ec68): exit 0, "Build complete! (26.27 sec)".
- C-01 `NASModels.swift` extracted from CONTRACTS.md and type-checked with `xcrun swiftc -typecheck -swift-version 6` against that build's ChronoframeCore module: exit 0 with `-D DEBUG` and without it.
- `script/check_agents_invariants_have_tests.sh` on the relabeled invariants: exit 0, 26 of 26 covered.
- Not yet run on `feature/nas-v1`; WP-00 re-verifies there.

## Checkout at start
2026-11-07, branch `feature/nas-v1` already checked out at `e257003` (same commit as `codex/stable-invariant-ids`), so step 2 was a no-op. `git status --porcelain`:
```
?? docs/NAS_REQUIREMENTS.md
?? docs/NAS_REQUIREMENTS_REVIEW_LOG.md
?? docs/next-half-product-review-2026-11-07.md
?? docs/plan/
?? marketing/app-preview/
?? marketing/macapps-launch-post-2026-11.md
?? marketing/macapps-top-posts-2026-11-03.csv
?? marketing/product-video/
?? marketing/social-video/source-footage/
?? node_modules/
?? ui/.swiftpm/
?? ui/Sources/ChronoframeCore/NASModels.swift
```
`docs/plan/nas-v1/bin/nas_swift.sh` (mode 755) and `ui/Sources/ChronoframeCore/NASModels.swift` already existed; both were checked against the plan: the script matches WP-00 step 3 byte for byte, and `diff` of the C-01 code block against `NASModels.swift` printed nothing (identical). `.claude/agents/nas-*.md` match `claude-config/agents` (`diff -r` clean).

## Baseline
- `docs/plan/nas-v1/bin/nas_swift.sh build`: exit 0, 15 s ("Build complete! (13.63 sec)").
- `script/check_agents_invariants_have_tests.sh`: exit 0, <1 s, "All 26 safety invariants have at least one tagged test."
- Full sharded suite (`script/run_swift_test_suites.sh` with local HOME/module cache): exit 0, 86 s, 154 suites in 31 shards, no line reporting a non-zero failure count.

## Work packages

| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch, shared models, baseline | done | exit 0 | baseline suite exit 0 | n/a | (this commit) | build 0, invariants 0, suite 0 |
| WP-01 | Volume classifier, system containers | done | exit 0 | 12+2 pass | approve | (this commit) | classifier test 0, rules test 0, build 0 |
| WP-02 | Library identity, lease key | done | exit 0 | 18 pass | approve | (this commit) | identity test 0, build 0 |
| WP-03 | Metered file reader | done | exit 0 | 13 pass | approve | (this commit) | reader test 0, build 0; FileIdentityHasher.swift diff empty |
| WP-04 | Assessment store | done | exit 0 | 12 pass | approve | (this commit) | store test 0, build 0; follow-up: non-ELOOP anchor errors surface as POSIX NSError (WP-10 must map) |
| WP-05 | Assessment scanner | todo | | | | | |
| WP-06 | Remote copy policy (safety-critical) | todo | | | | | orchestrator diff review required |
| WP-07 | Journal policy, share lease (safety-critical) | todo | | | | | orchestrator diff review required |
| WP-08 | CLI remote refusal | todo | | | | | |
| G2 | Invariants 27–28, coverage, full suite | todo | | | n/a | | |
| WP-09 | Probe, parity, corpus tool | todo | | | | | |
| WP-10 | App Core services, workspace store | todo | | | | | |
| WP-11 | NAS Library UI | todo | | | | | |
| WP-12 | Documentation | todo | | | | | |
| G3 | Final gate and report | todo | | | n/a | | |

Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Log
(Append one line per event: date, WP, what happened, command and exit code.)
- 2026-11-07 WP-00: verified branch, script and C-01 file; build exit 0; invariant guard exit 0; full suite exit 0.
- 2026-11-07 WP-01: implementer compiled+tested (failing-first: compile error, missing NASSystemContainerRules); reviewer approve (round 1); orchestrator: nas_swift.sh test ChronoframeCoreNASVolumeClassifierTests exit 0 (12 tests), test ChronoframeCoreNASSystemContainerRulesTests exit 0 (2 tests), build exit 0.
- 2026-11-07 WP-02: implementer compiled+tested (failing-first: cannot find NASLibraryIdentity); reviewer approve (round 1); orchestrator: nas_swift.sh test ChronoframeCoreNASLibraryIdentityTests exit 0 (18 tests: 17 named + testZeroShareRootFileIDIsNotCompared), build exit 0.
- 2026-11-07 WP-03: implementer compiled+tested (failing-first: cannot find type NASMeteredFileReader); reviewer approve (round 1; non-blocking: growth test simulates via smaller fstat size rather than an injected oversized read); orchestrator: nas_swift.sh test ChronoframeCoreNASMeteredFileReaderTests exit 0 (13 tests), build exit 0.
- 2026-11-07 WP-04: implementer compiled+tested (failing-first: cannot find type NASAssessmentStore); reviewer approve (round 1; non-blocking: raw NSError from openAnchor for e.g. EACCES, same as OrganizerDatabase; extra behaviors untested); orchestrator: nas_swift.sh test ChronoframeCoreNASAssessmentStoreTests exit 0 (12 tests), build exit 0.
