# Chronoframe V2 — final check and launch checklist

**Status (2026-11-21).** This is the authoritative launch record and the list of what is still open. V2 shipped: App Store Connect shows **2.0 Ready for Distribution / Chronoframe Unlock Approved** (2026-10-22), and the public US listing (checked 2026-11-21) shows **Free**, version 2.0 current since 2026-10-22, an in-app purchase "Chronoframe Unlock $14.99" and 0 ratings. Only the US storefront was checked; the 175-storefront $0.00 claim comes from App Store Connect's saved price table. Historical build-by-build detail lives in the per-build ledgers ([500](release-2.0-500-manual-session.md) to [507](release-2.0-507-manual-session.md), [511](app-review-replacement-511-2026-10-21.md)); this file does not repeat it. Gate definitions are in [remaining-work-plan.md](remaining-work-plan.md#version-20-release-scope-revised-2026-09-28); certification evidence is in [production-readiness-certification.md](production-readiness-certification.md).

**Shipping state.** Submitted **2.0 (511) + Chronoframe Unlock** together on 2026-10-21 at 9:46 PM PDT (submission `42e45604-bc72-4236-a1a1-8bca697a7884`, manual release) after the owner replied **Go**. 2.0 (507) was rejected 2026-10-19 under 2.1(b) because the reviewer could not find Chronoframe Unlock; the direct Settings → License → Unlock entry shipped in PR #251, and 511 added the Deduplicate-offer observation fix (PR #252, merged 2026-11-16 as `03e8d1a`). Access policy: free download; 500 organized files and 100 duplicates moved to Trash (cumulative per Apple Account per Mac); one $14.99 US lifetime non-consumable (`com.nishith.chronoframe.unlock`, Apple ID 6819083459, Family Sharing on); ungated revert with allowance refunds; no subscription. Details: [release-2.0-direct-free-access.md](release-2.0-direct-free-access.md) and [APP_STORE_RELEASE.md](APP_STORE_RELEASE.md#direct-free-launch).

**Still open:** public-store install and fresh-customer check, website/Pages verification, launch copy and posts, film audition and YouTube/social upload, first-week monitoring (sections 5 and 6). The signed scenarios listed under "Accepted residual coverage" in section 3 were accepted at Go and are not passes.

Distribution: Mac App Store only. Store identifiers: app `6771245052`, bundle `com.nishith.chronoframe`, team `EB2YPF68XZ`, minimum macOS 14.

## Prepared store assets (evidence)

| Item | Result |
|---|---|
| Release source | Runtime `6df85b4` for 501, merged as [PR #239](https://github.com/Nishith/Chronoframe/pull/239) (`e67bc9f`, 2026-10-05). Shipped source is 511 at `3b38279` (see the 511 ledger). |
| Screenshots | Seven final PNGs, 2880×1800, in `marketing/release-2.0/screenshots/`, uploaded and ordered 01–07 in App Store Connect. History heading reads "Receipts for safer undo." |
| App Store preview | `marketing/app-preview/exports/Chronoframe-App-Store-Preview.mp4`, 29.8 s, 1920×1080 H.264, ~41.7 MB; poster near 11.5 s, which Apple persists as 11 s. The file was verified technically; the music was not auditioned. |
| Unlock product | Non-consumable `com.nishith.chronoframe.unlock`, US $14.99, 175 territories, Family Sharing on. The real signed IAP screenshot (1440×900, from build 511) replaced the earlier developer-fixture capture; direct-navigation notes saved. |
| Account requirements | Paid and Free Apps agreements, bank, W-9 and Digital Services Act all Active; Photo & Video category; age rating 4+; privacy declaration Data Not Collected. |
| Media backup | `release-artifacts/2.0-500/marketing-source-and-exports.tar.gz` — a second local copy, not an off-device backup. |
| Social films | `marketing/social-video/exports/` (4K, 1080p, vertical, captions, thumbnail); technical checks passed. |
| Launch copy | `marketing/release-2.0/LAUNCH_COPY.md`; not published. |
| Hosted checks | 511 frozen source `3b38279`: all 22 CI jobs plus CodeQL (24 checks) passed. |

## 1. Freeze the direct-free candidate

- [x] Preserve source footage, scripts, provenance, exports, signed archive and package under `release-artifacts/2.0-500` (and per-build under `release-artifacts/2.0-50x`).
- [x] Release from clean tracked source containing every final fix (511 at `3b38279`).
- [x] Hosted CI and CodeQL on the shipped source: passed on `3b38279` (24 checks). Supersedes the earlier merged-main check on `e67bc9f`.
- [x] Owner confirmed no existing customers and approved direct free download with a $14.99 US lifetime unlock (2026-10-16).
- [x] Disable acquisition-date and cached legacy grants in the shipping policy; keep the 500/100 allowance and ungated refunding revert ([record](release-2.0-direct-free-access.md)).
- [x] Build and install a signed candidate containing the direct-free policy ([504](release-2.0-504-manual-session.md) onward; shipped 511).
- [x] Replace 504 after the History receipt-viewer permission failure; receipt loading and verification retested on signed 507 ([PR #246](https://github.com/Nishith/Chronoframe/pull/246), merged 2026-10-17).
- [x] Explicit unused build number: the stamp script accepts `CHRONOFRAME_BUILD_NUMBER`; do not assume `CURRENT_PROJECT_VERSION = 2` is the exported build number.

No seven-day paid hold or acquisition cutoff applies. Developer ID notarization and the 100,000-file / 1-TB certification are outside V2 scope.

## 2. Create the lifetime unlock and upload the signed build

- [x] Create **Non-Consumable** `com.nishith.chronoframe.unlock`, "Chronoframe Unlock", US $14.99, territories selected, **Family Sharing ON** (cannot be turned off afterward), localized description "Unlimited organizing and duplicate cleanup.", review screenshot and metadata.
- [x] Business: agreements, banking, tax and Digital Services Act Active.
- [x] Build with the non-local MAS script (`CHRONOFRAME_BUILD_NUMBER=<n> ./ui/archive-mas.sh`; `--local` is unsigned structure validation only). Version 2.0, explicit build, arm64 + x86_64, macOS 14, sandbox/bookmark/Photos entitlements, privacy manifest, Apple Distribution signing.
- [x] Preserve archive and package before rerunning the script (it replaces its previous output); record commit, build, archive identity and package SHA-256.
- [x] Upload through Xcode Organizer or Transporter; processing and export-compliance answer ("None of the algorithms mentioned above") saved.

## 3. Final TestFlight session

- [x] Processed replacement in the Internal testers group, installed through TestFlight, About confirms the build (511 shipped).
- [x] Focused manual session, per [remaining-work-plan.md](remaining-work-plan.md#version-20-release-scope-revised-2026-09-28), with results recorded per build:
  - copy, repeat, revert and reviewed exact-duplicate Trash/restore: [500](release-2.0-500-manual-session.md), [507](release-2.0-507-manual-session.md);
  - force-quit recovery and mid-copy cancel/resume with receipts reconciled: [500](release-2.0-500-manual-session.md), [502](release-2.0-502-manual-session.md), [504](release-2.0-504-manual-session.md);
  - Photos date/pair import: owner-reported on 504 with different photos from the original regression set;
  - 1,000-file and ~10,000-file correctness and memory: [500](release-2.0-500-manual-session.md), [504](release-2.0-504-manual-session.md);
  - large-receipt viewer, History reconnect and cancelled-run revert: [507](release-2.0-507-manual-session.md).
- [x] StoreKit and allowance: initial 500/100, consumption, relaunch persistence, oversized-run refusal, free test batch, ungated revert refunds, purchase cancellation, sandbox purchase and relaunch ([504](release-2.0-504-manual-session.md), [508](app-review-iap-rejection-2026-10-19.md)); positive owned Restore on signed 510 and fresh-account negative Restore on 511 ([510](app-review-resubmission-2026-10-21.md), [511](app-review-replacement-511-2026-10-21.md)). Sandbox results stay separate from production purchase evidence.
- [x] Owner **Go** recorded 2026-10-21 for 2.0 (511), with the evidence packet and the residual coverage below.

**Accepted residual coverage (owner assessment at Go; not passes):** kept RAW/Live Photo pair and sidecar retention; trial dedupe allowance and refund; exact Photos regression resource identities and pairs on the final build; remaining forced-interruption and recovery scenarios; real external-drive scenarios (advertised drives); fresh install and unavailable-folder guidance; old-receipt upgrade contents; small-window, light/dark, keyboard and VoiceOver walkthrough. A concrete safety failure blocks release; none was recorded.

## 4. V2 store page and combined submission

Draft: [App Store Connect version](https://appstoreconnect.apple.com/apps/6771245052/distribution/macos/version/inflight). Values: [APP_STORE_METADATA.md](APP_STORE_METADATA.md).

- [x] Version **2.0**, build **511** selected; app and the first IAP submitted together; **Manually release this version** selected.
- [x] Description, promotional text, What's New and review notes use the direct-free values (saved metadata confirmed 2026-10-21); description says macOS 14.0 or later and qualifies recovery (files must remain in Trash with their recorded contents).
- [x] Review notes state **500 organized files + 100 duplicates trashed**, cumulative per Apple Account per Mac, one non-consumable lifetime unlock, ungated revert; direct purchase path (Settings → License → Unlock Chronoframe…) and the physical-Mac recording attached to App Review Information. No sign-in or demo account.
- [x] Review contact, category, URLs, privacy declaration and age rating confirmed; the disabled Library Guardian feature is not advertised.
- [x] Seven numbered screenshots (not `contact-sheet.png`) and the preview uploaded.
- [x] Submit for Review: 2026-10-21 at 9:46 PM PDT, both items Waiting for Review.

Apple references: [Mac screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications), [IAP submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/), [app submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/).

## 5. Release free V2 with the lifetime unlock

- [x] Released: 2.0 Ready for Distribution, Unlock Approved (2026-10-22).
- [x] Free pricing. The $14.99 download price was missed at resubmission; a global **$0.00** price change (175 regions) was applied 2026-10-22 and confirmed in App Store Connect's price table after reload. Unlock stayed $14.99 US. See [the 511 ledger](app-review-replacement-511-2026-10-21.md).
- [x] Public US listing shows Free, 2.0, Unlock $14.99 (checked 2026-11-21).
- [ ] Verify the public listing's screenshots, preview and compatibility, and the free price in storefronts other than US.
- [ ] Install from the public store; verify a fresh customer's 500/100 allowance, production purchase and Restore, and the core workflow.
- [ ] Website: the Download button and App Store link are in `site/index.html`, but every `site/**` push to `main` deploys immediately, so verify the live Pages deployment, video, allowance terms, privacy/support links and CTA. Recheck publication dates and the development-capture labels in `site/assets/product-proof.json`.
- [ ] README, store and marketing copy match the actual free offer.

## 6. Send out the marketing assets

| Destination | File |
|---|---|
| Mac App Store preview | `marketing/app-preview/exports/Chronoframe-App-Store-Preview.mp4` |
| App Store screenshots | `marketing/release-2.0/screenshots/` |
| YouTube horizontal | `marketing/social-video/exports/Chronoframe-YouTube-4K.mp4` |
| YouTube thumbnail | `marketing/social-video/exports/Chronoframe-YouTube-Thumbnail.jpg` |
| Shorts / Reels / vertical posts | `marketing/social-video/exports/Chronoframe-Social-Vertical-1080x1920.mp4` |
| Vertical cover | `marketing/social-video/exports/Chronoframe-Vertical-Poster.png` |
| YouTube captions | `marketing/social-video/exports/Chronoframe-Youtube.srt` |
| Draft titles/descriptions | `marketing/social-video/publishing-copy.md` |

- [ ] Play the App Store and social films once with sound and once muted; confirm caption readability, covers and the call to action on a phone. Technical checks passed; the music was not auditioned.
- [ ] Upload the 4K video to YouTube as **unlisted** first (thumbnail, title, description, captions, photo/music credit); inspect HD/4K playback before publishing. No video is uploaded or published; the YouTube Studio upload dialog was only prepared.
- [ ] Prepare vertical posts as drafts with the provided captions and cover.
- [x] Replacement Reddit/Show HN launch copy prepared (`marketing/release-2.0/LAUNCH_COPY.md`, `marketing/macapps-launch-post-2026-11.md`). Review each community's current posting rules before posting.
- [ ] Publish YouTube and the initial announcement after the website/store checks pass; spread community posts out and disclose that you are the developer; include [chronoframe.app](https://chronoframe.app/) and the [App Store listing](https://apps.apple.com/us/app/chronoframe/id6771245052).
- [ ] First week: check support messages, reviews, TestFlight/crash feedback, purchase/restore failures and copy/Trash/recovery reports daily; pause promotion if a core safety or access failure appears.

Initial audit baseline, for the record: `main` at `9a96e83` (2026-10-04), [CI](https://github.com/Nishith/Chronoframe/actions/runs/37224530853) and [CodeQL](https://github.com/Nishith/Chronoframe/actions/runs/37224530851); all 13 static guards and 26 invariant tags passed. Earlier [local manual session](release-2.0-manual-session.md) findings F1 (exFAT) and F2 (hidden Trash names) were fixed in #237 and #236.
