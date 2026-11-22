# App Store Connect Metadata

Copy-paste-ready source for Chronoframe's current Mac App Store listing. Character limits are noted so nothing gets truncated in App Store Connect. Re-verify version, pricing, screenshots, and hosted URLs for every submission.

**Status (2026-11-21).** These are the direct-free values submitted with 2.0 (511) on 2026-10-21; version 2.0 has been public since 2026-10-22 and the public US listing shows Free with Unlock $14.99. Release state and open tasks: [V2_LAUNCH_CHECKLIST.md](V2_LAUNCH_CHECKLIST.md). The local source for these values is `marketing/release-2.0/metadata/fields.json` and its adjacent text files.

## Identity

| Field | Value |
| :--- | :--- |
| App name (30 char max) | `Chronoframe` |
| Subtitle (30 char max) | `Safe photo organizer` |
| Bundle ID | `com.nishith.chronoframe` |
| Primary category | Photo & Video |
| Secondary category | Utilities |
| Version | `2.0` |
| Copyright | `2026 Nishith Nand` |
| Age rating | 4+ (no objectionable content) |

Subtitle alternative (28 char): `Safe photo & video organizer`

## URLs

| Field | Value |
| :--- | :--- |
| Marketing URL | `https://chronoframe.app/` |
| Support URL | `https://chronoframe.app/support.html` |
| Privacy Policy URL | `https://chronoframe.app/privacy.html` |

## Direct free V2 submission — October 16, 2026

The owner confirmed there are no existing users (2026-10-16), so the earlier paid-window and grandfathering copy is superseded. On 2026-10-22 the app's retained $14.99 download price was corrected to $0.00 in all 175 regions; the $14.99 US Unlock and Family Sharing were unchanged ([ledger](app-review-replacement-511-2026-10-21.md)). Public propagation was verified for the US storefront only (2026-11-21).

## Promotional Text (170 char max)

> Free to try: organize 500 files and clear 100 duplicates before you decide. One $14.99 unlock, no subscription, ever. On-device, originals untouched, nothing uploaded.

## Description (4000 char max)

> Chronoframe brings scattered photos and videos into a clean, dated library, then helps you review duplicates and reclaim space. Every workflow starts with a preview and your approval.
>
> ORGANIZE
> Choose a source folder and a destination, select a date-based layout, and preview the plan. Chronoframe resolves dates from photo and video metadata, filenames, and file dates, with uncertain dates available for review. Your source files are only read: never moved, renamed, edited, or deleted.
>
> IMPORT FROM APPLE PHOTOS
> Import copies of selected original photos and videos into your organized destination. Chronoframe reads and exports from Photos; it never changes or deletes anything in your Photos library.
>
> WATCHED SOURCES
> Register source folders and see an estimate of new items. Review each import before it runs. You stay in control of what is copied and where it goes.
>
> DEDUPLICATE
> Find exact photo and video copies by content, plus similar photos, bursts, RAW+JPEG pairs, and Live Photo pairs. Optional similar-video matching helps you review re-encodes and resizes. Compare candidates, choose keepers, and approve which files move to macOS Trash. Chronoframe does not permanently delete them.
>
> SAFE BY DESIGN
> • Preview before copying or trashing.
> • Filename collisions receive distinct names; existing destination files are not overwritten.
> • Transfers verify written copies by default.
> • Pair and sidecar handling protects kept companions.
> • Run History records receipts and supports content-verified revert. Trashed items can be restored while they remain in Trash with their recorded contents.
> • Interrupted work is reconciled on relaunch, with clear guidance when a drive or manual recovery is needed.
>
> PRIVATE
> Your media is processed on your Mac and is never uploaded by Chronoframe. There is no Chronoframe account, advertising, analytics, or tracking. Importing iCloud-only originals may require macOS to download them from your own iCloud account. Purchase and restore verification use Apple's App Store services.
>
> FREE TO TRY
> Download free. Organize 500 files and move 100 duplicates to Trash, cumulatively per Apple Account on each Mac. Scanning, previews, duplicate review, and history are free and unlimited. One $14.99 US lifetime unlock removes the limits, with Family Sharing and no subscription. Revert is available without purchasing and returns the corresponding allowance. Restore Purchases is available in Settings → License. Reorganizing an existing destination requires the unlock.
>
> REQUIREMENTS
> macOS 14.0 or later. Apple Silicon and Intel. Local organizing, duplicate review, and history work offline.

## Keywords (100 char max, comma-separated, no spaces after commas)

> duplicate,dedupe,photos,organizer,EXIF,cleanup,media,folder,backup,video,sort,library,metadata

## What's New (release notes for version 2.0)

> Chronoframe 2.0 brings new ways to build and care for your photo library:
>
> • Import selected original photos and videos from Apple Photos without changing the Photos library.
> • Register watched source folders, see an estimate of new items, and review each import before copying.
> • Review similar videos with optional perceptual matching, alongside exact photo and video duplicates.
> • Preview your library with contact sheets and timelines, compare duplicates, and choose what moves to Trash.
> • Improved copy compatibility on external drives, visible duplicate names in Trash, interruption recovery, and clearer verification and history.
> • Refined layouts and accessibility throughout the organizing and duplicate-review workflows.
>
> Dates near midnight now use the capture date’s recorded time zone. For a previously organized library, use Health → Reorganize to correct affected destination folders; originals are unchanged.
>
> Now free to download: organize 500 files and move 100 duplicates to Trash before purchasing. These allowances are cumulative per Apple Account on each Mac. One $14.99 US lifetime unlock removes the limits, with Family Sharing. Scanning, preview, review, and history remain free; revert remains available without purchasing and returns the corresponding allowance.
>
> No subscription. Your organizing source files and Photos library remain untouched.

## Review Notes

Submitted 2026-10-21 with **2.0 (511) + Chronoframe Unlock** (submission `42e45604-bc72-4236-a1a1-8bca697a7884`, manual release). The disclosed 3:21 physical-Mac video is attached to App Review Information; direct app/IAP License navigation notes and the real signed purchase screenshot are saved ([ledger](app-review-replacement-511-2026-10-21.md)).

The purchase path below leads the saved review notes; it requires a build with the direct License entry (511 has it):

> FIND THE IN-APP PURCHASE: Launch Chronoframe, choose Chronoframe → Settings… (Command-comma), select License, then click Unlock Chronoframe…. The purchase sheet shows "Chronoframe Unlock" and the localized App Store price. Click that priced button to begin the Apple sandbox purchase. You do not need to select folders, organize 500 files, delete duplicates or use up any free allowance to reach this purchase. Restore Purchases is available in Settings → License and on the purchase sheet while locked. A successful purchase unlocks the app without starting any file operation. There is no Chronoframe sign-in or demo account. If the app already says Unlocked, that Apple Account already has access and another purchase is not offered.

> Chronoframe is a sandboxed macOS photo/video organizer. It only accesses folders the reviewer selects through the standard macOS folder picker. Organize copies files into a chosen destination and does not modify originals. The optional Photos import reads the Apple Photos library only: it exports copies of selected originals with PHAssetResourceManager into the chosen destination and never calls any mutating PhotoKit API, so it cannot modify, move, favorite, or delete anything in the library (macOS has no read-only Photos permission level, so the app requests read/write access but never writes). Deduplicate moves reviewer-approved files to the macOS Trash only; it does not hard delete. Before Trash, approved mutation units may be temporarily renamed within the same selected folder for content verification and crash recovery. The app runs entirely on-device, does not upload photos, and includes no analytics, telemetry, advertising, or crash-reporting services. Local cache, lock, journal, log, and receipt files are created in the selected destination to support preview, interruption recovery, history, and revert. No sign-in or demo account is required.
>
> FREE ALLOWANCE AND IN-APP PURCHASE. Chronoframe includes one non-consumable in-app purchase, "Chronoframe Unlock" (com.nishith.chronoframe.unlock): a one-time purchase, no subscription, with Family Sharing enabled. Without it, the app allows organizing 500 files and moving 100 duplicates to the Trash. Those counts are cumulative and permanent — not per session, per day, or per folder — and they are scoped to each Apple Account on each Mac: signing in as a different Apple Account gives that account its own allowance rather than an already-spent one, and signing back in returns to the original count. The counts are stored outside the app bundle, so deleting and reinstalling the app does not reset them. Previewing, planning, dry-run CSV export, duplicate scanning and review, Library Health, and Run History are free and unlimited, so the entire workflow can be exercised without purchasing anything. When a run would exceed the remaining allowance, the app refuses it before copying or trashing anything, states that the originals were left untouched, and offers either the purchase or a smaller batch that fits within what remains. Reverting a completed run is never restricted by purchase state, and a revert returns the allowance that run consumed. Reorganizing an existing destination requires the unlock. Restore Purchases is available in Settings → License.
>
> LAUNCH: Version 2.0 launches directly as a free download with the $14.99 US lifetime unlock. There are no existing customers to migrate and no paid rollout or acquisition-date legacy unlock. New customers receive the allowance regardless of the app transaction's original purchase date. Submit the app and first non-consumable together.

## App Privacy (questionnaire answers)

These mirror `docs/PRIVACY_POLICY.md` and `ui/Resources/PrivacyInfo.xcprivacy`.

- Data collection: **No, we do not collect data from this app.**
- Tracking: **No.**
- Third-party SDKs (analytics/ads/crash): **None.**

If App Store Connect still asks per-category questions, answer "Not Collected" for every data type — Chronoframe does not transmit any data off-device.

## In-App Purchase Metadata

One non-consumable, and the only one. Reference name is internal; display name and description are what a customer reads in the purchase sheet.

| Field | Value |
| :--- | :--- |
| Reference name (internal) | `Chronoframe Unlock` |
| Product ID | `com.nishith.chronoframe.unlock` |
| Type | Non-consumable |
| Price | USD 14.99 |
| Family Sharing | **ON** |
| Display name | `Chronoframe Unlock` (18 char) |
| Description | `Unlimited organizing and duplicate cleanup.` (43 char) |
| Availability | All territories (confirm before submitting) |

**Family Sharing cannot be turned off once the product is created.** Set it at creation.

App Store Connect caps the display name and description tightly — around 30 and 45 characters respectively, though Apple has moved these before. The values above are short enough for those caps; if the field disagrees, believe the field and shorten, don't assume the doc.

The description in `ui/Chronoframe.storekit` is longer than what App Store Connect will accept, deliberately: nothing truncates it locally and the longer text is easier to recognize while testing. It is not the shipping copy — the table above is.

Screenshot for review: the purchase sheet reached directly through Settings → License → Unlock Chronoframe…. It shows the StoreKit-supplied price, purchase button and Restore Purchases. The same purchase sheet is also offered when a run exceeds the remaining allowance or Reorganize requires an unlock; an over-allowance organize run may additionally offer a smaller free batch. A screenshot of a fixture is interface evidence only; the real sandbox recording is attached separately in App Review Information.

## Pricing

- App download: **Free**.
- Lifetime non-consumable unlock: **USD 14.99**, with Family Sharing; no subscription.
- Availability: all 175 territories (Unlock availability and $0.00 app prices confirmed in App Store Connect).
- No paid V2 holding period or date-based automatic unlock. The first IAP was submitted with V2; free pricing was applied 2026-10-22 (see above).

## Hosting the URLs

The three URLs above come from the static site in `site/` (`index.html`, `support.html`, `privacy.html`). It is published to GitHub Pages by `.github/workflows/pages.yml` on every push to `main`, served at the custom domain **chronoframe.app** (`site/CNAME`).

To make the custom domain resolve, add these records at the registrar for `chronoframe.app`:

- **A** (apex `@`) → `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
- **AAAA** (apex `@`) → `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153`

Then set the Pages custom domain (`gh api -X PUT repos/Nishith/Chronoframe/pages -f cname=chronoframe.app`) and enable "Enforce HTTPS" once DNS resolves.

The Mac App Store button `href` in `site/index.html` already points at the live product URL (`https://apps.apple.com/us/app/chronoframe/id6771245052`).

**Every push to `main` that touches `site/**` publishes immediately.** The owner approved early website publication on October 18, 2026, accepting the temporary old/unavailable App Store offer; website PRs #226, #248 and #249 are merged and the site carries direct-free wording, the App Store link and development-capture labels (`site/assets/product-proof.json`). Verifying the live Pages deployment and the public V2 offer/capture labels is still open (see V2_LAUNCH_CHECKLIST.md section 5).
