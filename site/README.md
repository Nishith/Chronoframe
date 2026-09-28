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

## Content and offer

This changeset targets the upcoming **free-download release**, as requested by the
owner on September 28, rather than the paid app currently listed. The shipping policy
in `TrialAllowance.swift` is 500 files organized and 100 duplicate files moved to Trash,
cumulative with no time limit. Unlimited previews/scans/review remain available.
The documented launch unlock is $14.99 USD; regional prices are shown by StoreKit.
See `docs/free-trial-plan.md` for policy and cutover details.

**Release coordination:** do not merge this PR until the matching trial build and free
download are available in the storefront. The older plan calls for a seven-day paid
transition; confirm the owner's release timing supersedes that sequence. Check the
actual unlock price before merging. The visible offer, FAQ, and SoftwareApplication
schema must remain consistent (the schema describes the $0 download, not the unlock).

The target release requires macOS 14+. Apple Photos import and watched sources are
promoted; similar-video matching is explicitly opt-in and review-only. Library Guardian
is excluded because `GuardianCapability.isEnabled` is false. Do not promote gated
source-tree features merely because their implementation exists.

The demo is development footage; `assets/video/README.md` records its provenance.
Set VideoObject uploadDate and the privacy effective date to the actual publication
date if launch moves from September 29, 2026.

Keep all render assets local and preserve the no-tracking policy. Do not add behavioral
analytics merely to measure conversion. App Store Connect campaign reporting is a
possible next step once campaign links are configured by the owner.
