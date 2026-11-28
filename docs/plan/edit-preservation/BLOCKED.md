# Edit preservation — blocked items

Rule: log it, then continue with the next independent WP. Only Nishith marks an item resolved.

## Template
### B-<n> — <short title>
- **WP:** <id>
- **Command:** `<exact command>`
- **Error:** <exact text>
- **Tried:** <what, in order>
- **Options:** 1) … 2) …
- **Recommendation:** <one option, one sentence>
- **Status:** open | resolved (<commit or decision>)

## Open items
### B-1 — Checkout has uncommitted tracked changes
- **WP:** WP-00
- **Command:** `git status --short`
- **Error:** on 2026-11-15 the session snapshot listed many modified tracked files (AGENTS.md, DECISIONS.md, `ui/Chronoframe.xcodeproj/project.pbxproj`, dozens of `ui/Sources/ChronoframeApp/**` files, `Localizable.xcstrings`, among others). Unrelated work in progress.
- **Tried:** nothing; WP-00 has not run.
- **Options:** 1) Owner commits or stashes that work before WP-00. 2) Run this plan in a separate clone at `main`. 3) Owner approves a worktree (note the global rule about Antigravity: remove the worktree and unset `extensions.worktreeConfig` when finished).
- **Recommendation:** Option 2, because several of those files (AGENTS.md, Localizable.xcstrings, the Photos views) are also owned by WPs here and would mix with unrelated edits.
- **Status:** resolved (2026-11-16: tracked tree was clean when WP-00 ran; branch cut from origin/main @ 5eee91f)

### B-2 — Companion follow-ups outside this plan's owned paths (non-blocking)
- **WP:** WP-03 / WP-04
- **Command:** read-only spike (D-EPR-103…111)
- **Error:** none at runtime. Three gaps for appended-form (`photo.jpg.xmp`) companions need changes the plan does not allow: (1) `TransferExecutor.chronoframeTmpPattern` (`TransferExecutor.swift:214-216`) does not match `2024-03-01_007.jpg.xmp.<UUID>.tmp`, so a crash mid-copy leaves that temp file behind; (2) `ReorganizeExecutor.parseFileBucket` (`:583-613`) counts `…_007.jpg.xmp` as unrecognized and leaves it in place when its photo moves; (3) the execution-time `_collision_N` rename can separate a companion from its owner (D-EPR-111). (4) If an owner's copy fails verification while its companion copies, the companion sits alone at the owner's planned name; a later run may give the owner another sequence number. No overwrite or deletion results. Fix: executor skips a companion whose owner job did not finalize.
- **Tried:** confirmed none needs a cache or receipt schema change and none breaks an AGENTS.md invariant (no overwrite, no deletion); WP-04 proceeds.
- **Options:** 1) Follow-up PR: widen the tmp regex to `\.[a-zA-Z0-9]+(?:\.[a-zA-Z0-9]+)?` before the UUID, and teach `parseFileBucket` to strip a known companion extension first. 2) Map appended-form companions to stem form in the destination (contradicts C-03.4 and breaks darktable's naming).
- **Recommendation:** Option 1 as a small follow-up PR with tests, since both are one-line pattern changes in safety-adjacent files that deserve their own review.
- **Status:** open

### B-3 — Review panes can label a protected edited variant "Suggested for removal" (non-blocking)
- **WP:** WP-08
- **Command:** cf-reviewer read of `ClusterListPane.swift:391`, `ClusterDetailPane.swift:302/390/602/618`, `RapidTriageView.swift:168-169`
- **Error:** none at runtime. These views fall back to `.delete` for any non-keeper with no explicit decision. After a scan the store pre-sets `.keep` for protected variants, so the label only shows after `resetReview`. Display-only: the planner (INV-31) still keeps the file and the commit footer is correct.
- **Tried:** confirmed outside WP-08's owned paths (D-EPR-122 covers the store only); not folded in.
- **Options:** 1) Follow-up PR routing those panes through `DedupeDecisions.keepersForCluster` (or a shared effective-decision helper) with an App test. 2) Leave as is.
- **Recommendation:** Option 1, a small follow-up so the review UI never contradicts the plan.
- **Status:** open
