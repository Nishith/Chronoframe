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
