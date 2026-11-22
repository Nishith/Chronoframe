# Chronoframe — Phase 2 Findings

> **Status: historical, all 25 findings fixed. Do not recreate this work.**
> Second-pass audit (property tests on `DeduplicationPlanner`, fault injection on `DeduplicateExecutor`, real-FileManager integration, receipt golden files, probes of the CLI, drag-drop/`FileSystemMonitor` and SwiftUI views). It added NEW1 to NEW25 on top of the 10 findings in [TOP_IMPROVEMENTS.md](TOP_IMPROVEMENTS.md). Every item below was fixed with a regression test; the fixes landed in e5cd82e (Finding #1 and NEW1), 5e0ee15 (NEW2 to NEW5) and 2d26352 (NEW6 to NEW25), then the remediation series through PR #160 added locking, immutable dedupe plans, quarantine and durable recovery. The per-finding write-ups were removed on 2026-11-21; full text is in git history.
> Current sources of truth: `AGENTS.md`, `docs/SAFETY_AND_RECOVERY.md`, `docs/production-readiness-certification.md`, `docs/remaining-work-plan.md`.

## Findings, one line each (all fixed)

| ID | Finding | Closed by |
|---|---|---|
| NEW1 | Pair fan-out could empty a whole dedupe cluster. Keep-wins now applies for every decision source; the safety rail accounts for pair-induced deletes. | e5cd82e; `testPropertyPairKeepWinsAcrossAllDecisionSources`, `testPropertyNoClusterIsCompletelyEmptiedByThePlan` |
| NEW2 | `--json` without `--yes` interleaved prompts on stdout and hung on stdin. Now a usage error (exit 2) before any prompt. | 5e0ee15; `testJSONWithoutAssumeYesFailsFastInsteadOfHangingOnAPrompt` |
| NEW3 | `FileSystemMonitor` polling fallback ran alongside FSEvents, double-yielding events. Fallback now runs only if FSEvents setup fails. | 5e0ee15; `testFileSystemMonitorDoesNotDoubleYieldEventsWhenFSEventsIsActive` |
| NEW4 | Unsynchronized `continuation` state in `FileSystemMonitor`. Guarded by `NSLock` (a `queue.sync` variant deadlocked and was rejected). | 5e0ee15 |
| NEW5 | FSEvents callback could outlive the monitor (`takeUnretainedValue`). Stream now holds a retain via context retain/release callbacks. | 5e0ee15 |
| NEW6 | `RunHistoryView` section identity regenerated every render. Identity is now the section date. | 2d26352 |
| NEW7 | `PreviewReviewPanel` row state stale after Save. | 2d26352 |
| NEW8 | `ClusterDetailPane` key monitor swallowed arrow keys app-wide. | 2d26352 |
| NEW9, NEW10 | Comparison views and difference-image generation blocked the main actor. | 2d26352 |
| NEW11 | CLI rejected option values beginning with `-`; no `--flag=value` or `--`. | 2d26352 |
| NEW12 | CLI `--json` printed usage errors as plain text. | 2d26352 |
| NEW13 | `--revert` silently ignored `--skip-verify` / `--folder-structure` (now a whitelist). | 2d26352 |
| NEW14 | CLI paths had no `~` expansion or NFC normalization. | 2d26352 |
| NEW15 | CLI tests bypassed the process boundary; a `Process()`-based test was added. | 2d26352 |
| NEW16 to NEW20 | Contact-sheet stale-result race, double `.keyboardShortcut`, flicker-toggle task leak, silent malformed drop manifest, stale `DroppedItemStager` doc comment. | 2d26352 |
| NEW21 | Dedupe footer count overcounted by including weak-match preselects (`currentDeletionPlan()`). | 2d26352 |
| NEW22 to NEW25 | CLI had no signal handling, watched-directory unmount was not surfaced, per-row recoverable-bytes was O(plan items), health dashboard retry-looped on a failed refresh. | 2d26352 |

## Still-useful notes

- Property tests on `DeduplicationPlanner` (250 scenarios per seed): plan items point to input clusters, non-high-confidence clusters get no automatic deletes, pair kinds toggle independently, plan items are unique by path, pair Keep-wins across all decision sources, no cluster is fully emptied. All six now run (the two that were skipped were unskipped by e5cd82e).
- The invariant linter (`script/check_agents_invariants_have_tests.sh`) is in CI; the "16 invariants" count in the May text is out of date, see `AGENTS.md` `## Safety Invariants` for the current list.
- Open from the original "needs deeper testing" list, unverified as of 2026-11-21: two Chronoframe processes against one destination (the lock work in #155 and `DestinationOperationLock` addresses the design, but a cross-process test was not re-checked here); whether `testRealTrashAdapterMovesFileToMacOSTrashAndWritesReceipt` skips silently in CI; mutation testing was never run; whether the failure-threshold question for skipped jobs was ever answered.
