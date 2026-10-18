# Chronoframe 2.0 (507) — responsive large receipts

October 17, 2026 (America/Los_Angeles). Replacement for the large-receipt rendering blocker observed in signed build 506. Archive and local package validation pass; upload succeeded at 17:09:04 PDT. Apple processing completed, the unchanged export-compliance answer was saved, and the existing Internal testers group (two testers) is confirmed. Signed retest, hosted checks and owner Go remain pending. No App Review submission, pricing change or public release.

- Frozen source commit: `f54191843a7f95f0ad211c79714402e36ea7f4ea`; archive tree: `7fc1ca0b669ba0d982a5fbc355a191e0b7b704ff`.
- [PR #246](https://github.com/Nishith/Chronoframe/pull/246) retains per-archive sandbox access and provides guided same-folder reconnection. The final viewer correction moves file reading/JSON decoding off the main actor with an independent worker scope and renders receipt rows lazily in a bounded viewport. Transfer, verification and revert semantics are unchanged.
- Local final checks: 53 focused tests pass; the macOS UI regression opens a 10,000-item app-owned fixture, confirms fewer than 100 rendered rows and closes the receipt (one test, zero failures, 7.980 seconds for the full scenario). These are development checks; they do not close the signed retest.
- Universal x86_64/arm64 Release MAS_BUILD, version 2.0, explicit build 507, macOS 14+. Exported package-extracted app passes strict/deep signature and App Store bundle validation, with Apple Distribution identity, hardened runtime and sealed resources; installer certificate chain is Apple-issued.
- Frozen identity, package hash and logs: `release-artifacts/2.0-507/`. No receipt or media mutations were required by this correction.

## Next owner check

Update through TestFlight and confirm About shows 2.0 (507). In History for Downloads/Cancel test 504, open the COMPLETED receipt from October 16 at 11:40 PM (filename contains 234020). Confirm 9,656 files, visible rows, responsive scrolling and normal dismissal. Run Verify Status; all files must Match. Quit/reopen and check receipt loading again. Preserve both receipts, the destination and source files. Coordinate disposable Revert separately; no repeat purchase or 10,000-file transfer is required.

The owner already verified every destination Match in the 344-copy ABORTED receipt on signed 506. Earlier copy/allowance/purchase/relaunch and cancellation/resume evidence remains in [the 504 ledger](release-2.0-504-manual-session.md); the access and large-viewer failures are in [the 506 ledger](release-2.0-506-manual-session.md). Restore Purchases, remaining signed recovery/dedupe/Photos coverage, final hosted candidate checks, App Store draft build/copy/free pricing and owner Go remain separate gates. There is no legacy-acquisition cutoff or seven-day paid window.

Apple build ID: `72b05d39-e241-4b63-bf56-50ddd3df62e5`. Availability proof: `release-artifacts/2.0-507/testflight-ready.png`. Subsequent evidence-only commits update AGENTS.md and docs; the app source remains identical to the frozen archive commit.
