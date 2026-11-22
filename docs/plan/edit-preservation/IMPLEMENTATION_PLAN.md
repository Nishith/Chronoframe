# Edit preservation — implementation plan

Status: proposal, prepared 2026-11-15. Prefix `EPR`. Read first: `docs/plan/next-half/AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`. Status lives in `PROGRESS.md`; traceability in `ACCEPTANCE_MATRIX.md`. Rationale: `SCOPE.md`.

## Execution model
Same as every next-half plan: one implementer at a time in this checkout; reviewer after each WP; orchestrator runs Done-when commands, logs to `PROGRESS.md`, commits owned paths as `EPR <WP-ID>: <title>`. Tests are written from the acceptance bullets first and must fail before the change. Shorthand: `docs/plan/next-half/bin/cf_swift.sh build|test|suite|coverage|guards|xcode`. Safety-critical WPs (EPR-2, EPR-3, EPR-4 executor, EPR-5): diffs are surgical, every changed line traces to a contract, and the orchestrator reads the full diff.

## Dependency waves
| Wave | WPs | Depends on |
|---|---|---|
| 0 | WP-00 | none |
| 1 | WP-01 (copy), WP-02 (`.aae`) | WP-00 |
| 2 | WP-03 (spike), then WP-04 (companions) | WP-02 |
| G1 | gate | WP-04 |
| 3 | WP-05 (export model), then WP-06 (executor), then WP-07 (UI) | G1 |
| 4 | WP-08 (dedupe INV-30) | WP-06 |
| G2 | final gate | all |

Run order: WP-00 → WP-01 → WP-02 → WP-03 → WP-04 → G1 → WP-05 → WP-06 → WP-07 → WP-08 → G2. WP-04 and WP-06 both touch the staging and transfer path, so they never run concurrently. WP-01 and WP-02 touch disjoint files and may be split across implementers only if the orchestrator wants; the default is sequential.

---

## WP-00 — Branch and baseline (orchestrator)
1. `git status` must show no modified tracked files; otherwise log B-1 and stop. `git switch -c feature/edit-preservation main`. Confirm `test -d docs/plan/edit-preservation`.
2. `cf_swift.sh build`, `cf_swift.sh suite`, `script/check_agents_invariants_have_tests.sh`; record exit codes under "Baseline".
3. Copy `docs/plan/next-half/claude-config/agents/cf-*.md` to `.claude/agents/` if missing.
- **Done when:** all three commands exit 0 and PROGRESS.md records them.

## WP-01 — Copy and docs for what import preserves
- **Model:** cf-implementer (Sonnet).
- **Owned paths:** the Photos import view and its strings (`ui/Sources/ChronoframeApp/Views/Photos/*` caption only), `Localizable.xcstrings`, `docs/FAQ.md`, `docs/TROUBLESHOOTING.md`, `docs/TECHNICAL.md` (Photos import paragraph), one test in `ui/Tests/ChronoframeAppTests/`.
- **Contracts:** C-01, C-07. **Decisions:** D-EPR-05.
- **Acceptance:**
  - `testPhotosImportCaptionStatesOriginalsOnlyByDefault`
  - `testFAQMentionsPhotosEditsAreNotImported` (reads `docs/FAQ.md`)
  - German strings present (the `german-localization` check).
- **Done when:** build exit 0; named tests pass; `git diff --check` clean. Behavior unchanged otherwise.

## WP-02 — `.aae` is a dedupe sidecar (INV-14)
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/DeduplicatePairDetector.swift` (the `sidecarExtensions` line and `detectSidecars` only), `ui/Tests/ChronoframeAppCoreTests/DeduplicatePairDetectorTests.swift`, `DeduplicateTests.swift` if a planner case is needed, AGENTS.md INV-14 sentence adding `.aae`.
- **Contracts:** C-02. **Decisions:** D-EPR-09, D-EPR-10.
- **Acceptance (all `// AGENTS-INVARIANT: 14`; each fails before the change):**
  - `testAAEReplacedExtensionFormIsDetected`
  - `testAAEAppendedExtensionFormIsDetected`
  - `testIMGEDigitsMapToEditedAAEExactly` and `testIMGEDoesNotMatchDifferentDigits`
  - `testAAEOwnedByTwoPhotosSurvivesWhenEitherIsKept` (planner)
  - `testAAETrashedOnlyWhenEveryOwnerIsTrashed`
  - `testXMPBehaviorUnchanged`
- **Done when:** build 0; named tests pass; `script/check_agents_invariants_have_tests.sh` 0; reviewer approves the surgical diff.

## WP-03 — Spike: where companions plug into discovery and planning (orchestrator + one Sonnet)
Read-only investigation, no production change. Answer in `DECISIONS.md` as `D-EPR-101…`:
1. Exactly where `MediaDiscovery` (`MediaDiscovery.swift:128`, `:353`) produces entries and how to return companions without touching media counts.
2. Where `CopyPlanBuilder` fixes the owner's final destination (including duplicates directory, collision suffix and already-present skips) and the narrowest hook to append companion jobs after it.
3. Confirm `TransferExecutor`, receipt writer and `RevertExecutor` need no change for an extra job (D-EPR-11). If any needs a change, stop and log BLOCKED with the proposed diff.
4. Watched Sources and the preview-review store: do they iterate discovery results in a way that would surface companions as media? List call sites.
- **Done when:** the four answers are logged with file:line references and the orchestrator confirms no schema change is required.

## WP-04 — Organize copies companions with their photo (safety-critical)
- **Model:** cf-implementer; reviewer must read the full diff.
- **Owned paths:** `MediaDateResolver.swift` (`MediaLibraryRules` additions only), `MediaDiscovery.swift`, a new `CompanionResolver.swift`, `CopyPlanBuilder.swift`, plan/preview models for `unresolvedCompanions`, preview and summary copy, `ui/Tests/ChronoframeAppCoreTests/Companion*Tests.swift`, `docs/TECHNICAL.md`, `docs/SAFETY_AND_RECOVERY.md`.
- **Contracts:** C-03. **Decisions:** D-EPR-08, D-EPR-09, D-EPR-11, WP-03 answers.
- **Acceptance (tag the invariant each covers):**
  - `testCompanionResolverMatchesExactlyOneOwner`, `testRAWPlusJPEGSharedXMPIsUnresolved`, `testOrphanXMPIsUnresolved`, `testCrossDirectoryXMPIsNotMatched`, `testHiddenAndCaseVariantsHandled`
  - `testCompanionDestinationFollowsOwnerCollisionSuffix` (owner renamed `-2` → companion renamed in lockstep)
  - `testCompanionDestinationFollowsOwnerDuplicateDirectory`
  - `testCompanionSkippedWhenOwnerSkipped`
  - `testExistingCompanionDestinationIsNeverOverwritten` (no-overwrite invariant)
  - `testCompanionIsReceiptedBeforeCopy` (receipt-before-mutation)
  - `testRevertRemovesCompanionWithOwnerAndChecksHash` and `testRevertLeavesModifiedCompanion` (revert hash-check)
  - `testOrganizeThenRevertRestoresDestinationByteForByte`
  - `testSourceFilesAreUntouched` (source read-only)
  - `testMediaCountsAndOtherScannersIgnoreCompanions` (dedupe scanner, health scanner, guardian unaffected)
  - `testUnresolvedCompanionsListedInPreviewAndDoNotBlockRun`
- **Done when:** build 0; named tests pass; `cf_swift.sh suite` 0; `check_agents_invariants_have_tests.sh` 0; reviewer approves; orchestrator diff read.

## G1 — Gate after companions
`cf_swift.sh suite` 0, `cf_swift.sh coverage` ≥ project meaningful-coverage threshold (95%), `check_agents_invariants_have_tests.sh` 0, `check_app_layer_changes_have_tests.sh main` 0, `cf_swift.sh xcode` 0. Record in PROGRESS.md.

## WP-05 — Export model: role, edited resource, checkpoint fields
- **Model:** cf-implementer.
- **Owned paths:** `PhotosExportExecutor.swift` (`PhotosExportableResource.role`, protocol method with default, `PhotosExportedFile` unchanged), `PhotosImportCheckpoint.swift` (version bump, `includeEditedVersions`, `editedFile`, variant-failure record), `ui/Tests/ChronoframeAppCoreTests/PhotosImportCheckpointTests.swift`.
- **Contracts:** C-04. **Decisions:** D-EPR-05, D-EPR-07.
- **Acceptance:**
  - `testResourceRoleDefaultsToOriginal`
  - `testEditedStillResourceDefaultsToNilForExistingDoubles`
  - `testOldCheckpointDecodesWithEditedVersionsOff`
  - `testCheckpointRoundTripsEditedFileAndVariantFailure`
- **Done when:** build 0; named tests pass.

## WP-06 — Executor and PhotoKit service export the edited still (safety-critical)
- **Model:** cf-implementer; reviewer reads the full diff.
- **Owned paths:** `PhotosExportExecutor.swift` (loop and name claim), `PhotosResourceExportService.swift` (`editedStillResource`, `isEditedStillType`), `ui/Tests/ChronoframeAppCoreTests/PhotosExportExecutorTests.swift`, `docs/TECHNICAL.md` (Photos import paragraph), AGENTS.md INV-22 and :130 wording.
- **Contracts:** C-04. **Decisions:** D-EPR-05…08.
- **Acceptance (invariant 22 tests keep the `// AGENTS-INVARIANT: 22` tag):**
  - `testOriginalsOnlyWhenOptionOffMatchesPreviousBehavior`
  - `testEditedStillExportedAsSeparateDistinctlyNamedFile` and `testOriginalBytesAndNameUnchangedWhenEditedExported`
  - `testEditedStemClaimedThroughSharedUniqueSet` (collides with another asset's `…-edited` → disambiguated, case-insensitively)
  - `testEditedRenderFailureRecordedAndOriginalStillCompleted`
  - `testVideoAndLivePhotoEditedRendersNotExported` and `testSummaryCountsUnsupportedEditedVideos`
  - `testEditedFileInheritsOriginalDateHint`
  - `testCancellationRollsBackEditedFileWithItsAsset` (per-asset transaction includes the variant)
  - `testResumeRepeatsRecordedIncludeEditedChoice`
  - `script/check_photos_import_readonly.sh` exits 0.
- **Done when:** build 0; named tests pass; readonly script 0; `check_agents_invariants_have_tests.sh` 0; reviewer approves; orchestrator diff read.

## WP-07 — Import UI, summary and history copy
- **Model:** cf-implementer.
- **Owned paths:** Photos import view and its store/coordinator (toggle, passing `includeEditedVersions`), preview and run summary text, `Localizable.xcstrings`, `ui/Tests/ChronoframeAppTests/` and `ui/Tests/ChronoframeAppCoreTests/PhotosImportStoreTests.swift`.
- **Contracts:** C-01, C-05. **Decisions:** D-EPR-05.
- **Acceptance:**
  - `testToggleDefaultsOffAndPersistsOnlyForCurrentImport`
  - `testStoreForwardsIncludeEditedVersionsToExecutor`
  - `testSummaryTextShowsOriginalsEditedAndCouldNotSaveCounts`
  - `testCaptionSwitchesWithToggle`
  - `testPreviewShowsEditedPhotoCountWithoutByteTotal`
- **Done when:** build 0; named tests pass; `check_app_layer_changes_have_tests.sh main` 0.

## WP-08 — Dedupe protects edited variants (INV-30, safety-critical)
- **Model:** cf-implementer; reviewer reads the full diff.
- **Owned paths:** `DeduplicatePairDetector.swift` (`Kind.editedVariant`, detection), `DeduplicationPlanner.swift` (protected-variant handling only), commit-footer text, AGENTS.md INV-30 bullet, `docs/SAFETY_AND_RECOVERY.md`, `docs/FAQ.md`, `ui/Tests/ChronoframeAppCoreTests/DeduplicatePairDetectorTests.swift`, `DeduplicateTests.swift`, `DeduplicateExecutorQuarantineTests.swift` if executor identity paths need a case.
- **Contracts:** C-06. **Decisions:** D-EPR-04, D-EPR-06.
- **Process (CLAUDE.md goal-driven):** write each INV-30 test and see it fail first; make the change; run `check_agents_invariants_have_tests.sh`.
- **Acceptance (all `// AGENTS-INVARIANT: 30`):**
  - `testEditedVariantDetectedByStemSameDirectoryCaseInsensitive` and `testDifferentDirectoryIsNotAVariant`
  - `testHighConfidenceClusterNeverAutoSelectsEditedVariant`
  - `testDeletingOriginalDoesNotFanOutToEditedVariant`
  - `testExplicitUserDeleteOfVariantIsHonored`
  - `testVariantKeptWhenOriginalDeletedAndFooterCountsIt`
  - `testPlanIntegrityExpectedIdentityStillRequiredForVariant`
  - `testFalsePositiveUserNamedEditedFileIsStillProtected` (documents D-EPR-06)
  - Existing INV-14 pair and sidecar tests still pass unchanged.
- **Done when:** build 0; named tests pass; suite 0; invariants script 0; coverage gate 0; reviewer approves; orchestrator diff read.

## G2 — Final gate (orchestrator)
1. `cf_swift.sh suite`, `coverage`, `guards main`, `xcode`; `script/check_agents_invariants_have_tests.sh`; `script/check_photos_import_readonly.sh`; `git diff --check`. All exit 0, recorded.
2. Docs reread: AGENTS.md (INV-14, INV-22, :130, INV-30), TECHNICAL.md, SAFETY_AND_RECOVERY.md, FAQ.md agree with each other.
3. If the app can be launched: `script/build_and_run.sh`, screenshot the Photos import options and an Organize preview with an unresolved-companion line; record the paths. Otherwise log BLOCKED and leave Verified unclaimed.
4. Ledger rows H-EPR-1…6 stay `todo-hardware`. Never push.
- **Done when:** PROGRESS.md shows every WP done with exit codes; the owner has the branch to review.
