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
Run `python3 script/check_site.py --release` immediately before merging. It requires
verified public-release proof or recorded owner approval for early website
publication. Ordinary PR checks allow held drafts. Owner-approved early publication
does not mean the public app or capture builds have been verified.

## Content and offer

This changeset targets the upcoming **direct free V2 launch**, confirmed by the owner
on October 16, 2026. The allowance is 500 organized files and 100 duplicates moved to
Trash cumulatively per Apple Account per Mac, with no time limit. Scanning, preview,
review and History remain unlimited. Revert is ungated and refunds allowance for
successfully undone work. The $14.99 US non-consumable lifetime unlock supports Family
Sharing and includes Reorganize; StoreKit shows local prices. There are no existing
customers to migrate, no acquisition cutoff and no paid rollout. Historical paid-app
ownership is not an access grant under this policy.

**Release coordination:** on October 18, 2026 the owner approved publishing the
website while V2 is in review and accepted the temporary unavailable/mismatched
App Store link because there are no active users or traffic. The previous hold is
superseded. Verify production unlock pricing, Family Sharing, purchase/restore and
the screenshot/film behavior after public V2 is available. A push of `site/**` to main deploys
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
The film's actual publication date is October 18, 2026, following the owner's merge
of PR #226 and its successful Pages deployment. A live range request verified the
expected media size. This does not establish public V2 availability: the proof
manifest records owner-approved prelaunch publication and outstanding app/offer
verification. The privacy policy was reviewed;
this pass introduces no new data practices, so its existing effective date remains.
Do not replace these with a projected launch date.
`assets/product-proof.json` tracks proof assets and outstanding release checks;
`assets/artwork/README.md` records the original generated artwork and exact prompt.

Keep all render assets local and preserve the no-tracking policy. Do not add behavioral
analytics merely to measure conversion. App Store Connect campaign reporting is a
possible next step once campaign links are configured by the owner.
