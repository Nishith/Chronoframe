# Website follow-up review — October 18, 2026

The website refresh is published through PRs #226 and #248. The final merge is
`c6546b715af4db482f468eb24bc842ab9296cad8`; Pages run `39186449345` succeeded.
This review uses fresh captures of [chronoframe.app](https://chronoframe.app/), not
the older preview screenshots. It assesses entry → product proof → recorded
walkthrough → support, using the in-app browser at 1280×720 and 390×844.

The main improvement is mobile product-proof readability. The desktop entry and
recorded walkthrough do not need another design pass. Public app/offer proof is
a recorded release follow-up under the owner's accepted early-publication decision.

## Recommendations and plan mapping

| Item | Priority / timing | Recommendation | Completion evidence |
|---|---|---|---|
| W1 — mobile product proof | Next website pass | Replace the default left edge of the oversized desktop image with a truthful focused mobile crop/capture. Show the planned count, destination, attention item and next action without horizontal discovery. Keep full-size and text alternatives. | Useful preview evidence visible at 320/390 pixels; no clipped text or controls with enlarged text; keyboard/focus and text alternative verified. |
| W2 — public V2 proof | When the app is public | Refresh or establish the build identity of screenshots/film; verify the download destination and production free/unlock/Family Sharing/purchase/restore offer. Fill the manifest from evidence. | Actual capture date/build/source/public-version mapping and verified production offer recorded. Unknown values are not inferred from TestFlight. |
| W3 — support navigation | Optional after W1 | Add topic jump links and a concise on-site first-run guide, reusing public docs and coordinating with existing unpublished `site/guides/` work. | People can find setup, permissions, purchase/restore and recovery help quickly; deeper GitHub docs remain optional. |

W1 is a UX finding, not a document overflow failure. W3 is an opportunity, not a
broken-link report. Do not reinstate the App Store availability hold: the owner
explicitly accepts a temporary unavailable/mismatched download link because there
are no active users or traffic. The interactive simulator remains cut from this
delivery; the recorded alternative already supplies the intended explanation.

## 1. Desktop entry — healthy

The benefit, source-original promise, free-download action and film entry are
clear. Artwork supports the photo-organizing story. The product screenshot begins
below the first viewport, but the next section is introduced. No document-wide
horizontal overflow was observed at this width. No additional hero redesign is
recommended from this review.

![Desktop entry](/Users/nishithnand/Code/Chronoframe/docs/website-follow-up-review-2026-10-18/01-home-desktop.png)

## 2. Mobile product proof — needs improvement

At a 390-pixel viewport, the image window is **333 pixels wide**, while the image
is **1120 pixels wide** and the window is about **633 pixels tall**. The initial
view shows the sidebar and a large dark strip. The useful preview/timeline is to
the right, outside the default view. The pan hint and expandable text explanation
are below that tall image, so they arrive late.

The visible 4,000-planned/zero-copied summary, full-size link and working text
disclosure are useful alternatives. Preserve them, but make the image's initial
mobile view communicate the result too. This is W1; it requires no app changes.

![Mobile proof showing the sidebar rather than the preview evidence](/Users/nishithnand/Code/Chronoframe/docs/website-follow-up-review-2026-10-18/02-mobile-preview.png)

## 3. Mobile recorded walkthrough — healthy controls

Play occupies its own row below the video, so it does not overlap the caption.
Native controls, one caption track, chapter shortcuts and the descriptive
transcript are present; autoplay is off. The transcript opens with Enter. No
document-wide horizontal overflow was observed. The small app text in the poster
has native full-screen/direct-video and transcript alternatives.

This pass inspected the entry/control presentation, not every video frame or a
new playback/seek run. The broader playback and fallback results remain in the
shipped QA record. No new interactive simulator is recommended.

![Mobile recorded walkthrough](/Users/nishithnand/Code/Chronoframe/docs/website-follow-up-review-2026-10-18/03-mobile-film.png)

## 4. Support/resources — usable; optional navigation improvement

The page includes getting-started, troubleshooting, purchase and recovery help.
Contact information is visible and the focused inline FAQ link has a visible
outline. The deeper Quick Start, full FAQ and Troubleshooting links point to
GitHub Markdown; those destinations were identified from the current page, not
audited as separate screens.

Topic jump links and an on-site first-run guide would reduce scrolling and the
need to leave the product site. This is W3, optional polish after the mobile proof.

![Support resources with visible keyboard focus and contact information](/Users/nishithnand/Code/Chronoframe/docs/website-follow-up-review-2026-10-18/04-support-resources.png)

## Evidence limits

These are current-run visual/DOM observations and selected keyboard interactions,
not a full accessibility certification. This pass did not repeat the prior axe
matrix, conduct spoken VoiceOver testing, test a physical iPhone/Safari, exercise
production StoreKit, or verify September capture identities. New mobile work
should receive its own enlarged-text and assistive-technology checks. The earlier
desktop/mobile, axe, contrast, video and publication-gate evidence remains in
`docs/website-design-2026-10-18.md` and `docs/website-qa-2026-10-18.json` in merged
PR #248 (also available in the local `.tmp/shedi-website/` checkout).
