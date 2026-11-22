# Edit preservation — evidence ledger (owner rows)

Only Nishith records results here. Agents leave every row `todo-hardware`. Use a disposable destination folder, a throwaway Photos library or a handful of assets you can re-download, and copies of any real photos.

## Setup
```bash
ui/build.sh
mkdir -p "$HOME/epr-source" "$HOME/epr-dest"
```
Put in `epr-source`: `IMG_1234.HEIC` with `IMG_E1234.AAE`, `IMG_1234.AAE` and a `photo.jpg` with `photo.jpg.xmp`; plus `shared.dng` + `shared.jpg` with one `shared.xmp` (should be unresolved).

## Ledger
| ID | Check | Expected | Result | Date |
|---|---|---|---|---|
| H-EPR-1 | Deduplicate the pair `IMG_1234.HEIC`/copy in a folder with `.aae`; Delete the HEIC | The `.aae` is trashed with it only when every owner is deleted; an edited variant (`X-edited.JPG`) beside `X.HEIC` stays when `X.HEIC` is deleted | todo-hardware | |
| H-EPR-2 | Organize `epr-source` and read the preview | `photo.jpg.xmp`, `IMG_E1234.AAE` listed as copying with their photos; `shared.xmp` listed as `Not copied … matches more than one photo` | todo-hardware | |
| H-EPR-3 | Run, then Revert | Companions removed with their photos; destination matches its pre-run state; run again after Revert works | todo-hardware | |
| H-EPR-4 | Photos import of 5 assets (two edited: one cropped, one filtered; one edited video; one unedited) with *Include edited versions* on | Originals unchanged, two `-edited` stills added, video reported as not included, no change in Photos | todo-hardware | |
| H-EPR-5 | Stop mid-import, relaunch, Resume with the option on | Same option applies; no duplicate or orphaned `-edited` files | todo-hardware | |
| H-EPR-6 | Read the Photos import screen and the FAQ | Wording is plain and says edits are not included unless the option is on | todo-hardware | |
