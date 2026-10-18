> Historical paid-download draft. For the October 2026 free-download launch, use `marketing/release-2.0/LAUNCH_COPY.md`. Do not publish these older pricing claims.

# Show HN draft

## Title options (pick one; HN strips "Show HN:" formatting games, keep it plain)

1. Show HN: A Mac app to merge 20 years of photo backups without touching the originals
2. Show HN: Chronoframe – organize and dedupe messy photo folders, source stays read-only
3. Show HN: I was afraid to touch my photo archive, so I built a copy-only organizer

Option 1 is strongest — it states the problem, the platform, and the safety hook in one line.

## Body

I had twenty years of photos spread across phones, old laptops, SD cards, and a
drawer of external drives. Every tool I tried either wanted a subscription to
hold my library, or moved/deleted files in bulk and asked questions later. I
was too scared to run any of them on the only copies of my kids' baby photos.

So I built Chronoframe, a native macOS app with one design rule: the source is
read-only, always. It copies your scattered media into a dated folder
structure (2024/06/15), finds exact and near-duplicate photos/videos, and
never mutates anything without showing you the full plan first.

The parts that took the most engineering, and that I'd love feedback on:

- Every destination-changing operation writes a durable receipt before it
  mutates anything. Undo re-verifies file hashes against the receipt before
  reverting — if a file changed since the run, it refuses rather than guesses.
- Interrupted runs (power loss, yanked drive) reconcile on relaunch from an
  append-only journal. Ambiguity fails closed: the app stops and tells you
  exactly which drive to reconnect instead of inferring that a missing path
  means a missing file.
- Copies are verified byte-for-byte after write. Dedupe deletions go to the
  macOS Trash only — there is no hard-delete code path in the app.
- Dedupe executes an immutable plan derived from the scan snapshot; every
  mutation target requires an expected content identity, so the commit can
  never drift from the preview you approved.
- A cross-process lock prevents the GUI, CLI, and any automation from
  mutating the same destination concurrently.

It's Swift end-to-end (SwiftUI app + a pure domain core with no AppKit deps),
runs entirely on-device — no account, no uploads, no analytics. One-time
purchase on the Mac App Store, no subscription.

Site: https://chronoframe.app
App Store: https://apps.apple.com/us/app/chronoframe/id6771245052

Happy to answer anything about the recovery model, the near-duplicate
detection, or what it took to get a file-mutating app through App Review.

## Notes before posting (delete this section)

- Post Tue–Thu, 8–10am ET. Weekends are quieter but lower ceiling.
- Be in the thread for the first 3–4 hours answering everything. HN rewards
  responsive founders; the comments are the marketing.
- Expect and pre-plan answers for the inevitable questions: "why not just
  use Photos.app / rsync / a script?", "why App Store only?", "why $14.99
  with no trial?" — the trial question is the strongest argument for
  shipping the free-scan IAP restructure BEFORE this post.
- Do not edit the post to respond; reply in comments.
- If it doesn't take off (< 5 points in an hour), it's allowed to repost
  once after a week or two — many successful Show HNs are second attempts.
