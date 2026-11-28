# Edit preservation — decisions

Plan prefix `EPR`. Runtime decisions go at the bottom as `D-EPR-1NN`. Status tags: **approved** (owner said so), **default** (picked under the tie-break, flip freely), **proposal**.

## Tie-break rule for new gaps
Choose the option that, in order: (1) keeps every `AGENTS.md` safety invariant; (2) changes the fewest existing files and lines; (3) copies an existing pattern from the reference file the WP names; (4) fails closed (refuse, mark unresolved, keep files, never delete). Log it as `D-EPR-1NN` with WP ID, options, choice. Never use the tie-break to weaken a safety rule; log that in `BLOCKED.md` instead.

## Scope and process
- **D-EPR-01 Branch (approved by owner 2026-11-27).** `feature/edit-preservation` was used for the plan and merged in #298, so implementation runs on `feature/edit-preservation-impl` from `origin/main` @ f1c5540, with the D-EPR-12 plan fix as its first commit. `main` already contains Photos import resume (#268), so no stacking. Push and PR per D-EPR-17. WP-00 stops with a BLOCKED entry if tracked files are modified (the checkout had many modified tracked files on 2026-11-15; see B-1).
- **D-EPR-02 Plan location (default).** `docs/plan/edit-preservation/`. Shared rules: `docs/plan/next-half/AGENT_RULES.md`.
- **D-EPR-03 Test placement (default).** Core and AppCore tests in `ui/Tests/ChronoframeAppCoreTests/`; App tests in `ui/Tests/ChronoframeAppTests/`. No XCUITests; `project.pbxproj` is never edited.
- **D-EPR-04 Invariants (approved 2026-11-15).** INV-22 is widened (EPR-4, wording in C-04). A new **INV-31** is added (C-06). INV-14 is extended to `.aae` (C-02). `INV-27…29` are already taken (NAS assessment, NAS destinations, saved Deduplicate review), so the number was 30 at approval; renumbered to **31** on 2026-11-27 (D-EPR-12).

## Product decisions
- **D-EPR-05 Edited export is opt-in, default off (approved by owner 2026-11-27).** Off keeps today's behavior and today's storage footprint.
- **D-EPR-06 Variant link is a stem convention for v1 (approved by owner 2026-11-27).** An edited variant is `<stem>-edited.<ext>` beside `<stem>.<ext>` in the same folder. Receipt-recorded links are a follow-up if the convention produces false positives. A user file that happens to be named `x-edited.jpg` beside `x.jpg` is protected by the same rule, which fails closed (it is never auto-trashed).
- **D-EPR-07 Stills only first (approved by owner 2026-11-27).** Edited renders of Live Photos and videos are not exported in v1; the import summary says "N edited videos / Live Photos not included". Claims for them need fixtures first (review, line 194).
- **D-EPR-08 Sidecars are copied byte-for-byte, never parsed or rewritten (approved by owner 2026-11-27).** No XMP/AAE fidelity promise.
- **D-EPR-09 Ambiguous or orphan companions are unresolved, never guessed (approved by owner 2026-11-27).** A companion with zero or more than one eligible owner is listed and not copied. Over-keeping is safe; mis-pairing is not.
- **D-EPR-10 Companion extensions (approved by owner 2026-11-27).** `.xmp` and `.aae` only. `.aae` also matches the iOS `IMG_E<n>.AAE` → `IMG_<n>.*` form (C-02).
- **D-EPR-11 No cache or schema migration (approved by owner 2026-11-27).** Companions are ordinary copy jobs, so `.organize_cache.db` and receipt JSON keep their schema (C-03). If WP-03's spike shows a schema change is unavoidable, apply D-EPR-16.

## Owner answers at kickoff (2026-11-27)
- **D-EPR-13 Checkpoint version (approved by owner 2026-11-27).** C-04's version bump goes to 2, and `PhotosImportFileCheckpointStore.load` accepts version 1 or 2 (today it rejects any version but the current one, which would strand imports interrupted before the update). A version-1 checkpoint decodes with `includeEditedVersions = false` and no `editedFile`.
- **D-EPR-14 Companion destination clash (approved by owner 2026-11-27).** When a companion's computed destination equals another planned destination (for example `IMG_1234.AAE` and `IMG_E1234.AAE`, both owned by `IMG_1234.HEIC`, map to `<owner dest stem>.AAE`), every clashing companion is not copied and is listed as not copied in the preview. Fails closed; the owner's photo still copies.
- **D-EPR-15 Import counts in the summary only (approved by owner 2026-11-27).** No Photos-specific history record exists, so C-05's `Originals: N · Edited versions: M · Could not save: K` line appears in the import run summary only. No new history schema.
- **D-EPR-16 Schema change escalation (approved by owner 2026-11-27).** If WP-03 shows a cache or receipt schema change is unavoidable, log it in BLOCKED.md with the proposed diff, skip WP-04 and the companion parts of G1, and continue with WP-05 to WP-08 and G2.
- **D-EPR-17 Finish (approved by owner 2026-11-27).** At the very end, push `feature/edit-preservation-impl` once and open a ready-for-review PR. No G2 screenshots; "Verified" stays not claimed (the Photos import screen would request access to the real Photos library).
- **D-EPR-18 Stale citations (orchestrator, 2026-11-27).** C-06 still says "(number 30)" and the WPs cite `AGENTS.md:130` for the Photos import bullet. Per D-EPR-12 the number is 31; the Photos bullets are now `AGENTS.md:122`–`123` (section "Apple Photos Import"). Implementers use the current locations.

## Runtime decisions
(Appended by the orchestrator as `D-EPR-1NN`.)
- **D-EPR-12 Invariant number (2026-11-27).** `find-and-account` claims INV-30 (evidence-bound completion accounting) and comes first in the plan sequence, so this plan's edited-variant invariant is INV-31 and its tests are tagged `// AGENTS-INVARIANT: 31`. Ids are permanent: if this plan lands first, it still takes 31 and leaves 30 to find-and-account. Same rule, same owner approval as D-EPR-04.
- **D-EPR-101 Caption helper (WP-01, default).** Options: extend `PhotosPreparationText` or add a new helper. Chose a new `PhotosImportEditsCaption` enum (`ui/Sources/ChronoframeApp/Views/Photos/PhotosImportEditsCaption.swift`) holding both C-01 strings; the view passes `includeEditedVersions: false` until WP-07 wires the toggle. Fewest lines touched in existing files.
- **D-EPR-102 `.aae` paths use on-disk spelling (WP-02, default).** iPhone writes `.AAE`; building `stem + ".aae"` would return a lower-case path on case-insensitive APFS (receipt and revert would then use a spelling the file never had) and miss the file on case-sensitive volumes. Options: 1) keep constructed paths; 2) resolve every sidecar extension against directory entries case-insensitively; 3) resolve only `.aae` (new behavior) and leave `.xmp` byte-for-byte. Chose 3: fails closed, keeps the INV-14 `.xmp` path unchanged (surgical). The same latent spelling issue for `.XMP` is pre-existing and flagged for a follow-up, not fixed here.
