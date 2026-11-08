# NAS public — acceptance matrix

Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`.

| ID | Requirement | Automated coverage | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-NASP-01 | Deduplicate never Trashes on a non-local volume (FINAL_REPORT item 1, D-NAS-135) | ChronoframeCoreNASDeduplicateFolderRefusalTests/*; DeduplicateEngineNetworkRefusalTests/*; AppStateTests (3 new) | H-NASP-1 | todo | todo-hardware |
| A-NASP-02 | Refusal copy is plain and points to NAS Library only when enabled | ChronoframeCoreNASDeduplicateFolderRefusalTests/testMessageMentionsNASLibraryOnlyWhenEnabled; UserFacingErrorMessageTests | — | todo | n/a |
| A-NASP-03 | Policy-less transfer entry point is not public (D-NAS-115) | grep + ChronoframeCoreTransferExecutorBehaviorTests | — | todo | n/a |
| A-NASP-04 | Dead share cannot stall the workspace (D-NAS-124) | NASWorkspaceStoreTests/testValidateTimesOutIntoWaitingForNAS | H5 | todo | todo-hardware |
| A-NASP-05 | Keeper save failure keeps results (D-NAS-129) | NASWorkspaceStoreTests/testChooseKeeperSaveFailureKeepsResultsAndSetsMessage; NASLibraryViewTests | — | todo | n/a |
| A-NASP-06 | NAS strings have catalog keys | G2 JSON validity + `grep -c` of each list line in the catalog | — | todo | n/a |
| A-NASP-07 | v1 hardware rows H1–H8 | (owner) | H1–H8 | n/a | todo-hardware |
