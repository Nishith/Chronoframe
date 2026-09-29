# Version 2.0 — manual release session, part 1 (local)

Date: 2026-09-28. Scope and pass conditions: `docs/remaining-work-plan.md` § "Version 2.0 Release
Scope".

**What was tested.** A pre-merge integration of every open 2.0 pull request (#217–#234, including #226,
plus #212 and version 2.0) on top of `main` at `d363818`, integration commit `b296eb8` (not pushed).
Mac App Store flavour (`MAS_BUILD`), Release configuration, ad-hoc signed with the shipping sandbox
entitlements: **Chronoframe 2.0 (481)**, bundle `com.nishith.chronoframe`, arm64 + x86_64,
minimum macOS 14. macOS 27 on Apple silicon. The organize, recovery, upgrade and performance
checks drive the same `ChronoframeCore` engine through `ChronoframeCLI` (Release build); the dedupe
check drives the app's `NativeDeduplicateEngine`. Comparison baseline: `v1.1.297`.

**This is not the Go evidence.** It must be repeated on the final merged commit, and the rows
marked *TestFlight* need the signed TestFlight build and a person at the Mac.

All fixtures were synthetic and disposable: dated JPEGs, exact duplicates, a same-day filename
collision, composed and decomposed Unicode names, a RAW+JPEG pair, a HEIC+MOV pair, an MP4, an XMP
sidecar, a non-media file and a symlink escaping the source; plus 1,000-file and 10,000-file
(9,800 photos, 200 videos, 155 MB) libraries.

## Results

| Check | Result | Evidence |
|---|---|---|
| Copy, repeat, revert | **PASS** | 32 of 32 copies byte-identical to their sources; receipt `COMPLETED`, verification on. Exact duplicates filed under `Duplicate/`; same-day name collision became `_001`/`_002`; non-media file and escaping symlink skipped; the symlink's target unchanged. Repeat run: "Nothing to copy". A new same-day photo became `_002`, `_001` unchanged. Revert: 31 reverted, the one copy edited after transfer **preserved**, a later receipt's file untouched. Source tree byte-identical throughout. |
| Interrupt and recover (internal disk) | **PASS** | `kill -9` at ~2,500 of 10,000. Relaunch recovered the run as `ABORTED` and copied the remaining 7,488; a second relaunch copied nothing. Final: 10,000 distinct files, each byte-identical to a source, none twice, no temp files left; receipts 2,512 + 7,488. Reverting the aborted run removed its 2,512 files; reverting again was a no-op ("2512 already missing"). |
| Dedupe and restore | **PASS**, with finding F2 | Real scan → plan → commit to the real macOS Trash → revert on fixtures. Four exact-duplicate groups; exactly the four planned files trashed, Trash bytes equal the originals; the paired JPEG kept, its `.CR2` and the XMP sidecar untouched; revert restored every file byte-for-byte (36 files before and after). The synthetic HEIC+MOV lacks Apple's content identifier, so Live Photo Keep-wins was not exercised here (unit-tested). |
| Upgrade from 1.x | **PASS** (engine level) | Destination organized by `v1.1.297` (receipt schema 2, cache DB version 0). 2.0 migrated the cache (added `DedupeMutationIdentities`), treated all 32 files as already present, placed a new photo correctly and reverted the 1.1 receipt. Settings, bookmarks and folder access across an App Store upgrade: *TestFlight*. |
| External drive — APFS image | **PASS**, with finding F3 | Transfer to an attached APFS disk image, force-ejected mid-run: copies failed, the run stopped after 5 failures and said to reconnect the drive; nothing crashed. After reattaching, recovery completed and the volume held all 10,000 files, none twice, no temp files. |
| External drive — exFAT image | **FAIL** — finding F1 | Every copy fails. |
| Performance, 1,000 files | Recorded | v1.1 → 2.0: preview 0.29 s → 0.33 s; verified transfer 9.7 s → 10.7 s (≈ +10 %). |
| Performance, 10,000 files | Recorded | Cold verified transfer 107 s, peak RSS 272 MB; warm rescan 3.0 s, peak RSS 327 MB, 0 new files; Ctrl-C exits within 0.09 s (see F5). |
| Fresh install and persistence; Photos import; StoreKit; usability (light/dark, keyboard, VoiceOver); a physical drive | *TestFlight* | Not run: they need the signed TestFlight build, Photos-library permission, a sandbox Apple Account, or a person at the Mac. The candidate was not launched outside its UI-test scenarios because it would open the real app container. |

## Findings

| # | Finding | Since | Severity (proposed) |
|---|---|---|---|
| F1 | **Organizing onto an exFAT volume fails for every file** ("Operation not supported"). The final no-overwrite rename uses `renamex_np(…, RENAME_EXCL)`, which the macOS 27 FSKit exFAT driver rejects with `ENOTSUP` (plain `rename` works; `clonefile` is also unsupported). The run stops after 5 failures and originals are untouched. External drives are advertised and are commonly exFAT. | v1.1 or earlier (v1.1.297 fails the same way) | P1 if exFAT destinations are supported |
| F2 | **Deduplicated files are hidden in the Trash.** Each target is renamed to `.chronoframe-quarantine-<UUID>-<name>` before `trashItem`, and that dot-prefixed name is what lands in the Trash, so Finder does not show them and "Put Back" is unavailable. Chronoframe's own Revert restores them correctly. | New since v1.1.297 (quarantine landed after it) | P2 |
| F3 | After a drive disconnect, the first recovery run reports "Transfer complete" but skips the files whose copies failed during the disconnect (4–5 files); the next ordinary run copies them. No loss or duplication. | v1.1 as well | P2 |
| F4 | Videos never read embedded capture metadata; they fall back to filename, then file creation date. A Live Photo's MOV can land in a different day folder than its HEIC when file dates were not preserved. | v1.1 as well | P3 |
| F5 | The CLI has no SIGINT handler: Ctrl-C leaves a `PENDING` receipt and temp files, recovered on the next run (same path as a force quit). The app's Cancel is unaffected. | — | P3 |
| F6 | During a disconnect the per-file CLI errors read "You don't have permission to save the file…" (macOS's wording for a vanished volume); the final message correctly says to reconnect. | — | P3 |
| F7 | The organize receipt finalization and the dry-run/preview reports still use `<name>.tmp` + `FileManager.createFile` rather than the exclusive `O_EXCL | O_NOFOLLOW` helper. Probed: a planted link is replaced, not written through; only a narrow create-then-reopen window remains. Invariant 26 (#231) now states this exactly. | — | P3 |

Local automated baseline on the integration (2026-09-28): full SwiftPM lane 0 failures; all 13 CI
guards and the site check pass; 24 of 24 UI tests pass; meaningful coverage 95.52 % on `main` with
#233; Release build succeeds. The accessibility audit is validated on hosted CI (macOS 14); locally
on macOS 27 it stops on the sidebar "LIBRARY" heading.

## Open for the Go decision

F1 (exFAT organize fails for every file) and F2 (deduplicated files are hidden in the Trash) are
unresolved. Under "What blocks 2.0" in `docs/remaining-work-plan.md` (broken copy or recovery;
Trash recoverability) each needs an explicit owner decision before Go: fix, or accept with the
impact and workaround recorded. The severities above are proposals, not decisions.
