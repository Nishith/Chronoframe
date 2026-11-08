# NAS v1 acceptance matrix

Maps the P0 portions of `docs/NAS_REQUIREMENTS.md` section 16 (T01–T21) to automated tests and hardware rows. P1 portions and T10/T22 are out of scope. Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`. Only Nishith sets `pass-hardware`.

| Spec test | Requirements | Automated coverage (class/method) | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| T01 | NAS-SCP-01, 03, NAS-UX-01 | ChronoframeCoreNASAssessmentScannerTests/testRecursiveAssessmentFindsCrossFolderDuplicates; NASLibraryViewTests/testEveryStateHasBannerCopy | H3 | pass (ebdefd2) | todo-hardware |
| T02 | NAS-SCP-03, 04, 05, NAS-REC-05 | ScannerTests/testSynologyContainersExcludedAndReported, testSymlinksPackagesAndSpecialFilesAreReportedNotTraversed, testNestedMountIsNotCrossed, testUnreadableDirectoryMakesAssessmentIncomplete, testExclusionsAloneKeepAssessmentComplete; ChronoframeCoreNASSystemContainerRulesTests/* | H3 | pass (ebdefd2) | todo-hardware |
| T03 | NAS-SCP-08 (B), NAS-UX-03 | ScannerTests/testUnicodeAndCaseCollisionPathsAreDistinct; NASLibraryViewTests (lazy list) | H8 | pass (ebdefd2; case pair skipped on case-insensitive APFS temp volume) | todo-hardware |
| T04 | NAS-CON-01, NAS-DAT-01, NAS-PRV-01 | ScannerTests/testAssessmentDoesNotWriteInsideReadOnlyRoot, testAssessmentLeavesWritableRootByteIdentical, testRefusesStateInsideRoot | H3, H4 | pass (ebdefd2) | todo-hardware |
| T05 | NAS-CON-01–05, NAS-REC-02 | ChronoframeCoreNASLibraryIdentityTests/* ; NASWorkspaceStoreTests/testRemountUpdatesRecordAndGoesReady, testMismatchShowsDifferentFolderAndNewChoiceGetsNewUUID, testUnreachableBookmarkGoesWaitingForNAS; NASReconnectProbeTests/* | H3 | pass (ebdefd2) | todo-hardware |
| T06 | NAS-CON-06–07, NAS-DAT-01, NAS-PRV-04 | ChronoframeCoreNASShareLeaseTests/*; NASRemoteDestinationRefusalTests/*; ChronoframeCoreNASProbeTests/testProbeHeldWriterRecordsLatencyAndBusy | H1 | pass (ebdefd2) | todo-hardware |
| T07 | NAS-DED-01, 02, 07 (B) | ScannerTests/testRecursiveAssessmentFindsCrossFolderDuplicates, testUniqueSizeFilesAreNeverRead | H2 | pass (ebdefd2) | todo-hardware |
| T09 | NAS-DED-05 | NASWorkspaceStoreTests/testStaleChoiceDetected, testSavedReviewIsNotMutationAuthority; ChronoframeCoreNASAssessmentStoreTests/testChoicesAndReviewStateSurvivePruning; NASAssessmentEngineTests/testSaveChoiceAndSelectedDigestRoundTrip | H3 | pass (ebdefd2) | todo-hardware |
| T11 | NAS-CPY-01–05 (B), 03, 09 | ChronoframeCoreNASRemoteCopyPolicyTests/* | H1, H6 | pass (ebdefd2) | todo-hardware |
| T12 | NAS-CPY-02 (B) | existing INV-21 overlap tests (regression in full suite) | H6 | pass (ebdefd2) | todo-hardware |
| T13 | NAS-CPY-08 (B), NAS-PRV-03 (B) | existing receipt/revert/trial suites (regression) | H6 | pass (ebdefd2) | todo-hardware |
| T14 | NAS-DAT-02–06 | ChronoframeCoreNASJournalPolicyTests/*; ChronoframeCoreNASAssessmentStoreTests/testRefusesSymlinkedStoreFile | H1 | pass (ebdefd2) | todo-hardware |
| T15 | NAS-DAT-08 (B), NAS-REC-06 (B) | ScannerTests/testWarmScanReusesDigestsWithoutReads; NASAssessmentEngineTests | H3 | pass (ebdefd2) | todo-hardware |
| T16 | NAS-REC-01–04, 09 | ScannerTests/testVolumeLossEndsWithInterruptedOutcome, testCancellationFinishesWithCancelledSummary, testSleepActivityBeginsAndEndsOnceForEveryOutcome; NASWorkspaceStoreTests/testStartStopTransitions, testVolumeInterruptionGoesWaitingForNAS; RemoteCopyPolicyTests/testRemoteVolumeChangeAbortsBeforeNextJob | H5 | pass (ebdefd2) | todo-hardware |
| T17 | NAS-REC-05–07 (B), NAS-CPY-08 (B) | existing TransferExecutorCrashRecoveryTests (regression) + RemoteCopyPolicyTests run-fatal cases | H5, H6 | pass (ebdefd2) | todo-hardware |
| T18 | NAS-SPC-01–03 | ScannerTests (no local media copy; store only metadata); existing capacity tests (regression) | H6 | pass (ebdefd2) | todo-hardware |
| T19 | NAS-SPC-04 (P0 label), NAS-SPC-05 (B) | NASLibraryViewTests/testRedundantBytesLabelSaysNotSpaceFreed; StoreTests/testChoicesAndReviewStateSurvivePruning | — | pass (ebdefd2) | n/a |
| T20 | NAS-UX-02–05, NAS-PRV-02 | NASAccessibilityTextTests/*; NASLibraryViewTests/testAccessibilityLabelsCoverEveryControl | H7 | pass (ebdefd2) | todo-hardware |
| T21 | NAS-NFR-01–04, 09 (P0) | ChronoframeCoreNASMeteredFileReaderTests/*; ScannerTests/testCleanBytesEqualCandidateBytesOnColdScanAndWithinBudget, testConcurrencyNeverExceedsWorkerCount; NASPreviewLoaderTests/*; ChronoframeCoreNASProbeTests/testParityCheckPassesOnGeneratedCorpus | H2, H8 | pass (ebdefd2) | todo-hardware |

## Release gates (section 17.1) — owner view

| Gate | Evidence | Status |
|---|---|---|
| 1 Scope accepted | `docs/NAS_REQUIREMENTS.md` status "approved, v1.0" | pass (2026-11-07) |
| 2 Regression checks | G2 and G3 command log in PROGRESS.md | pass (ebdefd2; G2 d6fbd13, G3 suite/coverage/guards exit 0) |
| 3 Signed Synology P0 tests | H1–H8 in EVIDENCE_LEDGER.md | todo-hardware |
| 4 No NAS writes, parity, byte limits, review/reconnect, truthful coverage | T04, T21, T09, T05, T02 rows | auto pass (ebdefd2); hardware todo-hardware |
| 5 ADR-NAS-01–03 accepted with evidence | H1 probe JSON + T05/T06/T11/T14 rows | todo-hardware |
| 6 No NAS cleanup action | NASLibraryViewTests/testNoDestructiveControlsExist | pass for NAS Library (ebdefd2); Deduplicate can still Trash on a mounted share — owner decision, D-NAS-135 |
| 7 Owner Go | Nishith records Go in EVIDENCE_LEDGER.md | todo-hardware |
