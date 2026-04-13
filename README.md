# NAS Photo Organizer v3

> **TL;DR:** A high-performance Python tool that recursively scans, deduplicates, and organizes massive photo/video libraries on network-attached storage into a clean `YYYY/MM/DD` folder structure. Survives network drops, power outages, and partial transfers with atomic writes, SQLite-backed resume queues, and exponential backoff retries. Ships with a rich terminal UI, YAML configuration profiles, full audit logging, and a native macOS SwiftUI application.

---

## Features

- **Atomic File Transfers** — Files are written to `.tmp` staging buffers, flushed to disk via `os.fsync()`, and only then renamed into place. No corrupted partial files from network hiccups.
- **Resumable Job Queue** — The entire copy plan is committed to an SQLite database (`CopyJobs` table) before a single byte is written. If interrupted, just re-run — it picks up exactly where it stopped.
- **SQLite WAL Mode** — Write-Ahead Logging ensures the database never locks or corrupts, even during crashes.
- **BLAKE2b Hashing** — Fast, hardware-accelerated deduplication using chunked hash digests (first + last 512 KB).
- **Multithreaded I/O** — Configurable thread pool for parallel hashing across network drives with streaming dest walk (hashing begins as files are discovered, not after).
- **Exponential Backoff** — `tenacity`-powered automatic retries on network failures. Disk-full (`ENOSPC`) errors are never retried.
- **Disk Space Pre-Flight** — Checks available destination space (with 10 MB safety buffer) before each copy attempt. Fails immediately on `ENOSPC` rather than looping.
- **Orphan Cleanup** — Sweeps destination for leftover `.tmp` files from any previous interrupted run at startup.
- **Flapping Network Guard** — Aborts early when too many consecutive *or* total copy failures are detected, preventing an indefinite retry storm.
- **Parallel Date Classification** — Date extraction (EXIF, filename, Spotlight, mtime) runs in parallel threads on all new files simultaneously, eliminating the serial `mdls` bottleneck.
- **Rich Terminal Dashboard** — Animated progress bars with ETA, transfer speed (MB/s), and file counts.
- **Native macOS GUI** — A standalone Apple-native SwiftUI application that wraps the Python engine via a JSON pipe, with a 5-phase progress indicator, real-time speed/ETA, error badges, and post-run actions.
- **YAML Profiles** — Define named source/dest mappings in `nas_profiles.yaml` to manage multiple libraries.
- **Audit Receipts** — Every successful run generates a JSON receipt mapping exact `source → destination` paths.
- **Dry-Run Reports** — Preview the entire copy plan as a CSV spreadsheet before committing.

## Data Safety Rules

1. **Zero Deletion** — The source is never modified or deleted. All operations are read + copy only.
2. **Global Deduplication** — Files already in the destination (matched by BLAKE2b hash) are silently skipped. Internal source duplicates are routed to `Duplicate/YYYY/MM/DD/`.
3. **Collision Protection** — If a destination file already exists at the target path, the incoming copy is safely renamed with an incrementing `_collision_N` suffix. No data is ever overwritten.

## Date Extraction (Graceful Degradation)

| Priority | Method | Details |
| :---: | :--- | :--- |
| 1 | **EXIF** | `exifread` extracts `DateTimeOriginal` from JPEG/HEIC/RAW files |
| 2 | **Filename** | Regex parsing for `IMG_20240101_XXXXXX`, `VID_`, `PANO_`, `BURST_`, etc. |
| 3 | **Spotlight** | macOS `mdls kMDItemContentCreationDate` for MOV and other formats |
| 4 | **Modified Time** | Last resort: filesystem `mtime` |

Files that cannot yield a date go into `Unknown_Date/` for manual review.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                        organize_nas.py                              │
│              (bootstrap: installs deps, delegates to               │
│                    nas_organizer.core.main)                         │
└───────────────────────────────┬─────────────────────────────────────┘
                                │
                ┌───────────────▼───────────────┐
                │         nas_organizer/         │
                │                               │
                │  ┌──────────────────────────┐ │
                │  │       core.py            │ │
                │  │  ─ CLI argument parsing  │ │
                │  │  ─ Rich terminal UI      │ │
                │  │  ─ 5-phase orchestration │ │
                │  │  ─ Parallel execution    │ │
                │  └────┬──────┬──────┬───────┘ │
                │       │      │      │          │
                │  ┌────▼──┐ ┌─▼───┐ ┌▼──────┐  │
                │  │ io.py │ │ db  │ │ meta  │  │
                │  │       │ │ .py │ │ data  │  │
                │  │ hash  │ │     │ │ .py   │  │
                │  │ copy  │ │SQLi-│ │ EXIF  │  │
                │  │ retry │ │te   │ │ mdls  │  │
                │  │ space │ │WAL  │ │ regex │  │
                │  └───────┘ └─────┘ └───────┘  │
                └───────────────────────────────┘
                                │
                    (JSON pipe: stdout/stdin)
                                │
                ┌───────────────▼───────────────┐
                │     nas_ui/ (SwiftUI macOS)    │
                │                               │
                │  ContentView.swift             │
                │  ─ Sidebar: source/dest/opts  │
                │  ─ 5-phase progress indicator │
                │  ─ Speed + ETA display        │
                │  ─ Error badge counter        │
                │  ─ Post-run action bar        │
                │                               │
                │  BackendRunner.swift           │
                │  ─ NSTask process management  │
                │  ─ JSON event parsing         │
                │  ─ Speed/ETA computation      │
                └───────────────────────────────┘
```

---

## Execution Flow

```
organize_nas.py
      │
      ▼
  main()
    │
    ├─ 1. STARTUP
    │    ├── Load profile / parse args
    │    ├── Open CacheDB (SQLite WAL)
    │    ├── Open RunLogger
    │    └── Cleanup orphaned .tmp files in dest
    │
    ├─ 2. RESUME CHECK
    │    └── If pending jobs in DB → offer to resume or flush
    │
    ├─ 3. DISCOVERY  [task: discovery]
    │    └── os.walk(src) → collect all media files
    │
    ├─ 4. SRC HASH   [task: src_hash]
    │    └── ThreadPoolExecutor → BLAKE2b each source file
    │        (cache-aware: skip if size+mtime unchanged)
    │
    ├─ 5. DEST INDEX  [task: dest_hash]
    │    ├── fast_dest=True  → load from SQLite cache (instant)
    │    └── fast_dest=False → stream walk+hash concurrently
    │         └── ThreadPoolExecutor submits during os.walk
    │
    ├─ 6. CLASSIFICATION  [task: classification]
    │    ├── Compare src hashes against dest index
    │    │    ├── already_in_dst → skip
    │    │    ├── src_dup       → route to Duplicate/
    │    │    └── new_file      → queue for copy
    │    └── ThreadPoolExecutor → parallel date extraction
    │         EXIF → filename regex → mdls → mtime
    │
    ├─ 7. COPY PLAN
    │    ├── Assign YYYY/MM/DD paths with sequential numbers
    │    ├── Detect sequence overflow (>999/day → widened suffix)
    │    └── INSERT into CopyJobs (SQLite)
    │
    ├─ 8. DRY RUN?
    │    └── Yes → generate CSV report → complete
    │
    └─ 9. EXECUTE   [task: copy]
         ├── For each job: safe_copy_atomic()
         │    ├── check_disk_space() → raise ENOSPC immediately
         │    ├── shutil.copy2() → .tmp file
         │    ├── os.fsync()
         │    └── os.rename() → final path
         ├── verify_copy() if --verify
         ├── Track consecutive + total failures
         │    └── Abort if either threshold exceeded
         └── generate_audit_receipt() → JSON
```

---

## JSON Event Protocol (Python ↔ SwiftUI)

When `--json` is active, the backend emits one JSON object per line to stdout. The SwiftUI `BackendRunner` parses these in real time.

| `type` | Key Fields | Description |
| :--- | :--- | :--- |
| `startup` | — | Engine initialized |
| `task_start` | `task`, `total` | Phase beginning (discovery/src_hash/dest_hash/classification/copy) |
| `task_progress` | `task`, `completed`, `total`, `bytes_copied`, `bytes_total` | Mid-phase progress tick |
| `task_complete` | `task`, `new`, `already_in_dst`, `dups`, `errors`, `copied`, `failed` | Phase finished with summary |
| `copy_plan_ready` | `count` | Number of files queued for copy |
| `info` | `message` | Informational log line |
| `warning` | `message` | Non-fatal warning |
| `error` | `message` | Copy or verification failure |
| `prompt` | `message` | Requests a yes/no confirmation from the UI |
| `complete` | `status`, `dest`, `report` | Run finished; `status` ∈ {`finished`, `dry_run_finished`, `nothing_to_copy`, `cancelled`} |

---

## Installation & Usage

The bootstrap wrapper `organize_nas.py` handles dependency management. It detects missing packages (`exifread`, `tenacity`, `rich`, `pyyaml`) and offers to install them.

```bash
# Basic usage
python3 organize_nas.py --source /Volumes/NAS/Unsorted --dest /Volumes/NAS/Organized

# Use a named profile from nas_profiles.yaml
python3 organize_nas.py --profile mobile_backup

# Preview without copying (generates CSV report)
python3 organize_nas.py --dry-run

# Auto-confirm for unattended/cron usage
python3 organize_nas.py -y

# Fast repeated dry-runs (load dest index from cache, skip network scan)
python3 organize_nas.py --fast-dest --dry-run
```

### Native macOS UI

A standalone, fully native macOS Swift application is included. It wraps the Python engine via a JSON pipe.

```bash
cd nas_ui
./build.sh
open "build/NAS Organizer UI.app"
```

The UI provides:
- Source/destination folder pickers with live path validation
- Optional profile name input with in-app help popover
- "Preview" (dry-run) and "Start Transfer" split buttons
- 5-step phase indicator: Discover → Hash Src → Index Dst → Classify → Copy
- Real-time MB/s speed and ETA display
- Persistent error badge showing total error count
- Workers stepper (1–32 threads, default 8)
- Fast Dest Mode toggle
- Post-run actions: Open in Finder, View Report, Logs Folder

### CLI Flags

| Flag | Description |
| :--- | :--- |
| `--source PATH` | Source directory to scan |
| `--dest PATH` | Destination directory for organized output |
| `--profile NAME` | Load source/dest from `nas_profiles.yaml` |
| `--dry-run` | Generate a CSV report of planned operations without copying |
| `-y` / `--yes` | Skip confirmation prompts (for cron/GUI use) |
| `--verify` | Re-hash each file after copy to verify byte-level integrity |
| `--rebuild-cache` | Force a full re-index of the destination |
| `--fast-dest` | Load destination index from SQLite cache, skipping the network scan |
| `--workers N` | Thread pool size for parallel hashing (default: 8) |
| `--json` | Stream raw JSON events to stdout (used by the SwiftUI app) |

### Configuration Profiles

Define reusable source/dest pairs in `nas_profiles.yaml` next to `organize_nas.py`:

```yaml
default:
  source: "/Volumes/photo/bkp_1_9"
  dest: "/Volumes/home/Organized_Photos"

mobile_backup:
  source: "/Volumes/home/Mobile_Snapshots"
  dest: "/Volumes/home/Organized_Photos"
```

Running without `--source`/`--dest` automatically loads the `default` profile.

---

## Project Structure

```
NAS-Photo-Organizer/
├── organize_nas.py              # Bootstrap wrapper (dependency installer)
├── nas_organizer/
│   ├── __init__.py
│   ├── __main__.py              # python -m nas_organizer entry point
│   ├── core.py                  # Main orchestrator, CLI, Rich UI, 5-phase engine
│   ├── database.py              # SQLite WAL: FileCache + CopyJobs tables
│   ├── io.py                    # Atomic copy, BLAKE2b hashing, retries, disk check
│   └── metadata.py              # Date extraction (EXIF → filename → mdls → mtime)
├── nas_ui/
│   ├── Sources/
│   │   ├── AppDelegate.swift    # macOS app lifecycle
│   │   ├── ContentView.swift    # SwiftUI layout, sidebar, phase indicator
│   │   └── BackendRunner.swift  # NSTask process, JSON pipe, speed/ETA computation
│   └── build.sh                 # swiftc compiler script (no Xcode required)
├── test_organize_nas.py         # 214 tests, ≥95% code coverage
├── nas_profiles.yaml            # YAML configuration profiles
└── requirements.txt             # Python dependencies
```

---

## Testing

The project maintains **≥95% code coverage** across all modules.

```bash
# Run all tests
python3 -m unittest test_organize_nas.py -v

# Run with coverage report
python3 -m coverage run --source=nas_organizer -m unittest test_organize_nas
python3 -m coverage report --show-missing
```

Test classes cover:

| Area | What Is Tested |
| :--- | :--- |
| `TestFastHash` | Partial hashing, size prefix, large files |
| `TestProcessSingleFile` | Cache hits, mtime tolerance, OSError handling |
| `TestSafeCopyAtomic` | Atomic rename, collision suffixes, retry on transient errors |
| `TestVerifyCopy` | Hash match/mismatch, missing dest file |
| `TestCheckDiskSpace` | Sufficient space, ENOSPC raise, 10 MB buffer |
| `TestIsRetryableError` | ENOSPC not retried, other OSErrors retried |
| `TestCleanupTmpFiles` | Orphan removal, nested dirs, dotdir skip |
| `TestCacheDB` | Hash cache, job queue, WAL mode, idempotent inserts |
| `TestBuildDestIndex` | Empty dest, seq tracking, duplicate dir, fast_dest mode |
| `TestClassification` | New/dup/already-in-dest logic, date grouping |
| `TestParallelClassification` | Correct YYYY/MM/DD paths, mdls fallback |
| `TestClassificationException` | `get_file_date` crash → mtime fallback → Unknown_Date |
| `TestUnknownDatePath` | 1970 epoch date → `Unknown_Date/` copy plan |
| `TestExecuteJobs` | Successful copy, bytes tracking, `run_log` error messages |
| `TestMaxTotalFailures` | Consecutive + total failure abort thresholds |
| `TestSeqOverflowWarning` | `>999` files/day widened suffix, log warning |
| `TestRunLogger` | Open/close, log/warn/error, try/finally guarantee |
| `TestDryRunReport` | CSV columns, row count |
| `TestAuditReceipt` | JSON structure, return path |
| `TestLoadProfile` | YAML loading, missing profile error |
| `TestFormatSeq` | Zero-padding, >999 widening |
| `TestExifreadTagFound` | Tag match → parsed datetime; zero timestamp → None |
| `TestParseArgs` | All CLI flags |

---

## Generated Artifacts

All logs and reports are written inside the destination directory:

| File | Purpose |
| :--- | :--- |
| `.organize_cache.db` | SQLite database (hash cache + job queue) |
| `.organize_log.txt` | Plain-text run log with timestamps |
| `.organize_logs/audit_receipt_*.json` | Post-copy audit receipts (source → dest mapping) |
| `.organize_logs/dry_run_report_*.csv` | Dry-run preview spreadsheets |

---

## Reliability Improvements

This version adds several hardening improvements over v2:

### Disk Space Guard
Before each copy attempt, `check_disk_space()` verifies the destination has at least `file_size + 10 MB` of free space. An `ENOSPC` error is raised immediately and never handed to the retry decorator — unlike transient network failures, a full disk won't self-heal.

### Flapping Network Protection
Two failure counters run in parallel: `consecutive_fail` (resets on success) and `total_fail` (never resets). If either reaches its threshold (`MAX_CONSECUTIVE_FAILURES = 5` or `MAX_TOTAL_FAILURES = 20`), the run aborts immediately with a clear diagnostic message rather than grinding through thousands of doomed jobs.

### Orphan `.tmp` Cleanup
At startup, the engine walks the destination tree and removes any `*.tmp` files left by previous interrupted copies. This prevents stale partial files from accumulating over time.

### `ptask = 0` Bug Fix
Rich `Progress.add_task()` returns integer `TaskID` values starting at `0`. The previous `if progress and ptask:` guard treated task ID `0` as falsy, silently skipping all progress updates for the first task added to a `Progress` object. Fixed to `if progress is not None and ptask is not None:`.

### Resource Cleanup
The `main()` function is wrapped in a `try/finally` block that guarantees `RunLogger.close()` and `CacheDB.close()` are called even when an unhandled exception occurs mid-run.

### Parallel Classification
Date extraction (EXIF/filename/mdls/mtime) previously ran serially. It now runs in a `ThreadPoolExecutor` on the new-files list only, eliminating the `mdls` serial bottleneck for libraries with thousands of undated files.
