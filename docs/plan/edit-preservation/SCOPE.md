# Edit preservation — scope

Status: **approved in part 2026-11-15** (owner approved widening INV-22 and a new INV-31; stem-based variant link, D-EPR-06, not yet answered and defaulted). Superseded by the plan files in this folder; this file is kept as the rationale. Builds on the review's "Follow-up challenge — edited photos" (`docs/next-half-product-review-2026-11-07.md:182`) and backlog card B8 (`docs/plan/next-half/README.md:59`). Verified by reading code only; no builds or tests were run.

## Current state (read from code)

| Surface | Behavior today | Evidence |
|---|---|---|
| Photos import | Originals only. `.fullSizePhoto`/`.fullSizeVideo` and adjustment data are excluded by design. | `PhotosResourceExportService.swift:93-104`, INV-22, AGENTS.md:130 |
| Organize | Copies media bytes verbatim (edits baked into a JPEG survive). Sidecars (`.xmp`, `.aae`) are not discovered, so they are left behind. | review :186; `MediaDiscovery` allowlist |
| Deduplicate | `.xmp` is the only sidecar and travels with its owner (INV-14). `.aae` is unknown, so it is orphaned when its parent is trashed. Edited and original variants are not linked, so the edited one can be suggested for Delete. | `DeduplicatePairDetector.swift:33` |
| Docs | No user-facing statement that Photos import is originals-only. | FAQ, TROUBLESHOOTING grep |

## Work packages (proposed order; each is independently shippable)

### EP-1 — Docs: say what import preserves (S, ~0.5 day)
- FAQ, TROUBLESHOOTING and the Photos import screen's explanatory copy: "Imports the original photo. Edits made in Photos (crops, filters) are not included."
- No invariant change. App-layer copy change, so a test is still needed (`check_app_layer_changes_have_tests.sh`), or `[skip-app-test-check]` for pure copy.
- Done when: strings catalog updated; FAQ and TROUBLESHOOTING updated; German string folder (`german-localization`) reconciled.

### EP-2 — `.aae` recognized as a dedupe sidecar (S, ~1 day) — touches INV-14
- Add `.aae` to `sidecarExtensions`. iOS names it `IMG_E1234.AAE` or `IMG_1234.AAE` depending on the edit, so `detectSidecars` needs a second matching rule: `IMG_<n>` → `IMG_E<n>.AAE`/`IMG_<n>.AAE` in the same directory.
- **Risk:** the `IMG_E` rule can match across unrelated basenames. Match only the exact numeric tail, and treat more than one owner as shared (INV-14 gate: trash only when every owner is trashed).
- Goal-driven (per CLAUDE.md): write the failing test first (tag `// AGENTS-INVARIANT: 14`), change, then `script/check_agents_invariants_have_tests.sh`.
- Surgical diff only in `DeduplicatePairDetector`; planner and executor already consume `sidecarPaths` generically.
- Done when: tagged tests pass for parent kept, parent trashed, shared owner, and `IMG_E` mapping; invariant script green; coverage gate green.

### EP-3 — Sidecars travel with organized photos (M, ~3–4 days) — completes B8
- `MediaDiscovery` finds `.xmp` (and `.aae`) whose basename matches **exactly one** supported media file in the same directory; ambiguous or orphan companions are listed as unresolved in the plan (B8 scope).
- `CopyPlanBuilder`: companion copies unchanged beside its owner and is renamed in lockstep on collision (`-2` suffixes), so the pair never desyncs.
- `TransferExecutor`: companion is verified, receipted and reverted with the owner. Receipt entry written before mutation.
- Touches safety-critical code (executor, revert): diffs must be surgical, one invariant at a time. Tag tests for no overwrites, receipt-before-mutation and revert hash checks.
- Out (per B8): parsing or rewriting XMP, two-owner RAW+JPEG sidecars (unresolved), other sidecar formats.
- Done when: round-trip test organize → revert leaves destination byte-identical to before; collision test keeps owner and companion names in lockstep; unresolved list shown in preview.

### EP-4 — Photos import: "Originals + edited versions" (L, ~2 weeks) — changes INV-22 wording
Needs explicit owner approval, since it widens the original-only contract.

- **Option:** a toggle on the import screen, default **off** (originals only, unchanged behavior).
- **Export:** for assets that have an edit, also export `.fullSizePhoto`/`.fullSizeVideo` as a separate file with a distinct stem (for example `IMG_0001-edited.JPG`, `-edited.MOV`). The original stays byte-identical. Strictly read-only PhotoKit; `script/check_photos_import_readonly.sh` must stay green.
- **Planner:** `PhotosExportPlanner` gets the variant and reserves the edited stem in the same uniqueness set, so a variant can never collide with another asset's stem (case-insensitive, per #270).
- **Not every edited asset exposes a materialized full-size resource** (review warning). A missing or failed render is recorded as a per-asset failure in the checkpoint and reported in the import summary. No silent fallback to "edits preserved."
- **Live Photos and video:** validate separately before any claim. First release scope: stills only; Live Photo and video edited renders are reported as "not included" until fixtures verify them.
- **Preview:** show the extra storage cost. PhotoKit has no public resource size (D-PIR-05), so show an estimate or count of edited assets only, never a byte total.
- **Checkpoint/resume:** extend the plan-4 checkpoint with variant records; version-bump the JSON, keep backward-compatible read.
- **Interaction with dedupe:** the edited variant must be linked to its original so dedupe does not auto-suggest deleting an intentional edit. See EP-5.
- Done when: fixtures covering edited/unedited, cropped/rotated, color-adjusted, HDR and a third-party edit show original bytes identical, the edited export visually matching Photos, distinct hashes and correct dates; failed variants reported.

### EP-5 — Dedupe knows an edited variant from a duplicate (M, ~1 week; depends on EP-4)
- Recognize the `-edited` stem convention as a related-variant pair: never cluster as high-confidence duplicates, and never auto-select the edited variant for Delete. Keep-wins style: either half kept keeps both.
- Preferable alternative: record the variant link in the organize receipt or `.organize_cache.db` rather than inferring from a filename. Decision needed (see below).
- New invariant candidate: INV-31, "an intentional edited variant is never auto-trashed". Needs a `// AGENTS-INVARIANT: 31` test and a bullet under `## Safety Invariants`.
- Done when: planner tests cover variant kept/trashed/shared; invariant script passes; commit footer counts variants.

## Decisions logged (picked defaults; flip any one)

| ID | Decision | Rationale |
|---|---|---|
| D-EP-01 | Edited export is opt-in, default off. | Keeps INV-22's original-only default and avoids doubling storage unexpectedly. |
| D-EP-02 | Edited variant is a distinct file with a `-edited` stem, never replaces the original. | Original bytes remain the master; matches review acceptance. |
| D-EP-03 | Sidecars: copy unchanged, never parse or rewrite XMP/AAE. | B8 out-of-scope; avoids a fidelity promise. |
| D-EP-04 | Ambiguous sidecars are listed as unresolved, not guessed. | Over-keeping is safe, mis-pairing is data loss. |
| D-EP-05 | Photos edited-render ships for stills first; Live Photo and video later. | Review requires separate validation. |
| D-EP-06 | Variant link inferred from stem for v1 (EP-5), receipt-recorded link as follow-up. | Smallest safe change; revisit if false positives appear. |

## Dependencies and order

EP-1 → EP-2 → EP-3 can run in that order, or EP-1 and EP-2 in parallel (different files). EP-4 → EP-5 follow and need owner approval of the INV-22 wording change plus a new INV-31. EP-3 and EP-4 both touch the staging and transfer path, so run them one at a time.

Total: ~3.5 weeks sequential; the first three (~1 week) close the sidecar gaps with no invariant widening beyond INV-14.

## Out of scope

- Reconstructing editable Photos edits or edit history (no public PhotoKit path).
- Writing to Photos in any form.
- Parsing or rewriting XMP/AAE.
- Round-tripping edits into another app.

## Open questions for the owner

1. Approve widening INV-22 to allow exporting edited renders (EP-4)?
2. Approve a new INV-31 (edited variants never auto-trashed)?
3. Should edited export default to off (recommended) or on?
4. Is a stem convention (`-edited`) acceptable, or must the link live in the receipt?
