# Chronoframe 2.0 (506) — History access recovery

October 17, 2026 (America/Los_Angeles). Build 506 uploaded successfully at 16:43:59 PDT. App Store Connect completed processing. The signed retest exposed a large-receipt rendering blocker; build 506 is held. Required PR checks and owner Go remain pending. No App Review submission, pricing change or public release.

- Source commit: `98cae0a12d42b10133f822c16599f0c956bccf50`; archive source tree: `27b2e78433b7103e61ba68566f3acfeb118709a7`.
- [PR #246](https://github.com/Nishith/Chronoframe/pull/246) includes receipt sheet and verification scopes, independent history-load scopes, persistent per-archive bookmarks, and a guided same-folder reconnect action. It preserves loaded history on refresh failure and distinguishes unavailable history from a genuinely empty archive. The earlier completed-run bookmark finding is addressed and its thread resolved; hosted checks remain pending.
- [PR #245](https://github.com/Nishith/Chronoframe/pull/245) merged. Earlier 504/505 test evidence is preserved in their session ledgers.
- Full local sharded suite: 1,754 tests, 31 shards, zero failures. The subsequent canonical-folder alias correction passes all 16 focused receipt/History tests. Logs are copied under `release-artifacts/2.0-506/logs/`.
- Universal x86_64/arm64 Release `MAS_BUILD`, explicit build number 506, version 2.0, macOS 14+. Signed archive/export and actual package-extracted app pass App Store bundle validation and strict/deep signature verification, with Apple Distribution identity, hardened runtime, sandbox and sealed resources. Installer chain is Apple-issued 3rd Party Mac Developer Installer. Local MAS Gatekeeper rejection is not a signature or App Store installation failure.
- Archive/package/upload logs, frozen source identity and local validation package SHA-256 are recorded in `release-artifacts/2.0-506/release-record.json`. Upload re-exports the frozen archive; the local validation package hash does not claim identical upload re-export bytes.
- Apple build ID: `c7870b6e-1eaf-4414-ad37-43c08297bdb1`.

## Focused signed check

Update through TestFlight and confirm 2.0 (506). Open History for Downloads/Cancel test 504. Valid saved permission should restore automatically. If access fails, choose the same named folder through the new reconnect action; History must reload automatically without retargeting Setup or starting a transfer. Cancellation or selection of a different folder must preserve the archive and explain any mismatch.

Open the October 16 11:37 PM ABORTED receipt containing `233713` (344 copies), then the 11:40 PM COMPLETED receipt containing `234020` (9,656 copies), and run destination verification. All files must match; close/reopen the sheet and quit/reopen the app to check scope reacquisition. Coordinate any disposable Revert test separately. Do not reset settings, purchase or allowances, or remove the source, destination or receipt evidence.

No repeat purchase or 10,000-file transfer is required for this permission-only replacement. Restore Purchases, remaining signed dedupe/Photos coverage, hosted candidate CI, final store build/copy/free-pricing configuration and owner Go remain separate release requirements. There is no compiled acquisition cutoff or seven-day paid window.

After PR #245 merged, the two fix commits were rebased onto main; PR #246 head is `b5d085a3113fdf51534d7310939f7f01bc30a924`. Its full tracked tree exactly matches archive tree `27b2e78433b7103e61ba68566f3acfeb118709a7`; no rebuild is required for the history-only rebase. Required hosted checks rerun for the new head.

Processing completed. Saved the unchanged OS-only encryption answer (“None of the algorithms mentioned above”); App Store Connect shows build 506 Ready to Submit. The existing Internal testers group (two testers) is confirmed on build 506. Screenshot: `release-artifacts/2.0-506/testflight-ready.png`. Required hosted checks remain pending, with no failures observed.

## Owner retest and large-receipt blocker

The owner installed 506, opened the 344-copy ABORTED receipt, and reported every destination **Match** after Verify Status. Opening the 9,656-copy COMPLETED receipt then showed a blank, dimmed sheet. A read-only process sample recorded 2.2 GB footprint (2.8 GB peak); the sample found the main thread in the AppKit event loop, not proof of a CPU deadlock. The receipt decoded but its eager row layout did not render usefully. The sheet could be closed; the app was quit without changing transfer files or receipts.

The replacement uses a fixed-height lazy row list and background receipt read/decode with an independent security-scope lease. Local focused validation passed 53 tests. A real macOS UI regression opened an app-owned 10,000-item fixture, asserted fewer than 100 rendered rows and closed the sheet successfully (one test, zero failures, 7.980 seconds for launch/open/check/close). Evidence is retained locally in `.tmp/LargeReceiptRendering-Retry.xcresult` and `.tmp/large-receipt-ui-proof/`. This is development UI evidence, not a substitute for the replacement signed TestFlight retest. No repeat 10,000-file transfer or purchase is needed for this viewer correction.
