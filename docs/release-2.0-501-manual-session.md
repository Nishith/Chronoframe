# Chronoframe 2.0 (501) — replacement candidate

Prepared October 4, 2026. **HOLD: owner mid-copy cancellation exposed a stale terminal count. Build 501 is uploaded, processed and selected in the saved App Store draft, but must be replaced and retested before submission. IAP review screenshot and disclosure saved. Signed copy/repeat/persistence and watched-import smoke checks pass; remaining manual scenarios and owner Go remain open. No review submission made.**

## Candidate identity

- Runtime source: `6df85b4b3ef96fa5f2165c29d35627f3d92e50d3`.
- Version/build: **2.0 (501)**, universal arm64/x86_64, macOS 14+.
- Cutoff unchanged: **2026-10-26T07:00:00Z**, October 26, 00:00 PDT.
- Package SHA-256: `c0b5972e7f4198ffc40fdb675d829278118a02a092f5e409302c56ce92482ab9`.
- Preserved archive/package, logs and release record: `release-artifacts/2.0-501/`.
- The actual app extracted from the upload package has valid Apple Distribution signing, team EB2YPF68XZ, hardened runtime and sandbox/user-folder/bookmark/Photos entitlements. Archive/export validation passed.

The sole runtime change from 500 is the unlock sheet layout: the purchase product name and localized price now occupy a separate line above Restore and Not Now. Engines, receipts, allowance and acquisition policy are unchanged. The previous native 420pt sheet visibly truncated the price. The bitmap/OCR regression fails for that missing visible price on the old view and passes on the fix. **25 focused unlock/presentation/free-batch tests pass.** All hosted CI and CodeQL passed on `64d0d43` (runtime unchanged from `6df85b4`). PR #239 merged as `e67bc9f`; its CI passed and CodeQL was still running when these records were finalized. These subsequent release-record edits are a separate documentation-only follow-up.

## Review interface evidence

`marketing/release-2.0/iap-review/Chronoframe-Unlock-Review.jpg` is a 1440×900 native screenshot of the corrected production `UnlockSheet`, rendered in an isolated developer host with deterministic product metadata matching the local StoreKit configuration and configured US IAP. Its source hashes and environment are in `capture-provenance.json`; capture-host source is preserved beside it. It is not an edited illustration, a TestFlight purchase or proof of live product availability. No financial action was attempted. That test-state provenance is disclosed in the saved IAP review notes.

The owner approved the 501 upload, replacement of selected 500 and IAP screenshot upload. Apple accepted the JPEG after its filename was corrected from `.png` to `.jpg` without changing bytes. The screenshot and disclosure persisted after reload. App 2.0 (501) and the first non-consumable are now together in one draft: **Items Ready to Submit (2)**, macOS version 2.0. Submit for Review is available; it has not been clicked.

## Signed 501 evidence

The first 501 test used the shared disposable source containing the previous large-test fixtures: 11,034 media copies, 169.4 MB. Every receipt entry matches its source bytes, verification was enabled and all original source hashes are unchanged. A separate core run copied 32 files and a repeat preview planned zero. Watched import copied one additional fixture after preview and consent. Machine evidence and receipts are preserved in `release-artifacts/2.0-501/signed-session-evidence/`; `verification-501.json` records the comparisons. No personal library was transferred or mutated.

## Final checks and owner decision

The [signed 500 session](release-2.0-500-manual-session.md) records copy/repeat/revert, reviewed exact Trash/restore, 1,000/10,000-file correctness and actual crash/resume/repeat. Those results remain evidence for the unchanged engines; they are not relabelled as executed on 501.

- [x] Upload/processing and selected draft build **2.0 (501)** confirmed. Upload succeeded from the preserved archive; TestFlight build ID `b096040e-b8ca-4cf4-a868-e960a939ddb5`. Export compliance saved; existing Internal testers group assigned. Selected draft 501 persisted after reload, with manual release.
- [x] Candidate-head CI and CodeQL green at `64d0d43`; runtime source matches the preserved archive. PR #239 merged as `e67bc9f`.
- [ ] Confirm merged-main CodeQL and documentation follow-up checks complete. Merged-main CI passed.
- [x] Installed 501 through TestFlight; actual `/Applications/Chronoframe.app` reports 2.0 (501). Original folder selections survived upgrade; disposable source/destination survived normal relaunch. Focused run completed 32/32 verified byte-identical copies; repeat preview plans zero.
- [x] Corrected production view has readable product/price/Restore in the native capture and bitmap/OCR regression. This locked-state fixture remains separate from signed StoreKit verification.
- [ ] Direct mid-run cancellation check: confirm displayed outcome agrees with receipt/files. Both delayed automated checks were inconclusive. On 501 the UI displayed Cancelled with stale 1,761/11,034 progress, while the receipt recorded COMPLETED for all 11,034 files before cancellation was processed. All 11,034 copies match source bytes and all 11,036 source file hashes are unchanged. A prompt human mid-run cancellation and outcome/receipt agreement check remains required; do not classify the observed cancellation result as passing.
- **Owner mid-copy check, October 4 at 21:25 PDT: FAIL for final count accuracy.** The installed TestFlight 2.0 (501) displayed Cancelled and 108 copied out of 10,000. The engine actually stopped with an ABORTED receipt containing 844 verified copies, exactly matching the 844 destination files and FINALIZED queue jobs; 9,156 jobs remain PENDING. All copies are byte-identical to their sources, every copy is recorded, and all 10,000 source hashes match the pre-test baseline. Cancellation and file safety worked, but the terminal UI count is stale. Hold review submission pending a fix and replacement signed-build retest. Screenshot, receipt, log and `verification.json` are preserved under `release-artifacts/2.0-501/signed-session-evidence/human-mid-copy-cancel/`. The earlier 21:24 screenshot showed zero copies during planning and is not evidence of mid-copy cancellation.
- [ ] Remaining signed scenarios assessed: unavailable folders/fresh install; old receipt upgrade; Keep-wins pair/sidecar retention; Photos import and watched partial-batch retention of another pending item; StoreKit purchase/restore/cancellation/offline; keyboard/VoiceOver/light/dark/small window; real external drive where advertised. Record actual results or accepted limitations.
- [x] Required IAP review screenshot saved in App Store Connect, with honest reviewer notes.
- [ ] Owner **Go / No Go**, date, exact candidate identity and accepted residuals recorded here.

The known crash-receipt boundary still applies: one last in-flight finalized copy can be safely recognized by the queue but absent from the receipt, so that file is not separately revertable. The 500 crash test observed exactly this one-file gap. Do not infer receipt entries from queue rows; originals remained untouched.

## Cancellation-summary replacement

The source fix keeps the session busy with "Stopping…" until the engine finalizes its receipt and emits the actual outcome/counts. Folder access and the destination lease stay held during that interval, and a replacement operation cannot start. A late cancel no longer changes an already-completed receipt into a Cancelled UI. Fresh and resumed transfers emit terminal results with committed counts; planning-only cancellation is published only after its stream ends. Revert/reorganize also retain their final executor counts when stopping.

Local validation: all **1,729 Swift tests** pass via the sharded runner, including regression coverage for the observed 108→844 mismatch, folder access/lock retention, repeated cancellation, a buffered successful completion, and real receipt-backed fresh/resumed cancellation. The universal Release `MAS_BUILD` build succeeds with build number 502. These checks validate source/build behavior; they do not replace uploading, installing and manually retesting the replacement signed candidate. Build 501 remains held.

For the October 26 free date, paid V2 must be live by **October 18, 07:00 PDT** to finish the project's seven-day paid hold before the first regional free-price start. Prefer earlier. Validate real paid-purchaser grandfathering during that rollout. If the schedule slips, postpone pricing and ship a later cutoff before October 26, 00:00 PDT. Keep website deployment and free-launch announcements held until the relevant storefront is actually free and production access/purchase/restore work.
