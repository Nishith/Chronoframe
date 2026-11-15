# NAS v1 implementation plan

Status: approved plan. Scope: `docs/NAS_REQUIREMENTS.md` v1.0, P0 slices 0, 1a, 1b and 1c. Everything marked P1 or Deferred there is out of scope.

Read first: `NAS_AGENT_RULES.md`, `CONTRACTS.md`, `DECISIONS.md`. Status lives in `PROGRESS.md`; test traceability lives in `ACCEPTANCE_MATRIX.md`.

## Execution model

- Work packages (WPs) run **one implementer at a time** in this single checkout. SwiftPM shares one `ui/.build`, so a half-finished package would break another package's build. "Waves" below express dependencies only.
- After each WP: the reviewer subagent reviews it, the orchestrator runs the WP's Done-when commands, updates `PROGRESS.md`, and commits the WP's owned paths with message `NAS <WP-ID>: <title>`.
- Every WP's tests are written from its acceptance bullets **before** the production code, and must fail before the change (the implementer records one failing run in its report).
- A WP may edit only its owned paths. A needed change outside them goes to `BLOCKED.md`.

Shorthand used below (created in WP-00):

```bash
docs/plan/nas-v1/bin/nas_swift.sh build
docs/plan/nas-v1/bin/nas_swift.sh test <XCTest filter>
```

## Dependency waves

| Wave | WPs | Depends on |
|---|---|---|
| 0 | WP-00 | none |
| 1 | WP-01, then WP-02; WP-03; WP-04 | WP-00 (WP-02 also needs WP-01) |
| 2 | WP-05, WP-06, WP-07, WP-08 | wave 1 |
| G2 | gate | wave 2 |
| 3 | WP-09, WP-10 | G2 |
| 4 | WP-11 | WP-10 |
| 5 | WP-12 | WP-11 |
| G3 | final gate | all |

Run order: WP-00 → WP-01 → WP-02 → WP-03 → WP-04 → WP-05 → WP-06 → WP-07 → WP-08 → G2 → WP-09 → WP-10 → WP-11 → WP-12 → G3.

---

## WP-00 — Branch, shared models and baseline (orchestrator)

- **Model:** orchestrator (Opus). Not delegated.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASModels.swift` (new), `docs/plan/nas-v1/bin/nas_swift.sh` (new), `docs/plan/nas-v1/**`, `docs/NAS_REQUIREMENTS.md`, `docs/NAS_REQUIREMENTS_REVIEW_LOG.md`.
- **Precondition (owner, before kickoff):** the subagent and permission files in `docs/plan/nas-v1/claude-config/` are installed into `.claude/` (see `ORCHESTRATOR_KICKOFF.md`). If `.claude/agents/nas-implementer.md` is missing, log `BLOCKED.md` B-1 and stop. The installed `.claude/` copies are local configuration and are never committed.
- **Contracts:** C-01. **Decisions:** D-NAS-01, 02, 03.
- **Steps:**
  1. `git status --porcelain` and record it in `PROGRESS.md` under "Checkout at start". Do not touch anything listed there except this WP's paths.
  2. `git switch -c feature/nas-v1 codex/stable-invariant-ids`. If the branch exists, `git switch feature/nas-v1`. If switching is refused because of local changes to tracked files, log in `BLOCKED.md` and stop the run (owner must decide).
  3. Create `docs/plan/nas-v1/bin/nas_swift.sh` exactly:
     ```bash
     #!/usr/bin/env bash
     set -euo pipefail
     ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"
     export HOME="$ROOT/.tmp/home"
     export XDG_CACHE_HOME="$ROOT/.tmp/home/Library/Caches"
     export CLANG_MODULE_CACHE_PATH="$ROOT/.tmp/modulecache"
     export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT/.tmp/modulecache"
     mkdir -p "$XDG_CACHE_HOME" "$CLANG_MODULE_CACHE_PATH"
     cd "$ROOT"
     case "${1:-}" in
       build) swift build --package-path ui --build-tests --disable-sandbox ;;
       test) swift test --package-path ui --disable-sandbox --filter "${2:?usage: nas_swift.sh test FILTER}" ;;
       *) echo "usage: nas_swift.sh build | test FILTER" >&2; exit 2 ;;
     esac
     ```
     then `chmod +x docs/plan/nas-v1/bin/nas_swift.sh`.
  4. Create `ui/Sources/ChronoframeCore/NASModels.swift` with the C-01 code block verbatim.
  5. Run `docs/plan/nas-v1/bin/nas_swift.sh build`, `script/check_agents_invariants_have_tests.sh`, and the full suite once with `/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache script/run_swift_test_suites.sh"`. Record exit codes and durations in `PROGRESS.md` "Baseline".
  6. `git add` exactly: `docs/NAS_REQUIREMENTS.md docs/NAS_REQUIREMENTS_REVIEW_LOG.md docs/plan/nas-v1 ui/Sources/ChronoframeCore/NASModels.swift`; commit `NAS WP-00: plan, shared models and baseline`.
- **Done when:** build exit 0; invariant guard exit 0; baseline suite result recorded (a pre-existing failure is recorded, not fixed); commit exists.

---

## WP-01 — Volume classifier and system-container rules

- **Model:** nas-implementer (Sonnet).
- **Owned paths:** `ui/Sources/ChronoframeCore/NASVolumeClassifier.swift`, `ui/Sources/ChronoframeCore/NASSystemContainerRules.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASVolumeClassifierTests.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASSystemContainerRulesTests.swift`.
- **Read for reference:** `DestinationOperationLock.swift` lines 70–95 (current remote detection).
- **Contracts:** C-02, C-03. **Decisions:** D-NAS-15, 33.
- **Acceptance (test name → bullet):**
  - `testParsesSMBMountedFromWithUser` → C-02 case 1.
  - `testParsesSMBMountedFromWithDomainPasswordPortAndPercentEncoding` → case 2, and asserts neither "nishith" nor "secret" appears in the observation's `String(describing:)`.
  - `testParsesSMBMountedFromWithEmptyShare` → case 3.
  - `testParsesNFSMountedFrom` → case 4.
  - `testLocalDeviceHasNoServerOrShare` → case 5.
  - `testRemoteFileSystemTypeIsRemoteEvenWithLocalFlag` → smbfs + MNT_LOCAL ⇒ remote.
  - `testMissingLocalFlagIsRemote` → unknown fstype, no MNT_LOCAL ⇒ remote.
  - `testLocalAPFSIsLocal`.
  - `testWalksToNearestExistingAncestor` → statfs nil for the leaf, non-nil for the parent ⇒ `observedPath` is the parent.
  - `testAllStatfsFailuresAreUnknown`.
  - `testLiveClassifierOnTemporaryDirectoryIsLocal` (real statfs on `FileManager.default.temporaryDirectory`).
  - `testFileSystemIDPacksBothWords`.
  - `testExcludesSynologyContainersCaseInsensitively` → `@eaDir`, `#RECYCLE`, `#snapshot`.
  - `testDoesNotMatchSubstringsOrSimilarNames` → `backup`, `My #recycle notes`, `@eaDirX`, `eaDir`.
- **Done when:** `nas_swift.sh test ChronoframeCoreNASVolumeClassifierTests` and `nas_swift.sh test ChronoframeCoreNASSystemContainerRulesTests` pass; `nas_swift.sh build` passes.

## WP-02 — Library identity and share lease key

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASLibraryIdentity.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASLibraryIdentityTests.swift`.
- **Contracts:** C-04 (uses C-02). **Decisions:** D-NAS-30, 31, 32.
- **Acceptance:**
  - `testSameObservationIsSame`.
  - `testDifferentMountPointIsRemounted` → T05 remount.
  - `testLocalDirectoryAtOldMountPathIsMismatchNotRemote` → T05 local fallback directory.
  - `testReplacedShareWithSameNameIsMismatchByRootFileID` → T05 same-name replacement.
  - `testShareNameCompareIsCaseInsensitive`.
  - `testRootRelativePathCompareIsNFCAndCaseInsensitive` (NFD "é" vs NFC "é").
  - `testServerHostChangeIsAmbiguous`.
  - `testMissingShareNameIsAmbiguous`.
  - `testMismatchTakesPrecedenceOverAmbiguous` and asserts reason order matches C-04.
  - `testCreationTimeWithinOneSecondIsIgnored` and `testCreationTimeChangeIsMismatch`.
  - `testObserveComputesRootRelativePath` (mount `/Volumes/photo`, root `/Volumes/photo/Family` ⇒ `Family`; root equal to mount ⇒ "").
  - `testObserveRejectsSymlinkRoot` and `testObserveRejectsFileRoot`.
  - `testLeaseKeyIgnoresServerHost` → two observations differing only in host give the same key.
  - `testLeaseKeyDiffersByShareAndShareRootFileID`.
  - `testLeaseKeyIsThirtyTwoLowercaseHex`.
- **Done when:** `nas_swift.sh test ChronoframeCoreNASLibraryIdentityTests` passes; build passes.

## WP-03 — Metered file reader

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASMeteredFileReader.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASMeteredFileReaderTests.swift`.
- **Read for reference:** `FileIdentityHasher.swift` (do not edit it).
- **Contracts:** C-05. **Decisions:** D-NAS-11.
- **Acceptance:**
  - `testDigestMatchesFileIdentityHasherForBoundarySizes` → sizes 1, 1 MiB − 1, 1 MiB, 1 MiB + 1, 3 MiB + 7 on real temp files.
  - `testCountsExactlyFileSizeBytes` → `bytesRead == size`.
  - `testShortReadsAreCountedByReturnedBytes` → injected `read` returning 1000-byte chunks; `bytesRead == size`, `readCalls` counts calls.
  - `testEINTRIsRetried`.
  - `testSizeChangedBeforeReadIsUnresolvedWithZeroBytes` → T21 enumeration-vs-descriptor.
  - `testGrowthDuringReadIsBytesConsumedMismatch` → injected read returns more bytes than expected.
  - `testTruncationDuringReadIsUnresolved` → early EOF ⇒ `bytesConsumedMismatch`.
  - `testPostReadSizeChangeIsUnresolved` → second fstat differs ⇒ `sizeChangedDuringRead`.
  - `testModificationTimeChangeIsUnresolved`.
  - `testSymlinkIsNotFollowed` → real symlink to a file ⇒ `openFailed` (ELOOP).
  - `testVolumeUnavailableErrnoMapping` → open with ENOTCONN ⇒ `volumeUnavailable`; read with ETIMEDOUT ⇒ `volumeUnavailable`; read with EIO ⇒ `readFailed`.
  - `testDescriptorClosedExactlyOnceOnEveryPath` → counting `close` seam over all outcomes above.
  - `testNonRegularFileIsUnresolved` → directory path.
- **Done when:** `nas_swift.sh test ChronoframeCoreNASMeteredFileReaderTests` passes; build passes.

## WP-04 — Assessment store

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASAssessmentStore.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASAssessmentStoreTests.swift`.
- **Read for reference:** `GuardianManifestStore.swift` (SQLite style), `OrganizerDatabase.swift` init (anchor sequence).
- **Contracts:** C-06. **Decisions:** D-NAS-20, 21.
- **Acceptance:**
  - `testCreatesSchemaAndMeta`.
  - `testRejectsDifferentLibraryUUID` → `storeLibraryMismatch`.
  - `testGenerationsIncrementFromOne`.
  - `testMarkCandidatesClassifiesUniqueEmptyAndCollidingSizes` → returns counts and H; unique sizes stay `notCandidate`.
  - `testPendingItemsOrderedBySizeDescending`.
  - `testExactGroupsRequireTwoHashedMembersAndSortByRedundantBytes`.
  - `testUnresolvedItemsNeverJoinGroups`.
  - `testSummaryRoundTripsCountsLedgerAndRedundantBytes`.
  - `testChoicesAndReviewStateSurvivePruning` → prune keeps 2 generations, choices intact.
  - `testFileIDRoundTripsAboveInt64Max` → `UInt64.max` survives.
  - `testRefusesSymlinkedStoreFile` → anchor behavior matches `OrganizerDatabaseLinkTests` style.
  - `testStoreErrorsUseStoreFailedWithoutLeakingInDescription` → `errorDescription` has no "SQLITE" text.
- **Done when:** `nas_swift.sh test ChronoframeCoreNASAssessmentStoreTests` passes; build passes.

---

## WP-05 — Assessment scanner

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASAssessmentScanner.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASAssessmentScannerTests.swift`, `ui/Tests/ChronoframeAppCoreTests/NASFixtureBuilder.swift` (test helper).
- **Read for reference:** `MediaDiscovery.swift` (traversal rules), `MediaDateResolver.swift` (`MediaLibraryRules`).
- **Contracts:** C-07 (uses C-01 to C-06). **Decisions:** D-NAS-10, 12–19, 22.
- **Test helper:** `NASFixtureBuilder` creates a temp tree from a declarative list (`file(path, bytes)`, `directory(path)`, `symlink(path, target)`, `fifo(path)`), returns root URL and a separate state directory, and offers `snapshot()` returning `[relativePath: (size, mtime, inode, mode)]` for every entry including dot files.
- **Acceptance (tag the read-only tests `// AGENTS-INVARIANT: 27`):**
  - `testRecursiveAssessmentFindsCrossFolderDuplicates` → T01, T07: identical bytes in `Curated/2018 Japan/a.jpg`, `Backup Copy/Photos/b.JPG`, `Old Mac/x.heic` group together; same-name different bytes don't.
  - `testUniqueSizeFilesAreNeverRead` → counting reader seam: zero `hash` calls for unique sizes (NAS-DED-01, NFR-09).
  - `testCleanBytesEqualCandidateBytesOnColdScanAndWithinBudget` → `bytesReadClean == H`, `isWithinBudget`.
  - `testZeroByteFilesAreEmptyNotGrouped`.
  - `testSynologyContainersExcludedAndReported` → duplicates inside `@eaDir`/`#recycle`/`#snapshot` never appear in groups; issues list them (T02).
  - `testSymlinksPackagesAndSpecialFilesAreReportedNotTraversed` → T02.
  - `testNestedMountIsNotCrossed` → fake file system with different `deviceID` for one child (NAS-SCP-04).
  - `testUnreadableDirectoryMakesAssessmentIncomplete` → T02 false-complete guard; outcome `completedWithGaps`.
  - `testExclusionsAloneKeepAssessmentComplete` → D-NAS-17.
  - `testUnresolvedCandidateMakesAssessmentIncomplete` → reader seam returns `sizeChangedBeforeRead`.
  - `testVolumeLossEndsWithInterruptedOutcome` → `entry(root)` starts returning nil mid-hash; no further reads scheduled.
  - `testCancellationFinishesWithCancelledSummary` → isCancelled flips during enumeration; stream finishes, does not throw.
  - `testWarmScanReusesDigestsWithoutReads` → second run: zero reads, `cacheHits == candidates`.
  - `testChangedFileIsRehashedOnWarmScan` → mtime change ⇒ reread exactly that file.
  - `testConcurrencyNeverExceedsWorkerCount` → reader seam tracks max in-flight with `workerCount = 3`.
  - `testAssessmentDoesNotWriteInsideReadOnlyRoot` (INV-27) → chmod tree read-only, outcome `complete`, `snapshot()` before == after.
  - `testAssessmentLeavesWritableRootByteIdentical` (INV-27) → same on a writable tree, including no new dot files.
  - `testRefusesStateInsideRoot` (INV-27) → `stateInsideLibrary`, no events.
  - `testRefusesSymlinkRoot`.
  - `testUnicodeAndCaseCollisionPathsAreDistinct` → NFD/NFC names and `IMG.jpg`/`img.jpg` on a case-sensitive-safe fixture are separate items (T03); skip the case pair with `XCTSkip` only when the temp volume is case-insensitive, and say so in the skip message.
  - `testSleepActivityBeginsAndEndsOnceForEveryOutcome` → fake activity provider over complete, cancelled and interrupted runs (NAS-REC-09).
- **Done when:** `nas_swift.sh test ChronoframeCoreNASAssessmentScannerTests` passes; build passes.

## WP-06 — Remote copy policy in TransferExecutor (safety-critical)

- **Model:** nas-implementer, then nas-reviewer, then an orchestrator line-by-line review of the `TransferExecutor.swift` diff.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASRemoteCopyPolicy.swift` (new), `ui/Sources/ChronoframeCore/TransferExecutor.swift` (modify per C-08 only), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASRemoteCopyPolicyTests.swift` (new).
- **Read for reference:** `ChronoframeCoreTransferExecutorBehaviorTests.swift` (how tests drive `executeQueuedJobs` and inject `exclusiveRename`), `TransferExecutorCrashRecoveryTests.swift`.
- **Contracts:** C-08. **Decisions:** D-NAS-40–43. **Change discipline:** CLAUDE.md "Surgical changes in safety-critical code": every changed line traces to a C-08 item. No renames, no refactors, no tightening elsewhere.
- **Acceptance (tag each with `// AGENTS-INVARIANT: 28`; also tag the no-overwrite tests `4`, the flush tests `2`, the verification test `3`):**
  - `testRemoteRunWithVerificationOffAbortsBeforeAnyJob` → no file in destination, receipt ABORTED with the C-01 message.
  - `testRemoteExclusiveRenameENOTSUPAbortsRunWithoutPlaceholder` → no empty placeholder, no final file, temp removed, later jobs not attempted, abortReason matches.
  - `testRemoteRenameNeverOverwritesForeignFinalPath` → foreign file created at the final name before rename ⇒ next collision name used and foreign bytes unchanged (T11 race).
  - `testLocalExclusiveRenameENOTSUPStillUsesPlaceholderFallback` → regression: local behavior unchanged.
  - `testRemoteFullFsyncUnsupportedFallsBackToFsync` → seam: F_FULLFSYNC −1/ENOTSUP, fsync 0 ⇒ copied.
  - `testRemoteFsyncFailureFailsCopyAndLeavesNoFinalFile` → fsync −1/EIO.
  - `testRemoteFullFsyncOtherErrorFailsCopy` → F_FULLFSYNC −1/EIO, fsync never called.
  - `testLocalFullFsyncFailureStillThrows` → regression.
  - `testRemoteMetadataFailureWarnsButCopies` → `copyMetadata` −1 ⇒ warning issue text from C-08 and verified final file.
  - `testRemoteDataFailureFailsCopy` → `copyData` −1.
  - `testRemoteSkipsClone` → `clone` seam never called.
  - `testRemoteVolumeChangeAbortsBeforeNextJob` → fsid seam changes after job 1; job 2 not prepared, no directory created for it.
  - `testRemoteAppleDoubleFilesCountedInOneInfoIssue` → create `._name` beside the final file in a seam hook; exactly one info issue with the count.
  - `testRemoteRunFatalErrorDoesNotCountTowardFailureThresholds`.
  - Existing suites `ChronoframeCoreTransferExecutorBehaviorTests`, `ChronoframeCoreTransferExecutorParityTests`, `TransferExecutorCrashRecoveryTests` pass unchanged.
- **Done when:** `nas_swift.sh test ChronoframeCoreNASRemoteCopyPolicyTests`, `nas_swift.sh test ChronoframeCoreTransferExecutor`, and `nas_swift.sh test TransferExecutorCrashRecoveryTests` pass; build passes; orchestrator review recorded in `PROGRESS.md`.

## WP-07 — Remote journal policy and share lease

- **Model:** nas-implementer, then nas-reviewer, then orchestrator diff review.
- **Owned paths:** `ui/Sources/ChronoframeCore/OrganizerDatabase.swift` (C-09 only), `ui/Sources/ChronoframeCore/DestinationOperationLock.swift` (C-10 only), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASJournalPolicyTests.swift`, `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASShareLeaseTests.swift`.
- **Read for reference:** `DestinationOperationLockTests.swift`, `OrganizerDatabaseLinkTests.swift`, `ChronoframeCoreDatabaseTests.swift`.
- **Contracts:** C-09, C-10. **Decisions:** D-NAS-32, 33, 44.
- **Acceptance (tag `// AGENTS-INVARIANT: 28`; lease tests also `19`):**
  - `testRollbackDeletePolicyReadsBackDeleteAndFull`.
  - `testRollbackDeleteLeavesNoWALOrSHMAfterWrites`.
  - `testRollbackDeleteConvertsIdleWALDatabase` → WAL db with no other connection converts.
  - `testRollbackDeleteRefusesWhileAnotherConnectionHoldsWAL` → `journalModeUnavailable`, `-wal` file still present, no sidecar deleted.
  - `testAutomaticPolicyUsesWALOnLocalVolume` → regression: local opens still report `wal`.
  - `testReadOnlyOpenIgnoresPolicy`.
  - `testJournalModeUnavailableDescriptionIsPlain` → C-09 message, no "SQLite".
  - `testRemoteDestinationsOnSameShareSerialize` → classifier seam maps two different temp destination folders to one share; second acquire throws `DestinationBusyError`; after release it succeeds (NAS-CON-06, T06 same-container contention).
  - `testMountAliasesShareOneLease` → same share name and share-root ID, different server host and mount point ⇒ busy.
  - `testDifferentSharesDoNotSerialize`.
  - `testLocalDestinationsNeverTakeCompanionLease` → regression.
  - `testNoLeaseDirectoryKeepsTodaysBehavior`.
  - `testCompanionReleasedWhenInRootLockFails` → in-root lock busy ⇒ companion free afterwards.
  - `testReleaseReleasesBothLocks`.
  - Existing `DestinationOperationLockTests`, `OrganizerDatabaseLinkTests`, `ChronoframeCoreDatabaseTests`, `ChronoframeCoreDatabaseExtraTests` pass unchanged.
- **Done when:** the two new classes and the four existing classes pass via `nas_swift.sh test`; build passes; orchestrator review recorded.

## WP-08 — CLI refuses remote destinations

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCLIKit/CLI.swift` (C-11 only), `ui/Tests/ChronoframeCLIKitTests/NASRemoteDestinationRefusalTests.swift`.
- **Read for reference:** existing tests in `ui/Tests/ChronoframeCLIKitTests/` for how `CLI.run` is invoked with `output`/`input` closures.
- **Contracts:** C-11. **Decisions:** D-NAS-34.
- **Acceptance (tag `// AGENTS-INVARIANT: 28`):**
  - `testTransferToRemoteDestinationIsRefusedBeforeAnyWrite` → classifier seam marks the temp dest remote; after the throw the dest has no `.organize_logs` and no `.organize_cache.db`.
  - `testDryRunToRemoteDestinationIsRefused`.
  - `testRebuildCacheOnRemoteDestinationIsRefused`.
  - `testStartFreshOnRemoteDestinationIsRefused`.
  - `testRevertOnRemoteDestinationIsRefused` (receipt inside a remote-classified dest).
  - `testProfileDestinationOnRemoteVolumeIsRefused`.
  - `testUnknownVolumeIsRefused` (D-NAS-33).
  - `testRemoteSourceWithLocalDestinationIsAllowed` → `remoteDestinationRefusal` returns nil.
  - `testRefusalMessageAndExitCode` → C-11 text; exit code equals the usage-error code.
- **Done when:** `nas_swift.sh test NASRemoteDestinationRefusalTests` and `nas_swift.sh test ChronoframeCLIKitTests` pass; build passes.

---

## Gate G2 — Core and safety (orchestrator)

1. Append these two lines to `AGENTS.md` under `## Safety Invariants`, directly after the INV-26 bullet, byte for byte:
   ```markdown
   - **INV-27:** NAS assessment is read-only on the library. `NASAssessmentScanner` keeps all scan, review and lease state under Application Support (`nas/`), refuses a state location inside the assessed root, opens library files only read-only with `O_NOFOLLOW`, never creates, renames or deletes anything in the library, never reads a file whose size is unique in scope, and never reports complete coverage when a folder or file was unreadable, a candidate was unresolved, or the scan was interrupted.
   - **INV-28:** Network or unclassifiable destinations use the remote copy policy. Copy verification can't be turned off; flushing uses `F_FULLFSYNC` and falls back only to `fsync`, whose failure fails the copy; installation needs native `renamex_np`/`RENAME_EXCL`, an ENOTSUP aborts the run, and the placeholder check-then-rename fallback is never used; a destination volume change aborts before the next copy; `.organize_cache.db` opens with rollback `journal_mode=DELETE` verified by readback; app mutations hold the per-share Application Support lease; and the CLI refuses these destinations before writing anything.
   ```
2. Add to `MEANINGFUL_BASENAMES` in `script/swift_meaningful_coverage.sh`: `NASVolumeClassifier NASSystemContainerRules NASLibraryIdentity NASMeteredFileReader NASAssessmentStore NASAssessmentScanner NASRemoteCopyPolicy`.
3. Run: `script/check_agents_invariants_have_tests.sh`; the full sharded suite (WP-00 command); `script/swift_meaningful_coverage.sh`; `git diff --check`.
4. Commit `AGENTS.md` and the coverage script: `NAS G2: invariants 27-28 and coverage scope`.
- **Pass when:** all exit 0 and the coverage gate stays at or above its threshold. A coverage shortfall becomes a follow-up WP-05b/06b test card for the same implementer, not a threshold change.

---

## WP-09 — Probe, parity and corpus tool

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/NASProbe.swift`, `ui/Sources/ChronoframeCore/NASParityCheck.swift`, `ui/Sources/ChronoframeCore/NASCorpusGenerator.swift`, `ui/Sources/ChronoframeNASProbeTool/main.swift`, `ui/Package.swift` (add product and executable target only), `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreNASProbeTests.swift`, `docs/plan/nas-v1/EVIDENCE_LEDGER.md`.
- **Read for reference:** `ChronoframeVideoCalibrationTool/main.swift` and its `Package.swift` entry.
- **Contracts:** C-14. **Decisions:** D-NAS-60, 61.
- **Acceptance:**
  - `testProbeRefusesNonEmptyTestDirectory` → a `photo.jpg` in the test dir ⇒ refusal, nothing created.
  - `testProbeOnLocalVolumeRecordsAllChecksAndCleansUp` → APFS temp dir: P01–P07 present, P03/P04/P05 pass, workspace removed, test dir empty afterwards.
  - `testProbeExclusiveRenameOntoExistingKeepsBytes` → P04 digest unchanged.
  - `testProbeHeldWriterRecordsLatencyAndBusy` → P07 elapsed ≥ 1500 ms with timeout 30000, SQLITE_BUSY with timeout 0.
  - `testTrashProbeOnlyRunsWithFlag`.
  - `testCorpusGeneratorIsDeterministicAndManifestMatchesDisk` → same seed twice ⇒ identical manifests; every manifest digest equals `FileIdentityHasher`.
  - `testCorpusIncludesRequiredCases` → zero-byte, same-size-different-bytes, NFD name, excluded containers with duplicates.
  - `testParityCheckPassesOnGeneratedCorpus` → scanner groups equal manifest expected groups; ledger within budget.
  - `testParityCheckDetectsDifference` → manipulated expected set ⇒ `parity == false`.
  - `testParityRefusesStateInsideRoot`.
- `EVIDENCE_LEDGER.md` content: the table columns from `docs/NAS_REQUIREMENTS.md` section 17.2, one row per hardware item H1–H8 below, all status `todo-hardware`, plus the exact commands:
  ```bash
  ui/.build/debug/ChronoframeNASProbeTool probe --test-dir "/Volumes/<share>/<empty-test-folder>" > probe.json
  ui/.build/debug/ChronoframeNASProbeTool make-corpus --dest "/Volumes/<share>/<empty-corpus-folder>" --manifest "$HOME/nas-corpus-manifest.json" --files 10000 --duplicate-percent 20 --seed 42
  ui/.build/debug/ChronoframeNASProbeTool assess-parity --root "/Volumes/<share>/<corpus-folder>" --state-dir "$HOME/nas-parity-state" > parity.json
  ```
- **Done when:** `nas_swift.sh test ChronoframeCoreNASProbeTests` passes; `nas_swift.sh build` passes (the tool target builds); `mkdir -p .tmp/nas-probe-smoke && ui/.build/debug/ChronoframeNASProbeTool probe --test-dir "$PWD/.tmp/nas-probe-smoke"` exits 0, prints JSON, and leaves `.tmp/nas-probe-smoke` empty.

## WP-10 — App Core services and workspace store

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeAppCore/Support/NASPaths.swift`, `ui/Sources/ChronoframeAppCore/Support/NASStartup.swift`, `ui/Sources/ChronoframeAppCore/Services/NASLibraryRegistry.swift`, `ui/Sources/ChronoframeAppCore/Services/NASReconnectProbe.swift`, `ui/Sources/ChronoframeAppCore/Services/NASAssessmentEngine.swift`, `ui/Sources/ChronoframeAppCore/Stores/NASWorkspaceStore.swift`, `ui/Sources/ChronoframeAppCore/Services/FolderAccessService.swift` (C-12 addition only), `ui/Sources/ChronoframeAppCore/Support/UserFacingErrorMessage.swift` (add `NASAssessmentError` and `NASRemoteCopyError` cases to the existing type switch only), tests `ui/Tests/ChronoframeAppCoreTests/NASLibraryRegistryTests.swift`, `NASReconnectProbeTests.swift`, `NASAssessmentEngineTests.swift`, `NASWorkspaceStoreTests.swift`, `NASUserFacingErrorTests.swift`.
- **Read for reference:** `GuardianPaths.swift`, `DeduplicateSessionStore.swift` and `DeduplicateEngine.swift` (store/engine pattern), `DeduplicateSessionStoreTests.swift` (mock engine pattern), `FolderAccessService.swift`.
- **Contracts:** C-12. **Decisions:** D-NAS-21, 22, 30, 31, 52.
- **Acceptance:**
  - Registry: `testLoadMissingFileIsEmpty`, `testUpsertReplacesByUUIDAndPersists`, `testRegistryFileNeverContainsUserInfo` (record built from an observation parsed from a mount string with user and password).
  - Probe: `testValidatedStartPathForSameLibrary`, `testValidatedStartPathNilOnMismatch`, `testValidatedStartPathTimesOutWithoutBlockingMainActor` (observe sleeps 5 s; result nil within ~2.5 s; a main-actor task completes meanwhile).
  - Engine: `testAssessStreamsScannerEventsAndPersistsSnapshot` (local temp root using an injected "remote" observation), `testSaveChoiceAndSelectedDigestRoundTrip`, `testRecordPreviewRequestIncrementsCounter`.
  - Store (mock engine): `testLoadSavedLibrarySameGoesReady`, `testRemountUpdatesRecordAndGoesReady`, `testAmbiguousRequiresConfirmation`, `testConfirmIdentityAcceptsAndKeepsChoices`, `testMismatchShowsDifferentFolderAndNewChoiceGetsNewUUID` (T05/NAS-CON-03), `testUnreachableBookmarkGoesWaitingForNAS`, `testChooseLocalFolderIsRefused`, `testStartStopTransitions` (`assessing` → `stopping` → finished), `testVolumeInterruptionGoesWaitingForNAS`, `testIncompleteOutcomeShowsIncomplete`, `testSelectNeverRequestsPreview`, `testRequestPreviewIsTheOnlyPreviewTrigger`, `testStaleChoiceDetected`, `testSavedReviewIsNotMutationAuthority` (no API on the store or engine deletes, moves or trashes; assert via a mock engine that records every call).
  - Errors: `testNASErrorsMapToTheirDescriptions`.
  - `NASStartup`: `testConfigureSetsLeaseDirectoryIdempotently`.
- **Done when:** each new test class passes via `nas_swift.sh test`; `nas_swift.sh test DeduplicateSessionStoreTests` and `nas_swift.sh test SetupStoreTests` still pass; build passes.

## WP-11 — NAS Library workspace UI

- **Model:** nas-implementer.
- **Owned paths:** `ui/Sources/ChronoframeCore/ProfileModels.swift` (`SidebarDestination` only), `ui/Sources/ChronoframeApp/App/AppState.swift` (store wiring and `NASStartup.configure()` only), `ui/Sources/ChronoframeApp/Views/RootSplitView.swift` (one case), `ui/Sources/ChronoframeApp/Views/SidebarView.swift` (new case in existing switches only), `ui/Sources/ChronoframeApp/App/AccessibilityIdentifiers.swift` (new `enum NAS`), `ui/Sources/ChronoframeApp/Views/NAS/*.swift` (new), any other file the compiler reports as a non-exhaustive `switch` over `SidebarDestination` (add the case only, and list each in the report), tests `ui/Tests/ChronoframeAppTests/NASLibraryViewTests.swift`, `NASAccessibilityTextTests.swift`, `NASPreviewLoaderTests.swift`, `NASSidebarTests.swift`.
- **Read for reference:** `Views/Guardian/GuardianView.swift` (gated workspace), `Views/Deduplicate/DeduplicateView.swift`, `App/Motion.swift`, `docs/DESIGN_SYSTEM.md`, `script/check_detail_views_set_navigation_title.sh`, `script/check_no_raw_animations.sh`.
- **Contracts:** C-13. **Decisions:** D-NAS-05, 06, 50, 51.
- **Acceptance:**
  - `testSidebarHidesNASWhenDisabled` and `testSidebarShowsNASAfterDeduplicateWhenEnabled` (use `isEnabledOverride`; reset in `tearDown`).
  - `testNavigationTitleIsNASLibrary`.
  - `testEveryStateHasBannerCopy` → each `NASWorkspaceState` maps to the C-13 text.
  - `testNoDestructiveControlsExist` → the view model exposes no delete/move/trash action; the accessibility identifier list contains none.
  - `testPreviewLoaderNotCalledOnSelectionOrAppear` and `testPreviewLoaderRendersOnceAfterExplicitRequestAndCaches` (injected renderer closure).
  - `testRedundantBytesLabelSaysNotSpaceFreed`.
  - `testAccessibilityLabelsCoverEveryControl`.
  - `testKeeperCaptionStatesNoDeletion`.
  - Guards pass: `script/check_detail_views_set_navigation_title.sh`, `script/check_no_raw_animations.sh`, `script/check_app_layer_changes_have_tests.sh codex/stable-invariant-ids`.
- **Done when:** the new App test classes, `SidebarViewTests`, `AppStateTests` and `AccessibilityTests` pass via `nas_swift.sh test`; build passes; the three guards exit 0.

## WP-12 — Documentation

- **Model:** nas-implementer.
- **Owned paths:** `docs/SAFETY_AND_RECOVERY.md`, `docs/TECHNICAL.md`, `docs/TROUBLESHOOTING.md`, `docs/FAQ.md`, `CLAUDE.md` (on-disk artifacts note only).
- **Contracts:** C-01, C-08–C-13. **Decisions:** D-NAS-06, 07, 40.
- **Content (change only these sections; list them in the report):**
  - SAFETY_AND_RECOVERY: a "Network destinations" subsection stating INV-28 in plain words, and a "NAS assessment" subsection stating INV-27, that review choices are not deletion approvals, and that cleanup on a NAS is not offered.
  - TECHNICAL: the `nas/` Application Support layout (`libraries.json`, `libraries/<uuid>/assessment.db`, `leases/`), the journal policy, and the probe tool commands.
  - TROUBLESHOOTING: the C-13 and C-01 messages and the action for each ("Waiting for your NAS", "can't guarantee that a copy never replaces", "copy records on this network folder", CLI refusal).
  - FAQ: "Can Chronoframe remove duplicates on my NAS?" → not in this version, why (no recoverable Trash on network shares), what it does instead.
  - CLAUDE.md: under "On-disk artifacts", one sentence that NAS assessment state lives outside the library under Application Support `nas/`.
- **Done when:** `git diff --check` passes; every claim cites behavior that exists in code (reviewer checks each against the source).

---

## Gate G3 — Final (orchestrator)

1. Full sharded suite; `script/swift_meaningful_coverage.sh`; every CI guard script listed in `NAS_AGENT_RULES.md`; `git diff --check`.
2. Xcode lane: `xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug -derivedDataPath .tmp/ChronoframeDerivedData -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build`.
3. App smoke (verified, not just compiled): `(cd ui && ./build.sh)`, then `pkill -x Chronoframe || true`, then `open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app`. Select NAS Library in the sidebar, choose a local folder, and confirm the "Choose a folder on a network share" refusal. Capture the empty state and the refusal with `screencapture -x docs/plan/nas-v1/evidence/<name>.png` (or the session's screenshot tool). If capture is not permitted, log it in `BLOCKED.md` and mark the row `todo-hardware`. If a network share is mounted, also capture a completed assessment; otherwise that row stays `todo-hardware`.
4. Update `ACCEPTANCE_MATRIX.md` and `PROGRESS.md`; write `docs/plan/nas-v1/FINAL_REPORT.md` with: commits, commands with exit codes, compiled vs verified status per slice, open `BLOCKED.md` items, and the hardware checklist H1–H8.
5. Commit `NAS G3: final verification report`. Do not push.

## Hardware handoff (owner only; stays `todo-hardware` until Nishith records results)

| ID | Evidence | Requirement / test |
|---|---|---|
| H1 | `probe` JSON on the Synology SMB share (P01–P07), including whether RENAME_EXCL is supported | Slice 0, ADR-NAS-01/02/03, T06, T11 |
| H2 | `assess-parity` on the generated 10,000-file corpus: parity true, within budget, three matched cold runs | T21 P0, NAS-NFR-09, V1 reference corpus |
| H3 | Signed sandboxed build: choose share, assess, quit, relaunch, review restored, remount under another path | T04, T05, T09, T15 |
| H4 | Read-only share assessment shows no server-side changes | T04 |
| H5 | Disconnect, sleep and wake during a scan and during a copy | T16, NAS-REC-09 |
| H6 | Representative verified copy batch ≥ 100 files / 10 GiB to and from the share, plus a forced quota-full fault | T11, T18 |
| H7 | VoiceOver, keyboard, increased text and reduced motion pass over the NAS workspace | T20 |
| H8 | Latency, memory and cancel targets on the reference corpus | NAS-NFR-01–04 |
