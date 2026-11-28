# Clear path — progress

Status: shipped in PR #269 (including WP-15 and WP-16) with follow-up PR #274. Not verified in the running app (B-5 open); hardware rows H-CLP-1 to H-CLP-7 are `todo-hardware`.

Prefix `CLP`. Status values: todo, in-progress, review, done, blocked. "done" requires the Done-when commands with exit 0 recorded in Notes. Report compiled, tested and verified separately.

## Baseline
- 2026-11-12: branch `feature/clear-path` from `feature/photos-import-resume` @ 5c72052; plan commit c3f23b4; `cf_swift.sh build` exit 0; `cf_swift.sh suite` exit 0.

## Work packages
| WP | Title | Status | Compiled | Tested | Reviewer | Commit | Notes |
|---|---|---|---|---|---|---|---|
| WP-00 | Branch, baseline, plan commit | done | build 0 | suite 0 | n/a | c3f23b4 | |
| WP-01 | Core titles and tab order | done | build 0 | ChronoframeCoreOrganizeNavigationTests 0 (6); DeduplicateAccessibilityTextTests 0 (28); DeduplicateStatusViewTests 0 (30) | approved | e960598 |  |
| WP-02 | Staged sources checked against destination | done | build 0 | MultiItemSourceOverlapTests 0 (6); SwiftOrganizerEngineIntegrationTests 0; invariants script 0 | approved | e4b4ca7 | safety-critical (INV-21); orchestrator diff read required |
| WP-03 | Folder list model, store, picker | done | build 0 | SourceItemListTests 0 (12); SetupStoreTests 0 (11); PreferencesStoreTests 0 (12) | approved | 2a51360 |  |
| WP-04 | Setup coordinator, bookmarks, forwarders | done | build 0 | SetupCoordinatorTests 0 (25); BookmarkPathResolverTests 0 (8); AppStateTests 0; check_no_await_in_xctassert 0 | approved (round 2) | 49e6c5a |  |
| G1 | Coverage scope, suite, invariants | done | n/a | suite 0; coverage 0; invariants 0; diff --check 0 | n/a | b1fc096 |  |
| WP-05 | Setup screen | done | build 0 | SetupScreenModelTests 0 (18); check_no_raw_animations 0; check_detail_views_set_navigation_title 0 | approved | a612863 |  |
| WP-06 | Folder layout in Setup | done | build 0 | FolderLayoutPresentationTests 0 (6); SettingsUnlockSafetyTests 0 (2, file unchanged) | approved | 5a7e92e |  |
| WP-07 | Organize chrome, toolbar, prompts | done | build 0 | OrganizeContainerViewTests 0 (4); RunSessionStoreTests 0 (33); KeyboardInteractionTests 0 (10); RunHistoryViewTests 0 (8); WatchedSourcesViewModelTests 0 (7); SidebarViewTests 0 (4); RunCoordinatorTests 0 (12); ReceiptVerificationTests 0 (9); FreeTestBatchRunTests 0 (4); navtitle guard 0; invariants 0 | changes required → fixed (1 round) | 9e7bf13 |  |
| WP-08 | Preview & Copy workspace | done | build 0 | RunPreviewHeadlineTests 0 (10); RunWorkspaceModelTests 0 (14); RunAnnouncementPlannerTests 0 (14); AccessibilityTests 0 (8); raw-animations guard 0; invariants 0 | changes required → fixed (1 round) | 4ba4438 |  |
| WP-09 | Next step after a copy | done | build 0 | RunWorkspaceModelTests 0 (18) | approved | 6b62c83 |  |
| WP-10 | Deduplicate lanes and vocabulary | done | build 0 | DeduplicateReviewLanesTests 0 (7); DeduplicateReviewViewsTests 0 (3); DeduplicateAccessibilityTextTests 0 (28); TipsTests 0 (4); DeduplicateSessionStoreTests 0 (unchanged); DeduplicateStatusViewTests 0 (30); invariants 0 | approved | f2cebb4 | no Core/AppCore diff allowed |
| WP-11 | Health | done | build 0 | ChronoframeCoreLibraryHealthScannerTests 0 (11) | approved | c9f4b5b |  |
| WP-11b | Glossary leftovers (added, D-CLP-117) | done | build 0 | RunSessionStoreTests 0 (34); ChronoframeCoreModelTests 0; ChronoframeCorePreviewReviewModelsTests 0; AccessibilityTests 0 (8); ChronoframeCLIKitTests 0 (46); invariants 0 | approved | 23e37e8 | display literals only |
| WP-12 | UI-test scenarios and string lists | done | build 0 | no acceptance tests (scenario fixtures); implementer sweep AppTests 416/0; git diff --check 0 | approved | de0936c |  |
| WP-13 | XCUITest expectations and baseline | done | cf_swift.sh xcode 0 (after typealias fix; first run exit 65) | check_uitest_membership 0; UI lane NOT run: xcodebuild test exit 65, 'Timed out while enabling automation mode' (B-4); WP-02 classes re-run 0 after the MediaDiscovery fix | n/a | c87c97b | orchestrator |
| WP-14 | Documentation | done | n/a (docs) | git diff --check 0 | approved | daed52e |  |
| G2 | Final gate | done | build 0; cf_swift.sh xcode 0; ui/build.sh 0 | suite 0; coverage 0; guards feature/photos-import-resume 0 (14 guards); git diff --check 0 | n/a | a68d3ca | verified: |

## Outcome
- Baseline 2026-11-12: branch from `feature/photos-import-resume` @ 5c72052, plan commit c3f23b4, build 0, suite 0. `feature/photos-import-resume` (with DDP WP-05) was merged in at 2c307af.
- WP-02 found a real INV-21 gap (a staged overlap let a run write `.organize_cache.db` into the destination); production change made and `AGENTS.md` INV-21 extended at G2.
- G2 (after the first run's string-symbol collisions were fixed, D-CLP-122): `suite` 0, `coverage` 0, `guards` 0 (14/14), `xcode` 0, `ui/build.sh` 0. After WP-15 and WP-16: `suite` 0, `coverage` 0 (meaningful 96.04%, 20041/20868), `guards` 0, `xcode` 0.
- WP-15 (D-CLP-123) made "Accept All Safe" skip groups already reviewed; WP-16 (D-CLP-124) replaced leftover engine words on screen. Remaining engine words are listed under B-3 in `BLOCKED.md`.
- Banned-word sweep at G2: 11 hits, all the Swift parameter name `cluster`, no visible text.
- UI-test lane: ran 28/28 plus the strict accessibility audit on 2026-11-13 (D-CLP-125, D-CLP-133).

Per-step log condensed 2026-11-21 (failing-first output, reviewer rounds, Done-when commands are in git history before the docs cleanup).
