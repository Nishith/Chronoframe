# NAS v1 agent rules

Status: the NAS v1 plan shipped in PR #266. The shared rules now live in one place: `docs/plan/next-half/AGENT_RULES.md` (reading order, commands, definition of done, hard rules, never lists, checkout hygiene). It applies to this plan unchanged, except for the NAS-specific points below. The root `AGENTS.md` and `CLAUDE.md` still win on conflict.

## NAS-specific differences
- Commands use `docs/plan/next-half/bin/cf_swift.sh` (`build`, `test <filter>`); the NAS-specific `nas_swift.sh` wrapper was removed 2026-11-23; see git history. Also run `script/check_agents_invariants_have_tests.sh` and `git diff --check`.
- Orchestrator-only: the full sharded suite, `script/swift_meaningful_coverage.sh`, the Xcode build in `CLAUDE.md`, and these CI guards (all `script/<name>.sh`): `check_agents_invariants_have_tests`, `check_app_intents_never_purchase`, `check_app_layer_changes_have_tests codex/stable-invariant-ids`, `check_authorizer_has_no_default`, `check_detail_views_set_navigation_title`, `check_guardian_restore_verified`, `check_mas_build_lane_exists`, `check_no_await_in_xctassert`, `check_no_raw_animations`, `check_photos_import_readonly`, `check_recovery_goes_through_helper`, `check_storekit_config_matches_policy`, `check_test_dirs_are_targets`, `check_uitest_membership`.
- "Verified" is claimed only at G3. "Hardware" means real Synology, signed build, VoiceOver or the owner's network, and stays `todo-hardware`.
- Safety-critical files for this plan: `TransferExecutor`, `OrganizerDatabase`, `DestinationOperationLock`, anything under revert or dedupe.
- Subagents may run only `git status` and `git diff` (the shared rules also allow `git log`). Never touch a real NAS or `/Volumes/*` from tests or tools.
- Machine facts: baseline `swift build --build-tests` succeeded on 2026-11-07 (about 26 s incremental).

## Out of scope (v1)
NAS duplicate cleanup or any delete/move/Trash on a NAS; protected/keeper folder rules; similarity or video perceptual matching on NAS; metered previews; include/exclude subtree editor; shared app/CLI remote mutation; state relocation/migration; Apple Photos to NAS; 1 TiB and eight-hour soak qualification; Reorganize/Guardian on NAS; multi-Mac locking.
