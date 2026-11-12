# Clear path — blocked items

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

## Listed blockers (the only reasons to stop a WP)
- A change would need a file outside the WP's owned paths.
- A contract cannot be met without weakening an `AGENTS.md` invariant, a threshold or an existing test.
- WP-02's fix would need more than the three named production files.
- WP-10 cannot be done without editing `DeduplicateSessionStore`, `DeduplicationPlanner` or `DeduplicateExecutor`.
- Two failed review rounds on one WP.
- The session may not launch or see the app (G2 step 5, WP-13 step 4): log it and continue; this never blocks a commit.

## Open items
(none)
