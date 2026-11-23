# First ten minutes — contracts

Status: not started (verified 2026-11-22 on main 8308aac: `git grep` finds no `RunPreflightAssessment`, `PreflightService`, `FirstRunTestBatch` or `RunProofModel` in `ui/`). References and UI names below were refreshed against that commit after clear-path (#269, #274), free-space reservation (#265), run-outcome accuracy (#282) and presentation accuracy (#281); the contracts themselves are unchanged except where a `Stale since` note says so. UI names: the Setup tab is now Choose Folders, the Run tab is Preview & Copy, the copy button is "Start Copying" (was "Start Transfer") and the preview button "Preview Plan".

Plan prefix `FTM`. Read `docs/plan/next-half/AGENT_RULES.md` first. Line numbers were refreshed against `main` at 8308aac (2026-11-22); if a line moved, search for the quoted declaration.

Goal: the first archive feels safe before it starts and proven after it finishes. Three moments: (1) a live preflight on the Setup and Preview screens: destination free space against planned bytes, source and destination still reachable, Photos staging free space; (2) a proactive small verified test batch offered to first-time users next to Start Copying; (3) after that batch, a proof card: the files that now exist, Show in Finder, and Undo. No new wizard; experienced users keep the direct path.

Facts this design rests on (verified 2026-11-07): no preflight free-space check exists in the app: the only checks are the Deduplicate Trash dialog (`DeduplicateView.swift:592`), the Photos export floor (`PhotosExportExecutor.swift:129–222`) and the executor's pause loop and in-flight reservation (`TransferExecutor.checkDiskSpace`, `:1112–1170`, called at `:970`; `reserve(_:freeBytes:safetyBufferBytes:)` at `:185`, #265); planned bytes are not computed at preview (`RunMetrics.bytesTotal` stays unset in the preview summary, `SwiftOrganizerEngine.swift:535–542`) but `PlannedTransfer.identity.size` is available; restored bookmarks are never re-validated before a run (`SetupCoordinator.bootstrap`, `:51–70`, restores through `BookmarkPathResolver.restoreManualPaths`); the free batch is only offered after a refusal (`TrialAuthorizer.offeringFreeTestBatch`, `:84`, surfaced as `RunSessionStore.lastOfferedBatch` and `AppState.runOfferedFreeTestBatch`, `AppState.swift:515–530`); the completion hero has a "Show in Finder" button that reveals the destination folder (`RunSectionViews.swift:169`, `AppState.openDestination` `:815`) and the Summary card has "Open History" (`CurrentRunView.swift:122–173`), but neither can undo the batch; receipts are found through `HistoryStore.entries` and their filenames contain the run ID (`TransferExecutor.uniqueReceiptStem`, `:1426–1432`); `RunCompletionRecord.batchSourcePaths` identifies a batch run (`RunSessionStore.swift:16–50`).

## C-01 Preflight model — `ui/Sources/ChronoframeCore/RunPreflightAssessment.swift` (WP-01, new, Core, pure)

```swift
public enum PreflightCheckKind: String, Codable, Sendable, CaseIterable { case sourceAccess, destinationAccess, destinationSpace, stagingSpace }
public enum PreflightCheckStatus: String, Codable, Sendable { case ok, warning, blocked, unknown }

public struct PreflightCheck: Equatable, Sendable, Identifiable {
    public var id: PreflightCheckKind { kind }
    public let kind: PreflightCheckKind
    public let status: PreflightCheckStatus
    public let title: String       // "Destination space"
    public let detail: String      // "412 GB free; this copy needs about 38.2 GB." / "Not checked yet"
}

public struct PreflightInputs: Equatable, Sendable {
    public var sourceReachable: Bool?             // nil = not checked
    public var destinationWritable: Bool?
    public var destinationFreeBytes: Int64?
    public var plannedBytes: Int64?               // sum of PlannedTransfer.identity.size; nil before preview
    public var stagingFreeBytes: Int64?           // Photos only; nil when not a Photos import
    public static let safetyMarginBytes: Int64 = 1 * 1024 * 1024 * 1024   // 1 GiB beyond planned bytes
}

public enum RunPreflightAssessment {
    /// Rules: sourceAccess: nil→unknown "Not checked yet"; false→blocked "Chronoframe can't reach the source folder right now. Reconnect the drive or choose it again."; true→ok "Readable".
    /// destinationAccess: nil→unknown; false→blocked "…can't write to the destination…"; true→ok "Writable".
    /// destinationSpace: free nil→unknown "Free space unknown"; planned nil→ (free known) ok "{free} free; the copy size is known after Preview."; free < planned→blocked "{free} free; this copy needs about {planned}. Free up space or choose another destination before starting."; free < planned+margin→warning "{free} free; this copy needs about {planned}. That's close; the copy pauses if space runs out."; else ok "{free} free; this copy needs about {planned} (estimate, rechecked when the copy starts)."
    /// stagingSpace: nil→omitted from the list; else ok/warning at 2 GiB floor "Staging drive has {free} free. Photos doesn't report item sizes before export; the import pauses if space runs low."
    public static func assess(_ inputs: PreflightInputs) -> [PreflightCheck]
    public static func hasBlocked(_ checks: [PreflightCheck]) -> Bool
}

public enum ByteCountText {
    /// ByteCountFormatter, .file style, 1 decimal for GB and above, "0 bytes" for 0.
    public static func string(_ bytes: Int64) -> String
}
```

## C-02 Planned bytes at preview — `ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift:535–542` (WP-02)

Set `bytesTotal: result.transfers.reduce(0) { $0 + $1.identity.size }` in the preview `RunMetrics`. Nothing else changes; the transfer path keeps its own computation.

## C-03 Preflight service and store state (WP-02)

`ui/Sources/ChronoframeAppCore/Services/PreflightService.swift` (new):
```swift
public protocol FreeSpaceProviding: Sendable { func freeBytes(at url: URL) -> Int64? }
public struct VolumeFreeSpaceProvider: FreeSpaceProviding { public init(); /* volumeAvailableCapacityForImportantUsageKey; nil on error */ }

public struct PreflightService: Sendable {
    public init(freeSpace: any FreeSpaceProviding = VolumeFreeSpaceProvider(), folderAccess: any FolderAccessServicing)
    /// Off-main: validateFolder(source, .source) / validateFolder(destination, .destination) via Task.detached, free bytes of destination and optional staging parent. Missing paths → nil inputs.
    public func inputs(sourcePath: String?, destinationPath: String?, stagingParent: URL?, plannedBytes: Int64?) async -> PreflightInputs
}
```
`SetupStore` (`SetupStore.swift`) gains `@Published public private(set) var preflightChecks: [PreflightCheck] = []` and `public func applyPreflight(_ checks: [PreflightCheck])`.
`RunSessionStore` gains `public var previewPlannedBytes: Int64? { summary?.metrics.bytesTotal }` for preview summaries (nil when `summary == nil` or status is not a preview result).

## C-04 Setup coordinator recheck — `ui/Sources/ChronoframeApp/App/Coordinators/SetupCoordinator.swift` (WP-03)

- `bootstrap(restoreBookmarks:)` (`:51`) ends with `await refreshPreflight()`. Note `bootstrap` is synchronous (`func bootstrap(restoreBookmarks: Bool = true)`), so the `await` needs a `Task` or a signature change; log it as a decision.
- New `func refreshPreflight() async`: builds inputs via `PreflightService.inputs(sourcePath: setupStore.sourcePath, destinationPath: setupStore.destinationPath, stagingParent: nil, plannedBytes: runSessionStore.previewPlannedBytes)` and calls `setupStore.applyPreflight`. Called after `selectSourceFolder`/`selectDestinationFolder` succeed (`SetupCoordinator.swift:210`, `:483`; `AppState.swift:400`, `:405`), on Choose Folders appear (`SetupView` calls `appState.refreshPreflight()`), and when a preview completes (`RunCoordinator` observes `lastRunCompletion` with `mode == .preview`).
- `AppState` exposes `func refreshPreflight() async` forwarding to the coordinator.

## C-05 Setup checklist goes live — `ui/Sources/ChronoframeApp/Views/Setup/SetupSectionViews.swift:624–690` (WP-03)

`SetupPreflightChecklist` takes `checks: [PreflightCheck]` and renders one `preflightItem` per check with `isReady = status == .ok`, a warning tint for `.warning`, danger for `.blocked`, muted for `.unknown`; the static "Originals" ("Never changed"), "Undo" ("Each copy keeps a receipt") and "Copy check" ("On"/"Off") rows stay as they are below the live rows. `SetupScreenModel` (`SetupScreenModel.swift`; `SetupStepState` at `:35`, `sourceStepState` `:212`, `destinationStepState` `:219`, `readinessMessage` `:311`) gains `preflightChecks` in its context and `var blockingPreflight: PreflightCheck?`; when a source or destination check is `.blocked`, `sourceStepState`/`destinationStepState` return `.needed("Source Unavailable" / "Destination Unavailable", .warning)` and `readinessMessage` uses the check's detail. `canStartRun` is unchanged (preflight warns; the engine still enforces).

## C-06 Preview preflight card and test-batch offer — `ui/Sources/ChronoframeApp/Views/Run/RunSectionViews.swift:260`, `PreviewReviewPanel.swift:55` and `RunWorkspaceModel.swift` (WP-04)

- `RunPreviewReviewSection` gains a `PreflightSummaryRow` above the tiles: destination-space check detail with its tint; when `.blocked`, the Start Copying button stays enabled but the row says what will happen ("the copy pauses until space is freed"). Identifier `run.preview.preflight`.
- `RunWorkspaceModel` (`RunWorkspaceModel.swift:173`; `RunWorkspaceContext` `:99`) gains `var offersTestBatch: Bool` = preview finished with `transferCount > FirstRunTestBatch.size` and `isFirstRun` and `trialStatus` allows at least `FirstRunTestBatch.size` files; and `var testBatchTitle: String` = "Start with \(FirstRunTestBatch.size) files". `isFirstRun` comes from `RunWorkspaceContext.isFirstRun` = `historyStore.entries` has no `.auditReceipt` **and** `TrialUsage.organizeUsed == 0`.
- New Core `ui/Sources/ChronoframeCore/FirstRunTestBatch.swift` (WP-01): `public enum FirstRunTestBatch { public static let size = 25; public static func selection(from transfers: [PlannedTransfer], remainingAllowance: Int?) -> FreeTestBatch? }` — wraps `FreeTestBatchPlanner.batch(from:limit:)` with `limit = min(size, remainingAllowance ?? size)`; nil when `transfers.count <= limit` (a small plan needs no batch) or limit == 0.
- `AppState.startFirstRunTestBatch() async`: computes the selection from `runSessionStore`'s last preview transfers (expose `lastPreviewTransfers: [PlannedTransfer]?` on `RunSessionStore` if not already available; WP-02 owns that addition) and calls `runCoordinator.startTransfer(batch: batch.selection)`. The existing refusal-driven offer is unchanged.
- Button placement: beside "Start Copying" (`RunSectionViews.swift:145`, `case .transfer`, gated by `RunWorkspaceModel.canStartTransferFromPreview`, `:658`) as `.bordered` with identifier `run.preview.testBatch`, visible only when `offersTestBatch`.

> Stale since #265 (checked 2026-11-22): the executor already enforces disk space with an in-flight byte reservation, so "no free-space check exists anywhere" is no longer true of the executor; the preflight is still new at Setup and Preview. `startFirstRunTestBatch` and `lastPreviewTransfers` are also unclaimed: `RunSessionStore` holds no preview transfer list, but the refusal-driven path (`AppState.runOfferedFreeTestBatch`, `RunSessionStore.lastOfferedBatch`) already starts a batch through `runCoordinator.startTransfer(batch:)` and is the pattern to copy. No type named `RunPreviewReviewSection` exists; the summary section is `RunPreviewSummarySection` ("What will happen") and the review tiles live in `PreviewReviewPanel`.

## C-07 Proof card after a batch — `ui/Sources/ChronoframeApp/Views/Run/RunProofCard.swift` (WP-05, new) and `CurrentRunView.swift`

Shown instead of (above) `RunOutcomeSummaryCard` (`CurrentRunView.swift:122`; inserted near `:48`) when `runSessionStore.lastRunCompletion?.batchSourcePaths != nil && status == .finished`.
```swift
struct RunProofCard: View {
    let model: RunProofModel
    let showInFinder: () -> Void
    let undo: () -> Void
    let continueFullRun: () -> Void
}
struct RunProofModel: Equatable {   // pure, tested; built by RunWorkspaceModel
    let copiedCount: Int; let folderCount: Int; let verified: Bool
    let firstDestinationPath: String?        // from the receipt's first transfer dest
    let receiptURL: URL?; let destinationRoot: String
    var headline: String   // "25 files copied and verified into 3 folders." (verified false → "…copied into…")
    var body: String       // "Your originals weren't touched. Look at the result, then continue with the rest or undo this batch."
    var canUndo: Bool { receiptURL != nil }
}
```
- `firstDestinationPath`, `folderCount` and `receiptURL` come from the receipt located as `historyStore.entries.first { $0.kind == .auditReceipt && $0.relativePath.contains(completion.runToken.uuidString) }` (WP-05 reads `RunCompletionRecord.runToken`'s type and adapts; if it is not a UUID, use the executor's stem rule at `TransferExecutor.swift:1426`), decoded with `RevertExecutor().loadReceipt(at:)` off-main.
- `showInFinder` → `finderService.revealInFinder(firstDestinationPath ?? destinationRoot)`.
- `undo` → `.confirmationDialog` "Undo this test batch?" message "Undo removes the {copiedCount} copies Chronoframe just made. Your originals are untouched." button "Undo Batch" (destructive) → `appState.revertHistoryEntry(entry)` for that receipt entry (existing path, hash-checked revert).
- `continueFullRun` → `appState.startTransfer()` (existing; the engine skips the already-present batch).
- Identifiers `run.proof.card`, `run.proof.reveal`, `run.proof.undo`, `run.proof.continue`.

> Stale since #168 (checked 2026-11-22): `RunCompletionRecord.runToken` is "unique per accepted run request in this session" (`RunSessionStore.swift:117–119`, `currentRunToken = UUID()` at `:574`), not the run ID the executor writes into the receipt filename, so `relativePath.contains(completion.runToken.uuidString)` would find no receipt. The receipt must be found another way (for example newest `.auditReceipt` entry for the batch's destination whose transfers match `batchSourcePaths`); log it as a decision. The completion hero also already has a "Show in Finder" button for the destination folder, so the card's `showInFinder` duplicates it unless it selects the first copied file.

## C-08 Photos staging line — `ui/Sources/ChronoframeApp/Views/Photos/PhotosImportView.swift` (WP-06)

Below the status column in the footer (`footer`, `:285`), when `appState.photosStagingCheck` is non-nil, a `Text` with its detail and tint. `AppState` gains `@Published private(set) var photosStagingCheck: PreflightCheck?` refreshed on Photos tab appear (the staging parent is `AppState.photosStagingParentURL(environment:)`, `AppState.swift:982`) via `PreflightService.inputs(sourcePath: nil, destinationPath: setupStore.destinationPath, stagingParent: <the store's staging parent URL>, plannedBytes: nil)` → `assess` → the `.stagingSpace` and `.destinationSpace` entries (destination shown only when `.blocked`).

> Stale since clear-path (#269, #274): the glossary (`docs/plan/clear-path/CONTRACTS.md` C-01) replaces "source" with "folders to organize" and "transfer" with "copy" in user-visible text. This contract's strings "Source Unavailable", "Destination Unavailable" and "Chronoframe can't reach the source folder right now…" (C-01, C-05) still use "source", and the shipped step copy is "Add a folder" / "Choose a destination" (`SetupScreenModel.swift:212–224`). The strings are left as written; align them with the glossary when WP-03 lands.

## C-09 Strings (G2) — every literal in C-01 rules, C-06, C-07 and C-08 gets an English catalog key; the WP-07 implementer writes `docs/plan/first-ten-minutes/strings-app.txt` and `strings-core.txt` (Core literals live in `RunPreflightAssessment`; they are plain Swift literals surfaced through the App, so they go in the App catalog list).

## C-10 Documentation (WP-07) — `docs/QUICK_START.md` (preflight, test batch, proof card), `docs/FAQ.md` ("Why does Chronoframe suggest 25 files first?", "What does 'estimate, rechecked' mean?"), `docs/TROUBLESHOOTING.md` (Source Unavailable / Destination Unavailable), `README.md` "Safety First" one sentence on the free-space check.
