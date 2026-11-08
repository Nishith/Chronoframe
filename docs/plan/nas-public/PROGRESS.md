# NAS public — progress

Prefix `NASP`. Status values: todo, in-progress, review, done, blocked.

## Baseline
- 2026-11-08 HEAD `c82b369` (descendant of `4b992a4`), branch `feature/nas-v1`, no tracked modifications.
- `docs/plan/next-half/bin/cf_swift.sh build` → exit 0
- `docs/plan/next-half/bin/cf_swift.sh suite` → exit 0 (no failing shards)

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Baseline | done | 0 | suite 0 | n/a | | |
| WP-01 | Deduplicate refuses network folders | done | 0 | 4+2+17+33 pass | approve (round 1) | (this commit) | INV-12 tags |
| WP-02 | Internalize execute(queuedJobs:) | todo | | | | | safety-critical, one line |
| WP-03 | Validate timeout, keeper save failure | todo | | | | | |
| WP-04 | Comment fix, errata, docs, string lists | todo | | | | | |
| G2 | Strings, suite, guards, evidence | todo | | | n/a | | |

## Log
- 2026-11-08 WP-00: build 0, suite 0.
- 2026-11-08 WP-01: implementer compiled + tested (failing-first: `cannot find 'NASDeduplicateFolderRefusal' in scope`). Reviewer approve, round 1. Orchestrator safety read of `DeduplicateEngine.swift` diff: 3 hunks — `volumeClassifier` seam, scan refusal before `acquire`, commit refusal before lease re-acquire; every line traces to C-02; `networkAdvisory` untouched. Done-when: `cf_swift.sh test ChronoframeCoreNASDeduplicateFolderRefusalTests` 0 (4 tests); `… DeduplicateEngineNetworkRefusalTests` 0 (2); `… UserFacingErrorMessageTests` 0 (17); `… AppStateTests` 0 (33); `script/check_agents_invariants_have_tests.sh` 0; `cf_swift.sh build` 0; `git diff --check` 0. Runtime decisions D-NASP-101…103.
- D-NASP-05 note: `NativeDeduplicateEngine.networkAdvisory` is now unreachable for remote folders; left in place deliberately (surgical change).
