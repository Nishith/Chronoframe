# Chronoframe

**A safe macOS photo and video organizer for messy libraries, old backups, camera cards, and NAS dumps.**

Chronoframe scans an unsorted source folder, resolves capture dates, previews exactly where files will go, and copies them into a clean destination library. Originals are never moved, renamed, edited, or deleted.

| ![Chronoframe setup overview](docs/screenshots/ui-setup-overview.png) | ![Run preview with timeline](docs/screenshots/ui-run-preview.png) |
| :---: | :---: |
| Setup - choose source, destination, and layout | Run - preview, review, then transfer |

## Current App

Chronoframe is primarily a native macOS SwiftUI app with three top-level workspaces:

| Workspace | What it does |
| :--- | :--- |
| **Organize** | Setup, preview, review, transfer, health checks, history, revert, and destination reorganization |
| **Deduplicate** | Find exact duplicates, near duplicates, and burst-like similar shots before moving chosen files to Trash |
| **Profiles** | Save reusable source/destination setups |

The app uses a restrained native macOS interface with the Meridian visual language. The amber waypoint dot marks progress and attention states throughout the app.

## What Chronoframe Does

- Reads photos and videos from a source folder without modifying the source.
- Resolves dates from photo metadata, filenames, filesystem creation dates, and filesystem modification dates.
- Copies files into one of several destination layouts.
- Detects exact duplicates by file content, not by filename.
- Lets you review uncertain dates, duplicates, skipped items, and planned paths before transfer.
- Saves user date and event corrections as Chronoframe planning metadata, not as EXIF edits.
- Suggests event groupings when enabled, but never applies them automatically.
- Shows a Library Health dashboard for unknown dates, duplicates, interrupted work, audit safety, and structure drift.
- Keeps audit receipts so completed organize and dedupe runs can be reverted safely.

## Safety Guarantees

- **Originals are never modified.** Chronoframe only reads source files.
- **Copies are atomic.** Files are written to a temporary path, flushed, then renamed into place.
- **No overwrites.** Destination collisions receive a distinct filename.
- **Duplicates are content-based.** Chronoframe uses BLAKE2b identities instead of filename guesses.
- **Transfers are planned first.** Preview and transfer use the same override-aware planner path.
- **Review edits make the preview stale.** Transfer is disabled until the preview is rebuilt.
- **Revert verifies hashes.** Revert deletes only destination files whose current hash still matches the audit receipt.
- **Deduplicate defaults to Trash.** Hard delete is available only behind an explicit Settings toggle and confirmation.
- **Pair handling is conservative.** RAW+JPEG and Live Photo HEIC+MOV pairs can be treated as units, and keep decisions win.

## Install

1. Download `Chronoframe.zip` from the [Releases page](https://github.com/Nishith/Chronoframe/releases).
2. Unzip it.
3. Drag `Chronoframe.app` to Applications.
4. Open the app.

If macOS blocks the app on first launch, right-click `Chronoframe.app`, choose **Open**, then confirm.

## First Run

1. Open **Organize > Setup**.
2. Choose a source folder.
3. Choose a destination folder.
4. Pick a folder layout.
5. Click **Preview**.
6. Open **Run > Review** to inspect uncertain items, dates, event names, duplicates, and skipped items.
7. Click **Transfer** once the preview is current and looks right.

If you edit a date or event name in Review, Chronoframe saves that correction to `.organize_cache.db` and marks the preview stale. Rebuild the preview before transfer so the approved plan and actual transfer stay identical.

## Organize Features

### Setup

Setup tracks the source, destination, readiness state, selected folder layout, saved profiles, and bookmark-backed folder access.

Supported destination layouts:

| Layout | Example |
| :--- | :--- |
| `YYYY/MM/DD` | `2024/06/15/2024-06-15_001.jpg` |
| `YYYY/MM` | `2024/06/2024-06-15_001.jpg` |
| `YYYY` | `2024/2024-06-15_001.jpg` |
| `YYYY/Mon/Event` | `2024/Jun/Tahoe Trip/2024-06-15_001.jpg` |
| `Flat` | `2024-06-15_001.jpg` |

`YYYY/Mon/Event` uses an accepted event override when one exists. Without an accepted override, it preserves the existing behavior of using the source file's immediate parent folder as the event segment. Files without a date route to `Unknown_Date/`.

### Preview And Review

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

Review supports filters for attention items, unknown dates, low-confidence dates, duplicates, skipped items, ready items, and all items. Inline edits save durable overrides by content identity plus source path.

### Smart Event Suggestions

Smart Events are opt-in from Settings. When enabled, preview suggests event groups using:

- Date buckets.
- Capture-time proximity.
- An 8-hour default split threshold.
- Specific source folder names when useful.

Generic names such as `DCIM`, `Camera`, `Photos`, `Imports`, `Downloads`, and `100APPLE` are ignored. If Chronoframe cannot find a meaningful name, it creates an unnamed group for the user to label. Suggestions are review metadata only until accepted, and accepted suggestions require a preview rebuild before transfer.

### Library Health

The **Organize > Health** tab scans on demand. It does not run background Vision analysis.

Health cards cover:

- Ready to Organize.
- Unknown Dates in `Unknown_Date/`.
- Duplicates in `Duplicate/` and cached exact-duplicate hints.
- Interrupted Work from pending or failed copy jobs.
- History & Revert Safety from audit receipts.
- Structure Drift for destination files that do not match the selected Chronoframe layout.

Recommended actions can jump to Preview, Review Unknown Dates, Deduplicate, Run History, Reorganize Destination, or Refresh Destination Index.

### History, Revert, And Reorganize

Run History indexes reports, logs, queue databases, transfer audit receipts, and dedupe audit receipts under `.organize_logs/`.

Transfer receipts can be reverted from History. Revert is hash-verified and leaves edited or missing files alone. Dedupe receipts can also be restored through the Deduplicate workspace.

Reorganize Destination can move existing Chronoframe-organized destination files from one supported layout to another while preserving safety checks.

## Deduplicate Features

The Deduplicate workspace scans the active organize destination by default, or a dedicated dedupe folder if you choose one.

It can find:

- Byte-identical duplicates using BLAKE2b identities.
- Near-duplicate photos using Vision feature prints.
- Burst-like groups using capture-time proximity.
- RAW+JPEG pairs.
- Live Photo HEIC+MOV pairs.

Settings include strict, balanced, and loose similarity presets, dHash prefilter thresholds, burst-mode behavior, pair-as-unit toggles, exact-duplicate grouping, worker count, and the hard-delete safety toggle.

Deduplicate caches feature prints, dHash values, dimensions, dates, and quality scores in `.organize_cache.db` so later scans are incremental. Commit writes a dedupe audit receipt before mutating anything, then moves selected files to Trash by default.

## Command Line

Chronoframe still ships a Python CLI at the repo root:

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

The native app is ahead of the CLI for Review editing, Smart Event acceptance, Library Health, and Deduplicate UI workflows. The Python CLI remains compatible with the shared artifacts.

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
| `DeduplicateExecutor` | Trash/delete commit and dedupe revert |
| `LibraryHealthScanner` | On-demand destination health checks |

The app defaults to `SwiftOrganizerEngine` for preview, transfer, revert, and reorganize. `PythonOrganizerEngine` remains available for compatibility and CLI parity work.

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

## Build From Source

### SwiftPM tests

Use a local home and module cache to avoid system cache noise:

```bash
/bin/zsh -lc "HOME=$PWD/.tmp/home XDG_CACHE_HOME=$PWD/.tmp/home/Library/Caches CLANG_MODULE_CACHE_PATH=$PWD/.tmp/modulecache SWIFTPM_MODULECACHE_OVERRIDE=$PWD/.tmp/modulecache swift test --package-path ui"
```

Meaningful Swift coverage gate:

```bash
script/swift_meaningful_coverage.sh
```

This gate focuses on deterministic domain logic, planning, hashing, indexing, user-facing formatting, review metadata, and health scanning. It intentionally excludes most SwiftUI view rendering.

### Xcode build

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

### App bundle

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

### Python tests

```bash
python3 -m unittest test_chronoframe test_ui_build test_ui_packaging -v
```

Python coverage:

```bash
python3 -m coverage run -m unittest test_chronoframe test_ui_build test_ui_packaging -v
python3 -m coverage report -m --omit "test_*"
```

Additional parity and benchmark suites:

| File | Focus |
| :--- | :--- |
| `test_parity_fixtures.py` | Swift and Python dry-run planning parity |
| `test_execution_parity_fixtures.py` | Swift and Python transfer execution parity |
| `test_benchmarks.py` | Hashing and scanning microbenchmarks |

Before committing:

```bash
git diff --check
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

## Notes

- The GUI is macOS-specific.
- The Python CLI runs wherever the Python dependencies are available, with macOS-only Spotlight date resolution skipped on other platforms.
- The destination cache is a performance optimization. Use `--rebuild-cache` when you need a guaranteed fresh destination index.
- `--fast-dest` is for repeated previews against a stable destination.
- Releases are currently built locally and uploaded to GitHub Releases manually.
