# Find and account — contracts

Plan prefix `FAA`. Read `docs/plan/next-half/AGENT_RULES.md` first. Line numbers refer to `main` after the preceding plans merge; if a line moved, search for the quoted declaration.

Goal: two faces on one index. (a) After an Organize run, every selected item has an outcome the customer can inspect: copied and verified, already present at an identified destination, excluded from discovery, failed, changed, or unresolved, each with evidence and a next action. (b) Across runs, find an imported file by its original filename or source folder and reveal where it went, with honest present / missing / unavailable status.

Facts this design rests on (verified 2026-11-07): the organize receipt lists only copied files as `{source, dest, hash}` (`TransferExecutor.swift:1543–1548`) with run status `PENDING|COMPLETED|ABORTED`; "already present" exists only in the preview (`PreviewReviewItem.plannedDestinationPath`, `PreviewReviewModels.swift:192–204`) and is not persisted by the transfer; discovery exclusions are neither counted nor listed (`MediaDiscovery.swift:106–205`); `CopyJobs` keeps `status`, `run_id`, `actual_dst_path` for every planned source after a run but is keyed by `src_path` and cleared by Start Fresh (`OrganizerDatabase.swift:256–265`, `DestinationRecovery.swift:78–95`); `RevertExecutor.swift:375` and `RunHistoryView.swift:1217` treat `!fileExists` as missing; `RunArtifactPaths` has no receipt path (`TransferExecutor.swift:240–253`); `FilesystemPresence { exists, missing, inaccessible }` already exists (`MutationRecoveryCoordinator.swift:4–25`).

## C-01 Run outcome record — `ui/Sources/ChronoframeCore/RunOutcomeRecord.swift` (WP-01, new, Core)

```swift
public enum RunItemOutcome: String, Codable, Sendable, CaseIterable {
    case copiedVerified        // receipt entry exists; dest and hash from the receipt
    case alreadyPresent        // preview status .alreadyInDestination; destinationPath = existing file
    case duplicateInSelection  // preview status .duplicate (another selected file with the same identity was copied)
    case excluded              // never a candidate: see RunExcludedItem.reason
    case failed                // CopyJobs status FAILED
    case skipped               // CopyJobs status SKIPPED (identity already present at copy time)
    case changed               // planned but identity mismatch at copy time (TransferExecutor "changed" issue) — recorded as failed with reason "changed" when the job row says so; see D-FAA-06
    case unresolved            // planned, but no receipt entry and no terminal job row (crash, cancel, missing evidence)
}

public struct RunOutcomeItem: Equatable, Codable, Sendable {
    public let sourcePath: String
    public let sourceName: String                 // last path component, for search
    public let identityRawValue: String?          // FileIdentity.rawValue when known
    public let outcome: RunItemOutcome
    public let destinationPath: String?           // copiedVerified: receipt dest; alreadyPresent: existing path; skipped: actual_dst_path if present
    public let detail: String?                    // plain reason for failed/changed/unresolved
}

public enum RunExclusionReason: String, Codable, Sendable, CaseIterable {
    case hidden, unsupportedType, skipRule, symlinkOrPackage, cloudDataless, attributesUnreadable
}
public struct RunExcludedItem: Equatable, Codable, Sendable {
    public let path: String
    public let reason: RunExclusionReason
}

public struct RunOutcomeRecord: Equatable, Codable, Sendable {
    public static let version = 1
    public static let filenamePrefix = "run_outcome_"      // run_outcome_<receiptStem-without-"audit_receipt_">.json
    public static let maxListedExclusions = 5_000
    public let version: Int
    public let runID: UUID
    public let receiptRelativePath: String?               // ".organize_logs/audit_receipt_…json" when known
    public let sourceRoot: String
    public let destinationRoot: String
    public let startedAt: Date
    public let finishedAt: Date
    public let runStatus: String                          // COMPLETED | ABORTED | FAILED | CANCELLED (from RunSummary)
    public let items: [RunOutcomeItem]                    // every planned/previewed source, plus copied ones
    public let excludedCounts: [RunExclusionReason: Int]  // always complete
    public let excludedItems: [RunExcludedItem]           // first maxListedExclusions, discovery order
    public let unassessedDirectories: [String]            // DirectoryIssue paths (unreadable subtrees)
    public var counts: [RunItemOutcome: Int] { get }
    public var isComplete: Bool { counts[.unresolved, default: 0] == 0 && unassessedDirectories.isEmpty }
}

public enum RunOutcomeRecordBuilder {
    /// Pure. Joins the frozen preview (what was selected), the job rows (what the executor did), the receipt (what was verified) and discovery exclusions.
    /// Rules: every previewItem produces exactly one item. Precedence per source path: receipt entry → copiedVerified;
    /// else job FAILED → failed (detail from job if present) ; job SKIPPED → skipped; preview .alreadyInDestination → alreadyPresent;
    /// preview .duplicate → duplicateInSelection; preview .hashError → failed(detail "couldn't be read"); else → unresolved.
    /// A receipt entry whose source is not in the preview still produces a copiedVerified item (evidence wins).
    public static func build(runID: UUID, receiptRelativePath: String?, sourceRoot: String, destinationRoot: String,
                             startedAt: Date, finishedAt: Date, runStatus: String,
                             previewItems: [PreviewReviewItem], jobs: [CopyJobRecord],
                             receiptTransfers: [RevertReceiptTransfer],
                             exclusions: [RunExcludedItem], unassessedDirectories: [String]) -> RunOutcomeRecord
}

public enum RunOutcomeRecordIO {
    /// Writes with DestinationMetadataFile.replaceFile (O_EXCL temp, F_FULLFSYNC, rename) into <destinationRoot>/.organize_logs/. Returns the URL.
    public static func write(_ record: RunOutcomeRecord, destinationRoot: URL, receiptStem: String?) throws -> URL
    public static func read(at url: URL) throws -> RunOutcomeRecord   // JSONDecoder .iso8601; version > Self.version → throws unsupported
}
```

## C-02 Discovery exclusion callback — `ui/Sources/ChronoframeCore/MediaDiscovery.swift` (WP-01)

`discoverMediaFiles(at:isCancelled:onDirectoryIssue:)` (`:36–46`) gains a trailing parameter `onExcluded: (RunExcludedItem) -> Void = { _ in }`. Each existing `continue` at `:106/:185` (hidden), `:110` (skip rule), `:114` (unsupported), `:192–193` (symlink/package), `:200–202` (dataless), `:204–205` (attributes error) calls it with the matching reason before continuing. No other behavior change. `DryRunPlanner.plan`/`planAsync` (`:121–132`, `:474`) gain `onExcluded` and forward it; default keeps every caller compiling.

## C-03 Record writer in the engine — `ui/Sources/ChronoframeAppCore/Services/SwiftOrganizerEngine.swift` (WP-02)

In the transfer path after `TransferExecutor` returns (around `:972–1000` where the transfer `RunSummary` is built): collect `previewItems` from the planning result used for this transfer, `jobs` from `database.loadCopyJobs(status:)` for each `CopyJobStatus` filtered to this `runID`, `receiptTransfers` by reading the receipt just written (locate it by `runID` in `.organize_logs/audit_receipt_*_<runID>.json`; `RevertExecutor().loadReceipt(at:)`), exclusions and directory issues captured during planning via C-02 and the existing `DirectoryIssue` events. Build and write the record. Any failure to write the record is logged through the run logger and surfaced as a run issue of severity `.warning` with text "Chronoframe couldn't save the per-item summary for this run. Your copies and receipt are unaffected." It never fails the run. Set `RunArtifactPaths.outcomeRecordPath` (C-04).

## C-04 Artifact path — `ui/Sources/ChronoframeCore/RunModels.swift:276–281` (WP-01)

`RunArtifactPaths` gains `public var outcomeRecordPath: String? = nil` (Codable, defaulted; existing initializers unchanged). `RunHistoryEntryKind` (`ProfileModels.swift:33–41`) gains `case runOutcome` with title "Run Summary"; `RunHistoryIndexer.classify` (`RunHistoryIndexer.swift:69–88`) maps the `run_outcome_` prefix to it; `RunHistoryIndexer` timestamp parsing treats it like `audit_receipt_` (local time zone).

## C-05 Lookup index — `ui/Sources/ChronoframeCore/MediaLookupIndex.swift` (WP-03, new, Core; SQLite under Application Support so WAL is allowed)

```sql
CREATE TABLE IF NOT EXISTS Mappings (
    destination_root TEXT NOT NULL,
    run_id TEXT NOT NULL,
    source_path TEXT NOT NULL,
    source_name_lower TEXT NOT NULL,
    identity TEXT,
    outcome TEXT NOT NULL,
    destination_path TEXT,
    run_finished_at REAL NOT NULL,
    PRIMARY KEY (destination_root, run_id, source_path)
);
CREATE INDEX IF NOT EXISTS idx_mappings_name ON Mappings(source_name_lower);
CREATE INDEX IF NOT EXISTS idx_mappings_finished ON Mappings(run_finished_at);
CREATE TABLE IF NOT EXISTS IndexedRecords (destination_root TEXT NOT NULL, relative_path TEXT NOT NULL, file_size INTEGER NOT NULL, PRIMARY KEY (destination_root, relative_path));
```
```swift
public struct MediaLookupQuery: Equatable, Sendable {
    public var nameContains: String          // case-insensitive substring of source_name_lower; empty matches all
    public var sourceFolderPrefix: String?   // source_path LIKE prefix%
    public var finishedAfter: Date?
    public var finishedBefore: Date?
    public var outcomes: Set<RunItemOutcome> // empty = all
    public var limit: Int = 500
}
public struct MediaLookupHit: Equatable, Sendable, Identifiable {
    public var id: String { "\(destinationRoot)|\(runID)|\(sourcePath)" }
    public let destinationRoot: String; public let runID: UUID; public let sourcePath: String
    public let identityRawValue: String?; public let outcome: RunItemOutcome
    public let destinationPath: String?; public let runFinishedAt: Date
}
public enum MediaLookupPresence: Equatable, Sendable { case present, missing, unavailable, notApplicable }

public final class MediaLookupIndex: @unchecked Sendable {
    public static func defaultURL() -> URL    // RuntimePaths.applicationSupportDirectory()/lookup/index.db
    public init(url: URL) throws              // pragmas as NASAssessmentStore (busy_timeout, WAL, synchronous FULL, foreign_keys)
    public func ingest(record: RunOutcomeRecord, relativePath: String, fileSize: Int64) throws   // idempotent; replaces rows for (destination_root, run_id)
    public func ingestLegacyReceipt(_ receipt: RevertReceipt, destinationRoot: String, relativePath: String, fileSize: Int64, finishedAt: Date) throws
    // every transfer → copiedVerified with identity = hash; used for receipts that predate outcome records
    public func isIndexed(destinationRoot: String, relativePath: String, fileSize: Int64) -> Bool
    public func search(_ query: MediaLookupQuery) throws -> [MediaLookupHit]   // ordered run_finished_at DESC, source_name_lower ASC
    public func forget(destinationRoot: String) throws
}

public enum MediaLookupPresenceEvaluator {
    /// Uses FilesystemPresenceChecking (POSIXFilesystemPresenceChecker): exists → .present; missing → .missing; inaccessible → .unavailable. nil destinationPath → .notApplicable. Never deletes, never follows symlinks (lstat-based checker).
    public static func presence(of hit: MediaLookupHit, checker: any FilesystemPresenceChecking = POSIXFilesystemPresenceChecker()) -> MediaLookupPresence
}
```

## C-06 Lookup store and history ingestion — `ui/Sources/ChronoframeAppCore/Stores/MediaLookupStore.swift` (WP-04, new) and `HistoryStore.swift` (WP-04)

```swift
@MainActor public final class MediaLookupStore: ObservableObject {
    @Published public private(set) var hits: [MediaLookupHit] = []
    @Published public private(set) var presence: [MediaLookupHit.ID: MediaLookupPresence] = [:]
    @Published public private(set) var isSearching = false
    @Published public private(set) var statusMessage: String?          // plain; never raw SQLite
    @Published public var query = MediaLookupQuery(nameContains: "", outcomes: [])
    public init(index: @escaping @Sendable () throws -> MediaLookupIndex = { try MediaLookupIndex(url: MediaLookupIndex.defaultURL()) },
                presenceChecker: any FilesystemPresenceChecking = POSIXFilesystemPresenceChecker())
    public func search() async          // off-main via Task.detached; sets hits; then evaluates presence for the first 200 hits off-main
    public func refreshPresence(for hit: MediaLookupHit) async
    public func ingest(from historyEntries: [RunHistoryEntry], destinationRoot: String) async
    // for each .runOutcome entry not yet indexed (isIndexed by relativePath+fileSize) → read + ingest; for each .auditReceipt entry whose run has no .runOutcome sibling → ingestLegacyReceipt (finishedAt = entry.createdAt). Holds the caller-provided security scope (HistoryStore passes its destination scope).
}
```
`HistoryStore.loadEntries()` (`HistoryStore.swift:77`) gains an injected hook `onEntriesLoaded: (@MainActor ([RunHistoryEntry], String) async -> Void)?` (defaulted nil) that `AppState` sets to `mediaLookupStore.ingest(from:destinationRoot:)`. No other HistoryStore change.

## C-07 Revert presence (WP-05, safety-critical: INV-08) — `ui/Sources/ChronoframeCore/RevertExecutor.swift`

- `RevertExecutor` gains `presenceChecker: any FilesystemPresenceChecking = POSIXFilesystemPresenceChecker()` (init parameter, defaulted).
- At `:375–380`, replace `fileManager.fileExists` with `presenceChecker.presence(atPath:)`: `.missing` → `missingCount += 1` (as today); `.inaccessible` → new `unavailableCount += 1`, observer gets "Couldn't be checked (volume or folder unavailable)", **no deletion attempt**; `.exists` → continue to `safeRevert` unchanged.
- `RevertExecutionResult` (`:140–163`) gains `public let unavailableCount: Int` (defaulted 0 in its init). `revertedCount` semantics unchanged. The App's revert summary text includes "N couldn't be checked" when > 0 (`RunSessionStore` revert completion → where `missingCount` is rendered; the WP finds it with grep and lists the file).

## C-08 Receipt viewer and run surfaces — `ui/Sources/ChronoframeApp/Views/` (WP-06)

- `RunHistoryView.swift:918–923` `VerificationStatus` gains `.unavailable`; `verifyStatus(forDestination:expectedHash:fileManager:hasher:)` (`:1211–1217`) gains `presenceChecker:` and returns `.unavailable` for `.inaccessible`. Row label "Unavailable (volume or folder can't be reached)". `ReceiptVisualItem.sizeBytes` is filled by parsing `FileIdentity(rawValue: hash)?.size` at `:1169–1182`.
- New `ui/Sources/ChronoframeApp/Views/Run/RunOutcomeDetailSheet.swift`: given a `RunOutcomeRecord` URL (from `runSessionStore.artifacts.outcomeRecordPath`), loads off-main, shows a segmented filter over `RunItemOutcome` + "Excluded" + "Unassessed", a search field over `sourceName`, a `LazyVStack` of rows: source name, outcome badge (`MeridianStatusBadge`), destination path when present, presence (`MediaLookupPresenceEvaluator`), and a context menu "Reveal in Finder" (destination; source when no destination) via `FinderServicing.revealInFinder`. Header line: `RunOutcomeCopy.headline(record)` = "Every one of {items.count} selected items is accounted for." when `isComplete`, else "{unresolved} items are unresolved and {unassessedDirectories.count} folders couldn't be read, so this isn't a complete picture." Footer action for unresolved: "Preview Again" → `appState.startPreview()`.
- `CurrentRunView.swift:118–149` `RunOutcomeSummaryCard` gains a button "Account for Every Item" (identifier `run.outcome.detail`) enabled when `outcomeRecordPath != nil`, presenting the sheet.
- New `ui/Sources/ChronoframeApp/Views/History/MediaLookupView.swift` reachable from History via a `Picker` ("Artifacts" | "Files") above the existing list (`RunHistoryView.swift:128` area): search field bound to `query.nameContains`, optional source-folder and date filters, results list with outcome badge, destination path, presence label, "Reveal in Finder". Empty state: "No imported file matches. Chronoframe only knows about files it copied or planned in a recorded run." Identifiers `history.files.search`, `history.files.row`.
- `RunOutcomeCopy.swift` (pure): `headline(_:)`, `outcomeTitle(_:)` ("Copied and verified", "Already in destination", "Duplicate in selection", "Excluded", "Failed", "Skipped", "Changed before copy", "Unresolved"), `presenceTitle(_:)` ("Present", "Missing", "Unavailable", "—"), `exclusionTitle(_:)`.

## C-09 New invariant (G1, orchestrator appends after INV-29)

```markdown
- **INV-30:** Completion accounting is evidence-bound. A run outcome record marks an item `copiedVerified` only when the audit receipt lists it, reports unreadable subtrees and unresolved items explicitly instead of inferring success, and never reports a path as missing when it is inaccessible: presence is `exists`, `missing` or `inaccessible`, and revert, the receipt viewer and file lookup treat `inaccessible` as "couldn't be checked", not as absent.
```
Tests tagged `// AGENTS-INVARIANT: 30`; the revert change is also tagged `8`.

## C-10 Documentation (WP-07)
`docs/SAFETY_AND_RECOVERY.md` (outcome record, what "unresolved" means, presence states), `docs/TECHNICAL.md` (artifact table rows: `run_outcome_*.json` in destination; `lookup/index.db` in Application Support), `docs/FAQ.md` ("Where did IMG_1234 go?"), `README.md` "What You Can Do" row "Find where a photo went". Strings list `docs/plan/find-and-account/strings-app.txt`.
