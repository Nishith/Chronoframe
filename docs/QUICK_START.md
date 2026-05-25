# Chronoframe Quick Start

Get your photos organized in 5 minutes.

## Installation

1. Download `Chronoframe.zip` from [Releases](https://github.com/Nishith/Chronoframe/releases)
2. Unzip and drag `Chronoframe.app` to Applications
3. Open the app (macOS 13+)

If macOS blocks the app, right-click it and choose **Open**.

## Organize Photos

Use this when you want Chronoframe to copy messy folders into a cleaner date-based library.

### Step 1: Choose Folders

1. Open **Organize → Setup**
2. Click **Choose Source…** and choose your messy photo folder
3. Click **Choose Destination…** and choose where organized photos should go
4. Chronoframe organizes into `YYYY/MM/DD` by default. To use year/month or `YYYY/Mon/Event` folders instead, change the layout in **Settings → Layout**.

### Step 2: Preview Your Plan

5. Click **Preview Plan**
   - Chronoframe scans the source, resolves dates, and builds a transfer plan — nothing is copied yet
   - This takes 10–60 seconds depending on your library size
6. When it finishes, the **Run** tab shows the plan: a timeline of your library plus counts for what's ready, already there, duplicates, and issues

### Step 3: Review (Optional)

7. In the **Review** tab, you'll see:
   - **Ready**: Photos ready to copy
   - **Unknown Dates**: Photos Chronoframe isn't sure about
   - **Duplicates**: Files that appear in both source and destination
   - **Issues**: Permission errors or read failures

8. For uncertain items, you can edit the date or event right in Review
9. Click **Rebuild Preview** after any edits

### Step 4: Transfer

10. Review the plan one more time
11. Click **Start Transfer**
    - Files are copied to destination, written safely, and verified
    - You'll see live progress and a summary when done

### Step 5: Keep Your Originals Safe

12. **Your source folder stays untouched.** Nothing is deleted or modified.
13. You can review the transfer report under **History**
14. If something went wrong, use **History** → **Revert** to undo the transfer

That's it. Your photos are now organized.

## Deduplicate Photos

Use this when you want Chronoframe to find exact copies and similar shots so you can choose what to keep.

1. Open **Deduplicate**
2. Click **Choose Folder…** to pick the folder to scan, or reuse a recent one
3. Pick a **Detection** preset (Strict, Balanced, or Loose) and click **Start Scan**
4. Review each group — compare candidates side by side and choose what to keep
5. Use **Auto-Accept Safe** to clear the obvious exact copies, then click **Move to Trash** to remove the files you approved

Chronoframe does not permanently delete files from Deduplicate. It sends selected files to the macOS Trash.

## Tips

- **Trust the preview.** It shows exactly what will copy before anything happens.
- **Edit uncertain dates.** If a photo has an unknown date, fix it in Review and Chronoframe will use your correction.
- **Review duplicate groups carefully.** Exact copies are straightforward, but similar shots still need your judgment.
- **Don't delete the source yet.** Keep it for a few days to make sure everything looks right.
- **Keyboard shortcuts** (once you're comfortable):
  - `Cmd+R` to preview
  - `Cmd+Return` to transfer
  - `Cmd+,` for Settings, `Cmd+?` for Help

## Need Help?

- **First run taking too long?** Large libraries (50K+ files) can take 5–10 minutes to scan. That's normal.
- **Unsure about a photo?** You can look at it in Review before transfer.
- **Want to see what will happen without copying?** Preview Plan is already a non-destructive dry run — it never copies anything until you click Start Transfer.
- **Questions?** See [Troubleshooting](./TROUBLESHOOTING.md) or check the full [README](../README.md).

---

**Remember:** Your originals are always safe. Chronoframe only copies, never deletes your source folder.
