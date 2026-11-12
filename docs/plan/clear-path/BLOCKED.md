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
### B-1 — "Accept All Safe" also re-applies suggestions to groups already reviewed
- **WP:** WP-10 (found; not blocking the WP — it is committed)
- **Command:** read `DeduplicateSessionStore.acceptAllSuggestions()` (`DeduplicateSessionStore.swift:481–495`)
- **Error:** the store filters by `DeduplicationPlanner.isAutomaticCommitEligible` only, not by `approvedClusterIDs`. The lane counts "eligible and not yet reviewed", but the button overwrites custom keep/delete choices in eligible groups the user already reviewed. Pre-existing (the footer button already called it); the lane makes it more prominent. Undoable (the store registers undo); a commit still needs the confirmation dialog and goes to the Trash.
- **Tried:** looked for an App-only mitigation inside WP-10's paths; any one decides which groups are accepted, which D-CLP-16 forbids.
- **Options:** 1) make `acceptAllSuggestions` skip clusters in `approvedClusterIDs`, with a tagged test (store edit, owner approval needed); 2) reword the lane sentence to say reviewed safe groups are reset too; 3) leave as is.
- **Recommendation:** option 1; it is a small store change and makes the button do what the sentence says.
- **Status:** open

### B-2 — Quick Review sheet filter and the check lane can disagree
- **WP:** WP-10 (found; not blocking)
- **Command:** read `DeduplicateView.swift:727–730` (sheet lists `.medium`/`.low` confidence) against `DeduplicateReviewLanes.checkGroupCount` (not eligible)
- **Error:** a group annotated `.high` but refused by the gate is counted in the check lane and would not appear in Quick Review. Not reachable today: `ClusterConfidenceScorer` clamps perceptual video groups to `.medium`.
- **Tried:** nothing; changing the sheet filter is logic outside C-11.
- **Options:** 1) filter the sheet with `!isAutomaticCommitEligible`; 2) leave as is.
- **Recommendation:** option 1 in the same follow-up as B-1.
- **Status:** open
