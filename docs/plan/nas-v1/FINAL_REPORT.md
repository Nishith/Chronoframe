# NAS v1 final report

Status: shipped in PR #266 behind the disabled `NASCapability.isEnabled` flag. Items 1 to 5 under "Owner decisions, ranked" were closed by `nas-public` WP-01 to WP-04. This report is kept as the record of the v1 build.

Date: 2026-11-07. Branch: `feature/nas-v1` (from `codex/stable-invariant-ids` e257003). Written before the merge (the branch was later merged as PR #266).

## Bottom line

All 13 work packages and gate G2 are committed. G3's automated checks all exit 0: full suite, coverage, 14 CI guards, Xcode lane and the app build. Nothing is **verified** in the running app. The smoke launch and screen capture were refused by the session's permission classifier (B-1). Every hardware row (H1–H8) is `todo-hardware`.

## Commits

| Hash | Title |
|---|---|
| 2e4ef40 | NAS WP-00: plan, shared models and baseline |
| 5dbde1d | NAS WP-01: Volume classifier and system-container rules |
| dbea45f | NAS WP-02: Library identity and share lease key |
| 7f060d3 | NAS WP-03: Metered file reader |
| 7925df7 | NAS WP-04: Assessment store |
| 6902de8 | NAS WP-05: Assessment scanner |
| 92db1fe | NAS WP-06: Remote copy policy in TransferExecutor |
| 5318d4d | NAS WP-07: Remote journal policy and share lease |
| 4bed44d | NAS WP-08: CLI refuses remote destinations |
| d6fbd13 | NAS G2: invariants 27-28 and coverage scope |
| 2a95e06 | NAS WP-09: Probe, parity and corpus tool |
| c9a3e55 | NAS WP-10: App Core services and workspace store |
| ca0ce3a | NAS WP-11: NAS Library workspace UI |
| 35f2c87 | NAS WP-12: Documentation |
| ebdefd2 | NAS WP-09b: Exempt the probe tool from the Xcode source-list test |
| 3100748 | NAS G3: final verification report |
| 54bee13 | NAS WP-11b: Keep the NAS workspace's minimum height inside the window |

## Gate results

G2 (d6fbd13): invariants 28/28, full sharded suite 0 (119 s, 33 shards), coverage meaningful 95.88%, `git diff --check` 0.

G3 (ebdefd2 plus docs): the first suite run exited 1 (`BuildPipelineTests.testSwiftAppSourcesAreListedInXcodeProject`; the probe tool was not on the SwiftPM-tool exemption list; fixed in ebdefd2, D-NAS-136). Rerun: suite 0 (129 s, 35 shards, 175 suites), coverage meaningful 95.90% (19484/20318), all 14 CI guards 0, `git diff --check` 0, `xcodebuild` Debug `CODE_SIGNING_ALLOWED=NO` 0 (BUILD SUCCEEDED), `(cd ui && ./build.sh)` 0. The launch and `screencapture` smoke was refused by the permission classifier (B-1, since resolved by the owner). Per-WP Done-when results are in git history of `PROGRESS.md`.

Coverage for the new NAS Core files: 100% for NASLibraryIdentity, NASMeteredFileReader, NASRemoteCopyPolicy and NASSystemContainerRules; NASVolumeClassifier 94.6%, NASAssessmentStore 94.2%, NASAssessmentScanner 94.5%.

## Status per slice

| Slice | WPs | Compiled | Tested | Verified (running app) | Hardware |
|---|---|---|---|---|---|
| 0 Probe / qualification tooling | WP-09 | yes (`nas_swift.sh build` 0) | yes: 11 probe tests; local APFS smoke exit 0 with P01–P07 pass and the dir left empty | n/a (CLI tool) | H1, H2 todo |
| 1a Read-only assessment engine | WP-01–05 | yes | yes: 12+2, 18, 13, 12, 21 tests. One scanner case-pair check was skipped because the temp volume is case-insensitive. | no | H3, H4, H8 todo |
| 1b Review workspace | WP-10, WP-11 | yes; Xcode lane 0 | yes: 37 AppCore + 25 App tests; existing Dedupe, Setup, Sidebar, AppState and Accessibility suites pass | **partly**: empty state and local-folder refusal verified by owner (54bee13); a completed assessment needs a share (H3) | H3, H5, H7 todo |
| 1c Copy qualification (unflagged) | WP-06–08 | yes; release build of ChronoframeCore checked by the reviewer | yes: 21 + 7 + 7 + 10 new tests; existing executor, lock and DB suites pass | no | H1, H5, H6 todo |

The NAS Library workspace is off in release builds (`NASCapability.isEnabled` is false). The remote copy policy, the journal policy and the CLI refusal ship unflagged (D-NAS-07). They are now enforced for every network or unclassifiable destination.

## Post-G3

Owner reported the NAS Library window blank. Cause: a `fixedSize` banner gave the workspace a 1,692 pt minimum height, pushing all content outside the window. Fixed in 54bee13 with two regression tests (D-NAS-137). Owner then verified the workspace renders in the running app.

## Open BLOCKED.md items

None. B-1 (G3 app smoke) was resolved by the owner; see `BLOCKED.md`.

## Owner decisions, ranked

1. **Deduplicate can still Trash files on a mounted network share** (D-NAS-135). This behavior predates NAS v1 and is outside its scope. The Deduplicate workspace only shows a network warning (`DeduplicateEngine.swift:101`), then moves files to the Trash (`DeduplicateExecutor.swift:582`). The requirements say recoverable Trash on SMB is unverified. Recommendation: a follow-up WP that refuses network folders in Deduplicate, using the same classifier and refusal copy the NAS workspace uses. The docs now state the gap plainly.
2. **`TransferExecutor.execute(queuedJobs:)` ignores the remote policy** (D-NAS-115). It is public but only tests call it; production uses `executeQueuedJobs`. Recommendation: make it `internal`, or resolve the policy in it. Either is a small change to a safety-critical file, so I didn't fold it in.
3. **A dead share can stall the workspace in "checking connection"** (D-NAS-124). `validate()` resolves the bookmark on the main actor, and `observe` has no timeout. Check during H5. If it reproduces, route the saved-library check through `NASReconnectProbe`.
4. **Contract errata to fold into CONTRACTS.md** (code already follows the decisions):
   - D-NAS-118: the CLI also classifies a named profile's destination.
   - D-NAS-120: P07 uses BEGIN EXCLUSIVE.
   - D-NAS-124: the probe is placed in `chooseLibrary`.
   - D-NAS-134: a lease-folder failure fails closed, with no fallback.
5. **Small follow-ups:**
   - A `chooseKeeper` save failure replaces the results with an error state (D-NAS-129).
   - The doc comment in `DestinationOperationLock.swift` (~line 100) still says remote detection "does not change locking behavior".
   - The new UI strings are not in `.xcstrings` yet (D-NAS-51, D-NAS-130).
6. **Local artifact:** earlier WP-11 test runs created an empty `~/Library/Application Support/Chronoframe/nas/leases`. The app creates the same directory on first launch, so I left it. Tests no longer do this (D-NAS-133).

## Hardware checklist

Owner only; procedures and exact commands for H1 to H8 are in `EVIDENCE_LEDGER.md`. Results are recorded in `docs/plan/nas-public/EVIDENCE_LEDGER.md`.
