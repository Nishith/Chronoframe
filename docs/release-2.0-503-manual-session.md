# Chronoframe 2.0 (503) — Photos capture-date replacement

Prepared October 5, 2026. **Local signed archive/export validated; NOT UPLOADED, NOT INSTALLED through TestFlight, NOT SUBMITTED. No owner Go. Build 502 remains held.**

## Candidate

- Runtime source: **`6a847f14e3153dcd65abadc02e1d2965264d3a87`**. Follow-up branch: `codex/fix-photos-capture-dates`, [PR #242](https://github.com/Nishith/Chronoframe/pull/242). PR #241 was squash-merged while this work was in progress; the branch includes that merged cancellation work and adds only the Photos fix and release evidence.
- Actual archive and package-extracted app: **2.0 (503)**, universal arm64/x86_64, macOS 14+.
- Build environment: `CHRONOFRAME_BUILD_NUMBER=503`, Release, `SWIFT_ACTIVE_COMPILATION_CONDITIONS=MAS_BUILD`. The stamp script overrides `CURRENT_PROJECT_VERSION`; both actual Info.plists were inspected.
- Archive: `release-artifacts/2.0-503/Chronoframe-MAS.xcarchive`.
- Package: `release-artifacts/2.0-503/mas-export/Chronoframe.pkg`.
- Package SHA-256: **`daf46d7c86a2555b3399d2a75da208849440d7e9a19a6dfd5c39c904f213e061`**.
- Export explicitly uses `destination=export`, `manageAppVersionAndBuildNumber=false`, `uploadSymbols=false`. No upload occurred.
- Actual package-extracted app passes `ChronoframePackagingTool --app-store`: Apple Distribution, team EB2YPF68XZ, hardened runtime and sealed resources. Strict/deep signature verification passes; installer certificate chain is Apple-issued. Local Gatekeeper rejects the MAS bundle; this is not an Apple processing or TestFlight result.
- Paid/free cutoff remains **2026-10-26T07:00Z**. No pricing, draft-selection, submission or publication changes.

## Fix and validation

[Signed 502's failure](release-2.0-502-manual-session.md) remains preserved. Generated HEIC/MOV fixtures reproduced the movie import-day fallback and the loss of metadata pair recognition before production edits. The existing Test iPhotos destination and personal Photos library were never modified or repaired during this fix. Committed fixture pixels, identifiers and clock times are synthetic.

Native video resolution now reads capture metadata before filename/filesystem fallback and retains recorded offsets. Reads forbid external references, cap outstanding loads at four, enforce a ten-second deadline and observe cancellation. Photos export pins one shared capture date per asset: still metadata → movie metadata → filename → valid Photos asset instant → Unknown. A still's date/offset wins over a differing paired-movie timestamp, including midnight. Staging creation/mtime are excluded. Content-bound snapshots travel through the pinned context and configuration into preview and execution planning; changed/new staging bytes require preparing again. User overrides retain precedence. Original bytes/identifiers, transactional export, confirmation, verification, collision safety and cancellation/recovery remain intact.

Actual local results:

- **1,742 tests passed in 31 shards**, zero skipped/failed. The final fixture revision also passes the full coverage suite.
- Final meaningful coverage: **95.86%** (17,299/18,047 selected deterministic lines; not project-wide SwiftUI coverage).
- All CI repository guards pass, including Photos read-only, 26 invariant tags, MAS lane and app-layer tests; whitespace passes.
- Universal Release MAS_BUILD compilation, signed archive and local export succeed. Versions/architectures inspected in the actual archived and package-extracted apps; package validator and signatures pass.
- Regressions cover generated export → real preview → execution re-plan → verified copies → COMPLETED receipt → final metadata-based pair recognition; midnight boundaries in positive/negative offsets; differing still/movie timestamps; standalone January/July videos; invalid/missing dates; filename/user precedence; legacy configuration decoding; same-size/same-mtime staged-byte replacement; and metadata timeout/cancellation. Existing cancellation/recovery regressions pass in the full suite.

Logs, local export options and machine-readable identity are retained under `release-artifacts/2.0-503/`. PR #242 is open and mergeable; CI and CodeQL were queued/in progress at the post-creation snapshot, not claimed green. Final-head hosted checks remain separate from these local results.

## Exact signed retest steps

Upload is a separate future action requiring authorization. After Apple processes the replacement, perform and record these steps before owner Go:

1. Install through TestFlight; capture About confirming **2.0 (503)**. Record runtime commit/package identity and Apple processing/install outcome.
2. Choose a **new empty disposable destination**, never the existing Test iPhotos evidence folder. Import the same three Live Photos and two standalone videos (eight original resources) with verification enabled. Retain review and final UI/receipt. Both August pairs must remain together under `2026/08/01`; the October pair must remain together under `2026/10/04`; standalone movies must use `2026/01/30` and `2026/07/17`, rather than the import day.
3. Verify all eight copied hashes against the COMPLETED receipt. Confirm review destinations equal committed destinations, zero failures and cleaned staging. Read embedded offsets/dates/content IDs without rewriting files. Report library immutability as owner-observed/structurally guarded unless an independent baseline was actually collected.
4. Run **scan-only Deduplicate** on the disposable destination. Retain evidence that all three pairs are recognized by embedded identifiers in their shared directories even when renamed stems differ. Do not confirm Trash. If available, include a generated/selected midnight-boundary pair and missing-date resource: explicit offsets retain local day; truly missing capture information goes to Unknown.
5. Repeat import/preview (zero new resources), then repeat signed mid-copy cancel/resume on another disposable destination. Reconcile terminal UI counts with finalized receipts/copies and verify unchanged originals. Preserve all 502 evidence. Record remaining signed scenarios/accepted limitations, final-head CI/CodeQL and owner Go before review submission.

No signed retest result is claimed. Do not submit 502 or select an untested replacement for review.
