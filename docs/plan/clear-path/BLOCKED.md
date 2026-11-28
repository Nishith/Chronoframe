# Clear path — blocked items

Status: shipped in PR #269 and #274; one item open (owner-only).

Entry format: see "Blocked items" in `docs/plan/next-half/AGENT_RULES.md`. Only Nishith marks an item resolved.

Listed blockers (the only reasons to stop a WP): a change needs a file outside the WP's owned paths; a contract cannot be met without weakening an `AGENTS.md` invariant, a threshold or an existing test; WP-02's fix needs more than its three named production files; WP-10 cannot be done without editing `DeduplicateSessionStore`, `DeduplicationPlanner` or `DeduplicateExecutor`; two failed review rounds on one WP; the session may not launch or see the app (log it and continue).

## Open items
### B-5 — App smoke screenshots could not be taken
- **WP:** G2 step 5.
- **What happened:** `ui/build.sh` exit 0; the app launched with `--chronoframe-ui-test-scenario setupReady`; `screencapture -x` (exit 0) showed only the wallpaper because the shell has no screen-recording permission; the computer-use access request for Chronoframe was declined.
- **Recommendation:** the owner launches each scenario (`open -n ui/build/Chronoframe.app --args --chronoframe-ui-test-scenario <name>` for `setupReady`, `setupMultiFolder`, `runPreviewReview`, `runCopyComplete`, `healthDashboard`, `deduplicateReviewWide`) together with H-CLP-4 and H-CLP-6. "Verified" stays unclaimed until then.
- **Status:** open

## Resolved
- **B-1** "Accept All Safe" re-applied suggestions to already reviewed groups: the owner chose to make `acceptAllSuggestions` skip clusters in `approvedClusterIDs` (2026-11-12; WP-15, commit 1e4928d, D-CLP-123).
- **B-2** Quick Review sheet filter and the check lane could disagree: sheet filtered with `!isAutomaticCommitEligible` (same WP-15 change; no unit test, the filter is an inline closure in the view).
- **B-3** Engine words still reaching the screen (`RunPhase` titles, completion notification text, and similar): fixed for (a), (b), (d), (e), (f) in WP-16 (D-CLP-124); the wording is a proposal until the owner reads it on screen. Still left: (c), "Refresh Profiles", "then run the free test batch", and "Run History" in engine-side messages (`UserFacingErrorMessage.swift:30`, `SwiftOrganizerEngine.swift:628, :641`, `DeduplicateExecutor.swift:295`). PR #278 changed "Run History" and "free test batch" wording in remaining copy.
- **B-4** The local UI-test lane could not enable automation mode (macOS developer-tools prompt). Resolved 2026-11-13: the owner ran the lane (two failures, one fixed in 655bfa5, one a launch flake); the agent then ran it 28/28 plus the strict audit (D-CLP-125, D-CLP-133).
