# Dedupe persistence — evidence ledger (owner rows)

Only Nishith records results. Use a copy of a real library in a disposable folder.

| Row | What to run | Pass when | Status | Evidence |
|---|---|---|---|---|
| H-DDP-1 | `ui/build.sh && open ui/build/Chronoframe.app`; Deduplicate a ≥ 5,000-photo folder; review ~10 minutes; ⌘Q; relaunch; Scan | Banner shows the same counts you made; the list opens on the group you were viewing | todo-hardware | screenshot |
| H-DDP-2 | Edit one reviewed file in Preview.app (rotate, save); Scan again | Banner reports 1 file changed and its group needs another look; that group has no restored approval | todo-hardware | screenshot |
| H-DDP-3 | Commit the reviewed groups | Trash receives exactly the planned files; `ls ~/Library/Application\ Support/Chronoframe/dedupe_reviews/` no longer has that folder's file | todo-hardware | ls output |
| H-DDP-4 | VoiceOver on; focus the banner and the idle card | Title, body and buttons are read | todo-hardware | note |
