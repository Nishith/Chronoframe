# NAS Photo Organizer v3

A high-performance Python script designed specifically to organize thousands of messy, ungrouped media files directly on Network Attached Storage (NAS) drives into an elegant `YYYY/MM/DD` folder structure.

## Features
- **Zero Data Loss Rule**: Operations safely duplicate and merge logic. It *never* deletes source media.
- **Deduplication Engine**: Automatically skips media already indexed in the destination and sequesters internal source duplicates directly to a `Duplicate/` bucket to avoid polluting the timeline.
- **Multithreaded I/O**: Eliminates painful network delay latencies during analysis by leveraging `concurrent.futures`.
- **SQLite Database Cache**: Preserves indexes and file hashes identically across runs without memory bloating.
- **EXIF Native Parsing**: Supports `exifread` to extract raw EXIF data, guaranteeing correct photo date associations bypassing Spotlight logic.

## Usage
Simply invoke the script with python:
```bash
python3 organize_nas.py --source /Volumes/NAS/Unsorted --dest /Volumes/NAS/Organized
```

### CLI Arguments
* `--dry-run`: Previews the copy plan and flags any sequence duplicate risks entirely without writing any actual copies.
* `--yes` or `-y`: Auto-confirm copy execution cleanly for automated tasks.
* `--verify`: Cross-references hash bytes again after the copy writes to disk.
* `--rebuild-cache`: Flushes the SQLite state manually to force a pristine re-index.

### Date Rules
Date mapping cascades gracefully depending on available metadata:
1. Native EXIF Data (if `pip install exifread` is accessible)
2. Filename text pattern matches (e.g. `IMG_20240101_XXX`)
3. macOS Spotlight `mdls` API
4. OS `mtime` modification date

Unknown media resolves cleanly into an `Unknown_Date/` bin for manual review.

## Tests
A comprehensive test suite runs through SQLite instantiation logic and EXIF extraction fallbacks via:
```bash
python3 -m unittest test_organize_nas.py -v
```
