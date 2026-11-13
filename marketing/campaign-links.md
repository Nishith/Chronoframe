# Campaign links

Every link shared from Nov 7, 2026 onward carries a channel tag so App Store Connect
(App Analytics → Sources → Campaigns) can attribute downloads and lifetime unlocks, and so
site visits can be split by referrer in site analytics.

- App Store provider token: `pt=117867077` (public; it appears in every shared link).
- App Store link form: `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=<ct>&mt=12`
- Site link form: `https://chronoframe.app/?utm_source=<source>&utm_medium=post&utm_campaign=<campaign>`
- A campaign appears in App Store Connect automatically once its `ct=` value receives traffic. Nothing has to be created first.
- Never share the untagged canonical link `https://apps.apple.com/us/app/chronoframe/id6771245052?mt=12` in a post. It stays only in the site's JSON-LD schema.
- Log every published post in `marketing/PROGRESS.md` under "Post log" with the link you actually used.

## Paste into the live r/macapps post now

| Link | URL |
|---|---|
| App Store | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-macapps&mt=12` |
| Website | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=launch30` |

## All channels

| Channel | `ct=` | utm_source / utm_campaign | Tagged App Store link | Site link with UTM |
|---|---|---|---|---|
| r/macapps (launch) | `reddit-macapps` | reddit / launch30 | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-macapps&mt=12` | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=launch30` |
| chronoframe.app buttons | `site` | — | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=site&mt=12` | — (these are the site's own download buttons) |
| r/apple Promo Sunday | `reddit-apple` | reddit / promo-sunday | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-apple&mt=12` | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=promo-sunday` |
| r/ApplePhotos | `reddit-applephotos` | reddit / applephotos | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-applephotos&mt=12` | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=applephotos` |
| Show HN | `hn-show` | hackernews / show-hn | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=hn-show&mt=12` | `https://chronoframe.app/?utm_source=hackernews&utm_medium=post&utm_campaign=show-hn` |
| r/SideProject | `reddit-sideproject` | reddit / sideproject | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-sideproject&mt=12` | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=sideproject` |
| YouTube film + Short | `youtube` | youtube / film | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=youtube&mt=12` | `https://chronoframe.app/?utm_source=youtube&utm_medium=post&utm_campaign=film` |
| r/MacOS | `reddit-macos` | reddit / macos | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-macos&mt=12` | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=macos` |
| Black Friday sale | `bf-sale` | (per venue) / bf2026 | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=bf-sale&mt=12` | `https://chronoframe.app/?utm_source=<venue>&utm_medium=post&utm_campaign=bf2026` |
| r/DataHoarder | `reddit-datahoarder` | reddit / method | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-datahoarder&mt=12` | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=method` |
| r/macapps second post | `reddit-macapps-2` | reddit / update | `https://apps.apple.com/us/app/chronoframe/id6771245052?pt=117867077&ct=reddit-macapps-2&mt=12` | `https://chronoframe.app/?utm_source=reddit&utm_medium=post&utm_campaign=update` |

Black Friday: replace `<venue>` with the posting venue's `utm_source` from this table
(`reddit`, `hackernews`, `youtube`), keeping `utm_campaign=bf2026`.

## Notes

- The site's download buttons default to `ct=site`. If the visitor arrived with `utm_source` (else `utm_campaign`) in the URL, a small inline script on each page rewrites `ct=` on App Store links to that value (sanitized to `[A-Za-z0-9_-]`, max 40 chars), so tagged site links keep their channel. Source wins over campaign because campaigns such as `launch30` are shared across channels (the guides link home with `utm_campaign=launch30`).
- Guide pages default to `ct=guide-<folder-name>` (cut to 40 chars) instead of `ct=site`, with the same utm override.
- The site's three SEO guides already link back to the homepage with their own
  `utm_source=guide_*&utm_medium=seo_guide&utm_campaign=launch30` tags; those are unchanged.
- `ct=` values are case-sensitive in App Store Connect reports. Copy them exactly.
