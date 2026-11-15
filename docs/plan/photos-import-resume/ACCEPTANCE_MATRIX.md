# Photos import resume — acceptance matrix

Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`. Only Nishith sets `pass-hardware`.

| ID | Requirement (Round 3 #3) | Automated coverage (class/method) | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-PIR-01 | Per-asset progress and iCloud wait are visible | PhotosExportExecutorTests/testEventsFollowStartedProgressCompletedOrderPerAsset; PhotosImportResumeTests/testPreparationProgressTracksEventsAndCloudWait; PhotosPreparationTextTests/* | H-PIR-1 | todo | todo-hardware |
| A-PIR-02 | Stop keeps every completely exported asset, rolls back the in-flight one | PhotosExportExecutorTests/testCancellationStillRollsBackOnlyInFlightAsset; PhotosImportResumeTests/testStopKeepsCompletedAssetsAndMarksStopped | H-PIR-1 | todo | todo-hardware |
| A-PIR-03 | Resume exports only the remainder and preserves hints and order | PhotosImportResumeTests/testResumeSkipsCompletedAndMergesHints; PhotosImportCheckpointTests/testExportedAssetIDsFollowPlanOrderNotCompletionOrder | H-PIR-2 | todo | todo-hardware |
| A-PIR-04 | Resume revalidates destination, access and staged files | PhotosImportResumeTests/testResumeRefusedWhenDestinationDiffers, testRefreshRemovesInvalidAndConsumedStaging | H-PIR-4 | todo | todo-hardware |
| A-PIR-05 | Low staging space pauses cleanly and is resumable | PhotosExportExecutorTests/testLowSpaceStopsBeforeFirstWriteOfNextAsset; PhotosImportResumeTests/testLowSpaceMarksCheckpointAndOffersResume | H-PIR-3 | todo | todo-hardware |
| A-PIR-06 | Checkpoint survives relaunch; consumed or invalid staging is removed | PhotosImportCheckpointTests/testRoundTripThroughFileStorePreservesEveryField; AppStateTests/testLaunchRefreshesResumableImport; RunCoordinatorTests/testPhotosTransferUsesContextCleansStagingAndClears | H-PIR-2 | todo | todo-hardware |
| A-PIR-07 | PhotoKit stays read-only (INV-22) | PhotosExportExecutorTests (tagged 22); script/check_photos_import_readonly.sh | — | todo | n/a |
| A-PIR-08 | Copy is plain, says the library was not changed | PhotosPreparationTextTests/*; PhotosImportResumeTests message assertions | H-PIR-5 | todo | todo-hardware |
