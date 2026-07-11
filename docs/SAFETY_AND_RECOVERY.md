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
| Guardian scrub | Nothing (read-only integrity check) | No library lock, hashes against a trusted manifest kept outside the library, never advances trust automatically |
| Guardian mirror | New/updated files on the mirror volume | Copies only from a currently-verified primary, verified copy + atomic no-overwrite rename, divergent mirror quarantined, deletions never propagated, library never written |
| Guardian restore | A corrupt/missing library file is healed from the mirror | Mirror re-verified against the trusted digest at commit time, review-gated, same-directory quarantine before install, journaled crash recovery |

## One Destination-Changing Operation At A Time

Chronoframe keeps `.organize_logs/.chronoframe-operation.lock` open for the
entire destination-changing operation, including prompts, execution, receipt
finalization, and recovery. The lock is process-wide, so it also protects against
a CLI run, App Intent, or second app process targeting the same destination.

If another operation owns the destination, Chronoframe stops immediately and
asks you to wait. It does not queue a second mutation or try to infer that a
stale-looking diagnostic file means the destination is free; the operating
system lock is authoritative.

This lock reliably enforces mutual exclusion on **one machine**. It is not a
substitute for keeping a shared/NAS destination single-host: the underlying
file lock is unreliable over SMB/AFP, so two Macs pointed at the same network
volume could both proceed. Chronoframe detects a network destination and shows
a one-time warning per destination so you know this configuration isn't
supported; it does not change locking behavior.

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

## Library Guardian: Scrub, Mirror, Restore

Library Guardian protects an already-organized library from silent bit rot. It
is built on one load-bearing rule: Guardian never creates or advances trust
automatically from an unexplained filesystem change, never replaces either copy
unless the other copy verifies against an already-trusted identity, and never
propagates a deletion without retaining a recoverable copy.

**Where Guardian keeps its state.** The trusted-digest manifest, receipts,
journals, and schedule live in Application Support, keyed by a stable library
identity — never inside the protected library. This is what lets a scrub and a
mirror-read treat the library's own bytes as strictly read-only.

**Trust never advances on its own.** Each file's trust state moves only through
explicit intent:

- `unprotected` — first seen, no provenance. Corruption that predates Guardian
  is never blessed as good.
- `trusted` — reached only by explicit user acceptance or by matching a digest
  Chronoframe itself wrote and verified in an organize/import transfer.
- `changedPendingReview` — a trusted file whose bytes changed (whether or not
  the modification time moved). A legitimate edit, metadata-changing bit rot, and
  a malicious edit are indistinguishable without your intent or a second trusted
  copy, so Guardian never silently re-baselines it. You decide: accept the new
  bytes as trusted, or restore the good copy from the mirror.
- `retired` — a deletion you explicitly acknowledged.

A scrub re-hashes every file and reports `verified`, `corrupt` (bytes differ
while size/mtime match — the classic silent rot), `modified`, `missing`, `new`,
`dataless` (iCloud-evicted, skipped, not corrupt), or `unreadable`. A scan that
couldn't fully read a subtree is conservative: it reports an incomplete check
rather than false "missing" or "corrupt" results, and changes no trust.

**The mirror is a real backup, so it never mirrors damage.** A mirror pass
copies a file only when the primary currently verifies against its trusted
digest; the primary is re-hashed immediately before the copy. Anything not
currently verified is left alone and the existing mirror copy is preserved. A
mirror copy that has diverged is moved into a mirror-side quarantine **before**
its replacement is written, so a recoverable copy is never erased. Deletions are
never propagated — a mirror file whose primary is now missing is retained until
you acknowledge it. The library volume is only ever read.

**Restore heals the library, and only from bytes it can prove are good.** A
corrupt or missing primary is restore-eligible only if the mirror copy still
hashes to the trusted digest; corrupt-on-both-sides is reported and never
"restored" from bad bytes. Restore is the one Guardian surface that writes the
library, so it is the most defensive:

1. It opens the mirror without following symlinks and hashes the **same file
   descriptor** it will copy from, so a symlink swap or content change between
   planning and commit cannot slip through.
2. It refuses a corrupt primary that changed again since planning, and refuses a
   missing primary that has reappeared (it will not overwrite a file that came
   back).
3. It moves the corrupt original into a **same-directory quarantine before**
   installing the replacement — never Trash-first, so rollback never depends on
   Trash naming or volume availability.
4. It installs via a verified copy and an atomic, no-overwrite rename.
5. Every transition is journaled (`intent → original quarantined → replacement
   installed → finalized`). If a restore is interrupted after the original is
   quarantined but before the replacement is installed, recovery rolls the
   original back into place, so the library is never left missing.

Restore only ever touches the files you selected for review, and both the
library and mirror are locked for the whole run.

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
