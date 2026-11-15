# Photos import resume — contracts

Plan prefix `PIR`. Read `docs/plan/next-half/AGENT_RULES.md` first. Line numbers refer to `main` after `feature/nas-v1` merges; if a line has moved, search for the quoted declaration.

Goal: an Apple Photos import that shows per-asset progress and iCloud waits, can be stopped, keeps every completely exported asset in a checkpoint, and resumes after a stop, a crash or a relaunch. Read-only PhotoKit (INV-22), per-asset transactions, `SourceDateHint` identity and the destination pin are unchanged.

## C-01 Checkpoint model — `ui/Sources/ChronoframeAppCore/Services/PhotosImportCheckpoint.swift` (WP-01, new)

```swift
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// One completely exported asset: every resource file and its content-bound date hint.
public struct PhotosCompletedAssetRecord: Equatable, Codable, Sendable {
    public let assetID: String
    public let files: [PhotosExportedFile]                 // gains Codable in WP-01
    public let sourceDateHints: [String: SourceDateHint]   // keyed by SourceDateHint.pathKey
    public init(assetID: String, files: [PhotosExportedFile], sourceDateHints: [String: SourceDateHint])
}

public enum PhotosImportCheckpointState: String, Codable, Sendable {
    case inProgress   // a prepare is (or was, if the app died) running
    case stopped      // user pressed Stop; resumable
    case lowSpace     // export paused for free space; resumable
    case ready        // every planned asset is completed or failed; a run may consume it
}

public struct PhotosImportCheckpoint: Equatable, Codable, Sendable {
    public static let version = 1
    public static let filename = ".chronoframe_photos_checkpoint.json"
    public let version: Int
    public let importID: UUID
    public let createdAt: Date
    public private(set) var updatedAt: Date
    public let destinationPath: String
    public let destinationBookmarkKeys: [String]
    public let plan: PhotosExportPlan                      // gains Codable in WP-01
    public private(set) var completed: [PhotosCompletedAssetRecord]
    public private(set) var failures: [PhotosAssetExportFailure]   // gains Codable in WP-01
    public private(set) var state: PhotosImportCheckpointState

    public init(importID: UUID, createdAt: Date, destinationPath: String, destinationBookmarkKeys: [String], plan: PhotosExportPlan)
    // state == .inProgress, completed and failures empty, updatedAt == createdAt, version == Self.version

    public var completedAssetIDs: Set<String> { get }
    public var remainingEntries: [PhotosAssetExportEntry] { get }   // plan.entries minus completed minus failed, in plan order
    public var reservedFilenames: Set<String> { get }                // last path component of every completed file
    public var isResumable: Bool { state == .stopped || state == .lowSpace || state == .inProgress }
    public var mergedSourceDateHints: [String: SourceDateHint] { get }
    public var exportedAssetIDs: [String] { get }                    // completed, in plan order

    public mutating func recordCompleted(_ record: PhotosCompletedAssetRecord, at date: Date)
    public mutating func recordFailure(_ failure: PhotosAssetExportFailure, at date: Date)
    public mutating func setState(_ state: PhotosImportCheckpointState, at date: Date)
}

public protocol PhotosImportCheckpointStoring: Sendable {
    func load(in stagingDirectory: URL) -> PhotosImportCheckpoint?   // nil when missing, unreadable, wrong version
    func save(_ checkpoint: PhotosImportCheckpoint, in stagingDirectory: URL) throws
    func remove(in stagingDirectory: URL)
}

public struct PhotosImportFileCheckpointStore: PhotosImportCheckpointStoring {
    public init()
    // URL: stagingDirectory.appendingPathComponent(PhotosImportCheckpoint.filename)
    // save: JSONEncoder (.iso8601 dates, [.sortedKeys, .prettyPrinted]) → Data.write(to:options: .atomic); creates stagingDirectory if missing.
    // load: JSONDecoder (.iso8601); any error → nil; checkpoint.version != PhotosImportCheckpoint.version → nil.
    // remove: FileManager.removeItem of the checkpoint file only; ignores a missing file.
}
```

Codable additions (WP-01, in their own files): `PhotosExportedFile`, `PhotosAssetExportFailure` (`PhotosExportExecutor.swift:46`, `:60`), `PhotosAssetExportEntry`, `PhotosExportPlan` (`ChronoframeCore/PhotosExportPlanner.swift:8`, `:28`), `PhotosAssetSummary.MediaKind` already `String`-raw. Add `Codable` to each declaration's conformance list; no other change.

## C-02 Export executor events and bounds — `ui/Sources/ChronoframeAppCore/Services/PhotosExportExecutor.swift` (WP-02, safety-critical: INV-22)

```swift
public enum PhotosExportEvent: Equatable, Sendable {
    case assetStarted(assetID: String, index: Int, total: Int)      // index is 0-based within this export call
    case resourceProgress(assetID: String, fraction: Double)         // 0…1 from the exporter, forwarded unchanged
    case assetCompleted(assetID: String)
    case assetFailed(assetID: String, message: String)
}

public enum PhotosExportStop: Error, Equatable, Sendable {
    case lowStagingSpace(freeBytes: Int64, floorBytes: Int64)
}

public struct PhotosExportExecutor {
    public static let defaultFreeSpaceFloorBytes: Int64 = 2 * 1024 * 1024 * 1024   // 2 GiB
    public init(exporter: any PhotosResourceExporting,
                timeZone: TimeZone = .current,
                freeSpaceFloorBytes: Int64 = PhotosExportExecutor.defaultFreeSpaceFloorBytes,
                freeSpaceProvider: @escaping @Sendable (URL) -> Int64? = PhotosExportExecutor.liveFreeSpace)
    public static func liveFreeSpace(at url: URL) -> Int64?
    // resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]) of url (create url first if missing is the caller's job); nil on error.

    public func export(plan: PhotosExportPlan,
                       to stagingDirectory: URL,
                       reservedFilenames: Set<String> = [],
                       isCancelled: @escaping @Sendable () -> Bool = { false },
                       onEvent: @escaping @Sendable (PhotosExportEvent) -> Void = { _ in }) async throws -> PhotosExportReceipt
}
```

Rules, in the order the existing loop (`:124–192`) runs:
1. `uniqueFilename(stem:fileExtension:resourceIndex:used:)` starts with `used = reservedFilenames` so a resumed export never reuses a completed asset's filename.
2. Before each asset (after `throwIfCancelled` at `:125`): `let free = freeSpaceProvider(stagingDirectory)`; if `free != nil && free! < freeSpaceFloorBytes` → `throw PhotosExportStop.lowStagingSpace(freeBytes: free!, floorBytes: freeSpaceFloorBytes)`. Nothing of the current asset has been written yet, so no rollback is needed. A `nil` free value never stops the export.
3. Emit `.assetStarted` before listing resources; `.assetCompleted` after the files are published (`:177–178`); `.assetFailed` in the failure branch (`:182–192`) with the same message string that goes into `PhotosAssetExportFailure`.
4. Resource writes call `exporter.writeResource(resource, to: url, onProgress:)` (C-03) and forward each fraction as `.resourceProgress`.
5. `CancellationError` behavior (`:179–181`) is unchanged: roll back the in-flight asset, rethrow. `PhotosExportStop` propagates the same way (it is thrown before any write). Both leave previously completed assets' files in place — the executor never deletes a published file.
6. The receipt still contains only this call's exported files, failures and hints. Merging with a checkpoint is the store's job.

## C-03 Progress-capable exporter seam — `ui/Sources/ChronoframeAppCore/Services/PhotosExportExecutor.swift` (protocol, WP-02) and `PhotosResourceExportService.swift` (WP-03, safety-critical: INV-22)

```swift
public protocol PhotosResourceExporting: Sendable {
    func originalResources(forAssetID id: String) async throws -> [PhotosExportableResource]
    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL) async throws
    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL,
                       onProgress: @escaping @Sendable (Double) -> Void) async throws
}
public extension PhotosResourceExporting {
    // Default keeps every existing test double compiling: ignores progress.
    func writeResource(_ resource: PhotosExportableResource, to destinationURL: URL,
                       onProgress: @escaping @Sendable (Double) -> Void) async throws {
        try await writeResource(resource, to: destinationURL)
    }
}
```

`PhotosResourceExportService` (WP-03) implements the three-argument method by copying the body of the existing `writeResource(_:to:)` (`:37–77`) and adding, after `options.isNetworkAccessAllowed = true` (`:48`): `options.progressHandler = { fraction in onProgress(fraction) }`. The two-argument method then calls the three-argument one with `{ _ in }`. No other line changes. Only read-only PhotoKit symbols remain in the file; `script/check_photos_import_readonly.sh` must stay green.

## C-04 Import store — `ui/Sources/ChronoframeAppCore/Stores/PhotosImportStore.swift` (WP-04)

New published state (all `public private(set)`):

```swift
public struct PhotosPreparationProgress: Equatable, Sendable {
    public let total: Int            // plan entries in this prepare/resume, including already-completed ones
    public let completed: Int        // completed so far, including carried-over checkpoint records
    public let failed: Int
    public let currentAssetLabel: String?    // originalFilename of the asset in flight, else nil
    public let isWaitingForCloud: Bool       // true from the first resourceProgress < 1 until assetCompleted/assetFailed
}

public struct PhotosResumableImport: Equatable, Sendable {
    public let stagingDirectoryURL: URL
    public let checkpoint: PhotosImportCheckpoint
    public let readyCount: Int        // checkpoint.completed.count
    public let totalCount: Int        // checkpoint.plan.entries.count
    public let interruptedAt: Date    // checkpoint.updatedAt
    public let destinationMatches: Bool
}

@Published public private(set) var preparation: PhotosPreparationProgress?
@Published public private(set) var resumable: PhotosResumableImport?
public var isPreparingImport: Bool { preparation != nil }   // replaces the stored Bool at :36; same name, now computed
```

New init parameters, appended with defaults: `checkpointStore: any PhotosImportCheckpointStoring = PhotosImportFileCheckpointStore()`, `exportExecutorFactory: @escaping (any PhotosResourceExporting) -> PhotosExportExecutor = { PhotosExportExecutor(exporter: $0) }`, `now: @escaping @Sendable () -> Date = Date.init`.

Methods:

```swift
public func refreshResumableImport(destination: DestinationCapture?)
// Enumerate stagingParentURL's immediate subdirectories. For each with a loadable checkpoint whose isResumable is true and
// whose every completed file exists with the recorded size (SourceDateHint.identity.size vs FileManager attributes; no hashing),
// build PhotosResumableImport. destinationMatches = pathsMatch(checkpoint.destinationPath, destination?.path) using the same
// standardized-path comparison RunCoordinator.pathsMatch uses (copy its 3 lines; do not import App). If several qualify,
// keep the newest updatedAt and remove the others' directories. Subdirectories with no checkpoint, a .ready checkpoint, or a
// checkpoint whose files are missing/resized are removed. Sets `resumable` (nil when none).

public func prepareImport(destination: DestinationCapture?) async -> PhotosImportContext?
// Unchanged preconditions (:174–183). Replace purgeStagingParent() at :192 with refreshResumableImport(destination:) followed by
// removal of `resumable`'s directory if present (a new prepare supersedes an old checkpoint; the UI confirms first, see C-05).
// Then runExport(checkpoint: new checkpoint for this plan, stagingDirectory:, destination:).

public func resumeImport(destination: DestinationCapture?) async -> PhotosImportContext?
// Requires `resumable != nil`, destinationMatches, authorization.allowsReading, !isPreparingImport; otherwise sets statusMessage
// (C-06 strings) and returns nil. Runs runExport with the loaded checkpoint and its remainingEntries.

public func cancelPreparation()
// Sets a cancellation flag read by the export's isCancelled closure. Does not clear `preparation`; runExport does when it unwinds.

public func discardResumableImport()
// Removes `resumable`'s directory and sets resumable = nil.

public func cleanupStaging(for context: PhotosImportContext)   // unchanged (:224)
```

`runExport` (private) rules:
1. `preparation = PhotosPreparationProgress(total: plan.entries.count, completed: checkpoint.completed.count, failed: checkpoint.failures.count, currentAssetLabel: nil, isWaitingForCloud: false)`; `checkpoint.setState(.inProgress)`; save.
2. Call `exportExecutorFactory(exporter).export(plan: PhotosExportPlan(entries: checkpoint.remainingEntries), to: stagingDirectory, reservedFilenames: checkpoint.reservedFilenames, isCancelled:, onEvent:)`. Events update `preparation` on the main actor; `.assetCompleted` appends a `PhotosCompletedAssetRecord` built from the receipt-in-progress — because the receipt arrives only at the end, the executor's `.assetCompleted` must carry enough to record: **amend C-02**: `case assetCompleted(assetID: String, files: [PhotosExportedFile], sourceDateHints: [String: SourceDateHint])`. After each `.assetCompleted` / `.assetFailed`: update checkpoint and save (one atomic write per asset).
3. On normal return: `checkpoint.setState(.ready)`, save, `resumable = nil`, `preparation = nil`. If `checkpoint.completed.isEmpty` → remove the directory, statusMessage = existing "couldn't read the selected items" text (:200–202), return nil. Else statusMessage = existing failures text when failures > 0 (:205), return `PhotosImportContext(importID:, stagingDirectoryURL:, destinationPath:, destinationBookmarkKeys:, assetIDs: checkpoint.exportedAssetIDs, sourceDateHints: checkpoint.mergedSourceDateHints)`.
4. On `CancellationError`: `setState(.stopped)`, save, `preparation = nil`, `refreshResumableImport(destination:)`, statusMessage = C-06 "stopped" string with counts. Return nil.
5. On `PhotosExportStop.lowStagingSpace`: `setState(.lowSpace)`, save, `preparation = nil`, refresh resumable, statusMessage = C-06 "low space" string. Return nil.
6. Any other error: as today (:215–219) but **do not purge the parent**: remove only this import's directory when `checkpoint.completed.isEmpty`; otherwise `setState(.stopped)`, save, refresh resumable, statusMessage = existing "couldn't prepare" text. Return nil.
7. `purgeStagingParent()` is deleted. The only whole-directory removals are: discard, superseded-by-new-prepare, invalid checkpoint cleanup in refresh, empty-result cleanup, and `cleanupStaging(for:)` after a run.

## C-05 Photos UI — `ui/Sources/ChronoframeApp/Views/Photos/` (WP-05)

New file `PhotosPreparationPanel.swift`:
```swift
struct PhotosPreparationPanel: View {
    let progress: PhotosPreparationProgress
    let onStop: () -> Void
    // Row 1: ProgressView(value: Double(progress.completed + progress.failed), total: Double(max(progress.total, 1)))
    // Row 2: Text(PhotosPreparationText.progressLine(progress))  // "Preparing 12 of 480…"
    // Row 3 (optional): currentAssetLabel, and when isWaitingForCloud: Text("Downloading from iCloud…")
    // Row 4 (optional, failed > 0): Text(PhotosPreparationText.failuresLine(progress.failed))
    // Button("Stop", action: onStop) with accessibilityIdentifier AccessibilityIdentifiers.photosImportStopButton
}
```
New file `PhotosResumeCard.swift`:
```swift
struct PhotosResumeCard: View {
    let resumable: PhotosResumableImport
    let onResume: () -> Void
    let onDiscard: () -> Void
    // Title: "An import was interrupted."
    // Body: PhotosPreparationText.resumeBody(resumable)  (C-06)
    // When !destinationMatches: Text(PhotosPreparationText.destinationMismatch) and the Resume button disabled.
    // Buttons: "Resume Import" (identifier photosImportResumeButton), "Discard" (identifier photosImportDiscardButton).
}
```
New file `PhotosPreparationText.swift` (pure functions returning `String`; unit-tested):
```swift
enum PhotosPreparationText {
    static func progressLine(_ p: PhotosPreparationProgress) -> String
    static func failuresLine(_ failed: Int) -> String
    static func resumeBody(_ r: PhotosResumableImport) -> String
    static let destinationMismatch: String
    static let waitingForCloud: String
}
```
`PhotosImportView.swift` edits: at `:285–288` replace the bare `ProgressView` with `if let progress = store.preparation { PhotosPreparationPanel(progress: progress, onStop: { store.cancelPreparation() }) }`; above the album list, when `store.resumable != nil && store.preparation == nil`, show `PhotosResumeCard(resumable:, onResume: { Task { await appState.resumeInterruptedPhotosImport() } }, onDiscard: { store.discardResumableImport() })`; when a resumable import exists and the user presses Review & Import for a new selection, show a `.confirmationDialog` "Start a new import?" with message C-06 `supersedeMessage`, buttons "Start New Import" (destructive role) and "Keep Interrupted Import" (cancel). On view appear: `store.refreshResumableImport(destination: appState.currentDestinationCapture())`.

`AccessibilityIdentifiers.swift` (`:56–60` block) gains `photosImportStopButton`, `photosImportResumeButton`, `photosImportDiscardButton` as `"photos.import.stop"`, `"photos.import.resume"`, `"photos.import.discard"`.

## C-06 User-facing strings (exact; used by C-04 and C-05)

| Key | Text |
|---|---|
| stopped | `Import stopped. {ready} of {total} items are ready and were kept. Resume whenever you like. Your Photos library was not changed.` |
| lowSpace | `Chronoframe paused the import because the drive holding its staging folder is almost full. {ready} of {total} items are ready and were kept. Free up space, then resume. Your Photos library was not changed.` |
| resumeBody | `{ready} of {total} items from Photos were prepared on {date, .dateTime.month().day().hour().minute()} and are ready to import. Your Photos library was not changed.` |
| destinationMismatch | `This import was prepared for a different destination. Choose that destination again to resume, or discard it.` |
| notAuthorized (resume) | `Chronoframe needs access to Photos to continue this import.` |
| progressLine | `Preparing {completed} of {total}…` |
| failuresLine | `{failed} couldn't be read and will be skipped.` (singular: `1 item couldn't be read and will be skipped.`) |
| waitingForCloud | `Downloading from iCloud…` |
| supersedeMessage | `Starting a new import discards the {ready} prepared items from the interrupted one. Your Photos library is not affected either way.` |

Counts are formatted with `NumberFormatter` decimal style. Strings are Swift literals in `PhotosPreparationText` / the store; the orchestrator adds the `.xcstrings` keys at G2 (D-PIR-09).

## C-07 App wiring — `ui/Sources/ChronoframeApp/App/AppState.swift` (WP-06)

- `makePhotosImportStore()` (`:925–934`): staging parent becomes `ProcessInfo.processInfo.environment["CHRONOFRAME_PHOTOS_STAGING_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) } ?? <existing path>` **inside `#if DEBUG` only**; release keeps the existing path.
- New `func currentDestinationCapture() -> PhotosImportStore.DestinationCapture?` extracted from `:1284–1288` (same body); `reviewAndImportSelectedPhotos()` calls it.
- New `func resumeInterruptedPhotosImport() async`: same guards as `:1279–1281`; `let context = await photosImportStore.resumeImport(destination: currentDestinationCapture())`; on nil copy `statusMessage` to `transientErrorMessage`; else `previewReviewStore.reset()` and `await runCoordinator.startPreview(photosImportContext: context)`.
- On app launch, after stores are built: `photosImportStore.refreshResumableImport(destination: currentDestinationCapture())`.
- `RunCoordinator` is unchanged: its post-transfer `cleanupPhotosStaging` (`RunCoordinator.swift:68–84`) removes the whole staging directory including the checkpoint, which is correct because the run consumed it.

## C-08 Documentation (WP-07 implementer; AGENTS.md and `.xcstrings` by the orchestrator at G2)

- `AGENTS.md:131` sentence "Staging is deleted on completion, failure, or cancellation" becomes: "Staging is deleted when a transfer run consumes it, when the user discards an interrupted import, or when a prepare produced nothing. A stopped, paused or crashed prepare keeps its completely exported assets with a checkpoint (`.chronoframe_photos_checkpoint.json`) so the import can resume; partially written assets are always rolled back."
- `docs/SAFETY_AND_RECOVERY.md`: add a "Photos import checkpoints" subsection: where the checkpoint lives, what resume validates (destination path, authorization, every completed file present with its recorded size; content is re-hashed by the planner at preview and any change aborts), and that Stop never deletes prepared files.
- `docs/FAQ.md` / `docs/TROUBLESHOOTING.md`: "The import stopped. Do I have to start over?" and "Chronoframe says the drive is almost full" entries using the C-06 wording.
