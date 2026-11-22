# Chronoframe 2.0 (502) — cancellation replacement

**Historical evidence, 2026-10-04 to 2026-10-05. Cancellation fix passed signed retest; build held and replaced** after the signed Photos Live Photo/video import split pairs across date folders (fixed in [503](release-2.0-503-manual-session.md) and PR #242, shipped in later builds). The shipped build is 2.0 (511); see [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md).

## Candidate

- Runtime source: `4868b4b` on `codex/fix-cancellation-summary`; [PR #241](https://github.com/Nishith/Chronoframe/pull/241).
- Actual archived and exported version: **2.0 (502)**, universal arm64/x86_64, macOS 14+.
- `CHRONOFRAME_BUILD_NUMBER=502` is required: the project's stamp script overrides `CURRENT_PROJECT_VERSION` without this environment variable.
- Package: `release-artifacts/2.0-502/mas-export/Chronoframe.pkg`.
- Package SHA-256: `e28da69d7031e441aa2a4e9763912ad9777f96bef7a04f3256716cbcff293093`.
- Apple Distribution signing, team EB2YPF68XZ, hardened runtime and sealed resources verified. The app extracted from the actual upload package passes `ChronoframePackagingTool --app-store`. A local Gatekeeper rejection is not an App Store processing or TestFlight result.

## Fix and evidence

The [owner's signed 501 test](release-2.0-501-manual-session.md) displayed Cancelled at 108 copied, while the ABORTED receipt and destination contained 844 verified copies. All 10,000 originals were unchanged. Build 501 remains held.

Cancellation now keeps the session busy (Stopping…), retains folder access and the destination lock, and continues consuming events until the engine supplies its final committed counts. Repeated cancel requests are ignored, another operation cannot replace a stopping run, and a completed transfer stays completed when the cancel click arrives late. Fresh/resumed transfer and revert/reorganize results carry final executor counts. Planning-only cancellation waits for the stream to end.

All **1,729 Swift tests** pass via `script/run_swift_test_suites.sh`; universal Release MAS_BUILD compilation, signed archive/export, package validation, invariant tags and whitespace checks pass. Regression coverage includes stale 108→844 progress, lock/access retention, late buffered completion, real cancelled fresh/resumed receipts, and late cancellation after a real COMPLETED receipt. These are source/local-package checks, not signed TestFlight manual results.

## Signed results (owner, 2026-10-04)

- Upload 2.0 (502): Xcode reported Upload succeeded / EXPORT SUCCEEDED and App Store Connect showed 502 Processing. Upload used `destination=upload`, `manageAppVersionAndBuildNumber=false`, `testFlightInternalTestingOnly=false` from the preserved archive; the saved package checksum does not identify the upload re-export. Log and options: `release-artifacts/2.0-502/`. TestFlight and About confirm 2.0 (502).
- **Mid-copy cancellation retest: PASS**, 22:11 PDT. UI showed Cancelled with **311 copied / 10,000 planned and zero issues**. The finalized **ABORTED** receipt `38CE8696-3D90-4819-82BD-65453DA2638C` and the destination agree at 311 copies, verification on, zero failed jobs; every copy matches its original bytes and recorded BLAKE2b identity. CopyJobs holds 311 COPIED/FINALIZED and 9,689 PENDING. All 10,000 originals match the pre-test SHA-256 baseline. Receipt started 22:11:06, finalized 22:11:09 PDT. Evidence: `release-artifacts/2.0-502/signed-session-evidence/human-mid-copy-cancel/`.
- **Resume after cancellation: PASS** (22:25:04–22:26:19 PDT). The resumed run finalized a COMPLETED receipt for the remaining **9,689** copies, verification on, zero failures; with the cancelled receipt's 311 entries the receipts account for exactly **10,000 distinct paths**, all matching source bytes. Destination holds exactly 10,000 files; all originals match the baseline; CopyJobs has 10,000 COPIED/FINALIZED. The owner reported repeat preview and relaunch complete; the final zero-plan preview was not separately captured. Evidence: `.../resume-after-cancel/`.
- **Photos still-image import: PASS** (22:42 PDT). 7 files (4 HEIC, 3 JPEG), 21,857,794 bytes; 7/7 copied, zero issues; receipt `D93FBBF6-D9D0-4BAA-9985-D3CD5265C85C` COMPLETED, every file matches its recorded identity, staging cleaned. Album-selection provenance was not retained and no independent before/after Photos-library baseline is claimed (the Photos read-only source guard passes). Evidence: `.../photos-import-stills/`.
- **Photos Live Photo/video import: FAIL** for date-folder and pair preservation (22:46 PDT). The receipt is COMPLETED with 8 new resources (3 HEIC, 5 MOV), verification on, zero failures; all 15 destination files match their receipt identities. Three shared Live Photo content identifiers are confirmed, but two pairs were split between August capture-date still folders and October import-date movie folders, and both standalone videos used import-date folders despite embedded capture dates. Cause: `FileDateResolver` read photo metadata but not video metadata, the Photos export did not preserve capture dates in staging, and `DeduplicatePairDetector` matches Live Photo IDs only within one directory. Evidence: `.../photos-live-video/`.
- The known last-in-flight crash-receipt gap (see 500/501) remains documented.

## Capture-date fix (October 5)

Fix `6a847f1` ([PR #242](https://github.com/Nishith/Chronoframe/pull/242), merged 2026-10-17): video capture metadata is read with bounded, reference-restricted loads and recorded offsets are preserved; Photos export resolves one shared asset date from still metadata, then movie metadata, then filename, then a valid Photos asset instant, then Unknown, never staging creation/mtime; content-bound date snapshots reach preview and execution planning, and user overrides keep precedence. [PR #241](https://github.com/Nishith/Chronoframe/pull/241) (cancellation) merged 2026-10-05. Local validation: 1,742 tests in 31 shards, meaningful coverage 95.86% (17,299/18,047), repository guards, universal Release `MAS_BUILD` compile. These are generated-fixture and local-build results, not signed TestFlight results. The signed retest plan and package identity are in [503](release-2.0-503-manual-session.md).
