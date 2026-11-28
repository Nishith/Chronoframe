# Edit preservation — progress

Prefix `EPR`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes.

## Baseline
- 2026-11-27 branch `feature/edit-preservation-impl` from `origin/main` @ f1c5540 (#298), plan fix 10ede42, owner answers 8d13bd5 (D-EPR-01).
- `docs/plan/next-half/bin/cf_swift.sh build` → exit 0 (.tmp/epr-baseline-build.log)
- `docs/plan/next-half/bin/cf_swift.sh suite` → exit 0, 2425 test cases passed, 0 failures (.tmp/epr-baseline-suite.log)
- `script/check_agents_invariants_have_tests.sh` → exit 0, "All 29 safety invariants have at least one tagged test"

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch and baseline | done | build 0 | suite 0, inv 0 | n/a | 10ede42, 8d13bd5 | B-1 resolved |
| WP-01 | Copy and docs for what import preserves | done | build 0 | PhotosImportEditsCopyTests 2/2 (exit 0), l10n 0 | approved | (this commit) | failing-first: "cannot find PhotosImportEditsCaption"; xcode loc build 0; check_german_localization 0; diff --check 0; app-layer guard 0 |
| WP-02 | `.aae` is a dedupe sidecar (INV-14) | done | build 0 | DeduplicatePairDetectorTests 11/11, DeduplicateTests 74/74 (exit 0); inv 0 | approved (round 1 after orchestrator fix) | (this commit) | safety-critical; orchestrator diff review: pass after one fix (aae lookup was O(n·m) per scan; now per-directory dictionary); failing-first: 4 detector + 2 planner tests failed with nil sidecars; diff --check 0 |
| WP-03 | Spike: companion plug-in points | done | n/a | n/a | n/a | (this commit) | answers D-EPR-103…111; no schema change (D-EPR-105); B-2 logged non-blocking |
| WP-04 | Organize copies companions | done | build 0 | suite 0 (2461 passed); Companion* 7+9+5+4+2 pass; inv 0; l10n 0 | approved (4a: 2 rounds; 4b: 1 round + nits) | 9328af2 + (this commit) | safety-critical; orchestrator diff review: pass (4a discovery/resolver/planner/reduced traced to C-03, D-EPR-103…112; 4b engine changes limited to post-planning issues, metrics and read-only receipt count); app-layer guard 0; diff --check 0 |
| G1 | Gate after companions | done | xcode 0 | suite 0 (2461 passed, run on the WP-04 tree), coverage 0 (meaningful 96.09%), inv 0, app-layer guard (origin/main) 0 | n/a | (this commit) | logs .tmp/epr-wp04-suite.log, .tmp/epr-g1-coverage.log, .tmp/epr-g1-xcode.log |
| WP-05 | Export model, role, checkpoint fields | done | build 0 | PhotosImportCheckpointTests 14/14, PhotosExportExecutorTests 32/32, PhotosImportResumeTests 28/28 (exit 0) | approved | (this commit) | failing-first: compile errors (no member role/editedStillResource/includeEditedVersions…); checkpoint v2, loader accepts 1–2 (D-EPR-13); one existing test now interpolates the version (not weakened, reviewer confirmed); diff --check 0 |
| WP-06 | Executor and service export edited still | in-progress | | | | | safety-critical; INV-22 wording |
| WP-07 | Import UI, summary, history copy | todo | | | | | |
| WP-08 | Dedupe protects edited variants (INV-31) | todo | | | | | safety-critical |
| G2 | Final gate | todo | | | n/a | | |

## Log
- 2026-11-15 plan written; owner approved INV-22 widening and INV-31. D-EPR-06 (stem link) defaulted pending owner answer.
- 2026-11-27 merged `origin/main` @ 4cabd27 (#297) into the branch; baseline above is from 5eee91f, so re-run the WP-00 commands at kickoff. Invariant renumbered INV-30 → INV-31 (D-EPR-12).
- 2026-11-27 owner approved D-EPR-06: link edited variants by file name (`<stem>-edited.<ext>`). No open owner questions remain.
- 2026-11-27 kickoff: owner answers recorded as D-EPR-01, 05, 07–11 approved and D-EPR-13…17; D-EPR-18 notes stale citations. Baseline re-run on the impl branch, all exit 0.
- 2026-11-27 WP-01: caption helper `PhotosImportEditsCaption.text(includeEditedVersions:)`; view passes `false` until WP-07 (D-EPR-101). Both C-01 caption keys added to Localizable.xcstrings with German.
- 2026-11-27 WP-02: `.aae` detected (both forms + IMG_E exact digits), on-disk spelling (D-EPR-102); AGENTS.md INV-14 sentence names `.aae`. Reviewer nit kept for follow-up: `.XMP` spelling issue is pre-existing.
- 2026-11-27 WP-03 spike: CopyPlanBuilder.build is unused in production, hook moves to DryRunPlanner (D-EPR-104); WP-04 owned paths widened to DryRunPlanner.swift and LibraryHealthScanner.swift (one filter). WP-04 runs in two parts: 4a Core planning, 4b preview/summary copy and docs.
- 2026-11-27 WP-04 part 1 (4a, Core): companions discovered, resolved and planned in DryRunPlanner; trial reduction keeps owners and companions together; health duplicate stats ignore sidecars. Orchestrator diff review: pass after one round (reviewer + orchestrator found reduced(to:) counting companions in counts/histogram; fixed). Failing-first shown by stubbing discovery/resolve (implementer wrote code first; stub proof recorded). Commands: build 0; CompanionResolverTests 7/7, CompanionPlanningTests 9/9, CompanionTransferTests 5/5, FreeTestBatch 43/43, DryRunPlanner 24/24, ChronoframeCoreMediaDiscoveryTests 10/10, ChronoframeCoreLibraryHealthScannerTests 15/15 (all exit 0); inv 0; diff --check 0. B-2 item 4 (owner fails, companion copies) added.
- 2026-11-27 WP-04 part 2: unresolved companions shown as preview warnings (D-EPR-114), photo/sidecar split in headline and hero (D-EPR-113, D-EPR-115), TECHNICAL and SAFETY_AND_RECOVERY updated with residual gaps. 6 App + 4 Core keys added with German; xcode loc build 0; check_german_localization 0.
