# Conflicting capture dates progress

## Status

- Branch: `feature/conflicting-dates` (unpushed).
- `git pull --ff-only`: `Already up to date.`
- Existing local changes were present before this task: modified `.gitignore`; untracked `marketing/macapps-launch-post-2026-11.md`, `marketing/macapps-top-posts-2026-11-03.csv`, and `marketing/product-video/`. Leave all untouched and out of commits.
- Baseline test command: `/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache swift test --package-path ui --filter 'ChronoframeCore(MediaDate|PreviewReviewModels)Tests'"`
- Baseline result: passed, 27 tests (23 `ChronoframeCoreMediaDateTests`, 4 `ChronoframeCorePreviewReviewModelsTests`), 0 failures.
- Final baseline-filter command (same command as above): passed, 34 tests (29 date tests, 5 review model tests), 0 failures.
- Focused feature test command: `/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache swift test --package-path ui --filter 'ChronoframeCore(MediaDate|PreviewReviewModels|DryRunPlannerParity)Tests|PreviewReviewUndoTests'"`
- Focused feature result: passed, 52 tests, 0 failures. Includes planner compatibility fixtures, photo/video conflict resolution and one-read assertions, legacy review-row decoding, and applying the alternative as a user override.
- Authoritative shard lane: one final run failed in the unrelated `ChronoframeCoreMediaDiscoveryTests.testWalkEntriesSkipsSymbolicLinksAndPackages` test (the `.photoslibrary` package was traversed). The same isolated shard failure reproduced; the failing source and discovery implementation are unchanged by this feature. The earlier complete shard-lane run passed before the final test-only I/O-counter assertions were added.
- The focused Xcode UI test target compiled, but the runner did not launch while the Mac session was locked. No screenshot has been captured yet. The runner log reports CoreSimulator unavailable; `cua.getState()` independently reports that the Mac is locked. The screenshot is saved by the UI test to `/private/tmp/Chronoframe-conflicting-date-review.png` once that test can run.
- Xcode UI command: `xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug -derivedDataPath .tmp/ChronoframeDerivedData -destination 'platform=macOS,arch=arm64' -only-testing:ChronoframeUITests/ChronoframeUITests/testPreviewDateConflictRowShowsAlternativeAndSavesScreenshot CODE_SIGNING_ALLOWED=NO test`. App and UI-test targets compiled; launch hung before UI test execution because this Mac session is locked, then the run was interrupted (exit 75).
- CI guards: `git diff --check`, `script/check_no_raw_animations.sh`, `script/check_photos_import_readonly.sh`, `script/check_agents_invariants_have_tests.sh`, and `script/check_uitest_membership.sh` all passed.
- App-layer test guard: `script/check_app_layer_changes_have_tests.sh origin/main` passed after commits.
- Feature commits on this branch: `eef795b`, `76e6b60`, `614d763` (all unpushed).

## Decisions logged

See `DECISIONS.md`: offset-normalized calendar-day comparison with a one-day tolerance; only documented exact camera default 2000-01-01 00:00:00; future means more than one day after scan time; ignore filesystem timestamps; warnings do not change the chosen date or plan.

## Next

1. Resolver, planner, persistence, alternative acceptance, review UI/filter, and fixture changes are implemented and committed.
2. The Mac screenshot remains pending because the interactive session is locked; unlock the Mac and rerun the focused UI test above to capture it.
3. Preserve the pre-existing `.gitignore` and marketing changes in the worktree; they remain uncommitted and outside this branch's feature commits.
