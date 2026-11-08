# Find and account — decisions

Prefix `FAA`. Runtime decisions appended as `D-FAA-1NN`.

## Tie-break rule for new gaps
Keep every invariant (INV-08, INV-09, INV-26 and the new INV-30 above all); fewest changed lines; copy the named reference pattern; fail closed (report unresolved rather than infer). Log as `D-FAA-1NN`.

- **D-FAA-01 Branch.** `feature/find-and-account` from `main` after `feature/photos-import-resume` merged (or after `dedupe-persistence` if the owner reorders; edit this line). Never push.
- **D-FAA-02 One index, two faces.** Reconciliation after a run and cross-run lookup read the same `RunOutcomeRecord`; the lookup index is a derived cache in Application Support rebuilt from records and receipts. Deleting `lookup/index.db` loses nothing.
- **D-FAA-03 Receipt is the only proof of a copy.** The record never upgrades a `CopyJobs` COPIED row to `copiedVerified` without a receipt entry (AGENTS.md "Organize recovery tracks"). Such a row becomes `unresolved` with detail "copied but not in the receipt; verify in History".
- **D-FAA-04 Record is written by the engine, not the executor.** `SwiftOrganizerEngine` owns it so `TransferExecutor` (safety-critical) is untouched. The record is best-effort: a write failure is a warning, never a run failure.
- **D-FAA-05 Record location.** `<destination>/.organize_logs/run_outcome_<stem>.json`, written with `DestinationMetadataFile.replaceFile` (INV-26). It is an artifact like the receipt and is indexed by `RunHistoryIndexer` as `runOutcome`.
- **D-FAA-06 "Changed" outcome.** The executor already reports identity mismatches as failures with a message; the builder maps a FAILED job whose detail contains the executor's changed-identity wording to `.changed`, else `.failed`. The implementer records the exact wording it matched in a runtime decision.
- **D-FAA-07 Exclusions are counted fully and listed up to 5,000 paths.** Beyond that, counts only, and the record says so in the UI ("and N more").
- **D-FAA-08 Presence never deletes and never follows links.** `POSIXFilesystemPresenceChecker` (lstat semantics) is the single presence primitive for revert, viewer and lookup.
- **D-FAA-09 Revert change is reporting-only.** Inaccessible paths are skipped and counted as `unavailableCount`; nothing about the hash gate (INV-08) changes. The WP is still treated as safety-critical with an orchestrator diff review.
- **D-FAA-10 Legacy receipts index as copiedVerified only.** Runs before this plan have no outcome record; their receipts are indexed so lookup works for old archives, with no claims about non-copied items.
- **D-FAA-11 Search scope.** Substring, case-insensitive, over the original filename; optional source-folder prefix and date range. No fuzzy matching, no content search, no thumbnails.
- **D-FAA-12 Multi-destination.** The index spans every destination the History tab has indexed. History itself stays single-root; the Files face shows the destination root per hit.
- **D-FAA-13 Test placement.** Core: `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreRunOutcome*Tests.swift`, `ChronoframeCoreMediaLookupIndexTests.swift`; AppCore: `MediaLookupStoreTests.swift`, additions to `HistoryStoreTests.swift`; App: `RunOutcomeDetailSheetTests.swift`, `MediaLookupViewTests.swift`, additions to `ReceiptVerificationTests.swift`.

## Runtime decisions
