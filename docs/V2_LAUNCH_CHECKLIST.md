# Chronoframe V2 — final check and launch checklist

Checked October 4, 2026 (America/Los_Angeles). Distribution: Mac App Store only.

Release preparation is in progress. **2.0 (500) is uploaded and selected**, with the seven screenshots and preview saved. A final capture exposed a clipped purchase price; the fix and rendering regression are committed, and signed replacement **2.0 (501) is prepared locally**. Its upload, remaining signed checks and owner Go decision still gate submission. Planned free date: **October 26, 2026**.

## Execution update — October 4

**Replacement candidate 501:** the original 420pt unlock sheet compressed “Chronoframe Unlock · $14.99” into “Chronoframe Unlo…”. The production purchase button now has its own line above Restore/Not Now. A bitmap/OCR regression fails on the original layout and passes on the fix; all 25 focused unlock tests pass. Runtime source is `6df85b4b3ef96fa5f2165c29d35627f3d92e50d3`. The signed universal archive/export and actual package signature/entitlements passed; preserved package SHA-256 is `c0b5972e7f4198ffc40fdb675d829278118a02a092f5e409302c56ce92482ab9`. The cutoff is unchanged. Replacement upload and selection approval are pending; do not submit selected build 500. See [the 501 session record](release-2.0-501-manual-session.md).

A genuine capture of the corrected production view is prepared at `marketing/release-2.0/iap-review/Chronoframe-Unlock-Review.png` (1440×900), with developer test-state metadata and provenance. It establishes the visible interface, not live StoreKit purchase/restore. New screenshot upload approval is pending. Apple's [IAP reference](https://developer.apple.com/help/app-store-connect/reference/in-app-purchases-and-subscriptions/in-app-purchase-information/) requires a review-only screenshot meeting a supported app screenshot size.

| Work | Current result |
|---|---|
| Release source | `c722cad` on `codex/release-v2-preparation`; [draft PR #239](https://github.com/Nishith/Chronoframe/pull/239). Based on final fixes at `9a96e83`. |
| Cutoff | `2026-10-26T07:00:00Z`, midnight PDT. Apple’s latest regional start for October 26 is 03:00 UTC; four-hour late margin favors paid customers. Earliest regional start is October 25 at 14:00 UTC. |
| Rollout deadline | For October 26, finish seven live-and-paid days before the earliest regional transition: paid V2 must be live by **October 18, 07:00 PDT**. Prefer earlier. If this slips, postpone the free date and ship a later cutoff before October 26, 00:00 PDT. Never keep charging beyond the cutoff in the installed binary. |
| Local verification | **1,724 Swift tests passed**, all shards. Meaningful line coverage **95.81%**, raw aggregate **70.98%**. Restricted sandbox initially prevented package metadata lookup; traversal and the full lane passed with normal macOS access. |
| Signed package | **2.0 (500)**, universal arm64/x86_64, macOS 14, MAS_BUILD, valid Apple Distribution signature, hardened runtime, sandbox/folder/bookmark/Photos entitlements, privacy manifest and provisioning profile. Exported app inspected inside the actual package. |
| Build upload | Xcode reports **Upload succeeded / EXPORT SUCCEEDED**. Processing completed, export-compliance answer saved, and **2.0 (500) is Testing in the existing Internal testers group**. No review submission made. |
| Package identity | SHA-256 `16576870570e9604f3c7f6252dd9e1b9b6e27968cfb94ec424128416fe36ff3b`. Archive and package preserved under `release-artifacts/2.0-500`. |
| Store listing | Version 2.0 saved; description, promotional text, What's New, keywords and reviewer notes updated. Minimum macOS corrected, recovery qualified, manual release selected. **Processed build 2.0 (500) is selected and saved**; expired build 373 unlinked. Required recorded-time-zone folder migration note added for upgrades from public 1.1. |
| Unlock product | Non-consumable `com.nishith.chronoframe.unlock`, Apple ID **6819083459**, created. Family Sharing visibly enabled, English localization saved, US $14.99 pricing configured, all 175 territories selected. Availability and corrected review notes persisted after reload; product remains a draft. Review screenshot still needed. |
| Screenshots | Seven final PNGs, 2880×1800. History heading corrected to “Receipts for safer undo.” All tracked in PR #239. Old eight images replaced with owner approval. **All seven final screenshots uploaded, arranged 01–07 and persisted after reload.** |
| App Store preview | Owner enabled Chrome file access; approved upload succeeded. Apple processed the 29.8-second preview. Selected 11.5-second poster; Apple’s editor reopened at the persisted whole-second position **11 seconds**. One preview and seven screenshots saved. |
| Account requirements | Paid and free agreements, bank account, W-9 and Digital Services Act compliance all **Active**. Photo & Video category confirmed. Updated age-rating questionnaire completed (new Social Media questions answered No); calculated rating stays **4+**. No legal agreement accepted or financial details changed. |
| IAP review capture | Corrected production unlock sheet captured in an isolated developer host at 1440×900; full product name, $14.99 and Restore visible; new upload approval pending. Earlier genuine License UI captured from an isolated Debug copy using the existing deterministic `settingsLicense` fixture. It shows allowance/restore, not the purchase flow, so it has not been uploaded as the required IAP screenshot. Signed build 500 currently shows Unlocked for the pre-cutoff TestFlight account; this does not test a post-cutoff purchase. |
| Signed app checks | Installed **2.0 (500)** through TestFlight. Folder selections survived relaunch. 32/32 copies match source bytes; repeat plans zero. Two reviewed exact copies moved to Trash, then restored byte-identically. Revert removed 31 unchanged copies and preserved one deliberately modified copy plus an unrelated sentinel. Source hashes unchanged. Both 1,000- and 10,000-file runs copied all files correctly; warm previews plan zero. Actual force quit/resume produced exactly 10,000 matching files; second relaunch plans zero. The documented single in-flight receipt gap was observed. Cancellation remains inconclusive due delayed automation; a direct manual check is required. Further scenarios remain in the candidate session record. |
| Media backup | `release-artifacts/2.0-500/marketing-source-and-exports.tar.gz` preserves source footage, scripts, provenance and exports. This is a second local copy, not an off-device backup. Generated media are now explicitly git-ignored. |
| YouTube draft | YouTube Studio is signed into the **Nishith Nand** channel. Upload dialog prepared; specific file/destination approval requested. No video uploaded or published. File access is now available; YouTube upload approval is still pending. |
| Launch copy | `marketing/release-2.0/LAUNCH_COPY.md` has current free-tier social/community copy. Historical drafts are marked obsolete for this launch. No public post published. |
| Held website | PR #226 remains held. Planned video publication date changed to October 26; sitemap modification dates updated to October 4. Recheck if launch moves. No website deployment triggered. |
| Hosted checks | PR #239 at `584b659`: SwiftPM tests, meaningful coverage, ordinary/MAS builds, UI tests, accessibility audit, archive smoke and all static guards passed. CodeQL analysis passed; **all hosted checks green on 584b659**. Subsequent evidence-only edits need their own head checks before merge. Latest main's standalone SwiftPM job was cancelled, while coverage and other main gates passed. Require candidate checks before merging/submitting. |

Media preparation in [the V2 draft](https://appstoreconnect.apple.com/apps/6771245052/distribution/macos/version/inflight) is complete: seven numbered PNGs and the processed 29.8-second preview are saved. The poster was selected near 11.5 seconds; Apple persists it at 11 seconds. Supply a purchase-flow IAP review screenshot and complete the remaining signed TestFlight scenarios before adding app and IAP to review. Build 500 is selected. Replace selected build 500 with 501 after its approved upload/processing. Use [the 501 candidate session record](release-2.0-501-manual-session.md) for the remaining checks and owner decision; the completed 500 session remains historical evidence.

## Initial audit snapshot

The table below records the starting state, before the execution update above.

## What was checked

| Item | Result and evidence |
|---|---|
| Current GitHub `main` | `9a96e83c6a1a4ce7bae7da156f81c349da8e8f92`. Includes the exFAT fix (#237), visible Trash names (#236), IAP fixes (#212), and remaining destination-record hardening (#238). |
| Hosted automated gates | On `9a96e83`, CodeQL, meaningful coverage, ordinary and MAS builds, UI tests, accessibility, archive smoke, and static guards passed. SwiftPM tests were still running at the audit snapshot; require that job to finish successfully. The previous commit `1473c417` has a fully successful CI run; the newer commit adds ten invariant-tag comments to tests, with no product code change. |
| Local static verification | All 13 static guard scripts passed against a downloaded snapshot of `9a96e83`, including all 26 invariant tags, Photos read-only, verified Guardian restore, StoreKit configuration, recovery routing, and UI titles. `git diff --check` passed in the working checkout. Tag coverage is not a claim that every safety scenario was manually tested. |
| Working checkout | Branch `chore/demo-photo-library-scripts`, HEAD `ef1c036`. It predates the final fixes. Do not create the release from this checkout without updating or using a separate clean checkout of current `main`. Existing `marketing/` and `site/guides/` files were untracked before this audit; preserve them. |
| Version and platform | Project marketing version is 2.0, bundle ID `com.nishith.chronoframe`, development team `EB2YPF68XZ`, minimum macOS 14. Both architecture support and actual sandbox entitlements must also be confirmed in the final archive. |
| Pricing cutoff | Current `main` still compiles `grandfatherCutover = 2100-01-01T00:00:00Z`. Safe while downloads are paid, but unsuitable for the free-download launch: future free downloaders would receive legacy unrestricted access. |
| App Store Connect draft | **1.2 — Prepare for Submission**, with build **1.2 (373)** from June 21 selected. Eight older screenshots, **zero app previews**, old release notes and review notes. Description incorrectly says macOS 13 and promises users can “always recover” trashed files. Automatic release after approval is selected. |
| App Store Connect IAP | The In-App Purchases page is empty. `com.nishith.chronoframe.unlock` has not been created in the inspected app record. |
| TestFlight | Only version 1.2 and 1.1 are listed. Build 373 is expired. No uploaded V2 candidate or final V2 TestFlight evidence was found. |
| Existing local MAS output | `ui/build/Chronoframe-MAS.xcarchive` and `Chronoframe-MAS.pkg` are the June **1.2 (373)** artifacts. They are not the V2 release candidate. |
| Privacy and public links | App Store Connect declares **Data Not Collected** and uses the correct privacy URL. Home, privacy, support, and the public App Store listing returned HTTP 200. US app price is currently **$14.99**; no future price row was visible. |
| App Store preview | Fresh `verify.py` run passed: 1920×1080, 29.8 seconds, H.264 High, 30 fps, stereo AAC, approximately 41.7 MB; full-frame decode and audio-level checks passed. This verifies the file, not Apple approval or a listening review. |
| Social videos | Fresh `verify.py` run passed for the 4K, 1080p, and vertical exports, including full decode, format, frame count, audio levels, and fast-start checks. |
| Final screenshots | Located seven September exports in `.tmp/marketing-capture/app-store-final`, inspected the contact sheet and full-size Setup/History images, and verified every image is 2880×1800. Copied them unchanged into `marketing/release-2.0/screenshots` so the upload set no longer depends on `.tmp`. |
| Website launch | [PR #226](https://github.com/Nishith/Chronoframe/pull/226) is open and mergeable with successful checks. It advertises the free trial. Hold it until the download actually becomes free. |

Current evidence:

- [Latest main CI](https://github.com/Nishith/Chronoframe/actions/runs/37224530853)
- [Latest main CodeQL](https://github.com/Nishith/Chronoframe/actions/runs/37224530851)
- [Previous fully green CI](https://github.com/Nishith/Chronoframe/actions/runs/37221873091)
- [Exact main cutoff source](https://github.com/Nishith/Chronoframe/blob/9a96e83c6a1a4ce7bae7da156f81c349da8e8f92/ui/Sources/ChronoframeCore/Entitlement.swift#L376)
- [V2 release scope and manual pass conditions](remaining-work-plan.md)
- [Earlier local manual session](release-2.0-manual-session.md): historical integration evidence, not final signed-build evidence. F1 and F2 were subsequently fixed; do not carry its “unresolved” paragraph forward as current status.

## 1. Freeze the candidate and settle the transition date

- [x] Preserve source footage, scripts, provenance, exports, signed archive and package under `release-artifacts/2.0-500`. Screenshots and manifest are committed in PR #239. This is a second local copy; an off-device backup remains advisable.
- [ ] Use a clean checkout of current `main` containing every final fix. Wait for all required checks on the exact candidate SHA to finish successfully. Repeat checks after changing the cutoff.
- [x] Choose a conservative free-download date that allows App Review, release of paid V2, **at least seven days** of real paid-storefront use, and grandfathering verification.
- [x] Set the compiled `grandfatherCutover` to that transition, biased late. Account for the last storefront still accepting paid purchases, not just the US date: Apple applies scheduled pricing by storefront time zone. Record the UTC instant and its Los Angeles equivalent. If approval or rollout slips beyond the cutoff, postpone the price change and ship a corrected cutoff build first.
- [x] Set the real cutoff in the initial V2 candidate, as required. Build 500 contains October 26 at 07:00 UTC. The source comment and release documentation now agree.
- [x] Choose an explicit unused build number higher than the last uploaded build. The stamping script accepts `CHRONOFRAME_BUILD_NUMBER`; do not assume Xcode's `CURRENT_PROJECT_VERSION = 2` is the actual exported build number.

The seven-day paid hold is the project's migration policy, not an Apple review requirement. Developer ID notarization and the deferred 100,000-file/1-TB certification are outside this V2 launch scope.

## 2. Create the lifetime unlock and upload the signed build

In [App Store Connect](https://appstoreconnect.apple.com/apps/6771245052/distribution/iaps):

- [x] Create **Non-Consumable** → reference/display name **Chronoframe Unlock** → product ID **`com.nishith.chronoframe.unlock`**.
- [x] Set the initial US price to **$14.99**, select intended territories, and turn **Family Sharing ON**. Apple does not allow turning it off afterward.
- [ ] Use the localized description **“Unlimited organizing and duplicate cleanup.”** Add the required review screenshot of the unlock interface and any requested review details; complete the product metadata.
- [x] Check Business: agreements, banking, tax and Digital Services Act compliance are Active. No outstanding action was shown.

From the clean final checkout, build with the project's MAS script. Supply your chosen build number in place of the placeholder:

```sh
CHRONOFRAME_BUILD_NUMBER=<unused-build-number> ./ui/archive-mas.sh
```

- [x] Use the **non-local** script path. `--local` is unsigned structure validation, not a releasable artifact. The script enables `MAS_BUILD`; an ordinary Xcode archive without that condition would use the unrestricted distribution policy.
- [x] Confirm export/validation success, version **2.0**, chosen build number, arm64 + x86_64, minimum macOS **14.0**, sandbox, folder/bookmark and Photos entitlements, privacy manifest, and App Store distribution signing.
- [x] Preserve the archive and exported package before rerunning the script: it replaces its previous archive/export directories. Record commit SHA, version/build, cutoff, archive identity, and package SHA-256.
- [x] Upload through **Xcode → Window → Organizer → Distribute App → App Store Connect → Upload**, or use Transporter with the exported package. Wait for processing and address any validation/export-compliance prompts.

## 3. Run the final TestFlight session

- [x] Confirm processed V2 build in the existing internal testing group (2.0/500, Testing).
- [x] Install build 500 through TestFlight. Focused signed-build results are being recorded below; remaining scenarios still gate Go.
- [ ] Run the focused manual session in `remaining-work-plan.md`: fresh install/persistence; copy/repeat/revert; dedupe/Trash/restore; force quit and repeat recovery; upgrade from public 1.1; Photos import and watched batch; purchase/access; small-window/light/dark/keyboard/VoiceOver; and a real external drive if advertised.
- [ ] Include the realistic 1,000/approximately 10,000-file checks and record dataset count/bytes, cold/warm correctness, memory, cancellation, and drive format.
- [ ] Verify StoreKit product availability, existing paid access, restore, cancellation, offline behavior, exhausted allowance, free test batch, and ungated revert with the appropriate test environment. Before the future cutoff, a new sandbox/TestFlight account may correctly qualify for legacy access; that alone does **not** test the locked allowance or purchase prompt. Keep deterministic locked-state tests separate from signed TestFlight and real paid-purchase evidence.
- [ ] Record the owner's Go decision for the exact candidate, including evidence links and any accepted residual limitations. The signed 500 session is partial historical evidence; candidate 501 needs its own installation/recheck and final Go record.

## 4. Prepare the V2 store page and submit app + IAP together

Open the existing [draft version](https://appstoreconnect.apple.com/apps/6771245052/distribution/macos/version/inflight).

- [x] Change draft Version to **2.0**, save, and replace build **373** with **2.0 (500)**.
- [x] Replace the old description, promotional text, What's New, and review notes using [APP_STORE_METADATA.md](APP_STORE_METADATA.md). Use the **paid-window** variants for the initial release.
- [x] Ensure the description says **macOS 14.0 or later**. Replace “always recover” with conditional recovery: files must remain in Trash with their recorded contents. Avoid a blanket offline claim for initial purchase/restore or downloading iCloud-only originals.
- [x] In What's New, include the actual V2 customer benefits: Photos import, watched-source review, optional similar-video review, safety/recovery and interface improvements, plus existing-purchase protection. The staged notes currently focus mostly on pricing migration.
- [x] Paste the full review notes, including **500 organized files + 100 duplicates trashed**, cumulative per Apple Account per Mac, permanent allowance, free scanning/review/history, one non-consumable unlock, grandfathered paid access, and revert refunds. Mention that the app remains paid during the initial transition window.
- [x] Keep no app sign-in required; confirm review contact details, Photo & Video category, URLs, privacy declaration, and updated age-rating questionnaire. Do not advertise the disabled Library Guardian feature.
- [x] Replace the older screenshot set with the numbered files in `marketing/release-2.0/screenshots`. Upload the actual screenshots, not `contact-sheet.png`. All seven files have accepted dimensions.
- [x] Correct **06-run-history-app-store.png** to **“Receipts for safer undo.”** Regenerated and visually checked. 07 shows the Photos permission entry point rather than a populated library.
- [x] Upload `marketing/app-preview/exports/Chronoframe-App-Store-Preview.mp4` into the Mac **App Preview** slot. Selected its poster near **11.5 seconds**; Apple’s editor reopens at the persisted whole-second **11 seconds**. Do not use the 60-second social film as the App Store preview.
- [x] Select **Manually release this version** to coordinate publication. Keep existing ratings unless you specifically decide to reset them.
- [ ] Include the first lifetime-unlock IAP with V2 in the same submission. Select **Add for Review**, inspect the draft submission, then **Submit for Review**. Add for Review alone does not submit it.

Apple references checked for this audit: [Mac screenshots](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications), [preview specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/app-preview-specifications), [IAP submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/), and [app submission](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/).

## 5. Release paid V2, then transition to free

- [ ] Once app and IAP are approved, manually release V2 while the app still costs **$14.99**.
- [ ] Verify the public listing shows V2, correct screenshots/preview and compatibility; install/update from the public store and check paid access and core workflows.
- [ ] Hold **at least seven days after paid V2 goes live**. Verify grandfathering using actual paid purchasers' production AppTransaction data, including V2 purchasers. Sandbox and TestFlight purchases cannot substitute for that evidence.
- [ ] Only proceed when the released binary contains the correct cutoff, grandfathering has been verified, and the IAP is approved and available. If any condition fails, keep the app paid and postpone the transition.
- [ ] Execute the free-download schedule for all intended territories. Apple applies pricing changes by storefront time zone, and propagation may take time; inspect actual storefronts rather than assuming a single instantaneous worldwide switch. See [Apple's price scheduling instructions](https://developer.apple.com/help/app-store-connect/manage-app-pricing/schedule-price-changes-for-apps/).
- [ ] Verify a real account whose first acquisition is **after the cutoff** receives the allowance, while prior paid customers retain unrestricted use. Test purchase and restore against the production product.
- [ ] When the advertised storefront is free, merge **PR #226**, wait for Pages deployment, and verify the live video, trial terms, privacy/support links and App Store CTA. Planned publication date is now October 26 and sitemap last-modified date October 4; recheck dates and conflicts before merging. Every `site/**` push to `main` deploys immediately.
- [ ] Update README and App Store promotional text to the free-to-try variants. Keep the pricing-neutral description or coordinate a reviewed follow-up version for description changes; do not assume the released description is freely editable.

## 6. Send out the marketing assets

| Destination | File |
|---|---|
| Mac App Store preview | `marketing/app-preview/exports/Chronoframe-App-Store-Preview.mp4` |
| App Store screenshots | `marketing/release-2.0/screenshots/` |
| YouTube horizontal | `marketing/social-video/exports/Chronoframe-YouTube-4K.mp4` |
| YouTube thumbnail | `marketing/social-video/exports/Chronoframe-YouTube-Thumbnail.jpg` |
| Shorts / Instagram Reels / Facebook Reels / other vertical posts | `marketing/social-video/exports/Chronoframe-Social-Vertical-1080x1920.mp4` |
| Vertical cover where supported | `marketing/social-video/exports/Chronoframe-Vertical-Poster.png` |
| YouTube timed captions | `marketing/social-video/exports/Chronoframe-Youtube.srt` |
| Draft video titles/descriptions | `marketing/social-video/publishing-copy.md` |

- [ ] Play the complete App Store and social films once with sound and once muted. Technical checks passed; this audit did not audition the music. Confirm caption readability, covers, and the final call to action on a phone.
- [ ] Upload the 4K video to YouTube as **unlisted** first; add thumbnail, title, description, caption track and photo/music credit. Wait for HD/4K processing and inspect playback before publishing.
- [ ] Prepare the vertical posts as drafts with the provided captions and cover. Use the pricing-neutral publishing copy during the paid window. For a free-trial launch, wait until the free storefront and website are verified before publishing.
- [x] Prepare replacement Reddit/Show HN launch copy and mark older drafts obsolete. Planned offer: **free download; 500 organized files and 100 trashed duplicates; $14.99 US one-time unlock; existing paid customers keep access**. Remove the older paid-download/no-trial framing. Preserve the limits on revert and review each community's current posting rules.
- [ ] Publish YouTube and the initial social announcement after the website/store checks pass. Spread community posts out and disclose that you are the developer. Include both [chronoframe.app](https://chronoframe.app/) and the [App Store listing](https://apps.apple.com/us/app/chronoframe/id6771245052) where supported.
- [ ] For the first week, check support messages, App Store reviews, TestFlight/crash feedback, purchase/restore failures, and copying/Trash/recovery reports daily. Respond to questions and pause further promotion if a core safety or access failure emerges.

The initial audit made no external changes. The execution update above records subsequent authorized preparation and build upload. No review submission, app price transition, website publication or public marketing post has been performed.
