# Next-half agent rules

Shared by the orchestrator and every subagent working on any plan under `docs/plan/` that names this file. The root `AGENTS.md` (safety invariants) and `CLAUDE.md` (commands, change discipline) still apply and win on conflict. Each plan folder (`PLAN_DIR`, for example `docs/plan/dedupe-persistence`) holds `CONTRACTS.md`, `DECISIONS.md`, `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, `ACCEPTANCE_MATRIX.md`, `BLOCKED.md` and `EVIDENCE_LEDGER.md`. The orchestrator's brief names `PLAN_DIR` and the work package (WP).

## Reading order
1. This file. 2. `PLAN_DIR/CONTRACTS.md` sections your WP cites. 3. `PLAN_DIR/DECISIONS.md`. 4. Your WP in `PLAN_DIR/IMPLEMENTATION_PLAN.md`. 5. The reference files your WP names, only the line ranges it names.

## Commands (run from the repo root)
```bash
docs/plan/next-half/bin/cf_swift.sh build
docs/plan/next-half/bin/cf_swift.sh test <XCTestClass or Class/testMethod>
git diff --check
```
Orchestrator only: `cf_swift.sh suite` (sharded full suite), `cf_swift.sh coverage`, `cf_swift.sh guards <base-ref>`, `cf_swift.sh xcode`, `script/check_agents_invariants_have_tests.sh`.

## Definition of done (report each separately)
- **Compiled:** `cf_swift.sh build` exit 0.
- **Tested:** the WP's named test classes pass, and you saw each new test fail (or fail to compile) before the production change.
- **Verified:** behavior observed in the running app with a screenshot path. Only a plan's final gate claims this, and only when the orchestrator can launch the app.
- **Hardware / owner:** signed build, App Review, real NAS, real Photos library with iCloud, VoiceOver. Never claimed by an agent; rows stay `todo-hardware` until Nishith records them.
Never write "done", "works" or "passes" without the command and its exit code.

## Hard rules
- Edit only your WP's owned paths. Need anything else → stop that part and add a `BLOCKED.md` entry in the template format.
- Implement contract names, signatures, rules and UI copy exactly. No extra public API, no renames, no "while I'm here" cleanups.
- Safety-critical files (`TransferExecutor`, `RevertExecutor`, `DeduplicateExecutor`, `DeduplicationPlanner`, `OrganizerDatabase`, `DestinationOperationLock`, `MutationRecoveryCoordinator`, `PhotosResourceExportService`, anything under revert or dedupe): every changed line must trace to a contract item.
- Never weaken an `AGENTS.md` invariant, a threshold or a test to make something pass. Never skip, delete or `XCTExpectFailure` an existing test.
- Tests first: write the WP's acceptance tests with the exact names, run them, see them fail, then implement.
- Tag tests that cover an invariant with `// AGENTS-INVARIANT: N` on the line above the test method.
- New AppCore/App files guard Core imports with `#if canImport(ChronoframeCore)`. No `withAnimation` in views; use `Motion`. No `print`. No force unwraps in production code.
- User-facing text: plain, specific, reassuring; says what stayed unchanged; never shows raw errno, POSIX, SQLite or Swift decoding text. Add new strings through `UserFacingErrorMessage` or the view's `Text("…")` literal; the orchestrator adds `.xcstrings` keys at the plan's documentation WP.
- Tests use temp directories under `FileManager.default.temporaryDirectory` and remove only what they created, in `tearDown`, via `FileManager.removeItem`. Tests restore any permissions they changed.
- Never touch a real NAS, `/Volumes/*`, the user's Photos library, or the user's photo folders from tests or tools you run.

## Never (subagents)
`git` anything except `git status`, `git diff` and `git log`; `swift package` mutation, `brew`, `pip`, `npm`, any install; `rm`, `rm -rf`, `mv` on files outside your owned paths; `sudo`; network access; editing `project.pbxproj`, `.xcstrings`, `Package.swift`, `AGENTS.md`, `CLAUDE.md`, or files under `ui/Xcode/UITests/`. The orchestrator commits.

## Never (everyone)
`git push`, `git reset --hard`, `git clean`, `git stash`, `git checkout -- <path>`, `git restore`, `git add -A`, `git add .`, force anything, `sudo`, worktrees, editing StoreKit configuration or purchase code, changing any `*Capability.isEnabled` release value.

## Machine facts
macOS 27.0.1, Xcode 27.2, Swift 6.4.2, Apple Silicon. Baseline `cf_swift.sh build` exit 0 on 2026-11-07 on `feature/nas-v1`. SwiftPM shares one `ui/.build`: only one agent builds at a time. The temp directory is APFS and usually case-insensitive. `.claude/` is gitignored; agent files are installed from `docs/plan/next-half/claude-config/`.

## Checkout hygiene
The checkout may hold unrelated untracked files (`marketing/`, `node_modules/`, `ui/.swiftpm/`, `docs/*.md` drafts). Agents never stage, stash, restore or delete them. Stage explicit paths only.
