# Chronoframe Native Engine Behavior Spec

This document freezes the Python engine contract that the future native Swift
engine must match before app cutover. The Python backend remains the behavioral
reference until parity is proven against these rules and the existing test
fixtures.

## Stable CLI Surface

- Keep the current flags and meanings unchanged:
  - `--source`
  - `--dest`
  - `--profile`
  - `--dry-run`
  - `--rebuild-cache`
  - `--verify`
  - `--workers`
  - `--yes`
  - `--json`
  - `--fast-dest`
- `profiles.yaml` remains the shared CLI profile source until a compatibility
  layer replaces it.

## File Identity

- Identity format is `"{size}_{blake2b_hex}"`.
- The size prefix is part of the stable identity contract, not a display-only
  convenience.
- Hashing uses a full-file BLAKE2b digest and currently streams in 8 MiB
  chunks.

## Queue And Cache Database

- Database filename: `.organize_cache.db`
- SQLite pragmas:
  - `journal_mode = WAL`
  - `synchronous = NORMAL`
- Stable tables:
  - `FileCache(id, path, hash, size, mtime)` with primary key `(id, path)`
  - `CopyJobs(src_path, dst_path, hash, status)` with primary key `src_path`
- `id = 1` is the source cache namespace and `id = 2` is the destination cache
  namespace.
- Pending resume work is defined as `CopyJobs.status = 'PENDING'`.

## Artifact Layout

- Persistent run log: `.organize_log.txt`
- Logs directory: `.organize_logs/`
- Dry-run report filename shape: `.organize_logs/dry_run_report_YYYYMMDD_HHMMSS.csv`
- Audit receipt filename shape: `.organize_logs/audit_receipt_YYYYMMDD_HHMMSS.json`
- The macOS app may index and present these artifacts, but must not rename or
  relocate them.

## Planning And Naming Rules

- Planned filenames use `YYYY-MM-DD_NNN` with a default sequence width of 3.
- Unknown-date files use the `Unknown_###` naming branch and route into
  `Unknown_Date` directories.
- Network collisions append `_collision_N` before the extension.
- Duplicate routing and collision handling must preserve current destination
  layout and audit receipt paths.

## Copy Safety Rules

- Copies are atomic: write to `*.tmp`, fsync, then rename.
- Verification, when enabled, re-hashes the destination and compares against the
  planned identity.
- Verification failures clean up the invalid destination file and leave the job
  failed.
- Disk-space failures bubble as `ENOSPC` and are not retried.
- Retry policy only applies to transient `OSError` values that are not in the
  non-retryable set.

## Failure Thresholds

- Consecutive-failure abort threshold: 5
- Total-failure abort threshold: 20
- These limits are behavioral safeguards and must not change without an explicit
  compatibility decision.

## Native Port Exit Criteria

- Swift dry-run planning must match Python outputs for counts, duplicate
  classification, destination paths, queue rows, and generated report contents.
- Swift execution must preserve the same database schema, artifact locations,
  retry behavior, and cleanup guarantees before it becomes the default app
  engine.
