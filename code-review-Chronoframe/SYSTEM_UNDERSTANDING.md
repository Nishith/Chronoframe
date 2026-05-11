# Chronoframe — System Understanding

*Generated: 2026-05-10 | Review type: NEW-BUILD | Reviewer: Principal-engineer deep-code-review*

---

## Overview

Chronoframe is a macOS-native photo and video library organizer. Its core purpose is to consolidate scattered media (across drives, phones, and years of backups) into a single, date-organized destination folder — **without ever modifying or risking the originals.**

The product's defining promise: source files are always read-only, transfers are atomic and hash-verified, and every run produces an audit receipt that makes the entire operation fully reversible. This makes it safe to run on irreplaceable family photo archives.

**Who depends on it:** Individual users managing personal photo libraries — typically years or decades of media from multiple devices and drives. There are no multi-user or networked deployments; it is a single-user, local-only macOS application.

**Why it matters:** The files it operates on (family photos, home videos) are often irreplaceable. A correctness bug that deletes or corrupts the wrong files is a permanent, unrecoverable harm. The entire design is structured around preventing this class of failure.

---

## High-Level Architecture

Chronoframe has a **dual-layer implementation**:

| Layer | Technology | Purpose |
|-------|-----------|---------|
| macOS App | Swift 6, SwiftUI | User-facing GUI, state management, engine orchestration |
| Core Engine (Swift) | Swift 6, Foundation, Vision | Planning, hashing, transfer, revert, deduplicate, health |
| CLI Backend (Python) | Python 3.13 | Legacy CLI, hybrid engine, compatibility layer |
| Database | SQLite 3 | Hash cache, copy job queue, dedupe feature cache |
| Shared State | JSON files on disk | Audit receipts, dry-run reports, run logs |

The Swift app (`ui/Sources/ChronoframeApp/`) talks to `ChronoframeAppCore` services, which delegate to `ChronoframeCore` — the domain engine. The Python backend (`chronoframe/`) runs as a subprocess when the app selects the hybrid engine, communicating via JSON on stdout.

**External dependencies (Python):** `exifread`, `tenacity`, `rich`, `pyyaml` — all local, no network services.

**External dependencies (Swift):** System frameworks only — `Foundation`, `Vision`, `AppKit`, `SQLite3` (linked library). No third-party Swift packages.

---

## Core Flows

### 1. Organize (primary flow)

```
User selects source + destination folders
        ↓
Discovery: os.walk(src), filter by extension, skip symlinks
        ↓
Source indexing: BLAKE2b hash each file (parallel, cached)
        ↓
Destination indexing: BLAKE2b hash existing destination files (parallel, cached)
        ↓
Classification: compare source hashes to dest index
  → already_in_dest  (skip)
  → internal_dup     (route to Duplicate/ subdirectory)
  → new              (route to date-organized destination)
        ↓
Date extraction per new file (parallel):
  1. EXIF DateTimeOriginal (exifread)
  2. Filename patterns (IMG_YYYYMMDD_, YYYYMMDD-HHMMSS, etc.)
  3. Spotlight metadata (mdls subprocess, 5s timeout)
  4. File mtime (fallback)
        ↓
Copy plan: assign destination paths with zero-padded sequence numbers
        ↓
DB queue: persist plan as PENDING rows in CopyJobs (SQLite)
        ↓
Execute: for each job:
  1. Disk space pre-flight check (10 MB buffer)
  2. Atomic copy: write to <dest>.tmp → fsync → rename
  3. Optional: re-hash destination, compare to planned hash
  4. Update CopyJobs status → COPIED or FAILED
        ↓
Audit receipt: write JSON to <dest>/.organize_logs/audit_receipt_*.json
        ↓
Done (source untouched)
```

### 2. Revert flow

```
User selects an audit receipt file
        ↓
Parse JSON receipt: list of {source, dest, hash} transfers
        ↓
For each transfer:
  - Check if dest file exists
  - Re-hash the dest file
  - If hash matches planned hash → os.remove(dest)
  - If hash mismatch → skip (user has modified the file)
  - Clean up empty directories
        ↓
Report: N reverted, M skipped/modified
```

### 3. Deduplicate flow

```
User scans destination
        ↓
DeduplicateScanner: BLAKE2b exact-match + Vision feature prints + dHash perceptual hashing
        ↓
DuplicateClusterer: group files by similarity (exact / near-identical / similar)
        ↓
Review UI: user selects keeper per cluster
        ↓
DeduplicateExecutor: move non-keepers to Trash or hard-delete
        ↓
Dedupe audit receipt: written before any mutation
```

### 4. Resume / interrupted session

If a previous run was interrupted mid-transfer, the PENDING rows remain in the CopyJobs SQLite table. On next launch, Chronoframe detects these and offers to resume — re-executing only the remaining jobs using the already-computed plan.

---

## Data Model and Data Lifecycle

### Entities

| Entity | Storage | Fields | Sensitive? |
|--------|---------|--------|-----------|
| FileCache | SQLite | id (namespace), path, hash, size, mtime | Path only |
| CopyJobs | SQLite | src_path, dst_path, hash, status | Path only |
| DedupeFeatures | SQLite | path, blake2b, dhash, feature_print, dimensions, quality | Path only |
| ReviewOverrides | SQLite | cluster_id, decision | No |
| Audit receipt | JSON file | runID, timestamp, transfers[{source, dest, hash}] | Path only |
| Run log | Plain text | Timestamped operation log | Path only |

### Sensitive data

- **File paths** are stored and logged locally. They may contain personally identifying information (e.g., `~/Photos/2024-Vacation-John-Sarah/`). They are never transmitted externally.
- **BLAKE2b hashes** are non-reversible; safe to store.
- **No credentials, tokens, or PII** beyond filesystem paths.

### Lifecycle

- SQLite database lives at `<dest>/.organize_cache.db` — persists across runs for caching
- Audit receipts accumulate in `<dest>/.organize_logs/` — never automatically deleted
- Run log at `<dest>/.organize_log.txt` — grows indefinitely (no rotation; see Finding 6)
- Temp files (`<planned_dest>.tmp`) — written during copy, renamed on success, cleaned on next run startup

---

## Security Model

### Trust boundaries

| Boundary | What is trusted |
|---------|----------------|
| User → macOS file picker | Explicit folder selection; macOS enforces sandbox scope |
| App → security-scoped bookmarks | Stored in macOS keychain; persists across restarts |
| Python subprocess → stdout JSON | Trusted: same user, same machine, no network hop |
| Audit receipt → revert operation | **Partially trusted**: hash verification prevents arbitrary deletion, but path validation is missing (Finding 2) |

### Authentication and authorization

None required. Chronoframe is a single-user, local-only application. macOS sandbox + security-scoped bookmarks provide the access boundary. The user explicitly selects which folders the app may access.

### Security-critical invariants

| Invariant | Where enforced |
|-----------|---------------|
| Source files are never modified | `os.walk` is read-only; `shutil.copy2` does not move; no `os.remove(src)` calls |
| No destination overwrites | `os.path.exists(dst)` collision loop in `io.py:111-117` appends `_collision_N` suffix |
| Atomic writes | Write to `.tmp` → `fsync` → `os.rename` in `io.py:119-124` |
| Hash verification before revert deletion | `fast_hash(dst) == expected_hash` in `core.py:344-346` before `os.remove` |
| Symlinks never followed | `os.path.islink()` checks at `io.py:14-15`, `core.py:487, 493` |
| Parameterized SQL only | No dynamic SQL anywhere in `database.py` |
| YAML safe deserialization | `yaml.safe_load()` at `core.py:113, 413` |

### Abuse considerations

- **Receipt crafting (P1):** A receipt with `dest` paths outside the destination directory could cause file deletion outside scope (mitigated by BLAKE2b hash check, but no path boundary validation — see Finding 2)
- **`.tmp` collateral deletion (P1):** Any `.tmp` file under the destination is silently deleted on startup, including files from other applications (see Finding 1)

---

## Reliability and Operational Model

### Failure modes

| Failure | Behavior |
|---------|---------|
| Copy fails (transient I/O) | Tenacity retries up to 5× with exponential backoff (1–10s) |
| Copy fails (permanent: ENOSPC, ENOENT) | Immediate failure, job marked FAILED, no retry |
| 5 consecutive failures | Run aborts; partial receipt written with status=ABORTED |
| 20 total failures | Run aborts |
| Hash verification fails | Destination copy deleted; job marked FAILED |
| Interrupted mid-transfer | PENDING rows remain; resumed on next run |
| Source file disappeared mid-run | ENOENT → non-retryable failure, job skipped |

### Retries and timeouts

- File copy: 5 attempts, exponential 1–10s backoff, only for retryable OSErrors
- `mdls` metadata query: 5-second subprocess timeout (`metadata.py:58`)
- No timeouts on SQLite operations or thread pool (bounded by file size / GIL)

### Deploy / rollback model

- Distributed as a notarized macOS `.app` bundle in a ZIP
- No server-side deployment; no rollback required
- Revert is a first-class user-facing feature (audit receipt → revert)

### Observability

- **Run log** (`<dest>/.organize_log.txt`): timestamped plain-text entries
- **JSON progress events** (stdout, for GUI): startup, task_start, task_progress, task_complete, error, warning, complete
- **Audit receipts** (JSON): immutable per-run record of what was transferred
- **No metrics, no dashboards, no external alerting** — local-only tool, appropriate for scope

---

## Performance and Capacity Posture

### Hot paths

1. **BLAKE2b hashing**: 8 MB chunks; parallel via `ThreadPoolExecutor` (default 8 workers). I/O-bound; no CPU bottleneck.
2. **Destination index scan**: parallel hash walk; cached in SQLite for subsequent runs.
3. **Date extraction**: parallel; EXIF fast, `mdls` subprocess slow (5s timeout per file). Falls back to filename parsing if `exifread` unavailable.

### Scaling limits

- **Thread pool**: 8 workers default, configurable via `--workers`. Single-machine I/O; no distributed coordination.
- **SQLite**: Single connection, WAL mode. Handles tens of thousands of rows without issue for a photo library.
- **File count**: No hard limit; tested with thousands of files.

### Cost drivers

- `.organize_log.txt` grows unbounded (Finding 6) — potential ENOSPC on SD card destinations
- Audit receipts accumulate forever in `.organize_logs/` — no cleanup policy

---

## Testing and Quality Posture

### Test strategy

- **235 Python test methods** across 55 test classes in `tests/test_chronoframe.py` (3,241 LOC)
- **Real I/O**: tests use actual tempdir + real SQLite, not mocks — no test theater
- **Parity fixtures**: `test_parity_fixtures.py` and `test_execution_parity_fixtures.py` cross-validate Python and Swift planning output against golden files
- **Xcode UI tests**: run in CI against the full app on macOS
- **Swift coverage gate**: `script/swift_meaningful_coverage.sh` enforces coverage of deterministic domain logic

### Major gaps

| Gap | Risk |
|-----|------|
| No Python coverage threshold in CI (Finding 5) | Coverage regressions go undetected |
| No test for `cleanup_tmp_files` leaving non-Chronoframe `.tmp` alone (Finding 1) | Collateral deletion untested |
| No test for receipt path boundary validation (Finding 2) | Path escape untested |
| No test for concurrent SQLite read/write (Finding 3) | Lock gap untested |
| Swift tests not read in depth | Unknown gaps in Swift layer |

---

## Dependency and Supply-Chain Posture

### Python

| Package | Version | Pinned | Notes |
|---------|---------|--------|-------|
| exifread | 3.5.1 | Yes | Graceful fallback if unavailable |
| tenacity | 9.1.4 | Yes | Retry logic; no network |
| rich | 15.0.0 | Yes | Terminal UI only |
| pyyaml | 6.0.3 | Yes | `safe_load()` used throughout |

- **No lockfile** for transitive dependencies (Finding 4)
- **No `pip-audit` in CI** (Finding 4)
- Dependabot configured for weekly pip + GitHub Actions updates

### Swift

- **No external Swift packages** — only system frameworks (`Foundation`, `Vision`, `SQLite3`, `AppKit`)
- Zero supply-chain risk in the Swift layer

### CI/CD trust

- GitHub Actions on `ubuntu-latest` and `macos-latest`
- CodeQL security analysis weekly + on PR
- Release signing uses secrets stored in GitHub Actions secrets
- `actions/checkout@v6` used — pinned to major version, not SHA (low risk for this project scale)

---

## Known Risks and Fragile Areas

| Area | Risk |
|------|------|
| `cleanup_tmp_files()` (io.py:55-68) | **P1**: Deletes any `.tmp` in dest, including from other apps |
| `revert_receipt()` path validation (core.py:338-346) | **P1**: No dest-root boundary check before deletion |
| SQLite unlocked reads (database.py:47, 72) | **P2**: Correctness gap under concurrent reads/writes |
| Log file growth (core.py:54) | **P2**: Unbounded; could fill dest drive |
| `_json_active` global state (core.py:36) | **P2**: Non-reentrant; test suite masks it |
| Audit receipt timestamps (core.py:277-284) | **P2**: startedAt = finishedAt always |

---

## Important Files and Components

| File | Role |
|------|------|
| `chronoframe/io.py` | Atomic copy, BLAKE2b hashing, retry policy, tmp cleanup |
| `chronoframe/core.py` | CLI entry point, orchestration, planning, execute, revert, receipt |
| `chronoframe/database.py` | SQLite cache and job queue abstraction |
| `chronoframe/metadata.py` | EXIF, filename pattern, Spotlight date extraction chain |
| `ui/Sources/ChronoframeCore/TransferExecutor.swift` | Swift atomic copy, tmp cleanup, hash verification |
| `ui/Sources/ChronoframeCore/RevertExecutor.swift` | Hash-verified revert logic |
| `ui/Sources/ChronoframeCore/OrganizerDatabase.swift` | Swift SQLite layer for the app |
| `ui/Sources/ChronoframeCore/DryRunPlanner.swift` | Copy plan construction (Swift) |
| `tests/test_chronoframe.py` | 235-method Python test suite |
| `tests/test_parity_fixtures.py` | Python↔Swift planning parity validation |
| `.github/workflows/ci.yml` | CI: Python tests, SwiftPM tests, Xcode build/test, coverage gate |

---

## Open Questions and Unknowns

1. **Does the Swift `cleanupTemporaryFiles()` in TransferExecutor.swift have the same `.tmp` collateral deletion issue as the Python version?** (Medium: same suffix-only filter visible in TransferExecutor.swift:213; needs fix)
2. **What is the current Python test coverage percentage?** (`.coverage` file exists locally but not generated in CI; needed to set a realistic `--fail-under` threshold)
3. **Are Swift `ui/Tests/` unit tests comprehensive for the domain engine, or do they primarily test the app layer?** (Test structure seen; contents not read in depth)
4. **Is the `--fast-dest` flag safe when the destination is being modified by another process between runs?** (WAL mode provides read safety; stale cache would cause re-copies, not data loss — low risk)
5. **Is there a policy for how long audit receipts are retained?** (No cleanup seen; receipts accumulate indefinitely)
