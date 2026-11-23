# First ten minutes — decisions

Status: not started (verified 2026-11-22 on main 8308aac: `git grep` finds no `RunPreflightAssessment`, `PreflightService`, `FirstRunTestBatch` or `RunProofModel` in `ui/`). Intact. D-FTM-01 names the base branch; edit it before running (see its note).

Prefix `FTM`. Runtime decisions appended as `D-FTM-1NN`.

## Tie-break rule for new gaps
Keep every invariant; fewest changed lines; copy the named reference pattern; when a check cannot be made, show "unknown", never a guess. Log as `D-FTM-1NN`.

- **D-FTM-01 Branch.** `feature/first-ten-minutes` from `main` after `feature/find-and-account` merged. Never push. As of 2026-11-22 `find-and-account` is not built, so there is nothing to merge first; the two plans both edit `CurrentRunView.swift`, `AppState.swift` and `AccessibilityIdentifiers.swift`, so the owner picks the order and the later plan rebases its line references. `photos-import-resume` (#268, #270), `dedupe-persistence` (#267), nas-v1/nas-public (#266) and clear-path (#269, #274) are on `main`.
- **D-FTM-02 Preflight warns, the engine enforces.** A blocked destination-space check does not disable Start Copying: `TransferExecutor.checkDiskSpace` (`TransferExecutor.swift:1112`) already pauses safely, and since #265 a copy in flight also reserves its bytes (`:185`). Disabling would duplicate enforcement and could be wrong when the estimate is stale. Blocked source/destination access changes the step state copy so the user fixes it first, but `canStartRun` is unchanged.
- **D-FTM-03 Estimates are labeled.** Every space line that uses planned bytes says "estimate" and that it is rechecked when the copy starts.
- **D-FTM-04 Test batch is proactive only for first-time users.** First-time = no audit receipt in the current destination and zero organize allowance used. Everyone else keeps the direct path; the refusal-driven offer is untouched.
- **D-FTM-05 Batch size 25, oldest first.** Reuses `FreeTestBatchPlanner.batch(from:limit:)`; capped by remaining allowance. A plan of 25 or fewer files gets no offer.
- **D-FTM-06 Proof card reads the receipt, not the metrics.** Counts and folders come from the receipt the run wrote, found by run ID in the filename; if the receipt cannot be found, the card shows the metrics' copied count, no folder count, and no Undo (`canUndo == false`) with the line "Receipt not found yet; open History to undo."
- **D-FTM-07 Undo goes through the existing revert.** `appState.revertHistoryEntry(entry)` with its hash checks (INV-08) and allowance refund. No new deletion path.
- **D-FTM-08 Photos staging line is informational.** No size estimate is possible before export (see `docs/plan/photos-import-resume/DECISIONS.md` D-PIR-05); the line shows free space and says the import pauses when low.

> Stale since #268 (checked 2026-11-22): D-PIR-128 amends D-PIR-05, so each asset's size joins the executor's low-space threshold once its resources are listed (`PhotosExportExecutor.swift:129–222`, floor `defaultFreeSpaceFloorBytes` = 2 GiB). There is still no whole-import estimate before export, so this decision's line stands; its "pauses when low" text is now literally the executor's behaviour.
- **D-FTM-09 Setup step copy.** New states "Source Unavailable" / "Destination Unavailable" use the warning tone and the check's detail as the readiness message.
- **D-FTM-10 No new invariant.** Tests touching Undo are tagged `// AGENTS-INVARIANT: 8` where they assert the hash-checked path is used.
- **D-FTM-11 Test placement.** Core `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreRunPreflightAssessmentTests.swift`, `ChronoframeCoreFirstRunTestBatchTests.swift`; AppCore `PreflightServiceTests.swift`, additions to `SetupStoreTests.swift`, `RunSessionStoreTests.swift`; App `SetupScreenModelTests.swift`, `SetupCoordinatorTests.swift`, `RunWorkspaceModelTests.swift`, `RunProofModelTests.swift` (new), `AppStateTests.swift`.

## Runtime decisions
