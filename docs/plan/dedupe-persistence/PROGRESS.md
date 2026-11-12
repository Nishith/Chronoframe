# Dedupe persistence — progress

Prefix `DDP`. Status values: todo, in-progress, review, done, blocked.

## Baseline
- 2026-11-11 branch `feature/dedupe-persistence` from `feature/nas-v1` @ 4079fb1 (D-DDP-01 revised).
- `docs/plan/next-half/bin/cf_swift.sh build` → exit 0
- `docs/plan/next-half/bin/cf_swift.sh suite` → exit 0

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch and baseline | done | 0 | suite 0 | n/a | | |
| WP-01 | Core model, keys, fingerprint, restorer | done | 0 | 6+14 pass | approve (round 1) + orchestrator fix D-DDP-101 | | INV-29/17/12 tags |
| WP-02 | Snapshot store and session-store integration | in-progress | | | | | |
| G1 | INV-29, coverage scope | todo | | | n/a | | |
| WP-03 | UI and termination flush | todo | | | | | |
| WP-04 | Docs and string list | todo | | | | | |
| G2 | Final gate | todo | | | n/a | | |

## Log
- 2026-11-11 WP-00: build 0, suite 0.
- 2026-11-11 WP-01: implementer compiled + tested (failing-first: `cannot find 'DeduplicateReviewKeys' in scope`). Reviewer approve round 1 (nits: memberCount redundant with key; duplicate identity multisets). Orchestrator read of the restorer found content-only identity lets a renamed member restore an approval with a never-made choice → D-DDP-101 fix by the same implementer (failing-first: 8 failures in 14 tests, e.g. `choices the user never made must not be approved`). Done-when: `cf_swift.sh test ChronoframeCoreDeduplicateReviewSnapshotTests` 0 (6); `… ChronoframeCoreDeduplicateReviewRestorerTests` 0 (14); `cf_swift.sh build` 0; `git diff --check` 0. Runtime decisions D-DDP-101…106.
