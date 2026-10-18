> Historical paid-download draft. For the October 2026 free-download launch, use `marketing/release-2.0/LAUNCH_COPY.md`. Do not publish these older pricing claims.

# Reddit post drafts

Read each subreddit's self-promo rules the week you post; some require a
mod message first or limit dev posts to specific days. Never post the same
text twice — these are deliberately different angles. Space posts ~1 week
apart. Reply to every comment.

---

## 1. r/macapps — the "I made this" post

Subreddit is explicitly friendly to indie dev launches. Straight product post.

**Title:** I made a photo/video organizer + deduplicator where your source folder is always read-only [one-time purchase, on-device]

**Body:**

Hi r/macapps — after years of being too scared to touch my own photo
archive, I built the tool I couldn't find, and it's now on the Mac App
Store. Sharing here because this sub has shaped a few of my decisions
(one-time purchase, no accounts, native SwiftUI).

Chronoframe does two jobs:

**Organize** — copies scattered photos/videos from any folder (phone dumps,
SD cards, old drive backups) into a clean dated structure like `2024/06/15`.
It resolves dates from metadata, filenames, and file content, and flags
anything uncertain for review *before* copying. The source folder is never
written to — no moves, no renames, no deletes.

**Deduplicate** — finds exact photo/video copies by content (not filename),
plus near-duplicates: bursts, RAW+JPEG pairs, Live Photos. You review
side-by-side and pick keepers. Everything you approve goes to the macOS
Trash — the app has no permanent-delete code path.

Safety details, since that's the whole point:

- Full preview of every plan before anything is copied or trashed
- Copies verified byte-for-byte after write
- Every run writes a receipt; supported runs can be reverted from History
- Interrupted runs (power loss, unplugged drive) reconcile safely on relaunch
- Entirely on-device: no account, no uploads, no analytics

$14.99 one-time (intro price), no subscription. macOS 14+, Apple Silicon
and Intel.

Site: https://chronoframe.app
App Store: https://apps.apple.com/us/app/chronoframe/id6771245052

I'm the developer and happy to answer anything — including "why not just
use X", which I asked myself a lot before building this.

---

## 2. r/DataHoarder — the problem/methodology post

This sub hates drive-by promotion but loves methodology and safety
engineering. Lead with the workflow problem; the app appears halfway down.
Check current self-promo rules; if in doubt, message the mods first.

**Title:** How I consolidated ~20 years of photo backups from a drawer of drives without risking the originals

**Body:**

Like a lot of people here I had the drawer: external drives from three
laptops ago, SD cards, phone backup dumps, a NAS folder called
`photos_final_v2_REAL`. Massive overlap, no structure, and every
consolidation tool I tried wanted to *move* files or delete duplicates
in bulk. With irreplaceable data, "move" is a scary word.

The workflow I landed on, whatever tools you use:

1. **Copy, never move.** Treat every source as read-only until the new
   library is verified. Disk space is cheaper than regret.
2. **Verify after copy.** A copy isn't a copy until it's been re-read and
   compared. Checksums or byte-compare, not file size + date.
3. **Dedupe by content, not filename.** IMG_0042.jpg exists on every drive.
   Hash-based exact matching first, perceptual matching for near-dupes
   (bursts, RAW+JPEG, re-encodes) second — and never auto-delete the
   near-dupes, always review them.
4. **Trash, don't delete.** Deletions should be reversible for weeks.
5. **Keep receipts.** A log of exactly what was copied/removed and from
   where, so you can audit or undo later.

I couldn't find a Mac app that enforced all five, so I built one
(Chronoframe — https://chronoframe.app, one-time purchase, on-device only,
I'm the dev). The source folder is architecturally read-only, every plan
is previewed before execution, copies are verified, deletions are
Trash-only, and every run writes a receipt that supports verified undo.
Interrupted runs reconcile from a journal on relaunch instead of guessing.

Even if you'd rather script this with rsync + checksums (respect), the
five rules above are the actual point of this post — I lost photos in
2011 to a "smart" dedupe tool and built my entire approach around never
letting that happen again.

Happy to go deep on the verification/recovery design or dedupe detection
in comments.

---

## 3. Bonus: comment-first strategy (higher trust, slower)

Before or instead of the r/DataHoarder post: search the sub (and
r/photography, r/AppleWatch adjacent subs, Apple support communities) for
recurring threads like "how do I merge photo libraries", "best duplicate
photo finder Mac", "consolidate old drives". Answer the actual question
thoroughly, mention Chronoframe once with a disclosure ("I built an app
for exactly this"). Reddit's algorithm surfaces old threads in Google
results for years — these comments are SEO assets too.
