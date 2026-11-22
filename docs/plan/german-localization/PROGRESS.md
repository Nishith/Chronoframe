# German localization verification

## Goal and scope

User follow-up (2026-11-15): check the German UI and ensure no translation gaps. Fill missing German translations and repair runtime localization paths; preserve supplied German, all other languages, safety semantics and user data such as filenames/paths. Use informal German consistent with the supplied translations. No new visual design.

## Baseline and findings

- Original import added 108 App German entries and updated 20 App / 32 Core entries. Existing catalog keys remained 512 App / 112 Core.
- Catalog-only translation left gaps: raw String presentation helpers bypass lookup, and 155 direct UI literal keys were absent. NAS Core messages use the wrong table.
- Both original catalogs compiled; Xcode Debug build passed after retry with full local build access (sandbox blocked SwiftUI macro helper). Log: `/private/tmp/chronoframe-german-build.log`.
- CUA baseline screenshot `.tmp/german-ui-check/screenshots/01-setup-before.jpg` shows mixed English/German setup, sidebar subtitles, tabs, status and helper copy. German system controls prove the process language is German.
- Do not disturb pre-existing untracked `default.profraw` or `marketing/product-video/`.

## Work ownership

- `german_app_catalog`: App catalog (initial missing 350 entries completed), now adding direct UI and helper keys with German. No App source edits.
- `german_core_catalog`: Core source and Core catalog, runtime localizations and focused tests. Initial 72 missing catalog entries completed.
- `localization_source_audit`: App pure formatter/helper source + HelpView + tests; coordinates new keys via `/private/tmp/cf-app-runtime-german.json`. Owns SetupScreenModel too.
- Root: generic SharedViews components, SetupSectionViews rendering, WorkspaceTabStrip, SettingsView, dynamic navigation titles, history rendering; UI capture/build/final verification.

## UI harness

`.tmp/german-ui-check/Chronoframe.app` is a signed copy of the local Debug app. `.tmp/german-ui-check/Launcher.app` is a temporary native launcher that sets the existing test scenario, `-AppleLanguages (de)` and `-AppleLocale de_DE`; it executes the copied app's unchanged executable. Scenario comes from `.tmp/german-ui-check/german-ui-scenario.txt` (defaults to setupReady). The app uses existing synthetic fixtures, not the real library.

CUA session bindings: `finder` (Finder), `germanApp` (full path above), `fs` from node:fs/promises. Launch via Finder: Go to folder `.tmp/german-ui-check`, open Launcher. `cua.computer.launch_app` unavailable and `getApp` does not launch non-running Mac apps. Use CUA for all live UI actions. Save screenshots through `getAXStateAndScreenshot().screenshot`. On finishing ALL CUA work, the next CUA call must be completion_summary only.

## Remaining

- Catalogs/runtime wiring implemented. Current coverage: 1,630 App keys / 298 Core keys, all German. Compiler extraction: 880 App keys / 257 AppCore keys, zero missing German keys. `.tmp/german-ui-check/validate_localization.py` verifies compiled German values, positional placeholders and preservation of original keys/metadata/all non-German locales against HEAD.
- Xcode Debug build with extraction passed. Broad regression command in `/private/tmp/chronoframe-german-tests.log` passed 635 tests (460 App, 175 AppCore); the latest focused run in `/private/tmp/chronoframe-german-final-tests.log` passed 85 tests (62 App, 23 AppCore). The unrelated concurrent edit-preservation work appeared while the UI connection was waiting; preserve those edits, especially native DeduplicateExecutor, UserFacingErrorMessage/related tests, clear-path string notes and `docs/plan/edit-preservation/`.
- Visually inspected setup/native folder buttons, Preview & Copy idle, seven Settings tabs, four Help tabs and populated duplicate review. Found and fixed AppKit lookup bypasses, Core/App table mismatches, dynamic review/Health/phase/count phrases, remaining review VoiceOver/tooltips, sidebar subtitle truncation, the Profiles label column, quality-row truncation and the match-reason heading fit.
- Accepted compact duplicate-review capture: `.tmp/german-ui-check/screenshots/19-dedupe-final.jpg` (900×700 points). Native captures are JPEG bytes; corrected saved filename extensions from `.png` to `.jpg` without modifying their contents. Capture 05 caught a transition and is rejected as final evidence; earlier captures can show pre-fix findings. See `VERIFICATION.md` for scope/limits.
- **Visual verification blocked:** CUA repeatedly returned `timeoutReached` / `noWindowsAvailable`, then resolved a shared bundle identifier to another running Chronoframe. Did not operate on that instance's real library. A uniquely identified copied test app and native launcher were prepared, but connecting to it also timed out. CUA completion summary sent. Do not claim final visual verification of Photos, populated History, the App Store purchase sheet or the last Profiles/inspector fit changes.
- Remaining after UI access is restored: use the isolated test identity and existing synthetic scenarios (`photosImport`, `historyPopulated`, `runPreviewReview`, `settingsLicense`, `deduplicateReviewWide`) to complete those captures. No real-library mutation or purchase is necessary.

## Final harness identity

The original copied app shared `com.nishith.chronoframe`, which became ambiguous when another instance opened. The revised `.tmp/german-ui-check/ChronoframeGermanCheck.app` uses `com.nishith.chronoframe.german-ui-check` and a distinct display name. `Launcher.app` now uses `NSWorkspace.OpenConfiguration` with explicit German launch arguments, the selected fixture scenario, and a 1100×800-point visible-area override. This is a temporary test artifact only. The shipping bundle identity/preferences remain unchanged. CUA was finalized after repeated connection failures; reinitialize its documentation before any future UI session.
