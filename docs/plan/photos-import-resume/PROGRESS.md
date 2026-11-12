# Photos import resume — progress

Prefix `PIR`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Baseline
- 2026-11-12 branch `feature/photos-import-resume` from `feature/dedupe-persistence` @ 97fc546 (D-PIR-01 revised).
- `docs/plan/next-half/bin/cf_swift.sh build` → exit 0
- `docs/plan/next-half/bin/cf_swift.sh suite` → exit 0

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch and baseline | done | 0 | suite 0 | n/a | | |
| WP-01 | Checkpoint model and store | done | 0 | 9+12 pass | approve (round 1) | | D-PIR-101 |
| WP-02 | Executor events, reserved names, free-space floor | in-progress | | | | | safety-critical: orchestrator diff review required |
| WP-03 | Service forwards PhotoKit progress | todo | | | | | safety-critical; no unit test (PhotoKit) |
| WP-04 | Store: checkpoint, cancel, resume, purge policy | todo | | | | | |
| G1 | Coverage scope, suite, invariants | todo | | | n/a | | |
| WP-05 | Photos UI | todo | | | | | |
| WP-06 | App wiring | todo | | | | | |
| WP-07 | Documentation | todo | | | | | |
| G2 | Final gate | todo | | | n/a | | verified: claim only with screenshot path |

## Log
- 2026-11-12 WP-00: build 0, suite 0.
- 2026-11-12 WP-01: implementer stopped on a plan gap (`MediaKind` not `Codable`) → D-PIR-101, same implementer continued. Compiled + tested (failing-first: `cannot find type 'PhotosImportCheckpoint' in scope`). Reviewer approve round 1 (nits: hint-merge collision policy unstated; cosmetic doc comment). Done-when: `cf_swift.sh test PhotosImportCheckpointTests` 0 (9); `… PhotosExportExecutorTests` 0 (12); `cf_swift.sh build` 0; `git diff --check` 0.
