# Website design update — October 18, 2026

> **Status (2026-11-21): historical record, shipped.** Continued held PR #226 (remote head `276bc8569384736247153511d65e41cd8ee8d9ec`); the owner merged it at 23:54:32 UTC on 2026-10-18 and Pages deployed `54df5f9` at 23:54:53 UTC. Final QA fixes shipped as PR #248 (`c6546b7`), followed by [mobile preview and Support](website-mobile-support-2026-10-18.md) in #249. The owner approved publishing before V2 was public and accepted a temporary unavailable or mismatched App Store link; that superseded the publication hold. V2 has been public since 2026-10-22. Shortened 2026-11-21 (validation narrative condensed; raw results are in [website-qa-2026-10-18.json](website-qa-2026-10-18.json)).
>
> **Still open:** the September development screenshots and film are not certified captures of public V2. `site/assets/product-proof.json` still has `publication_status: owner_approved_prelaunch` and `verify_against_public_V2_before_publication` on each proof asset. Verify their visible behavior against public 2.0 or replace them, then update the manifest and the `--release` gate expectations. The app/offer proof (public build, Free storefront, unlock price, Family Sharing) was not re-verified by this website work; the owner's 2026-11-21 check of the US listing shows Free, 2.0, and the "Chronoframe Unlock $14.99" in-app purchase (US only).

The change touched website assets, content, validation and this record only; no app change.

## Delivered

- Shorter introduction keeping "A lifetime of photos, finally in order." Original generated photo-print artwork (`site/assets/artwork/photos-to-order.jpg`, 1536×1024, under 350 KB; prompt in `site/assets/artwork/README.md`). Warm graphite, amber and indigo with system typography keep the Meridian identity. Implemented for owner review, not recorded as an approved final visual selection.
- One real Organize preview in the main proof position, its staged 4,000-file scope stated and distinct from the 500-file allowance. Small screens can pan, open the original or expand a readable text alternative.
- Four steps (choose folders, preview, approve copies, inspect History) and a separate Deduplicate story (compare, review, Trash, conditional restore, including the Trash/storage tradeoff).
- The captioned, user-initiated recorded walkthrough is the selected delivery. The interactive Organize simulator was cut (new state machine, test dependencies and CI lane for too little explanatory gain); the optional interactive dedupe extension stays deferred. No JavaScript dependency, analytics or hosting change.
- Offer aligned with the 2026-10-16 direct-free policy: cumulative 500/100 allowance per Apple Account per Mac; unlimited scanning, preview, review and History; $14.99 US one-time lifetime unlock with Family Sharing; ungated revert with refunds for successfully undone work. Old paid-app grants and paid-transition instructions removed.
- `site/assets/product-proof.json` separates real development captures from decorative artwork and records unknown app versions and builds explicitly. The film's publication date is **2026-10-18** (successful Pages run recorded; live byte-range request returned HTTP 206 for the 6,874,782-byte film). The privacy policy was reviewed and its September 29 effective date retained.
- All five approved original screenshot PNGs matched their recorded source SHA-256, and the film matched its production export hash; every proof asset has a checksum verified by `check_site.py`.

## Follow-through checks

- Apple's US lookup (`https://itunes.apple.com/lookup?id=6771245052&country=us`) on 2026-10-18 returned version 1.1, $14.99, minimum OS 13.0, while the installed app was 2.0 (507, source commit `f54191843a7f95f0ad211c79714402e36ea7f4ea`). The manifest records both without mapping the September captures to 507.
- Accessibility (temporary local axe-core 4.10.3, WCAG 2 A/AA, 2.1 A/AA, 2.2 AA, best practices): zero violations and zero horizontal overflow on all seven content pages at 320, 390, 768 and 1280 px frames, plus a doubled-text-size stress pass at 320 (not browser zoom). Fixed: color-only inline links, an unsupported label on a proof container, grid overflow, unbreakable email text, a mobile Play button overlapping the caption. Lowest muted-text contrast over the closing gradient is 4.75:1. Spoken VoiceOver and OS forced-color sessions were not performed; this is not WCAG certification.
- Keyboard and failure states: skip link, screenshot scroll region (ArrowRight pans), details, chapter controls and video are reachable; a missing-media fixture announced the load error with transcript fallback; with the enhancement script removed, native controls, one caption track and transcript still work.
- Release gate: `python3 script/check_site.py` for drafts, `--release` before merging. It accepts the recorded owner-approved prelaunch state, fails on a held manifest without approval, and fails if unknown captures are labeled fully verified.

## PR #248 review follow-up

Pages still ran the draft checker, so a held manifest could reach deployment. The Pages workflow now runs `python3 script/check_site.py --release` before upload and deploy. `script/test_site_release_gate.py` reads the command from the real workflow and checks four cases against temporary copies (draft permits held proof; deploy rejects held proof; deploy accepts recorded owner approval; deploy rejects missing approval); `Check Website` runs it. No app code or visible content changed.
