# Safety And Recovery

Chronoframe is designed for media that cannot be replaced. This document is the
plain-language and technical reference for what the app protects, what it
records, and what happens after an interruption.

## The Short Version

- Organize treats the selected source folder as read-only.
- Every organize plan is previewed before copying starts.
- Copies are written to temporary files, flushed, atomically renamed, and
  re-hashed by default.
- Existing destination files are never overwritten.
- Deduplicate uses one immutable, content-verified plan for both the preview and
  the executor.
- Deduplicate moves approved files to the macOS Trash; production code has no
  hard-delete path.
- Organize, Deduplicate, Reorganize, and Revert serialize access to a destination
  so two Chronoframe processes cannot mutate the same library at once.
- Durable receipts and mutation state let Chronoframe reconcile interrupted work
  on the next launch. Ambiguous cases fail closed and remain visible in History.

Chronoframe is not a replacement for a backup. Keep an independent backup of an
important library, especially before a large first run or filesystem migration.

## Safety By Operation

| Operation | What can change | Main safeguards |
| :--- | :--- | :--- |
| Organize | New copies in the destination | Read-only source, preview, no overwrite, atomic copy, verification, durable queue and receipt |
| Deduplicate | Approved destination files move to Trash | Immutable plan, expected content identity, pair-unit rules, quarantine and descriptor verification, durable journal, Trash only |
| Reorganize | Existing destination files move to a new layout | Previewed move plan, content recheck, collision protection, pending receipt, per-item mutation state |
| Revert | Files created or moved by a recorded run | Receipt scope, current-content verification, path containment, no overwrite |

## One Destination-Changing Operation At A Time

Chronoframe keeps `.organize_logs/.chronoframe-operation.lock` open for the
entire destination-changing operation, including prompts, execution, receipt
finalization, and recovery. The lock is process-wide, so it also protects against
a CLI run, App Intent, or second app process targeting the same destination.

If another operation owns the destination, Chronoframe stops immediately and
asks you to wait. It does not queue a second mutation or try to infer that a
stale-looking diagnostic file means the destination is free; the operating
system lock is authoritative.

## Content-Verified Deduplicate Plans

A deduplicate scan produces an immutable snapshot containing the expected
identity of every possible mutation target. The planner is the single source of
truth for the commit preview, item count, reclaimable bytes, receipt, and
executor.

Before Trash, Chronoframe:

1. Rejects any target whose expected identity is missing.
2. Applies Keep-wins pair and sidecar rules.
3. Writes a `PENDING` receipt and per-item recovery intent.
4. Moves each mutation unit to a unique same-directory quarantine name.
5. Opens the quarantined file without following symlinks and verifies its
   content identity.
6. Moves the verified file to the macOS Trash and records the resulting Trash
   location.

RAW+JPEG pairs, Live Photo pairs, and owned metadata sidecars are validated as a
unit. If one member changes or a journal update fails, Chronoframe restores the
unit where it safely can and stops before touching more files.

## What Happens After An Interruption

Chronoframe records intent before filesystem mutations where possible. On the
next launch—and again when History refreshes—it acquires the destination lock
and reconciles pending organize, deduplicate, and reorganize state.

Recovery distinguishes three situations:

- **Interrupted · Needs Drive** — a required external volume is unavailable or
  inaccessible. Reconnect and unlock the drive, then reopen Chronoframe or
  refresh History.
- **Trash Location Unverified** — macOS Trash cannot currently be inspected well
  enough to prove the recorded item location. Chronoframe preserves the journal
  and does not guess.
- **Manual Recovery Needed** — the filesystem no longer has one unambiguous safe
  interpretation. Chronoframe leaves the remaining evidence in place for manual
  inspection.

A permission denial is never treated as proof that a file is missing. Recovery
is idempotent: retrying it after reconnecting a drive or restoring permission
does not repeat a completed mutation.

## On-Disk Evidence

Chronoframe stores support artifacts inside the selected destination:

- `.organize_cache.db` — validated file identities, copy queue and mutation
  state, review overrides, and incremental photo/video dedupe features.
- `.organize_logs/audit_receipt_*.json` — organize receipts.
- `.organize_logs/dedupe_audit_receipt_*.json` — deduplicate receipts.
- `.organize_logs/dedupe_audit_receipt_*.json.spool` — append-only deduplicate
  recovery journal retained only when needed.
- `.organize_logs/reorganize_audit_receipt_*.json` — reorganize receipts.
- `.organize_logs/.chronoframe-operation.lock` — operation-lock diagnostics;
  the live file descriptor lock, not the JSON text, determines ownership.

Do not remove these artifacts while an operation is running or while History
shows interrupted work. Removing them can discard resume, recovery, history, or
revert information. Completed-run artifacts may be removed if you intentionally
accept losing those capabilities; Chronoframe will rebuild performance caches as
needed.

## Reporting A Safety Problem

Use GitHub's private vulnerability reporting flow for any case where originals
change unexpectedly, an unapproved file moves to Trash, a pair is split, a
receipt omits a mutation, recovery changes an ambiguous file, or concurrent
operations reach the same destination. Use synthetic media and remove personal
paths or metadata from logs before sharing them.

See [SECURITY.md](../SECURITY.md) for the reporting policy and
[Troubleshooting](TROUBLESHOOTING.md) for user-facing recovery steps.
