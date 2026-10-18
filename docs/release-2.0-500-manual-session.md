# Chronoframe 2.0 (500) — signed TestFlight release record

Prepared October 4, 2026. **Historical signed session, partly complete. Replacement candidate 501 fixes a subsequently discovered clipped purchase price; use [its session record](release-2.0-501-manual-session.md) for final Go.**

## Candidate

- Runtime source: `c722cad377058ffaf80d0ebb5e23820711ca2099` (subsequent release-branch edits are preparation documents).
- Version/build: **2.0 (500)**, universal Apple Silicon/Intel, macOS 14+.
- Grandfather cutoff: **2026-10-26T07:00:00Z** (October 26, 00:00 PDT).
- Package SHA-256: `16576870570e9604f3c7f6252dd9e1b9b6e27968cfb94ec424128416fe36ff3b`.
- Preserved archive and package: `release-artifacts/2.0-500/`.
- [TestFlight build](https://appstoreconnect.apple.com/teams/69a6de87-7410-47e3-e053-5b8c7c11a4d1/apps/6771245052/testflight/macos/f6e45a97-1d2d-4c23-b2f3-d99ee1edfce4): processed; existing Internal testers group shows Testing.
- Local baseline: 1,724 tests passed; meaningful line coverage 95.81%, raw aggregate 70.98%. Hosted candidate checks remain a separate gate.

Install this build through TestFlight. Use disposable copies of representative media and empty test destinations; keep personal originals outside the test mutation folders. A Debug or ad hoc app does not establish signed StoreKit/bookmark behavior.

## Session results

Enter PASS, FAIL, or an explicit residual limitation with evidence. No result below is pre-certified.

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

Before the future cutoff, a newly acquired TestFlight/sandbox transaction can correctly qualify for legacy access. That result does not establish the locked allowance or purchase prompt. Use the existing deterministic locked-state test seam for that interface and record its environment honestly. Production paid-purchase grandfathering must be checked during the later paid rollout; TestFlight cannot replace it.

Test device/macOS: Apple Silicon, macOS 27.0.1 (64 GB reported by Activity Monitor). Session date: October 4, 2026. Disposable fixtures, source hashes, receipts and verification JSON: `.tmp/release-prep/signed-session/`; durable evidence copy: `release-artifacts/2.0-500/signed-session-evidence/`. Actual app: TestFlight-installed `/Applications/Chronoframe.app`, verified bundle 2.0/500, universal, team EB2YPF68XZ. Original source/destination selections and Balanced dedupe preset were restored after the session. No personal-library mutation was performed.

**Crash receipt limitation:** the single last in-flight copy finalized just before its receipt spool append was safe and recognized by the queue, but absent from the recovered receipt. The recovered receipt has 1,775 entries for 1,776 finalized files; that one file is not separately revertable from the receipt. This matches the explicitly documented recovery contract in AGENTS.md; do not infer a receipt entry from the queue. The owner must acknowledge this residual limitation in Go.

**Cancellation remains unverified:** the automated cancel was issued after observing an active progress view, but the native-control observation delayed the action. By the time it arrived, the engine had completed all 8,224 remaining files and finalized the receipt COMPLETED. The UI displayed Cancelled with the earlier count of 2,909. This does not prove responsive mid-run cancellation or justify a passing result. Perform a direct human cancellation check on build 500, compare its displayed outcome with the receipt and actual files, and investigate if the discrepancy reproduces without automation delay.

The isolated Debug `settingsLicense` capture is a genuine allowance/restore interface screenshot, not signed StoreKit or purchase-flow evidence, and is not uploaded as the required IAP review screenshot.

## Store submission gates

- [x] Hosted CI and CodeQL green on `584b659` (runtime source identical to archived `c722cad`). Subsequent evidence-only edits require their own head checks before merge. [CI](https://github.com/Nishith/Chronoframe/actions/runs/37238611441), [CodeQL](https://github.com/Nishith/Chronoframe/actions/runs/37238611446).
- [x] Seven final screenshots and processed 29.8-second preview uploaded; order 01–07 persisted. Poster selected near 11.5 seconds; Apple’s editor reopened at the persisted whole-second 11 seconds.
- [ ] Genuine unlock-interface review screenshot uploaded to the IAP; app and first non-consumable IAP included together.
- [ ] Manual results above recorded; any residual limitations explained.
- [ ] Owner decision: **Go / No Go**, date and reason recorded here.

## Paid rollout and free transition

Release approved V2 manually while it remains paid. For the October 26 plan, paid V2 must be live no later than **October 18, 07:00 PDT** to finish seven days before the first regional free-price start. Prefer earlier. Verify actual paid purchasers, including purchasers during the V2 paid window, retain unrestricted access.

If review, rollout or verification slips, postpone the price change and ship a later compiled cutoff before October 26, 00:00 PDT. Never continue charging past the cutoff in the installed binary. Publish the free-trial website/social campaign only after the relevant storefront is actually free and access/purchase/restore work.
