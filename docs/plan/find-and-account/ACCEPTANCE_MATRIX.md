# Find and account — acceptance matrix

Status: not started (verified 2026-11-22 on main 8308aac: no `RunOutcomeRecord` or lookup index in `ui/`, no INV-30 tag). No row is built.

| ID | Requirement (Round 3 #4) | Automated coverage | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-FAA-01 | Every selected item has exactly one evidence-bound outcome | RunOutcomeRecordTests/testBuilderGivesEveryPreviewItemExactlyOneOutcome, testReceiptEntryWinsOverJobRow, testCopiedJobWithoutReceiptIsUnresolved | H-FAA-1 | todo | todo-hardware |
| A-FAA-02 | Excluded and unassessed are reported, never invented | RunOutcomeRecordTests/testExclusionCountsCompleteWhenListTruncated, testIsCompleteFalseWithUnassessedDirectory; MediaDiscoveryTests/testDiscoveryReportsEachExclusionReason | H-FAA-1 | todo | todo-hardware |
| A-FAA-03 | Record written durably, never fails the run | SwiftOrganizerEngineOutcomeRecordTests/* ; RunOutcomeRecordTests/testWriteUsesReplaceFileAndReadRoundTrips | — | todo | n/a |
| A-FAA-04 | Find by original name across runs with honest presence | MediaLookupIndexTests/*; MediaLookupStoreTests/*; MediaLookupViewTests/* | H-FAA-2 | todo | todo-hardware |
| A-FAA-05 | Inaccessible is never "missing" (INV-30) in revert and viewer | RevertExecutorTests/testInaccessibleDestinationIsCountedUnavailableAndNotDeleted; ReceiptVerificationTests/testInaccessibleDestinationIsUnavailableNotMissing | H-FAA-3 | todo | todo-hardware |
| A-FAA-06 | Copy is plain and specific | RunOutcomeCopyTests/* | H-FAA-4 | todo | todo-hardware |
