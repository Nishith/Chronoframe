# NAS public — implementation plan

Status: proposal (prepared 2026-11-07). Prefix `NASP`. Branch `feature/nas-v1`. Read first: `docs/plan/next-half/AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`.

## Execution model
Same as every next-half plan (one implementer at a time; reviewer; orchestrator runs Done-when, logs, commits owned paths as `NASP <WP-ID>: <title>`). Shorthand `docs/plan/next-half/bin/cf_swift.sh`.

## Run order
WP-00 → WP-01 → WP-02 → WP-03 → WP-04 → G2. WP-02, WP-03 and WP-04 are independent of each other but run sequentially (shared build dir).

---

## WP-00 — Baseline (orchestrator)
1. `git switch feature/nas-v1`; `git status` clean of tracked modifications; `git log -1` is `4b992a4` or a descendant.
2. `cf_swift.sh build`, `cf_swift.sh suite`; record in `PROGRESS.md`.
- **Done when:** both exit 0.

## WP-01 — Deduplicate refuses network folders
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASDeduplicateFolderRefusal.swift` (new), `ui/Sources/ChronoframeAppCore/Services/DeduplicateEngine.swift`, `ui/Sources/ChronoframeAppCore/Support/UserFacingErrorMessage.swift`, `ui/Sources/ChronoframeApp/App/AppState.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASDeduplicateFolderRefusalTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/DeduplicateEngineNetworkRefusalTests.swift` (new), `ui/Tests/ChronoframeAppCoreTests/UserFacingErrorMessageTests.swift`, `ui/Tests/ChronoframeAppTests/AppStateTests.swift`, `ui/Tests/ChronoframeAppTests/TestSupport.swift` (harness: add the classifier parameter).
- **Read for reference:** `NASVolumeClassifier.swift:20–104`, `CLI.swift:536–539`, `DeduplicateEngineTrialGateTests.swift:104` (nothing-trashed pattern), `NetworkDestinationAdvisoryTests.swift:55`, `AppStateTests.swift:195, :218, :350, :463`.
- **Contracts:** C-01, C-02, C-03. **Decisions:** D-NASP-02…05, D-NASP-09, D-NASP-10.
- **Acceptance:**
  - `ChronoframeCoreNASDeduplicateFolderRefusalTests`: `testRemoteVolumeIsRefused` (smbfs), `testUnknownVolumeIsRefused` (statfs nil), `testLocalVolumeIsAllowed` (apfs, MNT_LOCAL), `testMessageMentionsNASLibraryOnlyWhenEnabled` (DEBUG override both ways; restore in tearDown). `// AGENTS-INVARIANT: 12` on the first.
  - `DeduplicateEngineNetworkRefusalTests`: `testScanOnRemoteFolderThrowsBeforeAcquiringLock` → no `.organize_logs/.chronoframe-operation.lock` created, no `.organize_cache.db` created; `testCommitOnRemoteFolderThrowsAndTrashesNothing` → fixture files untouched, no receipt written. `// AGENTS-INVARIANT: 12` on the second.
  - `UserFacingErrorMessageTests`: `testDeduplicateNetworkRefusalPassesThroughItsOwnMessage`.
  - `AppStateTests`: `testChooseDeduplicateFolderRefusesNetworkVolumeAndStoresNothing` (no bookmark, `lastDeduplicateDestinationPath` unchanged, `transientErrorMessage` equals C-01 text), `testUseDeduplicateHistoryFolderRefusesNetworkVolume`, `testStartDeduplicateScanRefusesNetworkFallbackDestination` (destination comes from `setupStore.destinationPath`; engine `scan` never called).
- **Done when:** `cf_swift.sh test ChronoframeCoreNASDeduplicateFolderRefusalTests`, `DeduplicateEngineNetworkRefusalTests`, `UserFacingErrorMessageTests`, `AppStateTests` exit 0; `script/check_agents_invariants_have_tests.sh` exit 0; build exit 0.

## WP-02 — Internalize `execute(queuedJobs:)` (safety-critical)
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/TransferExecutor.swift` (line 447 only).
- **Contracts:** C-04.
- **Acceptance:** `grep -n "public func execute(queuedJobs" ui/Sources/ChronoframeCore/TransferExecutor.swift` prints nothing; `grep -n "func execute(queuedJobs" …` prints one line; `cf_swift.sh test ChronoframeCoreTransferExecutorBehaviorTests` and `ChronoframeCoreTransferExecutorParityTests` exit 0.
- **Done when:** the two greps and two test runs as above; `git diff --stat` shows one file, one changed line. Orchestrator reads the diff (kickoff step 3d).

## WP-03 — Workspace validate timeout and keeper save failure
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Stores/NASWorkspaceStore.swift`, `ui/Sources/ChronoframeAppCore/Services/NASReconnectProbe.swift`, `ui/Sources/ChronoframeApp/Views/NAS/NASLibraryView.swift`, `ui/Tests/ChronoframeAppCoreTests/NASWorkspaceStoreTests.swift`, `ui/Tests/ChronoframeAppTests/NASLibraryViewTests.swift`.
- **Read for reference:** `NASWorkspaceStore.swift:214–240, :461–473`, `NASReconnectProbe.swift:10–56`, `NASWorkspaceStoreTests.swift:68–71` (fake `saveChoice`), `:635`.
- **Contracts:** C-05. **Decisions:** D-NASP-06.
- **Acceptance:**
  - `NASWorkspaceStoreTests`: `testValidateTimesOutIntoWaitingForNAS` (observe sleeps 5 s; state becomes waiting within 3 s; main actor stayed responsive — assert via a concurrent main-actor task completing), `testValidateCompletesNormallyUnderTimeout`, `testChooseKeeperSaveFailureKeepsResultsAndSetsMessage` (fake gains `saveChoiceError`), `testChooseKeeperSuccessClearsMessage`.
  - `NASLibraryViewTests`: `testKeeperSaveMessageRendersWhenPresent` and `testEveryStateHasBannerCopy` still passes.
- **Done when:** `cf_swift.sh test NASWorkspaceStoreTests`, `NASReconnectProbeTests`, `NASLibraryViewTests` exit 0; `script/check_no_await_in_xctassert.sh` exit 0; build exit 0.

## WP-04 — Comment fix, errata, docs, string lists
- **Model:** cf-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/DestinationOperationLock.swift` (lines 99–103 only), `docs/plan/nas-v1/CONTRACTS.md` (append only), `README.md`, `docs/FAQ.md`, `docs/TROUBLESHOOTING.md`, `docs/TECHNICAL.md`, `docs/plan/nas-public/strings-app.txt` (new), `docs/plan/nas-public/strings-core.txt` (new).
- **Contracts:** C-06, C-07, C-08, C-09.
- **Acceptance:** `git diff ui/Sources/ChronoframeCore/DestinationOperationLock.swift` shows only comment lines changed; each string list line matches a literal in the named source lines exactly (reviewer spot-checks 10); every doc sentence is true of the committed code.
- **Done when:** build exit 0 (comment change compiles); `git diff --check` exit 0; reviewer approves.

## Gate G2 — Final (orchestrator)
1. `python3 docs/plan/next-half/bin/add_xcstrings_keys.py ui/Sources/ChronoframeApp/Resources/Localizable.xcstrings docs/plan/nas-public/strings-app.txt` and the Core catalog with `strings-core.txt`. `python3 -c "import json;json.load(open('<each catalog>'))"` exit 0.
2. `cf_swift.sh suite`, `cf_swift.sh coverage` (add `NASDeduplicateFolderRefusal` to `MEANINGFUL_BASENAMES` first), `cf_swift.sh guards codex/stable-invariant-ids`, `cf_swift.sh xcode`, `git diff --check`.
3. cf-data-entry: update `docs/plan/nas-v1/ACCEPTANCE_MATRIX.md` gate 6 note (C-08) and this plan's matrix.
4. App smoke (verified, if launching is permitted): `ui/build.sh`; `open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app`; in Deduplicate choose any folder under `/Volumes/<smb share>` if one is mounted, else skip to the owner row; screenshot into `docs/plan/nas-public/evidence/dedupe-refusal.png`.
5. Commit: `NASP G2: strings, coverage scope, evidence`.
- **Pass when:** every command exits 0; invariant script shows INV-12 tags from WP-01; `EVIDENCE_LEDGER.md` carries H1–H8 (copied from `docs/plan/nas-v1/EVIDENCE_LEDGER.md`) plus H-NASP-1 and the flag-flip row, all `todo-hardware`.

## Owner handoff (todo-hardware)
See `EVIDENCE_LEDGER.md`: H1–H8 from the v1 ledger, H-NASP-1 (Deduplicate refusal on the real share), then the flag flip edit at `ui/Sources/ChronoframeCore/NASModels.swift:15–16` with the three doc lines to update (`docs/TECHNICAL.md:124`, `docs/plan/nas-v1/FINAL_REPORT.md:81`, `docs/plan/nas-v1/DECISIONS.md` D-NAS-06), then merge to `main`.
