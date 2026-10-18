# Website design update — October 18, 2026

The owner asked to prioritize the website while the submitted app is in review.
This increment continues held PR #226 from remote head `276bc8569384736247153511d65e41cd8ee8d9ec`.
It changes website assets, content, validation and this record only; it does not
change the submitted app. The older divergent local `codex/website-demo` branch
and the primary checkout's uncommitted app/marketing work are preserved.

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
- The existing captioned, user-initiated recorded walkthrough is retained. No
  browser simulation, JavaScript dependency, analytics or hosting change is added.
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
  proof provenance. The new checks reject retired access claims and an invented
  upload date while the proof is held.
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

## Still held before publication

Submission for App Review is not public availability. **Do not merge PR #226
until the matching public V2 build, free storefront, unlock price and Family
Sharing are verified.** Merging `site/**` to main publishes through Pages.

The reused September development screenshots/film are not certified captures of
the submitted build. Their app build/source commit and public-version mapping
remain unknown in the proof manifest. Verify their visible behavior against the
public release or replace them before merging. The uncommitted app design changes
from the owner's primary checkout are not used as website screenshots.

Set the film's real publication date in the manifest and VideoObject, and review
the privacy policy's effective date at publication. The live storefront and
production purchase/restore were not exercised in this design pass. Broader
artwork variants, owner visual selection, a complete accessibility review and any
sample-data browser demo remain separate follow-up work.
