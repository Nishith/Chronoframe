# Dedupe persistence — decisions

Prefix `DDP`. Runtime decisions appended as `D-DDP-1NN`.

## Tie-break rule for new gaps
Keep every invariant (INV-06, 12, 14, 17, 18, 20 and the new INV-29 above all); fewest changed lines; copy the named reference pattern; fail closed (drop a saved choice rather than apply it). Log as `D-DDP-1NN`; safety weakening goes to `BLOCKED.md`.

- **D-DDP-01 Branch.** `feature/dedupe-persistence` from `main` after `feature/nas-v1` merged. Never push.
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
