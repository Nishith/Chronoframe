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
| WP-01 | Core model, keys, fingerprint, restorer | in-progress | | | | | INV-29/17/12 tags |
| WP-02 | Snapshot store and session-store integration | todo | | | | | |
| G1 | INV-29, coverage scope | todo | | | n/a | | |
| WP-03 | UI and termination flush | todo | | | | | |
| WP-04 | Docs and string list | todo | | | | | |
| G2 | Final gate | todo | | | n/a | | |

## Log
- 2026-11-11 WP-00: build 0, suite 0.
