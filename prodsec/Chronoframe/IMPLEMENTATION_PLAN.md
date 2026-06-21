# Chronoframe — Implementation Plans for Top 3

> **Historical audit artifact.** This file preserves the 2026-05-24 proposals
> and should not be used as the current implementation plan. The invariant CI
> guard, durable receipt finalization, destination locking, dedupe quarantine,
> mutation journaling, and startup recovery are implemented through PRs
> #152–#160. Use `AGENTS.md`, `docs/SAFETY_AND_RECOVERY.md`,
> `docs/TECHNICAL.md`, and `docs/remaining-work-plan.md` for current behavior and
> remaining work.

_Generated: 2026-05-24. Supersedes prior documents in this directory._

Plans for the three findings with the highest SEV × LIK × BLAST × LEV scores:
1. Invariant check script not wired to CI (score: 400)
2. DeduplicateExecutor crash strands files in Trash (score: 240)
3. Receipt finalization: remove-then-rename atomicity gap (score: 160)

---

## Plan 1: Wire `check_agents_invariants_have_tests.sh` to CI

### A. Objective

Add the invariant-tag check as a required CI job so that any PR that removes or fails to add a `// AGENTS-INVARIANT: N` test tag fails CI before merge.

**Success criteria:**
- A PR that removes a `// AGENTS-INVARIANT: N` tag from any test file causes the new CI job to fail.
- The job completes in under 60 seconds on a `ubuntu-latest` runner.
- The job is listed as a required status check in branch protection rules.

### B. Current State

`script/check_agents_invariants_have_tests.sh` exists and is correct. It parses `AGENTS.md` for invariant bullets and greps test files for `// AGENTS-INVARIANT: N` tags. It returns exit code 1 if any invariant lacks a test. It is called in `CLAUDE.md` and `AGENTS.md` as a required gate but is not referenced from any GitHub Actions workflow.

### C. Target State

A new `invariants-check` job in `.github/workflows/ci.yml` runs on every pull request and push to `main`. It runs `script/check_agents_invariants_have_tests.sh` on an Ubuntu runner. The job is added to the branch protection required-status-checks list.

### D. Detailed Design

No code changes required. One workflow file change only:

`.github/workflows/ci.yml` — add after the existing jobs:

```yaml
invariants-check:
  name: AGENTS-INVARIANT tag check
  runs-on: ubuntu-latest
  steps:
    - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v4
    - name: Check all AGENTS-INVARIANT bullets have tagged tests
      run: script/check_agents_invariants_have_tests.sh
```

The script uses only `bash`, `awk`, and `grep` — available on all Ubuntu runners with no setup step.

### E. Step-by-Step Execution Plan

**Phase 1 — Add the job (PR ~15 minutes):**
1. Edit `.github/workflows/ci.yml` to add the `invariants-check` job above.
2. Open PR. The new job runs. Verify it passes on the current main state.
3. Merge.

**Phase 2 — Make it a required check (~5 minutes):**
1. Navigate to GitHub repo → Settings → Branches → Branch protection rules → `main` → Edit.
2. Under "Require status checks to pass before merging", add `AGENTS-INVARIANT tag check`.
3. Save.

**Phase 3 — Document in AGENTS.md (~5 minutes):**
1. Update the "CI" section of `AGENTS.md` to note that the invariant check runs automatically on every PR.

### F. Testing Strategy

- **Regression test:** After merging, create a test PR that removes one `// AGENTS-INVARIANT:` tag from a test file. Verify the CI job fails on that PR. Then close the PR.
- **No unit tests required** for the workflow change itself.

### G. Operational Plan

- No metrics, alerts, or dashboards needed.
- If the script produces false positives (e.g., a new AGENTS.md bullet without a test), the correct response is to add the test, not to bypass the CI job.

### H. Risks and Mitigations

- **Risk:** Script has a parsing bug that falsely fails CI on clean code. **Mitigation:** The script was already written and used locally; verify on current `main` before merging.
- **Risk:** Ubuntu runner doesn't have a required shell utility. **Mitigation:** The script uses only `bash`, `awk`, `grep` — universally available.

### I. Resourcing and Sequencing

- Single engineer, 30 minutes total (including Phase 2 repository settings change).
- No cross-team dependencies.

### J. Definition of Done

- `invariants-check` job passes on all open PRs.
- The job is a required status check on `main`.
- Removing any `// AGENTS-INVARIANT: N` tag causes the job to fail.

---

## Plan 2: Fix DeduplicateExecutor Crash-Between-Trash-and-Receipt

### A. Objective

Eliminate the crash window in `DeduplicateExecutor.commit()` where a file is moved to Trash but its `trashURL` is never written to the receipt, leaving the file unrecoverable via Run History → Revert. As a side effect, eliminate the O(N²) receipt I/O.

**Success criteria:**
- A simulated app crash (fault injection) after the K-th trash produces a receipt with correct `trashURL` entries for all K trashed items.
- A 10,000-item dedupe run writes ≤ N+2 receipt-file operations (not N²).
- All existing dedupe executor tests continue to pass.
- `script/check_agents_invariants_have_tests.sh` passes with a new `// AGENTS-INVARIANT: 13` test.

### B. Current State

`DeduplicateExecutor.commit()` (DeduplicateExecutor.swift ~lines 100–210):

```
for each item to trash:
    1. trashItem(originalURL) → trashURL
    2. update receiptItems[i].trashURL = trashURL
    3. writeReceipt(all receiptItems)  ← full JSON encode + atomic write
```

This is O(N²) in total bytes written. More critically, if the process is killed between step 1 and step 3, the receipt on disk still has `trashURL: nil` for the just-trashed item. `DeduplicateExecutor.revert()` then skips that item with "Receipt is missing the Trash URL".

### C. Target State

```
Before the loop:
    1. Write PENDING receipt with all items as trashURL: nil
    2. Open a spool file for appending

For each item to trash:
    1. trashItem(originalURL) → trashURL
    2. Append spool line: "{originalPath}\t{trashURL}\n"  ← one write, not a full encode

After the loop:
    3. Read spool, assemble final receipt JSON
    4. Atomic rename spool→final receipt (NOT removeItem + moveItem)
    5. Delete spool file

On app relaunch:
    recoverInterruptedDedupeRuns():
        - Find PENDING dedupe receipts with associated spool files
        - Consolidate: mark items found in spool as completed with trashURL
        - Update receipt status to ABORTED (we can't know if the run was complete)
        - Make available in Run History for partial Revert
```

### D. Detailed Design

#### D1. Spool format

A spool file lives alongside the receipt: `dedupe_audit_receipt_<uuid>_spool.tsv`

Each line: `<originalPath>\t<trashURL>\n` (tab-separated, newline-terminated)

Tab-separated with no escaping is sufficient because:
- macOS paths cannot contain tab characters (the VFS rejects them)
- `trashURL` is a `file://` URL from `NSFileManager.trashItem`, which also cannot contain tabs

#### D2. Changes to `DeduplicateExecutor.swift`

```swift
// New: write PENDING receipt before loop
try Self.writeReceipt(
    receiptURL: pendingReceiptURL,
    status: .pending,
    items: allItems.map { item in
        DeduplicateReceiptItem(originalPath: item.originalPath, trashURL: nil, ...)
    }
)

// Open spool file for appending
let spoolURL = pendingReceiptURL.deletingPathExtension()
    .appendingPathExtension("spool.tsv")
let spoolFD = open(spoolURL.path, O_WRONLY | O_CREAT | O_APPEND, 0o600)
guard spoolFD >= 0 else { throw DeduplicateExecutorError.spoolOpenFailed(errno: errno) }
defer { close(spoolFD) }

for item in itemsToTrash {
    let (_, trashURL) = try fileOperations.trashItem(at: item.originalURL)
    // Append to spool — one write syscall, not a full encode
    let line = "\(item.originalURL.path)\t\(trashURL.absoluteString)\n"
    line.withCString { ptr in
        _ = Darwin.write(spoolFD, ptr, strlen(ptr))
    }
}

// After the loop: assemble final receipt from spool
let spoolLines = try String(contentsOf: spoolURL, encoding: .utf8)
    .split(separator: "\n", omittingEmptySubsequences: true)
let trashURLsByPath: [String: URL] = Dictionary(
    uniqueKeysWithValues: spoolLines.compactMap { line -> (String, URL)? in
        let parts = line.split(separator: "\t", maxSplits: 1)
        guard parts.count == 2, let url = URL(string: String(parts[1])) else { return nil }
        return (String(parts[0]), url)
    }
)

let finalItems = allItems.map { item in
    DeduplicateReceiptItem(
        originalPath: item.originalPath,
        trashURL: trashURLsByPath[item.originalPath],
        ...
    )
}

// Atomic rename: spool→finalReceipt (not removeItem+moveItem)
let finalReceiptURL = ... // UUID-stamped final path
try Self.writeReceipt(receiptURL: tmpReceiptURL, status: .completed, items: finalItems)
let renameResult = tmpReceiptURL.withUnsafeFileSystemRepresentation { src in
    finalReceiptURL.withUnsafeFileSystemRepresentation { dst in
        src.flatMap { s in dst.map { d in Darwin.rename(s, d) } } ?? -1
    }
}
guard renameResult == 0 else { throw DeduplicateExecutorError.finalizationFailed(errno: errno) }

// Remove spool and pending receipt (best-effort cleanup)
try? FileManager.default.removeItem(at: spoolURL)
try? FileManager.default.removeItem(at: pendingReceiptURL)
```

#### D3. New `recoverInterruptedDedupeRuns()` in `SwiftOrganizerEngine.swift`

Called at app launch alongside `recoverInterruptedRuns()`:

```swift
func recoverInterruptedDedupeRuns(destinationRoot: URL) {
    let logsDir = destinationRoot.appendingPathComponent(
        EngineArtifactLayout.chronoframeDefault.logsDirectoryName
    )
    let fm = FileManager.default
    guard let contents = try? fm.contentsOfDirectory(at: logsDir,
        includingPropertiesForKeys: nil) else { return }

    for pendingReceiptURL in contents where pendingReceiptURL.lastPathComponent
        .hasPrefix("dedupe_audit_receipt_") &&
        pendingReceiptURL.lastPathComponent.hasSuffix("_PENDING.json") {

        let spoolURL = pendingReceiptURL.deletingPathExtension()
            .appendingPathExtension("spool.tsv")
        guard fm.fileExists(atPath: spoolURL.path) else { continue }

        // Consolidate: mark spool entries as trashed, finalize as ABORTED
        // (we cannot know if the run completed — use ABORTED conservatively)
        DeduplicateExecutor.consolidatePendingReceipt(
            pendingReceiptURL: pendingReceiptURL,
            spoolURL: spoolURL
        )
    }
}
```

#### D4. `DeduplicateExecutor.revert()` — no changes needed

Once the receipt has correct `trashURL` entries (even from a recovered spool), the existing revert logic works unchanged. The only change is that previously-stranded items now have valid `trashURL` entries.

### E. Step-by-Step Execution Plan

**Phase 1 — Structural guard (failing test) [~1 day]:**

1. Add `DeduplicateExecutorFaultInjectionTests.testCrashBetweenTrashAndReceiptPreservesTrashURL`:
   - Configure executor with a `MockFileOperations` that throws after the 3rd `trashItem` call.
   - Run `commit()` — expect throw.
   - Read the on-disk receipt (or spool).
   - Assert all 3 trashed items have a non-nil `trashURL` in the spool file.
   - Tag: `// AGENTS-INVARIANT: 13`
   - This test **fails** on the current code (the spool doesn't exist yet). That's the point.

2. Run `script/check_agents_invariants_have_tests.sh` — confirm it now reports the new tag.

**Phase 2 — Implement spool writer [~2 days]:**

1. Add `DeduplicateExecutor.SpoolWriter` (private inner type or free function).
2. Modify `commit()` to open spool, append after each trash, close.
3. Modify `finish()` to assemble final receipt from spool + atomic rename.
4. Run the Phase 1 test — it should now pass.
5. Run all existing `DeduplicateExecutorFaultInjectionTests` — all should pass.
6. Run `script/swift_meaningful_coverage.sh` — confirm ≥95%.

**Phase 3 — Implement `recoverInterruptedDedupeRuns` [~1 day]:**

1. Add `DeduplicateExecutor.consolidatePendingReceipt(pendingReceiptURL:spoolURL:)`.
2. Call it from `SwiftOrganizerEngine` at app launch after `recoverInterruptedRuns`.
3. Add test: `DeduplicateExecutorFaultInjectionTests.testInterruptedRunIsRecoverableAfterRelaunch`.

**Phase 4 — Integration and cleanup [~0.5 days]:**

1. Remove the old per-item `writeReceipt` call from the loop.
2. Remove the old `receiptItems` accumulation array (replaced by spool).
3. Run full test suite.
4. Build app and do a manual smoke test: small dedupe run, verify receipt correct.
5. Merge.

### F. Testing Strategy

- **New fault injection tests** (Phase 1 + 3): kill after K trashes, verify receipt/spool integrity.
- **Existing tests:** All existing `DeduplicateExecutorFaultInjectionTests` must continue to pass.
- **Property test (optional):** For N in {1, 10, 100, 1000}, verify total bytes written scales O(N) not O(N²).
- **Regression test:** Large dedupe run (1,000+ items) completes without errors; receipt has all items; Revert restores all items.

### G. Operational Plan

- No new metrics or alerts required.
- The receipt file format is unchanged (same JSON schema). Only the write pattern changes.
- If the spool file is present at next launch without a PENDING receipt (unusual), it is silently ignored (best-effort cleanup).

### H. Risks and Mitigations

- **Risk:** Spool append fails mid-run (disk full). **Mitigation:** Treat spool write failure as a fatal executor error — abort the run, do not continue trashing files without a spool. The PENDING receipt is left on disk for manual inspection.
- **Risk:** Spool file is corrupted (truncated line). **Mitigation:** `consolidatePendingReceipt` skips any line that doesn't parse as a valid `path\tURL` pair. Only complete entries are included in the recovery receipt.
- **Risk:** This changes behavior for existing PENDING dedupe receipts (from the old code). **Mitigation:** On relaunch, a PENDING receipt without a spool file is treated as before (run reported as interrupted, no recovery). The new recovery path only activates when a spool file is present.

### I. Resourcing and Sequencing

- Single engineer, ~4–5 days.
- No cross-team dependencies.
- Can be worked in parallel with plans 1 and 3.

### J. Definition of Done

- `testCrashBetweenTrashAndReceiptPreservesTrashURL` passes (AGENTS-INVARIANT: 13 tagged).
- `testInterruptedRunIsRecoverableAfterRelaunch` passes.
- All existing `DeduplicateExecutorFaultInjectionTests` pass.
- `script/check_agents_invariants_have_tests.sh` passes.
- `script/swift_meaningful_coverage.sh` passes (≥95%).
- A manual 1,000-item dedupe run produces a receipt with all correct `trashURL` entries.
- A manual "kill app after 100 trashes and relaunch" produces a recovery receipt with 100 correct entries.

---

## Plan 3: Fix Receipt Finalization Atomicity Gap

### A. Objective

Replace the non-atomic `removeItem(PENDING) + moveItem(tmp→final)` two-step in `StreamingAuditReceiptWriter.finish()` with a single atomic `rename(2)` call, eliminating the crash window where neither receipt exists.

**Success criteria:**
- After any simulated crash during `finish()`, exactly one of {PENDING receipt, COMPLETED receipt} exists on disk.
- Existing receipt-recovery tests continue to pass.
- No regression in `RunHistoryIndexer` (it reads both PENDING and COMPLETED receipt names).

### B. Current State

`StreamingAuditReceiptWriter.finish()` (TransferExecutor.swift lines 1155–1162):

```swift
// Problem: crash between these two lines leaves no receipt
if fileManager.fileExists(atPath: finalReceiptURL.path) {
    try fileManager.removeItem(at: finalReceiptURL)
}
try fileManager.moveItem(at: temporaryReceiptURL, to: finalReceiptURL)
```

The comment at line 1152 explains the intent: `moveItem` refuses to overwrite, so the existing PENDING receipt is removed first. But if the process is killed between `removeItem` and `moveItem`, neither receipt exists. `recoverInterruptedRuns` scans for PENDING receipts — but it was just deleted.

### C. Target State

```swift
// Single atomic rename: replaces the target atomically on APFS/HFS+
let result = temporaryReceiptURL.withUnsafeFileSystemRepresentation { src in
    finalReceiptURL.withUnsafeFileSystemRepresentation { dst in
        guard let s = src, let d = dst else { return Int32(-1) }
        return Darwin.rename(s, d)
    }
}
guard result == 0 else {
    throw AuditReceiptError.finalizationFailed(
        message: "Could not finalize receipt",
        underlyingErrno: errno
    )
}
```

On macOS, `rename(2)` is guaranteed atomic on the same filesystem. Both `temporaryReceiptURL` and `finalReceiptURL` are always inside `.organize_logs` on the destination volume — same filesystem guaranteed.

### D. Detailed Design

#### D1. Why `rename(2)` instead of `FileManager.replaceItem`

`FileManager.replaceItem(at:withItemAt:...)` is the Apple-sanctioned "safe save" API. However it:
- Internally creates a backup copy (extra I/O)
- Can fail on volumes that don't support the backup mechanism
- Returns `resultingItemURL` rather than throwing on partial success — adds error handling complexity

`rename(2)` is a single POSIX syscall, atomic at the VFS layer on all Apple filesystems (APFS, HFS+). It has been used elsewhere in this codebase (`renamex_np(RENAME_EXCL)` in `TransferExecutor.performCopy`). Using it here is consistent with the existing low-level I/O style.

#### D2. Error case

If `rename` returns -1, the temporary receipt still exists (the rename is all-or-nothing). Log the errno and throw. The caller (`StreamingAuditReceiptWriter`) already has a `deinit` path (`discardUnfinishedFiles`) that removes the temporary receipt on cleanup. The PENDING receipt is still on disk. `recoverInterruptedRuns` will find it on next launch and treat it as an interrupted run — which is the correct behavior.

#### D3. Files affected

- `ui/Sources/ChronoframeCore/TransferExecutor.swift` — lines 1155–1162: replace `removeItem` + `moveItem` with `rename(2)`.
- No changes to `StreamingAuditReceiptWriter` public interface.
- No changes to `recoverInterruptedRuns` — it already handles PENDING receipts correctly.

### E. Step-by-Step Execution Plan

**Phase 1 — Structural guard (failing test) [~2 hours]:**

1. Add test `StreamingAuditReceiptWriterTests.testFinalizationCrashWindowLeavesAtLeastOneReceipt`:
   - Create a mock that throws `FileManager.moveItem` (or equivalent) after `removeItem` succeeds.
   - Call `finish()`.
   - Assert that either the PENDING receipt or the final receipt exists (not neither).
   - This test **fails** on the current code (neither exists when moveItem fails after removeItem).
   - Tag: `// AGENTS-INVARIANT: 9` (receipts carry status; receipt-before-mutation)

**Phase 2 — Implement fix [~1 hour]:**

1. Edit `TransferExecutor.swift` lines 1155–1162:
   - Remove the `removeItem` call.
   - Replace `moveItem` with `Darwin.rename(src, dst)`.
   - Add errno-based error throw.

2. Run the Phase 1 test — should now pass.

3. Run all `ChronoframeCoreTransferExecutorBehaviorTests` — all should pass.

**Phase 3 — Verify edge cases [~1 hour]:**

1. Verify that `recoverInterruptedRuns` still correctly processes PENDING receipts (no behavior change — the PENDING receipt path is unaffected by this fix; the PENDING receipt is now atomically replaced by the final receipt, not removed first).
2. Run `script/swift_meaningful_coverage.sh`.

**Phase 4 — Merge [~30 minutes]:**

1. Open PR with the test (Phase 1) and the fix (Phase 2) as separate commits.
2. Verify CI passes.
3. Merge.

### F. Testing Strategy

- **New test** (Phase 1): fault-injected `moveItem`/`rename` failure asserts receipt invariant.
- **Existing tests:** All existing `ChronoframeCoreTransferExecutorBehaviorTests` must pass unchanged.
- **Manual smoke test:** Run a small transfer, interrupt it, verify PENDING receipt is on disk. Run again, verify it completes to COMPLETED receipt. Run History shows both entries.

### G. Operational Plan

- No new metrics or alerts required.
- The receipt filename convention is unchanged (same PENDING/COMPLETED naming). `RunHistoryIndexer` continues to work without changes.

### H. Risks and Mitigations

- **Risk:** `rename(2)` fails on network volumes that don't support atomic rename. **Mitigation:** Network volumes are not the primary use case (local Photos library is). If `rename` fails, the PENDING receipt is still on disk — the user sees an interrupted run in history, not data loss. Log the errno clearly.
- **Risk:** On a case-insensitive filesystem (HFS+, common external drives), two receipts with the same base name could collide. **Mitigation:** Receipt names include a UUID suffix, making collisions cryptographically negligible.
- **Risk:** The change is in a safety-critical path. **Mitigation:** The fix is a mechanical replacement of two syscalls with one. The logic (write temp → rename to final) is unchanged.

### I. Resourcing and Sequencing

- Single engineer, ~4 hours total.
- No cross-team dependencies.
- Can be done in parallel with plans 1 and 2.
- **Land this before Plan 2**, since Plan 2 (dedupe) mirrors this pattern for its own finalization.

### J. Definition of Done

- `testFinalizationCrashWindowLeavesAtLeastOneReceipt` passes (AGENTS-INVARIANT: 9 tagged).
- All existing executor tests pass.
- `script/check_agents_invariants_have_tests.sh` passes.
- Manual smoke test: interrupted run leaves PENDING receipt; completed run produces COMPLETED receipt (via atomic rename).

---

## Recommended Execution Order

```
Week 1 (Quick wins — all can be done in parallel):
  ├── Plan 1: Wire invariant check to CI              [30 min]
  ├── Plan 3: Fix receipt finalization atomicity       [4 hours]
  ├── Fix try? in verify path (TOP #6)                [1 hour]
  ├── Fix IssueCounter data race (TOP #7)             [30 min]
  ├── Fix reorganize aborts transfer (TOP #8)         [1 hour]
  ├── Enable CodeQL uploads (TOP #3)                  [10 min]
  └── Housekeeping: SECURITY.md, remove notary secret [30 min]

Week 2–3 (Plan 2: Dedupe spool pattern):
  ├── Phase 1: Structural guard test                  [1 day]
  ├── Phase 2: Spool writer implementation            [2 days]
  ├── Phase 3: recoverInterruptedDedupeRuns           [1 day]
  └── Phase 4: Integration + smoke test              [0.5 days]

Week 3 (Parallel, while Plan 2 is in review):
  ├── Fix reorganize checkpoint gap (TOP #5)          [1 day]
  ├── Fix PreviewReviewStore scope (TOP #9)           [1 day]
  └── Add TransferExecutor fault injection tests (#10) [2 days]

Week 4 (Hardening):
  ├── Add BLAKE2b reference-vector tests
  ├── Fix RevertExecutor nil boundary default
  ├── Fix drop manifest containment check
  └── Fix RunHistoryIndexer mtime sort key
```

**Front-load the structural guards.** Plans 1, 3, and the quick fixes (try?, IssueCounter, reorganize abort) all land their guards first. By end of Week 1, every subsequent fix has a regression-proof test gate already in CI.
