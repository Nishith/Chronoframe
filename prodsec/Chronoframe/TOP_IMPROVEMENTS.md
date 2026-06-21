# Chronoframe — Top 10 Highest Impact Improvements

> **Historical prioritized findings.** This ranking records the 2026-05-24
> review and is intentionally not rewritten as findings are fixed. The
> remediation series through PR #160 implemented the code and test work,
> including CI guards, durable receipts/recovery, destination serialization,
> dedupe quarantine, and stale-plan verification. See
> `docs/production-readiness-certification.md` for evidence and
> `docs/remaining-work-plan.md` for the actual open gates.

_Generated: 2026-05-24. Pass type: REFRESH. Supersedes prior documents in this directory._

---

## Scoring Table

Scale: 1–5, higher = worse. Priority subtotal = SEV × LIK × BLAST × LEV. Tie-break = EFF_INV (effort inverse, 5=XS, 1=XL) × REV (reversibility, 5=trivially reversible) × CONF (confidence, 5=high).

| # | Title | SEV | LIK | BLAST | LEV | Score | EFF_INV | REV | CONF | Tie |
|---|-------|-----|-----|-------|-----|-------|---------|-----|------|-----|
| 1 | Invariant check script not wired to CI | 4 | 5 | 4 | 5 | **400** | 5 | 5 | 5 | 125 |
| 2 | DeduplicateExecutor: crash strands files in Trash | 5 | 3 | 4 | 4 | **240** | 2 | 3 | 5 | 30 |
| 3 | CodeQL SARIF upload disabled | 3 | 5 | 3 | 5 | **225** | 5 | 5 | 5 | 125 |
| 4 | Receipt finalization: remove-then-rename atomicity gap | 4 | 2 | 5 | 4 | **160** | 4 | 5 | 5 | 100 |
| 5 | ReorganizeExecutor checkpoint gap (up to 24 moves) | 4 | 3 | 3 | 4 | **144** | 3 | 4 | 5 | 60 |
| 6 | TransferExecutor: `try?` in verify deletes valid copies | 4 | 3 | 4 | 3 | **144** | 3 | 3 | 5 | 45 |
| 7 | IssueCounter data race under parallel transfer | 3 | 4 | 3 | 4 | **144** | 5 | 5 | 5 | 125 |
| 8 | Reorganize/Revert silently aborts active transfer | 3 | 3 | 3 | 4 | **108** | 4 | 5 | 5 | 100 |
| 9 | PreviewReviewStore: override lost after scope close | 3 | 4 | 3 | 3 | **108** | 3 | 4 | 5 | 60 |
| 10 | Missing TransferExecutor receipt fault-injection test | 4 | 4 | 3 | 2 | **96** | 4 | 5 | 5 | 100 |

---

## 1. Invariant Check Script Not Wired to CI

- **Category:** Testing / Release Safety
- **Priority:** P1 — The safety net for all executor/revert/deduplication invariants exists but is not connected. Every merged PR that touches safety-critical code bypasses the check automatically.
- **Effort:** XS
- **Confidence:** High

**Problem:** `script/check_agents_invariants_have_tests.sh` verifies that every bullet in `AGENTS.md ## Safety Invariants` has at least one test tagged `// AGENTS-INVARIANT: N`. `CLAUDE.md` and `AGENTS.md` both describe this as a required gate. No job in `.github/workflows/ci.yml` calls it.

**Why it matters:** A developer who weakens a safety invariant — by accident or by design — can pass all CI jobs and merge. The first indication of a regression would be a user data-loss report, not a failed CI build.

**Evidence:** `.github/workflows/ci.yml` (all jobs); `script/check_agents_invariants_have_tests.sh` (exists, is correct, is not referenced from any workflow).

**Root cause:** The script was written as a local development tool and was never added to the workflow when it was created.

**Risks if unchanged:** Any future refactor of `TransferExecutor`, `RevertExecutor`, or `DeduplicateExecutor` can silently drop invariant coverage without CI catching it.

**Recommended change:** Add a new `invariants-check` job to `ci.yml`:

```yaml
invariants-check:
  name: AGENTS-INVARIANT tag check
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd
    - run: script/check_agents_invariants_have_tests.sh
```

**Structural guard:** The job itself is the guard — once wired, any PR that drops a tagged test fails CI.

**Expected impact:** Invariant regressions caught at PR time. Zero false positives (the script only fails if a bullet in AGENTS.md has no tagged test).

**Tradeoffs:** None. This is a Bash script that runs in under 10 seconds.

**Dependencies:** None.

**Suggested owner:** Any contributor; 15-minute change.

---

## 2. DeduplicateExecutor: Crash Between Trash and Receipt Update Strands Files

- **Category:** Data Integrity / Reliability
- **Priority:** P0 — A crash during any dedupe commit leaves trashed files with no receipt entry, making them unrecoverable via Run History → Revert.
- **Effort:** M
- **Confidence:** High

**Problem:** `DeduplicateExecutor.commit()` (DeduplicateExecutor.swift ~lines 147–175) calls `NSFileManager.trashItem()` and then calls `Self.writeReceipt(...)` which atomically replaces the entire receipt file. If the process is killed (SIGKILL, power loss, crash) between `trashItem` and the receipt write, the item is in Trash but the receipt records `trashURL: nil` (or the item is entirely absent from the receipt if it was the first item). `RevertExecutor` for dedupe then reports "Receipt is missing the Trash URL" and cannot restore the file. The user has to manually locate it in Trash.

Additionally, writing the full receipt after every trash causes O(N²) total bytes written — 1 GB+ for 10,000-item runs on slow volumes.

**Why it matters:** Users trust the "Revert" button to undo dedupe. A crash during a large run — extremely plausible on a slow NAS or spinning disk that stalls — silently makes Revert incomplete. The file is in Trash (not lost forever) but the user has no indication which items need manual recovery.

**Evidence:**
- `ui/Sources/ChronoframeCore/DeduplicateExecutor.swift` lines 147–175 (per-item receipt rewrite loop)
- `ui/Sources/ChronoframeCore/TransferExecutor.swift` lines 1074–1162 (`StreamingAuditReceiptWriter` — the correct pattern, not used by dedupe)
- `AGENTS.md` Safety Invariants: "receipts are written before mutation where possible"

**Root cause:** The dedupe executor was written independently of the organize executor and did not adopt the streaming-write / spool pattern that `TransferExecutor` uses. Each is a correct stand-alone design, but they have divergent crash-recovery postures.

**Attack/Failure Scenario:**
1. User initiates a 5,000-item dedupe commit.
2. After 1,247 successful trashes, the NAS stalls and the macOS process watchdog kills the app.
3. 1,247 files are in Trash. The on-disk receipt was last written after item 1,246 (the crash window is between `trashItem` on item 1,247 and the receipt write).
4. Item 1,247's receipt entry has `trashURL: nil`.
5. User relaunches app, opens Run History, clicks Revert.
6. `DeduplicateExecutor.revert()` skips item 1,247 with `.itemFailed("Receipt is missing the Trash URL")`.
7. Item 1,247 stays in Trash with no automated recovery path.

**Risks if unchanged:** Proportional to run size and volume reliability. A 50,000-item dedupe on an SMB share is a near-certain eventual failure.

**Recommended change:** Adopt a spool-based approach:
1. Write a PENDING receipt with all items as `trashURL: nil` before the loop (like `StreamingAuditReceiptWriter` writes a PENDING header).
2. After each successful `trashItem`, atomically append a sidecar spool line `{originalPath}\t{trashURL}\n` — one `write(2)` syscall, not a full JSON re-encode.
3. After the loop, read the spool, assemble the full receipt JSON once, atomic-rename to final path.
4. On app relaunch, add a `recoverInterruptedDedupeRuns` path (mirroring `recoverInterruptedRuns` for organize) that finds PENDING dedupe receipts with associated spool files and consolidates them.

**Structural guard:** Add a `// AGENTS-INVARIANT: 13` tagged test that kills the executor after the third trash (via fault injection mock `FileOperations`) and verifies that the receipt on disk has correct `trashURL` entries for all successfully trashed items (no nil trashURLs for completed trashes).

**Expected impact:** Eliminates data-recovery gaps for all dedupe crashes. Also eliminates O(N²) receipt I/O as a side effect.

**Tradeoffs:** Moderate implementation complexity (~2 engineer-days). The spool format is simple but requires coordinated changes in executor + engine + app relaunch path.

**Dependencies:** None; self-contained to `DeduplicateExecutor.swift` and `SwiftOrganizerEngine.swift`.

**Suggested owner:** Backend (Swift domain engine).

---

## 3. CodeQL SARIF Upload Disabled — Security Findings Silently Discarded

- **Category:** Security / Release Safety
- **Priority:** P1 — CodeQL runs on every push to main but `upload: never` in `.github/workflows/codeql.yml` means findings are never persisted, never visible in the Security tab, and can never block a PR. Vulnerability detection is effectively theater.
- **Effort:** XS
- **Confidence:** High

**Problem:** `.github/workflows/codeql.yml` line 88: `upload: never`. CodeQL analyzes Swift source via a full Xcode build, produces a SARIF result file, then discards it. No finding from CodeQL has ever been surfaced to a maintainer through the GitHub Security tab. The gate only catches "CodeQL failed to build" — not actual vulnerabilities.

**Why it matters:** CodeQL for Swift can detect taint-flow issues (unsanitized input reaching file operations), path traversal, injection, and unsafe API usage. These are exactly the relevant vulnerability classes for a file-organizer app. Discarding results means this analysis provides no security value.

**Evidence:** `.github/workflows/codeql.yml` line 88 (comment: "Code scanning is not currently enabled for this repository, so SARIF uploads fail after analysis succeeds").

**Root cause:** Code scanning was disabled at the repository settings level at some point. The workaround (`upload: never`) was added to prevent the workflow from failing rather than fixing the underlying setting.

**Risks if unchanged:** Any taint-flow or path traversal vulnerability that CodeQL could detect will ship undetected indefinitely.

**Recommended change:**
1. In GitHub repo settings: Settings → Code security → Code scanning → Enable.
2. Remove `upload: never` from `codeql.yml` (or change to `upload: true` explicitly).
3. Configure the Code scanning alert threshold to block PRs on high-severity findings.

**Structural guard:** Once enabled, any new high/critical CodeQL finding blocks merge. The workflow itself is the guard.

**Expected impact:** Continuous automated security scanning on all PRs. Zero engineering overhead once configured.

**Tradeoffs:** One-time repository settings change. May surface existing findings that require triage.

**Dependencies:** Repository admin access.

**Suggested owner:** Any maintainer with admin access; 5-minute change.

---

## 4. Receipt Finalization: Remove-Then-Rename Atomicity Gap

- **Category:** Data Integrity / Reliability
- **Priority:** P1 — A crash in the narrow window between `removeItem(PENDING)` and `moveItem(tmp→final)` leaves a completed run with no receipt and no revert path.
- **Effort:** S
- **Confidence:** High

**Problem:** `StreamingAuditReceiptWriter.finish()` (TransferExecutor.swift lines 1157–1162) removes the existing receipt file, then moves the temporary receipt to the final path. If the process is killed between these two operations, there is no receipt on disk. `recoverInterruptedRuns` scans for PENDING receipts — but the PENDING receipt was just deleted. The run's files are all on disk. The run is silently absent from Run History. Revert is impossible.

**Evidence:** `ui/Sources/ChronoframeCore/TransferExecutor.swift` lines 1155–1162.

**Root cause:** `FileManager.moveItem` does not support overwrite, requiring a prior `removeItem`. The correct fix is `rename(2)` which is atomic on the same filesystem (guaranteed here since both paths are inside `.organize_logs`).

**Recommended change:**

```swift
// Replace the removeItem + moveItem two-step with a single atomic rename:
let result = temporaryReceiptURL.withUnsafeFileSystemRepresentation { src in
    finalReceiptURL.withUnsafeFileSystemRepresentation { dst in
        src.flatMap { s in dst.map { d in Darwin.rename(s, d) } } ?? -1
    }
}
guard result == 0 else {
    throw AuditReceiptError.finalizationFailed(errno: errno)
}
```

**Structural guard:** Add a fault-injection test that kills the writer between receipt operations and verifies that either a PENDING receipt or a COMPLETED receipt exists on disk afterward (never neither).

**Expected impact:** Eliminates the finalization crash window. `rename(2)` is an O(1) atomic VFS operation on APFS.

**Tradeoffs:** Uses a Darwin syscall directly instead of `FileManager`. This is appropriate and well-precedented in the codebase (which already uses `clonefile`, `renamex_np`, `unlinkat`, `O_NOFOLLOW` directly).

**Dependencies:** None.

**Suggested owner:** Backend.

---

## 5. ReorganizeExecutor Checkpoint Gap: Up to 24 Moves Unrecorded on Crash

- **Category:** Data Integrity / Reliability
- **Priority:** P1 — A crash during reorganize leaves up to 24 completed file moves absent from the receipt, making those moves irreversible via Run History → Revert.
- **Effort:** S
- **Confidence:** High

**Problem:** `ReorganizeExecutor` writes a PENDING receipt before the loop (correct), then updates the receipt every 25 items (`receiptCheckpointInterval = 25`, ReorganizeExecutor.swift line ~321). A crash after move 13 and before the checkpoint at move 25 leaves those 13 moves unrecorded. `ReorganizeExecutor.revert` filters on `item.completed == true`, so those 13 items are not reverted. The files are intact at their new locations, but the user cannot use Revert to move them back.

**Evidence:** `ui/Sources/ChronoframeCore/ReorganizeExecutor.swift` lines 317–367; comment at line 321–326 explicitly acknowledges this gap.

**Root cause:** A deliberate performance/correctness tradeoff that chose performance (batched writes) over correctness (per-move writes). The comment acknowledges the gap but does not tag it as a known invariant violation.

**Recommended change:** Lower `receiptCheckpointInterval` to 1. Reorganize moves are `rename(2)` on APFS — they are extremely fast. The checkpoint write dominates the wall-clock time only on slow NAS volumes, and on those volumes a crash is most likely. Alternatively, use the spool-append pattern (as recommended for dedupe) to make receipt writes O(1) per move instead of O(N).

**Structural guard:** Add a `// AGENTS-INVARIANT: 9` test that kills the reorganize executor after move 3 (via fault injection) and verifies that moves 1–3 are present in the on-disk receipt with `completed: true`.

**Expected impact:** All completed reorganize moves are always recoverable via Revert, regardless of when a crash occurs.

**Tradeoffs:** Small I/O increase (1 write per move vs. 1 write per 25 moves). On a 10,000-file reorganize: ~10,000 small JSON writes vs. ~400 batched writes. On a local APFS volume the difference is negligible. On a slow volume the per-write approach is slower but more correct.

**Dependencies:** None.

**Suggested owner:** Backend.

---

## 6. TransferExecutor: `try?` in Verify Path Silently Deletes Valid Copies

- **Category:** Data Integrity / Reliability
- **Priority:** P1 — A transient I/O error during hash verification causes the just-written copy to be deleted, even if the copy is valid.
- **Effort:** XS
- **Confidence:** High

**Problem:** `TransferExecutor.performCopy()` (TransferExecutor.swift line 610) and `prepareCopy()` (line 657) use:

```swift
let verifiedIdentity = try? fileHasher.hashIdentity(at: destinationURL)
if verifiedIdentity?.rawValue != job.hash {
    removeUnverifiedCopyIfNeeded(...)
    return .failed(...)
}
```

`try?` swallows any thrown error and produces `nil`. `nil != job.hash` is unconditionally `true`, so any I/O error (FD limit exhaustion, brief volume unavailability, AV scanner exclusive lock) enters the failure path and deletes the just-written destination file. The source is safe (read-only invariant holds), but the user loses the copy and must re-run.

**Evidence:** `ui/Sources/ChronoframeCore/TransferExecutor.swift` lines 610, 657.

**Root cause:** `try?` was used defensively to handle the "file doesn't exist" case, but it conflates "hash error" (don't delete — hash is unknown) with "hash mismatch" (delete — copy is confirmed bad).

**Recommended change:**

```swift
do {
    let verifiedIdentity = try fileHasher.hashIdentity(at: URL(fileURLWithPath: actualDestinationPath))
    if verifiedIdentity.rawValue != job.hash {
        removeUnverifiedCopyIfNeeded(atPath: actualDestinationPath, runLogger: runLogger)
        return .failed(message: "Verification failed: hash mismatch.", logMessage: "...")
    }
} catch {
    // Hash threw; copy may be valid. Log warning, do NOT delete.
    runLogger.warn("Verification error (copy retained): \(actualDestinationPath): \(error)")
}
```

**Structural guard:** Add a test that injects a hash error (via mock `FileIdentityHasher`) after a successful copy and asserts the copy file still exists on disk. Tag `// AGENTS-INVARIANT: 3`.

**Expected impact:** Eliminates false-positive copy deletions on transient I/O errors. On a healthy system, behavior is unchanged.

**Tradeoffs:** A genuinely corrupt copy that cannot be hashed (very rare) is now retained rather than deleted. The user can identify and remove it manually. This is the correct tradeoff: retain ambiguous files, report clearly.

**Dependencies:** None.

**Suggested owner:** Backend.

---

## 7. IssueCounter Data Race Under Parallel Transfer

- **Category:** Reliability / Correctness
- **Priority:** P1 — `IssueCounter` in `SwiftOrganizerEngine` is accessed from multiple concurrent transfer workers without synchronization. Under `maxConcurrentCopies > 1`, the failure-threshold counters can produce incorrect counts.
- **Effort:** XS
- **Confidence:** High

**Problem:** `IssueCounter` (SwiftOrganizerEngine.swift lines 970–976) is marked `@unchecked Sendable` and its `increment()` and `value` read use no lock. When `maxConcurrentCopies > 1`, `TransferExecutionObserver.onIssue` is called from concurrent tasks on `errorCounter.increment()`. Two concurrent increments on a non-atomic `Int` is an undefined-behavior data race in Swift's memory model.

**Evidence:** `ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift` lines 970–976; `TransferExecutor.swift` parallel execution path.

**Root cause:** `@unchecked Sendable` was used to suppress a Swift concurrency warning without adding the necessary synchronization.

**Recommended change:**

```swift
private final class IssueCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    var value: Int { lock.withLock { _value } }
    func increment() { lock.withLock { _value += 1 } }
}
```

Or, if targeting macOS 15+, use `Atomic<Int>` from the `Synchronization` module.

**Structural guard:** Add a stress test that runs 100 parallel `increment()` calls and asserts `value == 100`. The race is detectable with `TSAN`.

**Expected impact:** Correct failure-threshold behavior under parallel transfer. Zero performance impact (the lock is taken once per failed copy, not per byte).

**Tradeoffs:** None. This is an unambiguous bug fix.

**Dependencies:** None.

**Suggested owner:** Backend.

---

## 8. Reorganize / Revert Silently Aborts Active Transfer

- **Category:** Reliability / UX
- **Priority:** P1 — Triggering "Reorganize Destination" or clicking "Revert" in Run History while a transfer is in progress silently aborts the transfer by calling `resetSessionState`, which cancels the current run.
- **Effort:** XS
- **Confidence:** High

**Problem:** `AppState.reorganizeDestination()` (AppState.swift lines 485–497) calls `runSessionStore.requestReorganize()` without checking `runSessionStore.isRunning`. `requestReorganize` calls `resetSessionState`, which calls `engine.cancelCurrentRun()`. The user sees the transfer stop with no explanation. Similarly, `HistoryCoordinator.revertHistoryEntry()` (HistoryCoordinator.swift lines 41–69) calls `requestRevert` without checking whether a transfer is running.

**Evidence:** `ui/Sources/ChronoframeApp/App/AppState.swift` lines 485–497; `ui/Sources/ChronoframeApp/App/Coordinators/HistoryCoordinator.swift` lines 41–69.

**Root cause:** `canStartRun` (AppState.swift line 160–161) checks only that paths are configured, not whether a run is active.

**Recommended change:** Add a guard at the entry point of `reorganizeDestination` and `revertHistoryEntry`:

```swift
guard !runSessionStore.isRunning else {
    // Surface a user-facing alert: "A transfer is in progress. Stop it before reorganizing."
    return
}
```

Also disable the Reorganize button in `SettingsView` when `runSessionStore.isRunning`.

**Structural guard:** Add a UI test asserting that the Reorganize button is disabled (or shows a confirmation dialog) during an active transfer.

**Expected impact:** Users are warned before a transfer is aborted. No silent data loss (source is always safe), but prevents confusion and wasted work.

**Tradeoffs:** None. The guard is a one-line addition.

**Dependencies:** None.

**Suggested owner:** Full-stack (Swift app layer).

---

## 9. PreviewReviewStore: Override Lost After Security Scope Closes

- **Category:** Reliability / UX
- **Priority:** P1 — User review decisions (Keep/Delete overrides) saved in `PreviewReviewStore` after the transfer completes are silently discarded with `EPERM` because the security scope was already closed.
- **Effort:** S
- **Confidence:** High

**Problem:** `PreviewReviewStore.persistOverride()` (PreviewReviewStore.swift lines 206–217) creates an `OrganizerDatabase` connection and writes to the destination's `.organize_cache.db`. This requires an open security scope for the destination. The scope is closed in `RunSessionStore.consume(.complete)` (RunSessionStore.swift lines 601–609). A user who opens the Preview Review panel, examines results, and then changes a Keep/Delete decision after the run completes is operating with a closed scope. The `Task.detached` write silently fails with `EPERM`. The override is not persisted.

**Evidence:** `ui/Sources/ChronoframeAppCore/Stores/PreviewReviewStore.swift` lines 206–217; `ui/Sources/ChronoframeAppCore/Stores/RunSessionStore.swift` lines 601–609.

**Root cause:** The security scope lifecycle was designed around the transfer run. The Preview Review panel's post-run interaction was not considered when the scope-close timing was set.

**Recommended change:** Open a short-lived, dedicated security scope in `persistOverride` from the stored destination bookmark before writing:

```swift
// In persistOverride, before creating OrganizerDatabase:
let scopeAccess = folderAccessService.scopedAccess(forKeys: [.manualDestination, .currentProfile])
defer { scopeAccess?.close() }
```

Alternatively, keep the main scope open until the Preview Review panel is dismissed (not just until transfer completion).

**Structural guard:** Add a unit test that calls `persistOverride` after `closeSecurityScope()` and verifies the override is either persisted (scope re-opened) or an explicit user-facing error is surfaced (not silent).

**Expected impact:** User review decisions are reliably persisted. No silent data loss.

**Tradeoffs:** Slightly extends sandbox scope lifetime. Acceptable for a user-initiated write.

**Dependencies:** Requires `FolderAccessService` access in `PreviewReviewStore` (currently `nonisolated static`).

**Suggested owner:** Full-stack.

---

## 10. Missing TransferExecutor Receipt-Directory Fault-Injection Test

- **Category:** Testing / Data Integrity
- **Priority:** P1 — `DeduplicateExecutor` has a comprehensive `FaultInjectionTests` suite covering unwritable `.organize_logs/`. `TransferExecutor` has no equivalent. This gap means the most-used flow in the app is untested for one of its most critical failure modes.
- **Effort:** S
- **Confidence:** High

**Problem:** `DeduplicateExecutorFaultInjectionTests` (verified to exist and be comprehensive) tests that: (a) an unwritable `.organize_logs/` before commit aborts with zero files trashed, (b) `.organize_logs/` becoming unwritable mid-run behaves correctly, and (c) cancelled runs produce the correct receipt status. `TransferExecutor` has no equivalent tests for: receipt directory unwritable mid-run, `StreamingAuditReceiptWriter` failure modes, or PENDING receipt left on disk after crash. The `StreamingAuditReceiptWriter` has untested failure paths that are safety-critical.

**Evidence:** Existence confirmed by reading `ui/Tests/ChronoframeAppCoreTests/DeduplicateExecutorFaultInjectionTests.swift`; absence confirmed by reading `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreTransferExecutorBehaviorTests.swift` (no `.organize_logs/` fault injection).

**Root cause:** `DeduplicateExecutor` was written with fault injection in mind; `TransferExecutor` predates that practice.

**Recommended change:** Add a new test file `ChronoframeCoreTransferExecutorFaultInjectionTests.swift` covering:
1. `.organize_logs/` unwritable before first copy → run aborts, zero files copied (tag `// AGENTS-INVARIANT: 9`)
2. `.organize_logs/` becomes unwritable after first copy → receipt has `ABORTED` status, copied files remain, no further copies attempted
3. Hash error after copy (mock hasher throws) → copy is retained, not deleted (regression guard for finding #6)
4. `renamex_np(RENAME_EXCL)` failure (destination exists) → correct `.failed(.collision)` outcome, no partial file

**Structural guard:** The tests themselves are the guard. Once added, any regression in these paths fails the test suite.

**Expected impact:** Provides a regression safety net for the most critical executor paths.

**Dependencies:** Requires mock `FileOperations` injection, which already exists in the test infrastructure.

**Suggested owner:** Backend.

---

## Quick Wins (ship this week)

1. **Wire `check_agents_invariants_have_tests.sh` to CI** (#1 above) — 15 minutes, PR adds one 6-line job to `ci.yml`.
2. **Fix `try?` in verify path** (#6 above) — 30 minutes, 10-line change in `TransferExecutor.swift`.
3. **Fix `IssueCounter` data race** (#7 above) — 20 minutes, add `NSLock` to `SwiftOrganizerEngine.swift`.
4. **Fix reorganize/revert aborting active transfer** (#8 above) — 30 minutes, add `isRunning` guard to `AppState.reorganizeDestination()`.
5. **Fix receipt finalization atomicity** (#4 above) — 45 minutes, replace two-step `removeItem`+`moveItem` with `rename(2)` in `TransferExecutor.swift`.
6. **Enable CodeQL uploads** (#3 above) — 5 minutes, one repository settings toggle + remove `upload: never`.
7. **Fix SECURITY.md stale Python reference** — 2 minutes, change "Python CLI" to "SwiftPM CLI (`ChronoframeCLI`)".
8. **Remove `CHRONOFRAME_NOTARY_PASSWORD` from release workflow env** — 5 minutes, delete one line from `release-package.yml`.

---

## Foundational Changes (land early, unlock other work)

1. **Dedupe executor: adopt streaming/spool receipt pattern** (#2 above) — Once landed, eliminates both the crash-stranding issue and the O(N²) I/O. The spool infrastructure also provides the foundation for a proper `recoverInterruptedDedupeRuns` path.
2. **Reorganize checkpoint gap → per-move writes** (#5 above) — Simple change; unblocks confident use of reorganize on unreliable volumes.

---

## High-Risk Refactors Worth Doing

1. **Drop manifest path containment check** (core engine finding #4): `MediaDiscovery.enumerateManifest` accepts arbitrary paths. Adding a `SafePathContainment.isContained(url, in: rootURL)` guard is small but touches the manifest ingestion path, which has no existing fault-injection tests. Add the test first.

---

## What Works — Do Not Change

1. **`RevertExecutor.safeRevert()` TOCTOU mitigations** — O_NOFOLLOW open, fd-based hash, `fstatat(AT_SYMLINK_NOFOLLOW)` inode re-check, `unlinkat`. This is among the strongest revert implementations anywhere. Leave it alone.
2. **`StreamingAuditReceiptWriter` PENDING/spool design** — The crash-recovery design for organize runs is solid. The fix for dedupe should mirror it, not replace it.
3. **Zero external Swift dependencies** — The decision to use no third-party packages eliminates an entire supply-chain risk class. Do not add dependencies without strong justification.
4. **All GitHub Actions pinned to full SHA** — Supply-chain hygiene is strong. Maintain this discipline as new workflows are added.
5. **Failure-threshold logic (5 consecutive / 20 total)** — The thresholds are well-calibrated for a photo-organizing app. Generous enough to survive transient errors; tight enough to stop a misconfigured run before it damages too much. Leave them unchanged.
6. **Custom BLAKE2b-512 implementation** — The implementation is correct by inspection, fast enough, and self-consistent. The only gap is reference-vector tests (easy to add). Do not replace it with a different hash algorithm — that would break all existing receipts.
7. **`DeduplicationPlanner` as single source of truth** — The architectural decision that both the UI preview and the executor consume the same `DeduplicationPlan` is sound. Never let the executor diverge from the plan.

---

## Changes to Avoid Right Now

1. **Replacing `OrganizerDatabase` with a different persistence layer** — SQLite is adequate; the schema is small; the migration infrastructure works. A rewrite here risks introducing new data-loss paths for no gain.
2. **Adding `CoreData` or `SwiftData`** — Would add a third-party-like dependency, a migration story, and background context complexity. The current SQLite layer is better understood and more auditable.
3. **Generalizing `StreamingAuditReceiptWriter` into a shared protocol before fixing the dedupe crash** — The crash fix is urgent. Premature generalization would delay it and add complexity.
4. **Switching BLAKE2b to `CommonCrypto` SHA-256** — Would break all existing receipts. If a hash algorithm change is ever needed, it requires a migration plan, receipt schema versioning, and broad testing.
