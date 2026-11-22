# Edit preservation — decisions

Plan prefix `EPR`. Runtime decisions go at the bottom as `D-EPR-1NN`. Status tags: **approved** (owner said so), **default** (picked under the tie-break, flip freely), **proposal**.

## Tie-break rule for new gaps
Choose the option that, in order: (1) keeps every `AGENTS.md` safety invariant; (2) changes the fewest existing files and lines; (3) copies an existing pattern from the reference file the WP names; (4) fails closed (refuse, mark unresolved, keep files, never delete). Log it as `D-EPR-1NN` with WP ID, options, choice. Never use the tie-break to weaken a safety rule; log that in `BLOCKED.md` instead.

## Scope and process
- **D-EPR-01 Branch (default).** `feature/edit-preservation` from `main`. `main` already contains Photos import resume (#268), so no stacking. Never push; the owner opens the PR. WP-00 stops with a BLOCKED entry if tracked files are modified (the checkout had many modified tracked files on 2026-11-15; see B-1).
- **D-EPR-02 Plan location (default).** `docs/plan/edit-preservation/`. Shared rules: `docs/plan/next-half/AGENT_RULES.md`.
- **D-EPR-03 Test placement (default).** Core and AppCore tests in `ui/Tests/ChronoframeAppCoreTests/`; App tests in `ui/Tests/ChronoframeAppTests/`. No XCUITests; `project.pbxproj` is never edited.
- **D-EPR-04 Invariants (approved 2026-11-15).** INV-22 is widened (EPR-4, wording in C-04). A new **INV-30** is added (C-06). INV-14 is extended to `.aae` (C-02). `INV-27…29` are already taken (NAS assessment, NAS destinations, saved Deduplicate review), so the number is 30, not the 27 used in SCOPE.md.

## Product decisions
- **D-EPR-05 Edited export is opt-in, default off (default).** Off keeps today's behavior and today's storage footprint.
- **D-EPR-06 Variant link is a stem convention for v1 (default; owner question open).** An edited variant is `<stem>-edited.<ext>` beside `<stem>.<ext>` in the same folder. Receipt-recorded links are a follow-up if the convention produces false positives. A user file that happens to be named `x-edited.jpg` beside `x.jpg` is protected by the same rule, which fails closed (it is never auto-trashed).
- **D-EPR-07 Stills only first (default).** Edited renders of Live Photos and videos are not exported in v1; the import summary says "N edited videos / Live Photos not included". Claims for them need fixtures first (review, line 194).
- **D-EPR-08 Sidecars are copied byte-for-byte, never parsed or rewritten (default).** No XMP/AAE fidelity promise.
- **D-EPR-09 Ambiguous or orphan companions are unresolved, never guessed (default).** A companion with zero or more than one eligible owner is listed and not copied. Over-keeping is safe; mis-pairing is not.
- **D-EPR-10 Companion extensions (default).** `.xmp` and `.aae` only. `.aae` also matches the iOS `IMG_E<n>.AAE` → `IMG_<n>.*` form (C-02).
- **D-EPR-11 No cache or schema migration (default).** Companions are ordinary copy jobs, so `.organize_cache.db` and receipt JSON keep their schema (C-03). If WP-00's spike shows a schema change is unavoidable, stop and log BLOCKED.

## Runtime decisions
(Appended by the orchestrator as `D-EPR-1NN`.)
