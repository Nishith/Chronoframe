# r/macapps launch post (tuned November 2026)

Tuned against the top 100 r/macapps posts of the past year (saved 2026-11-03),
the sub's current rules, and a simulated hostile comment section. The data
summary is at the end.

## Before you post (rules-driven checklist)

1. **Earn 10 local karma, then mark the rules as read.** Rule 1 requires
   10 karma earned inside r/MacApps (check at old.reddit.com/user/me, "show
   karma breakdown by subreddit"). Post approval is a "Read the Rules" flow
   on the sub's front page; the mod thread (`/r/macapps/comments/1smg62t/`)
   says a post that skips it has an 80–90% chance of removal, and a removal
   now starts a 30-day cooldown under Rule 3. Also verify the email on your
   Reddit profile; unverified profiles are on the mods' auto-removal list.
2. **You are Tier 1.** The Phase 3 thread (`/r/macapps/comments/1ryaeex/`)
   gives main-feed access to Mac App Store developers with a paid developer
   account and App Store distribution, plus 10 local karma. Notarization
   alone does not count, but you are on the store, so no portfolio or
   LinkedIn is needed. Everyone else goes to the App Pile megathread.
3. **Use the PCP template exactly.** The mods define it as: **Problem** (what
   the app solves), **Comparison** (name 1–2 top competitors and say how yours
   is better), **Pricing** (price amounts plus link). The body below follows
   it and names two competitors, not four. Changelogs and AI disclaimers were
   dropped from the requirements in Phase 3.
4. **No em dashes anywhere, and don't repost.** The mods' FAQ says em dashes
   and other recognisable AI patterns trigger Reddit's auto-removal, and that
   reposting after a removal, instead of editing and asking the mods to
   restore, leaves a strike. The body below contains none.
5. **Flair: Lifetime, not Free.** The sidebar says "Free flair: not for
   limited app tiers", and there is no trial flair. The precedent that worked:
   BookShelves ("free up to 10 books, $6.99 one-time Pro") used Lifetime and
   ended at a 0.99 ratio. The one that failed: Ultimate Clarity, a freemium
   photo manager with a $39.99 unlock, led with "free", drew the lowest ratio
   of any top Lifetime post (0.86), and edited in an apology.
6. **Post as a video (or gallery), not a text post.** Of 66 maker posts in the
   top 100, 62 carried a video, image, or gallery. Only 4 were text-only.
   Upload the 1-minute demo directly to Reddit as the post media (native
   uploads autoplay in the feed; a YouTube link does not) and put the text
   below in the body. Fallback: a 4-image gallery of Preview, Dedupe compare,
   Transfer complete, History. Include one frame of the actual dated folder
   tree in Finder; "dated folders" is abstract until people see `2019/07/14`.
7. **Drop the UTM parameters.** Rules only ban redirects and affiliate links,
   and one top post did use UTM, but a post whose pitch is "no tracking"
   reads better with clean links. Use the App Store campaign link if you want
   attribution.
8. **One self-promo post per 30 days**, counted even if removed. Don't follow
   up with another r/macapps post for a month; reply in comments instead.
9. **Timing.** Maker posts in the top 100 cluster Tue–Thu, 12:00–18:00 UTC
   (8am–2pm Eastern). Be at the keyboard for the first 4 hours. The
   warmest-received posts all had the developer answering nearly every
   comment and editing fixes into the post the same day.
10. **Post the first comment yourself**, answering your own closing question
   with the concrete trust mechanics (see "Prepared replies"). It anchors the
   thread on substance before the "freemium" and "why not rsync" replies land.

## Title

Median title length in the top 100 maker posts is 76 characters, but specific
long titles outperform generic short ones (the four highest-scoring Lifetime
posts with bodies all run 60–130 characters and tell a one-line story). Your
current title is 142 characters and contains two ideas. Pick one.

**Recommended (fear hook, 123 chars):**

> I was too scared to touch 20 years of family photos, so I built a Mac organizer that shows the full plan before it copies a single file

Outcome-led alternative (for a more skeptical day):

> Chronoframe: a Mac photo organizer that previews every copy before it happens. Copies, never moves. Content-based dedupe for photos and video. $14.99 once

Note: "I got tired of X so I built Y" is now openly mocked in the sub (a
post parodying it got 324 upvotes, and a meme titled "Every app thread on
r/macapps lately" got 401). The fear hook is a different emotion and reads
as sincere, so it survives that. Don't add "tired". Expect one comment
about "scared to touch, yet you built delete"; the Trash-only answer handles it.

## Body

Top maker posts have a median of 305 words (2,063 characters) and a 75th
percentile of 407 words (2,725 characters); the longest in the top 100 is
about 5,700 characters. Your draft was about 1,100 words. This is about 600
words and 3,700 characters including headings and links, upper-middle of the
range. If you want it shorter, cut the Apple Photos bullet and the Dup line
first; keep "How it checks".

---

Developer here, so read this as a maker post.

**Problem**

Twenty years of photos and videos across phones, laptops, and a drawer of old drives. Every tool I tried wanted to move files or delete duplicates in bulk, and when you hold the only copy of something, "move" is a scary word. I wanted to see the whole plan first, copy instead of move, and approve every change myself. So I built Chronoframe.

**What it does**

- **Organize.** Point it at any folders: phone backups, camera dumps, an old drive. It shows the full dated-folder plan, including every file whose date it is unsure about, before a single file is copied. The source is only ever read. Copies go to a separate destination, and a filename collision gets a new name, never an overwrite.
- **Deduplicate.** Exact copies of photos and videos by content, not filename. Similar photos get a side-by-side review. Optional similar-video matching flags re-exports and resized versions of the same clip (4K master, 1080p export, the compressed one from Messages). You pick what stays. Only files you approve go to the macOS Trash.
- **Apple Photos.** Copies unedited originals out of Photos into dated folders, Live Photo pairs intact. The library itself is never changed.
- **History.** Every run writes a receipt of what was copied or trashed, with hashes, and can be undone while the recorded files still match.

**How it checks**

- Every file is hashed in full (BLAKE2b). Each copy is re-hashed before it is finalized (on by default); a mismatch discards the copy and reports the file.
- Date priority: EXIF or video metadata, then a date in the filename, then file system dates. Only metadata counts as confident; the rest is flagged for review in the plan, not guessed quietly.
- In dedupe, RAW+JPEG pairs, XMP sidecars, and Live Photo pairs are reviewed as one unit, so keep or trash applies to the whole set.
- An interrupted run (power, unplugged drive) reconciles from its journal on relaunch instead of guessing.

Native Swift, runs entirely on your Mac. No account, no uploads, no analytics. macOS 14+, Apple Silicon and Intel.

**Comparison**

- vs **Gemini 2** (subscription, from $1.95/mo): duplicates only, exact matches only for video, no organizing.
- vs **PhotoSweeper** ($14.99 once): a good duplicate tool, photos only.

Dup, a newer App Store app, also does frame-based similar video, so that part is not unique to me. The difference is the combination: preview-first organizing plus exact and similar video dedupe, on device, paid once. If your library is already tidy and you only need dedupe, one of those may suit you better.

**Pricing**

Free trial allowance: organize 500 files and move 100 approved duplicates to Trash. That is a lifetime total per Mac, not a monthly reset, and undoing a run gives it back. Scanning, preview, review, and History are unlimited, so you see exactly what it would do before paying. US $14.99 once removes the limits, adds Reorganize, and supports Family Sharing. No subscription.

**Limits, up front**

- It copies rather than moves, so you need extra space at the destination.
- Dedupe works on folders. It does not go inside your Apple Photos library.
- Trash is Trash: space comes back when you empty it, and restore from History only works while those files are still there, unchanged.

**Disclosure:** I'm Nishith, the developer. Solo project.

Mac App Store: https://apps.apple.com/app/chronoframe/id6771245052
Site and 1-minute demo: https://chronoframe.app

One question: what would stop you trusting an app with the only copy of something? That shaped every choice here, and I would rather hear the hard version now than guess.

---

### Optional: giveaway block

The three highest-comment maker posts of the year all ran a promo-code
giveaway in the title and body (1,271 / 461 / 400 comments). App Store
offer codes work for the in-app unlock. If you want the comment volume, add
`[Giveaway: 20 lifetime unlock codes]` to the end of the title and this
paragraph after Pricing:

> I have 20 unlock codes for this thread. Comment with the worst photo mess you are sitting on and I will pick 20 at random on Friday and DM the codes.

Giveaway comments inflate counts without much signal, so skip it if you want
the trust question answered rather than a code lottery.

## What changed from your draft and why

| Change | Evidence |
|---|---|
| Cut from ~1,100 to ~600 words | Maker-post median 305 words, p75 407, max ~670 in the top 100. Nothing above 700 words made it. |
| Reordered into Problem / What it does / How it checks / Comparison / Pricing / Limits / Disclosure | The sub's mandatory PCP template. The four highest-rated Lifetime posts with bodies (Wallspace, BookShelves, SmoothCSV, Ultimate Clarity) all use these exact bold headings. |
| Added "How it checks" with hash, verification, date priority, sidecars, interruption | The simulated comment section's top skeptical replies were "verified how?", "which hash?", "RAW+JPEG and XMP?", "what picks the date?", and "vibe-coded?". Specifics are the only answer this crowd accepts, and every fact in the block is taken from the engine code. |
| Comparison cut to two "vs X:" bullets (Gemini 2, PhotoSweeper) plus one honest line about Dup; Cisdem dropped | The mods' PCP definition says name 1–2 top competitors. "No lifetime price listed" read as petty in the red-team pass; "subscription" says the same thing neutrally. Cisdem is still on the compare page for anyone who follows the link. |
| "Free: organize 500 files…" became "Free trial allowance… a lifetime total per Mac, not a monthly reset" | Ultimate Clarity was downvoted for leading with "free" on a freemium app. "Per Apple Account per Mac" read as a licensing trap in the red-team pass; "lifetime total per Mac" says it plainly. |
| "Receipt" and "needs review" explained inline | Both were flagged as jargon to a first-time reader. |
| "Regional pricing shows in the app" became "US $14.99" | Flagged as sounding evasive. |
| Added "Native Swift" | "Sick of Electron" is a recurring winner (a list of native apps got 390 upvotes; several top posts close with "no Electron bloat"). |
| Removed "works offline after App Store verification" | Your site's wording is narrower: offline once purchase or trial access has been verified, and iCloud originals need a download. Covered by "runs entirely on your Mac". |
| Moved the trust question to the last line, and you answer it first in the comments | Posts that end on one specific question (BookShelves, Ultimate Clarity, SmoothCSV) got the longest substantive threads. |
| Dropped the 4-step numbered walkthrough | Top posts show the flow in the video, not prose. |
| App Store link first, "Disclosure:" as its own bold line | Rule 2 (official distribution only) and Rule 3 (disclosure). The Mac App Store also signals the trusted tier after the "32 lifetime apps, 32 license bypasses" audit post that targeted direct-download apps. |

## Prepared replies (post the first one yourself)

- **Your own first comment, answering the trust question.** Source folder is
  opened read-only; nothing is ever written there. Receipt is written before
  any file moves. Every copy is hashed before and after. Deletion is Trash
  only; there is no permanent-delete code path. Undo checks hashes before it
  touches anything. Interrupted runs reconcile from a journal. Then: "What
  would you add?"
- **"Freemium, not free."** Agree immediately: "Fair. It's a trial allowance,
  which is why the flair is Lifetime." Don't argue the word.
- **"Why not Photos' Duplicates album / Hazel / ExifTool / rsync?"** One line
  each on what they lack (no plan preview, no content-based video dedupe, no
  receipt-based undo). Concede that a scripted workflow is fine if you already
  have one.
- **"RAW+JPEG, XMP, HEIC vs JPG, bursts?"** Pairs and sidecars are one dedupe
  unit. Be precise about the edges: .xmp is the only sidecar type recognised,
  and only in dedupe; Organize copies photo and video files only, so an .xmp
  next to a RAW is not carried over, and .aae and .dop are not recognised at
  all. Say that rather than "coming soon".
- **"Sandbox, NAS, external drives, drive sleeps mid-copy?"** Answer with what
  the lock and recovery actually do. Say which network setups you have tested.
- **"How does it pick the date? Screenshots and WhatsApp images?"** Repeat the
  priority chain, and say those land in the review list with a low-confidence
  flag, where you can set the date yourself.
- **"Performance on 100k files / a USB HDD?"** Give a real number from your own
  library if you have one, and say the scan cache makes re-runs incremental.
- **"$14.99 is steep / Gemini is cheaper."** Repeat the comparison line once
  and stop.
- **"What about Cisdem / Nektony?"** Point to the compare page, which has
  hand-checked prices for both, and say why they were left out of the post
  (the sub asks for one or two competitors).
- **"Vibe coded?"** Answer plainly and once. Evasiveness is what draws fire.
- **Bug reports.** Reply, fix, and edit an "Update:" block into the post listing
  what shipped. BookShelves did this twice and ended at a 0.99 ratio.

## Data summary (top 100 posts, r/macapps, past year, saved 2026-11-03)

- 66 of 100 were maker/app posts (31 Lifetime, 31 Free, 2 Deal, 2 Vibe Coded).
- Media: 38 video, 13 image, 10 gallery, 4 text-only, 1 link.
  Median score: gallery 466, video 435, image 405, text 404.
- Body length (chars): median 2,063, p25 1,439, p75 2,725, max 5,669.
- Title length: median 76 chars.
- 15 of 66 titles start "I built / I made / I spent / I got tired"; 8 use
  "because" or "so I".
- Median comments: Lifetime 244, Free 194. Giveaway posts: 1,271 / 461 / 400.
- Day (UTC): Wed 14, Thu 12, Mon 11, Fri 10, Tue 9, Sat 5, Sun 5.
  Hour (UTC): 12–15h is the mode (22), then 15–18h (11), 18–21h (10).
- Meta posts in the top 100 that signal community mood: "I tested every
  'lifetime' Mac app posted here for 7 weeks – 32 apps, 32 bypasses" (328),
  "Pricing and viability of indie apps post-AI" (621), "Every app thread on
  r/macapps lately" meme (401), parody of "I got tired… so I built" (324),
  "Raycast is deleting posts with negative feedback about its new pricing"
  (424), "1Password price increase – looking for alternatives" (350).
- Raw table of all 100 posts: `marketing/macapps-top-posts-2026-11-03.csv`.
