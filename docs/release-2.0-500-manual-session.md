# Chronoframe 2.0 (500) — signed TestFlight release record

Prepared October 4, 2026. **Pending manual execution and owner Go decision.**

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
| Install/relaunch | Version 2.0 (500); selected folders/preferences persist; unavailable-folder guidance | Pending |
| Upgrade from public 1.1 | Preferences, folder access and existing receipts survive | Pending |
| Organize/repeat/revert | Original hashes unchanged; copies match; collisions preserved; repeat adds nothing; revert removes only matching copies | Pending |
| Deduplicate/restore | Reviewed targets only go to Trash; Keep-wins pairs/sidecars survive; restored bytes match | Pending |
| Force quit/recovery | Recover twice; originals untouched; partial result honest; retry idempotent | Pending |
| Apple Photos import | Cross-album selected originals match review; Photos library unchanged | Pending |
| Watched source batch | Import one pending item; other pending item remains visible | Pending |
| StoreKit/bookmarks | Signed-build paid access, restore, purchase cancellation, offline relaunch and folder scope | Pending |
| Allowance/purchase interface | Separate locked-state test evidence for 500/100 cumulative allowance, partial batch and ungated revert | Pending |
| Usability | Small window, light/dark, keyboard and VoiceOver through preview/review/confirmation/recovery | Pending |
| Real external drive | Model/format; organize; disconnect/reconnect; bookmark restore | Pending |
| 1,000-file regression | Count, bytes, cold/warm correctness, memory, cancellation | Pending |
| Approximately 10,000-file mixed library | Actual count/bytes, cold/warm correctness, memory, cancellation | Pending |

Before the future cutoff, a newly acquired TestFlight/sandbox transaction can correctly qualify for legacy access. That result does not establish the locked allowance or purchase prompt. Use the existing deterministic locked-state test seam for that interface and record its environment honestly. Production paid-purchase grandfathering must be checked during the later paid rollout; TestFlight cannot replace it.

Test device/macOS: Pending. Session date: Pending. Evidence/log locations: Pending.

## Store submission gates

- [ ] Hosted CI and CodeQL green on the final release-branch source.
- [ ] Seven final screenshots and 29.8-second preview uploaded; order and 11.5-second poster checked.
- [ ] Genuine unlock-interface review screenshot uploaded to the IAP; app and first non-consumable IAP included together.
- [ ] Manual results above recorded; any residual limitations explained.
- [ ] Owner decision: **Go / No Go**, date and reason recorded here.

## Paid rollout and free transition

Release approved V2 manually while it remains paid. For the October 26 plan, paid V2 must be live no later than **October 18, 07:00 PDT** to finish seven days before the first regional free-price start. Prefer earlier. Verify actual paid purchasers, including purchasers during the V2 paid window, retain unrestricted access.

If review, rollout or verification slips, postpone the price change and ship a later compiled cutoff before October 26, 00:00 PDT. Never continue charging past the cutoff in the installed binary. Publish the free-trial website/social campaign only after the relevant storefront is actually free and access/purchase/restore work.
