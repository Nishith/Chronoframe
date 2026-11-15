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
supported; the warning itself changes nothing; in the app a per-share lease also
serializes changes to one share on this Mac (see Network Destinations), but two
Macs on one share are still not coordinated.

## Network Destinations

When the destination is a folder on a network share, or Chronoframe cannot tell
what kind of volume it is on, copies follow stricter rules. These rules apply to
every network destination. They are not behind the NAS Library feature flag.

- **Verification can't be turned off.** A copy run with verification off does
  not start. Nothing is copied.
- **Copies are flushed to the server.** Chronoframe asks for a full flush of each
  temporary file and falls back to a plain flush only when the share reports that
  a full flush is unsupported. If the flush fails, that copy fails.
- **A copy never replaces an existing file.** Files are installed with the
  operating system's no-replace rename. If the share can't do that, Chronoframe
  stops the run before placing the file. It never uses the check-then-rename
  fallback that it still uses on local volumes.
- **A changed or disconnected share stops the run.** Before each copy, the
  destination volume must still be the one the run started on.
- **Copy records are kept more conservatively.** `.organize_cache.db` on a network
  folder uses a rollback journal instead of write-ahead logging. If the switch
  can't be confirmed, Chronoframe refuses to open the records and copies
  nothing. It never deletes the database's side files.
- **One mutation per share on this Mac.** Besides the lock inside the destination,
  the app holds a per-share lease in Application Support. It is designed so that
  two folders on the same share, or the same share mounted twice, can't be
  changed at once. This is still one Mac: two Macs on the same share are not
  coordinated. If the lease folder can't be created, the change does not start.
- **The command-line tool refuses.** `ChronoframeCLI` will not write to a network
  destination in this version, and says so before it creates or locks anything.
  Use the app.

Originals stay untouched in every one of these cases.

## NAS Assessment

NAS Library assesses a photo library on a network share to find identical
copies. It is read-only on the library. The workspace is behind a feature flag
and isn't available in release builds yet.

- Library files are opened read-only and symlinks are not followed. Chronoframe
  never creates, renames, or deletes anything in the assessed folder.
- Everything it keeps (scan results, your review choices, the share lease) lives
  on this Mac under Application Support, never in the library. Chronoframe
  refuses to start if that location would be inside the assessed folder.
- A file whose size is unique in the library is never read, because it can't have
  an identical copy.
- Chronoframe never reports a complete assessment when a folder or file couldn't
  be read, a candidate couldn't be compared, or the scan was interrupted. It shows
  "Assessment incomplete", "Assessment stopped", or "Waiting for your NAS" instead
  of a complete result.

Your keeper choice for a group of identical files is saved on this Mac, keyed by
the files' content. It is a note for you, not an approval to delete anything. If
the files change so the chosen keeper is no longer in the group, the choice is
shown as out of date and you choose again.

**NAS Library offers no cleanup.** The NAS Library workspace has no delete, move,
or Trash control. The existing Deduplicate workspace moves files to the macOS
Trash; if you point it at a folder on a mounted network share it refuses the
folder, because Chronoframe has not verified that files moved to the Trash on a
network share can be put back.

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

### Saved Deduplicate reviews

Reviewing a large library can take longer than one sitting, so Chronoframe
remembers your review of a folder. This is review state only: your Keep and
Delete choices, which groups you marked as reviewed, and where you were in the
list. It is not permission to move anything to the Trash.

**Where it lives.** One small file per folder, at
`Application Support/Chronoframe/dedupe_reviews/<key>.json`, where `<key>` is
an encoded form of the folder's path. It is stored on this Mac, outside the
folder you are deduplicating, so Chronoframe writes nothing extra into your
photo folder. The file holds file paths, content fingerprints, and your
choices; it holds no photo data.

**What is saved.** Once you change anything, the save records the current
choice for every file in a group, including suggestions you left as they were,
so the counts on the card and banner include those. It also records which
groups you marked as reviewed and where you were in the list.

**When it is saved.** Shortly after you change a choice or mark a group
reviewed, and again when you pause, cancel, reset, scan again, or quit. A review
you have not touched is not saved, so opening a scan and leaving never creates
a saved review. Cancelling while a scan is still running saves nothing, because
there is no review yet. A normal quit writes any pending changes; a crash or
force-quit can lose the last half second of changes. Saving is best-effort: if
it fails (for example, the disk is full), Chronoframe doesn't interrupt your
review, and the next launch simply finds an older save.

**What comes back.** Saved reviews are applied when you scan the same folder
again; nothing is applied until that scan finishes.

- A Keep or Delete choice returns only when that file is at the same path, its
  content is unchanged since you chose, and it is still part of a duplicate
  group in the new scan.
- A group returns as reviewed only when every file in it is unchanged and had
  its own choice restored.
- Your place in the list returns when that group still exists.
- Choices come back even if you changed Deduplicate settings in between;
  Chronoframe tells you the settings changed because the groups may differ.

**What is dropped.** A file that was edited, replaced, moved, renamed, or
deleted loses its saved choice, and any group it belonged to comes back
unreviewed. A dropped file that still sits in a group gets the scan's own
suggestion; a file that was deleted or is no longer a duplicate simply has
nothing to restore. Chronoframe says so in the banner "Your earlier review was
restored.", which reports how many groups changed and need another look and how
many files had their choices cleared; that count includes files that left their
group. After a restore, the
next save replaces the file with what you see now, so cleared choices are not
kept on disk. A saved file that is missing, damaged, or written by a different
version of Chronoframe is ignored.

**Moving to Trash is unchanged.** Restoring a review never builds a plan, never
approves a commit, and never skips the reviewed-plan confirmation. You still
review, prepare the commit, and confirm, and the commit re-checks every file's
expected content before anything moves to the Trash, exactly as described
above. A restored choice is only a starting point.

**When it is removed.** After a Deduplicate commit finishes for that folder,
its saved review is removed. Reverting a commit does not remove it, and
choosing a different folder leaves each folder's save alone. To discard one
yourself, open the Deduplicate start screen for that folder and choose
**Discard Saved Review** on the "Pick up where you left off" card. The card
appears when no paused review is open in the current session, and it also offers
**Scan and Restore Review**. Discarding deletes only Chronoframe's saved review file; your photos
are not touched.

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

Saved Deduplicate reviews are not stored in the destination. They live under
Application Support (see Saved Deduplicate reviews above), and removing one
only discards your saved choices.

## Reporting A Safety Problem

Use GitHub's private vulnerability reporting flow for any case where originals
change unexpectedly, an unapproved file moves to Trash, a pair is split, a
receipt omits a mutation, recovery changes an ambiguous file, or concurrent
operations reach the same destination. Use synthetic media and remove personal
paths or metadata from logs before sharing them.

See [SECURITY.md](../SECURITY.md) for the reporting policy and
[Troubleshooting](TROUBLESHOOTING.md) for user-facing recovery steps.
