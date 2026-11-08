# NAS public — evidence ledger (owner rows)

Only Nishith records results. Rows H1–H8 are the v1 hardware checks; run them exactly as `docs/plan/nas-v1/EVIDENCE_LEDGER.md` and `docs/plan/nas-v1/FINAL_REPORT.md` "Hardware checklist" specify, then copy the results here.

| Row | What to run | Pass when | Status | Evidence |
|---|---|---|---|---|
| H1–H8 | per `docs/plan/nas-v1/EVIDENCE_LEDGER.md` | per that ledger | todo-hardware | |
| H-NASP-1 | `open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app`; Deduplicate → Choose Folder… → pick a folder on the mounted Synology share | Alert shows the C-01 text naming NAS Library; the Deduplicate folder path is unchanged; no `.organize_cache.db` or `.organize_logs` appeared in the chosen share folder | todo-hardware | screenshot |
| H-NASP-2 | Same, but set the Organize destination to the share and press Scan in Deduplicate without choosing a folder | Same refusal; `scan` never ran (no lock file on the share) | todo-hardware | screenshot |
| FLAG | After every row above is `pass-hardware`: edit `ui/Sources/ChronoframeCore/NASModels.swift:15–16` so the `#else` branch returns `true`; update `docs/TECHNICAL.md:124`, `docs/plan/nas-v1/FINAL_REPORT.md:81`, `docs/plan/nas-v1/DECISIONS.md` D-NAS-06; run `cf_swift.sh suite` and `cf_swift.sh xcode`; commit `NAS: enable NAS Library for release`; merge `feature/nas-v1` to `main` | NAS Library tab appears in a Release build | todo-hardware | commit hash |
