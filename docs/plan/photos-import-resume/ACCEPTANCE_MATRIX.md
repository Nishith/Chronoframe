# Photos import resume — acceptance matrix

Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`. Only Nishith sets `pass-hardware`.

| ID | Requirement (Round 3 #3) | Automated coverage (class/method) | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-PIR-01 | Per-asset progress and iCloud wait are visible | PhotosExportExecutorTests/testEventsFollowStartedProgressCompletedOrderPerAsset; PhotosImportResumeTests/testPreparationProgressTracksEventsAndCloudWait; PhotosPreparationTextTests/* | H-PIR-1 | pass (4c11529) | todo-hardware |
| A-PIR-02 | Stop keeps every completely exported asset, rolls back the in-flight one | PhotosExportExecutorTests/testCancellationStillRollsBackOnlyInFlightAsset; PhotosImportResumeTests/testStopKeepsCompletedAssetsAndMarksStopped; PhotosImportResumeTests/testResumeRemovesFilesTheCheckpointDoesNotRecord, testResumeFailsClosedWhenAnUnrecordedFileCannotBeRemoved | H-PIR-1 | pass (48e283e) | todo-hardware |
| A-PIR-03 | Resume exports only the remainder and preserves hints and order | PhotosImportResumeTests/testResumeSkipsCompletedAndMergesHints; PhotosImportCheckpointTests/testExportedAssetIDsFollowPlanOrderNotCompletionOrder | H-PIR-2 | pass (48e283e) | todo-hardware |
| A-PIR-04 | Resume revalidates destination, access and staged files | PhotosImportResumeTests/testResumeRefusedWhenDestinationDiffers, testRefreshRemovesInvalidAndConsumedStaging; PhotosImportResumeTests/testResumeRevalidatesDestinationAndFilesAtResumeTime | H-PIR-4 | pass (48e283e) | todo-hardware |
| A-PIR-05 | Low staging space pauses cleanly and is resumable | PhotosExportExecutorTests/testLowSpaceStopsBeforeFirstWriteOfNextAsset; PhotosImportResumeTests/testLowSpaceMarksCheckpointAndOffersResume | H-PIR-3 | pass (48e283e) | todo-hardware |
| A-PIR-06 | Checkpoint survives relaunch; consumed or invalid staging is removed | PhotosImportCheckpointTests/testRoundTripThroughFileStorePreservesEveryField; AppStateTests/testLaunchRefreshesResumableImport; RunCoordinatorTests/testPhotosTransferUsesContextCleansStagingAndClears | H-PIR-2 | pass (5e405f8) | todo-hardware |
| A-PIR-07 | PhotoKit stays read-only (INV-22) | PhotosExportExecutorTests (tagged 22); script/check_photos_import_readonly.sh | — | pass (d60fd7e) | n/a |
| A-PIR-08 | Copy is plain, says the library was not changed | PhotosPreparationTextTests/*; PhotosImportResumeTests message assertions | H-PIR-5 | pass (4c11529) | todo-hardware |
