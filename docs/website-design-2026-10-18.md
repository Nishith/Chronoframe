# Website design update — October 18, 2026

The owner asked to prioritize the website while the submitted app is in review.
This increment continues held PR #226 from remote head `276bc8569384736247153511d65e41cd8ee8d9ec`.
It changes website assets, content, validation and this record only; it does not
change the submitted app. The older divergent local `codex/website-demo` branch
and the primary checkout's uncommitted app/marketing work are preserved.

**Status update:** the owner merged PR #226 at 23:54:32 UTC during this QA pass.
Pages deployed `54df5f9` successfully at 23:54:53 UTC. The final QA fixes continue
as a separate unmerged follow-up based on that main commit. This records the
deployment; it does not certify the still-unverified public app/offer.

## Delivered for review

- A shorter introduction keeps “A lifetime of photos, finally in order.” Original
  generated photo-print artwork adds a photographic identity beside the copy.
  Warm graphite, amber accents, indigo actions and system typography retain the
  Meridian identity. This direction is implemented for owner review, not recorded
  as an owner-approved final visual selection.
- One real Organize preview now has the main proof position. Its staged 4,000-file
  scope is explicit and distinct from the 500-file allowance. Small screens can
  pan the screenshot, open the original, or expand a readable text alternative.
- Four steps explain choosing folders, previewing, approving copies and inspecting
  History. Deduplicate has a separate compare → review → Trash → conditional
  restore story, including the Trash/storage tradeoff.
- The existing captioned, user-initiated recorded walkthrough is the selected
  delivery under Phase 5's explicit fallback. The interactive Organize simulator
  is cut from this delivery: a new browser state machine, test dependencies and
  CI lane would add maintenance without improving the explanation enough to
  justify it. The optional interactive dedupe extension stays deferred. No
  JavaScript dependency, analytics or hosting change is added.
- The offer is aligned with the owner's October 16 direct-free policy: cumulative
  500/100 allowance per Apple Account per Mac; unlimited scanning, preview, review
  and History; $14.99 US one-time lifetime unlock with Family Sharing; ungated
  revert with refunds for successfully undone work. Old paid-app ownership grants
  and paid-transition instructions are removed from the affected site guidance.
- `site/assets/product-proof.json` distinguishes real development captures from
  decorative artwork and records unknown app versions/builds explicitly. The
  film no longer claims a projected public upload date. Original screenshot,
  film, photo and music provenance is retained.

## Validation

- `python3 script/check_site.py`: passes for all nine HTML pages, links/fragments,
  images, JSON-LD, sitemap, video policy/size/fast-start/captions, offer terms and
  proof provenance. The new checks reject retired access claims and a projected
  upload date for unpublished footage.
- `node --check site/site.js`, Python syntax compilation and `git diff --check`:
  pass. No app build or Swift tests are needed for this website-only increment.
- Browser review at effective CSS viewports **1280×1000**, **390×843** and
  **320×800**. The in-app browser's existing 110% zoom was retained; viewport
  overrides were compensated against observed `innerWidth`, then reset.
- No document-wide horizontal overflow at either narrow width. At 320 pixels the
  observed gap between the brand and download action is 12 pixels after fixing
  their overlap; the primary action remains inside the content area.
- The screenshot region receives keyboard focus and pans with ArrowRight. The
  native sample-details disclosure expands; its counts, destination and sample
  limitation are readable. The skip link receives focus with a visible outline.
- The recorded demo starts on request (`paused=false`, `readyState=4`), retains
  native controls and one caption track, seeks to the 39.8-second restore chapter,
  and pauses with Space. Transcript and FAQ disclosures work. The offer FAQ
  exposes the scope, Family Sharing and revert-refund terms. The primary App Store
  link retains app ID `6771245052`.
- The preview server returns HTTP 206 and the correct `Content-Range` for a
  1,024-byte media request. No broken in-view images were found.
- Computed palette checks: white text on the new indigo action is **5.42:1**,
  and **6.56:1** on hover. The new sections add no motion. Existing reduced-motion
  and forced-color rules remain. This is focused visual/keyboard verification,
  not a full screen-reader or WCAG certification.

Local review captures (not public product-proof assets):

- `.tmp/website-review-2026-10-18/home-desktop-1280.png`
- `.tmp/website-review-2026-10-18/home-mobile-390.png`
- `.tmp/website-review-2026-10-18/home-mobile-320.png`
- `.tmp/website-review-2026-10-18/mobile-preview-details.png`

Generated artwork and the exact final prompt are in
`site/assets/artwork/README.md`; the optimized delivery image is
`site/assets/artwork/photos-to-order.jpg` (1536×1024, under 350 KB).

## Public app proof still unverified

Submission for App Review is not public availability. The owner merged PR #226
while this follow-through was underway. The follow-up remains unmerged until the
matching public V2 build, free storefront, unlock price and Family Sharing are
verified. Merging `site/**` to main publishes through Pages.

The reused September development screenshots/film are not certified captures of
the submitted build. Their app build/source commit and public-version mapping
remain unknown in the proof manifest. Verify their visible behavior against the
public release or replace them before merging. The uncommitted app design changes
from the owner's primary checkout are not used as website screenshots.

The actual film publication date is now **October 18, 2026** in the manifest and
VideoObject: the successful Pages run is recorded and a live byte-range request
returned HTTP 206 for the expected 6,874,782-byte film. The asset did not exist in
main before PR #226. App-release proof remains unverified despite film publication.
The privacy policy was reviewed against the prepared site: no data collection,
network use or storage behavior changes in this increment, so its September 29
effective date is retained. Do not substitute a projected launch date.

## Follow-through — remaining website preparation

On October 18 the owner asked to do the remaining website work. The photographic
direction is retained for this implementation; additional artwork variants are
optional exploration, not unfinished requirements. No separate owner visual
sign-off or outside participant study is claimed.

**Public release check.** Apple's US lookup endpoint
`https://itunes.apple.com/lookup?id=6771245052&country=us` returned version **1.1**,
download price **$14.99 USD**, minimum OS **13.0**. The installed app's bundle reports
**2.0 (507)**, matching the submitted candidate's release record, whose source commit
is `f54191843a7f95f0ad211c79714402e36ea7f4ea`. These are different availability
states. The manifest records both without mapping the September captures to 507.
All five approved original screenshot PNGs matched their recorded source SHA-256;
the film matched its production export hash. Every delivered proof asset now has
a checksum checked by `check_site.py`.

**Accessibility and responsive checks.** Temporary local axe-core **4.10.3**,
downloaded from the npm registry, ran WCAG 2 A/AA, 2.1 A/AA, 2.2 AA and best-practice
rules across all seven content pages. All disclosures were expanded for the scan.
Frame widths **320, 390, 768 and 1280** produced **zero automated violations** and
**zero document horizontal overflow**. Frames with a scrollbar had 14 pixels less
content width. A separate stress pass doubled every computed text size at a
320-pixel frame width; all seven pages again had zero violations/overflow. This
is a text enlargement stress test, not a claim that browser zoom was emulated.

The checks found and fixed color-only inline links, an unsupported label on a
generic proof container, minimum-width grid overflow, unbreakable support/email
text, and a mobile player button that overlapped the film caption with enlarged
text. Links in prose/captions are underlined, the proof has a named group role,
grid tracks can shrink, long text wraps, and the mobile Play button occupies its
own row below the video.

Remaining axe contrast review items were inspected separately: decorative,
`aria-hidden` checkmarks duplicate written safety statements; gradient/pseudo
surfaces have bounded colors. Secondary/primary text over the brightest hero
gradient is **8.19:1 / 12.67:1**; the lowest muted text over the closing gradient is
**4.75:1**. Reduced-motion rules were applied in the local harness and produced
`scroll-behavior: auto` on all seven pages; there are no animated counters,
transitions or autoplay. Forced-color rules retain explicit control borders and
no meaning depends on color. OS-level forced-color and spoken VoiceOver sessions
were not performed; this is documented browser/AX verification, not certification.

**Keyboard and failure states.** Skip navigation moves focus to `main` with a
visible outline. The screenshot scroll region, native details, chapter controls
and video are keyboard reachable. A local missing-media fixture produced the
announced load error and an available transcript/direct link. A copy with the
enhancement script omitted retained native video controls, one caption track,
keyboard-openable transcript/FAQ, download links, and hidden chapter/overlay
controls. Pressing Space requested native playback. The transcript preserves
the staged-library caveat, media credit and conditional restoration explanation.

Raw local audit reports and captures are under
`.tmp/website-review-2026-10-18/` (not deployed). The temporary axe harness and
download are removed from `site/`; no third-party runtime or CI dependency ships.
The checked-in `docs/website-qa-2026-10-18.json` preserves the per-page results,
measured content widths and limitations.

Run `python3 script/check_site.py` for draft validation. Run
`python3 script/check_site.py --release` immediately before merging; it deliberately
fails while the manifest is held. The remaining release tasks are: public free V2
and production unlock/Family Sharing/purchase/restore verification; replacement
or build-identified verification of the older proof; then merge the follow-up and
run a live smoke check. They cannot be completed from a TestFlight-only candidate
while the public storefront still offers paid 1.1. No deployment was triggered
by this agent's follow-up push.
