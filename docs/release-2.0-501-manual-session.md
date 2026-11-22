# Chronoframe 2.0 (501) — replacement candidate

**Historical evidence, 2026-10-04. Held and replaced by [502](release-2.0-502-manual-session.md).** Owner mid-copy cancellation on 501 exposed a stale terminal count (UI 108 vs 844 verified copies); the fix and retest are in 502. The shipped build is 2.0 (511); see [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md).

## Candidate identity

- Runtime source: `6df85b4b3ef96fa5f2165c29d35627f3d92e50d3`.
- Version/build: **2.0 (501)**, universal arm64/x86_64, macOS 14+.
- Package SHA-256: `c0b5972e7f4198ffc40fdb675d829278118a02a092f5e409302c56ce92482ab9`.
- Preserved archive/package, logs and release record: `release-artifacts/2.0-501/`.
- The actual app extracted from the upload package has valid Apple Distribution signing, team EB2YPF68XZ, hardened runtime and sandbox/user-folder/bookmark/Photos entitlements. Archive/export validation passed.

The sole runtime change from 500 is the unlock sheet layout: the purchase product name and localized price now occupy a separate line above Restore and Not Now. Engines, receipts, allowance and acquisition policy are unchanged. The previous native 420pt sheet visibly truncated the price. The bitmap/OCR regression fails for that missing visible price on the old view and passes on the fix. **25 focused unlock/presentation/free-batch tests pass.** All hosted CI and CodeQL passed on `64d0d43` (runtime unchanged from `6df85b4`). PR #239 merged as `e67bc9f`; its CI passed and CodeQL was still running when these records were finalized. These subsequent release-record edits are a separate documentation-only follow-up.

## Review interface evidence

`marketing/release-2.0/iap-review/Chronoframe-Unlock-Review.jpg` is a 1440×900 native screenshot of the corrected production `UnlockSheet`, rendered in an isolated developer host with deterministic product metadata matching the local StoreKit configuration and configured US IAP. Its source hashes and environment are in `capture-provenance.json`; capture-host source is preserved beside it. It is not an edited illustration, a TestFlight purchase or proof of live product availability. No financial action was attempted. That test-state provenance is disclosed in the saved IAP review notes.

The owner approved the 501 upload, replacement of selected 500 and the IAP screenshot upload. Apple accepted the JPEG after its filename was corrected from `.png` to `.jpg` without changing bytes; screenshot and disclosure persisted after reload.

## Signed 501 evidence

The first 501 test used the shared disposable source containing the previous large-test fixtures: 11,034 media copies, 169.4 MB. Every receipt entry matches its source bytes, verification was enabled and all original source hashes are unchanged. A separate core run copied 32 files and a repeat preview planned zero. Watched import copied one additional fixture after preview and consent. Machine evidence and receipts are preserved in `release-artifacts/2.0-501/signed-session-evidence/`; `verification-501.json` records the comparisons. No personal library was transferred or mutated.

## Results

The [signed 500 session](release-2.0-500-manual-session.md) records copy/repeat/revert, reviewed exact Trash/restore, 1,000/10,000-file correctness and crash/resume/repeat; those remain evidence for the unchanged engines and are not relabelled as executed on 501.

- Upload, processing and selected draft build 501: upload succeeded from the preserved archive; TestFlight build ID `b096040e-b8ca-4cf4-a868-e960a939ddb5`; export compliance saved; Internal testers group assigned.
- Hosted CI and CodeQL green at `64d0d43` (runtime unchanged from `6df85b4`); PR #239 merged as `e67bc9f`.
- Installed through TestFlight; `/Applications/Chronoframe.app` reports 2.0 (501). Folder selections survived upgrade and relaunch. 32/32 verified byte-identical copies; repeat preview plans zero.
- Corrected production unlock view has readable product, price and Restore in the native capture and bitmap/OCR regression. This locked-state fixture is separate from signed StoreKit verification.
- IAP review screenshot saved in App Store Connect with honest reviewer notes.
- **Owner mid-copy check, 2026-10-04 21:25 PDT: FAIL for final count accuracy.** TestFlight 501 displayed Cancelled and 108 copied of 10,000; the engine had stopped with an ABORTED receipt of 844 verified copies matching the 844 destination files and FINALIZED queue jobs (9,156 PENDING). All copies are byte-identical, all recorded, and all 10,000 source hashes match the baseline. File safety held; only the terminal UI count was stale. Evidence (screenshot, receipt, log, `verification.json`): `release-artifacts/2.0-501/signed-session-evidence/human-mid-copy-cancel/`. An earlier delayed-automation run (UI stale at 1,761/11,034 while the receipt was COMPLETED) was inconclusive.
- Fix: the session stays busy with "Stopping…" until the engine finalizes its receipt and emits the actual counts, keeps folder access and the destination lease, and a late cancel no longer changes a completed receipt into a Cancelled UI. 1,729 Swift tests pass; details and retest in [502](release-2.0-502-manual-session.md).

The known crash-receipt boundary still applies: one last in-flight finalized copy can be recognized by the queue but absent from the receipt, so that file is not separately revertable. Do not infer receipt entries from queue rows; originals stay untouched.
