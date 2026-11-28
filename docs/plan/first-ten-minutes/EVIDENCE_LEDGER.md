# First ten minutes — evidence ledger (owner rows)

Status: not started (verified 2026-11-22 on main 8308aac: `git grep` finds no `RunPreflightAssessment`, `PreflightService`, `FirstRunTestBatch` or `RunProofModel` in `ui/`). No row is run.

| Row | What to run | Pass when | Status | Evidence |
|---|---|---|---|---|
| H-FTM-1 | Destination on a nearly full external drive; Preview a plan larger than the free space | Choose Folders checklist and the Preview & Copy row show the blocked wording with both numbers; Start Copying still works and pauses as before | todo-hardware | screenshot |
| H-FTM-2 | Unplug the source drive; relaunch | Choose Folders shows "Source Unavailable" with the reconnect detail; choosing the folder again clears it | todo-hardware | screenshot |
| H-FTM-3 | Clean container (new macOS user account): choose a 1,000-file source and an empty destination; Preview; press "Start with 25 files"; then Show in Finder; then Undo Batch | 25 copies verified; Finder selects the first file; Undo removes exactly 25 and the allowance indicator returns to 500 | todo-hardware | screenshots |
| H-FTM-4 | VoiceOver through checklist, batch button and proof card | Every status and button is read | todo-hardware | note |
