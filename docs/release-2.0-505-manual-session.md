# Chronoframe 2.0 (505) — History receipt access fix

October 17, 2026 (America/Los_Angeles). Signed archive, local export and upload succeed. Xcode reports upload success at 16:27:13 PDT and says the uploaded package is processing; App Store Connect confirms build 505 is Processing (Apple build ID `30c97731-df92-4195-9ff8-fa01491fad68`). TestFlight availability remains pending. The Apps page also requires Account Holder acceptance of an updated Apple Developer Program License Agreement before submission; the owner has been asked to review it. Not submitted for App Review. Signed retest and owner Go remain pending.

- Source commit: `fb69b5074643a941d1a99f969a3fc22c1009c93f`; archived tracked tree: `77cd5250047b2c8106f266090d893ce81f695012`.
- [Fix PR #246](https://github.com/Nishith/Chronoframe/pull/246) has protected auto-merge enabled; required CI and CodeQL are pending. It includes the release evidence from PR #245.
- The receipt sheet retains destination sandbox access while visible. Asynchronous destination verification has an independent lease retained until completion, including when the sheet closes. This changes no access policy, allowances, purchase behavior or transfer execution.
- Four focused receipt/History tests pass. The regression checks that History inspection reacquires the history destination bookmark rather than source access. Signed UI retest remains essential because local tests do not reproduce macOS sandbox enforcement.
- Universal x86_64/arm64 Apple Distribution archive/export: `release-artifacts/2.0-505/Chronoframe-MAS.xcarchive` and `mas-export/Chronoframe.pkg`, version 2.0, actual build 505, minimum macOS 14.0, `MAS_BUILD`, hardened runtime. Package-extracted app passes App Store bundle validation with macOS trust services and strict/deep code-signature validation. Restricted trust-service inspection initially could not identify the certificate; host-service validation confirms Apple Distribution. Local Gatekeeper rejection is not evidence of an ad hoc signature or a failed App Store installation.
- Local validation package SHA-256: `b9470255e8aa66d39e9033eeaf1595373853793c5cc5402d5a48597a85b4ced1`. Upload re-exports the same archive; this hash identifies the local validation export only.
- Archive/export/upload/signature and local test logs are preserved under `release-artifacts/2.0-505/` or `.tmp/receipt-viewer-tests-final.log`.

## Focused signed retest

1. Update through TestFlight and confirm About reports 2.0 (505); preserve settings, bookmarks, purchase and allowance state.
2. In History for `Downloads/Cancel test 504`, open the October 16 11:37 PM receipt containing `233713`. Expect ABORTED, 344 transfers, and no disk-read error.
3. Verify destination copies from this receipt: all 344 match. Close and reopen the sheet.
4. Open the 11:40 PM receipt containing `234020`: expect COMPLETED, 9,656 transfers; verify those copies too.
5. Quit/reopen and repeat receipt opening to verify bookmark reactivation.
6. Separately coordinate a disposable Revert check; do not erase the preserved destination before the read/verification checks pass. Keep original source fixtures untouched.

The [504 ledger](release-2.0-504-manual-session.md) records earlier successful allowance, sandbox purchase, relaunch, repeat-copy and independently hashed cancellation/resume evidence. Restore Purchases, remaining signed dedupe/Photos coverage, final candidate CI, store build/copy/free-pricing configuration and owner Go remain open. No acquisition cutoff, customer settings migration or seven-day paid rollout applies.

## Processing update

App Store Connect processing completed. Saved the unchanged “None of the algorithms mentioned above” export-compliance answer; build 505 now shows Ready to Submit. Owner reports accepting the updated Developer Program License Agreement. No App Review submission.

Automated review of PR #246 identified an additional scope gap when Setup replaces a destination bookmark during an active run and History later points back to the completed run. This remains open; 505 only contains the initial sheet/verification lifetime fix. Do not treat 505 as final release clearance.

## Signed test and requested recovery flow

The owner installed 505 through TestFlight. The October 17 16:33 screenshot shows a permission error while loading the History list, before any receipt can be selected. This does not establish missing receipts. The 505 receipt fix is not signed-clearance evidence.

The owner requested a direct History reconnection flow. The follow-up implementation adds a named-folder explanation and Choose Folder action; accepts only the same canonical archive root; saves refreshed access and reloads automatically without changing Setup/profile selection; preserves the last loaded snapshot during failed refreshes and replaces misleading empty states with History Unavailable. History loads now acquire their own scope, and per-archive bookmarks remain available after Setup/profile bookmark replacement. The follow-up changes are not in 505 and require a replacement signed build and focused retest. No settings or allowance reset, Full Disk Access grant, new transfer, or receipt deletion is part of recovery.

Local follow-up validation: the full sharded Swift suite passes 1,754 tests in 31 shards. A subsequent canonical-path normalization and alias regression have a separate focused rerun; see `.tmp/history-reconnect-canonical-tests.log`. The signed app has not yet validated this follow-up.

The final canonical-folder rerun passes all 16 receipt/History tests. Its first attempt caught an equivalent-folder URL comparison failure; comparison now uses canonical paths and the alias case passes. Full-suite log: `.tmp/history-reconnect-full-tests.log`; final focused log: `.tmp/history-reconnect-canonical-tests.log`.
