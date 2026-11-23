# German localization progress

**Status (2026-11-22): shipped and verified through PRs #277, #280, #281, #282, #284; #287 and #288 add the second review's wording fixes and singular phrases.** Evidence, screenshots and open items are in `VERIFICATION.md`. This file keeps the scope, decisions about the method and the test harness.

## Goal and scope

User request (2026-11-15): check the German UI and ensure no translation gaps. Fill missing German, repair runtime lookup paths that bypass the catalogs, preserve supplied German, all other languages, safety semantics, and user data such as filenames and paths. Informal German ("du"), consistent with the supplied translations. No new visual design.

## What was done

- Imported the supplied German into both catalogs (App `Localizable.xcstrings`, Core `LocalizableCore.xcstrings`), filled every extracted key, and repaired plain-`String` and AppKit paths that bypass lookup (`AppLocalization.string/format`, typed Library Health message details, the Core/App table split).
- Coverage and checks: `script/check_german_localization.py --baseline-ref origin/main --stringsdata-directory …` verifies placeholders, compiled values, preserved baseline keys and other locales; `GermanLocalizationTests` (App and AppCore) check real compiled lookups.
- UI passes: setup, Preview & Copy (idle and populated), History, Photos import, License and unlock sheet, all Settings tabs, Help, duplicate review (compact and wide), Profiles, Health, and the Prüfen/Probleme/Aktivität tabs. Fit and bypass defects found along the way were fixed (see `VERIFICATION.md` for each).
- Review: no native German speaker is available, so wording was checked by two independent model reviewers (the second without sight of the first's verdict) and by the check script.

## Open

- A native speaker has not reviewed any German; the "originals were not changed" and "nothing was copied" sentences matter most.
- The Überblick/Prüfen/Probleme/Aktivität tab strip ends about 28 pt past the card margin in German, and the Preview screen shows three different problem counts with the fixture data (not investigated). Details in `VERIFICATION.md`.
- Other count-dependent strings outside the Run timeline were not audited for a missing singular form (#288 covers the timeline).

## Test harness (local, temporary, gitignored)

Everything lives under `.tmp/german-ui-check/`:

- `ChronoframeGermanCheck.app` is a copy of the Debug app with bundle id `com.nishith.chronoframe.german-ui-check`, re-signed ad hoc. To refresh it after a build, copy the new `Contents/MacOS/Chronoframe` and the `de.lproj`/`en.lproj` resources from `.tmp/ChronoframeDerivedData/Build/Products/Debug/Chronoframe.app`, then `codesign --force --deep --sign -`.
- `Launcher.app` opens it with `-AppleLanguages (de) -AppleLocale de_DE`, the scenario named in `german-ui-scenario.txt`, and a 1100×800 visible-area override. The first launch sometimes fails with "miscellaneous error"; launching again works.
- Scenarios come from the synthetic UI-test fixtures (`photosImport`, `historyPopulated`, `runPreviewReview`, `settingsLicense`, `profilesPopulated`, `healthDashboard`, `deduplicateReviewWide`, `deduplicateReviewCompact`); no real library is touched and nothing is purchased.
- Drive it with the computer-use `app_*` tools, requesting access by the display name "Chronoframe German Check" and targeting the bundle id above. Never target the real Chronoframe app (`com.nishith.chronoframe`). English strings visible in these captures ("Preview complete", "All Photos", the price button) are fixture text, not production bugs.
- Screenshots are `.tmp/german-ui-check/screenshots/` (`01`–`39`); native captures are JPEG.
