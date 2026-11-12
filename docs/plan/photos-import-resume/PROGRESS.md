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
| WP-02 | Executor events, reserved names, free-space floor | done | 0 | 20 pass | approve (round 1) + orchestrator diff read | | safety-critical; D-PIR-102…104 |
| WP-03 | Service forwards PhotoKit progress | done | 0 | not tested (PhotoKit) | orchestrator diff read (no subagent review) | | safety-critical; H-PIR-1 covers it |
| WP-04 | Store: checkpoint, cancel, resume, purge policy | done | 0 | 17+13 pass | approve (round 1) + orchestrator fixes D-PIR-105/106 | | D-PIR-105…114 |
| G1 | Coverage scope, suite, invariants | in-progress | | | n/a | | |
| WP-05 | Photos UI | todo | | | | | |
| WP-06 | App wiring | todo | | | | | |
| WP-07 | Documentation | todo | | | | | |
| G2 | Final gate | todo | | | n/a | | verified: claim only with screenshot path |

## Log
- 2026-11-12 WP-00: build 0, suite 0.
- 2026-11-12 WP-01: implementer stopped on a plan gap (`MediaKind` not `Codable`) → D-PIR-101, same implementer continued. Compiled + tested (failing-first: `cannot find type 'PhotosImportCheckpoint' in scope`). Reviewer approve round 1 (nits: hint-merge collision policy unstated; cosmetic doc comment). Done-when: `cf_swift.sh test PhotosImportCheckpointTests` 0 (9); `… PhotosExportExecutorTests` 0 (12); `cf_swift.sh build` 0; `git diff --check` 0.
- 2026-11-12 WP-02: implementer compiled + tested (failing-first: `cannot find type 'PhotosExportEvent' in scope`; `extra argument 'onEvent' in call`). Reviewer approve round 1 (nits: no test for the no-original-resource `.assetFailed` emit; pre-existing filename collision classes, D-PIR-104). Orchestrator read of the full `PhotosExportExecutor.swift` diff: every hunk traces to C-02 rules 1–6, C-03 or D-PIR-11/102; `PhotosExportStop` is thrown outside the do/catch so no rollback runs; `CancellationError` branch and `rollBack` untouched; receipt construction untouched. Done-when: `cf_swift.sh test PhotosExportExecutorTests` 0 (20); `script/check_photos_import_readonly.sh` 0; `cf_swift.sh build` 0; `git diff --check` 0.
- 2026-11-12 WP-03: implementer compiled; no unit test possible. Orchestrator read the whole diff (+9/−0): one forwarding two-argument method, the original body under the three-argument signature, one `options.progressHandler` line after `isNetworkAccessAllowed`; matches C-03 verbatim, so the reviewer subagent was not spent on it. Done-when: `cf_swift.sh build` 0; `script/check_photos_import_readonly.sh` 0; `git diff --stat` only this file; `git diff --check` 0.
- 2026-11-12 WP-04: implementer compiled + tested (failing-first: `cannot find type 'PhotosPreparationProgress' in scope`; `no member 'cancelPreparation'`). Orchestrator read of `PhotosImportStore.swift` found crash leftovers could survive a resume and reach the transfer pipeline → D-PIR-105 fix by the same implementer (failing-first: staging held `.x.photoexport.tmp` and `b.heic` after resume). Reviewer approve round 1 (nits: stale destination match at resume; `try?` checkpoint saves can overstate "kept"; late progress event cosmetic; nil label after relaunch). Stale-match nit closed as D-PIR-106 (failing-first: `XCTAssertNil failed: "PhotosImportContext(importID: …"`); that follow-up was verified by the orchestrator's test run, not re-reviewed by the subagent. Done-when: `cf_swift.sh test PhotosImportResumeTests` 0 (17); `… PhotosImportStoreTests` 0 (13); `cf_swift.sh build` 0; `script/check_no_await_in_xctassert.sh` 0; `git diff --check` 0.
