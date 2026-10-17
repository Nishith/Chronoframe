# Chronoframe 2.0 (504) — direct-free signed candidate

October 16, 2026 (America/Los_Angeles). **Uploaded, processed, export compliance saved, installed through TestFlight. About confirms 2.0 (504). Signed functional retests and owner Go remain open. No App Review submission or public release.**

## Source and identity

- Includes the merged cancellation and Photos capture-date fixes plus the owner-approved direct-free access rules.
- Archived source: `37e652aa58586c64806710e248d74ab88b97bae3`, [PR #244](https://github.com/Nishith/Chronoframe/pull/244).
- Frozen tracked tree: `6c722f9686cff7d957be6973162cb1f51781aed9`.
- PR #244 merged as `5f10b177573acc39cfdfdde72b7cabd995477a0d` on October 16 at 22:47:46 PDT. Its tracked tree exactly equals the frozen archive source tree above; only the commit identity differs after squash merge.
- All 22 regular CI checks plus the CodeQL analysis and report pass, including Swift tests, coverage, both Xcode build lanes, UI tests, accessibility audit and archive smoke. The post-merge main workflows are separate runs; their results are not inferred from the PR results.
- Archive: `release-artifacts/2.0-504/Chronoframe-MAS.xcarchive`.
- Local validation package: `release-artifacts/2.0-504/mas-export/Chronoframe.pkg`.
- Local package SHA-256: `302ec8f74c5fe15680192408c15b120297b38cce1a637862a65fd2e80052e6b5`.
- Explicit `CHRONOFRAME_BUILD_NUMBER=504`, Release, `MAS_BUILD`, universal arm64/x86_64, macOS 14+. Versions and architectures checked in the actual archive and package-extracted app.
- Package-extracted app passes App Store bundle validation and strict/deep signature verification: Apple Distribution, team EB2YPF68XZ, sealed resources, hardened runtime and sandbox/bookmark/Photos permissions. Apple-issued installer signature verified. Local MAS Gatekeeper rejection is not an App Store installation or notarization result.
- Upload re-exports the same frozen archive; the hash above identifies the local validation package, not an assertion that Xcode's upload re-export has identical signing bytes.

## Upload and installation

- Xcode reports Upload succeeded and EXPORT SUCCEEDED at October 16, 22:32:54 PDT.
- Apple build ID: `636a219c-3dc3-43f9-806a-d2c2b706c1c6`.
- Apple processing completed; TestFlight showed Ready to Submit after saving “None of the algorithms mentioned above” in the encryption algorithm question. The app implements no encryption outside Apple OS services. [Apple's documentation](https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/) requires no App Store Connect documentation for OS-only encryption.
- The existing Internal testers group (two testers) is attached automatically. No new testers or groups were added.
- Updated the installed app through TestFlight; About visibly confirms **Chronoframe Version 2.0 (504)**.
- Screenshots and machine-readable record are local under `release-artifacts/2.0-504/`: `processing.png`, `testflight-ready.png`, `installed-about.png`, `release-record.json`; archive/export/upload/signature logs are in `logs/`.
- App Store draft remains on 501 with the older paid-transition copy. Prepared screenshots/preview and manual release remain saved. Updating the draft build/copy and free app pricing are later actions after signed assessment. The lifetime unlock price and Family Sharing were not changed in this step.

## What has passed

The tested source tree passes 1,748 Swift tests in 31 shards with zero failures. Meaningful coverage is 95.80% (17,301/18,059 selected deterministic lines), distinct from raw Swift coverage. Local universal Release MAS_BUILD compilation, signed archive/export, actual package validation and TestFlight installation pass. No signed purchase, allowance, Photos date/pair or cancellation/recovery result on 504 is claimed by installation alone.

## Next signed checks, in order

### Owner testing, October 16–17: partial results and blocking finding

- Owner screenshots show the initial 500/100 allowance, 20-file consumption to 480/100 and persistence after relaunch. Owner reports the 20-file revert refunded the allowance.
- The oversized 1,000-file run offered an explicit earliest-500 free batch. The batch completed with 500 copied and zero issues; the exhausted allowance blocked the remaining 500 without another free-batch option.
- Owner reports purchase cancellation preserved the trial state. Apple's test purchase dialog explicitly said no charge; its success dialog and the subsequent 500-file transfer demonstrate sandbox purchase and unlock. License remains Unlocked after relaunch. Repeat preview recognizes all 1,000 files with zero planned. Restore Purchases remains untested.
- Owner reports Photos transfer completion and matching date folders/pairs in Downloads/Test 504. Repeat screenshots show six selected resources already present and zero planned. The owner used different photos from the historical set; the original eight-resource regression set, metadata identities and receipt hashes have not been independently established for this test.
- Mid-copy cancellation in Downloads/Cancel test 504 stopped at 344 copies. After relaunch, preview recognized 344 already present and 9,656 remaining. Resumed transfer completed 9,656 with zero issues; final preview recognizes all 10,000 with zero planned.
- Independent read-only verification rehashed all 10,000 copies against source bytes and recorded receipt identities, and all source SHA-256 values against the saved pre-test baseline. The ABORTED receipt contains 344 transfers and the COMPLETED receipt 9,656, both with verification enabled and zero failed jobs. No missing, extra or duplicate destination media entries. Local report: `.tmp/release-prep/504-cancel-resume-verification.json`.
- **Release blocker:** opening the cancelled run's 11:37 PM receipt from History displays “Could not read the receipt file from disk.” The JSON remains readable and valid outside the sandboxed app. The receipt detail sheet reads and verifies files without reacquiring the destination security scope after the History scan closes its scope. A local fix is under validation; 504 does not contain it. Do not submit 504 as the final candidate. A replacement signed build needs focused History read/verification and recovery retests.

- Local receipt-viewer fix retains destination access for the sheet lifetime and a separate lease through asynchronous verification. Four focused receipt/History tests pass, including destination-bookmark selection instead of source access. This is local validation, not a signed sandbox retest. Log: `.tmp/receipt-viewer-tests-final.log`.

The checklist below records the intended gates; the observations above close only the stated portions.

1. Record Settings → License on 504. With a controlled fresh test account/state, confirm the initial 500 organized files and 100 duplicates allowance; no acquisition date or old cached legacy grant should unlock it. Do not reset the owner's settings, bookmarks or usage ledger. Reinstalling is not an allowance reset.
2. Use disposable fixtures to check consumption, relaunch persistence, oversized-run refusal/free test batch and ungated revert refunds.
3. Test sandbox purchase cancellation, successful lifetime unlock, relaunch and Restore Purchases. Keep sandbox results separate from later production purchase evidence.
4. After confirming the sandbox unlock, import the same three Live Photos and two standalone videos into a new empty disposable destination. Verify all eight resources and receipt hashes; August pairs together under `2026/08/01`, October pair under `2026/10/04`, standalone videos under `2026/01/30` and `2026/07/17`. Scan-only Deduplicate must recognize all three pairs. Repeat import should copy nothing new. Preserve the old Test iPhotos failure evidence and personal Photos library unchanged.
5. With the sandbox unlock confirmed, repeat mid-copy cancel/resume on the disposable 10,000-file fixture and a new destination. UI counts, finalized receipts and files must agree; resume completes without duplicates and all originals match the saved baseline. This test exceeds the free allowance, so the expected paywall before purchase is not a transfer bug.
6. Close other signed release checks or record accepted limitations and owner Go for the exact candidate. Then prepare free app pricing and the updated app/IAP submission with manual release. No seven-day paid rollout or customer migration applies.
