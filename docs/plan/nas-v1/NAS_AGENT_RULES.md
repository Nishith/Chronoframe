# NAS v1 agent rules

Shared by the orchestrator and every subagent working on the NAS v1 plan. The root `AGENTS.md` (safety invariants) and `CLAUDE.md` (commands, change discipline) still apply and win on conflict.

## Reading order
1. This file. 2. `CONTRACTS.md` sections your work package (WP) cites. 3. `DECISIONS.md`. 4. Your WP in `IMPLEMENTATION_PLAN.md`. 5. The reference files your WP names. Read only the line ranges you need.

## Commands (run from the repo root)
```bash
docs/plan/nas-v1/bin/nas_swift.sh build
docs/plan/nas-v1/bin/nas_swift.sh test <XCTestClass or Class/testMethod>
script/check_agents_invariants_have_tests.sh
git diff --check
```
Orchestrator only: full suite `/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache script/run_swift_test_suites.sh"`, `script/swift_meaningful_coverage.sh`, the Xcode build in `CLAUDE.md`, and these CI guards: `check_agents_invariants_have_tests`, `check_app_intents_never_purchase`, `check_app_layer_changes_have_tests codex/stable-invariant-ids`, `check_authorizer_has_no_default`, `check_detail_views_set_navigation_title`, `check_guardian_restore_verified`, `check_mas_build_lane_exists`, `check_no_await_in_xctassert`, `check_no_raw_animations`, `check_photos_import_readonly`, `check_recovery_goes_through_helper`, `check_storekit_config_matches_policy`, `check_test_dirs_are_targets`, `check_uitest_membership` (all `script/<name>.sh`).

## Definition of done (report each separately)
- **Compiled:** `nas_swift.sh build` exit 0.
- **Tested:** the WP's named test classes pass, and you saw each new test fail before the production change.
- **Verified:** behavior observed in the running app, with a screenshot path. Only G3 claims this.
- **Hardware:** real Synology, signed build, VoiceOver or owner network. Never claimed by an agent; stays `todo-hardware`.
Never write "done", "works" or "passes" without the command and its exit code.

## Hard rules
- Edit only your WP's owned paths. Need anything else → stop that part and add a `BLOCKED.md` entry.
- Implement contract names, signatures, rules and UI copy exactly. No extra public API, no renames, no "while I'm here" cleanups.
- Safety-critical files (`TransferExecutor`, `OrganizerDatabase`, `DestinationOperationLock`, anything under revert/dedupe): every changed line must trace to a contract item.
- Never weaken an AGENTS.md invariant, a threshold, or a test to make something pass. Never skip, delete or `XCTExpectFailure` an existing test.
- Tests first: write the WP's acceptance tests, run them, see them fail, then implement.
- Tag tests that cover an invariant with `// AGENTS-INVARIANT: N` on the line above the test method.
- New AppCore/App files guard Core imports with `#if canImport(ChronoframeCore)`. No `withAnimation` in views; use `Motion`. No `print`.
- User-facing text: plain, specific, reassuring; says what stayed unchanged; never shows raw errno, POSIX, SQLite or decoding text.
- Tests use temp directories under `FileManager.default.temporaryDirectory` and remove only what they created, in `tearDown`, via `FileManager.removeItem`. Tests restore any permissions they changed.
- Never touch a real NAS, `/Volumes/*`, or the user's photo folders from tests or tools you run.

## Never (subagents)
`git` anything except `git status` and `git diff`; `swift package` mutation, `brew`, `pip`, `npm`, any install; `rm`, `rm -rf`, `mv` on files outside your owned paths; `sudo`; network access; editing `project.pbxproj`, `.xcstrings`, or files under `ui/Xcode/UITests/`. The orchestrator commits.

## Never (everyone)
`git push`, `git reset --hard`, `git clean`, `git stash`, `git checkout -- <path>`, `git add -A`, `git add .`, force anything, `sudo`, worktrees.

## Machine facts
macOS 27.0.1, Xcode 27.2, Swift 6.4.2, Apple Silicon. Baseline `swift build --build-tests` succeeded on 2026-11-07 (about 26 s incremental). SwiftPM shares one `ui/.build`: only one agent builds at a time. The temp directory is APFS and usually case-insensitive.

## Out of scope (v1)
NAS duplicate cleanup or any delete/move/Trash on a NAS; protected/keeper folder rules; similarity or video perceptual matching on NAS; metered previews; include/exclude subtree editor; shared app/CLI remote mutation; state relocation/migration; Apple Photos to NAS; 1 TiB and eight-hour soak qualification; Reorganize/Guardian on NAS; multi-Mac locking.
