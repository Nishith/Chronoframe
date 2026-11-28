# Decisions

## German translation import (2026-11-15)

- Merge only German translations for existing keys from `/Users/nishithnand/Downloads/Translation DE`; preserve current keys, English, other languages and extraction metadata. The supplied catalogs predate newer app copy, which continues to fall back to English. Omit the unused incoming `%d duplicates found` key.
- Repair the supplied app catalog's trailing comma and move its misplaced `Nicht ausgewählt` translation to `Not selected`; retain the existing correct `Nichts zu bereinigen` translation for `Nothing to deduplicate`. Do not modify the supplied files.
- Register German in the Xcode project's known regions; continue using the existing system language selection and localization bundles.
- Follow-up UI check: complete German coverage for newer catalog/UI strings and repair plain-String presentation paths that bypass localization. Use informal German consistent with the supplied translations. Preserve filenames, folder names, paths, persisted identifiers and on-disk formats verbatim. Verify with the existing synthetic UI scenarios in an isolated German launch; do not change the user's app language preferences or operate on their library.
- App views consume some native Core model titles/messages through generic components, so their missing German keys are also present in the App table; existing App translations take precedence. Library Health's dynamic byte/count messages carry optional typed `messageDetails` to the App formatter rather than parsing English. Existing English messages and legacy decoding remain compatible.

## Conflicting capture dates (2026-11-06)

- Compare the metadata date's calendar day after applying its EXIF UTC offset with the parsed filename calendar day. Flag only when the two calendar days are more than one day apart; this avoids noise from timezone crossings and near-midnight photos. The metadata instant and its offset remain unchanged for sorting and bucketing.
- Flag the exact metadata wall-clock timestamp `2000-01-01 00:00:00` as a known camera default. The value is documented in the Nikon Coolpix 990 manual (photos before setting the clock receive this timestamp) and Ricoh RDC-6000 manual (initial display is this date/time): [Nikon Coolpix 990 Reference Manual](https://cdn-10.nikon-cdn.com/pdf/manuals/coolpix/cp990rm.pdf), [Ricoh RDC-6000 Manual](https://www.ricoh-imaging.co.jp/english/r_dc/support/manual/pdf/rdc-6000/RDC-6000.pdf). Keep this initial list to that exact value.
- Flag a metadata instant only when it is more than one day after the scan time. This is a review warning; never substitute a different date in the plan.
- Compare only embedded photo/video metadata and parsed filename dates. Ignore file creation and modification times because copying or extraction can rewrite them and create misleading matches or conflicts.
- The warning and optional alternative date are review-only fields. Preserve the existing chosen date, date source priority, bucket, and copy plan.
