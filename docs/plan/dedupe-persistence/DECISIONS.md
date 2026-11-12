# Dedupe persistence — decisions

Prefix `DDP`. Runtime decisions appended as `D-DDP-1NN`.

## Tie-break rule for new gaps
Keep every invariant (INV-06, 12, 14, 17, 18, 20 and the new INV-29 above all); fewest changed lines; copy the named reference pattern; fail closed (drop a saved choice rather than apply it). Log as `D-DDP-1NN`; safety weakening goes to `BLOCKED.md`.

- **D-DDP-01 Branch.** `feature/dedupe-persistence` stacked on `feature/nas-v1` at `4079fb1` (owner decision 2026-11-11: nas-v1 is unmerged and `main` lacks `docs/plan/` and INV-28). Rebase or merge after nas-v1 lands. Guards use base ref `feature/nas-v1`. Never push.
- **D-DDP-02 Identity, not path, is the key.** A saved choice is restored only when `scanSnapshot.identitiesByPath[path] == saved.identity`. Group approvals are keyed by sorted member identities because cluster UUIDs are regenerated each scan.
- **D-DDP-03 Decisions restore regardless of settings; the banner says when settings changed.** Content-identical files keep their Keep/Delete choice under any threshold. Approvals are protected by member identity, so a different threshold that regroups files simply yields unmatched (changed) groups.
- **D-DDP-04 Changed content clears the choice and un-approves the group.** No "stale Delete" can survive: a changed member drops its decision, and C-02 rule 4 withholds approval for its group.
- **D-DDP-05 Storage location.** Application Support `dedupe_reviews/<folderKey>.json`, one file per dedupe root. Not in the root's `.organize_cache.db`: the root may be read-only to us during review, and `ReviewOverrides` semantics (Organize) differ.
- **D-DDP-06 Lifecycle.** Saved on every change (debounced), on pause, cancel, reset and app termination. Removed on successful commit for that folder and on explicit Discard. Changing folder never removes it.
- **D-DDP-07 Saving is best-effort and silent.** A failed save (disk full, permissions) is not surfaced during review; the next relaunch simply has an older snapshot. Reviewer checks that no user-facing error is invented for this path.
- **D-DDP-08 Focus is the cluster key.** `reviewFocusClusterID` is set by the view; captured as the group key; restored to the matching cluster if any.
- **D-DDP-09 No undo for the restore itself.** Restoring happens before the user acts; registering it would make the first ⌘Z discard the whole restore. The user can "Discard Saved Review" from the idle card or change choices normally.
- **D-DDP-10 `pairKeepOverrides` and `hardDelete` are not persisted.** The UI never writes overrides; `hardDelete` is forced false by `DedupeDecisions.init`.
- **D-DDP-11 Test placement.** Core tests `ui/Tests/ChronoframeAppCoreTests/ChronoframeCoreDeduplicateReview*Tests.swift`; store tests in a new `DeduplicateReviewPersistenceTests.swift` alongside `DeduplicateSessionStoreTests.swift`; App tests `ui/Tests/ChronoframeAppTests/DeduplicateReview*Tests.swift`.
- **D-DDP-12 New invariant INV-29** added at G1 by the orchestrator with the exact C-07 text.

## Runtime decisions
- **D-DDP-101 Approval needs every member's own saved choice restored (orchestrator, WP-01).** `FileIdentity` is content-only, so a group key does not bind paths. A cluster is restored as approved only when key and member count match **and** every member path had a saved decision restored. Stricter than C-02 rule 4; fail closed. Covers renamed/moved members and two clusters with the same identity multiset.
- **D-DDP-102 Empty cluster has no group key** (`groupKey(for:snapshot:)` returns nil).
- **D-DDP-103 Fingerprint text.** Every `DeduplicateConfiguration` field except `workerCount` in declaration order, `destinationPath` included, `videoPerceptualMatchConfiguration` flattened; `additionalSources` entries joined by U+001E, their fields by U+001F; SHA-256 lowercase hex. A format change only flips `settingsChanged`.
- **D-DDP-104 `capture` output.** `folderPath` standardized; decisions sorted by path; every decision with a scan identity is kept (not only cluster members); approvals in cluster order; focus nil when the focus cluster has no key.
- **D-DDP-105 Counts.** `restoredGroupCount = approvedClusterIDs.count`; `changedGroupCount = max(0, approvals.count − restoredGroupCount)`; focus mapping is independent of approval.
- **D-DDP-106 "Member of some cluster" means `members[].path`.** The session store only keys decisions by member path; paired and sidecar paths never appear in `byPath`.
- **D-DDP-107 Only a touched review is saved (orchestrator, WP-02).** `saveNow()` writes only after a user action or an applied restore (`reviewHasUserChanges`). Untouched suggestions never create a saved review, so no card or banner appears for work the user did not do. Consequence: after a restore, the next save overwrites the file with current state, so choices dropped because a file changed are gone from disk too (fail closed).
- **D-DDP-108 `startScan` flushes a pending save first**, under the previous scan's folder, before any state is cleared.
- **D-DDP-109 XCTest default directory.** `DeduplicateReviewFileSnapshotStore.defaultDirectory()` returns a fresh temp directory per call when `XCTestCase` is loaded (same guard as `SpotlightIndexer`), so default-constructed stores in existing tests never touch real Application Support. Those temp directories are not cleaned up.
- **D-DDP-110 Commit removal applies to forward commits only**; a revert never removes a saved review. `cancel()` and `pauseReview()` save only when the review guard passes (a cancel during scanning writes nothing).
- **D-DDP-111 Extra tests beyond the plan's list:** `testCancelSavesImmediately`, `testUntouchedReviewIsNotSaved`, `testRestoredReviewIsSavedAgainOnPause`, `testStartScanFlushesPendingSave`, and three D-DDP-101 restorer tests.
