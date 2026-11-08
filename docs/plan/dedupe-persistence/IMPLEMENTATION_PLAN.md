# Dedupe persistence — implementation plan

Status: proposal (prepared 2026-11-07). Prefix `DDP`. Read first: `docs/plan/next-half/AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`.

## Execution model
Same as every next-half plan. Commits `DDP <WP-ID>: <title>`. Shorthand `docs/plan/next-half/bin/cf_swift.sh`.

## Run order
WP-00 → WP-01 → WP-02 → G1 → WP-03 → WP-04 → G2.

---

## WP-00 — Branch and baseline (orchestrator)
`git fetch origin main`; `git switch -c feature/dedupe-persistence main`; confirm `docs/plan/dedupe-persistence/` exists; `cf_swift.sh build`, `cf_swift.sh suite`; record. Done when both exit 0.

## WP-01 — Core model, keys, fingerprint, restorer
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/DeduplicateReviewSnapshot.swift` (new), `ui/Sources/ChronoframeCore/DeduplicateReviewRestorer.swift` (new), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreDeduplicateReviewSnapshotTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreDeduplicateReviewRestorerTests.swift` (new).
- **Read for reference:** `DeduplicateModels.swift:97–172` (configuration fields), `:344–374`, `:455–469`, `:554–586`; `TestSupport.swift:15–41` (`testScanSnapshot`), `DeduplicationPlannerPropertyTests.swift` (cluster fixtures).
- **Contracts:** C-01, C-02. **Decisions:** D-DDP-02…04, D-DDP-10.
- **Acceptance:**
  - Snapshot tests: `testGroupKeyIsOrderIndependent`, `testGroupKeyIsNilWhenAMemberLacksIdentity`, `testFolderKeyIsStableAcrossTrailingSlashAndDotSegments`, `testFingerprintIgnoresWorkerCountAndChangesWithThreshold`, `testSnapshotRoundTripsThroughJSON`, `testEmptySnapshotIsEmpty`.
  - Restorer tests: `testRestoresDecisionOnlyWhenIdentityMatches` (`// AGENTS-INVARIANT: 29`), `testDroppedDecisionIsCountedAndSuggestionKept`, `testApprovalRestoresWhenMemberIdentitiesUnchanged`, `testApprovalNotRestoredWhenAMemberChanged` (`// AGENTS-INVARIANT: 29`), `testApprovalNotRestoredWhenMembershipGrew`, `testGroupWithDroppedDecisionIsNotApproved`, `testFocusMapsToMatchingCluster`, `testSettingsChangedFlag`, `testCaptureOmitsDecisionsWithoutIdentity`, `testCaptureThenRestoreIsIdentityOnUnchangedScan`, `testRestoreNeverSetsHardDelete` (`// AGENTS-INVARIANT: 12`).
- **Done when:** both test classes exit 0; build exit 0.

## WP-02 — Snapshot store and session-store integration
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Services/DeduplicateReviewSnapshotStore.swift` (new), `ui/Sources/ChronoframeAppCore/Stores/DeduplicateSessionStore.swift`, `ui/Tests/ChronoframeAppCoreTests/DeduplicateReviewSnapshotStoreTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/DeduplicateReviewPersistenceTests.swift` (new).
- **Read for reference:** `DeduplicateSessionStore.swift:90–97, :269–316, :364–500, :501–540, :556–634`; `GuardianSchedulePersistence.swift:21–53`; `DeduplicateSessionStoreTests.swift:136–151, :648, :858, :1151`; `TestSupport.swift:177–245` (`MockDeduplicateEngine`).
- **Contracts:** C-03, C-04. **Decisions:** D-DDP-05…09.
- **Acceptance:**
  - Store tests: `testSaveLoadRoundTrip`, `testLoadNilOnMissingCorruptWrongVersion`, `testSavingEmptySnapshotRemovesFile`, `testDirectoryIsCreated`.
  - Persistence tests (in-memory snapshot store double + `MockDeduplicateEngine`): `testDecisionChangeSavesAfterDebounce`, `testPauseSavesImmediately`, `testResetSavesBeforeClearing`, `testCompleteRestoresMatchingDecisionsAndApprovals` (`// AGENTS-INVARIANT: 29`), `testCompleteDropsChangedIdentityAndReportsIt` (`// AGENTS-INVARIANT: 29`), `testRestoredApprovalStillRequiresPrepareAndCommit` → `preparedCommitPlan == nil` after restore; `reviewedDeletionPlan()` equals the planner's output for restored state (`// AGENTS-INVARIANT: 17`), `testCommitCompleteRemovesSnapshot`, `testDiscardSavedReviewRemovesFile`, `testRefreshSavedReviewLoadsForFolder`, `testUndoRedoTriggersSave`, `testFlushPendingSaveWritesImmediately`, existing `DeduplicateSessionStoreTests` unchanged and passing.
- **Done when:** `cf_swift.sh test DeduplicateReviewSnapshotStoreTests`, `DeduplicateReviewPersistenceTests`, `DeduplicateSessionStoreTests` exit 0; build exit 0.

## Gate G1 — Invariant and coverage (orchestrator)
1. Append the INV-29 bullet (C-07) to `AGENTS.md` after INV-28, byte for byte; add one sentence to the "Deduplicate Workspace" section pointing at it.
2. Add `DeduplicateReviewSnapshot DeduplicateReviewRestorer` to `MEANINGFUL_BASENAMES` in `script/swift_meaningful_coverage.sh`.
3. `script/check_agents_invariants_have_tests.sh`, `cf_swift.sh suite`, `cf_swift.sh coverage`, `git diff --check`.
4. Commit: `DDP G1: INV-29 and coverage scope`.
- **Pass when:** all exit 0; coverage at or above threshold.

## WP-03 — UI: banner, saved-review card, focus, termination flush
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Deduplicate/DeduplicateRestoredReviewBanner.swift` (new), `DeduplicateSavedReviewCard.swift` (new), `DeduplicateReviewCopy.swift` (new), `DeduplicateView.swift`, `ui/Sources/ChronoframeApp/App/AccessibilityIdentifiers.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift` (termination observer only), `ui/Tests/ChronoframeAppTests/DeduplicateReviewCopyTests.swift` (new), `ui/Tests/ChronoframeAppTests/DeduplicateReviewViewsTests.swift` (new), `ui/Tests/ChronoframeAppTests/AppStateTests.swift`.
- **Read for reference:** `DeduplicateView.swift:36–58, :160–170, :233–247, :855–890, :1190`; `SharedViews.swift:26–60`; `DeduplicateStatusViewTests.swift` (view test pattern).
- **Contracts:** C-05, C-06. **Decisions:** D-DDP-08, D-DDP-09.
- **Acceptance:**
  - `DeduplicateReviewCopyTests`: `testRestoredBodyWithNoChanges`, `testRestoredBodyMentionsChangedGroupsAndClearedFiles`, `testSavedBodySaysNothingIsTrashedUntilConfirmed`.
  - `DeduplicateReviewViewsTests`: `testBannerAndCardExposeIdentifiers`, `testCardButtonsCallClosures`.
  - `AppStateTests`: `testWillTerminateFlushesDedupeReviewSave` (post the notification; the injected snapshot store double records a save).
  - `check_app_layer_changes_have_tests` is satisfied by the new test files.
- **Done when:** the three test classes exit 0; `script/check_no_raw_animations.sh` exit 0; build exit 0.

## WP-04 — Documentation and string list
- **Model:** cf-implementer.
- **Owned paths:** `docs/SAFETY_AND_RECOVERY.md`, `docs/FAQ.md`, `docs/TECHNICAL.md`, `docs/plan/dedupe-persistence/strings-app.txt` (new).
- **Contracts:** C-08, C-09. Done when `git diff --check` exit 0 and the reviewer confirms each sentence against the code.

## Gate G2 — Final (orchestrator)
1. `add_xcstrings_keys.py` with `strings-app.txt` on `Localizable.xcstrings`; JSON validity check.
2. `cf_swift.sh suite`, `cf_swift.sh coverage`, `cf_swift.sh guards main`, `cf_swift.sh xcode`, `git diff --check`.
3. App smoke (verified, if launching is permitted): `ui/build.sh`; open the app; Deduplicate a temp folder containing two identical files; mark one Delete; quit; relaunch; Scan again; screenshot the restored banner into `docs/plan/dedupe-persistence/evidence/restored-banner.png`. Then modify one of the files and scan again; screenshot the "changed" wording into `evidence/changed-group.png`.
4. Commit: `DDP G2: strings and evidence`.
- **Pass when:** all commands exit 0; INV-29 is tagged by WP-01/WP-02 tests; owner rows in `EVIDENCE_LEDGER.md` are `todo-hardware`.

## Owner handoff (todo-hardware)
H-DDP-1 real library of ≥ 5,000 photos: review for ten minutes, quit, relaunch, scan, confirm restored counts and focus; H-DDP-2 edit one reviewed file externally, scan, confirm it lost its choice and its group needs review; H-DDP-3 commit, confirm the saved file under Application Support is gone; H-DDP-4 VoiceOver reads the banner and card.
