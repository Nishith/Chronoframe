# Chronoframe Quick Start

Get your photos organized in 5 minutes.

## Installation

1. [Download Chronoframe from the Mac App Store](https://apps.apple.com/us/app/chronoframe/id6771245052?mt=12)
2. Open the app on macOS 14 or later

## Organize Photos

Use this when you want Chronoframe to copy messy folders into a cleaner date-based library.

### Step 1: Choose Folders

1. Open **Organize → Choose Folders**
2. Click **Add Folders…** and choose the folders that hold your photos. You can pick more than one — see [Organizing several folders at once](#organizing-several-folders-at-once)
3. Click **Choose Destination…** and choose where organized photos should go
4. Chronoframe organizes into **Year / Month / Day** folders (`YYYY/MM/DD`) by default. To use **Year / Month**, **Year**, **Year / Month / Event** or **One folder** instead, change the **Folder layout** menu under the destination, or change it in **Settings → Layout**.

### Step 2: Preview Your Plan

5. Click **Preview Plan**
   - Chronoframe scans your folders, resolves dates, and builds a plan — nothing is copied yet
   - This takes 10–60 seconds depending on your library size
6. When it finishes, **Preview & Copy** shows the plan: a headline saying how many photos and videos will be copied, a **What will happen** card that lists anything unusual, a timeline of your library, and counts for what was found, what will be copied, what is already there, exact copies, and problems

### Step 3: Review (Optional)

7. In the **Review** tab, pick a filter to see:
   - **Needs Attention**: Photos with no date, a date Chronoframe is unsure about, or a file it could not read
   - **Unknown Date**: Photos with no date, which go to the `Unknown_Date` folder unless you set one
   - **Low Confidence**: Photos with a date Chronoframe is unsure about
   - **Duplicates**: Exact copies of another file, set aside in the `Duplicate` folder
   - **Skipped**: Files that are already in your organized library
   - **Ready**: Photos ready to copy

8. For uncertain items, you can edit the date or event right in Review and click **Save**
9. Click **Rebuild Preview** after any edits

### Step 4: Copy

10. Review the plan one more time
11. Click **Start Copying** on the **Preview & Copy** screen (or choose **Start Copying** from the **Organize** menu), then confirm in the **Start copying?** prompt
    - Files are copied to destination, written safely, and verified
    - You'll see live progress and a summary when done
    - If another Chronoframe window, CLI run, or system action is already changing this destination, wait for it to finish and try again

### Step 5: Keep Your Originals Safe

12. **Your original folders stay untouched.** Nothing is deleted or modified.
13. You can review the report and the receipt for each copy under **History**
14. If something went wrong, open **History** and click **Undo** next to the copy in the **Undo Center** to undo the copy
15. If a copy was interrupted, reopen Chronoframe with the destination drive connected. History will reconcile recorded work or show **Needs Drive** / **Manual Recovery Needed** when it cannot safely finish on its own.

That's it. Your photos are now organized.

## Organizing several folders at once

Use this when your photos are spread across more than one folder.

- **Build the list.** In **Organize → Choose Folders**, the **Folders to organize** list holds every folder you add. **Add Folders…** opens a folder picker where you can select several folders at once. You can also drag folders onto the Choose Folders window; dropped folders are added to the list, not swapped in for it.
- **Remove a folder.** Click the minus button on its row. Rows can't be removed while a preview or copy is running or while a saved profile is selected.
- **Folders inside folders.** Adding a folder that is already inside a listed folder is refused with a message, because the listed folder already covers it. Adding a folder that contains folders you already listed replaces those with the larger one. Adding the same folder twice does nothing.
- **Keep the destination apart.** A listed folder and the destination can't be the same folder, and neither may sit inside the other. Chronoframe refuses the folder when you add it, or the destination when you choose it, and the engine checks again before a preview or a copy.
- **The list is remembered.** Chronoframe restores your list when you reopen it. A folder it can no longer find is dropped from the list.
- **Profiles hold one folder.** A saved profile stores a single folder, so Chronoframe won't save a profile while two or more folders are listed. It keeps remembering the list instead.

## What happens after a copy

When a copy finishes, the **Preview & Copy** screen says **Copy complete** and how many photos and videos are now in your organized library. Your originals were not changed.

- **Receipt and undo.** The report and the receipt for undoing that copy are in **History**.
- **Next step.** If at least one file was copied, a **Next: remove extra copies** card appears directly under the **Copy complete** message. If the copy set aside exact copies, it says how many went to the `Duplicate` folder. Click **Find Duplicates** to open **Deduplicate**.
- **Find Duplicates only opens Deduplicate.** It doesn't start a scan or change the folder to scan; you choose that and click **Start Scan** yourself. Deduplicate removes nothing until you approve it, and approved files go to the macOS Trash.

## Deduplicate Photos and Videos

Use this when you want Chronoframe to find exact photo and video copies plus similar photos so you can choose what to keep.

1. Open **Deduplicate**
2. Click **Choose Folder…** to pick the folder to scan, or reuse a recent one
3. Pick a **Detection** preset (**Exact copies**, **Balanced**, or **Similar shots**) and click **Start Scan**
4. Review each group — compare candidates side by side and choose what to keep
5. Click **Accept All Safe** to accept every group Chronoframe marks as a safe match, then click **Move to Trash** to remove the files you approved

Chronoframe does not permanently delete files from Deduplicate. It sends selected files to the macOS Trash. Similar-photo, burst, RAW+JPEG, and Live Photo analysis applies to photos. Exact video copies are always detected, and an off-by-default setting can surface visually similar transcodes and re-exports for review; visual video matches are never auto-accepted.

The commit summary and executor use the same content-verified plan. If a planned file or pair changes after the scan, Chronoframe leaves it untouched and asks you to scan again.

## Tips

- **Trust the preview.** It shows exactly what will copy before anything happens.
- **Edit uncertain dates.** If a photo has an unknown date, fix it in Review and Chronoframe will use your correction.
- **Review duplicate groups carefully.** Exact copies are straightforward, but similar shots still need your judgment.
- **Keep destination support files during recovery.** Do not remove `.organize_cache.db` or `.organize_logs/` while a copy is active or History shows interrupted work.
- **Don't delete your originals yet.** Keep them for a few days to make sure everything looks right.
- **Keyboard shortcuts** (once you're comfortable):
  - `Cmd+R` to preview
  - `Cmd+Return` to start copying
  - `Cmd+,` for Settings, `Cmd+?` for Help

## Need Help?

- **First preview taking too long?** Large libraries (50K+ files) can take 5–10 minutes to scan. That's normal.
- **Unsure about a photo?** You can look at it in Review before copying.
- **Want to see what will happen without copying?** Preview Plan copies nothing — Chronoframe copies only after you click **Start Copying** and confirm.
- **Seeing “already using this destination”?** Another Chronoframe operation owns the destination. Let it finish; starting a second mutation is intentionally blocked.
- **Questions?** See [Troubleshooting](./TROUBLESHOOTING.md) or check the full [README](../README.md).

---

**Remember:** Your originals are always safe. Chronoframe only copies, never deletes your original folders.
