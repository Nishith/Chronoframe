# Chronoframe 2.0 (507) — responsive large receipts

**October 19, 2026 update:** Apple rejected app 2.0 (507) under Guideline 2.1(b):
the reviewer could not find Chronoframe Unlock. Live App Store Connect confirms
the combined two-item submission, with the app Rejected and the IAP Ready for
Review. The focused replacement and required sandbox recording are tracked in
[the rejection response record](app-review-iap-rejection-2026-10-19.md).
The remaining text is historical build-507 validation, not approval or a replacement-build pass.

October 17, 2026 (America/Los_Angeles). Replacement for the large-receipt rendering blocker observed in signed build 506. Archive and local package validation pass; upload succeeded at 17:09:04 PDT. Apple processing completed, the unchanged export-compliance answer was saved, and the existing Internal testers group (two testers) is confirmed. The owner confirms the 9,656-item receipt loads and scrolls normally and every destination verification status is Match. The owner also confirms the receipt survives an app restart. The cancelled-run Revert, preview and re-copy after Revert, a final repeat preview and an eight-file exact-duplicate Trash-and-restore smoke also pass on this build, and PR #246 is merged. Remaining signed gates, final hosted candidate checks and owner Go remain pending. No App Review submission, pricing change or public release.

- Frozen source commit: `f54191843a7f95f0ad211c79714402e36ea7f4ea`; archive tree: `7fc1ca0b669ba0d982a5fbc355a191e0b7b704ff`.
- [PR #246](https://github.com/Nishith/Chronoframe/pull/246) retains per-archive sandbox access and provides guided same-folder reconnection. The final viewer correction moves file reading/JSON decoding off the main actor with an independent worker scope and renders receipt rows lazily in a bounded viewport. Transfer, verification and revert semantics are unchanged.
- Local final checks: 53 focused tests pass; the macOS UI regression opens a 10,000-item app-owned fixture, confirms fewer than 100 rendered rows and closes the receipt (one test, zero failures, 7.980 seconds for the full scenario). These are development checks; they do not close the signed retest.
- Universal x86_64/arm64 Release MAS_BUILD, version 2.0, explicit build 507, macOS 14+. Exported package-extracted app passes strict/deep signature and App Store bundle validation, with Apple Distribution identity, hardened runtime and sealed resources; installer certificate chain is Apple-issued.
- Frozen identity, package hash and logs: `release-artifacts/2.0-507/`. No receipt or media mutations were required by this correction.

## Next owner check

Update through TestFlight and confirm About shows 2.0 (507). In History for Downloads/Cancel test 504, open the COMPLETED receipt from October 16 at 11:40 PM (filename contains 234020). Confirm 9,656 files, visible rows, responsive scrolling and normal dismissal. Run Verify Status; all files must Match. Quit/reopen and check receipt loading again. Preserve both receipts, the destination and source files. Coordinate disposable Revert separately; no repeat purchase or 10,000-file transfer is required.

The owner already verified every destination Match in the 344-copy ABORTED receipt on signed 506. Earlier copy/allowance/purchase/relaunch and cancellation/resume evidence remains in [the 504 ledger](release-2.0-504-manual-session.md); the access and large-viewer failures are in [the 506 ledger](release-2.0-506-manual-session.md). Restore Purchases, remaining signed recovery/Photos coverage, the unrecorded dedupe scenarios (pair/sidecar retention and trial dedupe allowance), final hosted candidate checks, App Store draft build/copy/free pricing and owner Go remain separate gates. There is no legacy-acquisition cutoff or seven-day paid window.

Apple build ID: `72b05d39-e241-4b63-bf56-50ddd3df62e5`. Availability proof: `release-artifacts/2.0-507/testflight-ready.png`. Subsequent evidence-only commits update AGENTS.md and docs; the app source remains identical to the frozen archive commit.

## Owner result, October 17

On the replacement TestFlight 507 check, the owner reports: “Loads and scrolls normally, all status matches.” This passes large-receipt rendering and verification of the 9,656 completed transfers. It does not claim a subsequent quit/reopen or Revert test. All regular PR #246 checks currently pass; Swift CodeQL remains in progress.

The owner subsequently reports “It survives a restart” after quitting/reopening Chronoframe and returning to the completed receipt. This closes the focused 507 receipt-loading persistence check. Disposable Revert is not yet tested.

## Cancelled-run Revert, October 17

The owner reverted the 11:37 PM ABORTED 344-copy receipt. The signed app shows Revert Complete and zero issues. A subsequent independent read-only check confirms exactly all 344 receipt destinations are absent, all 9,656 destinations from the completed receipt still hash to their recorded identities, and all 10,000 fixture originals match the saved SHA-256 baseline. There are 9,656 destination media files, no unexpected or missing retained files and zero verification errors. Report: `.tmp/release-prep/507-revert-verification.json`. The UI summary uses copy counters and does not show a removed-file count, so the screenshot alone was not treated as exact-count proof. Preview after Revert remains the next check.

## Preview and transfer after Revert

Owner screenshots confirm the same bulk10k source and Cancel test 504 destination preview at 10,000 discovered, 344 planned, 9,656 already present and zero issues. The 200 low-confidence date review items remain visible for the generated video fixtures. The subsequent transfer completes with 344 planned/copied, 9,656 skipped/already present and zero warnings, errors or issues. This demonstrates deleted-copy cache invalidation and successful recopy after Revert. Final repeat preview remains to be recorded.

Final owner repeat-preview screenshot shows 10,000 discovered, zero planned/copied, 10,000 already present, zero duplicates and zero issues. Start Transfer is disabled. This closes the focused organize cancel/resume/revert/re-copy/repeat sequence. PR #246 merged on October 17 at 17:39:34 PDT. Prepared a new eight-file disposable exact-duplicate fixture (four distinct JPEG identities, two copies each) for the next signed dedupe/Trash/restore smoke; no deletion or scan result is yet claimed. Baseline: `.tmp/release-prep/507-dedupe-baseline.json`.

## Exact-deduplicate signed smoke

The owner scanned the eight-file disposable fixture and saw four Safe exact duplicate groups. Before review, the footer showed zero files would move; Accept All Safe selected four files in four reviewed groups. The owner committed the plan and the signed UI reports “Moved 4 files to Trash · 0.1 MB recoverable.” Independent local inspection confirms four JPEG keepers remain and every keeper matches its saved SHA-256; the completed dedupe receipt contains four items. Restoration remains untested. Receipt: `dedupe_audit_receipt_20261018_004454_0DA8C08C-4AF6-43E2-AB35-0BDDFF71DE1B.json`.

The owner reports successful restoration through Run History. Independent read-only verification confirms all eight JPEG filenames and SHA-256 digests exactly match the pre-dedupe baseline, with no missing or extra JPEGs. This passes the focused signed exact-dedupe review → Trash → receipt → restore smoke. Report: `.tmp/release-prep/507-dedupe-restored-verification.json`. Pair/sidecar retention, trial dedupe allowance and other unrecorded scenarios are not implied by this eight-file exact-duplicate test.
