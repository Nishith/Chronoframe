# First ten minutes — implementation plan

Status: proposal (prepared 2026-11-07). Prefix `FTM`. Read first: `docs/plan/next-half/AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`.

## Run order
WP-00 → WP-01 → WP-02 → G1 → WP-03 → WP-04 → WP-05 → WP-06 → WP-07 → G2.

---

## WP-00 — Branch and baseline (orchestrator)
`git fetch origin main`; `git switch -c feature/first-ten-minutes main`; confirm the plan folder; `cf_swift.sh build`, `cf_swift.sh suite`. Done when both exit 0.

## WP-01 — Core preflight assessment, byte text, first-run batch
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/RunPreflightAssessment.swift` (new), `ui/Sources/ChronoframeCore/FirstRunTestBatch.swift` (new), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreRunPreflightAssessmentTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreFirstRunTestBatchTests.swift` (new).
- **Read for reference:** `FreeTestBatchPlanner.swift:22–130`, `TrialAllowance.swift:30–110`.
- **Contracts:** C-01, C-06 (Core part). **Decisions:** D-FTM-03, D-FTM-05.
- **Acceptance:** `testUnknownInputsGiveUnknownChecks`, `testBlockedWhenFreeBelowPlanned`, `testWarningWithinSafetyMargin`, `testOkAboveMarginSaysEstimate`, `testStagingOmittedWhenNil`, `testStagingWarningBelowFloor`, `testSourceAndDestinationAccessStates`, `testByteCountTextFormats` (0, 1 KiB-ish, 38.2 GB), `testHasBlocked`; batch: `testNoBatchForSmallPlan`, `testBatchCappedByAllowance`, `testBatchTakesOldestFirst`, `testZeroAllowanceGivesNil`.
- **Done when:** both classes exit 0; build exit 0.

## WP-02 — Preview bytes, preflight service, store state
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift` (lines 515–534 only), `ui/Sources/ChronoframeAppCore/Services/PreflightService.swift` (new), `ui/Sources/ChronoframeAppCore/Stores/SetupStore.swift`, `ui/Sources/ChronoframeAppCore/Stores/RunSessionStore.swift` (`previewPlannedBytes`, `lastPreviewTransfers`), `ui/Tests/ChronoframeAppCoreTests/PreflightServiceTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/SetupStoreTests.swift`, `ui/Tests/ChronoframeAppCoreTests/RunSessionStoreTests.swift`, the existing engine preview test file that asserts preview metrics (named in the report).
- **Contracts:** C-02, C-03, C-06 (`lastPreviewTransfers`).
- **Acceptance:** `PreflightServiceTests/testInputsFromRealTempFolders` (free bytes non-nil, both reachable), `testUnreachableSourceGivesFalse`, `testMissingPathsGiveNil`; `SetupStoreTests/testApplyPreflightPublishes`; `RunSessionStoreTests/testPreviewPlannedBytesAndTransfersExposed`; engine preview test: `bytesTotal` equals the fixture's summed sizes.
- **Done when:** the named classes exit 0; build exit 0.

## Gate G1 — Coverage (orchestrator)
Add `RunPreflightAssessment FirstRunTestBatch` to `MEANINGFUL_BASENAMES`; `cf_swift.sh suite`, `coverage`, `git diff --check`; commit `FTM G1: coverage scope`. Pass when all exit 0.

## WP-03 — Setup recheck and live checklist
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeApp/App/Coordinators/SetupCoordinator.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift` (`refreshPreflight` forwarder and preview-completion hook), `ui/Sources/ChronoframeApp/Views/Setup/SetupScreenModel.swift`, `ui/Sources/ChronoframeApp/Views/Setup/SetupSectionViews.swift`, `ui/Sources/ChronoframeApp/Views/Setup/SetupView.swift` (call on appear), `ui/Tests/ChronoframeAppTests/SetupScreenModelTests.swift`, `ui/Tests/ChronoframeAppTests/SetupCoordinatorTests.swift`.
- **Read for reference:** `SetupCoordinator.swift:40–160`, `SetupScreenModel.swift:35–60, :126–200, :292–340`, `SetupSectionViews.swift:457–620`.
- **Contracts:** C-04, C-05. **Decisions:** D-FTM-02, D-FTM-09.
- **Acceptance:** `SetupScreenModelTests/testBlockedSourceCheckGivesSourceUnavailableState`, `testBlockedDestinationCheckGivesDestinationUnavailableState`, `testCanStartRunUnchangedByPreflight`; `SetupCoordinatorTests/testBootstrapRefreshesPreflight`, `testSelectDestinationRefreshesPreflight`.
- **Done when:** both classes exit 0; `script/check_no_raw_animations.sh` exit 0; build exit 0.

## WP-04 — Preview preflight row and first-run test batch
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Run/RunSectionViews.swift`, `ui/Sources/ChronoframeApp/Views/Run/RunWorkspaceModel.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift` (`startFirstRunTestBatch`), `ui/Sources/ChronoframeApp/App/AccessibilityIdentifiers.swift`, `ui/Tests/ChronoframeAppTests/RunWorkspaceModelTests.swift`, `ui/Tests/ChronoframeAppTests/AppStateTests.swift`.
- **Read for reference:** `RunSectionViews.swift:257–320`, `RunWorkspaceModel.swift:105–203, :536–560`, `AppState.swift:486–510`, `RunCoordinator.swift:138`.
- **Contracts:** C-06. **Decisions:** D-FTM-04, D-FTM-05.
- **Acceptance:** `RunWorkspaceModelTests/testOffersTestBatchOnlyForFirstRunWithEnoughFiles`, `testTestBatchTitle`, `testPreflightRowUsesDestinationSpaceCheck`; `AppStateTests/testStartFirstRunTestBatchStartsTransferWithSelection` (coordinator receives a 25-file selection), `testNoTestBatchAfterFirstReceipt`.
- **Done when:** both classes exit 0; build exit 0.

## WP-05 — Proof card
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Run/RunProofCard.swift` (new), `ui/Sources/ChronoframeApp/Views/Run/RunProofModel.swift` (new), `ui/Sources/ChronoframeApp/Views/Run/CurrentRunView.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift` (receipt lookup + reveal/undo/continue actions), `ui/Sources/ChronoframeApp/App/AccessibilityIdentifiers.swift`, `ui/Tests/ChronoframeAppTests/RunProofModelTests.swift` (new), `ui/Tests/ChronoframeAppTests/AppStateTests.swift`.
- **Read for reference:** `CurrentRunView.swift:37–60, :118–149`, `RunSessionStore.swift:16–34, :260`, `HistoryCoordinator.swift:44–91`, `RevertExecutor.swift:247`, `TransferExecutor.swift:1379–1406`.
- **Contracts:** C-07. **Decisions:** D-FTM-06, D-FTM-07.
- **Acceptance:** `RunProofModelTests/testHeadlineVerifiedAndUnverified`, `testFolderCountFromReceiptDestinations`, `testNoReceiptDisablesUndoWithExplanation`; `AppStateTests/testProofCardUndoRevertsThatReceiptOnly` (`// AGENTS-INVARIANT: 8`; harness asserts `requestRevert` is called with the batch's receipt URL), `testProofCardRevealUsesFirstDestination`, `testProofCardShownOnlyForBatchCompletion`.
- **Done when:** both classes exit 0; `script/check_detail_views_set_navigation_title.sh` exit 0; build exit 0.

## WP-06 — Photos staging line
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Photos/PhotosImportView.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift` (`photosStagingCheck`), `ui/Tests/ChronoframeAppTests/AppStateTests.swift`, `ui/Tests/ChronoframeAppTests/PhotosImportViewTests.swift`.
- **Contracts:** C-08. **Acceptance:** `AppStateTests/testPhotosStagingCheckRefreshesFromStagingParent`; `PhotosImportViewTests` existing pass. Done when both exit 0; build exit 0.

## WP-07 — Docs and strings lists
- **Owned paths:** `docs/QUICK_START.md`, `docs/FAQ.md`, `docs/TROUBLESHOOTING.md`, `README.md`, `docs/plan/first-ten-minutes/strings-app.txt`. Contract C-09, C-10. Done when `git diff --check` exit 0 and the reviewer confirms claims.

## Gate G2 — Final (orchestrator)
1. Strings via `add_xcstrings_keys.py`. 2. `cf_swift.sh suite`, `coverage`, `guards main`, `xcode`, `git diff --check`. 3. App smoke (verified, if permitted): fresh `UserDefaults` domain (`defaults delete` is owner-only; instead use a temp destination with no receipts and a Debug build whose trial ledger is empty), choose a 100-file temp source; screenshots `evidence/setup-preflight.png`, `evidence/preview-batch-offer.png`, `evidence/proof-card.png`. 4. Commit `FTM G2: strings and evidence`.
- **Pass when:** all exit 0; owner rows `todo-hardware`.

## Owner handoff (todo-hardware)
H-FTM-1 external drive with less free space than the plan: Setup and Preview show the blocked copy; the transfer pauses as before; H-FTM-2 unplug the source drive, relaunch: "Source Unavailable"; H-FTM-3 fresh install path (new Mac user account or a clean Debug container): offer appears, batch copies 25, proof card shows files, Show in Finder selects them, Undo removes exactly 25 and refunds allowance; H-FTM-4 VoiceOver through checklist, offer and proof card.
