# Frequently Asked Questions

## Safety & Originals

**Q: Will Chronoframe delete or modify my original photos?**

A: No. Chronoframe only *reads* the folders you add to organize. Your originals are never moved, modified, or deleted. You control when (and whether) to delete them.

**Q: What if something goes wrong while Chronoframe is copying?**

A: Chronoframe writes files atomically (to a temporary location, then renames them into place), records mutation state durably, and reconciles interrupted work on the next launch. A completed copy is re-hashed by default; an incomplete temporary copy is never presented as a finished media file. Use **History** to review what was recovered, resume pending work, or **Undo** supported copies.

**Q: What if an external drive disconnects during a run?**

A: Chronoframe does not treat a disconnected or permission-denied drive as proof that files disappeared. Reconnect and unlock the drive, reopen Chronoframe, and refresh **History**. An interrupted entry may show **Needs Drive**, **Trash Location Unverified**, or **Manual Recovery Needed** until the filesystem state can be proven safely.

**Q: Why does Chronoframe say another operation is using the destination?**

A: Only one organize, deduplicate, reorganize, undo, CLI, or system-integrated mutation can use a destination at a time, so two valid plans can't race each other. See [Troubleshooting](./TROUBLESHOOTING.md#another-chronoframe-operation-is-already-using-this-destination).

**Q: Can I undo an organize operation?**

A: Yes. Open **Organize** → **History** and click **Undo** next to the copy you want to undo in the **Undo Center**. You can also open the ⋯ menu on a receipt in **Reports and Logs** and choose **Undo…**. Chronoframe will delete only the files it copied (not anything that was already in the destination). Undo verifies content hashes, so it won't delete files if they've been modified since the copy.

**Q: How do I know what Chronoframe will copy?**

A: **Preview Plan** shows the exact plan before anything is copied. You can review the plan and edit uncertain dates in the **Review** tab on the **Preview & Copy** screen. **Start Copying** uses the same plan you approved.

---

## Performance & System Requirements

**Q: What are the system requirements?**

A: macOS 14.0 or later. Chronoframe works on Intel and Apple Silicon Macs.

**Q: How much disk space do I need?**

A: Enough for your destination folder to hold copies of your original files. Chronoframe doesn't compress; it copies files as-is. You'll need roughly the same amount of free space as the size of the folders you are organizing.

**Q: Why is the first scan taking so long?**

A: Scanning reads metadata, computes content hashes, and resolves dates. Large libraries (50K+ photos) can take 5–10 minutes. Once done, Preview rebuilds are faster because destination metadata is cached in `.organize_cache.db`.

**Q: Can I speed things up?**

A: Yes—
- Open **Settings → Performance** and raise **Files at Once**, or turn on **Parallel Copies** (the **Standard** preset turns them on and sets 8 workers).
- Pre-filter your folders into smaller batches
- Keep your library on a local SSD rather than a network drive
- If Chronoframe feels sluggish instead, lower **Files at Once** and close other apps

---

## Dates & Organization

**Q: How does Chronoframe figure out photo dates?**

A: It checks in this order:
1. Photo metadata (EXIF capture time)
2. Filename patterns (e.g., `2024-01-15_photo.jpg`)
3. File creation date (from the filesystem)
4. File modification date (fallback)
5. **Your override** (if you edit it in Review)

Each source gets a confidence level (high, medium, low, unknown). Photos with unknown dates go to `Unknown_Date/` unless you provide an override.

**Q: Why did a photo taken near midnight land in a different date folder than I expected?**

A: When a photo's EXIF metadata includes a timezone offset, Chronoframe files it by the photographer's **local calendar day** at capture time, not the UTC day. A shot at 11 PM in a UTC-5 timezone stays on that local date even though its UTC instant has already rolled into the next day. Photos without an offset-tagged timestamp keep using the source's own day boundary as before. This only affects which date folder a file lands in — sorting and duplicate detection still use the exact capture instant.

**Q: Can I edit dates before organizing?**

A: Yes. In the **Review** tab on the **Preview & Copy** screen, change an item's date with its date picker and click **Save**. Chronoframe saves your correction; click **Rebuild Preview** to see the plan with your changes.

**Q: What does "Low Confidence Date" mean?**

A: It means Chronoframe isn't sure about the date—maybe the filename looks like a date but doesn't match metadata, or it's relying on filesystem dates. You can accept it or override it in Review.

**Q: Can I use custom event names?**

A: If your folder layout is `YYYY/Mon/Event`, Chronoframe suggests event names based on proximity and source folder names. You can accept suggestions in Review, or manually edit them.

---

## Features & Capabilities

**Q: What formats does Chronoframe support?**

A: Photos (JPG, PNG, HEIF, RAW, etc.) and videos (MP4, MOV, etc.). If your OS can read it, Chronoframe can organize it.

**Q: Can I organize several folders at once?**

A: Yes. **Add Folders…** in **Organize → Choose Folders** accepts several folders. See [Organizing several folders at once](./QUICK_START.md#organizing-several-folders-at-once) for the overlap rules.

**Q: What happens after a copy finishes?**

A: The **Preview & Copy** screen shows **Copy complete**, and the report and undo receipt are in **History**. See [What happens after a copy](./QUICK_START.md#what-happens-after-a-copy).

**Q: Can Chronoframe find duplicate photos?**

A: Yes. Use the **Deduplicate** workspace:
- Finds **exact photo and video copies** using content hashing (BLAKE2b)
- Finds **similar photos** using on-device Vision analysis
- Optionally finds **visually similar video transcodes and re-exports** using sampled frames
- Detects **burst groups** using capture-time proximity
- Recognizes **RAW+JPEG pairs** and **Live Photo pairs**

Visual video matching is off by default. Enable it in **Settings → Deduplicate** with the Balanced or Similar Shots preset. These groups are always review-only and never accepted automatically.

**Q: Can I deduplicate a folder on my NAS?**

A: No, not for now. Deduplicate moves files to the macOS Trash, and Chronoframe has not verified that files moved to the Trash from a network share can be put back, so it refuses any folder that isn't on this Mac or an attached drive. Nothing is changed. NAS Library, which only reads your library, isn't available in release builds yet. See [Troubleshooting](./TROUBLESHOOTING.md#choose-a-folder-on-this-mac-or-an-attached-drive).

**Q: Can I organize into a folder on my NAS?**

A: Only when the share supports a rename that refuses to replace an existing file. Chronoframe checks this before it plans anything and stops if the share can't guarantee it. Nothing is copied, and your originals are untouched. Many SMB shares, including the Synology share tested, do not support it. Copying from a share to a folder on this Mac is not affected. See [Troubleshooting](./TROUBLESHOOTING.md#nas-and-network-folder-issues).

**Q: What if a file changes after a deduplicate scan?**

A: Chronoframe's commit summary and executor use the same immutable plan with the expected content identity for every target. Before Trash, the app quarantines and verifies each mutation unit without following symlinks. If a file, pair partner, or owned sidecar no longer matches, Chronoframe leaves or restores the unit and reports it as stale instead of deleting it.

**Q: What happens if Deduplicate is interrupted while moving files to Trash?**

A: Deduplicate writes a pending receipt and append-only recovery journal before and during the commit. On relaunch, Chronoframe checks the original path, quarantine path, and recorded Trash candidates by content. It restores or finalizes only when the evidence is unambiguous; otherwise History preserves the record and asks for a drive or manual action.

**Q: I quit halfway through reviewing duplicates. Is my work gone?**

A: No. Chronoframe saves your Keep and Delete choices and the groups you marked as reviewed on this Mac, outside your photo folder. Scan the same folder again and your review comes back: any scan of that folder restores it, so **Scan and Restore Review** on the "Pick up where you left off" card and the normal **Start Scan** do the same thing. A choice returns only for files that haven't changed. A changed file loses its choice, its group needs another look, and the "Your earlier review was restored." banner tells you how many. Groups you had reviewed stay reviewed, and nothing moves to the Trash until you prepare the commit and confirm. To start fresh, choose **Discard Saved Review** before you scan. Your photos aren't touched either way.

**Q: Can I organize into a folder that already has photos?**

A: Yes. Chronoframe detects existing files and won't overwrite them. If a destination collision happens, it gives the new file a distinct name (e.g., `photo_2.jpg`).

**Q: Does Chronoframe work with cloud drives (iCloud, Google Photos, OneDrive)?**

A: Yes, but **slowly**. Cloud drives aren't optimized for the file operations Chronoframe does. Use local or external drives for best performance.

**Q: Can I import from my Apple Photos library?**

A: Yes. Open the **Photos** tab, grant read access, pick photos and videos, and choose **Review & Import**. Chronoframe copies the originals into your organized library through the same preview → confirm → verified-copy flow as everything else. It only ever *reads* your Photos library — it never changes, moves, favorites, or deletes anything there. Live Photos keep their photo and movie together, and iCloud-only originals are downloaded on demand. Imports land in your active organize destination, so set that up first.

**Q: Will importing from Photos change or remove anything in my Photos library?**

A: No. The Photos import is strictly one-directional and read-only. Chronoframe never writes back to your Photos library — it only exports copies out of it.

**Q: Does importing from Photos keep my edits?**

A: No. By default, Chronoframe imports the original photo or video, so edits made in Photos, such as crops and filters, are not included. Your Photos library is never changed, and the edited version stays in Photos.

**Q: The import stopped, or the drive is almost full. Do I have to start over?**

A: No. Chronoframe keeps every item that finished preparing, and **Resume Import** carries on with the rest. See [Troubleshooting](./TROUBLESHOOTING.md#photos-import-issues).

---

## Common Issues

**Q: Chronoframe is asking for permission to access a folder. Why?**

A: macOS requires apps to ask permission before reading folders outside your home directory (like external drives). Click **Allow** and choose the folder.

**Q: The app says "Permission Denied" for some files.**

A: Chronoframe can't read every file in your folders, for example when a file is locked or another app is using it. See [Troubleshooting](./TROUBLESHOOTING.md#permission-denied-for-some-files).

**Q: Deduplicate didn't find duplicates I know exist.**

A: Exact matching uses content hashing, so two files match only if their bytes are identical. Files that were recompressed or re-exported need the **Balanced** or **Similar shots** **Detection** preset. See [Troubleshooting](./TROUBLESHOOTING.md#deduplicate-didnt-find-duplicates).

**Q: Can I organize into one of the folders I am organizing?**

A: Not recommended. It's confusing and risky. Always use a different destination folder. Chronoframe refuses a destination that is the same as a folder you are organizing or sits inside or around one; see [Organizing several folders at once](./QUICK_START.md#organizing-several-folders-at-once).

---

## Advanced

**Q: Can I use Chronoframe from the command line?**

A: Yes. Use the SwiftPM CLI executable:

```bash
# Preview only
swift run --package-path ui ChronoframeCLI --source ~/Photos/Unsorted --dest ~/Photos/Organized --dry-run

# Copy files
swift run --package-path ui ChronoframeCLI --source ~/Photos/Unsorted --dest ~/Photos/Organized

# Revert
swift run --package-path ui ChronoframeCLI --revert ~/Photos/Organized/.organize_logs/audit_receipt_*.json
```

See the [Technical Documentation](./TECHNICAL.md#command-line) for all flags.

**Q: Can I automate repeated runs?**

A: Yes. Save a **Profile** in **Settings → Profiles** with a folder and a destination, then switch between saved pairs with one click. A profile holds one folder. The Swift CLI can load the same profiles with `--profile NAME`.

**Q: Where does Chronoframe store its data?**

A: Inside your destination folder: `.organize_cache.db` (metadata cache, review edits, dedupe cache), `.organize_logs/` (receipts, recovery journals, reports) and `.organize_log.txt`. Keep them while an operation is active or History shows interrupted work; removing them can discard resume, recovery, history, or undo evidence.

---

**Still have questions?** Check the [README](../README.md), [Safety and Recovery](./SAFETY_AND_RECOVERY.md), [Troubleshooting](./TROUBLESHOOTING.md), or [Technical Documentation](./TECHNICAL.md).
