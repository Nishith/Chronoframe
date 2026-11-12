# Clear path — acceptance matrix

Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`. Only Nishith sets `pass-hardware`.

| ID | Requirement (review finding) | Automated coverage (class/method) | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-CLP-01 | Several folders can be listed, removed and remembered as "folders to organize" (1) | SourceItemListTests/*; SetupCoordinatorTests/testAddSecondFolderStagesBothAndLabelsCount, testRemoveBackToOneFolderDropsStaging, testBootstrapRestoresListAndRestages; SetupScreenModelTests/testRowsComeFromSourceItems | H-CLP-1 | todo | todo-hardware |
| A-CLP-02 | A listed folder can never overlap the destination, at selection and in the engine (1, INV-21) | MultiItemSourceOverlapTests/* (tagged 21); SourceItemListTests/testAddOverlappingDestinationThrows; SetupCoordinatorTests/testSelectDestinationOverlappingListedFolderIsRefused | H-CLP-1 | todo | todo-hardware |
| A-CLP-03 | No engine vocabulary on Organize and Deduplicate screens (2) | SetupScreenModelTests/testNoUserVisibleSetupStringContainsBannedWord; RunWorkspaceModelTests/testHeroCopyNeverSaysTransferOrRun, testMetricTileTitlesMatchContract; DeduplicateReviewViewsTests/testNoVisibleDedupeStringSaysCluster; RunSessionStoreTests/testConfirmPromptCopyMatchesContract; G2 step 4 sweep | H-CLP-6 | todo | todo-hardware |
| A-CLP-04 | Stop and failure copy still says originals were not changed (INV-10) | RunWorkspaceModelTests/testFailureAndStopCopySayOriginalsNotChanged; RunSessionStoreTests/testBlockingBatchPromptSaysOriginalsNotChanged | — | todo | n/a |
| A-CLP-05 | Tabs read as a sequence; one primary action per screen; a copy cannot start from Setup (3) | ChronoframeCoreOrganizeNavigationTests/*; OrganizeContainerViewTests/testTabsFollowDisplayOrder, testDividerPrecedesFirstSecondaryTabOnly; reviewer reads WP-05 and WP-07 diffs | H-CLP-4, H-CLP-6 | todo | todo-hardware |
| A-CLP-06 | The folder layout and a real example are visible before the preview (4) | FolderLayoutPresentationTests/* | H-CLP-6 | todo | todo-hardware |
| A-CLP-07 | The preview result is one sentence plus exception rows (5) | RunPreviewHeadlineTests/*; RunWorkspaceModelTests/testHeroCopyMatchesContractForEveryStatus | H-CLP-2 | todo | todo-hardware |
| A-CLP-08 | A finished copy offers Deduplicate as the next step (6) | RunWorkspaceModelTests/testNextStepOnlyAfterFinishedCopyWithCopies, testNextStepBodyWithAndWithoutSetAsideCopies | H-CLP-6 | todo | todo-hardware |
| A-CLP-09 | Dedupe review opens with two lanes; "safe" only for eligible groups; one name for the bulk action (7, INV-06) | DeduplicateReviewLanesTests/* (tagged 6); TipsTests | H-CLP-3 | todo | todo-hardware |
| A-CLP-10 | Health shows no score and no warning before the first copy (8) | ChronoframeCoreLibraryHealthScannerTests/testNoReceiptsIsGoodAndSaysNothingToUndo, testHasOrganizedHistoryFalseWithoutReceipts, testOverallSeverityOfUntouchedDestinationIsGood | — | todo | n/a |
| A-CLP-11 | Identifiers, raw values, receipts, CLI and dedupe store/planner are unchanged | ChronoframeCoreOrganizeNavigationTests/testRawValuesAreUnchanged; OrganizeContainerViewTests/testTabIdentifiersUseRawValues; DeduplicateSessionStoreTests (unchanged); CLIIntegrationTests (unchanged, in suite) | H-CLP-4 | todo | todo-hardware |
| A-CLP-12 | VoiceOver reads every new control and sentence | AccessibilityTests; DeduplicateAccessibilityTextTests | H-CLP-3 | todo | todo-hardware |
