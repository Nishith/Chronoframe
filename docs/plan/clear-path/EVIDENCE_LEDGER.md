# Clear path — evidence ledger (owner rows)

Only Nishith records results here. Agents leave every row `todo-hardware`. Use a disposable destination folder for H-CLP-1 and H-CLP-2.

## Setup
```bash
ui/build.sh
```
```bash
mkdir -p "$HOME/clp-test/A" "$HOME/clp-test/B" "$HOME/clp-test/C" "$HOME/clp-test/Organized"
```

## Ledger
| Row | What to run | Pass when | Status | Evidence |
|---|---|---|---|---|
| H-CLP-1 | Sandboxed (MAS or signed Debug) build. Choose Folders: add `A`, `B`, `C` with one picker; choose `Organized`; quit (⌘Q); relaunch; Preview Plan. Then try to add `Organized` as a folder, and try to choose `A/Inside` as the destination. | The three folders are listed after relaunch; the preview finds files from all three; both overlap attempts are refused with the plain message and nothing is created | todo-hardware | screenshot path |
| H-CLP-2 | The real library (65,000+ files, several folders) into a disposable destination: Preview Plan | The hero sentence appears with the right total and date span; the exception rows match the Review tab counts; the app stays responsive | todo-hardware | screenshot path, timing note |
| H-CLP-3 | VoiceOver on: Choose Folders list (add, remove), layout picker and example, preview summary rows, Next step card, Deduplicate lanes | Every control is named; the example is read as one sentence; remove buttons name their folder | todo-hardware | note |
| H-CLP-4 | The CI UI lane locally: `xcodebuild -project ui/Chronoframe.xcodeproj -scheme Chronoframe -configuration Debug -derivedDataPath .tmp/ChronoframeUITestDerivedData -destination "platform=macOS" -skip-testing:ChronoframeUITests/ChronoframeUITests/testAccessibilityAuditAcrossScenarios DEVELOPMENT_TEAM= test`, then the audit test alone | Exit 0; the audit logs no new finding for the changed screens | todo-hardware | log path |
| H-CLP-5 | Recapture `docs/screenshots/*.jpg` (all are from May 2026 and show the old tabs and labels) | Files replaced and committed | todo-hardware | commit |
| H-CLP-6 | One person who has not used Chronoframe organizes two folders and removes duplicates with no help | They finish without asking what a word means; note every hesitation. This is the validation gate for the full stepper (D-CLP-02) and for the copy (D-CLP-06) | todo-hardware | notes |
| H-CLP-7 | Read `docs/APP_STORE_METADATA.md`, the site and the compare page against the new labels ("Choose Folders", "Preview & Copy", "Start Copying") | Mismatches listed or fixed | todo-hardware | note |
