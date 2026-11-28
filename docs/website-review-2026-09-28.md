# Chronoframe website: critical review and implemented improvements

> **Status (2026-11-21): historical review, implemented and published.** Reviewed 2026-09-27 and 2026-09-28; its changes shipped in PR #226 (merged 2026-10-18, Pages deployed `54df5f9`). Later website work (design and mobile-support records, removed 2026-11-23; see git history): PR #248 and #249, the `/compare` page (#254, #256, #257), the dated-folders guide (#255) and campaign-tagged links (#262). Shortened 2026-11-21: the before/after narrative and per-finding prose are folded into the table below. Hypotheses here were never measured: no conversion baseline, customer interview or App Store Connect analytics existed.
>
> **Still open from this review:** (1) the proof manifest (`site/assets/product-proof.json`) still marks the September development screenshots and film as unmapped to a public build, with `verify_against_public_V2_before_publication` on each; V2 has been public since 2026-10-22, so this check can now be done. (2) Real customer proof (a permissioned quote or a reproducible case study) does not exist yet. (3) Purchase measurement without site tracking: campaign links exist (#262); the App Store Connect baseline comparison has not been recorded here.

Goal: help a prospective Mac customer understand the product, trust its workflow and decide with fewer detours, keeping the dark Meridian theme, the static architecture and the privacy promise. Differentiator the original site undersold: care for irreplaceable originals. Evidence images: [live homepage](site-review/01-live-home-desktop.png), [mobile before](site-review/06-live-home-mobile.png) and [after](site-review/10-new-home-mobile.png), [original safety page](site-review/07-live-safety.png), [live store listing](site-review/04-live-store.png), [demo](site-review/13-demo-ready.png), [purchase section](site-review/14-purchase-desktop.png), [refreshed product screens](site-review/15-refreshed-product-screens.png).

## Findings and resolutions

| Priority | Finding | Resolution (all implemented in #226) |
|---|---|---|
| High | Product proof arrived late | The 60-second film near the top: play button, four chapter shortcuts, WebVTT, HTML transcript. 1080p export is 6,874,782 bytes; native playback works without JavaScript. |
| High | Long hero and repeated trust copy on phones | Shorter pitch, category named, separate purchase and watch actions, amber action color, same brand. |
| High | Paid-upfront funnel could not describe the free-download release | Led with a free download: 500 organized files, 100 moved to Trash, no time limit, unlimited review, optional lifetime unlock; FAQ covers cumulative allowances, Reorganize and restoring existing buyers. |
| High | Safety copy overpromised (no-loss language, universal verification, universal network locking) | Verification described as on by default, same-Mac locking and unsupported multi-host use stated, receipt/content/Trash conditions clarified, independent backups recommended. Organize's read-only source is distinguished from separately approved Trash operations in a Deduplicate folder. |
| Medium | Trash does not reclaim space | Homepage answer: emptying Trash releases space and ends that recovery option. |
| Medium | Repetitive sections, negative competitor passage | Two outcomes and a three-step starting path; shorter maker note. |
| Medium | Detours for subscription, formats, Apple Photos, offline use, free space | Inline disclosures with FAQ and support links; Apple Photos import explained and distinguished from deleting in Photos. |
| Medium | Mac compatibility mismatch (store macOS 13+, source 14+) | Site states macOS 14+ consistently. |
| Medium | Metadata did not expose the video or offer | SoftwareApplication and VideoObject JSON-LD, no fabricated ratings; sitemap dates and versioned CSS/JS. |
| Medium | Deploy checked file existence only | `script/check_site.py` validates all pages, local targets and fragments, metadata, sitemap, video policy and size, fast-start atoms and caption timings; runs on PRs and before deployment (now with `--release`, see #248). |
| Low | Header/footer repetition | Shared compact navigation, visible store action, dedicated price and maker section; all routes kept. |
| Correction | Seven older light-interface screenshots remained | Five illustrated workflows now use the approved September marketing captures (digests in `site/assets/screenshots/provenance.json`); stale Health and detection-setup images removed; contain sizing, linked originals, new filenames to defeat caches. |

## Release feature decisions (copy rules that still apply)

- Promote Apple Photos import: explain original/unedited resources, read-only access, iCloud downloads and staging space; never imply deduplication inside Photos.
- Promote watched sources, but call arrival counts estimates and imports review-gated; never imply unattended imports.
- Explain similar-video matching as opt-in, extra analysis, review always required.
- Do not promote Library Guardian: `GuardianCapability.isEnabled` is still `false` (`GuardianCapability.swift:12`).
- Keep the trial specific: 500/100 cumulative allowance, with preview, scan/review, CSV, Health and History unlimited; revert ungated and refunds successfully undone work; Reorganize requires the unlock. StoreKit networking belongs in the privacy and offline explanations.

## Engineering notes worth keeping

- No framework, build service, external font, tracking script or video embed. The only production JavaScript enhances playback; HTML carries content, native controls, captions, transcript, disclosures and purchase links. Playback is user-initiated with a visible fallback.
- Preserved accessibility: one h1 per page, language, alt text, intrinsic dimensions, visible focus, skip-link target, native details/summary, 44px targets, reduced-motion and forced-colors handling. Inspected contrast pairs meet 4.5:1. No full WCAG conformance claim; VoiceOver pass and real Safari/iPhone/Firefox testing were not done.
- `script/preview_site.py` supports HTTP byte ranges (plain `http.server` does not, which broke chapter seeking).
- Validation recorded: `check_site.py` (nine pages), `node --check site/site.js`, full FFmpeg decode of the MP4 with matching SHA-256, readyState 0 before play (no eager load), reflow at 1280, 390 and 320 px.
