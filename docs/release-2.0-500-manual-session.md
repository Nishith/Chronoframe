# Chronoframe 2.0 (500) — signed TestFlight release record

**Historical evidence, 2026-10-04.** Signed TestFlight session on build 500 (pre-grandfather-cutoff policy). Superseded by later builds; shipped build is 2.0 (511), see [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md). The copy/revert/Trash/recovery/performance results below remain the evidence for those engines, which were unchanged in later builds.

## Candidate

- Runtime source: `c722cad377058ffaf80d0ebb5e23820711ca2099` (subsequent release-branch edits are preparation documents).
- Version/build: **2.0 (500)**, universal Apple Silicon/Intel, macOS 14+.
- Package SHA-256: `16576870570e9604f3c7f6252dd9e1b9b6e27968cfb94ec424128416fe36ff3b`.
- Preserved archive and package: `release-artifacts/2.0-500/`.
- [TestFlight build](https://appstoreconnect.apple.com/teams/69a6de87-7410-47e3-e053-5b8c7c11a4d1/apps/6771245052/testflight/macos/f6e45a97-1d2d-4c23-b2f3-d99ee1edfce4): processed; existing Internal testers group shows Testing.
- Local baseline: 1,724 tests passed; meaningful line coverage 95.81%, raw aggregate 70.98%. Hosted candidate checks remain a separate gate.

## Session results

| Check | Required evidence | Result |
|---|---|---|
| Install/relaunch | Version 2.0 (500); selected folders/preferences persist; unavailable-folder guidance | **Partial PASS:** TestFlight updated the existing installation to 500. Selected test folders survived normal quit and force quit/relaunch. Fresh install and unavailable-folder guidance remain. |
| Upgrade from public 1.1 | Preferences, folder access and existing receipts survive | **Partial PASS:** TestFlight previously listed installed 1.1 (332). Existing folder selections and dated dedupe-history entries were visible after update. Old receipt contents were not compared. |
| Organize/repeat/revert | Original hashes unchanged; copies match; collisions preserved; repeat adds nothing; revert removes only matching copies | **PASS on disposable fixtures:** 32/32 copies byte-identical; verification enabled, receipt COMPLETED. Repeat plans zero. Revert removed 31 unchanged copies, preserved one deliberately altered copy and an unrelated sentinel. All 11,036 source-fixture hashes unchanged. |
| Deduplicate/restore | Reviewed targets only go to Trash; Keep-wins pairs/sidecars survive; restored bytes match | **Partial PASS:** two reviewed exact copies moved to Trash and restored byte-identically; all 32 organized files matched sources afterward. RAW/Live Photo Keep-wins and shared sidecar deletion cases were not exercised in this signed session. |
| Force quit/recovery | Recover twice; originals untouched; partial result honest; retry idempotent | **PASS with documented receipt limit:** actual force quit left 1,776 finalized files and a PENDING receipt. Reopening recognized all 1,776 and offered 8,224 pending jobs. Resume finalized the original receipt ABORTED with 1,775 transfers and completed 8,224 remaining copies. Final 10,000 files exactly match the source multiset; completed files were not replaced. Second relaunch plans zero. See limitation below. |
| Apple Photos import | Cross-album selected originals match review; Photos library unchanged | Pending |
| Watched source batch | Import one pending item; other pending item remains visible | Pending |
| StoreKit/bookmarks | Signed-build paid access, restore, purchase cancellation, offline relaunch and folder scope | **Partial PASS:** pre-cutoff TestFlight account shows Unlocked; sandbox folder selections persisted and supported copy/Trash/restore/revert. Purchase, restore, cancellation, offline behavior and production paid transactions remain separate checks. |
| Allowance/purchase interface | Separate locked-state test evidence for 500/100 cumulative allowance, partial batch and ungated revert | Pending |
| Usability | Small window, light/dark, keyboard and VoiceOver through preview/review/confirmation/recovery | Pending |
| Real external drive | Model/format; organize; disconnect/reconnect; bookmark restore | Pending |
| 1,000-file regression | Count, bytes, cold/warm correctness, memory, cancellation | **Partial PASS:** 1,000 synthetic JPEGs, 15,402,194 bytes; all copies identical, zero failed jobs; receipt elapsed 8 seconds; warm preview plans zero; sampled RSS after completion ~471 MiB. Cancellation still requires direct validation. |
| Approximately 10,000-file mixed library | Actual count/bytes, cold/warm correctness, memory, cancellation | **Partial PASS:** 9,800 synthetic photos + 200 videos, 152,024,747 bytes; all 10,000 copies identical, zero failed jobs; receipt elapsed 77 seconds; warm preview plans zero. Separate crash/resume dataset also ended with exactly 10,000 matching files. Sampled RSS during that transfer ~571 MiB, not a measured peak. Cancellation inconclusive, as recorded below. |

Test device/macOS: Apple Silicon, macOS 27.0.1 (64 GB reported by Activity Monitor). Session date: October 4, 2026. Disposable fixtures, source hashes, receipts and verification JSON: `.tmp/release-prep/signed-session/`; durable evidence copy: `release-artifacts/2.0-500/signed-session-evidence/`. Actual app: TestFlight-installed `/Applications/Chronoframe.app`, verified bundle 2.0/500, universal, team EB2YPF68XZ. Original source/destination selections and Balanced dedupe preset were restored after the session. No personal-library mutation was performed.

**Crash receipt limitation:** the single last in-flight copy finalized just before its receipt spool append was safe and recognized by the queue, but absent from the recovered receipt. The recovered receipt has 1,775 entries for 1,776 finalized files; that one file is not separately revertable from the receipt. This matches the explicitly documented recovery contract in AGENTS.md; do not infer a receipt entry from the queue. This residual limitation applies to every later build.

**Cancellation:** an automated cancel on 500 arrived after the engine had finished (UI showed Cancelled at 2,909 while the receipt was COMPLETED), so it proved nothing. The direct human check found a stale terminal count on 501, fixed in 502 and retested there ([502](release-2.0-502-manual-session.md)).

Hosted CI and CodeQL were green on `584b659` (runtime identical to archived `c722cad`): [CI](https://github.com/Nishith/Chronoframe/actions/runs/37238611441), [CodeQL](https://github.com/Nishith/Chronoframe/actions/runs/37238611446).
