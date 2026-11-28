# Chronoframe — Top 10 Highest Impact Improvements

> **Status: historical, implemented. Do not recreate this work.**
> Prioritized findings from the 2026-05-24 review (pass type REFRESH). Items 1, 2, 4 to 9 are implemented, mostly by the remediation series PR #152 to #160 (see the table). Item 3 and item 10 could not be fully confirmed and are listed as unverified. The long per-finding write-ups (problem, evidence line numbers, proposed code) were removed on 2026-11-21; they described the code as it was in May and the line numbers no longer apply. Full text is in git history (`git log -- prodsec/Chronoframe/TOP_IMPROVEMENTS.md`).
> Current sources of truth: `AGENTS.md`, `docs/SAFETY_AND_RECOVERY.md`, `docs/production-readiness-certification.md`, `docs/remaining-work-plan.md`.

Scale: 1 to 5, higher is worse. Score = SEV × LIK × BLAST × LEV.

| # | Finding (2026-05-24) | Score | Status on 2026-11-21 and evidence |
|---|---|---|---|
| 1 | Invariant check script not wired to CI | 400 | Done. `invariants-check` job in `.github/workflows/ci.yml:25`. |
| 2 | `DeduplicateExecutor`: crash between Trash and receipt update strands files; O(N²) receipt writes | 240 | Done in the #152 to #160 series: PENDING receipt plus versioned append-only spool (`*.spool`), `DeduplicateExecutor.recoverInterruptedRuns` (called at `SwiftOrganizerEngine.swift:645`), `ReceiptDurability.durablyWrite`. |
| 3 | CodeQL SARIF upload disabled (`upload: never`) | 225 | Unverified. `upload: never` is gone from `.github/workflows/codeql.yml` (commit c21a907 skips upload when code scanning is disabled; the workflow now has no upload key). Whether results reach the GitHub Security tab is a repository setting we could not check from the code. |
| 4 | Receipt finalization remove-then-rename gap | 160 | Done. `TransferExecutor` finalizes via `ReceiptDurability.durablyWrite` (atomic `rename(2)`, `ReceiptDurability.swift:52`); tests in `ReceiptDurabilityTests.swift`. |
| 5 | `ReorganizeExecutor` checkpoint gap (up to 24 unrecorded moves) | 144 | Done. `receiptCheckpointInterval = 1` (`ReorganizeExecutor.swift:416`). An append-only spool to cut the per-move rewrite cost is still a possible optimization, not a defect. |
| 6 | `try?` in verify path deletes valid copies | 144 | Done. No `try? ... hashIdentity` remains in `TransferExecutor.swift`. |
| 7 | `IssueCounter` data race | 144 | Done. `IssueCounter` is lock-protected (`SwiftOrganizerEngine.swift:1385`, `NSLock`). |
| 8 | Reorganize/Revert silently aborts an active transfer | 108 | Done. `guard !runSessionStore.isRunning` in `AppState.swift:934` and `:1042`; `HistoryCoordinator` revert/reorganize paths delegate to it. |
| 9 | `PreviewReviewStore` override lost after security scope closes | 108 | Done. `persistOverride` opens its own destination scope (`PreviewReviewStore.swift:377`, `defer { scope?.close() }`). |
| 10 | Missing `TransferExecutor` receipt-directory fault-injection test | 96 | Unverified. `ReceiptDurabilityTests.swift` (unwritable directory, failed rename, link/FIFO at temp name) now covers the receipt writer, but no dedicated `TransferExecutor` fault-injection file with the four scenarios proposed in May exists. Treat the exact scenarios (receipt directory unwritable mid-run, hash error retains copy, `RENAME_EXCL` collision) as open until a test is named. |

Original quick-win extras: `SECURITY.md` no longer mentions Python (done); `CHRONOFRAME_NOTARY_PASSWORD` no longer appears under `.github/` (done). Drop-manifest path containment (core engine finding #4 in the May review) is addressed by `SafePathContainment` (used by dedupe and watched sources); the manifest-ingestion fault-injection test remains unverified.

## Durable guidance (still valid)

What works, do not change:
1. `RevertExecutor.safeRevert()` TOCTOU mitigations: `O_NOFOLLOW` open, fd-based hash, `fstatat(AT_SYMLINK_NOFOLLOW)` inode re-check, `unlinkat`.
2. `StreamingAuditReceiptWriter` PENDING/spool design. Any new receipt writer should mirror it.
3. Zero external Swift dependencies. Do not add dependencies without strong justification.
4. All GitHub Actions pinned to full SHA.
5. Failure thresholds (5 consecutive, 20 total).
6. Custom BLAKE2b-512. Changing the hash breaks all existing receipts; it would need a migration plan and receipt schema versioning.
7. `DeduplicationPlanner` as the single source of truth for UI preview and executor.

Avoid: replacing `OrganizerDatabase` or adopting CoreData/SwiftData; generalizing the receipt writer into a shared protocol for its own sake; switching BLAKE2b to SHA-256.
