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
| WP-07 | Organize chrome, toolbar, prompts | done | build 0 | OrganizeContainerViewTests 0 (4); RunSessionStoreTests 0 (33); KeyboardInteractionTests 0 (10); RunHistoryViewTests 0 (8); WatchedSourcesViewModelTests 0 (7); SidebarViewTests 0 (4); RunCoordinatorTests 0 (12); ReceiptVerificationTests 0 (9); FreeTestBatchRunTests 0 (4); navtitle guard 0; invariants 0 | changes required → fixed (1 round) | (this commit) |  |
| WP-08 | Preview & Copy workspace | done | build 0 | RunPreviewHeadlineTests 0 (10); RunWorkspaceModelTests 0 (14); RunAnnouncementPlannerTests 0 (14); AccessibilityTests 0 (8); raw-animations guard 0; invariants 0 | changes required → fixed (1 round) | (this commit) |  |
| WP-09 | Next step after a copy | done | build 0 | RunWorkspaceModelTests 0 (18) | approved | (this commit) |  |
| WP-10 | Deduplicate lanes and vocabulary | done | build 0 | DeduplicateReviewLanesTests 0 (7); DeduplicateReviewViewsTests 0 (3); DeduplicateAccessibilityTextTests 0 (28); TipsTests 0 (4); DeduplicateSessionStoreTests 0 (unchanged); DeduplicateStatusViewTests 0 (30); invariants 0 | approved | (this commit) | no Core/AppCore diff allowed |
| WP-11 | Health | done | build 0 | ChronoframeCoreLibraryHealthScannerTests 0 (11) | approved | (this commit) |  |
| WP-11b | Glossary leftovers (added, D-CLP-117) | done | build 0 | RunSessionStoreTests 0 (34); ChronoframeCoreModelTests 0; ChronoframeCorePreviewReviewModelsTests 0; AccessibilityTests 0 (8); ChronoframeCLIKitTests 0 (46); invariants 0 | approved | (this commit) | display literals only |
| WP-12 | UI-test scenarios and string lists | done | build 0 | no acceptance tests (scenario fixtures); implementer sweep AppTests 416/0; git diff --check 0 | approved | (this commit) |  |
| WP-13 | XCUITest expectations and baseline | done | cf_swift.sh xcode 0 (after typealias fix; first run exit 65) | check_uitest_membership 0; UI lane NOT run: xcodebuild test exit 65, 'Timed out while enabling automation mode' (B-4); WP-02 classes re-run 0 after the MediaDiscovery fix | n/a | (this commit) | orchestrator |
| WP-14 | Documentation | in-progress | | | | | |
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
- 2026-11-12 WP-07: failing-first: compile error (OrganizeContainerView.tabs) and 3 RunSessionStore prompt tests failed on old wording. Reviewer confirmed RunSessionStore diff is literals only (+ .formatted()). Blocking finding (Undo label on non-copy receipts) fixed by orchestrator with the reviewer's suggested neutral 'Undo…'. XCUITest labels for WP-13: tab 'Run' :548-549, 'Run History' :553, 'Artifacts' :729/:741, 'Reusable Sources' :737, 'Actions for source' :518. D-CLP-110/111 logged.
- 2026-11-12 WP-08: failing-first: compile error (RunPreviewHeadline not in scope). Implementer sweeps: AppTests 404/0 failures, AppCoreTests 1706/0 failures. Blocking finding (NowCopyingCard strip mislabelled 'Copies Waiting') fixed by orchestrator with the reviewer's text. XCUITest labels for WP-13: 'Return to Setup' :937/:939/:1189, 'Artifacts' :729/:741; A11yBaseline.json:8 'Idle'. D-CLP-112/113 logged.
- 2026-11-12 WP-09: failing-first: compile error (no member nextStep). Implementer sweep: AppTests 408/0 failures. D-CLP-114 logged.
- 2026-11-12 WP-10: failing-first: compile error (lane identifiers/type missing); cluster-vocabulary scan seen failing on a reintroduced literal. No Core/AppCore diff (git diff --stat empty). Reviewer: lane buttons call only acceptAllSuggestions() and the sheet flag; 'safe matches' accurate. B-1/B-2 logged (store follow-ups, not blocking). D-CLP-115 logged.
- 2026-11-12 WP-11: failing-first: compile error (no member hasOrganizedHistory). Implementer sweeps: AppTests 416/0, AppCoreTests 1712/0. Reviewer confirmed dial renders only under hasOrganizedHistory and cards always render. D-CLP-116/117 logged; added card WP-11b next.
- 2026-11-12 WP-11b: failing-first: both new tests failed on old titles. Implementer sweeps: AppTests 416/0, AppCoreTests 1714/0, CLIKit 46/0, Packaging 37/0. Reviewer: literals only; changed Core titles not printed/persisted/compared. D-CLP-118 and B-3 logged.
- 2026-11-12 WP-12: Scenarios by cf-implementer; string lists by a Sonnet agent (every catalogue-bound line verified verbatim in ui/Sources; reviewer re-checked every line). Reviewer approved; 3 omitted literals added. D-CLP-119 logged.
- 2026-11-12 WP-13: Steps 1–3 exit 0; step 4 logged as B-4, H-CLP-4 stays todo-hardware. D-CLP-120 logged.
