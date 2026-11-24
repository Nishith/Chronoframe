# NAS v1 progress

Status: shipped in PR #266 behind the disabled `NASCapability.isEnabled` flag; WP-00 to WP-12 and gates G2 and G3 done. Owner verified the NAS Library workspace renders and the local-folder refusal shows in a Debug build (54bee13); hardware rows H1 to H8 are `todo-hardware` in this folder (results live in `docs/plan/nas-public/EVIDENCE_LEDGER.md`).

## Baseline (2026-11-07, `feature/nas-v1` @ e257003)
- `nas_swift.sh build` (wrapper removed 2026-11-23; see git history): exit 0, 15 s ("Build complete! (13.63 sec)").
- `script/check_agents_invariants_have_tests.sh`: exit 0, <1 s, "All 26 safety invariants have at least one tagged test."
- Full sharded suite (`script/run_swift_test_suites.sh` with local HOME/module cache): exit 0, 86 s, 154 suites in 31 shards, no line reporting a non-zero failure count.

## Work packages

| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch, shared models, baseline | done | exit 0 | baseline suite exit 0 | n/a | 2e4ef40 | build 0, invariants 0, suite 0 |
| WP-01 | Volume classifier, system containers | done | exit 0 | 12+2 pass | approve | 5dbde1d | classifier test 0, rules test 0, build 0 |
| WP-02 | Library identity, lease key | done | exit 0 | 18 pass | approve | dbea45f | identity test 0, build 0 |
| WP-03 | Metered file reader | done | exit 0 | 13 pass | approve | 7f060d3 | reader test 0, build 0; FileIdentityHasher.swift diff empty |
| WP-04 | Assessment store | done | exit 0 | 12 pass | approve | 7925df7 | store test 0, build 0; follow-up: non-ELOOP anchor errors surface as POSIX NSError (WP-10 must map) |
| WP-05 | Assessment scanner | done | exit 0 | 21 pass, 1 partial skip | approve | 6902de8 | scanner test 0 (case pair skipped: case-insensitive temp volume), build 0, invariants 0 |
| WP-06 | Remote copy policy (safety-critical) | done | exit 0 | 21 new + 39 + 4 pass | approve | 92db1fe | policy 0, TransferExecutor 0, crash recovery 0, build 0, invariants 0; orchestrator diff review recorded in Log |
| WP-07 | Journal policy, share lease (safety-critical) | done | exit 0 | 7+7 new, 17+10+15+23 existing pass | approve | 5318d4d | 6 test classes 0, build 0, invariants 0; orchestrator diff review recorded in Log |
| WP-08 | CLI remote refusal | done | exit 0 | 10 new, CLIKit 46 pass | approve (round 2) | 4bed44d | refusal test 0, CLIKit 0, build 0, invariants 0 |
| G2 | Invariants 27–28, coverage, full suite | done | n/a | suite 0, coverage 95.88% | n/a | d6fbd13 | invariants 0 (28/28), full suite 0, coverage 0, diff --check 0 |
| WP-09 | Probe, parity, corpus tool | done | exit 0 | 11 pass | approve | 2a95e06, ebdefd2 (WP-09b) | probe tests 0, build 0, probe smoke 0 (P01–P07 pass, dir empty), invariants 0 |
| WP-10 | App Core services, workspace store | done | exit 0 | 3+2+3+3+25+1 new; Dedupe 29, Setup 9 pass | approve (+2 follow-ups) | c9a3e55 | 8 test classes 0, build 0, invariants 0, no-await 0 |
| WP-11 | NAS Library UI | done | exit 0 | 11+4+5+3 new; Sidebar 4, AppState 29, Accessibility 8 pass | approve (+4 follow-ups) | ca0ce3a | 7 test classes 0, build 0, nav-title 0, raw-animations 0, uitest-membership 0, invariants 0; app-layer guard run after commit |
| WP-12 | Documentation | done | n/a | docs only | approve (round 2) | 35f2c87 | git diff --check 0; every claim checked against source by reviewer |
| G3 | Final gate and report | done (smoke blocked, B-1) | Xcode 0, build.sh 0 | suite 0, coverage 95.90%, 14 guards 0 | n/a | (this commit) | verified: not claimed — launch/screencapture refused (B-1); completed-assessment capture todo-hardware (no share mounted) |

Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Outcome
- Baseline 2026-11-07 on `feature/nas-v1` @ e257003: build 0, invariants 0 (26/26), full suite 0 (86 s, 154 suites).
- G2 (d6fbd13): INV-27 and INV-28 appended to `AGENTS.md`; invariants 0 (28/28); suite 0 (119 s); coverage meaningful 95.88%.
- G3: first full suite run failed (exit 1) because `BuildPipelineTests.testSwiftAppSourcesAreListedInXcodeProject` did not exempt the new probe tool; fixed in ebdefd2 (D-NAS-136). Rerun: suite 0 (129 s, 35 shards), coverage 95.90%, 14 guards 0, `xcodebuild` Debug 0, `ui/build.sh` 0. A later tests-only coverage pass reached meaningful 96.09% (16 new tests).
- Post-G3 fix 54bee13 (D-NAS-137): a `fixedSize` banner gave the NAS workspace a 1,692 pt minimum height, so the window rendered blank; fixed with two regression tests.
- WP-06 and WP-07 were safety-critical; the orchestrator read the full `TransferExecutor.swift`, `OrganizerDatabase.swift` and `DestinationOperationLock.swift` diffs and confirmed each changed line traces to C-08, C-09 or C-10. WP-08 had one blocking finding fixed in round 2 (D-NAS-118: `--profile NAS --dest /local` bypassed the CLI refusal).
- Commits: see `FINAL_REPORT.md`.

Per-step log condensed 2026-11-21 (failing-first output, reviewer rounds, Done-when commands are in git history before the docs cleanup).
