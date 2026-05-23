# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

> `AGENTS.md` is the authoritative project-memory document — safety invariants, detailed architecture, CI notes, and packaging details all live there. This file focuses on commands and orientation for Claude Code.

## Commands

All commands run from the repo root unless noted.

### SwiftPM tests (authoritative unit-test lane)

Always use a local home and module cache to avoid sandbox noise:

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache swift test --package-path ui"
```

Run a single test class or method with `--filter`:

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home ... swift test --package-path ui --filter ChronoframeCoreTransferExecutorBehaviorTests"
/bin/zsh -lc "HOME=$PWD/.tmp/home ... swift test --package-path ui --filter ChronoframeCoreTransferExecutorBehaviorTests/testAtomicCopyVerification"
```

### Coverage gate

```bash
script/swift_meaningful_coverage.sh
```

This enforces 95%+ on deterministic domain logic only (planning, hashing, executors, receipt writers, user-facing formatting). Raw SwiftPM aggregate coverage (~62%) is misleading because SwiftUI view bodies are counted but not unit-tested. Don't claim project-wide coverage above 95% unless the metric scope is clear.

### Safety invariant check

```bash
script/check_agents_invariants_have_tests.sh
```

Every bullet under `## Safety Invariants` in `AGENTS.md` must have at least one test tagged `// AGENTS-INVARIANT: N`. Run this after touching executor, revert, or deduplication code.

### Build and run the app

```bash
script/build_and_run.sh          # build then launch
cd ui && ./build.sh              # build only
open ui/build/Chronoframe.app    # launch the already-built app
```

### Xcode build (required for CodeQL; keep in sync with SwiftPM)

```bash
xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug \
  -derivedDataPath .tmp/ChronoframeDerivedData \
  -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build
```

### CLI

```bash
swift run --package-path ui ChronoframeCLI --source ~/Photos/Unsorted --dest ~/Photos/Organized --dry-run
swift run --package-path ui ChronoframeCLI --revert ~/Photos/Organized/.organize_logs/audit_receipt_*.json
```

### Icon regeneration

```bash
swift run --package-path ui ChronoframeIconTool <output-dir>
```

The icon tool is the single source of truth for the app icon — all PNG variants are generated from code in `ChronoframeIconTool`, not from a Figma or Sketch file.

### Bundle validation

```bash
swift run --package-path ui ChronoframePackagingTool ui/build/Chronoframe.app
```

### Pre-commit

```bash
git diff --check
```

## Architecture

Chronoframe is Swift-only. The old Python backend has been retired.

```
ui/Sources/
  ChronoframeCore/       Pure domain engine — no AppKit/SwiftUI deps
  ChronoframeAppCore/    Stores, services, and the OrganizerEngine protocol
  ChronoframeApp/        SwiftUI views and app entry point
  ChronoframeCLIKit/     CLI parser and runners (shares ChronoframeCore)
  ChronoframeCLI/        CLI executable entry point
  ChronoframePackaging/  App bundle validation helpers
  ChronoframeIconTool/   Procedural icon renderer
```

### Layer boundaries

`ChronoframeCore` contains all the stateless domain algorithms: `MediaDiscovery`, `MediaDateResolver`, `DryRunPlanner`, `CopyPlanBuilder`, `TransferExecutor`, `RevertExecutor`, `ReorganizeExecutor`, `DeduplicateScanner`, `DeduplicationPlanner`, `DeduplicateExecutor`, `LibraryHealthScanner`. It has no AppKit dependency and is tested entirely with SwiftPM unit tests.

`ChronoframeAppCore` wraps the core in `@MainActor` stores (`RunSessionStore`, `SetupStore`, `HistoryStore`, `PreviewReviewStore`, `DeduplicateSessionStore`, etc.) and defines the `OrganizerEngine` protocol. `SwiftOrganizerEngine` is the concrete implementation; `MockOrganizerEngine` (in `Tests/`) is the test double.

`ChronoframeApp` contains the SwiftUI views. `AppState` is the root `@MainActor ObservableObject` that holds all stores and wires coordinator objects (`SetupCoordinator`, `RunCoordinator`, `HistoryCoordinator`) which encapsulate multi-step flows and navigate between views.

### On-disk artifacts (all inside the destination folder)

| Path | Purpose |
|------|---------|
| `.organize_cache.db` | SQLite: `FileCache`, `CopyJobs`, `DedupeFeatures`, `ReviewOverrides` |
| `.organize_logs/audit_receipt_*.json` | Organize transfer receipt (used by revert) |
| `.organize_logs/dedupe_audit_receipt_*.json` | Deduplicate receipt |
| `.organize_logs/reorganize_audit_receipt_*.json` | Reorganize receipt |
| `.organize_logs/dry_run_report_*.csv` | Dry-run plan export |
| `.organize_logs/preview_review_*.jsonl` | Review tab data |

## Critical notes

**SwiftPM ↔ Xcode project sync.** When adding a Swift source file that must compile in the app, add it to both `ui/Package.swift` and `ui/Chronoframe.xcodeproj/project.pbxproj`. CodeQL builds the Xcode project, not the Swift package, so a file missing from the Xcode project will cause CodeQL to fail silently.

**Safety invariants.** Before weakening any invariant (source read-only, no overwrites, Trash-only delete, receipt-before-mutation, revert hash-checks), confirm it's an explicit product change. Add `// AGENTS-INVARIANT: N` to at least one test covering the invariant and re-run `script/check_agents_invariants_have_tests.sh`.

**User-facing error text.** Use `UserFacingErrorMessage.swift` to format technical errors. Keep wording plain, specific, and reassuring. When a run fails, copy must note that originals were untouched. Never surface raw `NSError`, POSIX codes, SQLite messages, or Swift decoding language directly in the UI.

**UI language.** Chronoframe uses a restrained, work-focused "Meridian" visual language — native controls, no decorative gradients or orb backgrounds, no instructional text describing obvious UI mechanics. The amber waypoint dot is the brand motif.

## Change discipline

**Surgical changes in safety-critical code.** When editing executor, revert, or deduplication code, every changed line must trace directly to the request. Don't opportunistically tighten error handling, rename variables, or clean up adjacent logic in the same change. Safety-critical diffs are audited, and noise obscures what actually changed. If you notice something worth fixing nearby, flag it — don't fold it in.

**Goal-driven execution for invariant work.** For any change that touches a safety invariant's behavior, the definition of done is not "code matches the description" — it's "the invariant script passes with a new or updated tagged test." Concretely:

```
1. Identify which AGENTS-INVARIANT number(s) apply
2. Write or update a test tagged // AGENTS-INVARIANT: N that fails before your fix
3. Make the change
4. Confirm script/check_agents_invariants_have_tests.sh passes
```

For bug fixes generally: write a test that reproduces the failure first, then fix it.

## Ignore these paths

`.claude/worktrees/`, `.codex/environments/environment.toml`, `.tmp/`, `ui/.build/`, `ui/build/`, `htmlcov/`
