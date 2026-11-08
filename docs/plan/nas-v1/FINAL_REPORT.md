# NAS v1 final report

Date: 2026-11-07. Branch: `feature/nas-v1` (from `codex/stable-invariant-ids` e257003). Not pushed; no pull request opened.

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
| (this commit) | NAS G3: final verification report |

## Gate commands

### G2 (at d6fbd13)

| Command | Exit | Result |
|---|---|---|
| `script/check_agents_invariants_have_tests.sh` | 0 | 28 of 28 invariants tagged |
| full sharded suite (`script/run_swift_test_suites.sh`, local HOME/module cache) | 0 | 119 s, 33 shards |
| `script/swift_meaningful_coverage.sh` | 0 | meaningful 95.88%, raw 73.23% |
| `git diff --check` | 0 | |

### G3 (at ebdefd2, plus docs)

| Command | Exit | Result |
|---|---|---|
| full sharded suite, first run | **1** | `BuildPipelineTests.testSwiftAppSourcesAreListedInXcodeProject`: the WP-09 probe tool wasn't on the SwiftPM-tool exemption list. Fixed in ebdefd2 (D-NAS-136). |
| full sharded suite, rerun | 0 | 129 s, 35 shards, 175 suites |
| `script/swift_meaningful_coverage.sh` | 0 | meaningful 95.90% (19484/20318), raw 73.31% |
| `check_agents_invariants_have_tests` | 0 | 28 of 28 |
| `check_app_intents_never_purchase` | 0 | |
| `check_app_layer_changes_have_tests codex/stable-invariant-ids` | 0 | |
| `check_authorizer_has_no_default` | 0 | |
| `check_detail_views_set_navigation_title` | 0 | |
| `check_guardian_restore_verified` | 0 | |
| `check_mas_build_lane_exists` | 0 | |
| `check_no_await_in_xctassert` | 0 | |
| `check_no_raw_animations` | 0 | |
| `check_photos_import_readonly` | 0 | |
| `check_recovery_goes_through_helper` | 0 | |
| `check_storekit_config_matches_policy` | 0 | |
| `check_test_dirs_are_targets` | 0 | |
| `check_uitest_membership` | 0 | |
| `git diff --check` | 0 | |
| `xcodebuild … -configuration Debug … CODE_SIGNING_ALLOWED=NO build` | 0 | BUILD SUCCEEDED |
| `(cd ui && ./build.sh)` | 0 | Debug app at `ui/build/Chronoframe.app` |
| `open --env CHRONOFRAME_ENABLE_NAS=1 …` + `screencapture` | refused | Permission classifier ("Interfere With Workloads"), logged as B-1 |

Per-WP Done-when commands and exit codes are in `PROGRESS.md` → Log.

Coverage for the new NAS Core files is 100% for NASLibraryIdentity, NASMeteredFileReader, NASRemoteCopyPolicy and NASSystemContainerRules. The other three are lower: NASVolumeClassifier 94.6%, NASAssessmentStore 94.2%, NASAssessmentScanner 94.5%.

## Status per slice

| Slice | WPs | Compiled | Tested | Verified (running app) | Hardware |
|---|---|---|---|---|---|
| 0 Probe / qualification tooling | WP-09 | yes (`nas_swift.sh build` 0) | yes: 11 probe tests; local APFS smoke exit 0 with P01–P07 pass and the dir left empty | n/a (CLI tool) | H1, H2 todo |
| 1a Read-only assessment engine | WP-01–05 | yes | yes: 12+2, 18, 13, 12, 21 tests. One scanner case-pair check was skipped because the temp volume is case-insensitive. | no | H3, H4, H8 todo |
| 1b Review workspace | WP-10, WP-11 | yes; Xcode lane 0 | yes: 37 AppCore + 23 App tests; existing Dedupe, Setup, Sidebar, AppState and Accessibility suites pass | **no** (B-1) | H3, H5, H7 todo |
| 1c Copy qualification (unflagged) | WP-06–08 | yes; release build of ChronoframeCore checked by the reviewer | yes: 21 + 7 + 7 + 10 new tests; existing executor, lock and DB suites pass | no | H1, H5, H6 todo |

The NAS Library workspace is off in release builds (`NASCapability.isEnabled` is false). The remote copy policy, the journal policy and the CLI refusal ship unflagged (D-NAS-07). They are now enforced for every network or unclassifiable destination.

## Review loop summary

- WP-08 had one blocking finding, fixed in round 2 (D-NAS-118). `--profile NAS --dest /local` passed the CLI refusal, but the engine then wrote to the profile's NAS destination.
- WP-12 had three false claims in the docs, fixed in round 2 (D-NAS-134, 135).
- WP-09, WP-10 and WP-11 were approved with non-blocking findings, and I sent the cheap ones back to the same implementer:
  - WP-09: P06 now reads back the live connection's mode.
  - WP-10: a stale review can no longer be edited after a mismatch, and an ambiguous re-pick now asks for confirmation.
  - WP-11: tests no longer write to the real home, preview paths are confined to the library, and accessibility labels start with the visible title.
- I reviewed the safety-critical diffs line by line for WP-06 (TransferExecutor) and WP-07 (OrganizerDatabase, DestinationOperationLock). Every changed line traces to C-08, C-09 or C-10, and the review is recorded in `PROGRESS.md`.

## Open BLOCKED.md items

- **B-1. G3 app smoke: launch and screen capture not permitted.** Recommendation: run it by hand (2 minutes).
  ```bash
  pkill -x Chronoframe || true
  open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app
  # click NAS Library in the sidebar
  screencapture -x docs/plan/nas-v1/evidence/nas-empty.png
  # click Choose Folder…, pick any local folder, confirm "Choose a folder on a network share…"
  screencapture -x docs/plan/nas-v1/evidence/nas-refusal.png
  ```

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

## Hardware checklist (owner only; from EVIDENCE_LEDGER.md)

Build first: `docs/plan/nas-v1/bin/nas_swift.sh build`. Run against empty, disposable folders on the share only.

```bash
ui/.build/debug/ChronoframeNASProbeTool probe --test-dir "/Volumes/<share>/<empty-test-folder>" > probe.json
ui/.build/debug/ChronoframeNASProbeTool make-corpus --dest "/Volumes/<share>/<empty-corpus-folder>" --manifest "$HOME/nas-corpus-manifest.json" --files 10000 --duplicate-percent 20 --seed 42
ui/.build/debug/ChronoframeNASProbeTool assess-parity --root "/Volumes/<share>/<corpus-folder>" --state-dir "$HOME/nas-parity-state" > parity.json
```

| ID | What to run | Pass when |
|---|---|---|
| H1 | `probe` on the Synology SMB share; keep `probe.json` and note whether RENAME_EXCL is supported | P03, P04, P05 pass; P04 leaves the existing file's digest unchanged |
| H2 | `make-corpus` (10,000 files, 20%, seed 42), then `assess-parity` three matched cold runs; record the manifest SHA-256 | `parity: true` and the ledger within the NAS-NFR-09 budget in all three runs |
| H3 | Signed sandboxed build: choose share, assess, quit, relaunch, check review restored, remount under another path | Review restored; remount recognized as the same library |
| H4 | Assess a share the account can't write to; compare server-side change history before and after | No server-side changes |
| H5 | Disconnect the share, sleep and wake, during a scan and during a copy | Scan ends "Waiting for your NAS" without data loss; copy stops cleanly and resumes |
| H6 | Verified copy batch of at least 100 files / 10 GiB each way, plus a forced quota-full fault | Every copy verified, no overwrite, quota fault stops cleanly with originals untouched |
| H7 | VoiceOver, keyboard, increased text and reduced motion over the NAS workspace | Every control reachable and labeled |
| H8 | Latency, memory and cancel on the reference corpus (`wallSeconds`, `ruMaxrss` from `parity.json`) | Within NAS-NFR-01 to NFR-04 targets |

Record results in `EVIDENCE_LEDGER.md`. Only the owner sets `pass-hardware`.
