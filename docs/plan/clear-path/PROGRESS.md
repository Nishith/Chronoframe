# Clear path — progress

Prefix `CLP`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes. Report compiled, tested and verified separately.

## Baseline
- 2026-11-12: branch `feature/clear-path` from `feature/photos-import-resume` @ 5c72052; plan commit c3f23b4; `cf_swift.sh build` exit 0; `cf_swift.sh suite` exit 0.

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch, baseline, plan commit | done | build 0 | suite 0 | n/a | c3f23b4 | |
| WP-01 | Core titles and tab order | done | build 0 | ChronoframeCoreOrganizeNavigationTests 0 (6); DeduplicateAccessibilityTextTests 0 (28); DeduplicateStatusViewTests 0 (30) | approved | (this commit) |  |
| WP-02 | Staged sources checked against destination | in-progress | | | | | safety-critical (INV-21); orchestrator diff read required |
| WP-03 | Folder list model, store, picker | todo | | | | | |
| WP-04 | Setup coordinator, bookmarks, forwarders | todo | | | | | |
| G1 | Coverage scope, suite, invariants | todo | | | n/a | | |
| WP-05 | Setup screen | todo | | | | | |
| WP-06 | Folder layout in Setup | todo | | | | | |
| WP-07 | Organize chrome, toolbar, prompts | todo | | | | | |
| WP-08 | Preview & Copy workspace | todo | | | | | |
| WP-09 | Next step after a copy | todo | | | | | |
| WP-10 | Deduplicate lanes and vocabulary | todo | | | | | no Core/AppCore diff allowed |
| WP-11 | Health | todo | | | | | |
| WP-12 | UI-test scenarios and string lists | todo | | | | | |
| WP-13 | XCUITest expectations and baseline | todo | | | n/a | | orchestrator |
| WP-14 | Documentation | todo | | | | | |
| G2 | Final gate | todo | | | n/a | | verified: |

## Log
(one line per step: date, WP, what ran, exit codes, failing-first evidence, reviewer verdict)
- 2026-11-12 WP-00: branch created, plan committed c3f23b4, build exit 0, suite exit 0. Owner answers: app launch for G2 smoke allowed; local XCUITest lane allowed.
- 2026-11-12 WP-01: failing-first: compile error (no member displayOrder); Done-when all exit 0; reviewer approved; existing tests updated: DeduplicateAccessibilityTextTests:215, DeduplicateStatusViewTests:466 (Near duplicates → Look-alikes).
