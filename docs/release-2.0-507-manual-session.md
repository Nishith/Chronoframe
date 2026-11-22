# Chronoframe 2.0 (507) — responsive large receipts

**Historical evidence, 2026-10-17 to 2026-10-19. Rejected by App Review on 2026-10-19 under Guideline 2.1(b)** (the reviewer could not find Chronoframe Unlock; combined submission `cdf1ea79-235f-4faa-8743-40ab920109f4`). Replaced by 508, then 510 and 511 ([rejection record](app-review-iap-rejection-2026-10-19.md); shipped build 2.0 (511), see [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md)). The results below remain the signed evidence for large-receipt rendering, cancelled-run revert, re-copy and exact-duplicate Trash/restore, which were unchanged in later builds.

Replacement for the large-receipt rendering blocker seen on signed 506. Uploaded 17:09:04 PDT; Apple build ID `72b05d39-e241-4b63-bf56-50ddd3df62e5`; processing completed, the unchanged export-compliance answer saved, Internal testers group confirmed (availability proof `release-artifacts/2.0-507/testflight-ready.png`). [PR #246](https://github.com/Nishith/Chronoframe/pull/246) merged 2026-10-17 at 17:39:34 PDT.

- Frozen source commit: `f54191843a7f95f0ad211c79714402e36ea7f4ea`; archive tree: `7fc1ca0b669ba0d982a5fbc355a191e0b7b704ff`.
- [PR #246](https://github.com/Nishith/Chronoframe/pull/246) retains per-archive sandbox access and provides guided same-folder reconnection. The final viewer correction moves file reading/JSON decoding off the main actor with an independent worker scope and renders receipt rows lazily in a bounded viewport. Transfer, verification and revert semantics are unchanged.
- Local final checks: 53 focused tests pass; the macOS UI regression opens a 10,000-item app-owned fixture, confirms fewer than 100 rendered rows and closes the receipt (one test, zero failures, 7.980 seconds for the full scenario). These are development checks; they do not close the signed retest.
- Universal x86_64/arm64 Release MAS_BUILD, version 2.0, explicit build 507, macOS 14+. Exported package-extracted app passes strict/deep signature and App Store bundle validation, with Apple Distribution identity, hardened runtime and sealed resources; installer certificate chain is Apple-issued.
- Frozen identity, package hash and logs: `release-artifacts/2.0-507/`. No receipt or media mutations were required by this correction.

## Owner result, October 17

On the replacement TestFlight 507 check, the owner reports: “Loads and scrolls normally, all status matches.” This passes large-receipt rendering and verification of the 9,656 completed transfers. It does not claim a subsequent quit/reopen or Revert test. All regular PR #246 checks currently pass; Swift CodeQL remains in progress.

The owner subsequently reports “It survives a restart” after quitting/reopening Chronoframe and returning to the completed receipt. This closes the focused 507 receipt-loading persistence check. Revert is recorded below.

## Cancelled-run Revert, October 17

The owner reverted the 11:37 PM ABORTED 344-copy receipt. The signed app shows Revert Complete and zero issues. A subsequent independent read-only check confirms exactly all 344 receipt destinations are absent, all 9,656 destinations from the completed receipt still hash to their recorded identities, and all 10,000 fixture originals match the saved SHA-256 baseline. There are 9,656 destination media files, no unexpected or missing retained files and zero verification errors. Report: `.tmp/release-prep/507-revert-verification.json`. The UI summary uses copy counters and does not show a removed-file count, so the screenshot alone was not treated as exact-count proof.

## Preview and transfer after Revert

Owner screenshots confirm the same bulk10k source and Cancel test 504 destination preview at 10,000 discovered, 344 planned, 9,656 already present and zero issues. The 200 low-confidence date review items remain visible for the generated video fixtures. The subsequent transfer completes with 344 planned/copied, 9,656 skipped/already present and zero warnings, errors or issues. This demonstrates deleted-copy cache invalidation and successful recopy after Revert.

Final owner repeat-preview screenshot shows 10,000 discovered, zero planned/copied, 10,000 already present, zero duplicates and zero issues. Start Transfer is disabled. This closes the focused organize cancel/resume/revert/re-copy/repeat sequence.  An eight-file disposable exact-duplicate fixture (four distinct JPEG identities, two copies each) was prepared for the dedupe smoke below; baseline `.tmp/release-prep/507-dedupe-baseline.json`.

## Exact-deduplicate signed smoke

The owner scanned the eight-file disposable fixture and saw four Safe exact duplicate groups. Before review, the footer showed zero files would move; Accept All Safe selected four files in four reviewed groups. The owner committed the plan and the signed UI reports “Moved 4 files to Trash · 0.1 MB recoverable.” Independent local inspection confirms four JPEG keepers remain and every keeper matches its saved SHA-256; the completed dedupe receipt contains four items. Receipt: `dedupe_audit_receipt_20261018_004454_0DA8C08C-4AF6-43E2-AB35-0BDDFF71DE1B.json`.

The owner reports successful restoration through Run History. Independent read-only verification confirms all eight JPEG filenames and SHA-256 digests exactly match the pre-dedupe baseline, with no missing or extra JPEGs. This passes the focused signed exact-dedupe review → Trash → receipt → restore smoke. Report: `.tmp/release-prep/507-dedupe-restored-verification.json`. Pair/sidecar retention, trial dedupe allowance and other unrecorded scenarios are not implied by this eight-file exact-duplicate test.
