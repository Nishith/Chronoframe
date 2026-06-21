# Contributing to Chronoframe

Thanks for helping make Chronoframe safer and more useful. This repository is public for transparency, security review, and personal study, but Chronoframe is proprietary source-visible software. The license in [LICENSE](LICENSE) controls reuse, redistribution, and derivative works.

## Good Ways To Help

- Report bugs with clear reproduction steps.
- Share edge cases around photo, video, RAW+JPEG, Live Photo, NAS, and external-drive workflows.
- Suggest documentation improvements.
- Propose user-facing copy improvements, especially around safety and error recovery.
- Report security or data-safety issues privately through the repository's security reporting flow.

Please do not upload private photos, videos, EXIF dumps, filesystem listings, or logs that include personal paths unless you have intentionally sanitized them.

## Bug Reports

Useful bug reports include:

- Chronoframe version or commit.
- macOS version.
- Whether you used the native app or the SwiftPM CLI (`ChronoframeCLI`).
- Source and destination storage type, such as local disk, external drive, NAS, or cloud-synced folder.
- A small synthetic reproduction case when possible.
- What you expected, what happened, and whether the source files were left untouched.

## Pull Requests

Open a discussion or issue before larger changes. Small documentation fixes are welcome directly.

By opening a pull request, you confirm that you wrote the contribution or have the right to submit it, and you grant the project owner permission to use, modify, and distribute that contribution as part of Chronoframe under Chronoframe's current and future licensing terms.

Pull requests should:

- Preserve Chronoframe's safety invariants: source folders are read-only, destination files are not overwritten, and destructive operations must be receipt-backed and reversible where applicable.
- Preserve preview/executor parity: destructive dedupe changes must flow through the immutable `DeduplicationPlan`, with expected identities for every target.
- Preserve destination serialization and recovery: hold the cross-process lease through prompts and finalization, never equate inaccessible paths with missing ones, and keep receipt/journal changes backward-tolerant.
- Treat RAW+JPEG, Live Photo, and shared-sidecar Keep-wins behavior as a filesystem safety boundary, not just a UI preference.
- Add or update tests for behavior changes.
- Keep SwiftPM and `ui/Chronoframe.xcodeproj/project.pbxproj` in sync when adding Swift files used by the app.
- Keep user-facing errors plain, specific, reassuring, and free of raw tracebacks.
- Avoid unrelated refactors.

## Local Validation

Run the checks that match your change. Chronoframe is Swift-only — there is no Python test suite. The CI-equivalent unit lane uses fresh-process suite shards:

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache script/run_swift_test_suites.sh"
```

A direct SwiftPM run is still useful while iterating:

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache swift test --package-path ui"
```

```bash
script/swift_meaningful_coverage.sh
```

Safety-critical changes should also run the invariant guard:

```bash
script/check_agents_invariants_have_tests.sh
```

```bash
xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug -derivedDataPath .tmp/ChronoframeDerivedData -destination "generic/platform=macOS" CODE_SIGNING_ALLOWED=NO build
```

Before opening a pull request:

```bash
git diff --check
```
