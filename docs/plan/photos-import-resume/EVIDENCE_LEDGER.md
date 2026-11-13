# Photos import resume — evidence ledger (owner rows)

Only Nishith records results here. Agents leave every row `todo-hardware`. Use a disposable destination folder and a Photos library you can afford to re-download from iCloud.

## Setup
```bash
ui/build.sh
mkdir -p "$HOME/pir-staging"
```
For H-PIR-3 create a small disk image: `hdiutil create -size 3g -fs APFS -volname PIRSmall "$HOME/pir-small.dmg" && hdiutil attach "$HOME/pir-small.dmg"`.

## Ledger
| Row | What to run | Pass when | Status | Evidence |
|---|---|---|---|---|
| H-PIR-1 | `open --env CHRONOFRAME_PHOTOS_STAGING_DIR="$HOME/pir-staging" ui/build/Chronoframe.app`; select ≥ 30 iCloud-only assets; Review & Import; press Stop while "Downloading from iCloud…" shows | Panel showed counts and the iCloud line; status text matches C-06 "stopped" with counts; `ls "$HOME/pir-staging"/*/` shows only complete assets plus `.chronoframe_photos_checkpoint.json` | todo-hardware | screenshot path |
| H-PIR-2 | Continue from H-PIR-1: quit the app (⌘Q) during a second prepare; relaunch; Resume card appears; press Resume Import | Preview starts with every selected asset; `assetIDs` count equals the selection; no asset was re-downloaded (Console: no second write for completed IDs) | todo-hardware | screenshot path |
| H-PIR-3 | `open --env CHRONOFRAME_PHOTOS_STAGING_DIR=/Volumes/PIRSmall/staging ui/build/Chronoframe.app`; import > 3 GB of assets | Import pauses with the C-06 low-space text; freeing space and Resume completes it | todo-hardware | screenshot path |
| H-PIR-4 | With a resumable import, change the Organize destination; open Photos tab | Resume disabled with the mismatch text; choosing the original destination re-enables it | todo-hardware | screenshot path |
| H-PIR-5 | VoiceOver on; tab through the preparation panel and the Resume card | Every control and status line is read; Stop/Resume/Discard are named | todo-hardware | note |
| H-PIR-6 | G2 app smoke (not completed by the agent, B-1): `ui/build.sh && open -n --env CHRONOFRAME_PHOTOS_STAGING_DIR="$PWD/.tmp/pir-smoke/staging" ui/build/Chronoframe.app`; open the Photos tab | The Resume card shows "An import was interrupted." with "0 of 3 items" and Resume Import / Discard; Resume is disabled with the different-destination text unless the Organize destination is `.tmp/pir-smoke/destination`; save a screenshot to `docs/plan/photos-import-resume/evidence/resume-card.png` | todo-hardware | screenshot path |
