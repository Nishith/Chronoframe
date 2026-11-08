# Next-half implementation plans (Nov 2026 – Apr 2027)

Status: **proposal**, prepared 2026-11-07 from the Round 3 ranking in [`docs/next-half-product-review-2026-11-07.md`](../../next-half-product-review-2026-11-07.md). Nothing here changes product behavior until a plan's orchestrator runs and Nishith merges its branch.

Owner decisions recorded 2026-11-07: ranks 1–5 at full depth, ranks 6–10 as backlog cards; finish NAS on `feature/nas-v1`, then one branch and one plan folder per feature; Opus orchestrates, Sonnet implements and reviews, Haiku does data entry; agents never touch App Review, StoreKit, hardware checks or release flag values.

## Run order

| # | Plan folder | Branch | Base | Prefix | Rank in review |
|---|---|---|---|---|---|
| 1 | [`nas-public/`](../nas-public/) | `feature/nas-v1` (existing) | — | `NASP` | 1 — take NAS v1 public |
| 2 | [`dedupe-persistence/`](../dedupe-persistence/) | `feature/dedupe-persistence` | `main` after #1 merges | `DDP` | 2 — dedupe review survives relaunch |
| 3 | [`photos-import-resume/`](../photos-import-resume/) | `feature/photos-import-resume` | `main` after #2 merges | `PIR` | 3 — visible, cancellable, resumable Photos import |
| 4 | [`find-and-account/`](../find-and-account/) | `feature/find-and-account` | `main` after #3 merges | `FAA` | 4 — item-level reconciliation and original-name lookup |
| 5 | [`first-ten-minutes/`](../first-ten-minutes/) | `feature/first-ten-minutes` | `main` after #4 merges | `FTM` | 5 — preflight, free batch, proof |

Each plan is self-contained: `CONTRACTS.md`, `DECISIONS.md`, `IMPLEMENTATION_PLAN.md`, `PROGRESS.md`, `ACCEPTANCE_MATRIX.md`, `BLOCKED.md`, `EVIDENCE_LEDGER.md`. Shared files live here: [`AGENT_RULES.md`](AGENT_RULES.md), [`bin/cf_swift.sh`](bin/cf_swift.sh), [`ORCHESTRATOR_KICKOFF.md`](ORCHESTRATOR_KICKOFF.md), [`claude-config/`](claude-config/) (install into the gitignored `.claude/`).

Plans 2–5 may be reordered by the owner; each `DECISIONS.md` D-01 names its base and must be edited if the base changes. Plan 4 reuses the receipt-mapping index that plan 3's checkpoint file does not need, so they are independent; plan 5 reads plan 3's staging estimate and plan 4's outcome index when present, and degrades to "not estimated" when absent (its contracts say how).

## Preconditions that are not plans

- **Build 508 App Review.** Owner-only. No plan edits StoreKit configuration, purchase code, or App Store metadata.
- **NAS hardware checks H1–H8.** Owner-only; see `docs/plan/nas-v1/EVIDENCE_LEDGER.md`. Plan 1 adds the rows that depend on them to its own ledger and leaves them `todo-hardware`.
- **Release flag flips** (`NASCapability.isEnabled` release value). Owner-only, after the ledger rows read `pass-hardware`.

## Backlog cards (ranks 6–10; not planned this pass)

Each card is the seed of a future plan folder. Scope lines are the Round 3 boundaries; nothing below is approved for implementation.

### B6 — Batch camera-clock correction (`feature/batch-clock`)
- **Job:** a camera's clock was wrong for a trip; shift every selected item's capture time by one offset, or assign one date, with before/after preview and one-step undo.
- **Builds on:** per-item date editing in `PreviewReviewPanel`, durable `ReviewOverrides`, the conflicting-date review on this branch.
- **Scope:** selection by folder, camera model or date range inside the current preview; offset shift preserves relative times; assignment sets one date; preview lists before/after date and destination folder per item; accept writes overrides, never source metadata; undo removes exactly the overrides the batch wrote.
- **Out:** editing EXIF, cross-run batches, Live Photo halves getting different offsets (units move together).
- **Invariants to tag:** source read-only; review gate before copy.

### B7 — Protected folders, then keeper preference (`feature/protected-folders`)
- **Job:** "never Trash anything in my curated album" and, later, "when copies are equivalent, keep the one in this folder".
- **Builds on:** `DeduplicateModels` keeper-priority substrate; `DeduplicationPlanner.plan` as the single plan source.
- **Scope, slice 1 (protection):** a protected-subfolder list within the selected dedupe root; the planner refuses any destructive target inside a protected path and any pair/sidecar unit that contains one; the commit footer shows protected counts. **Slice 2 (preference):** a preferred-subfolder list that only breaks ties among equivalents.
- **Out:** cross-root protection, Organize-source protection (sources are already read-only), near-duplicate auto decisions.
- **Invariants to tag:** Trash-only; plan integrity/expected identity; Keep-wins pair/sidecar.

### B8 — Existing XMP companions travel with organized photos (`feature/xmp-companions`)
- **Job:** a Lightroom user's `.xmp` ratings and edits are left behind by Organize today.
- **Builds on:** dedupe's sidecar discovery; `MediaDiscovery` extension allowlist; collision renaming in `CopyPlanBuilder`.
- **Scope:** discover `.xmp` whose basename matches exactly one supported media file in the same directory; copy unchanged beside the owner, renamed in lockstep on collision; verified, receipted and reverted with the owner; ambiguous or orphan companions listed as unresolved in the plan.
- **Out:** parsing or rewriting XMP, shared RAW+JPEG sidecars with two owners (unresolved), other sidecar formats.
- **Invariants to tag:** no overwrites; receipt before mutation; revert hash checks.

### B9 — Verify my archive (scrub-only Guardian) (`feature/guardian-verify`)
- **Job:** "has anything in my archive changed or gone missing since I last checked?"
- **Builds on:** `GuardianLibraryProbe`, `GuardianIntegrityClassifier`, `GuardianManifestStore`, `GuardianScheduler`.
- **Scope:** a Verify workspace behind a new `GuardianVerifyCapability` flag: establish a trusted baseline from a verified Organize receipt, scrub on demand or on the in-app schedule, report unchanged / changed / missing with dates and the exact paths, export the list. Copy for a changed or missing file says to restore it from a backup; it never offers restore.
- **Out:** mirror, restore, any write to the library, a single "safe" score, a background daemon.
- **Invariants to tag:** Guardian scrub read-only; newly observed files never gain trust automatically.

### B10 — Google Takeout rescue, narrow (`feature/takeout-dates`)
- **Job:** an extracted Takeout folder where JSON sidecars carry the real capture dates.
- **Builds on:** the conflicting-date review and alternative-date action on `feature/nas-v1`; B8's companion rule.
- **Scope:** for `name.ext` match exactly one of `name.ext.json`, `name.ext.supplemental-metadata.json` or the truncated-name variant Google documents, in the same directory; read `photoTakenTime.timestamp` as an alternative date shown in the existing conflicting-date review, never applied automatically; copy the JSON as a companion when B8 exists, otherwise leave it and say so.
- **Out:** Google login, album JSON, edited-variant `-edited` files, any date rewrite without review.
- **First to drop** if customer recruitment finds no demand.
