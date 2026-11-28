# Edit preservation — progress

Prefix `EPR`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Baseline
- 2026-11-16 branch `feature/edit-preservation` from `origin/main` @ 5eee91f (#275); local `main` was 2 commits behind, only the new branch was fast-forwarded (D-EPR-01).
- `docs/plan/next-half/bin/cf_swift.sh build` → "Build complete" (numeric exit hidden by `time`)
- `docs/plan/next-half/bin/cf_swift.sh suite` → exit 0, no failures in log (.tmp/epr-baseline-suite.log)
- `script/check_agents_invariants_have_tests.sh` → exit 0, "All 29 safety invariants have at least one tagged test"

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch and baseline | done | build ok | suite 0, inv 0 | n/a | | B-1 resolved |
| WP-01 | Copy and docs for what import preserves | todo | | | | | |
| WP-02 | `.aae` is a dedupe sidecar (INV-14) | todo | | | | | safety-critical |
| WP-03 | Spike: companion plug-in points | todo | | | n/a | | answers go to D-EPR-101… |
| WP-04 | Organize copies companions | todo | | | | | safety-critical |
| G1 | Gate after companions | todo | | | n/a | | |
| WP-05 | Export model, role, checkpoint fields | todo | | | | | |
| WP-06 | Executor and service export edited still | todo | | | | | safety-critical; INV-22 wording |
| WP-07 | Import UI, summary, history copy | todo | | | | | |
| WP-08 | Dedupe protects edited variants (INV-31) | todo | | | | | safety-critical |
| G2 | Final gate | todo | | | n/a | | |

## Log
- 2026-11-15 plan written; owner approved INV-22 widening and INV-31. D-EPR-06 (stem link) defaulted pending owner answer.
- 2026-11-27 merged `origin/main` @ 4cabd27 (#297) into the branch; baseline above is from 5eee91f, so re-run the WP-00 commands at kickoff. Invariant renumbered INV-30 → INV-31 (D-EPR-12).
- 2026-11-27 owner approved D-EPR-06: link edited variants by file name (`<stem>-edited.<ext>`). No open owner questions remain.
