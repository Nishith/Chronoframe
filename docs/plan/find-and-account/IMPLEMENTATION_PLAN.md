# Find and account — implementation plan

Status: not started (verified 2026-11-22 on main 8308aac: no `RunOutcomeRecord`, `MediaLookupIndex` or INV-30 tag in `ui/`, `script/` or `AGENTS.md`). Line references and UI names refreshed 2026-11-22 after clear-path (#269, #274), run-outcome accuracy (#282) and presentation accuracy (#281); `photos-import-resume` (#268, #270), `dedupe-persistence` (#267) and `nas-v1`/`nas-public` (#266) are all on `main`. Proposal prepared 2026-11-07. Prefix `FAA`. Read first: `docs/plan/next-half/AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`.

## Run order
WP-00 → WP-01 → WP-02 → WP-03 → WP-04 → WP-05 → G1 → WP-06 → WP-07 → G2. (WP-03 and WP-05 are independent of WP-02 but run sequentially.)

---

## WP-00 — Branch and baseline (orchestrator)
`git fetch origin main`; `git switch -c feature/find-and-account main`; confirm the plan folder exists; `cf_swift.sh build`, `cf_swift.sh suite`; record. Done when both exit 0.

## WP-01 — Outcome record, builder, IO, discovery callback, artifact path
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/RunOutcomeRecord.swift` (new), `ui/Sources/ChronoframeCore/MediaDiscovery.swift`, `ui/Sources/ChronoframeCore/DryRunPlanner.swift` (forwarding parameter only), `ui/Sources/ChronoframeCore/RunModels.swift` (`RunArtifactPaths` field), `ui/Sources/ChronoframeCore/ProfileModels.swift` (`RunHistoryEntryKind.runOutcome`), `ui/Sources/ChronoframeAppCore/Services/RunHistoryIndexer.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreRunOutcomeRecordTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreMediaDiscoveryTests.swift`, `ui/Tests/ChronoframeAppCoreTests/RunHistoryIndexerTests.swift`.
- **Read for reference:** `MediaDiscovery.swift:50–54, :103–225, :312–360`; `PreviewReviewModels.swift:178–260`; `EngineDomainModels.swift:128–160`; `RevertExecutor.swift:29–39`; `DestinationMetadataFile.swift:152`; `RunHistoryIndexer.swift:69–86, :131–137`.
- **Contracts:** C-01, C-02, C-04. **Decisions:** D-FAA-03, D-FAA-06, D-FAA-07.
- **Acceptance:**
  - Record tests: `testBuilderGivesEveryPreviewItemExactlyOneOutcome`, `testReceiptEntryWinsOverJobRow` (`// AGENTS-INVARIANT: 30`), `testCopiedJobWithoutReceiptIsUnresolved` (`// AGENTS-INVARIANT: 30`), `testAlreadyPresentCarriesExistingDestination`, `testFailedSkippedDuplicateHashErrorMapping`, `testChangedDetailMapsToChanged`, `testReceiptEntryOutsidePreviewStillCounted`, `testExclusionCountsCompleteWhenListTruncated` (6,000 exclusions → 5,000 listed, counts 6,000), `testIsCompleteFalseWithUnassessedDirectory`, `testWriteUsesReplaceFileAndReadRoundTrips` (file is complete JSON; no temp file left), `testReadRejectsNewerVersion`.
  - Discovery: `testDiscoveryReportsEachExclusionReason` (fixture with hidden, unsupported, symlink, package; assert reasons), existing tests unchanged.
  - Indexer: `testIndexerClassifiesRunOutcomeRecords`.
- **Done when:** the three test classes exit 0; build exit 0.

## WP-02 — Engine writes the record
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift`, `ui/Tests/ChronoframeAppCoreTests/SwiftOrganizerEngineOutcomeRecordTests.swift` (new).
- **Read for reference:** `SwiftOrganizerEngine.swift:499–570` (`makePreviewStream`), `:719–1030` (`startTransfer`) and `:1031–1200` (`resumeTransfer`, which builds its own `RunSummary`), `:1312–1390` (artifacts); `OrganizerDatabase.swift:866` (`loadCopyJobs`); `TransferExecutor.swift:1405–1440` (`uniqueReceiptStem`; a resumed run can write a second receipt with a suffixed stem).
- **Contracts:** C-03. **Decisions:** D-FAA-03, D-FAA-04.
- **Acceptance:** `testTransferWritesOutcomeRecordWithReceiptPathAndCounts` (real temp source/destination, 3 files: 1 copies, 1 already present, 1 unsupported extension → counts 1/1/0, excluded 1), `testCancelledTransferLeavesUnresolvedItems`, `testRecordWriteFailureIsWarningNotRunFailure` (destination `.organize_logs` made read-only after the receipt is written via a seam or by injecting a failing writer; run status unchanged), `testArtifactsExposeOutcomeRecordPath`.
- **Done when:** `cf_swift.sh test SwiftOrganizerEngineOutcomeRecordTests` exit 0; existing engine tests (`cf_swift.sh test SwiftOrganizerEngine`) exit 0; build exit 0.

## WP-03 — Lookup index and presence evaluator
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/MediaLookupIndex.swift` (new), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreMediaLookupIndexTests.swift` (new).
- **Read for reference:** `NASAssessmentStore.swift` (SQLite open pattern under Application Support), `MutationRecoveryCoordinator.swift:4–25`.
- **Contracts:** C-05. **Decisions:** D-FAA-08, D-FAA-10, D-FAA-11.
- **Acceptance:** `testIngestIsIdempotentPerRun`, `testLegacyReceiptIngestsAsCopiedVerified`, `testSearchByNameIsCaseInsensitiveSubstring`, `testSearchFiltersBySourcePrefixDateAndOutcome`, `testSearchOrderAndLimit`, `testForgetRemovesDestination`, `testPresenceMapsExistsMissingInaccessible` (`// AGENTS-INVARIANT: 30`; inaccessible via a checker double returning `.inaccessible`), `testPresenceDoesNotFollowSymlinks`.
- **Done when:** test class exit 0; build exit 0.

## WP-04 — Lookup store and history ingestion
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Stores/MediaLookupStore.swift` (new), `ui/Sources/ChronoframeAppCore/Stores/HistoryStore.swift`, `ui/Tests/ChronoframeAppCoreTests/MediaLookupStoreTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/HistoryStoreTests.swift`.
- **Contracts:** C-06. **Decisions:** D-FAA-02, D-FAA-12.
- **Acceptance:** `testSearchPopulatesHitsAndPresenceOffMain` (no `await` inside `XCTAssert`), `testIngestIndexesNewRecordsAndLegacyReceiptsOnce`, `testStatusMessageIsPlainOnIndexFailure` (index factory throws → message contains no "SQLite"), `HistoryStoreTests/testLoadEntriesCallsEntriesLoadedHook`.
- **Done when:** both test classes exit 0; `script/check_no_await_in_xctassert.sh` exit 0; build exit 0.

## WP-05 — Revert presence (safety-critical: INV-08, INV-30)
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/RevertExecutor.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreRevertExecutorTests.swift`, plus the one AppCore file that renders `missingCount` in the revert summary (`ui/Sources/ChronoframeAppCore/Stores/RunSessionStore.swift:821–823`; `ChronoframeCLIKit/EventEmitters.swift:193` builds the same string and is not owned by this WP, so log it if it needs the new count).
- **Contracts:** C-07. **Decisions:** D-FAA-09.
- **Acceptance:** `testInaccessibleDestinationIsCountedUnavailableAndNotDeleted` (`// AGENTS-INVARIANT: 8` and `30`), `testMissingStillCountsMissing`, `testExistingPathStillRequiresHashMatch` (unchanged behavior, re-asserted), revert summary text includes the unavailable count.
- **Done when:** revert tests exit 0; `cf_swift.sh test RunSessionStoreTests` exit 0; build exit 0; orchestrator diff review recorded.

## Gate G1 — Invariant and coverage (orchestrator)
1. Append INV-30 (C-09) to `AGENTS.md` after INV-29. 2. Add `RunOutcomeRecord MediaLookupIndex` to `MEANINGFUL_BASENAMES`. 3. `script/check_agents_invariants_have_tests.sh`, `cf_swift.sh suite`, `cf_swift.sh coverage`, `git diff --check`. 4. Commit `FAA G1: INV-30 and coverage scope`. Pass when all exit 0.

## WP-06 — UI: outcome sheet, Files face, viewer presence
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeApp/Views/Run/RunOutcomeDetailSheet.swift` (new), `ui/Sources/ChronoframeApp/Views/Run/RunOutcomeCopy.swift` (new), `ui/Sources/ChronoframeApp/Views/Run/CurrentRunView.swift`, `ui/Sources/ChronoframeApp/Views/History/MediaLookupView.swift` (new), `ui/Sources/ChronoframeApp/Views/RunHistoryView.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift` (own `mediaLookupStore`, set the HistoryStore hook), `ui/Sources/ChronoframeApp/App/AccessibilityIdentifiers.swift`, `ui/Tests/ChronoframeAppTests/RunOutcomeCopyTests.swift` (new), `ui/Tests/ChronoframeAppTests/RunOutcomeDetailSheetTests.swift` (new), `ui/Tests/ChronoframeAppTests/MediaLookupViewTests.swift` (new), `ui/Tests/ChronoframeAppTests/ReceiptVerificationTests.swift`.
- **Read for reference:** `RunHistoryView.swift:646, :902–1040, :1117–1220`; `CurrentRunView.swift:122–173`; `SharedViews.swift:442, :734`; `FinderService.swift:5–22`.
- **Contracts:** C-08. 
- **Acceptance:** `RunOutcomeCopyTests/testHeadlineCompleteAndIncomplete`, `testEveryOutcomeAndPresenceHasTitle`; `RunOutcomeDetailSheetTests/testFilterAndSearchReduceRows` (model-level static helper), `testRevealUsesDestinationThenSource`; `MediaLookupViewTests/testEmptyStateCopy`, `testRowExposesIdentifierAndPresence`; `ReceiptVerificationTests/testInaccessibleDestinationIsUnavailableNotMissing` (`// AGENTS-INVARIANT: 30`), `testSizeBytesParsedFromIdentityHash`; existing `RunHistoryViewTests` pass.
- **Done when:** the four test classes exit 0; `script/check_detail_views_set_navigation_title.sh`, `script/check_no_raw_animations.sh` exit 0; build exit 0.

## WP-07 — Documentation and strings list
- **Owned paths:** `docs/SAFETY_AND_RECOVERY.md`, `docs/TECHNICAL.md`, `docs/FAQ.md`, `README.md`, `docs/plan/find-and-account/strings-app.txt`. Contract C-10. Done when `git diff --check` exit 0 and the reviewer confirms claims.

## Gate G2 — Final (orchestrator)
1. Strings via `add_xcstrings_keys.py`. 2. `cf_swift.sh suite`, `coverage`, `guards main`, `xcode`, `git diff --check`. 3. App smoke (verified, if permitted): choose a temp folder under Choose Folders, copy with Start Copying, with one new file, one already-present and one `.txt`; open "Account for Every Item" from the Summary card on the Preview & Copy tab; screenshot `evidence/outcome-sheet.png`; History → Files → search the copied name; screenshot `evidence/files-search.png`. 4. Commit `FAA G2: strings and evidence`.
- **Pass when:** all exit 0; INV-30 tagged; owner rows `todo-hardware`.

## Owner handoff (todo-hardware)
H-FAA-1 10,000-file real run: sheet opens in < 2 s and counts reconcile with the receipt viewer; H-FAA-2 unmount the destination drive, open Files search: rows read "Unavailable", not "Missing"; H-FAA-3 revert a run with the drive unmounted: summary says "couldn't be checked", nothing deleted when remounted; H-FAA-4 VoiceOver.
