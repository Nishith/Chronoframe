# System Understanding: Chronoframe

> **Historical architecture snapshot.** This document describes the system as
> reviewed on 2026-05-24. It predates the PR #160 destination lock, immutable
> dedupe scan snapshot/plan, same-directory quarantine, schema-v2 mutation
> journal, sandbox-aware recovery coordinator, and bounded Live Photo metadata
> loader. Use `AGENTS.md`, `docs/TECHNICAL.md`, and
> `docs/SAFETY_AND_RECOVERY.md` for the current architecture.

_Generated: 2026-05-24. Pass type: REFRESH (prior review artifacts exist; code has changed since prior pass). This review supersedes prior documents in this directory._

---

## Overview

Chronoframe is a native macOS SwiftUI photo/video organizer distributed on the Mac App Store and via Developer ID notarization. Its central promise: **source files are never modified, moved, or deleted**. It scans an unsorted source folder, resolves each file's date, copies files into a date-structured destination, and provides audited revert. A parallel CLI (`ChronoframeCLI`) is backed by the same engine.

The user base is individual macOS users managing personal, often irreplaceable photo libraries. The primary risk class is **accidental permanent data loss**, not remote attacker exfiltration.

---

## High-Level Architecture

```
┌───────────────────────────────────────────────────────────────┐
│  ChronoframeApp  (SwiftUI, @MainActor)                        │
│  Views · AppState · Coordinators (Setup/Run/History/Dedupe)   │
└────────────────┬──────────────────────────────────────────────┘
                 │ OrganizerEngine protocol
┌────────────────▼──────────────────────────────────────────────┐
│  ChronoframeAppCore                                           │
│  SwiftOrganizerEngine · Stores · Services · FolderAccess      │
│  RunSessionStore · HistoryStore · DeduplicateSessionStore     │
│  PreviewReviewStore · SetupStore · PreferencesStore           │
└────────────────┬──────────────────────────────────────────────┘
                 │ pure Swift calls, no AppKit
┌────────────────▼──────────────────────────────────────────────┐
│  ChronoframeCore  (stateless domain engine)                   │
│  MediaDiscovery · MediaDateResolver · DryRunPlanner           │
│  CopyPlanBuilder · TransferExecutor · RevertExecutor          │
│  ReorganizeExecutor · DeduplicateScanner                      │
│  DeduplicationPlanner · DeduplicateExecutor                   │
│  OrganizerDatabase (SQLite cache) · BLAKE2bHasher             │
└───────────────────────────────────────────────────────────────┘

ChronoframeCLI / ChronoframeCLIKit  ──►  ChronoframeCore (shared)
```

**Layer boundaries:**
- `ChronoframeCore` — no AppKit; fully testable with SwiftPM unit tests. Pure domain algorithms.
- `ChronoframeAppCore` — `@MainActor` stores, `OrganizerEngine` protocol, `SwiftOrganizerEngine` concrete implementation, security-scoped bookmark management.
- `ChronoframeApp` — SwiftUI views, `AppState` root object, coordinators.

**External dependencies:** Zero (no third-party Swift packages). All cryptographic and image-analysis code is first-party (custom BLAKE2b-512, Vision framework, Photos framework).

---

## Core Flows

### Organize flow (main path)

```
1. User picks source + destination → security-scoped bookmarks stored
2. RunCoordinator.startPreview()
3. SwiftOrganizerEngine.preview():
   a. MediaDiscovery: walk source (no symlinks, no packages, no bundles)
   b. MediaDateResolver: EXIF → filename → mtime fallback
   c. DryRunPlanner: hash source files (O_RDONLY|O_NOFOLLOW), check destination
      → OrganizerDatabase caches hashes (size+mtime invalidation)
   d. CopyPlanBuilder: assign destination paths, handle collisions (_1, _2…)
4. User reviews plan in Preview tab
5. RunCoordinator.startTransfer()
6. SwiftOrganizerEngine.execute():
   a. StreamingAuditReceiptWriter writes PENDING receipt BEFORE first copy
   b. TransferExecutor.executeQueuedJobs():
      - clonefile → copyfile fallback → F_FULLFSYNC → renamex_np(RENAME_EXCL)
      - Optional hash verify: re-hashes destination, deletes on mismatch
        ⚠️ uses try? — throw falsely triggers deletion (finding #1)
      - Spool file updated after each successful copy
   c. Failure threshold: 5 consecutive OR 20 total → abort
   d. Receipt finalized: removeItem(PENDING) then moveItem(tmp→final)
      ⚠️ crash window between the two leaves no receipt (finding #5)
7. RunHistoryIndexer indexes receipt into HistoryStore
```

### Revert flow

```
1. User selects run in History → HistoryCoordinator.revertHistoryEntry()
2. SwiftOrganizerEngine.revert():
   a. RevertExecutor.safeRevert() per destination file:
      - O_NOFOLLOW open
      - BLAKE2b hash of open fd
      - fstatat(AT_SYMLINK_NOFOLLOW) inode check
      - Compare hash against receipt
      - unlinkat() only if match
   b. Boundary check: file must be inside destinationBoundary
      ⚠️ boundary defaults to nil; nil skips containment check (finding #7)
   c. Source is never touched
```

### Dedup flow

```
1. DeduplicateScanner: walk destination, compute BLAKE2b, Vision prints, dHash, quality
   → Cache in OrganizerDatabase.DedupeFeatures
2. DeduplicationPlanner.plan():
   a. Cluster by exact hash → by feature print → by dHash
   b. Select keeper (quality-based auto-suggest for high confidence)
   c. Apply pair-as-unit rules (RAW+JPEG, Live Photo HEIC+MOV)
   d. Keep-wins: if either half has Keep, neither is deleted
3. User reviews clusters
4. DeduplicateExecutor.commit():
   a. Preflight .organize_logs/ → ReceiptPreflightError if unwritable
   b. Write PENDING receipt
   c. NSFileManager.trashItem() only (no hard delete)
   d. Update full receipt JSON after each trash (O(N²) I/O — finding #6)
      ⚠️ crash between trash and receipt update strands file (finding P0-1)
   e. Finalize to COMPLETED/ABORTED
```

### Reorganize flow

```
1. ReorganizeExecutor: walk destination, re-resolve dates, plan moves
2. Write PENDING receipt before loop
3. Move + checkpoint receipt every 25 files
   ⚠️ up to 24 moves unrecorded on crash (finding P0-2)
4. Revert: hash-checked moves back to original location
```

---

## Data Model and Data Lifecycle

### On-disk artifacts (all inside the destination folder)

| Path | Purpose |
|------|---------|
| `.organize_cache.db` | SQLite: FileCache, CopyJobs, DedupeFeatures, ReviewOverrides |
| `.organize_logs/audit_receipt_*.json` | Organize transfer receipt (revert + history) |
| `.organize_logs/dedupe_audit_receipt_*.json` | Deduplicate receipt (revert + history) |
| `.organize_logs/reorganize_audit_receipt_*.json` | Reorganize receipt (revert + history) |
| `.organize_logs/dry_run_report_*.csv` | Dry-run plan export |

**Sensitive data:** Receipts and DB contain full filesystem paths of user photos. No content is exfiltrated — everything stays local. No network calls, no telemetry.

---

## Security Model

### Trust boundaries

| Boundary | What is trusted |
|----------|----------------|
| User ↔ App | Full trust (single-user app) |
| App ↔ Filesystem | Security-scoped bookmarks (App Sandbox). Must call `startAccessingSecurityScopedResource` before any read/write to user-selected folders |
| Source folder | Read-only. `O_RDONLY|O_NOFOLLOW` always |
| Drop manifest | **Untrusted** — JSON file in source that lists paths to copy. ⚠️ No containment check (finding #4) |
| `.organize_cache.db` | Cache only; hash+size+mtime validated before use |
| Receipts | Trusted at revert; hash-guarded before deletion |

### Safety-critical invariants and enforcement points

1. **Source read-only** — `O_RDONLY|O_NOFOLLOW` in `FileIdentityHasher.hashDigest()`. `TransferExecutor` never writes to `sourcePath`.
2. **Atomic copy, no overwrites** — `renamex_np(RENAME_EXCL)` in `TransferExecutor.performCopy()`.
3. **Copy verification** — `FileIdentityHasher.hashIdentity()` post-copy. ⚠️ `try?` — throws falsely trigger deletion (finding #1).
4. **Receipt before mutation** — `StreamingAuditReceiptWriter` writes PENDING before first copy. ⚠️ Dedupe executor does NOT use streaming — full re-encode after each trash (finding P0-1).
5. **Revert hash-check** — `RevertExecutor.safeRevert()` — O_NOFOLLOW + fd hash + inode check + `unlinkat`. Strongest component in the codebase.
6. **Trash-only delete** — `DeduplicateExecutor.commit()` uses only `NSFileManager.trashItem()`.
7. **Pair-as-unit / Keep-wins** — `DeduplicationPlanner.plan()` enforces before emitting plan.
8. **No symlink following** — checked in `MediaDiscovery`, `DeduplicateScanner`, and `FileIdentityHasher` (`O_NOFOLLOW`).

---

## Reliability and Operational Model

### Failure modes

| Failure | Current behavior | Gap |
|---------|-----------------|-----|
| App crash mid-transfer | PENDING receipt on disk; `recoverInterruptedRuns` recovers on relaunch | Robust |
| App crash mid-dedupe | Receipt updated in-place; crash between trash and receipt write strands file in Trash with no revert path | **P0** |
| App crash mid-reorganize | Checkpoint every 25 moves; up to 24 moves not in receipt | **P0** |
| Receipt finalization crash | `removeItem` + `moveItem` window: neither receipt exists | **P1** |
| Hash I/O error during verify | `try?` → falsely deletes the just-written copy | **P1** |
| Reorganize triggered during active transfer | `resetSessionState` silently aborts the transfer | **P1** |
| PreviewReview override saved after scope close | `EPERM` in sandbox, override silently discarded | **P1** |
| IssueCounter under parallel transfer | Data race; failure threshold may fire incorrectly | **P1** |

### Failure thresholds

5 consecutive OR 20 total failures abort a transfer run. Implemented in `BatchTransferState` in `TransferExecutor`.

### Observability

- `RunLogStore` provides per-run structured logs surfaced in the UI.
- No external telemetry, crash reporting, or metrics.
- The audit receipt is the primary operational record.

---

## Performance and Capacity Posture

- **Dedup receipt I/O:** O(N²) writes — full JSON re-encode for every item in N-item run. 10,000 files ≈ ~1 GB of receipt writes. Serializes the trash loop on slow volumes.
- **BLAKE2b hashing:** Pure-Swift; not benchmarked against `CommonCrypto` baseline.
- **Vision feature prints:** CPU-bound; batched with configurable concurrency.
- **NSCache countLimit=256** in `DedupeThumbnailLoader` — reasonable steady-state ceiling.
- SQLite is sufficient for the data volume. No horizontal scaling required.

---

## Testing and Quality Posture

- **Unit tests (authoritative):** SwiftPM tests; 95%+ meaningful coverage on domain code.
- **Fault injection:** `DeduplicateExecutorFaultInjectionTests` — comprehensive for dedupe. No equivalent for `TransferExecutor` receipt-directory failure.
- **AGENTS-INVARIANT tags:** Safety invariant tests are tagged. ⚠️ `script/check_agents_invariants_have_tests.sh` is **not called in any CI workflow**.
- **CodeQL:** Runs but `upload: never` — findings are silently discarded.

### Critical gaps
- No test: `TransferExecutor` receipt directory unwritable mid-run.
- No test: BLAKE2b RFC 7693 reference vectors.
- No test: Drop manifest entries outside source root.
- No test: `RevertExecutor` with `destinationBoundary: nil`.
- No CI gate: invariant check script never called.
- No CI gate: CodeQL findings never persist.

---

## Dependency and Supply-Chain Posture

**Zero external Swift package dependencies.** Exceptionally clean supply-chain posture. All GitHub Actions pinned to full 40-character SHA hashes. Dependabot configured. The only "supply chain" risk is the hand-rolled BLAKE2b implementation — absence of reference-vector tests means a silent regression would not be caught.

---

## Known Risks and Fragile Areas

1. **Dedupe receipt atomicity** — single most fragile area; crash during large dedupe commits can strand files in Trash.
2. **Reorganize checkpoint gap** — 24-move window where completed moves are unrecorded.
3. **TransferExecutor `try?` verify** — silently deletes valid copies on transient I/O errors.
4. **Receipt finalization atomicity** — `removeItem` + `moveItem` crash window.
5. **IssueCounter data race** — unsynchronized under parallel transfer.
6. **Invariant check not in CI** — safety regression can merge undetected.
7. **CodeQL results discarded** — vulnerability detection is theater.

---

## Breadth Coverage Table

| Directory | Status | Notes |
|-----------|--------|-------|
| `ui/Sources/ChronoframeCore/` | REVIEWED | All 32 files read |
| `ui/Sources/ChronoframeAppCore/` | REVIEWED | All stores, services, engine read |
| `ui/Sources/ChronoframeApp/` | REVIEWED | App entry, coordinators, key views read |
| `ui/Sources/ChronoframeCLIKit/` | REVIEWED | CLI.swift and runners read |
| `ui/Sources/ChronoframePackaging/` | REVIEWED | BundleValidator read |
| `ui/Sources/ChronoframeIconTool/` | SKIMMED | Procedural icon renderer; no security surface |
| `ui/Tests/` | REVIEWED | All test targets read |
| `.github/workflows/` | REVIEWED | All 4 workflow files read |
| `script/` | REVIEWED | All 3 scripts read |
| `ui/Packaging/` | REVIEWED | Entitlements, export options, scripts read |
| `site/` | SKIMMED | Static marketing site; no app code |
| `docs/` | SKIMMED | Release checklist, privacy policy |

---

## Open Questions

1. Does `DeduplicateConfiguration` carry a `hardDelete` field? If yes, stale `UserDefaults` could bypass the `PreferencesStore` guard.
2. Is `CHRONOFRAME_PROFILES_PATH` intentionally accepted in Developer ID builds, or is it development-only?
3. What is the exact GitHub account handle? `CODEOWNERS` uses `@Nishith` — if the handle differs, required reviews are silently not requested.
4. Is the `production` GitHub environment configured with required reviewers? The release pipeline depends on this gate; if not configured, any maintainer can cut a release from any commit.
