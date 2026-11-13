# NAS public — acceptance matrix

Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`, `fail-hardware (<date>, Nishith)`.

| ID | Requirement | Automated coverage | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-NASP-01 | Deduplicate never Trashes on a non-local volume (FINAL_REPORT item 1, D-NAS-135) | ChronoframeCoreNASDeduplicateFolderRefusalTests/*; DeduplicateEngineNetworkRefusalTests/*; AppStateTests (3 new) | H-NASP-1 | pass (a6fc3d8) | todo-hardware |
| A-NASP-02 | Refusal copy is plain and points to NAS Library only when enabled | ChronoframeCoreNASDeduplicateFolderRefusalTests/testMessageMentionsNASLibraryOnlyWhenEnabled; UserFacingErrorMessageTests | — | pass (a6fc3d8) | n/a |
| A-NASP-03 | Policy-less transfer entry point is not public (D-NAS-115) | grep + ChronoframeCoreTransferExecutorBehaviorTests | — | pass (e6fa2e6) | n/a |
| A-NASP-04 | Dead share cannot stall the workspace (D-NAS-124) | NASWorkspaceStoreTests/testValidateTimesOutIntoWaitingForNAS | H5 | pass (abde28b) | todo-hardware |
| A-NASP-05 | Keeper save failure keeps results (D-NAS-129) | NASWorkspaceStoreTests/testChooseKeeperSaveFailureKeepsResultsAndSetsMessage; NASLibraryViewTests | — | pass (abde28b) | n/a |
| A-NASP-06 | NAS strings have catalog keys | G2 JSON validity + `grep -c` of each list line in the catalog | — | pass (G2) | n/a |
| A-NASP-07 | v1 hardware rows H1–H8 | (owner) | H1–H8 | n/a | H1 fail-hardware (2026-11-08, Nishith); H2–H8 todo-hardware |
| A-NASP-08 | Organize preview/transfer refuses a network destination without atomic no-replace rename, before planning (D-NASP-115) | ChronoframeCoreNASCopyDestinationQualifierTests/*; OrganizerEnginePrepareNetworkGateTests/* | H-NASP-3 | pass (076329e) | todo-hardware |
| A-NASP-09 | Refusal copy is plain and says originals were untouched | UserFacingErrorMessageTests/testCopyDestinationRefusalPassesThroughItsOwnMessage; RunSessionStoreTests/testPrepareRefusalSurfacesPlainMessage | — | pass (076329e) | n/a |
