# Chronoframe 2.0 (501) — replacement candidate

Prepared October 4, 2026. **Local signed package ready; upload approval, processing, signed installation, final hosted checks and owner Go are pending. No review submission made.**

## Candidate identity

- Runtime source: `6df85b4b3ef96fa5f2165c29d35627f3d92e50d3`.
- Version/build: **2.0 (501)**, universal arm64/x86_64, macOS 14+.
- Cutoff unchanged: **2026-10-26T07:00:00Z**, October 26, 00:00 PDT.
- Package SHA-256: `c0b5972e7f4198ffc40fdb675d829278118a02a092f5e409302c56ce92482ab9`.
- Preserved archive/package, logs and release record: `release-artifacts/2.0-501/`.
- The actual app extracted from the upload package has valid Apple Distribution signing, team EB2YPF68XZ, hardened runtime and sandbox/user-folder/bookmark/Photos entitlements. Archive/export validation passed.

The sole runtime change from 500 is the unlock sheet layout: the purchase product name and localized price now occupy a separate line above Restore and Not Now. Engines, receipts, allowance and acquisition policy are unchanged. The previous native 420pt sheet visibly truncated the price. The bitmap/OCR regression fails for that missing visible price on the old view and passes on the fix. **25 focused unlock/presentation/free-batch tests pass.** Full final-head CI and CodeQL are separate gates.

## Review interface evidence

`marketing/release-2.0/iap-review/Chronoframe-Unlock-Review.png` is a 1440×900 native screenshot of the corrected production `UnlockSheet`, rendered in an isolated developer host with deterministic product metadata matching the local StoreKit configuration and configured US IAP. Its source hashes and environment are in `capture-provenance.json`; capture-host source is preserved beside it. It is not an edited illustration, a TestFlight purchase or proof of live product availability. No financial action was attempted. Disclose that test-state provenance in the IAP review notes if uploaded.

New review-screenshot upload approval is pending. Keep app and first non-consumable together for the eventual review submission.

## Final checks and owner decision

The [signed 500 session](release-2.0-500-manual-session.md) records copy/repeat/revert, reviewed exact Trash/restore, 1,000/10,000-file correctness and actual crash/resume/repeat. Those results remain evidence for the unchanged engines; they are not relabelled as executed on 501.

- [ ] Upload/processing and selected draft build **2.0 (501)** confirmed.
- [ ] Final branch-head CI and CodeQL green; runtime source matches the preserved archive.
- [ ] Install 501 through TestFlight; check version, folder persistence and a verified disposable copy/repeat smoke check.
- [ ] Corrected price/Restore controls remain readable; appropriate locked-state evidence kept separate from signed StoreKit.
- [ ] Direct mid-run cancellation check: confirm displayed outcome agrees with receipt/files. The delayed automated check on 500 was inconclusive.
- [ ] Remaining signed scenarios assessed: unavailable folders/fresh install; old receipt upgrade; Keep-wins pair/sidecar retention; Photos import/watched batch; StoreKit purchase/restore/cancellation/offline; keyboard/VoiceOver/light/dark/small window; real external drive where advertised. Record actual results or accepted limitations.
- [ ] Required IAP review screenshot saved in App Store Connect, with honest reviewer notes.
- [ ] Owner **Go / No Go**, date, exact candidate identity and accepted residuals recorded here.

The known crash-receipt boundary still applies: one last in-flight finalized copy can be safely recognized by the queue but absent from the receipt, so that file is not separately revertable. The 500 crash test observed exactly this one-file gap. Do not infer receipt entries from queue rows; originals remained untouched.

For the October 26 free date, paid V2 must be live by **October 18, 07:00 PDT** to finish the project's seven-day paid hold before the first regional free-price start. Prefer earlier. Validate real paid-purchaser grandfathering during that rollout. If the schedule slips, postpone pricing and ship a later cutoff before October 26, 00:00 PDT. Keep website deployment and free-launch announcements held until the relevant storefront is actually free and production access/purchase/restore work.
