# Chronoframe website

Static HTML/CSS/JavaScript, self-hosted assets, no package installation or bundler.
GitHub Pages serves this directory at https://chronoframe.app/.

## Local review

```sh
python3 script/check_site.py
python3 script/preview_site.py --port 8765
```

Open http://127.0.0.1:8765/. The preview server supports byte ranges; Python's basic
`http.server` does not, so it cannot accurately test MP4 chapter seeking.
Check narrow/mobile and desktop layouts, keyboard navigation, the video play button,
chapter seeking from a cold load, native captions, FAQ details, and App Store links.
The site remains usable without JavaScript: native playback and HTML transcript,
FAQ disclosures, navigation, and purchase links all remain available. JavaScript only
enhances playback with a poster button and chapter shortcuts.

## Publishing and checks

`Check Website` validates site PRs. `Deploy Site` validates again and publishes `site/`
on pushes to main. A branch or PR does not update the public site. The checker is
dependency-free Python 3.9+ and covers local assets/links/fragments, basic page semantics,
JSON-LD, sitemap, no third-party render dependencies, and demo/caption delivery constraints.
Browser QA is still required; these checks are not a WCAG certification.
Run `python3 script/check_site.py --release` immediately before merging. It rejects
a held product-proof manifest; ordinary PR checks intentionally allow an explicitly
held draft. Neither mode substitutes for checking Apple's current public offer.

## Content and offer

This changeset targets the upcoming **direct free V2 launch**, confirmed by the owner
on October 16, 2026. The allowance is 500 organized files and 100 duplicates moved to
Trash cumulatively per Apple Account per Mac, with no time limit. Scanning, preview,
review and History remain unlimited. Revert is ungated and refunds allowance for
successfully undone work. The $14.99 US non-consumable lifetime unlock supports Family
Sharing and includes Reorganize; StoreKit shows local prices. There are no existing
customers to migrate, no acquisition cutoff and no paid rollout. Historical paid-app
ownership is not an access grant under this policy.

**Release coordination:** the owner reports the app has been submitted for review.
Do not merge this PR until the matching V2 build and free download are publicly
available. Verify production unlock pricing, Family Sharing, purchase/restore and
the screenshot/film behavior before merging. A push of `site/**` to main deploys
immediately. The visible offer, FAQ, and SoftwareApplication schema must agree;
the schema's offer price is the $0 download, not the optional unlock.

The target release requires macOS 14+. Apple Photos import and watched sources are
promoted; similar-video matching is explicitly opt-in and review-only. Library Guardian
is excluded because `GuardianCapability.isEnabled` is false. Do not promote gated
source-tree features merely because their implementation exists.

The demo is development footage; `assets/video/README.md` records its provenance.
The October 18 design pass selects the plan's recorded, captioned walkthrough
fallback. An interactive browser simulator is cut from this delivery; the separate
interactive dedupe extension is deferred. Captions, transcript, native controls and
chapter shortcuts supply the walkthrough without a new runtime/test dependency.
The film's `VideoObject.uploadDate` is deliberately omitted while publication is
unknown; add the actual public publication date before release. Recheck the privacy
policy's effective date at publication. Do not replace these with a projected launch
date. `assets/product-proof.json` tracks proof assets and outstanding release checks;
`assets/artwork/README.md` records the original generated artwork and exact prompt.

Keep all render assets local and preserve the no-tracking policy. Do not add behavioral
analytics merely to measure conversion. App Store Connect campaign reporting is a
possible next step once campaign links are configured by the owner.
