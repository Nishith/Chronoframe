# Chronoframe — Implementation Plans for Top 3

> **Status: historical, already implemented. Do not recreate or re-execute these plans.**
> Written 2026-05-24 for the three highest-scoring findings in [TOP_IMPROVEMENTS.md](TOP_IMPROVEMENTS.md). All three were implemented by the remediation series PR #152 to #160, in a different final shape than proposed here (destination lock, immutable dedupe plan, quarantine, schema-v2 mutation journal and recovery coordinator went beyond these plans). The detailed designs, step lists and week-by-week order were removed on 2026-11-21; they no longer match the code. Full text is in git history (`git log -- prodsec/Chronoframe/IMPLEMENTATION_PLAN.md`).
> Current behavior and open work: `AGENTS.md`, `docs/SAFETY_AND_RECOVERY.md`, `docs/TECHNICAL.md`, `docs/remaining-work-plan.md`.

| Plan | Goal | Outcome |
|---|---|---|
| 1. Wire `check_agents_invariants_have_tests.sh` to CI | Fail any PR that drops a `// AGENTS-INVARIANT: N` tag | Done: `invariants-check` job in `.github/workflows/ci.yml:25`. |
| 2. Dedupe crash between trash and receipt update | Write a PENDING receipt first, append each trash to a spool, consolidate at the end, recover interrupted runs on relaunch | Done: PENDING receipt, versioned append-only `.spool`, `DeduplicateExecutor.recoverInterruptedRuns` (invoked from `SwiftOrganizerEngine.swift:645`), tagged invariant tests (`DeduplicateExecutorFaultInjectionTests`, `DeduplicateExecutorQuarantineTests`). |
| 3. Receipt finalization atomicity | Replace remove-then-move with an atomic `rename(2)` | Done: `ReceiptDurability.durablyWrite` (`ReceiptDurability.swift:52`), used by transfer, dedupe and reorganize receipts; tests in `ReceiptDurabilityTests.swift`. |

The plans' "Week 1 to 4" extras: `try?` verify fix, `IssueCounter` lock, reorganize/revert-during-transfer guard, reorganize checkpoint interval 1, `PreviewReviewStore` scope, SECURITY.md Python reference and notary-secret cleanup are done (evidence per item in TOP_IMPROVEMENTS.md). BLAKE2b reference-vector test exists (`ChronoframeCoreBLAKE2bTests.swift`). Unverified: CodeQL SARIF upload, a dedicated `TransferExecutor` receipt-directory fault-injection test, the `RevertExecutor` nil-boundary default, drop-manifest containment, and the `RunHistoryIndexer` mtime sort key.

One principle worth keeping: land the structural guard (the failing test or CI check) first, then the fix, so each fix arrives with a regression gate already in place. This is now project policy in `CLAUDE.md` under "Goal-driven execution for invariant work".
