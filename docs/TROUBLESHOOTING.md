# Troubleshooting Guide

## Installation & Launch

### macOS blocks the app on first launch

**Problem:** You see "Chronoframe cannot be opened because the developer cannot be verified."

**Solution:**
1. Right-click `Chronoframe.app` in Applications
2. Choose **Open**
3. Click **Open** in the confirmation dialog

This is a one-time check.

### App crashes on launch

**Problem:** The app opens briefly then closes.

**Solution:**
1. Make sure you're on **macOS 14 or later** (`About This Mac` → System Report)
2. Try removing and reinstalling the app
3. Check the system logs for crash details (`Console.app` → `Chronoframe`)

If the issue persists, [report it on GitHub](https://github.com/Nishith/Chronoframe/issues).

### Permission denied when launching

**Problem:** "Chronoframe does not have permission to run."

**Solution:**
1. Open **System Preferences** → **Security & Privacy** → **General**
2. If you see "Chronoframe was blocked," click **Allow**
3. Relaunch the app

---

## Preview Issues

### History asks to reconnect an archive folder

Chronoframe could not access the selected archive. This does not mean its media or receipts were deleted.

1. Connect and unlock the drive if the archive is on an external disk.
2. In **Organize → History**, click **Choose Folder…** under **Reconnect your archive folder**.
3. Select the same archive folder shown in the message. Chronoframe saves refreshed access and reloads History automatically.

Choosing a different folder leaves the current archive unchanged and explains which folder to select. Previously loaded entries remain visible but unavailable until access returns. You do not need to rerun a transfer, reset settings or grant Full Disk Access. Keep `.organize_logs/` and its receipts intact.

### Preview is taking too long

**Problem:** The preview has been running for 10+ minutes.

**Solution:**
- **Large libraries** (50K+ files) naturally take longer. Give it time (5–15 min is normal).
- Check the **Console** tab in the Run workspace to see progress.
- If it's frozen (no progress for several minutes), force-quit and try again.
- **To speed up future previews:**
  - Open **Settings → Performance** and raise the worker-thread count (the presets only switch parallel copying and reset workers to 8, so they don't speed up a preview)
  - Filter your source folder to smaller batches
  - Keep your library on a local SSD rather than a network drive

### Preview failed with a read error

**Problem:** Preview shows errors for some files.

**Solution:**
- Those files are likely corrupted or locked by another app
- In Review, scroll to **Errors** to see which files failed
- You have three options:
  1. Leave it skipped and inspect it with another media app
  2. Make a separate backup, then move it out of the selected source yourself if you do not want it included
  3. Check if the file is locked (right-click → Get Info → Locked) and unlock it

### Preview shows "Unknown Date" for many files

**Problem:** Many photos are routing to `Unknown_Date/` folder.

**Solution:**
- Click the **Unknown Dates** filter in Review to see them
- For each item, you can:
  1. **Edit the date** directly in Review (your edit is saved)
  2. **Check the source filename** for date patterns
  3. **Accept Unknown** if you're okay with putting it in `Unknown_Date/`
- Rebuild Preview after edits (button is at top of Review tab)

---

## Transfer Issues

### Transfer failed partway through

**Problem:** Transfer stopped with errors.

**Solution:**
- Check the **Console** tab in the Run workspace to see what went wrong
- **Permission errors?** Check that you have write access to destination folder
- **Disk full?** Free up space and try again
- **File locked?** Close other apps using destination files and retry
- **Network drive slow?** Transfer to a local drive instead

You can safely retry the transfer—Chronoframe will skip files already in destination and copy the rest.

If the app or Mac stopped unexpectedly, reconnect the destination drive before reopening Chronoframe. The app reconciles recorded copy state on launch. Check **History** for the recovered or pending run before removing `.organize_cache.db` or anything in `.organize_logs/`.

### "Another Chronoframe operation is already using this destination"

**Problem:** A preview, transfer, deduplicate commit, revert, reorganize run, CLI command, or system action refuses to start.

**Solution:**
- Let the active Chronoframe operation finish, then try again
- Check other Chronoframe windows and Terminal sessions using `ChronoframeCLI`
- If another Mac is writing to the same network destination, stop that run first
- Do not delete `.chronoframe-operation.lock` to force progress; the live operating-system lock, not the file's text, controls ownership
- If no operation is running after a crash, reopen Chronoframe normally—the operating system releases abandoned locks automatically

### Destination folder has permission issues

**Problem:** "Permission denied" when trying to write to destination.

**Solution:**
1. Open Finder, right-click the destination folder
2. Click **Get Info** → **Sharing & Permissions**
3. Make sure your user account has **Read & Write** access
4. Close the info window and try again in Chronoframe

### Transfer completed but some files are missing

**Problem:** Fewer files copied than expected.

**Solution:**
- Check the **History** tab → transfer report to see what was skipped
- Common reasons:
  - **Already in destination** — file was found in destination before copy
  - **Duplicate** — exact copy already exists in destination
  - **Error** — file couldn't be read (corrupted or locked)
- Review the detailed report to see which files were affected

### Revert failed or left files behind

**Problem:** Revert didn't undo the transfer completely.

**Solution:**
- Revert is **hash-verified** — it only deletes files whose content still matches what was copied
- If a file has been modified or deleted since transfer, revert won't touch it
- Check **History** to see which files were reverted
- You can manually delete the remaining files if needed

---

## Deduplicate Issues

### Deduplicate didn't find duplicates

**Problem:** You know there are duplicate photos, but Deduplicate found none.

**Solution:**
- Chronoframe uses **content hashing**, not filename matching
- Two files are duplicates only if their **bytes are identical**
- If duplicates have different:
  - Compression settings (JPEG quality)
  - Metadata (photographer name, date, etc.)
  - Format (one JPG, one PNG of the same image)
  - …they won't match
- **Try adjusting detection:**
  1. On the Deduplicate setup screen, switch the **Detection** preset from **Balanced** to **Loose** (more options live in **Settings → Deduplicate**)
  2. Start a new scan

### Similarity detection isn't working

**Problem:** "Similar Photos" mode found nothing or very few.

**Solution:**
- First scan creates a cache. **Second scans are much faster.**
- Make sure you have a GPU (Apple Silicon or Intel with dedicated GPU recommended)
- Adjust the similarity preset:
  1. Open **Settings → Deduplicate** (or use the Detection presets on the setup screen)
  2. Try **Balanced** or **Loose** for more matches (but more false positives)

### "Move to Trash" button is grayed out

**Problem:** You can't apply your deduplicate choices.

**Solution:**
- Make sure you've **selected keep/delete choices** for at least one group
- Click a group on the left and choose which items to keep and which to delete (or use **Auto-Accept Safe** for the obvious exact copies)
- The **Move to Trash** button activates once at least one file is marked for removal

### Deduplicate says a file changed after the scan

**Problem:** A planned file, pair, or sidecar was skipped as stale when you clicked **Move to Trash**.

**Solution:**
- Chronoframe intentionally stops that mutation because the live content no longer matches the reviewed plan
- Close any editor, sync client, or metadata tool changing the folder
- Start a new Deduplicate scan and review the updated group
- Do not rename quarantine-looking files manually; if a commit was interrupted, reopen Chronoframe and let recovery reconcile them

### History shows an interrupted recovery badge

**Problem:** A run shows **Interrupted · Needs Drive**, **Trash Location Unverified**, or **Manual Recovery Needed**.

**Solution:**
- **Needs Drive:** reconnect and unlock the named external volume, then reopen Chronoframe or refresh History
- **Trash Location Unverified:** keep the receipt and journal in place; do not empty Trash until the state is resolved
- **Manual Recovery Needed:** preserve `.organize_cache.db`, `.organize_logs/`, and any reported path, then contact support with sanitized logs
- Never treat a permission prompt or disconnected drive as a missing file and clean up the evidence by hand

---

## NAS And Network Folder Issues

The NAS Library workspace isn't available in release builds yet. The copy rules, copy-records check, and command-line refusal below apply to every network destination now.

### "Waiting for your NAS"

**Message:** "Waiting for your NAS. Reconnect the share, then choose Reconnect. Nothing was changed."

**Problem:** NAS Library couldn't reach the saved folder, or the share disappeared during an assessment.

**Solution:**
- Reconnect the share in Finder (**Go** → **Connect to Server**), then choose **Reconnect**
- If **Reconnect** still can't find it, choose **Choose Folder…** and pick the same folder; Chronoframe keeps your saved choices when it recognizes the same library
- Assess again to finish an interrupted scan; files that haven't changed aren't re-read

### "Choose a folder on a network share"

**Message:** "Choose a folder on a network share. For folders on this Mac, use Deduplicate."

**Problem:** NAS Library only accepts folders on a network share. A folder on this Mac, or on a volume macOS can't identify, is refused and nothing is saved.

**Solution:** Pick the top folder of your collection on the mounted share. Use **Deduplicate** for folders on this Mac.

### "...can't guarantee that a copy never replaces an existing file"

**Message:** "This network folder can't guarantee that a copy never replaces an existing file, so Chronoframe stopped before placing it: *path*. Your originals were untouched."

**Problem:** The share doesn't support the no-replace rename Chronoframe requires for network destinations. Chronoframe stops the run instead of using a weaker method.

**Solution:**
- Copy to a folder on a local drive instead, or to a share whose server supports it
- Files already copied and verified stay in place; nothing was overwritten
- Running again against the same share will stop the same way

### "This network folder can't guarantee that a copy never replaces an existing file, so Chronoframe won't organize into it"

**Message:** "This network folder can't guarantee that a copy never replaces an existing file, so Chronoframe won't organize into it. Choose a folder on this Mac or an attached drive. Nothing was copied, and your originals were untouched."

**Problem:** Before it plans a preview or a transfer into a network folder, Chronoframe checks that the share supports a rename that refuses to replace an existing file. This share doesn't, so Chronoframe stops before scanning or copying instead of using a weaker method. Many SMB shares, including the Synology share tested, don't support it.

**Solution:**
- Choose a destination folder on this Mac or an attached drive
- Copying from the share to a folder on this Mac is not affected
- Choosing the same network folder again will stop the same way; Chronoframe checks again each time, so a different share or server setup is picked up

### "The network folder ... disconnected or changed"

**Message:** "The network folder at *mount point* disconnected or changed, so Chronoframe stopped before the next copy. Your originals were untouched."

**Problem:** The share was unmounted, or a different volume is now at the destination path, partway through a copy run.

**Solution:** Reconnect the share, then run the transfer again. Chronoframe resumes from its recorded queue and skips files already copied.

### "...copy records on this network folder"

**Message:** "Chronoframe couldn't open its copy records on this network folder safely, so it didn't copy anything. Another app or Chronoframe window may be using them. Your originals were untouched."

**Problem:** Chronoframe keeps its copy records (`.organize_cache.db`) in the destination. On a network folder it must switch them to a rollback journal and confirm the switch, and that failed.

**Solution:**
- Close other Chronoframe windows, Terminal sessions, and any other app or Mac that may have the destination's `.organize_cache.db` open
- Try again
- Don't delete `.organize_cache.db` or its `-wal`, `-shm`, or `-journal` files to force it

### "Choose a folder on this Mac or an attached drive"

**Message:** "Choose a folder on this Mac or an attached drive. Deduplicate can't move files on a network share to the Trash safely yet, so nothing was changed." Builds where NAS Library is available add: "For a NAS, use NAS Library."

**Problem:** Deduplicate moves files to the macOS Trash, and Chronoframe has not verified that Trash on a network share can put files back. It refuses any folder that isn't on this Mac or an attached drive, including a folder on a volume macOS can't identify, before it scans or changes anything.

**Solution:**
- Pick a folder on this Mac or on an attached drive
- To look for duplicates on a NAS, use NAS Library where it is available; it only reads your library and changes nothing on the NAS

### Command-line tool says it can't write to a network folder

**Message:** "Chronoframe's command-line tool can't write to a network folder in this version: *path*. Use the Chronoframe app for NAS destinations. Nothing was changed."

**Problem:** `ChronoframeCLI` refuses network destinations before it scans, locks, or writes anything. This includes a named `--profile` whose destination is on a network share, even if `--dest` is local, and `--revert` for a receipt in a network destination. It exits with code 2.

**Solution:** Run the organize or revert from the Chronoframe app. Using a NAS as the **source** with a local destination still works in the command line.

---

## Performance

### App is slow or unresponsive

**Problem:** Chronoframe is sluggish, especially with large libraries.

**Solution:**
1. **Reduce worker threads** — sometimes more isn't better
   - **Settings** → **Performance** → reduce worker count
2. **Close other apps** to free up memory
3. **Use a faster drive** — local SSDs are much faster than network drives
4. **Reduce preview scope** — organize smaller batches at a time

### Hashing is slow

**Problem:** Preview is waiting on "Hashing files..." step.

**Solution:**
- BLAKE2b hashing can be slow on large files (videos, RAW photos)
- This is normal for libraries with 100K+ files
- You can't skip hashing (it's how Chronoframe finds duplicates safely)
- Performance improves on subsequent previews thanks to caching

---

## File Access

### "Permission denied" for some files

**Problem:** Chronoframe can't read certain files in source.

**Solution:**
- The file might be **locked** by another app or macOS
- Check if the file is **Locked** (right-click → Get Info → Locked checkbox)
- Unlock it and try again
- Or simply skip those files (Chronoframe skips read errors gracefully)

### Can't select source or destination folder

**Problem:** The folder picker is disabled or doesn't open.

**Solution:**
1. Re-select the folder with Chronoframe's standard folder picker
2. Check **System Settings → Privacy & Security → Files and Folders** if macOS previously denied access
3. If the folder is on an external drive, make sure it's mounted and unlocked
4. Try closing and reopening the app

### External drive isn't showing up

**Problem:** Your external drive doesn't appear in the folder picker.

**Solution:**
- Make sure the drive is **mounted** in Finder
- Try unplugging and replugging the drive
- Check that the drive's file system is supported (macOS works with most formats)
- If the drive is encrypted, unlock it first

---

## Data & Privacy

### Where is my data stored?

**Answer:**
- Source data is **never stored** — Chronoframe reads and copies it
- Destination data is **your files** in the folder you selected
- Chronoframe metadata is in `.organize_cache.db`, `.organize_logs/`, and `.organize_log.txt` inside your destination folder
- Keep those files while a run is active, resumable, interrupted, or still needed for History/Revert
- If all work is complete and you intentionally accept losing history and recovery evidence, Chronoframe can rebuild performance caches later

### How can I delete Chronoframe?

**Answer:**
1. **Quit the app** (Cmd+Q)
2. Open Finder → Applications
3. Right-click **Chronoframe** → Move to Trash
4. Empty Trash

That's it—Chronoframe doesn't install anything system-wide.

---

## Still Stuck?

If your issue isn't covered here:
1. Check the [FAQ](./FAQ.md) for general questions
2. Review the [Technical Documentation](./TECHNICAL.md) for command-line and architecture details
3. Read [Safety and Recovery](./SAFETY_AND_RECOVERY.md) before manually changing interrupted-run artifacts
4. Check the [Releases page](https://github.com/Nishith/Chronoframe/releases) for known issues
5. [Open a GitHub issue](https://github.com/Nishith/Chronoframe/issues) with details about what's happening

**When reporting a bug, include:**
- Your macOS version and hardware (Intel vs. Apple Silicon)
- The error message or steps to reproduce
- The **Console** tab in the Run workspace, or relevant `.organize_logs/` files
