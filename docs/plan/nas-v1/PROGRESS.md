# NAS v1 progress

Re-read this file, `NAS_AGENT_RULES.md` and `BLOCKED.md` after any context compaction before doing anything else.

## Plan authoring evidence (2026-11-07, before WP-00)
- `swift build --package-path ui --build-tests --disable-sandbox` with the local HOME/module-cache environment on `marketing/phase0-campaign-links` (634ec68): exit 0, "Build complete! (26.27 sec)".
- C-01 `NASModels.swift` extracted from CONTRACTS.md and type-checked with `xcrun swiftc -typecheck -swift-version 6` against that build's ChronoframeCore module: exit 0 with `-D DEBUG` and without it.
- `script/check_agents_invariants_have_tests.sh` on the relabeled invariants: exit 0, 26 of 26 covered.
- Not yet run on `feature/nas-v1`; WP-00 re-verifies there.

## Checkout at start
2026-11-07, branch `feature/nas-v1` already checked out at `e257003` (same commit as `codex/stable-invariant-ids`), so step 2 was a no-op. `git status --porcelain`:
```
?? docs/NAS_REQUIREMENTS.md
?? docs/NAS_REQUIREMENTS_REVIEW_LOG.md
?? docs/next-half-product-review-2026-11-07.md
?? docs/plan/
?? marketing/app-preview/
?? marketing/macapps-launch-post-2026-11.md
?? marketing/macapps-top-posts-2026-11-03.csv
?? marketing/product-video/
?? marketing/social-video/source-footage/
?? node_modules/
?? ui/.swiftpm/
?? ui/Sources/ChronoframeCore/NASModels.swift
```
`docs/plan/nas-v1/bin/nas_swift.sh` (mode 755) and `ui/Sources/ChronoframeCore/NASModels.swift` already existed; both were checked against the plan: the script matches WP-00 step 3 byte for byte, and `diff` of the C-01 code block against `NASModels.swift` printed nothing (identical). `.claude/agents/nas-*.md` match `claude-config/agents` (`diff -r` clean).

## Baseline
- `docs/plan/nas-v1/bin/nas_swift.sh build`: exit 0, 15 s ("Build complete! (13.63 sec)").
- `script/check_agents_invariants_have_tests.sh`: exit 0, <1 s, "All 26 safety invariants have at least one tagged test."
- Full sharded suite (`script/run_swift_test_suites.sh` with local HOME/module cache): exit 0, 86 s, 154 suites in 31 shards, no line reporting a non-zero failure count.

## Work packages

| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch, shared models, baseline | done | exit 0 | baseline suite exit 0 | n/a | (this commit) | build 0, invariants 0, suite 0 |
| WP-01 | Volume classifier, system containers | done | exit 0 | 12+2 pass | approve | (this commit) | classifier test 0, rules test 0, build 0 |
| WP-02 | Library identity, lease key | done | exit 0 | 18 pass | approve | (this commit) | identity test 0, build 0 |
| WP-03 | Metered file reader | done | exit 0 | 13 pass | approve | (this commit) | reader test 0, build 0; FileIdentityHasher.swift diff empty |
| WP-04 | Assessment store | done | exit 0 | 12 pass | approve | (this commit) | store test 0, build 0; follow-up: non-ELOOP anchor errors surface as POSIX NSError (WP-10 must map) |
| WP-05 | Assessment scanner | done | exit 0 | 21 pass, 1 partial skip | approve | (this commit) | scanner test 0 (case pair skipped: case-insensitive temp volume), build 0, invariants 0 |
| WP-06 | Remote copy policy (safety-critical) | done | exit 0 | 21 new + 39 + 4 pass | approve | (this commit) | policy 0, TransferExecutor 0, crash recovery 0, build 0, invariants 0; orchestrator diff review recorded in Log |
| WP-07 | Journal policy, share lease (safety-critical) | done | exit 0 | 7+7 new, 17+10+15+23 existing pass | approve | (this commit) | 6 test classes 0, build 0, invariants 0; orchestrator diff review recorded in Log |
| WP-08 | CLI remote refusal | todo | | | | | |
| G2 | Invariants 27–28, coverage, full suite | todo | | | n/a | | |
| WP-09 | Probe, parity, corpus tool | todo | | | | | |
| WP-10 | App Core services, workspace store | todo | | | | | |
| WP-11 | NAS Library UI | todo | | | | | |
| WP-12 | Documentation | todo | | | | | |
| G3 | Final gate and report | todo | | | n/a | | |

Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Log
(Append one line per event: date, WP, what happened, command and exit code.)
- 2026-11-07 WP-00: verified branch, script and C-01 file; build exit 0; invariant guard exit 0; full suite exit 0.
- 2026-11-07 WP-01: implementer compiled+tested (failing-first: compile error, missing NASSystemContainerRules); reviewer approve (round 1); orchestrator: nas_swift.sh test ChronoframeCoreNASVolumeClassifierTests exit 0 (12 tests), test ChronoframeCoreNASSystemContainerRulesTests exit 0 (2 tests), build exit 0.
- 2026-11-07 WP-02: implementer compiled+tested (failing-first: cannot find NASLibraryIdentity); reviewer approve (round 1); orchestrator: nas_swift.sh test ChronoframeCoreNASLibraryIdentityTests exit 0 (18 tests: 17 named + testZeroShareRootFileIDIsNotCompared), build exit 0.
- 2026-11-07 WP-03: implementer compiled+tested (failing-first: cannot find type NASMeteredFileReader); reviewer approve (round 1; non-blocking: growth test simulates via smaller fstat size rather than an injected oversized read); orchestrator: nas_swift.sh test ChronoframeCoreNASMeteredFileReaderTests exit 0 (13 tests), build exit 0.
- 2026-11-07 WP-04: implementer compiled+tested (failing-first: cannot find type NASAssessmentStore); reviewer approve (round 1; non-blocking: raw NSError from openAnchor for e.g. EACCES, same as OrganizerDatabase; extra behaviors untested); orchestrator: nas_swift.sh test ChronoframeCoreNASAssessmentStoreTests exit 0 (12 tests), build exit 0.
- 2026-11-07 WP-05: implementer compiled+tested (failing-first: cannot find type NASActivityProviding / NASScanFileSystem); reviewer approve (round 1; ran scanner tests 3x and concurrency test 5x under CPU load, all exit 0; non-blocking: state-inside-root check is case-sensitive, mid-scan store failure and cancel-during-hash untested); orchestrator: nas_swift.sh test ChronoframeCoreNASAssessmentScannerTests exit 0 (21 tests, 1 skipped — the case pair of testUnicodeAndCaseCollisionPathsAreDistinct only), build exit 0, check_agents_invariants_have_tests exit 0.
- 2026-11-07 WP-06: implementer compiled+tested (failing-first: cannot find type NASRemoteCopyPolicy; no member remotePolicyProvider); reviewer approve (round 1, also built ChronoframeCore -c release OK); orchestrator: nas_swift.sh test ChronoframeCoreNASRemoteCopyPolicyTests exit 0 (21), test ChronoframeCoreTransferExecutor exit 0 (39), test TransferExecutorCrashRecoveryTests exit 0 (4), build exit 0, check_agents_invariants_have_tests exit 0, git diff --check exit 0.
- 2026-11-07 WP-06 orchestrator diff review (TransferExecutor.swift, +158/−12, read in full): copyData stored default → C-08 item 2; four DEBUG seams inside existing #if DEBUG → item 1; policy resolved once before the concurrency branch + verificationRequired abort after context.start() in both branches → item 3; policy/destinationRoot parameters and context fields → item 4; remote copyFileContents branch and metadata warning text → item 5; fsync remote open flags, errno capture and ENOTSUP/EINVAL/ENOTTY fallback → item 6 (local flush routed through the fullFsync seam in DEBUG only, default fcntl F_FULLFSYNC; Release unchanged → item 1, needed by testLocalFullFsyncFailureStillThrows); remote ENOTSUP throw ahead of renameClaimingDestination → item 7; TransferJobOutcome.runFatal, prepareCopy catch, apply .runFatal case, prepared-catch check after the existing temp removal, abortRunFatally bypassing failedCount/consecutiveFailures → item 8; volume guard at top of prepareCopy, nil fsid fails closed → item 9; AppleDouble lstat counter and one info issue in finish() → item 10. One line beyond literal C-08: abortRunFatally also emits an .error RunIssue (D-NAS-114). No local-path reordering found. Verdict: every changed line traces to C-08.
- 2026-11-07 WP-07: implementer compiled+tested (failing-first: cannot find NASRemoteLeaseConfiguration / no member volumeClassifierProvider; then 2 real failures — -shm assertion and SQLITE_BUSY instead of journalModeUnavailable — fixed per D-NAS-116/117); reviewer approve (round 1); orchestrator: nas_swift.sh test ChronoframeCoreNASJournalPolicyTests 0 (7), ChronoframeCoreNASShareLeaseTests 0 (7), DestinationOperationLockTests 0 (17), OrganizerDatabaseLinkTests 0 (10), ChronoframeCoreDatabaseTests 0 (15), ChronoframeCoreDatabaseExtraTests 0 (23), build 0, check_agents_invariants_have_tests 0.
- 2026-11-07 WP-07 orchestrator diff review (OrganizerDatabase.swift +51/−1, DestinationOperationLock.swift +79/−2, read in full incl. whole init): OrganizerJournalPolicy enum, journalModeUnavailable case + C-09 message, appended init parameter → C-09 declarations; rollback branch inserted after anchor check and database assignment, before the untouched WAL block (WAL pragmas byte-identical; original init has only schema+migrations after it, both repeated) → C-09 rollbackDelete; usesRollbackJournal .automatic = live classify(parent) != .local → C-09/D-NAS-33; applyRollbackDeleteJournal busy_timeout/DELETE readback/synchronous readback, close+throw, no sidecar deletion → C-09. NASRemoteLeaseConfiguration, companion var, release order own-then-companion, fileprivate attach, two DEBUG seams → C-10 declarations; acquireShareCompanion (nil dir / local → nil; lstat st_ino or 0; NASShareLeaseKey; lockFileURL acquire) → steps 1–3; in-root acquire in do/catch releasing companion → step 4; attach → step 5. lockFileURL overload unchanged. Verdict: every changed line traces to C-09 or C-10.
