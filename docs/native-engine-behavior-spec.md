# Chronoframe Native Engine Behavior Spec

This document preserves the retired engine contract that the native Swift engine
was ported against. The old backend is no longer shipped, but these rules and
fixtures remain useful compatibility guardrails for existing Chronoframe
artifacts.

This is a compatibility document, not the complete current safety architecture.
The native engine now adds UUID-suffixed status-aware receipts, destination-wide
operation locking, durable mutation intent, startup reconciliation, immutable
dedupe plans, quarantine verification, and sandbox-aware recovery. Those are
documented in [Safety and Recovery](SAFETY_AND_RECOVERY.md),
[Technical Documentation](TECHNICAL.md), and `AGENTS.md`; they may strengthen
this frozen contract but must not weaken it.

## Current Native Safety Extensions

- Every destination-changing operation acquires the non-blocking cross-process
  lock at `.organize_logs/.chronoframe-operation.lock`.
- Organize, deduplicate, and reorganize persist recoverable state before
  mutation where possible and reconcile pending work on relaunch.
- Destination cache hits are hints only: current existence, size, and mtime are
  validated before a cached identity is trusted.
- Deduplicate previews and commits consume one immutable, content-verified
  `DeduplicationPlan`; missing target identities fail closed.
- Dedupe mutation units use same-directory quarantine, `O_NOFOLLOW` descriptor
  verification, pair-unit rollback, and Trash-only commit.
- Filesystem permission denial or a disconnected volume is represented as
  inaccessible recovery state, never silently collapsed into "missing."

## Stable CLI Surface

- Keep the current flags and meanings unchanged:
  - `--source`
  - `--dest`
  - `--profile`
  - `--dry-run`
  - `--rebuild-cache`
  - `--skip-verify`
  - `--workers`
  - `-y` / `--yes`
  - `--json`
  - `--folder-structure`
  - `--revert`
  - `--start-fresh`
- The original engine's `--verify` flag is now implicit: verification is on by
  default and `--skip-verify` opts out. The `--fast-dest` cache-only
  destination shortcut was retired — destination indexing always revalidates
  hashes against the filesystem.
- `--json` remains the machine-readable progress surface exposed by the Swift
  CLI. Additive app-only entrypoints are allowed, but they must not remove or
  reinterpret the current CLI contract.
- `profiles.yaml` remains the shared CLI profile source.

## File Identity

- Identity format is `"{size}_{blake2b_hex}"`.
- The size prefix is part of the stable identity contract, not a display-only
  convenience.
- The byte size is encoded into the digest stream before file contents are
  hashed, so same-size/same-content files are path-independent but still tied
  to the prefixed size field.
- Hashing uses a full-file BLAKE2b digest and currently streams in 8 MiB
  chunks.

## Discovery And Filtering

- Source discovery walks the tree with lexicographically sorted directory names
  and lexicographically sorted filenames.
- Source discovery skips dot-prefixed directories, dot-prefixed files, and
  names in the `SKIP_FILES` list.
- Source discovery only admits files whose extensions are in the current media
  extension allow-list.
- Destination indexing applies the same hidden-file and extension filtering
  rules while revalidating hashes against the filesystem. (The retired
  `--fast-dest` shortcut, which rebuilt the destination hash index and sequence
  counters from cached rows without a filesystem walk, is no longer offered.)

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
- Queue status lifecycle:
  - New planned rows are inserted as `PENDING`
  - Successful executed rows become `COPIED`
  - Copy failures and verification failures become `FAILED`
  - Unattempted rows left behind by an abort remain `PENDING`
- Pending resume work is defined as `CopyJobs.status = 'PENDING'`.

## Artifact Layout

- Persistent run log: `.organize_log.txt`
- Logs directory: `.organize_logs/`
- Dry-run report filename shape: `.organize_logs/dry_run_report_YYYYMMDD_HHMMSS.csv`
- Audit receipt filename shape: `.organize_logs/audit_receipt_YYYYMMDD_HHMMSS.json`
- The macOS app may index and present these artifacts, but must not rename or
  relocate them.

## Planning And Naming Rules

- Files already present in the destination hash index are skipped, not routed
  into `Duplicate/`.
- For hashes seen multiple times in the source during one run, the first
  unseen instance becomes the canonical primary copy and subsequent source
  instances route into the `Duplicate/` tree.
- Primary copy jobs are emitted in sorted `date_str` order. Within each date
  bucket, jobs preserve source discovery order.
- Internal duplicate jobs are appended after all primary jobs. Within the
  duplicate bucket, jobs preserve source discovery order.
- Planned filenames use `YYYY-MM-DD_NNN` with a default sequence width of 3.
- Main-library and duplicate-library sequence counters are independent.
- Sequence counters are reused from existing destination filenames by parsing
  `YYYY-MM-DD_NNN` and `Unknown_NNN` prefixes from the current destination
  library state.
- Unknown-date files use the `Unknown_###` naming branch and route into
  `Unknown_Date` directories.
- Duplicate unknown-date files use the same `Unknown_###` naming branch under
  `Duplicate/Unknown_Date/`.
- If the sequence exceeds the default width, the sequence widens instead of
  truncating, and the run emits a warning.
- Network collisions append `_collision_N` before the extension.
- Duplicate routing and collision handling must preserve current destination
  layout and audit receipt paths.

## Resume Semantics

- Resume detection happens before a fresh source scan.
- If `CopyJobs` contains `PENDING` rows and `--dry-run` is active, the pending
  queue is ignored and the run proceeds as a fresh dry-run plan.
- If `CopyJobs` contains `PENDING` rows and `-y` / `--yes` is active, the
  pending queue is resumed immediately without prompting or replanning.
- If resume is declined interactively, the user may flush the queue and proceed
  to a fresh scan. Flushing the queue never deletes already-copied media.

## Copy Safety Rules

- Copies are atomic: write to `*.tmp`, fsync, then rename.
- Successful copies update the destination cache with the actual written path,
  size, hash, and mtime.
- Audit receipts record only successfully executed transfers and must use the
  actual written destination path, including collision-renamed paths.
- Verification, when enabled, re-hashes the destination and compares against the
  planned identity.
- Verification failures clean up the invalid destination file and leave the job
  failed.
- Verification failures do not populate the destination cache and do not appear
  in the audit receipt transfer list.
- Disk-space failures bubble as `ENOSPC` and are not retried.

## Retry And Failure Policy

- `safe_copy_atomic` retries transient `OSError` failures for up to 5 attempts
  with exponential backoff bounded between 1 second and 10 seconds.
- Retry policy only applies to transient `OSError` values that are not in the
  non-retryable set.
- The current non-retryable `errno` set is:
  - `ENOSPC`
  - `ENOENT`
  - `ENOTDIR`
  - `EISDIR`
  - `EINVAL`

## Failure Thresholds

- Consecutive-failure abort threshold: 5
- Total-failure abort threshold: 20
- Verification failures count toward the same abort thresholds as copy
  failures.
- When either threshold is reached, the current run stops early and remaining
  queued jobs stay `PENDING` for later resume or inspection.
- These limits are behavioral safeguards and must not change without an explicit
  compatibility decision.

## Compatibility Fixtures And Tests

- Planning parity fixtures:
  - `planning_mixed_inputs`
  - `planning_sequence_reuse`
  - `planning_sequence_overflow`
  - `planning_layout_yyyy_mm`
  - `planning_layout_yyyy`
  - `planning_layout_yyyy_mon_event`
  - `planning_layout_flat`
- Execution parity fixtures:
  - `execution_collision_receipt`
  - `execution_missing_source_abort`
  - `execution_verify_cleanup`
- Swift tests remain the frozen reference surface for CLI flags, SQLite schema,
  retry behavior, abort thresholds, and artifact generation.

## Swift Port Exit Criteria

- Swift dry-run planning must keep matching the frozen fixture outputs for
  counts, duplicate classification, destination paths, queue rows, and generated
  report contents.
- Swift execution must preserve the same database schema, artifact locations,
  retry behavior, and cleanup guarantees.
