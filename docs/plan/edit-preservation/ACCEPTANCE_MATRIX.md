# Edit preservation — acceptance matrix

Status values: `todo`, `pass (<commit>)`, `fail`, `todo-hardware`, `pass-hardware (<date>, Nishith)`. Only Nishith sets `pass-hardware`.

| ID | Requirement | Automated coverage (class/method) | Hardware row | Auto status | Hardware status |
|---|---|---|---|---|---|
| A-EPR-01 | Photos import says originals only, edits not included | ChronoframeAppTests/testPhotosImportCaptionStatesOriginalsOnlyByDefault; testFAQMentionsPhotosEditsAreNotImported | H-EPR-6 | todo | todo-hardware |
| A-EPR-02 | `.aae` travels with its photo in Deduplicate (INV-14) | DeduplicatePairDetectorTests/testAAE*, testIMGE*; DeduplicateTests/testAAETrashedOnlyWhenEveryOwnerIsTrashed | H-EPR-1 | todo | todo-hardware |
| A-EPR-03 | Organize copies exactly-one-owner `.xmp`/`.aae` beside the photo, renamed with it | Companion*Tests/testCompanionResolverMatchesExactlyOneOwner; testCompanionDestinationFollowsOwnerCollisionSuffix; testCompanionDestinationFollowsOwnerDuplicateDirectory | H-EPR-2 | todo | todo-hardware |
| A-EPR-04 | Ambiguous or orphan companions are listed, not copied, and do not block | Companion*Tests/testRAWPlusJPEGSharedXMPIsUnresolved; testOrphanXMPIsUnresolved; testUnresolvedCompanionsListedInPreviewAndDoNotBlockRun | H-EPR-2 | todo | todo-hardware |
| A-EPR-05 | Companions never overwrite; receipted first; reverted with hash check | Companion*Tests/testExistingCompanionDestinationIsNeverOverwritten; testCompanionIsReceiptedBeforeCopy; testRevertRemovesCompanionWithOwnerAndChecksHash; testOrganizeThenRevertRestoresDestinationByteForByte | H-EPR-3 | todo | todo-hardware |
| A-EPR-06 | Source untouched; other scanners ignore companions | Companion*Tests/testSourceFilesAreUntouched; testMediaCountsAndOtherScannersIgnoreCompanions | — | todo | n/a |
| A-EPR-07 | Photos import exports edited still as a separate file, opt-in, original unchanged | PhotosExportExecutorTests/testOriginalsOnlyWhenOptionOffMatchesPreviousBehavior; testEditedStillExportedAsSeparateDistinctlyNamedFile; testOriginalBytesAndNameUnchangedWhenEditedExported | H-EPR-4 | todo | todo-hardware |
| A-EPR-08 | Edited-render failures and unsupported videos/Live Photos are reported, never silent | PhotosExportExecutorTests/testEditedRenderFailureRecordedAndOriginalStillCompleted; testVideoAndLivePhotoEditedRendersNotExported; PhotosImportStoreTests/testSummaryTextShowsOriginalsEditedAndCouldNotSaveCounts | H-EPR-4 | todo | todo-hardware |
| A-EPR-09 | Edited export is per-asset transactional, resumable and dated like the original | PhotosExportExecutorTests/testCancellationRollsBackEditedFileWithItsAsset; testResumeRepeatsRecordedIncludeEditedChoice; testEditedFileInheritsOriginalDateHint; PhotosImportCheckpointTests/testOldCheckpointDecodesWithEditedVersionsOff | H-EPR-5 | todo | todo-hardware |
| A-EPR-10 | PhotoKit stays read-only (INV-22, widened) | PhotosExportExecutorTests (tagged 22); script/check_photos_import_readonly.sh | — | todo | n/a |
| A-EPR-11 | Dedupe never auto-trashes an edited variant (INV-30) | DeduplicateTests/testHighConfidenceClusterNeverAutoSelectsEditedVariant; testDeletingOriginalDoesNotFanOutToEditedVariant; testExplicitUserDeleteOfVariantIsHonored; testFalsePositiveUserNamedEditedFileIsStillProtected | H-EPR-1 | todo | todo-hardware |
| A-EPR-12 | Every changed invariant has a tagged test | script/check_agents_invariants_have_tests.sh | — | todo | n/a |
