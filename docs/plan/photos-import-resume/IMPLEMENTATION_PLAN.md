# Photos import resume — implementation plan

Status: proposal (prepared 2026-11-07). Prefix `PIR`. Read first: `docs/plan/next-half/AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`. Status lives in `PROGRESS.md`; traceability in `ACCEPTANCE_MATRIX.md`.

## Execution model
Same as every next-half plan: one implementer at a time in this checkout; reviewer after each WP; orchestrator runs Done-when commands, logs to `PROGRESS.md`, commits owned paths as `PIR <WP-ID>: <title>`. Tests are written from the acceptance bullets first and must fail before the change. Shorthand: `docs/plan/next-half/bin/cf_swift.sh build|test|suite|coverage|guards|xcode`.

## Dependency waves
| Wave | WPs | Depends on |
|---|---|---|
| 0 | WP-00 | none |
| 1 | WP-01 | WP-00 |
| 2 | WP-02, then WP-03 | WP-01 |
| 3 | WP-04 | WP-02 |
| G1 | gate | WP-04 |
| 4 | WP-05, then WP-06 | G1 |
| 5 | WP-07 | WP-06 |
| G2 | final gate | all |

Run order: WP-00 → WP-01 → WP-02 → WP-03 → WP-04 → G1 → WP-05 → WP-06 → WP-07 → G2.

---

## WP-00 — Branch and baseline (orchestrator)
1. `git status` must show no modified tracked files. `git fetch origin main` (allowed), `git switch -c feature/photos-import-resume main`. Confirm `test -d docs/plan/photos-import-resume` on the new branch; otherwise BLOCKED (D-PIR-01).
2. `cf_swift.sh build` and `cf_swift.sh suite`; record exit codes in `PROGRESS.md` "Baseline".
3. `cp docs/plan/next-half/claude-config/agents/cf-*.md .claude/agents/` if missing.
- **Done when:** both commands exit 0 and PROGRESS.md records them.

## WP-01 — Checkpoint model and store
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Services/PhotosImportCheckpoint.swift` (new), `ui/Sources/ChronoframeAppCore/Services/PhotosExportExecutor.swift` (Codable conformance on `PhotosExportedFile` :46 and `PhotosAssetExportFailure` :60 only), `ui/Sources/ChronoframeCore/PhotosExportPlanner.swift` (Codable on `PhotosAssetExportEntry` :8 and `PhotosExportPlan` :28 only), `ui/Tests/ChronoframeAppCoreTests/PhotosImportCheckpointTests.swift` (new).
- **Read for reference:** `GuardianSchedulePersistence.swift:13–53` (atomic JSON pattern), `SourceDateHint.swift`.
- **Contracts:** C-01. **Decisions:** D-PIR-06, D-PIR-10.
- **Acceptance:**
  - `testNewCheckpointIsInProgressWithNoRecords`
  - `testRecordCompletedUpdatesCompletedIDsReservedFilenamesAndMergedHints`
  - `testRemainingEntriesExcludeCompletedAndFailedInPlanOrder`
  - `testExportedAssetIDsFollowPlanOrderNotCompletionOrder`
  - `testIsResumableForStoppedLowSpaceAndInProgressOnly`
  - `testRoundTripThroughFileStorePreservesEveryField` → save then load equals original, dates to the second.
  - `testLoadReturnsNilForMissingCorruptAndWrongVersion` → three cases.
  - `testSaveIsAtomicAndCreatesDirectory` → saving into a not-yet-existing staging dir works; file is complete JSON.
  - `testRemoveIgnoresMissingFile`
- **Done when:** `cf_swift.sh test PhotosImportCheckpointTests` exit 0; `cf_swift.sh test PhotosExportExecutorTests` exit 0 (unchanged); build exit 0.

## WP-02 — Executor events, reserved names, free-space floor (safety-critical: INV-22)
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Services/PhotosExportExecutor.swift`, `ui/Tests/ChronoframeAppCoreTests/PhotosExportExecutorTests.swift`.
- **Contracts:** C-02, C-03 (protocol + extension only; the service is WP-03). **Decisions:** D-PIR-05, D-PIR-11, D-PIR-12.
- **Acceptance** (add to the existing class; existing tests must keep passing unchanged):
  - `testEventsFollowStartedProgressCompletedOrderPerAsset` → RecordingExporter extended to call `onProgress(0.5)` then `(1.0)`; assert exact event sequence for two assets.
  - `testAssetCompletedEventCarriesFilesAndHints` → payload equals the receipt's entries for that asset.
  - `testFailedAssetEmitsAssetFailedWithReceiptMessage`
  - `testReservedFilenamesAreNeverReused` → reserved `{"IMG_0001.jpg"}` ⇒ the new file is `IMG_0001-1.jpg` (or the existing collision scheme's next name); assert the file name is not in the reserved set.
  - `testLowSpaceStopsBeforeFirstWriteOfNextAsset` → provider returns 10 GiB for asset 1 then 1 GiB; asset 1 completes, asset 2 has zero `write` calls, error is `.lowStagingSpace(freeBytes: 1 GiB, floorBytes: 2 GiB)`, asset 1's files still exist. `// AGENTS-INVARIANT: 22`
  - `testNilFreeSpaceNeverStopsExport`
  - `testCancellationStillRollsBackOnlyInFlightAsset` (existing `testCancellationBetweenResourcesThrows` extended: completed asset files remain). `// AGENTS-INVARIANT: 22`
  - `testDefaultProtocolProgressMethodForwardsToTwoArgumentWrite` → a double implementing only the two-argument method receives the write.
- **Done when:** `cf_swift.sh test PhotosExportExecutorTests` exit 0; `script/check_photos_import_readonly.sh` exit 0; build exit 0.

## WP-03 — Service forwards PhotoKit progress (safety-critical: INV-22; no unit test possible without PhotoKit)
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Services/PhotosResourceExportService.swift`.
- **Contracts:** C-03.
- **Acceptance:** the diff adds exactly one `progressHandler` assignment and one forwarding two-argument method; no other line changes. Reviewer confirms by reading the diff; `script/check_photos_import_readonly.sh` exit 0.
- **Done when:** build exit 0; readonly guard exit 0; `git diff --stat` shows only this file.

## WP-04 — Store: checkpoint, cancel, resume, purge policy
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Stores/PhotosImportStore.swift`, `ui/Tests/ChronoframeAppCoreTests/PhotosImportStoreTests.swift`, `ui/Tests/ChronoframeAppCoreTests/PhotosImportResumeTests.swift` (new).
- **Read for reference:** `RunCoordinator.swift:255` (`pathsMatch`), `PhotosImportStoreTests.swift:28–100` (StubExporter, makeStore).
- **Contracts:** C-04, C-06. **Decisions:** D-PIR-07, D-PIR-08, D-PIR-10, D-PIR-13.
- **Acceptance** (`PhotosImportResumeTests`, using a `ScriptedExporter` that can fail or block per asset):
  - `testPrepareWritesCheckpointAfterEachCompletedAsset` → after asset 2 of 3 fails, checkpoint has 2 completed + 1 failure.
  - `testStopKeepsCompletedAssetsAndMarksStopped` → cancel during asset 3; checkpoint `.stopped`, files of 1–2 exist, statusMessage equals the C-06 "stopped" text with counts "2 of 3".
  - `testResumeSkipsCompletedAndMergesHints` → context `assetIDs` has all three in plan order; exporter saw writes only for asset 3.
  - `testResumeRefusedWhenDestinationDiffers` → `resumable.destinationMatches == false`; `resumeImport` returns nil with the C-06 mismatch text.
  - `testLowSpaceMarksCheckpointAndOffersResume` → factory injects an executor whose provider returns 1 GiB on asset 2; state `.lowSpace`; message is the C-06 lowSpace text.
  - `testRefreshRemovesInvalidAndConsumedStaging` → three dirs: no checkpoint, `.ready`, valid `.stopped` with one file deleted ⇒ all three removed; a fourth valid dir survives.
  - `testRefreshKeepsNewestWhenSeveralAreResumable`
  - `testNewPrepareSupersedesResumableImport` → old directory removed, new checkpoint created.
  - `testPurgeStagingParentNoLongerExists` → compile-time: no `purgeStagingParent` symbol (grep in test via reflection is not possible; assert behaviorally that a foreign subdirectory **with** a valid checkpoint survives a new prepare only through the supersede path, i.e. `prepareImport` on a fresh store with two valid checkpoints removes exactly one). 
  - `testPreparationProgressTracksEventsAndCloudWait` → progress `completed` increments; `isWaitingForCloud` true after a 0.4 progress event, false after completion.
  - `testEmptyResultRemovesDirectoryAndKeepsLegacyMessage` → existing message text at :200–202 unchanged.
  - Existing `PhotosImportStoreTests` pass unchanged except `testCleanupStagingRemovesDirectory`, which must still pass.
  - `// AGENTS-INVARIANT: 22` on `testStopKeepsCompletedAssetsAndMarksStopped`.
- **Done when:** `cf_swift.sh test PhotosImportResumeTests` and `cf_swift.sh test PhotosImportStoreTests` exit 0; build exit 0.

## Gate G1 — Core/AppCore (orchestrator)
1. Add `PhotosImportCheckpoint` to `MEANINGFUL_BASENAMES` in `script/swift_meaningful_coverage.sh`.
2. Run `cf_swift.sh suite`, `cf_swift.sh coverage`, `script/check_agents_invariants_have_tests.sh`, `script/check_photos_import_readonly.sh`, `git diff --check`.
3. Commit the coverage script: `PIR G1: coverage scope`.
- **Pass when:** all exit 0 and coverage stays at or above its threshold. A shortfall becomes WP-01b/04b test cards, not a threshold change.

## WP-05 — Photos UI: preparation panel, resume card, dialog
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Photos/PhotosPreparationPanel.swift` (new), `PhotosResumeCard.swift` (new), `PhotosPreparationText.swift` (new), `PhotosImportView.swift`, `ui/Sources/ChronoframeApp/App/AccessibilityIdentifiers.swift`, `ui/Tests/ChronoframeAppTests/PhotosPreparationTextTests.swift` (new), `ui/Tests/ChronoframeAppTests/PhotosPreparationPanelTests.swift` (new).
- **Read for reference:** `PhotosImportView.swift:264–303`, `SharedViews.swift:26–60` (DarkroomPanel), `:442` (MeridianStatusBadge), `Motion.swift:79`.
- **Contracts:** C-05, C-06. **Decisions:** D-PIR-08, D-PIR-09.
- **Acceptance:**
  - `PhotosPreparationTextTests`: `testProgressLineUsesDecimalCounts` ("Preparing 1,204 of 4,800…"), `testFailuresLineSingularAndPlural`, `testResumeBodyFormatsCountsAndDate`, `testDestinationMismatchTextIsExact`.
  - `PhotosPreparationPanelTests` (hosting-free, model-level): `testStopButtonHasIdentifier` via `Mirror`/`accessibilityIdentifier` helper already used in `PhotosImportViewTests`, `testCloudWaitShowsOnlyWhenWaiting`, `testResumeCardDisablesResumeWhenDestinationDiffers`.
  - `PhotosImportViewTests` existing navigation-title tests pass.
  - `AppState.resumeInterruptedPhotosImport()` and `currentDestinationCapture()` do not exist yet in this WP: the view calls them, so WP-05 and WP-06 must be committed together only if the build fails in between. **Rule:** WP-05 adds the view code behind `#if false` guards? No. Instead WP-05 adds the two call sites as closures passed into `PhotosImportView` (`onResume: () -> Void`, `currentDestination: () -> PhotosImportStore.DestinationCapture?`) with defaults so it compiles; WP-06 wires them. Owned path for the init change is `PhotosImportView.swift` (this WP).
- **Done when:** `cf_swift.sh test PhotosPreparationTextTests`, `PhotosPreparationPanelTests`, `PhotosImportViewTests` exit 0; `script/check_no_raw_animations.sh`, `script/check_detail_views_set_navigation_title.sh` exit 0; build exit 0.

## WP-06 — App wiring
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeApp/App/AppState.swift`, the call site of `PhotosImportView(...)` (find with grep; likely `RootSplitView.swift` or a navigation file; list it in the report), `ui/Tests/ChronoframeAppTests/AppStateTests.swift`, `ui/Tests/ChronoframeAppTests/RunCoordinatorTests.swift` (only if a new assertion is needed).
- **Read for reference:** `AppState.swift:925–934`, `:1278–1297`; `RunCoordinator.swift:68–84`.
- **Contracts:** C-07. **Decisions:** D-PIR-14.
- **Acceptance** (`AppStateTests`):
  - `testResumeInterruptedPhotosImportStartsPreviewWithRestoredContext` → harness with a resumable store double; `runCoordinator.activePhotosImportContext?.assetIDs` equals the checkpoint's exported IDs.
  - `testResumeRefusedCopiesStatusToTransientError`
  - `testLaunchRefreshesResumableImport` → after `makeAppState(performInitialBootstrap: true)`, `photosImportStore.resumable != nil` when a valid checkpoint dir exists under the harness staging parent.
  - `testDebugStagingOverrideIsHonoured` (DEBUG only) → env var points at a temp dir; store's staging parent equals it.
  - Existing `testPhotosTransferUsesContextCleansStagingAndClears` passes (cleanup removes the checkpoint too).
- **Done when:** `cf_swift.sh test AppStateTests` and `cf_swift.sh test RunCoordinatorTests` exit 0; build exit 0.

## WP-07 — Documentation
- **Model:** cf-implementer.
- **Owned paths:** `docs/SAFETY_AND_RECOVERY.md`, `docs/FAQ.md`, `docs/TROUBLESHOOTING.md`, `docs/TECHNICAL.md` (artifact table row for the checkpoint file).
- **Contracts:** C-08 (docs part). Every sentence must be checkable against the code as committed; the reviewer verifies each claim.
- **Done when:** `git diff --check` exit 0; reviewer approves.

## Gate G2 — Final (orchestrator)
1. Apply the `AGENTS.md:131` replacement text from C-08 exactly. Add `.xcstrings` keys for every C-06 string with `docs/plan/next-half/bin/add_xcstrings_keys.py` (D-PIR-09).
2. Run `cf_swift.sh suite`, `cf_swift.sh coverage`, `cf_swift.sh guards main`, `cf_swift.sh xcode`, `git diff --check`.
3. App smoke (verified, only if the orchestrator may launch apps): `ui/build.sh` then open the app with `CHRONOFRAME_PHOTOS_STAGING_DIR` pointing at a temp dir seeded with a valid `.stopped` checkpoint (write it with a tiny Swift script using the AppCore types, or copy one produced by `PhotosImportResumeTests`); screenshot the Resume card into `docs/plan/photos-import-resume/evidence/resume-card.png`. If launching is refused, log B-n and leave "verified" unclaimed.
4. Commit `AGENTS.md`, both `.xcstrings`, evidence: `PIR G2: AGENTS.md staging policy, strings, evidence`.
- **Pass when:** every command exits 0, the invariant script reports INV-22 tagged by the new tests, and `EVIDENCE_LEDGER.md` lists the owner rows below as `todo-hardware`.

## Owner handoff (todo-hardware)
Real Photos library with iCloud-only assets, signed or Debug build on the Mac. Rows and commands are in `EVIDENCE_LEDGER.md` (H-PIR-1 stop/resume mid-download, H-PIR-2 quit/relaunch/resume, H-PIR-3 low-space pause on a small disk image via `CHRONOFRAME_PHOTOS_STAGING_DIR`, H-PIR-4 destination change refuses resume, H-PIR-5 VoiceOver reads the panel and card).
