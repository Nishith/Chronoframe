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
- **Status:** resolved (owner chose option 1, 2026-11-12; WP-15, commit 1e4928d, D-CLP-123)

### B-2 — Quick Review sheet filter and the check lane can disagree
- **WP:** WP-10 (found; not blocking)
- **Command:** read `DeduplicateView.swift:727–730` (sheet lists `.medium`/`.low` confidence) against `DeduplicateReviewLanes.checkGroupCount` (not eligible)
- **Error:** a group annotated `.high` but refused by the gate is counted in the check lane and would not appear in Quick Review. Not reachable today: `ClusterConfidenceScorer` clamps perceptual video groups to `.medium`.
- **Tried:** nothing; changing the sheet filter is logic outside C-11.
- **Options:** 1) filter the sheet with `!isAutomaticCommitEligible`; 2) leave as is.
- **Recommendation:** option 1 in the same follow-up as B-1.
- **Status:** resolved (owner chose option 1, 2026-11-12; WP-15, commit 1e4928d, D-CLP-123). No unit test covers the sheet filter: it is an inline closure in the view.

### B-3 — Engine words that still reach the screen (follow-up card, needs new UI logic or wider scope)
- **WP:** WP-11b (found; not blocking)
- **Command:** `grep -n '"' ui/Sources/ChronoframeCore/RunModels.swift ui/Sources/ChronoframeAppCore/Stores/RunSessionStore.swift`
- **Error:** (a) `RunPhase.title`/`runningTitle` ("Hash Source", "Index Destination", "Transfer", "Hashing source…", "Reverting files…") show in the phase strip, the hero "Now" line and announcements; the CLI prints the same strings (`EventEmitters.swift:160–164, :193`), so D-CLP-03 stops a Core rename. (b) `RunSessionStore.completionNotificationText` ("Transfer complete", "Transfer failed", "All source files are already in the destination.", pinned by `AppStateTests:810`, `SourceWatchCoordinatorTests:632`) and `:875` "could not complete this run", `:226` "then run the free test batch". (c) `SwiftOrganizerEngine.swift:90, :124` "Undo runs must be started…" (defensive, unreachable from the UI). (d) `PreviewReviewStatus.duplicate.title` "Duplicate" beside the issue title "Exact Copy". (e) the engine overlap refusal texts in `OrganizerEngine.swift:23–26` say "source" (quoted verbatim in `docs/TROUBLESHOOTING.md`). (f) "Worker Threads" in Settings, the "Run" menu and Help panel title, "Refresh Profiles", two Deduplicate Trash sentences that say "Run History", and the saved-setup card's "source" wording (D-CLP-108, D-CLP-111, D-CLP-115).
- **Tried:** WP-11b changed every display literal it could without logic or CLI changes.
- **Options:** 1) a follow-up card: UI-side display mapping for `RunPhase` (App target), plus literal edits for (b)–(d) with their pinned tests; owner picks wording for (e); 2) leave as is.
- **Recommendation:** option 1 before H-CLP-6, so the validation session does not trip on these words.
- **Status:** resolved for (a), (b), (d), (e), (f) (owner chose "fix before H-CLP-6", 2026-11-12; WP-16, D-CLP-124). The new wording is a proposal until the owner reads it on screen. Left: (c), "Refresh Profiles", "then run the free test batch", and "Run History" in engine-side messages (`UserFacingErrorMessage.swift:30`, `SwiftOrganizerEngine.swift:628, :641`, `DeduplicateExecutor.swift:295`).

### B-4 — The local UI-test lane cannot enable automation mode
- **WP:** WP-13 step 4
- **Command:** `xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug -derivedDataPath .tmp/ChronoframeUITestDerivedData -destination "platform=macOS" -skip-testing:ChronoframeUITests/ChronoframeUITests/testAccessibilityAuditAcrossScenarios DEVELOPMENT_TEAM= test` (exit 65)
- **Error:** `ChronoframeUITests-Runner encountered an error (The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.))` — the app and the UI-test bundle built and signed; no test case ran.
- **Tried:** one run. Enabling automation mode needs the macOS developer-tools authorization prompt (an administrator password, or `sudo DevToolsSecurity -enable`), which an agent may not answer.
- **Options:** 1) the owner runs the H-CLP-4 command in a terminal and answers the prompt; 2) run the lane in CI on the pull request.
- **Recommendation:** option 1; the label expectations and the baseline were edited without a run, so the first run may need small fixes.
- **Status:** open

### B-5 — App smoke screenshots could not be taken
- **WP:** G2 step 5
- **Command:** `ui/build.sh` (exit 0); `open -n ui/build/Chronoframe.app --args --chronoframe-ui-test-scenario setupReady` (launched, pid seen); `screencapture -x` (exit 0, but the image shows only the desktop wallpaper: the shell has no screen-recording permission); computer-use access request for Chronoframe (declined).
- **Error:** no way to see or capture the app window from this session.
- **Tried:** the two capture routes above. The one instance this step launched was quit; no other instance was touched.
- **Options:** 1) the owner launches each scenario and looks: `open -n ui/build/Chronoframe.app --args --chronoframe-ui-test-scenario <name>` for `setupReady`, `setupMultiFolder`, `runPreviewReview`, `runCopyComplete`, `healthDashboard`, `deduplicateReviewWide`; 2) grant the session access to Chronoframe and re-run G2 step 5.
- **Recommendation:** option 1 together with H-CLP-4 and H-CLP-6; "verified" stays unclaimed for every WP until then.
- **Status:** open

