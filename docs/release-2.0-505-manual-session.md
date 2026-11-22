# Chronoframe 2.0 (505) — History receipt access fix

**Historical evidence, 2026-10-17. Held and replaced by [506](release-2.0-506-manual-session.md) / [507](release-2.0-507-manual-session.md).** Signed archive, export and upload succeeded (Xcode upload success 16:27:13 PDT; Apple build ID `30c97731-df92-4195-9ff8-fa01491fad68`); processing completed and the unchanged "None of the algorithms mentioned above" export-compliance answer was saved. The owner's signed test hit a permission error loading the History list. Never submitted. The shipped build is 2.0 (511); see [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md).

- Source commit: `fb69b5074643a941d1a99f969a3fc22c1009c93f`; archived tracked tree: `77cd5250047b2c8106f266090d893ce81f695012`.
- [Fix PR #246](https://github.com/Nishith/Chronoframe/pull/246), merged 2026-10-17 as `ebb78c5`. It includes the release evidence from PR #245.
- The receipt sheet retains destination sandbox access while visible. Asynchronous destination verification has an independent lease retained until completion, including when the sheet closes. This changes no access policy, allowances, purchase behavior or transfer execution.
- Four focused receipt/History tests pass. The regression checks that History inspection reacquires the history destination bookmark rather than source access. Signed UI retest remains essential because local tests do not reproduce macOS sandbox enforcement.
- Universal x86_64/arm64 Apple Distribution archive/export: `release-artifacts/2.0-505/Chronoframe-MAS.xcarchive` and `mas-export/Chronoframe.pkg`, version 2.0, actual build 505, minimum macOS 14.0, `MAS_BUILD`, hardened runtime. Package-extracted app passes App Store bundle validation with macOS trust services and strict/deep code-signature validation. Restricted trust-service inspection initially could not identify the certificate; host-service validation confirms Apple Distribution. Local Gatekeeper rejection is not evidence of an ad hoc signature or a failed App Store installation.
- Local validation package SHA-256: `b9470255e8aa66d39e9033eeaf1595373853793c5cc5402d5a48597a85b4ced1`. Upload re-exports the same archive; this hash identifies the local validation export only.
- Archive/export/upload/signature and local test logs are preserved under `release-artifacts/2.0-505/` or `.tmp/receipt-viewer-tests-final.log`.

## Findings

- 505 contains only the first receipt-sheet and verification lifetime fix. The signed test (2026-10-17 16:33 screenshot) showed a permission error while loading the History list, before any receipt could be selected; this does not establish missing receipts.
- Automated review of PR #246 found an additional gap: Setup replacing a destination bookmark during an active run, then History pointing back to the completed run.
- The follow-up (not in 505) adds a named-folder explanation and Choose Folder action that accepts only the same canonical archive root, saves refreshed access and reloads without changing Setup, preserves the last loaded snapshot on failed refresh, shows History Unavailable instead of a misleading empty state, and keeps per-archive bookmarks after Setup bookmark replacement. Local validation: 1,754 tests in 31 shards; 16 receipt/History tests pass after canonical-path comparison replaced a URL comparison that failed on an alias case (`.tmp/history-reconnect-canonical-tests.log`, `.tmp/history-reconnect-full-tests.log`).
- Earlier 504 allowance, purchase, relaunch and cancellation/resume evidence stays in the [504 ledger](release-2.0-504-manual-session.md).
