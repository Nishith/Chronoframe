# Edit preservation — progress

Prefix `EPR`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Baseline
- 2026-11-27 branch `feature/edit-preservation-impl` from `origin/main` @ f1c5540 (#298), plan fix 10ede42, owner answers 8d13bd5 (D-EPR-01).
- `docs/plan/next-half/bin/cf_swift.sh build` → exit 0 (.tmp/epr-baseline-build.log)
- `docs/plan/next-half/bin/cf_swift.sh suite` → exit 0, 2425 test cases passed, 0 failures (.tmp/epr-baseline-suite.log)
- `script/check_agents_invariants_have_tests.sh` → exit 0, "All 29 safety invariants have at least one tagged test"

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch and baseline | done | build 0 | suite 0, inv 0 | n/a | 10ede42, 8d13bd5 | B-1 resolved |
| WP-01 | Copy and docs for what import preserves | in-progress | | | | | |
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
- 2026-11-27 kickoff: owner answers recorded as D-EPR-01, 05, 07–11 approved and D-EPR-13…17; D-EPR-18 notes stale citations. Baseline re-run on the impl branch, all exit 0.
