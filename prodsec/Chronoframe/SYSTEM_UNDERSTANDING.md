# System Understanding: Chronoframe

> **Status: historical snapshot of 2026-05-24. Do not use it as current architecture, and do not recreate the work it lists as risks.**
> Written as the first artifact of the 2026-05-24 review (pass type REFRESH). Every failure mode it flagged was addressed by the remediation series PR #152 to #160, which added the destination operation lock, immutable dedupe scan snapshot and plan, same-directory quarantine, the schema-v2 mutation journal, the sandbox-aware recovery coordinator and a bounded Live Photo metadata loader. Per-finding status is in [TOP_IMPROVEMENTS.md](TOP_IMPROVEMENTS.md) and [PHASE2_FINDINGS.md](PHASE2_FINDINGS.md). The architecture diagram, core-flow descriptions, on-disk artifact table, breadth-coverage table and performance notes were removed on 2026-11-21 because `AGENTS.md`, `docs/TECHNICAL.md` and `docs/SAFETY_AND_RECOVERY.md` cover them in current form; full text is in git history.

## Durable framing

Chronoframe is a native macOS SwiftUI photo and video organizer (Mac App Store, plus Developer ID notarization). Its central promise is that source files are never modified, moved or deleted. It scans a source folder, resolves each file's date, copies into a date-structured destination, and provides audited revert. `ChronoframeCLI` shares the same engine. Users manage personal, often irreplaceable libraries, so the primary risk is accidental permanent data loss, not remote exfiltration. There are no third-party Swift dependencies.

Trust boundaries (still the model):

| Boundary | Trust |
|---|---|
| User and app | Full trust (single-user app) |
| App and filesystem | Security-scoped bookmarks under App Sandbox; start access before any read or write to a user-selected folder |
| Source folder | Read-only (`O_RDONLY|O_NOFOLLOW`) |
| Drop manifest | Untrusted. Containment check: `SafePathContainment` exists in `ChronoframeCore`; its use on the manifest path was not re-verified (unverified) |
| `.organize_cache.db` | Cache only; hash, size and mtime validated before use |
| Receipts | Trusted at revert, hash-guarded before deletion |

## May 2026 failure modes and where they stand

| Failure (May) | Status |
|---|---|
| Crash mid-transfer | Was already robust (PENDING receipt, `recoverInterruptedRuns`); still true. |
| Crash mid-dedupe strands trashed files | Fixed: PENDING receipt plus spool plus `DeduplicateExecutor.recoverInterruptedRuns` (#152 to #160). |
| Crash mid-reorganize loses up to 24 moves | Fixed: `receiptCheckpointInterval = 1` (`ReorganizeExecutor.swift:416`). |
| Receipt finalization remove-then-rename window | Fixed: atomic rename in `ReceiptDurability.durablyWrite`. |
| `try?` in verify deletes valid copies | Fixed. |
| Reorganize or revert aborts an active transfer | Fixed (`runSessionStore.isRunning` guards in `AppState`). |
| Preview review override lost after scope close | Fixed (`PreviewReviewStore` opens its own scope). |
| `IssueCounter` data race | Fixed (`NSLock`). |
| Invariant script not in CI | Fixed (`ci.yml` `invariants-check`). |
| CodeQL results discarded | Unverified (see TOP_IMPROVEMENTS item 3). |

Failure thresholds (5 consecutive or 20 total failures abort a transfer) are unchanged.

## Open questions from May

1. Does `DeduplicateConfiguration` carry a `hardDelete` field that stale `UserDefaults` could flip? Answered 2026-11-21: no such field exists in `ChronoframeCore` or `ChronoframeAppCore`; `DeduplicateView.swift:514` hard-codes `hardDelete = false` for footer copy only.
2. Is `CHRONOFRAME_PROFILES_PATH` intentionally accepted outside development? Still open: `RuntimePaths.swift:8` reads it unconditionally. Unverified.
3. Does `CODEOWNERS` (`* @Nishith`) match the real GitHub handle? Unverified.
4. Is the `production` GitHub environment configured with required reviewers? Unverified (a repository setting).
