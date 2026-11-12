# Photos import resume — decisions

Plan prefix `PIR`. Resolves every gap the Round 3 review and the contracts leave open. Runtime decisions go at the bottom as `D-PIR-1NN`.

## Tie-break rule for new gaps
When a gap appears that no contract or decision covers, choose the option that, in this order: (1) keeps every `AGENTS.md` safety invariant, INV-22 above all; (2) changes the fewest existing files and lines; (3) copies an existing pattern from the reference file the WP names; (4) fails closed (refuse, mark unresolved, keep files and checkpoint, never delete). Log it as `D-PIR-1NN` with the WP ID, the options and the choice. Never use the tie-break to weaken a safety rule; log that in `BLOCKED.md` instead.

## Scope and process
- **D-PIR-01 Branch (revised 2026-11-12, owner).** `feature/photos-import-resume`, stacked on `feature/dedupe-persistence` @ 97fc546 (itself stacked on `feature/nas-v1`), because neither is merged to `main` yet. Guards that take a base ref use `feature/dedupe-persistence`. Never push; the owner opens the pull request. If the branch does not contain `docs/plan/photos-import-resume/`, WP-00 stops with a BLOCKED entry.
- **D-PIR-02 Plan location.** `docs/plan/photos-import-resume/`. Shared rules: `docs/plan/next-half/AGENT_RULES.md`.
- **D-PIR-03 Test placement.** AppCore tests in `ui/Tests/ChronoframeAppCoreTests/` named `Photos<Thing>Tests.swift` (matches `PhotosImportStoreTests.swift`); App tests in `ui/Tests/ChronoframeAppTests/` named `Photos<Thing>Tests.swift`. No XCUITests; `project.pbxproj` is never edited.
- **D-PIR-04 No bounded batches this plan.** Exporting the selection in batches and transferring each batch would require a reviewed plan per batch or a plan over not-yet-exported files. That changes the review contract. This plan keeps one staging set per import and makes it resumable and space-aware. Bounded batching stays NAS P1.
- **D-PIR-05 Capacity is a floor, not an estimate.** `PhotosAssetSummary` carries no byte size and PhotoKit has no public pre-export size. The executor checks free space before each asset and stops cleanly below 2 GiB (`defaultFreeSpaceFloorBytes`). No upfront estimate is shown as a number; the first-ten-minutes plan shows the staging volume's free space as a fact.
- **D-PIR-06 Checkpoint lives in the staging directory.** `<staging>/.chronoframe_photos_checkpoint.json`. The staging directory is the Organize source for the run; the file is hidden and `.json` is not a supported media extension, so discovery ignores it. `cleanupStaging(for:)` after a run removes it with the directory.
- **D-PIR-07 Resume validates existence and size, not content.** Rehashing gigabytes to offer a Resume card is wasteful; `DryRunPlanner.resolveSourceDate` already rehashes every hinted file at preview and aborts on an identity mismatch (`SourceDateHintError.changed`). Resume therefore checks each completed file exists with its recorded `identity.size`; the planner remains the content gate.
- **D-PIR-08 One resumable import at a time.** `refreshResumableImport` keeps the newest valid checkpoint and removes older staging directories. Starting a new import while one is resumable requires the confirmation dialog in C-05.
- **D-PIR-09 Strings.** New UI strings are Swift literals; the orchestrator adds English keys to `ui/Sources/ChronoframeApp/Resources/Localizable.xcstrings` and `ui/Sources/ChronoframeAppCore/Resources/LocalizableCore.xcstrings` at G2 with `docs/plan/next-half/bin/add_xcstrings_keys.py`. Translations are an owner step.
- **D-PIR-10 Failures are terminal per asset.** A failed asset is recorded in the checkpoint and skipped on resume; the user retries by selecting it again in a new import. No automatic retry.
- **D-PIR-11 Executor event payload.** `.assetCompleted` carries the asset's files and hints (C-04 amendment to C-02) so the store can checkpoint per asset without waiting for the receipt. The receipt type is unchanged.
- **D-PIR-12 Progress thresholds.** `isWaitingForCloud` turns on at the first `resourceProgress` with fraction < 1 for the current asset and off at that asset's completion or failure. No timers.
- **D-PIR-13 `isPreparingImport` stays.** It becomes computed from `preparation != nil` so `PhotosImportView` and existing tests keep compiling.
- **D-PIR-14 Staging override is DEBUG-only.** `CHRONOFRAME_PHOTOS_STAGING_DIR` lets the owner point staging at a small disk image to exercise the low-space path. Release ignores it.
- **D-PIR-15 AGENTS.md line 131 changes.** The sentence "Staging is deleted on completion, failure, or cancellation" is no longer true and is replaced by the C-08 text at G2 by the orchestrator. INV-22 is untouched; new executor and store tests are tagged `// AGENTS-INVARIANT: 22`.

## Runtime decisions
(appended by the orchestrator as D-PIR-1NN)
