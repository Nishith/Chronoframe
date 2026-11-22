# Photos import resume — progress

Status: shipped in PR #268; all WPs and gates done. Not verified in the running app (B-1: screen access declined); hardware rows H-PIR-1 to H-PIR-6 are `todo-hardware`.

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
| G1 | Coverage scope, suite, invariants | done | 0 | suite 0, coverage 96.06% | n/a | | |
| WP-05 | Photos UI | done | 0 | 4+3+2 pass | approve (round 1), nits applied D-PIR-115 | | D-PIR-115…116 |
| WP-06 | App wiring | done | 0 | 38+12 pass | approve (round 1) | | D-PIR-117…119 |
| WP-07 | Documentation | done | n/a | n/a (docs) | changes required (round 1) → reviewer's replacement text applied; not re-reviewed | | |
| G2 | Final gate | done (app smoke not run, B-1) | xcode 0 | suite 0, coverage 96.02% | n/a | | verified: no |

## Outcome
- G1: `cf_swift.sh suite` 0; `coverage` 0 (meaningful 96.06%); invariants 0 (29 tagged); `check_photos_import_readonly.sh` 0. G2: `suite` 0, `coverage` 0 (meaningful 96.02%, 19849/20672), `guards` 0 (14/14), `xcode` 0, `ui/build.sh` 0. Strings: 8 keys in `Localizable.xcstrings`, 2 in `LocalizableCore.xcstrings` (+110/-0). `AGENTS.md` staging sentence replaced (D-PIR-120).
- First G2 guard run failed `check_detail_views_set_navigation_title` because the `PhotosImportView(` call spanned lines; fixed by keeping `appState:` on the call's first line.
- WP-03 (PhotoKit progress forwarding) has no unit test possible; covered by hardware row H-PIR-1.
- WP-07 docs: reviewer's replacement text applied without a second review round.

Per-step log condensed 2026-11-21 (failing-first output, reviewer rounds, Done-when commands are in git history before the docs cleanup).
