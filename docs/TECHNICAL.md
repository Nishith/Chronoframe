# Chronoframe Technical Documentation

This document collects the command-line, architecture, build, and artifact details that are useful for developers and advanced users. The root [README](../README.md) is intentionally focused on everyday app use.

## Command Line

Chronoframe ships a Python CLI at the repo root:

```bash
# Preview only
python3 chronoframe.py --source ~/Photos/Unsorted --dest ~/Photos/Organized --dry-run

# Copy files
python3 chronoframe.py --source ~/Photos/Unsorted --dest ~/Photos/Organized

# Revert a previous transfer
python3 chronoframe.py --revert ~/Photos/Organized/.organize_logs/audit_receipt_20260417_103000.json
```

Install Python dependencies manually if needed:

```bash
pip3 install -r requirements.txt
```

CLI flags:

| Flag | Description |
| :--- | :--- |
| `--source PATH` | Source directory to scan |
| `--dest PATH` | Destination root for organized output |
| `--profile NAME` | Load source and destination from `profiles.yaml` |
| `--dry-run` | Build the copy plan and write a CSV without copying |
| `--folder-structure` | Output layout: `YYYY/MM/DD`, `YYYY/MM`, `YYYY`, `YYYY/Mon/Event`, or `Flat` |
| `--verify` | Re-hash each file after copy to verify integrity |
| `--revert PATH` | Undo a previous run using its audit receipt JSON |
| `--rebuild-cache` | Force a full rebuild of the destination index |
| `--fast-dest` | Load destination index from cache instead of scanning |
| `--workers N` | Hashing thread count |
| `--json` | Emit JSON progress events |
| `-y`, `--yes` | Auto-confirm prompts |

The native app is ahead of the CLI for Review editing, Smart Event acceptance, Library Health, and Deduplicate UI workflows. The Python CLI remains compatible with shared Chronoframe artifacts.

## Generated Files

Chronoframe writes shared artifacts inside the destination:

| Path | Purpose |
| :--- | :--- |
| `.organize_cache.db` | SQLite cache, copy queue, dedupe feature cache, and review overrides |
| `.organize_log.txt` | Plain-text run log |
| `.organize_logs/dry_run_report_*.csv` | Dry-run plan export |
| `.organize_logs/preview_review_*.jsonl` | Review data for the app's Review tab |
| `.organize_logs/audit_receipt_*.json` | Transfer receipt used by revert |
| `.organize_logs/dedupe_audit_receipt_*.json` | Deduplicate receipt used by dedupe revert |

Important SQLite tables:

| Table | Purpose |
| :--- | :--- |
| `FileCache` | Source and destination path identity cache |
| `CopyJobs` | Persisted copy queue for resume |
| `DedupeFeatures` | Cached Vision feature prints, dHash, dimensions, dates, and quality scores |
| `ReviewOverrides` | User date and event corrections for future preview and transfer planning |

## Architecture

Chronoframe ships both a native macOS app and a Python CLI.

```text
Chronoframe/
  chronoframe.py
  chronoframe/
    core.py                 # CLI orchestration, planning, execution, revert
    database.py             # SQLite cache and queue
    io.py                   # Atomic copy, retry, hashing, verification
    metadata.py             # EXIF, filename, mdls, filesystem date resolution
  ui/
    Sources/
      ChronoframeCore/      # Native Swift domain engine
      ChronoframeAppCore/   # Stores, app services, engine selection
      ChronoframeApp/       # SwiftUI app and views
    Tests/
    Chronoframe.xcodeproj
  docs/screenshots/
  script/
```

Native Swift core modules include:

| Module | Responsibility |
| :--- | :--- |
| `MediaDiscovery` | Source and destination media discovery |
| `MediaDateResolver` | Rich date source and confidence resolution |
| `FileIdentityHasher` / `BLAKE2bHasher` | Content identity hashing |
| `DryRunPlanner` | Override-aware preview and transfer planning |
| `CopyPlanBuilder` | Destination routing, sequence allocation, duplicate routing |
| `TransferExecutor` | Atomic copy execution and verification |
| `RevertExecutor` | Hash-verified transfer revert |
| `ReorganizeExecutor` | Destination layout migration |
| `DeduplicateScanner` | Exact and visual duplicate analysis |
| `DeduplicationPlanner` | Keep/delete mutation planning |
| `DeduplicateExecutor` | Trash commit and dedupe revert |
| `LibraryHealthScanner` | On-demand destination health checks |

The app defaults to `SwiftOrganizerEngine` for preview, transfer, revert, and reorganize. `PythonOrganizerEngine` remains available for compatibility and CLI parity work.

## Organize Details

Supported destination layouts:

| Layout | Example |
| :--- | :--- |
| `YYYY/MM/DD` | `2024/06/15/2024-06-15_001.jpg` |
| `YYYY/MM` | `2024/06/2024-06-15_001.jpg` |
| `YYYY` | `2024/2024-06-15_001.jpg` |
| `YYYY/Mon/Event` | `2024/Jun/Tahoe Trip/2024-06-15_001.jpg` |
| `Flat` | `2024-06-15_001.jpg` |

`YYYY/Mon/Event` uses an accepted event override when one exists. Without an accepted override, it preserves the existing behavior of using the source file's immediate parent folder as the event segment. Files without a date route to `Unknown_Date/`.

Preview scans the source and destination, hashes content, resolves dates, classifies files, writes artifacts, and shows a transfer plan before any copying happens.

The Review tab is built from `.organize_logs/preview_review_*.jsonl` and includes:

- Ready to copy items.
- Already-in-destination items.
- Exact duplicates.
- Unknown dates.
- Low-confidence dates.
- Hash or read errors.
- Planned destination paths.
- Event suggestions when Smart Events are enabled.

Inline edits save durable overrides by content identity plus source path. If the user edits a date or event name, the preview becomes stale and must be rebuilt before transfer.

## Smart Event Suggestions

Smart Events are opt-in from Settings. When enabled, preview suggests event groups using:

- Date buckets.
- Capture-time proximity.
- An 8-hour default split threshold.
- Specific source folder names when useful.

Generic names such as `DCIM`, `Camera`, `Photos`, `Imports`, `Downloads`, and `100APPLE` are ignored. If Chronoframe cannot find a meaningful name, it creates an unnamed group for the user to label. Suggestions are review metadata only until accepted, and accepted suggestions require a preview rebuild before transfer.

## Library Health

The **Organize > Health** tab scans on demand. It does not run background Vision analysis.

Health cards cover:

- Ready to Organize.
- Unknown Dates in `Unknown_Date/`.
- Duplicates in `Duplicate/` and cached exact-duplicate hints.
- Interrupted Work from pending or failed copy jobs.
- History & Revert Safety from audit receipts.
- Structure Drift for destination files that do not match the selected Chronoframe layout.

Recommended actions can jump to Preview, Review Unknown Dates, Deduplicate, History, Reorganize Destination, or Refresh Destination Index.

## Deduplicate Details

The Deduplicate workspace scans the active organize destination by default, or a dedicated dedupe folder if the user chooses one.

It can find:

- Byte-identical duplicates using BLAKE2b identities.
- Near-duplicate photos using Vision feature prints.
- Burst-like groups using capture-time proximity.
- RAW+JPEG pairs.
- Live Photo HEIC+MOV pairs.

Settings include strict, balanced, and loose similarity presets, dHash prefilter thresholds, burst-mode behavior, pair-as-unit toggles, exact-duplicate grouping, and worker count.

Deduplicate caches feature prints, dHash values, dimensions, dates, and quality scores in `.organize_cache.db` so later scans are incremental. Commit writes a dedupe audit receipt before mutating anything, then moves selected files to Trash by default.

## Date Resolution

The native app records both the date and how confident Chronoframe is about it.

Sources:

1. Photo metadata.
2. Filename patterns.
3. Filesystem creation date.
4. Filesystem modification date.
5. User override.
6. Unknown.

Confidence values are high, medium, low, or unknown. Unknown dates still route to `Unknown_Date/` unless the user saves an override in Review.

## JSON Event Protocol

The Python backend can emit one JSON object per line with `--json`. The app also normalizes native Swift engine events into the same high-level run model.

| Event type | Key fields |
| :--- | :--- |
| `startup` | `status` |
| `task_start` | `task`, `total` |
| `task_progress` | `task`, `completed`, `total`, `bytes_copied`, `bytes_total` |
| `task_complete` | `task`, `found`, `already_in_dst`, `dups`, `errors`, `copied`, `failed`, `reverted`, `skipped` |
| `copy_plan_ready` | `count` |
| `info` / `warning` / `error` | `message` |
| `prompt` | `message` |
| `complete` | `status`, `dest`, `report` |

Example:

```json
{"type":"task_progress","task":"copy","completed":412,"total":8193,"bytes_copied":1824251904,"bytes_total":35280441344}
```

## Profiles

Profiles can be saved in the app or provided to the CLI through `profiles.yaml`:

```yaml
default:
  source: "/Volumes/MyDrive/Incoming"
  dest: "/Volumes/MyDrive/Organized_Photos"

mobile_backup:
  source: "/Volumes/MyDrive/Phone_Imports"
  dest: "/Volumes/MyDrive/Organized_Photos"
```

`profiles.yaml` is ignored by Git because it contains machine-specific paths.

## Keyboard Shortcuts

| Shortcut | Action |
| :--- | :--- |
| `Cmd+O` | Choose source folder |
| `Shift+Cmd+O` | Choose destination folder |
| `Shift+Cmd+P` | Toggle saved-profile field |
| `Cmd+R` | Start a preview |
| `Cmd+Return` | Start a transfer |
| `Cmd+L` | Toggle activity pane |

## Build From Source

### SwiftPM Tests

Use a local home and module cache to avoid system cache noise:

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache swift test --package-path ui"
```

Meaningful Swift coverage gate:

```bash
script/swift_meaningful_coverage.sh
```

This gate focuses on deterministic domain logic, planning, hashing, indexing, user-facing formatting, review metadata, and health scanning. It intentionally excludes most SwiftUI view rendering.

### Xcode Build

```bash
xcodebuild \
  -project ui/Chronoframe.xcodeproj \
  -scheme Chronoframe \
  -configuration Debug \
  -derivedDataPath .tmp/ChronoframeDerivedData \
  -destination "generic/platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

The Xcode project is used by CodeQL and app builds. If you add a Swift source file that must compile in the app, keep `ui/Chronoframe.xcodeproj/project.pbxproj` in sync with SwiftPM.

### App Bundle

```bash
cd ui
./build.sh
open "build/Chronoframe.app"
```

Release archive:

```bash
cd ui
./archive.sh
```

Validate a bundle:

```bash
python3 ui/Packaging/validate_app_bundle.py ui/build/Chronoframe.app
```

### Python Tests

```bash
python3 -m unittest discover -s tests -t . -v
```

Python coverage:

```bash
python3 -m coverage run -m unittest discover -s tests -t . -v
python3 -m coverage report -m --omit "tests/*"
```

Additional parity and benchmark suites:

| File | Focus |
| :--- | :--- |
| `tests/test_parity_fixtures.py` | Swift and Python dry-run planning parity |
| `tests/test_execution_parity_fixtures.py` | Swift and Python transfer execution parity |
| `tests/test_benchmarks.py` | Hashing and scanning microbenchmarks |

Before committing:

```bash
git diff --check
```

## Notes

- The GUI is macOS-specific.
- The Python CLI runs wherever the Python dependencies are available, with macOS-only Spotlight date resolution skipped on other platforms.
- The destination cache is a performance optimization. Use `--rebuild-cache` when you need a guaranteed fresh destination index.
- `--fast-dest` is for repeated previews against a stable destination.
- Releases can be packaged with the Release Package GitHub Actions workflow or locally with `ui/archive.sh`, then uploaded to GitHub Releases with a checksum.
