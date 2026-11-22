# Edit preservation — contracts

Plan prefix `EPR`. Read `docs/plan/next-half/AGENT_RULES.md` first. Line numbers are from 2026-11-15; if one has moved, search for the quoted declaration.

Goal: edits the user made are not silently left behind. Close four gaps: say what Photos import preserves, treat `.aae` as a dedupe sidecar, copy `.xmp`/`.aae` companions with organized photos, and optionally export Photos' edited renders next to originals, with dedupe never auto-trashing them. PhotoKit stays read-only; every destination mutation keeps its lock, receipt-before-mutation and verification.

## C-01 Copy (EPR-1)
Wording is fixed here so tests can assert it.
- Photos import screen caption: `Imports the original photo or video. Edits made in Photos, such as crops and filters, are not included.` When the C-04 toggle is on: `Also saves the edited version of each edited photo as a separate file. Edited videos and Live Photos are not included.`
- FAQ entry "Does importing from Photos keep my edits?" and a TROUBLESHOOTING line: originals only by default; the library is never changed.
- Add keys to `Localizable.xcstrings` and `docs/plan/clear-path/strings-app.txt`-style tracking, and a German entry via the `german-localization` flow.

## C-02 Dedupe sidecars (EPR-2) — `ui/Sources/ChronoframeCore/DeduplicatePairDetector.swift`
- `sidecarExtensions` (line 33) becomes `[".xmp", ".aae"]`.
- `detectSidecars(for:)` keeps both existing forms (`photo.xmp`, `photo.jpg.xmp`) for every extension, and adds for `.aae` only: a media file `IMG_<digits>.<ext>` also owns `IMG_E<digits>.aae` in the same directory (case-insensitive). The digit string must match exactly; no prefix, substring or fuzzy match.
- A sidecar with more than one owner is shared; INV-14's gate holds unchanged (trash only when every owner is trashed and no surviving pair partner shares the basename).
- Nothing else changes: `DeduplicationPlanner` and `DeduplicateExecutor` consume `sidecarPaths` generically.
- Tag tests `// AGENTS-INVARIANT: 14`.

## C-03 Organize companions (EPR-3)
Design rule: **a companion is an ordinary copy job**. It flows through the existing planner, `TransferExecutor`, verification, receipt and revert, so those paths are unchanged. Only discovery and planning learn about companions.

1. `MediaLibraryRules` (`MediaDateResolver.swift:4`) gets `companionExtensions: Set<String> = [".xmp", ".aae"]` and `isCompanionFile(path:)`. `allExtensions`, `isSupportedMediaFile` and the dedupe/guardian scanners are **unchanged**, so no other surface starts seeing companions.
2. Discovery returns companions separately from media (`MediaDiscovery`, near `:128` and `:353`): a companion is never a media entry and never counted in media totals. Hidden files (`shouldSkipDiscoveredFile`) are still skipped.
3. Owner resolution, a pure function in `ChronoframeCore` (`CompanionResolver`): a companion belongs to a media file in the **same directory** when its name equals `<media stem>.<ext>` or `<media full name>.<ext>`, plus the C-02 `IMG_E` rule for `.aae`, all case-insensitive. Eligible owners are media files only. Exactly one eligible owner → resolved. Zero or more than one (for example `photo.xmp` beside `photo.raw` and `photo.jpg`, or a RAW+JPEG pair) → **unresolved**.
4. Planning (`CopyPlanBuilder`): after the owner's destination path is final, including collision naming and duplicate-directory placement, the companion's destination is the owner's destination path with the companion's real extension appended in the same form it had (`IMG_1.xmp` → `IMG_1.xmp`; `IMG_1.jpg.xmp` → `<owner dest name>.xmp`). It lands in the same directory as its owner. It is never planned independently, so it cannot be renamed apart from its owner. A companion whose owner is skipped, already present or excluded is skipped with it.
5. If the companion's computed destination already exists, the companion is skipped and reported (INV: no overwrites; no collision renaming of companions apart from the owner).
6. The plan carries `unresolvedCompanions: [String]` (source paths) and the preview lists them with `Not copied: <name> (matches more than one photo)` / `(no matching photo)`. Counts appear in the preview summary; they never block the run.
7. Receipt and revert: companion jobs are normal jobs, so receipt-before-mutation, hash-verified copy and hash-checked revert apply. Revert removes a companion with its owner and no other way.
8. Cache: companions use the existing `FileCache`/`CopyJobs` tables unchanged (D-EPR-11).
9. Free-space estimates, progress counts and the "Copied N files" summary count companions as files; summary copy says `N photos and videos, M sidecar files`.
10. Source is read-only; nothing is written beside sources.

Invariants to tag: no overwrites; receipt-before-mutation; revert hash checks; source read-only (numbers per AGENTS.md at WP time).

## C-04 Photos edited export (EPR-4) — INV-22 widened (approved)
Replace the first sentence of INV-22 after "…copies each selected asset's" with: "**original** resources, and, only when the user turns on *Include edited versions* for that import, each edited still photo's current edited render (`.fullSizePhoto`)…". The rest of INV-22 is unchanged: only read-only PhotoKit APIs, no `performChanges`, no change requests, `script/check_photos_import_readonly.sh` stays green. AGENTS.md:130 is updated to match.

Model changes (`ChronoframeAppCore/Services/PhotosExportExecutor.swift`, `PhotosResourceExportService.swift`, `ChronoframeCore/PhotosExportPlanner.swift`):
- `PhotosExportableResource` gains `role: Role` (`.original`, `.editedRender`), default `.original` so every existing call site and test double compiles.
- `PhotosResourceExporting.originalResources(forAssetID:)` is unchanged. A new method `editedStillResource(forAssetID:) async throws -> PhotosExportableResource?` returns the `.fullSizePhoto` resource when the asset has one, else `nil`. Default implementation returns `nil` (test doubles keep compiling). Read-only: `PHAssetResource.assetResources(for:)` and `PHAssetResourceManager.writeData`.
- `isOriginalImportableType` is unchanged. A separate `isEditedStillType` accepts only `.fullSizePhoto`. `.fullSizeVideo`, `.adjustmentData` and everything else stay excluded (D-EPR-07, D-EPR-08).
- Naming: the edited file's stem is `<entry.stagingStem>-edited`, extension from the resource's own filename (a HEIC original usually has a JPEG render). It goes through the executor's existing unique-name claim (`nameKey`, case-insensitive) in the same `usedFilenames` set, so it can never collide with another asset's file.
- `PhotosAssetExportEntry`/`PhotosExportPlan` do not change shape. The option is an executor parameter `includeEditedVersions: Bool` (default `false`), also stored in the checkpoint so Resume repeats the same choice.
- Failure: if the asset claims an edit but the render cannot be fetched, record a per-asset variant failure `editedRenderUnavailable` in the checkpoint and import summary. The original is still exported and the asset is still "completed". No retry of failed variants on Resume (matches current failed-asset behavior). No silent fallback: the summary says `N edits could not be saved`.
- Dates: the edited file gets the original's `SourceDateHint` / `creationDate` fallback so both land in the same date folder.
- Checkpoint: JSON version bump with `includeEditedVersions` and per-asset `editedFile: PhotosExportedFile?`. Older checkpoints decode with `false`/`nil`.
- Preview summary shows `N edited photos will also be saved`. No byte total (D-PIR-05: no public PhotoKit size).

## C-05 Import UI (EPR-4)
- Toggle `Include edited versions` in the Photos import options, default off, with the C-01 caption. Persisted only for the current import (not an app-wide setting).
- Run summary and history show `Originals: N · Edited versions: M · Could not save: K`.

## C-06 Edited-variant protection, INV-30 (EPR-5)
Text for AGENTS.md `## Safety Invariants` (number 30):

> **INV-30:** An edited variant exported from Apple Photos (`<stem>-edited.<ext>` beside `<stem>.<ext>` in one folder, matched case-insensitively) is never Trashed unless the user explicitly marks that file Delete. It is never selected by a cluster's automatic suggestion, never added by pair, sidecar or fanout rules, and is never a deletion consequence of its original being Deleted. Deleting the original leaves the variant in place.

Implementation constraints:
- `DeduplicatePairDetector` gets `Pair.Kind.editedVariant` (stem rule above, same directory). The planner treats the variant side as **protected**: it contributes `Keep` to its unit, and the only way it appears as a Delete target is an explicit user Delete on that exact path.
- A variant is still a normal photo in clusters, so a user can review it. Only automatic selection and fanout are blocked.
- Commit footer counts `N edited versions kept`.
- Plans stay derived from immutable scan snapshots with expected identity; `DeduplicationPlanner.plan` remains the single source (CLAUDE.md).
- Tag tests `// AGENTS-INVARIANT: 30`; add the bullet to AGENTS.md; `script/check_agents_invariants_have_tests.sh` must pass.

## C-07 Docs
`docs/SAFETY_AND_RECOVERY.md`, `docs/TECHNICAL.md` (Photos import paragraph, Organize and Deduplicate sections), `docs/FAQ.md`, `AGENTS.md` (INV-22 wording, INV-14 `.aae`, INV-30, :130) updated in the WP that changes the behavior, not at the end.
