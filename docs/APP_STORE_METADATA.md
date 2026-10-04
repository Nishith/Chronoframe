# App Store Connect Metadata

Copy-paste-ready source for Chronoframe's current Mac App Store listing. Character limits are noted so nothing gets truncated in App Store Connect. Re-verify version, pricing, screenshots, and hosted URLs for every submission.

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

## Promotional Text (170 char max)

Editable at any time without a review, which is what makes it the right place to stage the pricing message.

### Version 2.0 — the one to publish

Unchanged, and true of a $14.99 up-front app.

> Organize years of scattered photos into a clean date-based library without changing your originals — then remove duplicates safely to the Trash. On-device. No uploads.

(167 characters.)

### At the price cutover

Publish only once the App Store price is actually free.

> Free to try: organize 500 files and clear 100 duplicates before you decide. One $14.99 unlock, no subscription, ever. On-device, originals untouched, nothing uploaded.

(167 characters.)

## Description (4000 char max)

Two variants, because version 2.0 ships while the app is still USD 14.99 — see [Pricing](#pricing). **Submit the first one.** The free-tier variant describes a free download and is false for as long as checkout charges for the app.

### Version 2.0 — the one to submit

Unchanged from version 1.x. It makes no pricing claim, so it stays true on both sides of the cutover. During the paid window the free tier is dormant anyway: everyone who acquires the app before `grandfatherCutover` is grandfathered, so no paying customer ever meets an allowance, and copy explaining one would only confuse them.

> Chronoframe is a safe photo and video organizer for people with years of media spread across phones, camera cards, old laptops, external drives, and backup folders. It builds a cleaner library in two practical ways — and it always shows you a plan before it changes anything.
>
> ORGANIZE
> Point Chronoframe at a messy folder and a destination, pick a date-based layout, and preview the plan. Chronoframe resolves each file's date from photo metadata, filename patterns, and the filesystem, and lets you review or correct uncertain dates before a single file is copied. Your source folder is read-only — nothing is moved, renamed, edited, or deleted.
>
> DEDUPLICATE
> Find exact copies by content, not filename, plus near-duplicates, burst groups, RAW+JPEG pairs, Live Photo pairs, and optional review-only visual video matches. You decide what to keep. Selected files move to the macOS Trash, never a permanent delete.
>
> SAFE BY DESIGN
> • Originals stay untouched — Chronoframe only reads your source folder.
> • You approve the plan — Organize previews what will copy; Deduplicate previews what moves to Trash.
> • No overwrites — filename collisions get a distinct name instead of replacing a file.
> • Copies are verified — transfers are written atomically and re-hashed by default.
> • Receipts and revert — History records each run, and supported runs can be reverted when files still match the receipt.
> • Interruption-aware — durable recovery state reconciles recorded work on relaunch and tells you when a drive or manual action is needed.
> • One operation at a time — app, command-line, and system actions cannot race on the same destination.
>
> PRIVATE
> Chronoframe works only on folders you choose, processes everything on-device, and never uploads your library. There is no account, no analytics, no advertising, and no tracking. Cache, log, and receipt files are written inside the destination folder you select, so you can inspect or remove them anytime.
>
> REQUIREMENTS
> macOS 14.0 or later. Apple Silicon and Intel. Works fully offline.

### At the price cutover

Publish only once the App Store price is actually free. It is the variant above with one block inserted after the opening paragraph:

> FREE TO TRY
> Use Chronoframe on your own library before paying anything. Previewing, planning, dry-run CSV export, duplicate scanning and review, Library Health, and Run History are free and unlimited — you can see everything Chronoframe would do without buying. The free allowance covers organizing 500 files and moving 100 duplicates to the Trash, and it is yours per Apple Account on each Mac. One purchase of $14.99 removes the allowance for good, on every Mac signed in to your Apple Account, and it is shared with your family. There is no subscription and no account.

**This swap probably needs an app version, and that changes the cutover plan.** Promotional text is editable at any time, which is why the free-to-try message is staged there. The description, keywords, and screenshots are attached to a version in App Store Connect and, as far as we know, cannot be changed without submitting one. Confirm that in App Store Connect before scheduling the cutover; do not take this paragraph's word for it. If it holds, pick one deliberately:

- Submit a **2.0.1** whose only purpose is the copy swap, timed with the price transition. The description is the listing's main sales surface, and leaving it silent about a free trial wastes the change.
- Or leave the description pricing-free permanently and let promotional text carry the free-to-try message. No extra submission, weaker listing.

## Keywords (100 char max, comma-separated, no spaces after commas)

> `duplicate,dedupe,photos,organizer,EXIF,cleanup,media,folder,backup,video,sort,library,metadata`

(94 characters. Apple counts spaces, so commas have no trailing space. Don't repeat the app name or subtitle words here — they're already indexed.)

## What's New (release notes for version 2.0)

Version 2.0 initially ships while the app still costs $14.99 up front. The notes describe its features and reassure paid customers about the later free-download transition. Do not advertise the free allowance until the download actually becomes free. Copy-ready text:

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
> Chronoframe is preparing to become a free download with a single lifetime unlock. If you already bought the paid app, your purchase covers unrestricted use: you will not need to buy the unlock. Settings → License shows your status, with Restore Purchases available when verification is needed.
>
> No subscription. Your organizing source files and Photos library remain untouched.

## What's New (release notes for version 1.3)

> • Import from Apple Photos: browse your albums, pick photos and videos, and import copies straight into your organized library. Chronoframe only ever reads your Photos library — it never changes, moves, or deletes anything there. Live Photos keep their still and movie together, and iCloud-only originals are downloaded on demand.
> • Every Photos import still goes through the same preview → confirm → verified-copy flow as the rest of Chronoframe, so you see exactly what will happen before anything is written.

## What's New (release notes for version 1.2)

> • Photos with a timezone-tagged capture date near midnight now file under your local calendar day instead of UTC. If you organized a library before this update, re-run Organize or use Health → Reorganize to move any affected files into their corrected date folder.
> • Chronoframe now warns you once if a chosen destination is on a network volume, since two Macs writing to the same network share at once isn't supported.
> • Deduplicate's Revert now re-verifies a Trash item's identity before restoring it, so a changed or replaced item in Trash is left alone instead of being restored.

## What's New (release notes for version 1.1)

> First public release of Chronoframe on the Mac App Store.
>
> • Organize scattered photos and videos into a clean date-based library without changing your originals.
> • Deduplicate exact copies, near-duplicates, bursts, RAW+JPEG pairs, and Live Photos — safely to the Trash.
> • Optionally review visually similar video transcodes and re-exports; these matches are never auto-accepted.
> • Preview every plan before anything changes, with interruption recovery, run history, and content-verified revert.

## App Review Notes

> Chronoframe is a sandboxed macOS photo/video organizer. It only accesses folders the reviewer selects through the standard macOS folder picker. Organize copies files into a chosen destination and does not modify originals. The optional Photos import reads the Apple Photos library only: it exports copies of selected originals with PHAssetResourceManager into the chosen destination and never calls any mutating PhotoKit API, so it cannot modify, move, favorite, or delete anything in the library (macOS has no read-only Photos permission level, so the app requests read/write access but never writes). Deduplicate moves reviewer-approved files to the macOS Trash only; it does not hard delete. Before Trash, approved mutation units may be temporarily renamed within the same selected folder for content verification and crash recovery. The app runs entirely on-device, does not upload photos, and includes no analytics, telemetry, advertising, or crash-reporting services. Local cache, lock, journal, log, and receipt files are created in the selected destination to support preview, interruption recovery, history, and revert. No sign-in or demo account is required.
>
> FREE ALLOWANCE AND IN-APP PURCHASE. Chronoframe includes one non-consumable in-app purchase, "Chronoframe Unlock" (com.nishith.chronoframe.unlock): a one-time purchase, no subscription, with Family Sharing enabled. Without it, the app allows organizing 500 files and moving 100 duplicates to the Trash. Those counts are cumulative and permanent — not per session, per day, or per folder — and they are scoped to each Apple Account on each Mac: signing in as a different Apple Account gives that account its own allowance rather than an already-spent one, and signing back in returns to the original count. The counts are stored outside the app bundle, so deleting and reinstalling the app does not reset them. Previewing, planning, dry-run CSV export, duplicate scanning and review, Library Health, and Run History are free and unlimited, so the entire workflow can be exercised without purchasing anything. When a run would exceed the remaining allowance, the app refuses it before copying or trashing anything, states that the originals were left untouched, and offers either the purchase or a smaller batch that fits within what remains. Reverting a completed run is never restricted by purchase state, and a revert returns the allowance that run consumed. Customers who bought Chronoframe while it was a paid app keep unrestricted access without paying again; that is determined from the signed original purchase date in the app's own App Store receipt, not from any server we operate.

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

Screenshot for review: the unlock sheet reached by starting a run larger than the remaining allowance. It shows the price, the purchase button, Restore Purchases, and the smaller free batch offer in one frame.

## Pricing

- App price at version 2.0: **USD 14.99**, unchanged.
- App price after the cutover: **Free**.
- In-app purchase: **USD 14.99** at launch; move to **USD 19.99** once conversion and reviews accumulate.
- Availability: all territories (confirm before submitting).

**The app does not become free at submission, and this is the ordering that matters.** Version 2.0 ships while the app is still paid, because Apple requires the first non-consumable to be submitted *with* a new app version. The price then drops to free as a separate, scheduled change at least 7 days later, once grandfathering has been verified against real purchase data. Dropping the price early asks paying customers to buy twice; the full sequence and its reasoning are in `docs/APP_STORE_RELEASE.md`.

That gap is why the listing copy above is staged rather than switched: the promotional text has a paid-era version to use until the drop, and the version 2.0 release notes describe the in-app purchase without calling the app free.

## Hosting the URLs

The three URLs above come from the static site in `site/` (`index.html`, `support.html`, `privacy.html`). It is published to GitHub Pages by `.github/workflows/pages.yml` on every push to `main`, served at the custom domain **chronoframe.app** (`site/CNAME`).

To make the custom domain resolve, add these records at the registrar for `chronoframe.app`:

- **A** (apex `@`) → `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`
- **AAAA** (apex `@`) → `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153`

Then set the Pages custom domain (`gh api -X PUT repos/Nishith/Chronoframe/pages -f cname=chronoframe.app`) and enable "Enforce HTTPS" once DNS resolves.

After the App Store listing is live, replace the Mac App Store button `href` in `site/index.html` with the live App Store product URL.

**Every push to `main` that touches `site/**` publishes immediately.** There is no staging step, so the site's pricing copy is live the moment it merges. `site/index.html` and `site/faq.html` currently say "$14.99 introductory price · One-time purchase", which is true today and stays true through version 2.0. Changing them to free-to-try before the App Store price actually drops would advertise a free download while customers are still charged up front. That copy change is therefore part of the cutover, not part of this release — see the cutover step in `docs/APP_STORE_RELEASE.md`.

## October 2026 prepared submission

The V2 draft was updated on October 4. Copy-ready values are in `marketing/release-2.0/metadata/fields.json` and the adjacent text files. They correct the macOS requirement to 14.0, describe Photos import and watched sources, include the recorded-time-zone folder migration note for users upgrading from public 1.1, and qualify revert against retained, unchanged Trash contents. These copy-ready values are the complete V2 listing; the version-specific notes above preserve earlier drafts. The app remains paid during the first V2 rollout. The planned free date is October 26, subject to the release gates.
