# Clear path — implementation plan

Status: approved scope, proposal copy (prepared 2026-11-12). Prefix `CLP`. Branch `feature/clear-path` (D-CLP-01). Read first: `docs/plan/next-half/AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`. Status lives in `PROGRESS.md`; traceability in `ACCEPTANCE_MATRIX.md`. The rationale is `CONTRACTS.md` "Findings" (not the product review the shared kickoff names).

## Execution model
Same as every next-half plan: one implementer at a time in this checkout (SwiftPM shares one build directory); `cf-reviewer` after each WP; the orchestrator runs the Done-when commands, logs to `PROGRESS.md`, and commits the WP's owned paths as `CLP <WP-ID>: <title>`. Tests are written from the acceptance bullets first and must fail (or fail to compile) before the change. Shorthand: `docs/plan/next-half/bin/cf_swift.sh build|test|suite|coverage|guards|xcode`.

Models: Opus orchestrates and does WP-00, WP-13, G1, G2. `cf-implementer` (Sonnet) does WP-01…WP-12 and WP-14. `cf-reviewer` (Sonnet) reviews each. `cf-data-entry` (Haiku) updates `ACCEPTANCE_MATRIX.md`, `EVIDENCE_LEDGER.md` and `PROGRESS.md` rows, and compiles the string lists in WP-12 from the diff the orchestrator hands it.

Rules that apply to every UI WP here:
- Copy is implemented exactly as the contract gives it. A string the contract does not list follows the C-01 glossary and is listed in the WP report (old → new, file:line); the orchestrator logs the list as a runtime decision.
- An existing test that pins old wording has its expected value updated in the same WP (D-CLP-26). Find them with `grep -rn "<old string>" ui/Tests`.
- Accessibility identifiers never change (D-CLP-07).
- Subagents never edit `ui/Xcode/UITests/`, `.xcstrings`, `project.pbxproj`, `AGENTS.md` (shared rules). Those are WP-13 and G2.

## Dependency waves
| Wave | WPs | Depends on |
|---|---|---|
| 0 | WP-00 | none |
| 1 | WP-01, then WP-02, then WP-03 | WP-00 |
| 2 | WP-04 | WP-02, WP-03 |
| G1 | gate | WP-04 |
| 3 | WP-05, then WP-06, then WP-07 | G1, WP-01 |
| 4 | WP-08, then WP-09 | WP-07 |
| 5 | WP-10, then WP-11 | WP-01 |
| 6 | WP-12, then WP-13, then WP-14 | WP-05…WP-11 |
| G2 | final gate | all |

Run order: WP-00 → WP-01 → WP-02 → WP-03 → WP-04 → G1 → WP-05 → WP-06 → WP-07 → WP-08 → WP-09 → WP-10 → WP-11 → WP-12 → WP-13 → WP-14 → G2.
If a WP is blocked, continue with the next WP whose dependencies are done (WP-10 and WP-11 depend only on WP-01; WP-14 can describe only what landed).

---

## WP-00 — Branch, baseline, plan commit (orchestrator)
1. `git status --short`: the only modified tracked files may be `docs/plan/next-half/README.md` and `docs/plan/next-half/claude-config/settings.json`; `docs/plan/clear-path/` may be untracked. Anything else modified → BLOCKED.
2. `git rev-parse feature/photos-import-resume` must start with `5c72052` or be a descendant of it; then `git switch -c feature/clear-path feature/photos-import-resume` (uncommitted plan files carry over). If the branch already exists, `git switch feature/clear-path`.
3. `git add docs/plan/clear-path docs/plan/next-half/README.md docs/plan/next-half/claude-config/settings.json` and commit `CLP WP-00: plan`.
4. `cp docs/plan/next-half/claude-config/agents/cf-*.md .claude/agents/` if missing.
5. `cf_swift.sh build` and `cf_swift.sh suite`; record exit codes under "Baseline" in `PROGRESS.md`.
- **Done when:** both exit 0, the commit exists, PROGRESS.md records them.

## WP-01 — Core titles and tab order
- **Owned paths:** `ui/Sources/ChronoframeCore/ProfileModels.swift` (`OrganizeSubSection` `:228–285` and `SidebarDestination.subtitle` `:158–170` only), `ui/Sources/ChronoframeCore/DeduplicateModels.swift` (`ClusterKind.title` `.nearDuplicate` line only), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreOrganizeNavigationTests.swift` (new), any existing test file that asserts these titles or subtitles (name them in the report).
- **Contracts:** C-02. **Decisions:** D-CLP-02, D-CLP-03, D-CLP-07.
- **Acceptance** (`ChronoframeCoreOrganizeNavigationTests`):
  - `testDisplayOrderIsPrimaryFlowThenSecondary` → `[.setup, .run, .history, .sources, .health]`.
  - `testDisplayOrderCoversEveryCaseOnce`
  - `testRawValuesAreUnchanged` → `["sources","setup","run","health","history"]` for `allCases`.
  - `testTitlesAndSubtitlesMatchContract` → the C-02 table.
  - `testSidebarSubtitlesAreShort` → organize, photos, deduplicate equal C-02 and are ≤ 24 characters.
  - `testNearDuplicateTitleIsLookAlikes`
- **Done when:** `cf_swift.sh test ChronoframeCoreOrganizeNavigationTests` exit 0; every test file the report names passes; build exit 0.

## WP-02 — Staged sources are checked against the destination (safety-critical: INV-21)
- **Owned paths:** `ui/Sources/ChronoframeCore/MediaDiscovery.swift` (the new enum and function only), the file that declares `SourceDestinationDisjointness` (find with grep; the new overload only), `ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift` (`:468–477` only), `ui/Tests/ChronoframeAppCoreTests/MultiItemSourceOverlapTests.swift` (new).
- **Read for reference:** `MediaDiscovery.swift:20–40, :236–305`; `DroppedItemStager.swift:44–143`; an existing engine test that drives preflight (find `sourceOverlapsDestination` in `ui/Tests`).
- **Contracts:** C-03. **Decisions:** D-CLP-20, D-CLP-23.
- **Order of work:** write `testPreflightRejectsStagedItemThatContainsDestination` first and run it. If it passes with no production change, stop: the WP is test-only; say so in the report and keep all the tests that pass. Otherwise implement C-03.
- **Acceptance:**
  - `testPreflightRejectsStagedItemThatContainsDestination` → stage `[A, B]` with the real `DroppedItemStager` into a temp staging root, destination `B/Organized`; preview preflight throws `sourceOverlapsDestination`; nothing is created under `B/Organized`. `// AGENTS-INVARIANT: 21`
  - `testPreflightRejectsStagedItemInsideDestination` → destination `D`, item `D/Inbox`. `// AGENTS-INVARIANT: 21`
  - `testTransferStartRejectsStagedOverlapToo` → same pair through the transfer entry point. `// AGENTS-INVARIANT: 21`
  - `testStagedItemsDisjointFromDestinationPassPreflight`
  - `testDropManifestLookupAbsentItemsUnreadable` → three cases.
  - `testItemsConflictReturnsFirstConflictInOrder`
- **Done when:** `cf_swift.sh test MultiItemSourceOverlapTests` exit 0; the existing overlap test class (named in the report) exit 0; `script/check_agents_invariants_have_tests.sh` exit 0; build exit 0. The orchestrator reads the whole diff of the three production files and records that every line traces to C-03.

## WP-03 — Folder list model, store state, multi-folder picker
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Services/SourceItemList.swift` (new), `ui/Sources/ChronoframeAppCore/Stores/SetupStore.swift`, `ui/Sources/ChronoframeAppCore/Stores/PreferencesStore.swift` (the new property and its init line only), `ui/Sources/ChronoframeAppCore/Services/FolderAccessService.swift` (protocol requirement and the real implementation), every `FolderAccessServicing` conformer under `ui/Sources` and `ui/Tests` (one added method each; list them in the report), `ui/Tests/ChronoframeAppCoreTests/SourceItemListTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/SetupStoreTests.swift`, `ui/Tests/ChronoframeAppCoreTests/PreferencesStoreTests.swift`.
- **Read for reference:** `PreferencesStore.swift:70–90, :180–195` (persist pattern); `FolderAccessService.swift:86–140`.
- **Contracts:** C-04. **Decisions:** D-CLP-04, D-CLP-18, D-CLP-19.
- **Acceptance:**
  - `SourceItemListTests`: `testAddSamePathTwiceIsNoOp`, `testAddFolderInsideListedFolderThrowsInsideListed`, `testAddParentReplacesListedChildren`, `testAddOverlappingDestinationThrows` (both directions), `testAddMissingPathThrowsMissing`, `testEmptyDestinationSkipsOverlapCheck`, `testRemoveKeepsOrder`, `testNeedsStagingForTwoFoldersOrOneFile`, `testFirstConflictWithDestination`, `testSummaryLabelSingularAndPlural`, `testErrorDescriptionsMatchContract`, `testSymlinkedPathResolvesToSameItem`.
  - `SetupStoreTests/testSetSourceItemsPublishes`, `testSelectProfileLeavesSourceItems`.
  - `PreferencesStoreTests/testManualSourceItemPathsRoundTrip`.
- **Done when:** the three classes exit 0; build exit 0 (proves every conformer compiles).

## WP-04 — Setup coordinator, bookmarks, AppState forwarders
- **Owned paths:** `ui/Sources/ChronoframeApp/App/Coordinators/SetupCoordinator.swift`, `ui/Sources/ChronoframeApp/App/Coordinators/BookmarkPathResolver.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift` (`:384–406` neighborhood: two new forwarders only), `ui/Tests/ChronoframeAppTests/SetupCoordinatorTests.swift`, `ui/Tests/ChronoframeAppTests/BookmarkPathResolverTests.swift`, `ui/Tests/ChronoframeAppTests/AppStateTests.swift`, `ui/Tests/ChronoframeAppTests/TestSupport.swift` (only if a harness seam is needed; say why).
- **Read for reference:** `SetupCoordinator.swift:40–160`, `BookmarkPathResolver.swift:27–108`, `DroppedItemStager.swift:102–159`, `TestSupport.swift` (harness and folder-access double).
- **Contracts:** C-05. **Decisions:** D-CLP-18, D-CLP-19, D-CLP-21.
- **Acceptance:**
  - `SetupCoordinatorTests`: `testAddOneFolderBehavesLikeSelectSource` (no staging, `usingDroppedSource == false`, `lastManualSourcePath` set); `testAddSecondFolderStagesBothAndLabelsCount` (`sourcePath` under the harness staging root, label "2 folders", manifest lists both); `testRemoveBackToOneFolderDropsStaging` (old staging dir gone, plain path restored); `testRemoveLastFolderClearsSource`; `testAddNestedFolderShowsMessageAndKeepsList`; `testDropAppendsToExistingList`; `testChooseSourceFolderUsesMultiPicker`; `testSelectDestinationOverlappingListedFolderIsRefused` (destination unchanged, message is the C-04 text); `testSaveProfileRefusedWithSeveralFolders`; `testBootstrapRestoresListAndRestages` (two bookmarks resolve → two items, fresh staging dir); `testBootstrapDropsUnresolvableItem` (one of three fails → two remain, its key removed); `testClearProfileRestoresList`; `testStagingNeverLivesInsideAListedFolder` (`// AGENTS-INVARIANT: 1`: after staging, no file was created under either listed folder).
  - `BookmarkPathResolverTests`: `testPersistSourceItemBookmarksRemovesStaleKeys`, `testResolveSourceItemURLsKeepsIndexOrder`, `testRetainScopedAccessIncludesSourceItems`.
  - `AppStateTests/testAddAndRemoveSourceItemsInvalidateWatchedImport`.
- **Done when:** the three classes exit 0; `script/check_no_await_in_xctassert.sh` exit 0; build exit 0.

## Gate G1 — Core and AppCore (orchestrator)
1. Add `SourceItemList` to `MEANINGFUL_BASENAMES` in `script/swift_meaningful_coverage.sh`.
2. `cf_swift.sh suite`, `cf_swift.sh coverage`, `script/check_agents_invariants_have_tests.sh`, `git diff --check`.
3. Commit the coverage script: `CLP G1: coverage scope`.
- **Pass when:** all exit 0 and coverage stays at or above its threshold. A shortfall becomes a WP-03b test card, never a threshold change.

## WP-05 — Setup screen: folder list, one primary action, plain copy
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Setup/SetupScreenModel.swift`, `SetupSectionViews.swift`, `SetupView.swift`, `ui/Sources/ChronoframeApp/App/AccessibilityIdentifiers.swift` (new constants `setupSourceItems`, `setupSourceItemRemovePrefix`), `ui/Tests/ChronoframeAppTests/SetupScreenModelTests.swift`, `ui/Tests/ChronoframeAppTests/ContactSheetViewTests.swift` (only if a title assertion breaks).
- **Read for reference:** `SetupScreenModel.swift:83–342`, `SetupSectionViews.swift:52–120, :243–362, :457–700`, `SharedViews.swift` (`PathValueView`, `MeridianSurfaceCard`, `SectionHeading`, `MeridianStatusBadge`).
- **Contracts:** C-06, C-01. **Decisions:** D-CLP-07, D-CLP-09, D-CLP-10, D-CLP-27.
- **Acceptance** (`SetupScreenModelTests`): `testRowsComeFromSourceItems`; `testSinglePlainSourcePathYieldsOneRowWithoutItems`; `testStagingPathAloneYieldsNoRow`; `testHeroBadgeTitlesMatchContract` (four states); `testNextStepSummariesMatchContract`; `testStepStatesHaveNoBadgeTextWhenReady`; `testSourceSummaryValueCountsFolders`; `testHelpersForOneAndSeveralFolders`; `testReadinessMessagesMatchContract`; `testPrimaryActionTitles`; `testNoUserVisibleSetupStringContainsBannedWord` (iterates the model's string properties over a matrix of contexts and asserts none contains, case-insensitively, "source", "transfer", "mutat", "artifact", "non-destructive", "manual"). Existing tests in the class are updated to the new wording.
- **Also verified by reading (reviewer):** `SetupReadinessSection` has no `transfer` parameter and one prominent button; a badge renders only for `.needed`; remove buttons are disabled while running or with a profile; the step-card drop passes all URLs.
- **Done when:** `cf_swift.sh test SetupScreenModelTests` exit 0; `script/check_no_raw_animations.sh` and `script/check_detail_views_set_navigation_title.sh` exit 0; build exit 0.

## WP-06 — Folder layout picker and example in Setup
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Setup/FolderLayoutPresentation.swift` (new), `SetupSectionViews.swift` (`SetupLayoutBlock` and the destination step's use of it), `SetupView.swift` (pass `preferencesStore`), `ui/Sources/ChronoframeApp/Views/SettingsView.swift` (`:99–103` and the dialog message at `:145` only), `AccessibilityIdentifiers.swift` (`setupFolderLayoutPicker`), `ui/Tests/ChronoframeAppTests/FolderLayoutPresentationTests.swift` (new).
- **Read for reference:** `CopyPlanBuilder.swift:296–420` and the declaration of `PlanningPathBuilder.buildDestinationPath`; `EngineDomainModels.swift:325–363`.
- **Contracts:** C-07. **Decisions:** D-CLP-12, D-CLP-13.
- **Acceptance:** `testTitlesForEveryStructure`; `testExampleRelativePathEqualsPathBuilderOutput` (for every case, equals the builder called with the same inputs, root stripped); `testExampleLinesIndentOneLevelPerComponent`; `testFlatLayoutIsOneLine`; `testAccessibilityExampleStartsWithExample`; `testEveryStructureHasDistinctTitle`.
- **Done when:** `cf_swift.sh test FolderLayoutPresentationTests` exit 0; `cf_swift.sh test SettingsUnlockSafetyTests` exit 0 (unchanged); build exit 0.

## WP-07 — Organize chrome, toolbar, prompts
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Components/WorkspaceTabStrip.swift`, `Views/Organize/OrganizeContainerView.swift`, `Views/RootSplitView.swift`, `App/AppCommands.swift` (`:52–66`), `App/AppState.swift` (the three message literals at `:445, :453, :457`), `ui/Sources/ChronoframeAppCore/Stores/RunSessionStore.swift` (string literals in `:219–244` only), `Views/Organize/WatchedSourcesView.swift` and `Views/RunHistoryView.swift` (visible strings only), `ui/Tests/ChronoframeAppTests/OrganizeContainerViewTests.swift`, `KeyboardInteractionTests.swift`, `RunHistoryViewTests.swift`, `WatchedSourcesViewModelTests.swift`, `SidebarViewTests.swift`, `ui/Tests/ChronoframeAppCoreTests/RunSessionStoreTests.swift`, `ui/Tests/ChronoframeAppTests/RunCoordinatorTests.swift` (expected strings only).
- **Contracts:** C-08, C-01. **Decisions:** D-CLP-02, D-CLP-10, D-CLP-11.
- **Acceptance:**
  - `OrganizeContainerViewTests`: `testTabsFollowDisplayOrder`, `testDividerPrecedesFirstSecondaryTabOnly`, `testTabIdentifiersUseRawValues`.
  - `RunSessionStoreTests`: `testConfirmPromptCopyMatchesContract` (title, message with the destination path, no "transfer"), `testResumePromptCopyMatchesContract` (singular and plural), `testBlockingBatchPromptSaysOriginalsNotChanged`. `// AGENTS-INVARIANT: 10` on the last.
  - `KeyboardInteractionTests` or the test that covers `AppCommands` titles (name it): "Preview Plan", "Start Copying".
  - Reviewer confirms by reading: the `RunSessionStore.swift` diff changes string literals only; the toolbar has one conditional button; no identifier changed.
- **Done when:** the named classes exit 0; `script/check_detail_views_set_navigation_title.sh` exit 0; build exit 0.

## WP-08 — Preview & Copy workspace: headline, exceptions, plain copy
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Run/RunPreviewHeadline.swift` (new), `RunWorkspaceModel.swift`, `RunSectionViews.swift`, `CurrentRunView.swift`, `PreviewReviewPanel.swift`, `NowCopyingCard.swift`, `RunTimelineView.swift`, `RunAnnouncementPlanner.swift` (visible and spoken strings only in the last four), `AccessibilityIdentifiers.swift` (`runPreviewSummary`), `ui/Tests/ChronoframeAppTests/RunPreviewHeadlineTests.swift` (new), `RunWorkspaceModelTests.swift`, `RunAnnouncementPlannerTests.swift`, `AccessibilityTests.swift` (expected strings only).
- **Read for reference:** `RunWorkspaceModel.swift:165–360, :423–470, :506–680`, `RunSectionViews.swift:24–190, :257–320, :371–683`, `RunModels.swift:157–230`, `PreviewReviewModels.swift:237–275`.
- **Contracts:** C-09, C-01. **Decisions:** D-CLP-07, D-CLP-14.
- **Acceptance:**
  - `RunPreviewHeadlineTests`: `testSentenceWithDateSpan` ("64,212 photos and videos will be copied, from Mar 2009 to Oct 2026. Nothing has been copied yet." in `en_US`); `testSentenceSingleMonth`; `testSentenceOmitsSpanWhenKeysDoNotParse`; `testSentenceSingular`; `testSentenceNothingToCopy`; `testSentenceStale`; `testExceptionsOnlyForNonZeroCountsInContractOrder`; `testExceptionSingularForms`; `testOnlyDateAndUnreadableExceptionsOpenReview`; `testCountsUseGroupingSeparators`.
  - `RunWorkspaceModelTests`: `testHeroCopyMatchesContractForEveryStatus` (table-driven, all 13 rows); `testHeroCopyNeverSaysTransferOrRun` (every status, title + message + badge, case-insensitive whole-word "transfer", "run"); `testFailureAndStopCopySayOriginalsNotChanged` (`// AGENTS-INVARIANT: 10`); `testMetricTileTitlesMatchContract`; `testTabTitlesMatchContract`; `testThroughputSaysDoneWhenFinishedAndStartingOtherwise`; `testOutcomeSummaryMessagesMatchContract`.
  - Reviewer confirms by reading: `startTransferFromPreviewButton` sits on the hero's Start Copying button; `RunPreviewSummarySection` has no start button; the hero "Mode" line is gone.
- **Done when:** `RunPreviewHeadlineTests`, `RunWorkspaceModelTests`, `RunAnnouncementPlannerTests`, `AccessibilityTests` exit 0; `script/check_no_raw_animations.sh` exit 0; build exit 0.

## WP-09 — Next step after a copy
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Run/RunNextStepCard.swift` (new), `RunWorkspaceModel.swift` (`RunNextStep`, `nextStep`, `nextStepBody`), `CurrentRunView.swift` (one insertion), `ui/Sources/ChronoframeApp/Views/Deduplicate/DeduplicateView.swift` (`:157–169` only), `AccessibilityIdentifiers.swift` (`runNextStepCard`, `runNextStepFindDuplicates`), `ui/Tests/ChronoframeAppTests/RunWorkspaceModelTests.swift`, `DeduplicateAccessibilityTextTests.swift` (only if the header label is asserted there).
- **Contracts:** C-10. **Decisions:** D-CLP-15.
- **Acceptance** (`RunWorkspaceModelTests`): `testNextStepOnlyAfterFinishedCopyWithCopies` (finished + 0 copied → nil; dryRunFinished, reverted, nothingToCopy, failed → nil); `testNextStepCarriesSetAsideCount`; `testNextStepBodyWithAndWithoutSetAsideCopies`; `testNextStepBodySaysNothingRemovedUntilApproved`.
- **Done when:** `cf_swift.sh test RunWorkspaceModelTests` exit 0; build exit 0.

## WP-10 — Deduplicate review: two lanes, one vocabulary (dedupe UI; no store, planner or executor edits)
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Deduplicate/DeduplicateReviewLanes.swift` (new), `DeduplicateView.swift` (lanes bar insertion at `:357–361`; literals at `:422, :692–694, :739–741, :774`), `ClusterDetailPane.swift` (`:65, :513, :527`), `ClusterListPane.swift` (`:190`), `RapidTriageView.swift` (`:265`), `DeduplicateAccessibilityText.swift` (visible "cluster" only), `ui/Sources/ChronoframeApp/App/Tips.swift` (`:18`), `AccessibilityIdentifiers.swift` (`dedupeLanes`, `dedupeLanesAcceptSafe`, `dedupeLanesQuickReview`), `ui/Tests/ChronoframeAppTests/DeduplicateReviewLanesTests.swift` (new), `DeduplicateReviewViewsTests.swift`, `DeduplicateAccessibilityTextTests.swift`, `TipsTests.swift`.
- **Read for reference:** `DeduplicateSessionStore.swift:150–160, :472–530` (read only), `DeduplicationPlanner.isAutomaticCommitEligible` (read only), `DeduplicateView.swift:357–460, :640–760`.
- **Contracts:** C-11, C-01. **Decisions:** D-CLP-16, D-CLP-17.
- **Acceptance** (`DeduplicateReviewLanesTests`): `testEligibleUnreviewedGroupsCountAsSafe`; `testNonEligibleGroupsNeverCountAsSafe` (`// AGENTS-INVARIANT: 6`: a high-confidence but non-eligible fixture lands in `checkGroupCount`); `testReviewedGroupsLeaveBothLanes`; `testTextsSingularPluralAndNil`; `testDoneTextOnlyWhenEverythingReviewed`; `testEmptyClustersGiveNoText`. `DeduplicateReviewViewsTests/testNoVisibleDedupeStringSaysCluster` (the helper strings the views expose).
- **Reviewer checks:** `git diff --stat` shows no file under `ChronoframeCore/` or `ChronoframeAppCore/`; the lane buttons call only `acceptAllSuggestions()` and the existing sheet flag; the reviewer reads `isAutomaticCommitEligible` and states whether "safe matches" is accurate (D-CLP-17).
- **Done when:** `DeduplicateReviewLanesTests`, `DeduplicateReviewViewsTests`, `DeduplicateAccessibilityTextTests`, `TipsTests`, `DeduplicateSessionStoreTests` (unchanged) exit 0; `script/check_agents_invariants_have_tests.sh` exit 0; build exit 0.

## WP-11 — Health: plain cards, no score before the first copy
- **Owned paths:** `ui/Sources/ChronoframeCore/LibraryHealthScanner.swift` (card `title`/`message` literals, the history card's severity expression, the new computed property), `ui/Sources/ChronoframeApp/Views/Organize/HealthDashboardView.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreLibraryHealthScannerTests.swift`, the App test that covers the health view if one exists (name it; otherwise none).
- **Contracts:** C-12, C-01. **Decisions:** D-CLP-22.
- **Acceptance** (`ChronoframeCoreLibraryHealthScannerTests`): `testNoReceiptsIsGoodAndSaysNothingToUndo`; `testHasOrganizedHistoryFalseWithoutReceipts`; `testHasOrganizedHistoryTrueWithOneReceipt`; `testCardTitlesMatchContract`; `testOverallSeverityOfUntouchedDestinationIsGood`; `testCardIDsAndActionsUnchanged`. Reviewer confirms by reading that the dial renders only under `hasOrganizedHistory`.
- **Done when:** the class exits 0; build exit 0.

## WP-12 — UI-test scenarios and string lists
- **Owned paths:** `ui/Sources/ChronoframeApp/App/UITesting/UITestScenario.swift`, `UITestAppStateFactory.swift`, `UITestDoubles.swift` (only if the folder-access double needs `chooseFolders` behavior beyond WP-03), `docs/plan/clear-path/strings-app.txt` (new), `docs/plan/clear-path/strings-core.txt` (new).
- **Contracts:** C-13, C-14 (lists). The implementer adds the scenarios; `cf-data-entry` then compiles the two string lists from the diff text the orchestrator gives it (`git diff feature/photos-import-resume -- ui/Sources`).
- **Acceptance:** build exit 0 in Debug; `grep -c . docs/plan/clear-path/strings-app.txt` > 0; every line in both lists appears verbatim as a literal in `ui/Sources` (the reviewer spot-checks 20 lines and every line containing a quote or apostrophe).
- **Done when:** build exit 0; `git diff --check` exit 0; reviewer approves.

## WP-13 — XCUITest expectations and accessibility baseline (orchestrator)
1. In `ui/Xcode/UITests/ChronoframeUITests.swift` replace every expectation of a renamed label (`"1. Source"`, `"Start"`, `"Artifacts"`, `"Return to Setup"`, any `"Transfer"`/`"Preview"` label match, others found with `grep -n 'staticTexts\["\|buttons\["' `) with the C-06/C-08/C-09 text. Identifier-based queries stay. Add the two WP-12 scenarios to the audited-scenario list and to `organizeTabIdentifier(for:)`.
2. Update label strings in `ui/Xcode/UITests/A11yBaseline.json` that name renamed controls; do not add suppressions for new findings.
3. `script/check_uitest_membership.sh` exit 0; `cf_swift.sh xcode` exit 0.
4. If the session may launch apps: run the CI UI lane command (`.github/workflows/ci.yml:310–320`, with `-derivedDataPath .tmp/ChronoframeUITestDerivedData`) and record the exit code. If it cannot run, log B-n and leave row H-CLP-4 `todo-hardware`.
- **Done when:** steps 1–3 exit 0 and step 4 is either exit 0 or logged.

## WP-14 — Documentation
- **Owned paths:** `docs/QUICK_START.md`, `docs/FAQ.md`, `docs/TROUBLESHOOTING.md`, `docs/SAFETY_AND_RECOVERY.md` (one sentence).
- **Contracts:** C-14 (docs). **Decisions:** D-CLP-03. Every sentence must be checkable against the code as committed; the reviewer verifies each claim and each quoted label against `ui/Sources`.
- **Done when:** `git diff --check` exit 0; reviewer approves.

## Gate G2 — Final (orchestrator)
1. Add catalog keys for `strings-app.txt` → `ui/Sources/ChronoframeApp/Resources/Localizable.xcstrings` and `strings-core.txt` → `ui/Sources/ChronoframeAppCore/Resources/LocalizableCore.xcstrings`, in each catalog's existing JSON style (D-CLP-25). If WP-02 changed production code, extend the INV-21 bullet in `AGENTS.md` as C-14 says.
2. Add `RunPreviewHeadline`, `DeduplicateReviewLanes` and `FolderLayoutPresentation` to `MEANINGFUL_BASENAMES` only if that list already contains App-target files (check for `RunWorkspaceModel`); otherwise leave it.
3. `cf_swift.sh suite`, `cf_swift.sh coverage`, `cf_swift.sh guards feature/photos-import-resume`, `cf_swift.sh xcode`, `git diff --check`.
4. Banned-word sweep, recorded with its output: `grep -rnE '"[^"]*\b(Transfer|transfer|mutat|artifact|Artifact|cluster|Cluster|Raw score|Console|Structure Drift|Current Focus)\b[^"]*"' ui/Sources/ChronoframeApp/Views ui/Sources/ChronoframeApp/App/AppCommands.swift`. Every remaining hit is either an identifier/raw value/log string (say which) or is fixed.
5. App smoke (verified, only if the session may launch and see the app): `ui/build.sh`, then for each of `setupReady`, `setupMultiFolder`, `runPreviewReview`, `runCopyComplete`, `healthDashboard`, `deduplicateReviewWide`: `open -n ui/build/Chronoframe.app --args --chronoframe-ui-test-scenario <name>`, screenshot into `docs/plan/clear-path/evidence/<name>.png`, quit that instance. Quit only instances this step launched; never touch an instance that was already running. If launching or screen access is refused, log B-n and leave "verified" unclaimed.
6. Commit catalogs, `AGENTS.md` (if changed), coverage script (if changed), evidence: `CLP G2: strings, guards, evidence`.
- **Pass when:** every command in step 3 exits 0, step 4's remaining hits are all explained, and `EVIDENCE_LEDGER.md` lists the owner rows as `todo-hardware`.

## WP-15 — Bulk accept skips reviewed groups (added 2026-11-12, D-CLP-123; BLOCKED B-1, B-2)
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Stores/DeduplicateSessionStore.swift` (only the two filter lines in `acceptAllSuggestions` and `acceptAllHighConfidence`), `ui/Sources/ChronoframeApp/Views/Deduplicate/DeduplicateView.swift` (only the `reviewClusters` filter in the Quick Review sheet), `ui/Tests/ChronoframeAppCoreTests/DeduplicateSessionStoreTests.swift`, `ui/Tests/ChronoframeAppTests/DeduplicateReviewLanesTests.swift`.
- **Read for reference:** `DeduplicateSessionStore.swift:390–408, :470–535`; `DeduplicateView.swift:715–740`; `DeduplicationPlanner.isAutomaticCommitEligible`; `DeduplicateSessionStoreTests.swift:590–640` (fixture and test pattern).
- **Contracts:** C-15. **Decisions:** D-CLP-123.
- **Safety:** the store is safety-critical. The diff in it must be exactly the two filter conditions. No refactor, no shared helper, no comment rewrites beyond one line explaining the new condition.
- **Acceptance:**
  - `DeduplicateSessionStoreTests`: `testAcceptAllSuggestionsKeepsChoicesInReviewedGroups` (two eligible groups; in the first, flip the suggested keeper with `setDecision` so it is reviewed with custom choices; call `acceptAllSuggestions()`; the first group's custom choices are unchanged, the second group is approved with its suggestions); `testAcceptAllHighConfidenceKeepsChoicesInReviewedGroups` (same for the other function); `testAcceptAllSuggestionsDoesNothingWhenEveryEligibleGroupIsReviewed` (decisions and approvals unchanged).
  - `DeduplicateReviewLanesTests`: `testQuickReviewFilterMatchesCheckLane` only if the filter can be tested without rendering the view; if it cannot, say so in the report and do not add a view-rendering test.
  - Existing tests in both classes pass unchanged.
- **Done when:** `cf_swift.sh test DeduplicateSessionStoreTests`, `DeduplicateReviewLanesTests`, `DeduplicateReviewPersistenceTests`, `DeduplicateStatusViewTests` exit 0; `script/check_agents_invariants_have_tests.sh` exit 0; `cf_swift.sh build` exit 0; `git diff --check` exit 0.

## WP-16 — Leftover engine words (added 2026-11-12, D-CLP-124; BLOCKED B-3)
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Support/RunPhaseDisplay.swift` (new); `ui/Sources/ChronoframeAppCore/Stores/RunSessionStore.swift` (the lines C-16 items 2 and 3 name, nothing else); `ui/Sources/ChronoframeAppCore/Services/OrganizerEngine.swift` (the four error texts); `ui/Sources/ChronoframeCore/PreviewReviewModels.swift` (one title); `ui/Sources/ChronoframeApp/App/AppState.swift` (`:1464` only), `App/AppCommands.swift`; `ui/Sources/ChronoframeApp/Views/Run/RunAnnouncementPlanner.swift`, `Views/Run/RunWorkspaceModel.swift`, `Views/SettingsView.swift`, `Views/Help/HelpView.swift`, `Views/Deduplicate/DeduplicateView.swift` (two sentences), `Views/Setup/SetupSectionViews.swift`, `Views/ProfilesView.swift`; `docs/TROUBLESHOOTING.md`, `docs/FAQ.md`; `docs/plan/clear-path/strings-app.txt`, `strings-core.txt`; `ui/Tests/ChronoframeAppCoreTests/RunPhaseDisplayTests.swift` (new); any existing file under `ui/Tests/` whose assertion pins a string C-16 changes; `ui/Xcode/UITests/ChronoframeUITests.swift` and `A11yBaseline.json` only where they contain a string C-16 changes.
- **Read for reference:** C-01 glossary; `ui/Sources/ChronoframeCore/RunModels.swift:25–70`; `ui/Sources/ChronoframeCLIKit/EventEmitters.swift:155–195` (read only; it must keep using `title`/`runningTitle`).
- **Contracts:** C-16, C-01. **Decisions:** D-CLP-124, D-CLP-03.
- **Safety:** `RunSessionStore` and `OrganizerEngine` edits are display literals and property names only. No control-flow change.
- **Acceptance:**
  - `RunPhaseDisplayTests`: `testEveryPhaseHasDisplayTitlesFromContract` (the exact table in C-16 item 1, over `RunPhase.allCases` or every case by hand); `testDisplayTitlesContainNoBannedWord` (no display title contains "hash", "index", "transfer", "revert", "classif", "source", case-insensitively); `testCoreTitlesAreUnchangedForTheCLI` (pins `RunPhase.sourceHashing.title == "Hash Source"` and `RunPhase.copy.title == "Transfer"`).
  - `RunSessionStoreTests`: `testNotificationCopyMatchesContract` (the three notification literals of C-16 item 3).
  - Existing tests: update only assertions that pin a string C-16 changes, and list each edit (file:line, old → new) in the report.
- **Done when:** `cf_swift.sh test RunPhaseDisplayTests`, `RunSessionStoreTests`, `RunWorkspaceModelTests`, `RunAnnouncementPlannerTests`, `FreeTestBatchRunTests`, `AppStateTests`, `RunCoordinatorTests`, `SourceWatchCoordinatorTests`, `ChronoframeCLIKitTests`, `DeduplicateStatusViewTests`, `AccessibilityTests` exit 0; `script/check_uitest_membership.sh` exit 0; `cf_swift.sh build` exit 0; `git diff --stat -- ui/Sources/ChronoframeCLIKit ui/Sources/ChronoframeCore/RunModels.swift` is empty; `git diff --check` exit 0.

## Owner handoff (todo-hardware)
Rows and commands are in `EVIDENCE_LEDGER.md`: H-CLP-1 sandboxed build, three folders, quit and relaunch, preview; H-CLP-2 the real 65,000-file library through preview; H-CLP-3 VoiceOver through Setup list, preview summary, lanes; H-CLP-4 UI-test lane and accessibility audit; H-CLP-5 recapture `docs/screenshots/`; H-CLP-6 a non-technical person does the whole job unaided (the validation gate for the full stepper); H-CLP-7 App Store metadata and site wording against the new labels.
