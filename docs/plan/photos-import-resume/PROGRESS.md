# Photos import resume — progress

Prefix `PIR`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Baseline
(WP-00 records `cf_swift.sh build` and `cf_swift.sh suite` exit codes and the branch's base commit here.)

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch and baseline | todo | | | n/a | | |
| WP-01 | Checkpoint model and store | todo | | | | | |
| WP-02 | Executor events, reserved names, free-space floor | todo | | | | | safety-critical: orchestrator diff review required |
| WP-03 | Service forwards PhotoKit progress | todo | | | | | safety-critical; no unit test (PhotoKit) |
| WP-04 | Store: checkpoint, cancel, resume, purge policy | todo | | | | | |
| G1 | Coverage scope, suite, invariants | todo | | | n/a | | |
| WP-05 | Photos UI | todo | | | | | |
| WP-06 | App wiring | todo | | | | | |
| WP-07 | Documentation | todo | | | | | |
| G2 | Final gate | todo | | | n/a | | verified: claim only with screenshot path |

## Log
(one line per step: date, WP, command, exit code, or decision/blocker reference)
