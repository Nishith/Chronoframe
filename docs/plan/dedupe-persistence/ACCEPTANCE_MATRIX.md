# Dedupe persistence — acceptance matrix

Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`.

| ID | Requirement (Round 3 #2) | Automated coverage | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-DDP-01 | Decisions, reviewed groups and position survive relaunch | DeduplicateReviewPersistenceTests/testCompleteRestoresMatchingDecisionsAndApprovals, testDecisionChangeSavesAfterDebounce, testFlushPendingSaveWritesImmediately; RestorerTests/testFocusMapsToMatchingCluster; PersistenceTests/testStartScanFlushesPendingSave; AppStateTests/testWillTerminateFlushesDedupeReviewSave | H-DDP-1 | pass (3661b89) | todo-hardware |
| A-DDP-02 | Restore only against matching content (INV-29) | RestorerTests/testRestoresDecisionOnlyWhenIdentityMatches, testApprovalNotRestoredWhenAMemberChanged; PersistenceTests/testCompleteDropsChangedIdentityAndReportsIt; RestorerTests/testApprovalNotRestoredWhenAMemberPathChanged | H-DDP-2 | pass (3661b89) | todo-hardware |
| A-DDP-03 | Trash still requires explicit review and commit | PersistenceTests/testRestoredApprovalStillRequiresPrepareAndCommit; RestorerTests/testRestoreNeverSetsHardDelete | H-DDP-3 | pass (3661b89) | todo-hardware |
| A-DDP-04 | Saved review removed after commit, kept across folder changes | PersistenceTests/testCommitCompleteRemovesSnapshot, testResetSavesBeforeClearing | H-DDP-3 | pass (3661b89) | todo-hardware |
| A-DDP-05 | Copy explains what was restored, changed and cleared | DeduplicateReviewCopyTests/* | H-DDP-4 | pass (3661b89) | todo-hardware |
