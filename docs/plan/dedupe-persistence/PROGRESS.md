# Dedupe persistence — progress

Status: shipped in PR #267; all WPs and gates done. Not verified in the running app (the owner declined the computer-use prompt, D-DDP-118); hardware rows H-DDP-1 to H-DDP-5 are `todo-hardware`.

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
| WP-02 | Snapshot store and session-store integration | done | 0 | 4+15+29 pass | approve (round 1) | | |
| G1 | INV-29, coverage scope | done | 0 | suite 0, coverage 96.00% | n/a | | |
| WP-03 | UI and termination flush | done | 0 | 5+2+34+30 pass | approve (round 1) | | |
| WP-04 | Docs and string list | done | n/a | n/a (docs) | approve (round 1), accuracy nits applied | | |
| G2 | Final gate | done (app smoke not run) | xcode 0 | suite 0, coverage 96.00% | n/a | | verified: no |

## Outcome
- INV-29 appended to `AGENTS.md` at G1. G2: `cf_swift.sh suite` 0; `coverage` 0 (meaningful 96.00%, 19766/20589 after WP-05); `guards` 0 (14/14); `xcode` 0 (BUILD SUCCEEDED); `ui/build.sh` 0; 18 string keys added (+198/-0).
- Orchestrator found and fixed one restore flaw at WP-01 (D-DDP-101): content-only identity let a renamed member restore an approval with a never-made choice.
- WP-05 (added 2026-11-12, D-DDP-119, owner decision "fix before merge"): restored and dropped counts cover reviewed groups only. One existing expectation changed (`testCaptureThenRestoreIsIdentityOnUnchangedScan` restored count 4 to 2). No reviewer subagent; orchestrator read the restorer diff.

Per-step log condensed 2026-11-21 (failing-first output, reviewer rounds, Done-when commands are in git history before the docs cleanup).
