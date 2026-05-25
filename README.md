# Chronoframe

[![Release](https://img.shields.io/github/v/release/Nishith/Chronoframe?label=release)](https://github.com/Nishith/Chronoframe/releases/latest)
[![License](https://img.shields.io/badge/license-source--visible-lightgrey)](LICENSE)

**Organize messy photo folders without changing your source files, then clean up duplicates safely through Trash.**

Chronoframe is a macOS app for people with years of photos and videos spread across phones, camera cards, old laptops, external drives, and backup folders. It helps you build a cleaner library in two practical ways:

- **Organize** copies scattered media into a date-based folder structure.
- **Deduplicate** finds exact copies and similar shots so you can choose what to keep.

Chronoframe always shows you a plan before it changes anything. Your source folder is read-only, transfers can be reviewed before copying, and dedupe choices move files to the macOS Trash instead of permanently deleting them.

![Chronoframe Setup — choose a source and destination, with a contact sheet of the frames it will organize.](docs/screenshots/setup.jpg)

## What You Can Do

| Need | Use Chronoframe to |
| :--- | :--- |
| Make sense of a messy folder | Copy photos and videos into folders like `2024/06/15` |
| Combine old backups | Skip files that are already in the destination |
| Fix uncertain dates | Review unknown or low-confidence dates before copying |
| Keep an eye on the library | Run a Health check for unknown dates, duplicates, and interrupted work |
| Clean up duplicate files | Find exact copies by content, not filename |
| Compare similar shots | Review near-duplicates, bursts, RAW+JPEG pairs, and Live Photos |
| Undo a transfer | Revert copied files from History when their contents still match the receipt |

## Safety First

- **Originals stay untouched.** Chronoframe reads the source folder but does not move, rename, edit, or delete source files.
- **You approve the plan.** Organize shows what will copy before transfer. Deduplicate shows what will move to Trash before commit.
- **No overwrites.** If a destination filename already exists, Chronoframe creates a distinct name.
- **Copies are checked.** Transfers are written safely and verified by default.
- **Trash, not hard delete.** Deduplicate sends selected files to the macOS Trash.
- **Receipts are kept.** History records what happened so you can inspect or revert supported runs.

## Install

Chronoframe is being prepared for Mac App Store distribution. Until that release is live:

1. Download `Chronoframe.zip` from the [Releases page](https://github.com/Nishith/Chronoframe/releases).
2. Unzip it.
3. Drag `Chronoframe.app` to Applications.
4. Open the app.

Chronoframe requires **macOS 13.0 or later** and enough free space for the organized copy of your library.

If macOS blocks the app on first launch, right-click `Chronoframe.app`, choose **Open**, then confirm.

## Organize Photos

Organize is a four-step workspace — **Setup**, **Run**, **Health**, and **History** — that you move through left to right.

1. Open **Organize → Setup**.
2. Click **Choose Source…** and pick the folder with your unsorted photos and videos.
3. Click **Choose Destination…** and pick where organized copies should go.
4. Click **Preview Plan**. Chronoframe scans the source, resolves dates, and builds a transfer plan — nothing is copied yet.

![Preview Ready for Review — a timeline of the library by month, with discovered, planned, and issue counts.](docs/screenshots/preview-timeline.jpg)

5. On the **Run** tab, inspect the preview: the timeline shows your library by month, and the counts cover what's ready, what's already there, duplicates, and anything that needs attention. Open **Review** to fix uncertain dates.
6. Click **Start Transfer** when the preview looks right. Chronoframe copies files into the destination, verifies them, and writes a receipt — your source is never touched.

![Transfer Complete — every frame copied, with a run summary and links to open the destination, report, and logs.](docs/screenshots/transfer-complete.jpg)

### Check your library's health

The **Health** tab scans the destination on demand and surfaces cleanup opportunities — unknown dates, duplicates, interrupted work, structure drift, and revert safety — with a one-glance health score and shortcuts to act on each.

![Library Health — a health score with cards for unknown dates, duplicates, interrupted work, and structure drift.](docs/screenshots/library-health.jpg)

### Review and undo from History

The **History** tab keeps every run's reports and receipts. Reuse a past source, inspect logs, or open the **Undo Center** to revert a transfer when its files still match the receipt.

![Run History — archived frames, reusable sources, an undo center, and a list of run reports and receipts.](docs/screenshots/run-history.jpg)

## Deduplicate Photos

1. Open **Deduplicate**.
2. Click **Choose Folder…** to pick the folder to scan, or reuse a recent one. Pick a **Detection** preset (Strict, Balanced, or Loose) and click **Start Scan**.

![Deduplicate setup — a scan folder, recent folders with files removed and space saved, and detection presets.](docs/screenshots/dedupe-setup.jpg)

3. Review each group. Compare candidates side by side, choose what to **Keep**, and use **Accept & Next** to move through them. **Auto-Accept Safe** clears the obvious exact copies for you.
4. Click **Move to Trash** to send the files you approved to the macOS Trash.

![Deduplicate review — two similar photos compared side by side, with keep and delete choices.](docs/screenshots/dedupe-compare.jpg)

Exact duplicates can be accepted automatically. Similar photos, bursts, RAW+JPEG pairs, and Live Photo pairs stay reviewable so you can make the final call.

## Helpful Guides

- [Quick Start](docs/QUICK_START.md) for a short walkthrough.
- [FAQ](docs/FAQ.md) for common questions.
- [Troubleshooting](docs/TROUBLESHOOTING.md) for installation, permission, preview, transfer, and dedupe issues.
- [Technical Documentation](docs/TECHNICAL.md) for command-line use, architecture, generated files, build commands, and developer notes.

## Command Line

Developers can run the Swift CLI through SwiftPM:

```bash
swift run --package-path ui ChronoframeCLI --source ~/Photos/Unsorted --dest ~/Photos/Organized --dry-run
```

## Privacy

Chronoframe works on folders you choose on your Mac. It does not upload your photo library. Its cache, reports, and receipts are stored inside the destination folder so you can inspect or remove them when you no longer need them.

See the [privacy policy](docs/PRIVACY_POLICY.md) and [Mac App Store release checklist](docs/APP_STORE_RELEASE.md) for release-readiness details.
