# Clear path — contracts

Plan prefix `CLP`. Read `docs/plan/next-half/AGENT_RULES.md` first. Line numbers refer to `feature/photos-import-resume` @ 5c72052; if a line moved, search for the quoted declaration. Paths are relative to `ui/Sources/` unless they start with `ui/` or `docs/`.

Goal: a non-technical person with tens of thousands of photos in several folders can organize and deduplicate them without learning Chronoframe's internal vocabulary. Every engine behavior, receipt format and safety invariant is unchanged; one invariant gap (INV-21 for staged sources) is closed.

## Findings (rationale; from the 2026-11-12 review of the running app)
| # | Finding | Contracts |
|---|---|---|
| 1 | "Several folders" has no home: Setup takes one "Manual Folder Source"; multi-drop works but is labelled as a one-off | C-03, C-04, C-05, C-06 |
| 2 | Engine vocabulary in the UI ("mutates", "artifacts", "Transfer", "Run", "Current Focus", "cluster", "Raw score", "Structure Drift") | C-01, C-02, C-06…C-12 |
| 3 | Five peer tabs for a linear job; Transfer offered beside Preview; three places to start a preview | C-02, C-06, C-08 |
| 4 | Folder layout is chosen in Settings; Setup never shows the result | C-07 |
| 5 | Preview result is six counters and a four-tab workspace, no sentence | C-09 |
| 6 | Nothing connects a finished copy to Deduplicate | C-10 |
| 7 | Dedupe review opens on hundreds of groups; the bulk action has three names | C-11 |
| 8 | Health scores an untouched library 83% with a warning | C-12 |

## C-01 Glossary (applies to every user-visible string in every WP)
User-visible means `Text`, `Label`, `Button`, alert titles and messages, `.help`, accessibility labels/hints/values, `UserFacingErrorMessage` output and Core `title`/`subtitle`/`message` strings that reach the UI. It does not mean identifiers, raw values, log lines written to files, receipts or the CLI.

| Do not show | Show instead |
|---|---|
| transfer (verb or noun), "Start Transfer" | copy, "Start Copying" |
| run (noun: "the run", "Run Cancelled", "Run History") | "preview" or "copy" as applies; "History" |
| source, source library, "Manual Folder Source" | "folders to organize"; the files are "originals" |
| mutate, mutation | change |
| artifacts, supporting artifacts | "reports and logs" |
| non-destructive | "copies nothing" |
| dry run, dry-run report | preview, "preview report" |
| idle (status) | "Not started" |
| issues (for warnings and errors) | "problems" |
| console | "Activity" |
| workers, queue, copy jobs, pending jobs | "copies waiting" (or omit) |
| cache, index, engine | omit; say what the user sees |
| cluster | group |
| perceptual match, near duplicate | look-alike |
| raw score | match score |
| routed, route | "goes to", "set aside in" |
| structure drift | "files outside the layout" |
| audit receipt | receipt (explained on first-contact surfaces, D-CLP-08) |
| revert | undo |

Rules: sentence case for sentences, title case for buttons and card titles as the codebase does today. Numbers use `.formatted()`. Singular and plural are both written out. Any failure or stop text says the originals were not changed (INV-10). No raw paths in sentences except the destination path in the copy confirmation.

## C-02 Core titles — `ChronoframeCore/ProfileModels.swift`, `ChronoframeCore/DeduplicateModels.swift` (WP-01)
`OrganizeSubSection` (`:228`): cases and raw values unchanged.

| case | `title` | `subtitle` |
|---|---|---|
| `.setup` | "Choose Folders" | "What to organize and where it goes" |
| `.run` | "Preview & Copy" | "Check the plan, then copy" |
| `.history` | "History" | "Past copies, reports and undo" |
| `.sources` | "Watched Folders" | "Get told when new photos arrive" |
| `.health` | "Health" | "Checks on your organized library" |

New, on `OrganizeSubSection`:
```swift
public static let primaryFlow: [OrganizeSubSection] = [.setup, .run, .history]
public static let secondary: [OrganizeSubSection] = [.sources, .health]
public static var displayOrder: [OrganizeSubSection] { primaryFlow + secondary }
```
`SidebarDestination.subtitle` (`:158`): organize "Sort into dated folders"; photos "Copy from Apple Photos"; deduplicate "Remove extra copies". Others unchanged.
`ClusterKind.title` (`DeduplicateModels.swift:196`): `.nearDuplicate` → "Look-alikes". Nothing else in that file changes.

## C-03 Staged sources and the destination (INV-21) — safety-critical (WP-02)
`ChronoframeCore/MediaDiscovery.swift` gains one public read-only helper next to the private manifest type (`:26–34`):
```swift
public enum DropManifestLookup: Equatable, Sendable { case absent, items([String]), unreadable }
public static func dropManifestLookup(inSourceRoot sourceRoot: String) -> DropManifestLookup
```
It reads `.chronoframe_drop_manifest.json` with the same decoding the enumerator uses; it never writes.

`SourceDestinationDisjointness` gains:
```swift
/// First conflict between any item and the destination, using the existing single-pair rule for each.
public static func conflict(sourceItemPaths: [String], destinationPath: String) -> <the existing conflict type>?
```
`ChronoframeAppCore/Services/SwiftOrganizerEngine.swift:472`: after the existing pair check, `if case let .items(paths) = MediaDiscovery.dropManifestLookup(inSourceRoot: resolvedConfiguration.sourcePath)`, run the items check and throw the same `OrganizerEngineError.sourceOverlapsDestination`. `.absent` and `.unreadable` add no behavior (discovery already handles an unreadable manifest). No other line of the engine changes.

## C-04 Folder list model, store and picker — AppCore (WP-03)
`ChronoframeAppCore/Services/SourceItemList.swift` (new, pure):
```swift
public enum SourceItemListError: Error, Equatable, LocalizedError {
    case insideListed(name: String, parentName: String)
    case overlapsDestination(name: String)
    case missing(name: String)
    // errorDescription:
    // insideListed:        "“{name}” is already covered because it is inside “{parentName}”."
    // overlapsDestination: "“{name}” and the destination overlap. Choose a destination outside the folders you are organizing; nothing was changed."
    // missing:             "Chronoframe can't find “{name}” any more. Reconnect the drive or add the folder again."
}
public struct SourceItemList: Equatable, Sendable {
    public private(set) var items: [URL]            // symlink-resolved, standardized, insertion order
    public init(items: [URL] = [])
    /// Same path → no-op. Inside a listed folder → throws insideListed. Contains listed folders → they are removed, then it is appended.
    /// destinationPath non-empty and overlapping (SourceDestinationDisjointness) → throws overlapsDestination. Not on disk → throws missing.
    public mutating func add(_ url: URL, destinationPath: String, fileManager: FileManager = .default) throws
    public mutating func remove(_ url: URL)
    public var needsStaging: Bool { get }           // count > 1, or the single item is not a directory
    public func firstConflict(withDestination destinationPath: String) -> SourceItemListError?
    public static func summaryLabel(count: Int) -> String   // "1 folder", "3 folders"
}
```
`SetupStore` (`Stores/SetupStore.swift`) gains `@Published public private(set) var sourceItems: [URL] = []` and `public func setSourceItems(_ items: [URL])`. `selectProfile(named:)` leaves `sourceItems` alone (D-CLP-21). `usingDroppedSource` is unchanged.
`PreferencesStore` gains `@Published public var manualSourceItemPaths: [String]`, persisted under defaults key `manualSourceItemPaths`, default `[]`.
`FolderAccessServicing` (`Services/FolderAccessService.swift:86`) gains the requirement `@MainActor func chooseFolders(startingAt path: String?, prompt: String) -> [URL]`; the real service uses one `NSOpenPanel` with `allowsMultipleSelection = true`, directories only, same start-path rules as `chooseFolder`. Every conformer in `ui/Sources` and `ui/Tests` is updated (find with `grep -rn ": .*FolderAccessServicing" ui/Sources ui/Tests`).

## C-05 Setup coordinator and bookmarks — App (WP-04)
`App/Coordinators/BookmarkPathResolver.swift`:
```swift
func sourceItemBookmarkKey(index: Int) -> String            // "manual.sourceItem.<index>"
func persistSourceItemBookmarks(for urls: [URL]) async      // writes 0..<n, removes every other key with prefix "manual.sourceItem."
func resolveSourceItemURLs() -> [URL]                       // in index order; unresolvable → key removed, item skipped
```
`retainScopedAccess(forProfileName:)` (`:87`) also includes every `manual.sourceItem.*` bookmark when `profileName == nil`.

`App/Coordinators/SetupCoordinator.swift`:
- `func chooseSourceFolder() async` (`:58`) now calls `chooseFolders(startingAt:prompt: "Add Folders")` and passes the result to `addSourceItems`.
- `func addSourceItems(_ urls: [URL]) async`: for each URL hold security scope as `:74–75` does, validate with role `.source`, `list.add(_:destinationPath:)`; the first error becomes `setTransientErrorMessage` and stops; then `applySourceItems`.
- `func removeSourceItem(_ url: URL) async`: `list.remove`, then `applySourceItems`.
- `func selectSourceFolder(_ url: URL) async` (`:70`): replaces the list with `[url]` (existing callers: history "use this source", single-folder drop on the step card).
- `func applyDrop(urls:)` (`:106`): `addSourceItems(urls)` (appends), then `navigate(.organize(.setup))`. Leaving profile mode stays as `:111–114`.
- `private func applySourceItems(_ list: SourceItemList) async`:
  - 0 items: `sourcePath = ""`, `sourceURL = nil`, `clearDroppedSource()`, `lastManualSourcePath = ""`, remove `manual.source` and item bookmarks, `manualSourceItemPaths = []`.
  - `!needsStaging`: exactly today's `:82–89` for that folder; item bookmarks removed; `manualSourceItemPaths = [path]`.
  - `needsStaging`: `droppedItemStager.stage(urls: list.items)`; the previous staging directory, if `isStagingPath`, is removed with `cleanup(stagingDirectory:)`; `sourcePath`/`sourceURL` = the new staging directory; `droppedSourceLabel = SourceItemList.summaryLabel(count:)`; `droppedSourceItemCount = count`; `persistSourceItemBookmarks`; `manualSourceItemPaths = paths`. `lastManualSourcePath` is not set to a staging path.
  - always: `setupStore.setSourceItems(list.items)`.
- `bootstrap` (`:40`): after `restoreManualPaths`, `let restored = bookmarkPathResolver.resolveSourceItemURLs()`; if `restored.count >= 2`, rebuild the list (skipping items that now fail `add`) and `applySourceItems`; else if `manualSourceItemPaths.count >= 2` but fewer resolved, fall back to the single restored path or empty and clear the stored list.
- `selectDestinationFolder` (`:143`): after validation, `if let error = list.firstConflict(withDestination: url.path)` → transient message, destination unchanged.
- `saveCurrentPathsAsProfile` (`:193`): when `setupStore.sourceItems.count > 1` → message "A saved profile holds one folder. Keep this list as it is (Chronoframe remembers it), or remove the extra folders to save a profile." and return.
- `clearSelectedProfile` (`:174`): after `restoreManualPaths`, re-run the bootstrap restore of the list.

`App/AppState.swift` (`:384–406`): `func addSourceItems(_ urls: [URL]) async` and `func removeSourceItem(_ url: URL) async`, each calling `runCoordinator.invalidateWatchedImportContext()` first, like their neighbors.

## C-06 Setup screen — `ChronoframeApp/Views/Setup/` (WP-05)
`SetupScreenContext` gains `sourceItems: [SetupSourceItemRow]` (default `[]`), `struct SetupSourceItemRow: Identifiable, Equatable { let id: String /* path */; let name: String /* last path component */; let parent: String /* abbreviated parent path */; let isFolder: Bool }`. The `@MainActor` initializer fills it from `setupStore.sourceItems`; when that is empty and `sourcePath` is a non-staging path it yields one row for `sourcePath` (profile and legacy single-folder cases).

Model text (exact):
| Member | Value |
|---|---|
| `SetupPrimaryAction.title` | chooseSource "Add Folders"; chooseDestination "Choose Destination"; preview "Preview Plan" |
| `heroBadgeTitle` | profile "Profile ready"; can start "Ready to preview"; partly set "One more step"; nothing set "Start here" |
| `nextStepSummary` | "Add the folders to organize" / "Choose where the copies go" / "Preview the plan" |
| `sourceStepState` | ready → `.ready("", .success)` (no badge text); else `.needed("Add a folder", .warning)` |
| `destinationStepState` | ready → `.ready("", .success)`; else `.needed("Choose a destination", .warning)` |
| `sourceSummaryValue` | rows.count == 0 "Needed"; 1 "Ready"; n `SourceItemList.summaryLabel(count: n)`; profile unchanged |
| `modeSummaryValue` | profile unchanged; otherwise "Folders you chose" |
| `configurationSummary` | profile unchanged; otherwise "Folders you chose" |
| `readinessMessage` | can start "A preview copies nothing. It shows where every file would go, and you decide after that."; else "Add a folder and choose a destination to see a preview." |
| `sourcePathHelper` | 1 row "Chronoframe reads this folder and never changes what is in it."; n rows "Chronoframe reads these {n} folders together and never changes what is in them."; 0 rows "" |
| `destinationPathHelper` | "Chronoframe creates dated folders here and keeps a receipt of each copy so you can undo it from History." |
`readinessBadgeTitle`, `readinessBadgeSymbol`, `readinessTone` are deleted with their only use.

Views:
- `SetupView`: `.navigationTitle("Choose Folders")`. Onboarding card title "Start with the folders that hold your photos.", subtitle "Drag them onto this window or add them below. Nothing is copied until you say so.", accessibility summary "Welcome. Start with the folders that hold your photos." `SetupReadinessSection` call sites drop `transfer:`. The window-level drop handler is unchanged (it calls `appState.applyDrop`, which now appends). `SetupContactSheetSection` receives the first folder row's path and URL when the source is staged.
- `SetupHeroSection` (`SetupSectionViews.swift:52`): title "Choose Folders"; the "Privacy" line value "Everything stays on this Mac"; "Next" line unchanged in structure.
- `SetupSourceStepSection` (`:243`): step title "1. Folders to organize", message "Add every folder that holds photos or videos. Chronoframe only reads them." The single `PathValueView` is replaced by `SetupSourceItemList`: one row per `SetupSourceItemRow` (folder or document glyph, name in body weight, parent path as caption, trailing remove button with `systemImage: "minus.circle"`, accessibility label "Remove {name} from the folders to organize", identifier `setup.sourceItem.remove.<index>`), then the helper line, then `SetupFolderChooserButton(title: "Add Folders…")` keeping identifier `chooseSourceButton` and hint "Opens a folder picker. You can pick more than one folder." The list has identifier `setup.sourceItems`. The step-card `onDrop` (`:310–324` in file numbering) passes every dropped URL to `addSource: ([URL]) -> Void` instead of the first to `selectSource`. A badge renders only for `.needed` states. Rows are not removable while a run is in progress or a profile is active.
- `SetupDropZone` (`:623`): idle "Drop folders here", targeted "Release to add", active label `droppedSourceLabel ?? "Folders added"`.
- `SetupDestinationStepSection` (`:363`): message "Where the organized copies go."; field title "Destination folder"; chooser hint "Opens a folder picker to choose where the organized copies go". The layout block (C-07) sits under the path.
- `SetupReadinessSection` (`:457`): title "3. Preview"; no badge; one `.borderedProminent` button "Preview Plan" (identifier `previewButton`, accessibility label "Preview plan", hints: "Builds the plan without copying anything" / "Add a folder and choose a destination first"); beside it a `.link`-style button "Copy Settings…" calling `openSettings`. No Transfer button; the `transfer` parameter is removed. The disclosure label is unchanged.
- `SetupPreflightChecklist` (`:555`): heading "Before you start"; rows: "Folders to organize" → "Needed" / "Ready"; "Destination" → "Needed" / "Checked when the preview runs"; "Originals" → "Never changed"; "Undo" → "Each copy keeps a receipt"; "Copy check" → "On" / "Off".
- `SetupContactSheetSection` (`:121`): title "A first look"; message with a folder "The first photos Chronoframe found in your folders."; without "Photos appear here once you add a folder."
- `SetupSavedSetupSection` (`:141`): picker entry "Manual Paths" → "Folders I Choose". Nothing else.

## C-07 Folder layout in Setup — App (WP-06)
`ChronoframeApp/Views/Setup/FolderLayoutPresentation.swift` (new, pure):
```swift
enum FolderLayoutPresentation {
    /// yyyyMMDD "Year / Month / Day"; yyyyMM "Year / Month"; yyyy "Year"; yyyyMonEvent "Year / Month / Event"; flat "One folder"
    static func title(_ structure: FolderStructure) -> String
    /// The relative destination path PlanningPathBuilder.buildDestinationPath gives for source "IMG_0001.jpg",
    /// date bucket for 14 July 2019, sequence 1, chronoframeDefault naming rules, no event override, no duplicate directory.
    static func exampleRelativePath(_ structure: FolderStructure) -> String
    /// exampleRelativePath split into an indented tree, one component per line, two spaces per level, folders end with "/".
    static func exampleLines(_ structure: FolderStructure) -> [String]
    static func accessibilityExample(_ structure: FolderStructure) -> String   // "Example: {exampleRelativePath}"
}
```
The implementer reads `PlanningPathBuilder.buildDestinationPath`'s parameters (`CopyPlanBuilder.swift:396–419` shows a call) and passes a temporary-looking root string, then strips it. If that function is not reachable from the App target, the example is hand-written and the test compares it with a one-file `DryRunPlanner` plan instead (log the choice).

`SetupLayoutBlock` (in `SetupSectionViews.swift`, used by the destination step): caption "Folder layout"; `Picker` (`.menu`) over `FolderStructure.allCases` showing `title`, bound to `preferencesStore.folderStructure`, identifier `setup.folderLayoutPicker`, disabled while a run is in progress; below it the `exampleLines` in a monospaced caption block, hidden from VoiceOver as separate lines and exposed as one element with `accessibilityExample`. `SetupDestinationStepSection` gains `@ObservedObject var preferencesStore: PreferencesStore` (passed from `SetupView`).
`SettingsView.swift:101`: `Text(structure.rawValue)` → `Text(FolderLayoutPresentation.title(structure))`. The reorganize dialog message (`:145`) uses the same title.

## C-08 Organize chrome, toolbar, prompts — App and one AppCore string block (WP-07)
- `Components/WorkspaceTabStrip.swift`: new parameter `var showsDividerBefore: (Tab) -> Bool = { _ in false }`; when true, a 1-pt vertical hairline (`DesignTokens.ColorSystem.hairline`, height 16, horizontal padding 6, `accessibilityHidden(true)`) precedes that tab.
- `Organize/OrganizeContainerView.swift:29`: `tabs: OrganizeSubSection.displayOrder`, `showsDividerBefore: { $0 == OrganizeSubSection.secondary.first }`. Identifiers unchanged.
- `RootSplitView.swift:29–53`: the toolbar group shows only the destructive button while `runSessionStore.isRunning`, label `Label("Stop", systemImage: "stop.fill")`. `showsRunToolbarActions` and the private `canStartRun` are deleted. Alert buttons (`:65–87`): confirm "Start Copying" / "Cancel"; resume "Resume" / "Start Over" / "Cancel".
- `App/AppCommands.swift:57–64`: "Preview" → "Preview Plan"; "Transfer" → "Start Copying". Shortcuts and gating unchanged.
- `App/AppState.swift:445, :453, :457`: "Finish the duplicate cleanup before organizing." (both); "Rebuild the preview before copying so Chronoframe copies exactly the corrected plan."
- `ChronoframeAppCore/Stores/RunSessionStore.swift:219–244` (strings only; no control-flow change):
  - blocking: title "Finish the interrupted copy first"; message "{n} file(s) from an earlier copy that was interrupted {is/are} still waiting. Start copying to resume or discard them, then run the free test batch. Nothing was copied and your originals were not changed."
  - resume: title "Finish the earlier copy?"; message "{n} file(s) from an earlier copy {is/are} still waiting. Resume to finish them, or start over with the current plan."
  - confirm: title "Start copying?"; message "Chronoframe will copy into {resolvedDestinationPath}. Your originals stay exactly where they are."
- `Views/SidebarView.swift`: no code change expected (it renders the Core subtitle); confirm nothing truncates at `DesignTokens.Sidebar.minWidth` by reading the layout, and note it in the report.
- `Organize/WatchedSourcesView.swift`, `Views/RunHistoryView.swift`: apply the C-01 glossary to visible strings only; list every changed literal in the report.

## C-09 Preview & Copy workspace — `ChronoframeApp/Views/Run/` (WP-08)
`CurrentRunView`: `.navigationTitle("Preview & Copy")`.

`RunWorkspaceModel.heroState` (`:209`), exact text:
| Status | title | message | badgeTitle |
|---|---|---|---|
| idle, can start | "Preview the plan first" | "A preview copies nothing. It shows where every photo and video would go, so you can check before copying." | "Not started" |
| idle, cannot | "Choose your folders first" | "Add the folders to organize and a destination, then come back here to preview and copy." | "Not started" |
| preflighting | "Getting ready" | "Chronoframe is checking your folders before it starts." | "Preparing" |
| running, preview | "Building the preview" | "You can keep using your Mac. Nothing is being copied." | "Previewing" |
| running, transfer | "Copying your photos" | "You can keep using your Mac. Originals are only read, never changed." | "Copying" |
| dryRunFinished | "Preview ready" | `previewHeadline.sentence` | "Preview ready" |
| finished | "Copy complete" | "{copied} photos and videos are in your organized library. Your originals were not changed." (1 → "1 photo or video is…") | "Done" |
| nothingToCopy | "Already up to date" | "Everything in these folders is already in your organized library. Nothing was copied." | "Up to date" |
| cancelled | "Stopped" | "Chronoframe stopped before finishing. Files already copied stay in place and your originals were not changed. Preview again when you are ready." | "Stopped" |
| failed | "Something needs attention" | `lastErrorMessage` ?? "Chronoframe could not finish. Your originals were not changed. Check that both folders are available, then try again." | "Needs attention" |
| reverted | "Undo complete" | "Chronoframe removed the copies listed in that receipt. Copies changed since then were kept." | "Undone" |
| revertEmpty | "Nothing to undo" | "That receipt lists no copies." | "Empty" |
| reorganized | "Layout updated" | "Chronoframe moved the files in your organized library into the new folder layout." | "Updated" |
| nothingToReorganize | "Layout already matches" | "Every file is already in the chosen layout. Nothing was moved." | "Up to date" |
Symbols, tones and `primaryAction` values are unchanged.

Hero buttons (`RunSectionViews.swift:120–186`): setup "Choose Folders" (hint "Opens Choose Folders"); preview "Preview Plan" (hints "Builds the plan without copying anything" / "Choose your folders first"); transfer "Start Copying", accessibility label "Start copying", identifier `AccessibilityIdentifiers.startTransferFromPreviewButton` (moved here), hints "Copies the planned files after you confirm" / "Preview first"; cancel "Stop" / "Stopping…" (hint "Stops now. Files already copied stay in place"); openDestination "Show in Finder"; showIssues "See Problems".
Hero summary lines (`:76–91`): "Security" → "Privacy"; the "Mode" line is removed; "Current Focus" → "Now", with an empty or idle task shown as "Not started"; "Issues" → "Problems"; "Source" → "From"; "Destination" → "To".

`ChronoframeApp/Views/Run/RunPreviewHeadline.swift` (new, pure):
```swift
struct RunPreviewHeadline: Equatable {
    struct Exception: Identifiable, Equatable { let id: String; let count: Int; let text: String; let systemImage: String; let opensReview: Bool }
    let sentence: String
    let exceptions: [Exception]
    init(metrics: RunMetrics, review: PreviewReviewSummary, isStale: Bool, locale: Locale = .current)
}
```
`sentence`: stale → "You changed some dates. Rebuild the preview so the copy matches your changes."; `plannedCount == 0` → "Everything here is already in your organized library. Nothing needs copying."; otherwise "{planned} photos and videos will be copied{span}. Nothing has been copied yet." (1 → "1 photo or video will be copied…"). `span` = ", from {first} to {last}" using the first and last `dateHistogram` keys that parse as `yyyy-MM` (or `yyyy-MM-dd`, `yyyy`), formatted "MMM yyyy" (or "yyyy") in `locale`; ", all from {first}" when they are equal; "" when none parse.
`exceptions`, only for counts > 0, in this order (ids in brackets): [unknown] `review.unknownDateCount` "{n} have no date and will go to the Unknown_Date folder unless you set one." (opensReview); [unsure] `review.lowConfidenceDateCount` "{n} have a date Chronoframe is unsure about." (opensReview); [copies] `metrics.duplicateCount` "{n} are exact copies of another file here and will be set aside in the Duplicate folder."; [already] `metrics.alreadyInDestinationCount` "{n} are already in your organized library and will be skipped."; [unreadable] `review.hashErrorCount` "{n} could not be read and will be skipped." (opensReview). Singular forms: "1 has…", "1 is…", "1 could not…".
`RunWorkspaceModel` gains `var previewHeadline: RunPreviewHeadline`; `previewReviewMessage` is deleted with its use.

`RunPreviewReviewSection` (`:257`) becomes `RunPreviewSummarySection(model:openReview:)`: card title "What will happen"; the sentence is not repeated (the hero shows it); one row per exception (glyph, text; rows with `opensReview` are buttons that call `openReview`, which sets `workspaceTab = .review`; accessibility hint "Opens the review list"); identifier `run.preview.summary`; when there are no exceptions the card shows "No problems found." There is no Start button in this section.
`RunWorkspaceModel.metrics` (`:590`) titles/captions: "Found" / "Photos and videos in your folders."; "To Copy" / "New files in the plan."; "Already There" / "Skipped because the same file is already in the library."; "Exact Copies" / "Set aside in the Duplicate folder."; "Problems" / "Warnings and files that could not be copied or checked."; "Copied" / "Files copied so far.". `previewReviewSummaryTiles` captions: "Ready to copy."; "No date, an unsure date, or unreadable."; "Go to the Unknown_Date folder unless you set a date."; "Exact copies, set aside in the Duplicate folder." (titles: "Ready", "Needs Attention", "No Date", "Exact Copies").
`RunWorkspaceShell` (`:371`): title "Details", message ""; `tabTitle`: "Overview", "Review" / "Review (n)", "Problems" / "Problems (n)", "Activity". `RunSnapshotPanel` title "Status" ("Issues" line → "Problems"). `RunArtifactsPanel` title "Reports and Logs"; "Open Report" → "Open Preview Report" (label "Open preview report"). `RunIssuesPanel`: title "Problems"; "Engine Issues" → "Problems"; empty title "No Problems", message "Warnings and errors will be listed here."; `issueWorkspaceSummary` reworded with "problems" and "activity log". `RunConsolePanel` title "Activity".
`RunIdleOnboardingCard` (`:642`): title "Three steps to an organized library"; steps "Choose your folders" / "Add the folders to organize and pick where the copies go."; "Preview the plan" / "A preview copies nothing. It shows exactly what would happen."; "Copy when it looks right" / "Progress and any problems show here while Chronoframe copies."
`RunOutcomeSummaryCard` (`CurrentRunView.swift:118`): "Run Summary" → "Summary"; "Planned" → "To Copy"; "Skipped" → "Already There"; "Issues" → "Problems". `outcomeSummaryMessage`: finished "Your originals were not changed. The report and the receipt for undoing this copy are in History."; nothingToCopy "Nothing needed copying."; reverted "Copies changed since the original copy were kept."; reorganized "Files were moved into the chosen layout and a receipt was saved."; nothingToReorganize "The library already matches the chosen layout."
`throughputSummaryValue` (`:454`): when speed and ETA are both "—" → status `.finished`/`.nothingToCopy`/`.reverted`/`.reorganized` "Done"; otherwise "Starting…".
`PreviewReviewPanel.swift`, `NowCopyingCard.swift`, `RunTimelineView.swift`, `RunAnnouncementPlanner.swift`: apply the C-01 glossary to visible and spoken strings ("Already Exists" → "Already There", "Duplicate Route" → "Set Aside as a Copy", "transfer" → "copy"); list each changed literal in the report.

## C-10 After a copy: next step — App (WP-09)
`RunWorkspaceModel` gains:
```swift
enum RunNextStep: Equatable { case findDuplicates(setAsideCount: Int) }
var nextStep: RunNextStep? { context.status == .finished && context.metrics.copiedCount > 0 ? .findDuplicates(setAsideCount: context.metrics.duplicateCount) : nil }
var nextStepBody: String   // setAside > 0: "{n} exact copies were set aside in the Duplicate folder during this copy. Deduplicate checks the whole organized library, including look-alikes. Nothing is removed until you approve it."
                           // else: "Deduplicate checks your organized library for exact copies and look-alikes. Nothing is removed until you approve it."
```
`ChronoframeApp/Views/Run/RunNextStepCard.swift` (new): `MeridianSurfaceCard`, title "Next: remove extra copies", `nextStepBody`, one `.bordered` button "Find Duplicates" → `appState.navigate(to: .deduplicate)`. Identifiers `run.nextStep.card`, `run.nextStep.findDuplicates` (added to `AccessibilityIdentifiers`). Shown in `CurrentRunView` directly under the hero when `model.nextStep != nil`.
`Deduplicate/DeduplicateView.swift` idle header (`:161–168`): a third line in caption style, "Organize already sets aside exact copies it meets while copying. Deduplicate checks the whole library, including look-alikes."; the combined accessibility label gains the same sentence.

## C-11 Deduplicate review — App only (WP-10)
`ChronoframeApp/Views/Deduplicate/DeduplicateReviewLanes.swift` (new, pure):
```swift
struct DeduplicateReviewLanes: Equatable {
    let safeGroupCount: Int     // eligible and not yet reviewed
    let checkGroupCount: Int    // not eligible and not yet reviewed
    let reviewedGroupCount: Int
    init(clusters: [DuplicateCluster], reviewedIDs: Set<DuplicateCluster.ID>, isEligible: (DuplicateCluster) -> Bool = DeduplicationPlanner.isAutomaticCommitEligible)
    var safeText: String?    // n > 0: "{n} groups are safe matches. Accept them together." (1: "1 group is a safe match. Accept it now.")
    var checkText: String?   // n > 0: "{n} groups are look-alikes or less certain. Look at each one." (1: "1 group is a look-alike or less certain. Take a look.")
    var doneText: String?    // both zero and reviewed > 0: "Every group has been reviewed."
}
```
`DeduplicateReviewLanesBar` (same file or `DeduplicateView.swift`): a single-row band above `reviewBody` and below `restoredReviewBanner`; left lane `safeText` + button "Accept All Safe" → `sessionStore.acceptAllSuggestions()`; right lane `checkText` + button "Quick Review" → `showingRapidTriage = true`; `doneText` alone when set; wraps to two rows in compact width (`ViewThatFits`). Identifiers `dedupe.lanes`, `dedupe.lanes.acceptSafe`, `dedupe.lanes.quickReview`. `reviewedIDs` = `Set(sessionStore.reviewedClusters.map(\.id))`.
Wording, visible and spoken (no logic change): `DeduplicateView.swift:422` "Select a group with at least two items to compare"; `:692` and `:739` accessibility label "Accept all safe groups"; `:694` hint "Accepts the suggestion for every safe group"; `:741` hint "Keeps the suggested file in every safe group and marks the rest for the Trash"; `:774` "Open History"; `ClusterDetailPane.swift:65` "Select a group on the left"; `:513, :527` "Match score: %.2f"; `ClusterListPane.swift:190` rotor "Look-alikes"; `RapidTriageView.swift:265` "All groups reviewed"; `App/Tips.swift:18` "Safe groups are matches Chronoframe has verified. Accept them together and keep moving. Chronoframe never selects uncertain matches for you." Any other visible "cluster" in `Views/Deduplicate/` becomes "group". Filter labels Safe / Check / Risky, the commit footer titles and every Trash sentence are unchanged.
Not edited: `DeduplicateSessionStore`, `DeduplicationPlanner`, `DeduplicateExecutor`, `DeduplicateScanner`.

## C-12 Health — Core copy and App gating (WP-11)
`ChronoframeCore/LibraryHealthScanner.swift` card copy (ids, values, actions unchanged):
| id | title | zero-count message | non-zero message | severity change |
|---|---|---|---|---|
| unknown-dates | "No Date" | "No files are waiting in the Unknown_Date folder." | "{bytes} of files need a date." | none |
| duplicates | "Exact Copies" | "No exact copies were set aside during past copies." | "{bytes} could be freed after you review them." | none |
| interrupted-work | "Unfinished Copies" | "No copies are waiting or failed." | "{p} waiting, {f} failed. Open Preview & Copy to finish them." | none |
| history | "Undo Records" | "Nothing has been copied here yet, so there is nothing to undo." | "Receipts are saved for recent copies, so they can be undone." | zero receipts → `.good` |
| structure-drift | "Files Outside the Layout" | "Every recognized file follows the folder layout." | "Some files don't follow Chronoframe's folder layout." | none |
Other cards and messages in that file: apply the C-01 glossary; list each changed literal in the report.
New computed property (not stored, not coded): `public var hasOrganizedHistory: Bool` on `LibraryHealthSummary` — true when the card with id `history` exists and its `value` is not `0.formatted()`.
`ChronoframeApp/Views/Organize/HealthDashboardView.swift`: `LibraryHealthHero` renders only when `summary.hasOrganizedHistory`; otherwise the hero message is "Nothing has been organized into this folder yet. Health checks become useful after your first copy." and the badge is "Not started" with the idle tint. Empty state message: "Run a check to see files with no date, exact copies, unfinished copies and files outside the layout." Legend label "Review" → "To Review".

## C-13 UI-test scenarios — `ChronoframeApp/App/UITesting/` (WP-12)
`UITestScenario` gains `setupMultiFolder` (three listed folders under the scenario's temp root, a destination, no run) and `runCopyComplete` (status `.finished`, `copiedCount` 4 200, `duplicateCount` 37). `UITestAppStateFactory` builds both from the existing `setupReady` and `runPreviewReview` builders. Both are DEBUG-only like their neighbors and appear in `UITestScenario`'s organize-tab mapping (`:71`).

## C-14 Strings and documentation (WP-12 lists, WP-14 docs, G2 catalogs)
- WP-12 writes `docs/plan/clear-path/strings-app.txt` and `strings-core.txt`: one line per new or changed English literal that is rendered through `LocalizedStringKey`/`String(localized:)` (App target → app list; `ChronoframeCore`/`ChronoframeAppCore` → core list), produced from `git diff feature/photos-import-resume -- ui/Sources`. Count- or date-bearing strings rendered with `Text(verbatim:)` or interpolation are listed in a third section of `strings-app.txt` headed `# not catalogued (interpolated)`.
- WP-14: `docs/QUICK_START.md`, `docs/FAQ.md`, `docs/TROUBLESHOOTING.md` — replace quoted old labels with the new ones, add "Organizing several folders at once" (list, nested-folder rule, destination-overlap refusal, that the list is remembered) and "What happens after a copy" (the Find Duplicates step). `docs/SAFETY_AND_RECOVERY.md` — one sentence: a staged list of folders is checked against the destination item by item (INV-21). Every sentence must be checkable against the code as committed.
- G2 (orchestrator): catalog keys (D-CLP-25); `AGENTS.md` INV-21 bullet gains "including each folder of a multi-folder source" only if WP-02 changed production code.
