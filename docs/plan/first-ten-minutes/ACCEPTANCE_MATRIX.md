# First ten minutes — acceptance matrix

| ID | Requirement (Round 3 #5) | Automated coverage | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-FTM-01 | Capacity and access are checked before a run, with labeled estimates | RunPreflightAssessmentTests/*; PreflightServiceTests/*; SetupScreenModelTests (2 new); SetupCoordinatorTests (2 new) | H-FTM-1, H-FTM-2 | todo | todo-hardware |
| A-FTM-02 | Photos staging space is shown as a fact | AppStateTests/testPhotosStagingCheckRefreshesFromStagingParent | — | todo | n/a |
| A-FTM-03 | First-time users are offered a small verified batch without a refusal | FirstRunTestBatchTests/*; RunWorkspaceModelTests/testOffersTestBatchOnlyForFirstRunWithEnoughFiles; AppStateTests/testStartFirstRunTestBatchStartsTransferWithSelection | H-FTM-3 | todo | todo-hardware |
| A-FTM-04 | After the batch: files shown, undo available through the hash-checked revert | RunProofModelTests/*; AppStateTests/testProofCardUndoRevertsThatReceiptOnly | H-FTM-3 | todo | todo-hardware |
| A-FTM-05 | Experienced users keep the direct path | RunWorkspaceModelTests/testOffersTestBatchOnlyForFirstRunWithEnoughFiles; AppStateTests/testNoTestBatchAfterFirstReceipt; SetupScreenModelTests/testCanStartRunUnchangedByPreflight | — | todo | n/a |
