# r/macapps launch post — tuned draft (2026-11-04)

## Title (recommended)

I was afraid to touch 20 years of photos, so I built a Mac organizer that shows the full plan before it copies anything

Alternatives:
- Chronoframe: preview-first photo organizer and duplicate finder for Mac. Native, one-time $14.99, no subscription
- I built a Mac photo organizer that never touches your originals: full preview before copying, undo after

Use the sub's pricing flair (Lifetime) rather than putting the price in the title.

## Body

Hi r/macapps. Maker post: I built this, so weigh it accordingly.

I had twenty years of photos and videos spread across old phones, laptops, and a drawer of drives, and I never merged them because I was scared of wrecking the only copies. So I built Chronoframe around one rule: show me everything it is going to do, then do only that.

[15-second GIF or short video: pick folders → full plan appears → approve → History with Undo]

**What it does**

- Point it at any folders: phone backups, camera cards, old drives. Sources are opened read-only.
- It shows the complete plan first: the date it resolved for each file, the destination folder, the counts, and anything it is unsure about. Nothing copies until you approve.
- It copies into a separate destination and verifies every copy. Name collisions get a new name. It never overwrites, moves, or deletes a source file.
- Every run writes a receipt. Undo from History while the recorded files still match.
- Duplicates are found by content, not filename. Exact matches for photos and video, side-by-side review for similar photos, and optional similar-video matching for re-exports and resized copies (my 4K original, 1080p share, and compressed messaging version of the same clip). Only files you approve go to the Trash. Nothing is deleted outright.
- Optional Apple Photos export: unedited originals into dated folders, Live Photo pairs kept together. It only reads your library.

Native Swift, sandboxed, everything on-device. No account, no uploads, no analytics, no crash reporting. macOS 14 or later, Apple Silicon and Intel.

**Price**

Free to download. Scanning, the full preview, duplicate review, and History are unlimited, so you can run it over your whole library and see every decision before paying. The free tier lets you organize 500 files and trash 100 duplicates; undoing a run gives that back. One $14.99 purchase unlocks it for life, Family Sharing included. No subscription. I'll drop [N] App Store codes in a comment.

**Where it falls short**

- It copies rather than moves, so the destination needs the space up front.
- Dedupe works on folders. It will not clean duplicates inside your Photos library.
- Restore from History works only while the trashed files are still in the Trash.
- macOS 14+ only. Mac App Store only.

**Compared with Gemini 2, PhotoSweeper, and Cisdem:** those are duplicate finders. Chronoframe combines organizing into dated folders with duplicate finding, preview-first, for a one-time price. If your library is already tidy and you only need photo dedupe, PhotoSweeper is cheaper and good.

**One question for you:** what would make you refuse to trust an app with the only copy of something? That shaped every decision here, and I'd rather hear the hard version now than guess.

Site: https://chronoframe.app
Mac App Store: [direct apps.apple.com link]

Nishith

## App Pile megathread version (if the main feed is not open to you)

**Chronoframe** — Mac photo and video organizer with duplicate finding. Native Swift, on-device, macOS 14+.
**Problem:** merging years of photos from phones, drives, and Apple Photos without risking the originals. Shows the full plan before any copy, copies with verification, never overwrites or deletes sources, undo from History. Dedupe by content, including similar-video matching; Trash only, with your approval.
**Comparison:** Gemini 2, PhotoSweeper, and Cisdem are duplicate finders. Chronoframe adds preview-first organizing into dated folders and pairs it with dedupe. PhotoSweeper is cheaper if you only need photo dedupe.
**Pricing:** free to download; unlimited scan and preview; organize 500 files and trash 100 duplicates free. $14.99 one-time unlock, Family Sharing, no subscription.
https://chronoframe.app · [App Store link]
