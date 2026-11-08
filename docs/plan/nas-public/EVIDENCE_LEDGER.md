# NAS public — evidence ledger (owner rows)

Only Nishith records results. Rows H1–H8 are the v1 hardware checks; run them exactly as `docs/plan/nas-v1/EVIDENCE_LEDGER.md` and `docs/plan/nas-v1/FINAL_REPORT.md` "Hardware checklist" specify, then copy the results here.

| Row | What to run | Pass when | Status | Evidence |
|---|---|---|---|---|
| H1 | `probe --test-dir` on the share (P01 to P07), including whether RENAME_EXCL is supported; save `probe.json` (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H1) | P03, P04, P05 pass; P04 leaves the existing bytes' digest unchanged | todo-hardware | |
| H2 | `make-corpus` (10,000 files, 20% duplicates, seed 42), then `assess-parity` three matched cold runs; save `parity.json` per run (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H2) | `parity: true`, ledger within the NAS-NFR-09 budget in all three runs | todo-hardware | |
| H3 | Choose share, assess, quit, relaunch, confirm review restored, remount under another path (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H3) | Saved review restored; remount recognized as the same library | todo-hardware | |
| H4 | Assess a share with no write access to the account; compare server-side change history before and after (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H4) | No server-side changes | todo-hardware | |
| H5 | Disconnect the share, then sleep and wake the Mac, during a scan and during a copy (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H5) | Scan ends "waiting for your NAS" without data loss; copy stops cleanly and resumes | todo-hardware | |
| H6 | Representative batch of at least 100 files / 10 GiB each way, plus a forced quota-full fault (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H6) | Every copy verified, no overwrite, quota fault stops cleanly with originals untouched | todo-hardware | |
| H7 | VoiceOver, keyboard, increased text and reduced motion pass over the NAS workspace (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H7) | Every control reachable and labeled | todo-hardware | |
| H8 | Measure on the reference corpus (use `wallSeconds` and `ruMaxrss` from `parity.json`) (full procedure: docs/plan/nas-v1/EVIDENCE_LEDGER.md H8) | Within the NAS-NFR-01 to NFR-04 targets | todo-hardware | |
| H-NASP-1 | `open --env CHRONOFRAME_ENABLE_NAS=1 ui/build/Chronoframe.app`; Deduplicate → Choose Folder… → pick a folder on the mounted Synology share | Alert shows the C-01 text naming NAS Library; the Deduplicate folder path is unchanged; no `.organize_cache.db` or `.organize_logs` appeared in the chosen share folder | todo-hardware | screenshot |
| H-NASP-2 | Same, but set the Organize destination to the share and press Scan in Deduplicate without choosing a folder | Same refusal; `scan` never ran (no lock file on the share) | todo-hardware | screenshot |
| FLAG | After every row above is `pass-hardware`: edit `ui/Sources/ChronoframeCore/NASModels.swift:15–16` so the `#else` branch returns `true`; update `docs/TECHNICAL.md:124`, `docs/plan/nas-v1/FINAL_REPORT.md:81`, `docs/plan/nas-v1/DECISIONS.md` D-NAS-06; run `cf_swift.sh suite` and `cf_swift.sh xcode`; commit `NAS: enable NAS Library for release`; merge `feature/nas-v1` to `main` | NAS Library tab appears in a Release build | todo-hardware | commit hash |
