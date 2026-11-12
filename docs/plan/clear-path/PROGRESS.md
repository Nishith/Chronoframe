# Clear path — progress

Prefix `CLP`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes. Report compiled, tested and verified separately.

## Baseline
- 2026-11-12: branch `feature/clear-path` from `feature/photos-import-resume` @ 5c72052; plan commit c3f23b4; `cf_swift.sh build` exit 0; `cf_swift.sh suite` exit 0.

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch, baseline, plan commit | done | build 0 | suite 0 | n/a | c3f23b4 | |
| WP-01 | Core titles and tab order | done | build 0 | ChronoframeCoreOrganizeNavigationTests 0 (6); DeduplicateAccessibilityTextTests 0 (28); DeduplicateStatusViewTests 0 (30) | approved | (this commit) |  |
| WP-02 | Staged sources checked against destination | done | build 0 | MultiItemSourceOverlapTests 0 (6); SwiftOrganizerEngineIntegrationTests 0; invariants script 0 | approved | (this commit) | safety-critical (INV-21); orchestrator diff read required |
| WP-03 | Folder list model, store, picker | done | build 0 | SourceItemListTests 0 (12); SetupStoreTests 0 (11); PreferencesStoreTests 0 (12) | approved | (this commit) |  |
| WP-04 | Setup coordinator, bookmarks, forwarders | done | build 0 | SetupCoordinatorTests 0 (25); BookmarkPathResolverTests 0 (8); AppStateTests 0; check_no_await_in_xctassert 0 | approved (round 2) | (this commit) |  |
| G1 | Coverage scope, suite, invariants | done | n/a | suite 0; coverage 0; invariants 0; diff --check 0 | n/a | (this commit) |  |
| WP-05 | Setup screen | done | build 0 | SetupScreenModelTests 0 (18); check_no_raw_animations 0; check_detail_views_set_navigation_title 0 | approved | (this commit) |  |
| WP-06 | Folder layout in Setup | done | build 0 | FolderLayoutPresentationTests 0 (6); SettingsUnlockSafetyTests 0 (2, file unchanged) | approved | (this commit) |  |
| WP-07 | Organize chrome, toolbar, prompts | in-progress | | | | | |
| WP-08 | Preview & Copy workspace | todo | | | | | |
| WP-09 | Next step after a copy | todo | | | | | |
| WP-10 | Deduplicate lanes and vocabulary | todo | | | | | no Core/AppCore diff allowed |
| WP-11 | Health | todo | | | | | |
| WP-12 | UI-test scenarios and string lists | todo | | | | | |
| WP-13 | XCUITest expectations and baseline | todo | | | n/a | | orchestrator |
| WP-14 | Documentation | todo | | | | | |
| G2 | Final gate | todo | | | n/a | | verified: |

## Log
(one line per step: date, WP, what ran, exit codes, failing-first evidence, reviewer verdict)
- 2026-11-12 WP-00: branch created, plan committed c3f23b4, build exit 0, suite exit 0. Owner answers: app launch for G2 smoke allowed; local XCUITest lane allowed.
- 2026-11-12 WP-01: failing-first: compile error (no member displayOrder); Done-when all exit 0; reviewer approved; existing tests updated: DeduplicateAccessibilityTextTests:215, DeduplicateStatusViewTests:466 (Near duplicates → Look-alikes).
- 2026-11-12 WP-02: failing-first: 4 tests ran, 5 failures (staged overlap let start write .organize_cache.db into the destination) — real INV-21 gap, production change made; AGENTS.md bullet extension due at G2. Orchestrator read the full diff of MediaDiscovery.swift, SourceDestinationDisjointness.swift, SwiftOrganizerEngine.swift (+31 lines, 0 deletions): every line traces to C-03. D-CLP-101 logged. Reviewer approved; all entry points (preflight/start/batch/resume) go through resolvedConfiguration.
- 2026-11-12 WP-03: failing-first: compile errors (no member sourceItems, SourceItemList missing); conformers updated: FolderAccessService, MockFolderAccessService, NASViewTestFolderAccess, MockNASFolderAccess; D-CLP-102/103 logged; reviewer approved.
- 2026-11-12 WP-04: failing-first: compile errors, then 3 round-1 tests and 1 follow-up test each failed before its fix. Review round 1: changes required (profile-at-launch restage; loose-file drop refused) → fixed; round 2 approved; follow-up stale-rows fix read by orchestrator. D-CLP-104/105/106 logged. TestSupport seam: watchedSourcesStore parameter on makeAppState.
- 2026-11-12 G1: SourceItemList added to MEANINGFUL_BASENAMES; cf_swift.sh suite exit 0; cf_swift.sh coverage exit 0; check_agents_invariants_have_tests exit 0; git diff --check exit 0.
- 2026-11-12 WP-05: failing-first: compile errors (SetupSourceItemRow missing). Existing tests updated: testPrimaryActionAndReadinessTrackManualSetupState, testProfileContextProducesPreviewReadySummary. XCUITest expects 'Setup' hero/nav title at ChronoframeUITests.swift:550,565,587,602 → WP-13. D-CLP-107/108 logged.
- 2026-11-12 WP-06: failing-first: compile error (FolderLayoutPresentation not in scope). D-CLP-109 logged. Reviewer: binding the same preference from Setup bypasses nothing in Settings.
