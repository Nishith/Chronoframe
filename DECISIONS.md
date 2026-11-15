# Decisions

## Conflicting capture dates (2026-11-06)

- Compare the metadata date's calendar day after applying its EXIF UTC offset with the parsed filename calendar day. Flag only when the two calendar days are more than one day apart; this avoids noise from timezone crossings and near-midnight photos. The metadata instant and its offset remain unchanged for sorting and bucketing.
- Flag the exact metadata wall-clock timestamp `2000-01-01 00:00:00` as a known camera default. The value is documented in the Nikon Coolpix 990 manual (photos before setting the clock receive this timestamp) and Ricoh RDC-6000 manual (initial display is this date/time): [Nikon Coolpix 990 Reference Manual](https://cdn-10.nikon-cdn.com/pdf/manuals/coolpix/cp990rm.pdf), [Ricoh RDC-6000 Manual](https://www.ricoh-imaging.co.jp/english/r_dc/support/manual/pdf/rdc-6000/RDC-6000.pdf). Keep this initial list to that exact value.
- Flag a metadata instant only when it is more than one day after the scan time. This is a review warning; never substitute a different date in the plan.
- Compare only embedded photo/video metadata and parsed filename dates. Ignore file creation and modification times because copying or extraction can rewrite them and create misleading matches or conflicts.
- The warning and optional alternative date are review-only fields. Preserve the existing chosen date, date source priority, bucket, and copy plan.
