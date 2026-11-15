# Dedupe persistence — contracts

Plan prefix `DDP`. Read `docs/plan/next-half/AGENT_RULES.md` first. Line numbers refer to `main` after `feature/nas-v1` merges; if a line moved, search for the quoted declaration.

Goal: a Deduplicate review that survives quitting the app. Decisions, reviewed groups and the current position are saved per folder, restored only where the file content is unchanged, and Trash still requires the same explicit commit. The planner (`DeduplicationPlanner.plan`) and executor are not changed.

Facts this design rests on (verified 2026-11-07): `DuplicateCluster.id` is a fresh `UUID()` on every scan (`DuplicateClusterer.swift:142, :169`); `DedupeDecisions` and `DuplicateCluster` are not Codable (`DeduplicateModels.swift:554–586, :344`); every deletable path has a `FileIdentity` in `summary.scanSnapshot.identitiesByPath` (`DeduplicateScanner.swift:518–521`); scan results are never persisted; the store already has in-memory pause/resume (`DeduplicateSessionStore.swift:501–519`).

## C-01 Saved review model — `ui/Sources/ChronoframeCore/DeduplicateReviewSnapshot.swift` (WP-01, new, Core)

```swift
import Foundation

public struct DeduplicateSavedDecision: Equatable, Codable, Sendable {
    public let path: String
    public let identity: FileIdentity        // content at the time of the decision
    public let decision: DedupeDecision
    public init(path: String, identity: FileIdentity, decision: DedupeDecision)
}

/// A reviewed group, keyed by the sorted member identities so it survives new cluster UUIDs.
public struct DeduplicateSavedGroupApproval: Equatable, Codable, Sendable {
    public let groupKey: String              // DeduplicateReviewKeys.groupKey(memberIdentities:)
    public let memberCount: Int
    public init(groupKey: String, memberCount: Int)
}

public struct DeduplicateReviewSnapshot: Equatable, Codable, Sendable {
    public static let version = 1
    public let version: Int
    public let folderPath: String            // standardized path of the dedupe root
    public let savedAt: Date
    public let configurationFingerprint: String   // DeduplicateConfiguration.reviewFingerprint
    public let decisions: [DeduplicateSavedDecision]
    public let approvals: [DeduplicateSavedGroupApproval]
    public let focusGroupKey: String?        // where the user was
    public init(folderPath: String, savedAt: Date, configurationFingerprint: String,
                decisions: [DeduplicateSavedDecision], approvals: [DeduplicateSavedGroupApproval], focusGroupKey: String?)
    public var isEmpty: Bool { decisions.isEmpty && approvals.isEmpty }
}

public enum DeduplicateReviewKeys {
    /// Sorted `FileIdentity.rawValue`s joined by "\n". Deterministic for any member order.
    public static func groupKey(memberIdentities: [FileIdentity]) -> String
    /// nil when any member lacks an identity in the snapshot (such a group can never be approved from a save).
    public static func groupKey(for cluster: DuplicateCluster, snapshot: DeduplicateScanSnapshot) -> String?
    /// Standardized dedupe root path, the key for the on-disk file (see C-03).
    public static func folderKey(for folderPath: String) -> String   // base64url of URL(fileURLWithPath:).standardizedFileURL.path, no padding
}

public extension DeduplicateConfiguration {
    /// Stable text of every field except `workerCount`, joined by "|" in declaration order; SHA-256 hex via CryptoKit.
    var reviewFingerprint: String { get }
}
```

## C-02 Restorer — `ui/Sources/ChronoframeCore/DeduplicateReviewRestorer.swift` (WP-01, new, Core, pure)

```swift
public struct DeduplicateReviewRestoration: Equatable, Sendable {
    public let decisions: DedupeDecisions           // suggested decisions overlaid with restored ones
    public let approvedClusterIDs: Set<UUID>
    public let focusClusterID: UUID?
    public let restoredDecisionCount: Int
    public let droppedDecisionCount: Int            // path missing from scan, or identity differs
    public let restoredGroupCount: Int
    public let changedGroupCount: Int               // saved approval whose groupKey no longer matches any cluster
    public let settingsChanged: Bool                // fingerprint differs
    public let savedAt: Date
}

public enum DeduplicateReviewRestorer {
    /// Rules:
    /// 1. Start from `suggested` (the store's suggestedDecisions(for:)).
    /// 2. For each saved decision: if `snapshot.identitiesByPath[path] == identity` and the path is a member of some cluster → set byPath[path] = decision, restored += 1; else dropped += 1.
    /// 3. For each cluster: key = groupKey(for:snapshot:); if key != nil and approvals contains key with the same memberCount → approvedClusterIDs.insert(cluster.id), restoredGroup += 1.
    ///    changedGroupCount = approvals.count − restoredGroupCount.
    /// 4. A cluster is approved only if every member that had a saved decision was restored; if any member's decision was dropped, the cluster is NOT approved (it needs another look) even if its key matched. (Keys are identity-based so this can only happen with duplicate paths; implement it anyway.)
    /// 5. focusClusterID = the cluster whose key == focusGroupKey, else nil.
    /// 6. `hardDelete` stays false; `pairKeepOverrides` stays as in `suggested`.
    public static func restore(snapshot saved: DeduplicateReviewSnapshot,
                               clusters: [DuplicateCluster],
                               scanSnapshot: DeduplicateScanSnapshot,
                               suggested: DedupeDecisions,
                               currentFingerprint: String) -> DeduplicateReviewRestoration

    /// Inverse: build a snapshot from live state. Decisions without an identity in the scan snapshot are omitted (they could never be restored).
    public static func capture(folderPath: String, savedAt: Date, configuration: DeduplicateConfiguration,
                               decisions: DedupeDecisions, approvedClusterIDs: Set<UUID>,
                               clusters: [DuplicateCluster], scanSnapshot: DeduplicateScanSnapshot,
                               focusClusterID: UUID?) -> DeduplicateReviewSnapshot
}
```
Restoration touches review state only. It never produces a `DeduplicationPlan`, never calls the executor, and the restored `approvedClusterIDs` still go through `reviewedDeletionPlan()` → `prepareReviewedCommitPlan()` → the existing confirmation dialog.

## C-03 Snapshot store — `ui/Sources/ChronoframeAppCore/Services/DeduplicateReviewSnapshotStore.swift` (WP-02, new)

```swift
public protocol DeduplicateReviewSnapshotStoring: Sendable {
    func load(folderPath: String) -> DeduplicateReviewSnapshot?      // nil: missing, corrupt, wrong version
    func save(_ snapshot: DeduplicateReviewSnapshot) throws
    func remove(folderPath: String)
}

public struct DeduplicateReviewFileSnapshotStore: DeduplicateReviewSnapshotStoring {
    public static func defaultDirectory() -> URL   // RuntimePaths.applicationSupportDirectory()/dedupe_reviews
    public init(directory: URL = DeduplicateReviewFileSnapshotStore.defaultDirectory())
    // file: <directory>/<DeduplicateReviewKeys.folderKey(folderPath)>.json
    // save: createDirectory(withIntermediateDirectories:), JSONEncoder(.iso8601, [.sortedKeys, .prettyPrinted]), Data.write(.atomic). Empty snapshot → remove instead of save.
    // load: JSONDecoder(.iso8601); any error or version mismatch → nil.
}
```
Lives under Application Support, never inside the dedupe root (the root may be read-only, external, or a plain folder the user does not expect us to write into beyond `.organize_cache.db`).

## C-04 Session store integration — `ui/Sources/ChronoframeAppCore/Stores/DeduplicateSessionStore.swift` (WP-02)

New init parameters (appended, defaulted): `reviewSnapshotStore: any DeduplicateReviewSnapshotStoring = DeduplicateReviewFileSnapshotStore()`, `now: @escaping @Sendable () -> Date = Date.init`, `saveDebounceNanoseconds: UInt64 = 500_000_000`.

New published state (`public private(set)`):
```swift
@Published var restoredReview: DeduplicateReviewRestoration?     // set on restore; cleared by reset()/startScan()
@Published var savedReviewForCurrentFolder: DeduplicateReviewSnapshot?   // for the idle card; refreshed by refreshSavedReview(folderPath:)
@Published public var reviewFocusClusterID: UUID?                 // the view writes it; captured into the snapshot
```

Behavior:
1. `consume(.complete(summary))` (`:556–586`): after `decisions = DedupeDecisions(byPath: suggested.byPath)` and `approvedClusterIDs = []`, if `reviewSnapshotStore.load(folderPath: configuration.destinationPath)` returns a snapshot: call `DeduplicateReviewRestorer.restore(...)` with `currentFingerprint: configuration.reviewFingerprint`; assign `decisions`, `approvedClusterIDs`, `reviewFocusClusterID = focusClusterID`, `restoredReview = restoration`. Register no undo for the restore.
2. `setDecision`, `approveCluster`, `acceptSuggestionsForCluster`, `keepAllInCluster`, `deleteAllInCluster`, `acceptAllSuggestions`, `acceptAllHighConfidence`, undo/redo restoration (`registerUndo` closures) → call `scheduleSave()`. `scheduleSave` cancels the pending task and starts a new one that sleeps `saveDebounceNanoseconds` then calls `saveNow()`.
3. `saveNow()`: guard `status == .readyToReview || status == .idle && hasPausedReview`, `summary != nil`, `lastScanConfiguration != nil`; `capture(...)` and `try? reviewSnapshotStore.save`. Errors are swallowed silently here (saving is best-effort) but recorded in `lastErrorMessage` **only** when the next commit is attempted? No: keep it silent; D-DDP-07.
4. `pauseReview()` and `cancel()` → `saveNow()` first (synchronous, no debounce). `public func flushPendingReviewSave()` → cancels the debounce task and calls `saveNow()`; `AppState` calls it on app termination (C-06).
5. `consumeCommit(.complete)` (`:588–634`) → `reviewSnapshotStore.remove(folderPath:)` for the committed folder, `restoredReview = nil`, `savedReviewForCurrentFolder = nil`.
6. `reset()` (`:521`) → `saveNow()` **before** clearing (abandoning a review must not lose it), then clear in-memory state including `restoredReview` and `reviewFocusClusterID`. `startScan` clears `restoredReview` and `reviewFocusClusterID`.
7. `public func refreshSavedReview(folderPath: String)` sets `savedReviewForCurrentFolder = reviewSnapshotStore.load(folderPath:)`. `public func discardSavedReview(folderPath: String)` removes the file and sets it to nil.
8. `public var hasRestoredChanges: Bool { (restoredReview?.changedGroupCount ?? 0) > 0 || (restoredReview?.droppedDecisionCount ?? 0) > 0 }`.

## C-05 Deduplicate UI — `ui/Sources/ChronoframeApp/Views/Deduplicate/` (WP-03)

New file `DeduplicateRestoredReviewBanner.swift`:
```swift
struct DeduplicateRestoredReviewBanner: View {
    let restoration: DeduplicateReviewRestoration
    let onDismiss: () -> Void
    // DarkroomPanel(variant: .inset). Title: DeduplicateReviewCopy.restoredTitle. Body: DeduplicateReviewCopy.restoredBody(restoration). When settingsChanged: DeduplicateReviewCopy.settingsChanged line. Dismiss "xmark" button (identifier dedupeRestoredBannerDismiss).
}
```
New file `DeduplicateSavedReviewCard.swift` (idle view, shown when `savedReviewForCurrentFolder != nil && !hasPausedReview`):
```swift
struct DeduplicateSavedReviewCard: View {
    let snapshot: DeduplicateReviewSnapshot
    let resume: () -> Void      // = startScan(); restore happens on completion
    let discard: () -> Void
    // Title "Pick up where you left off". Body DeduplicateReviewCopy.savedBody(snapshot). Buttons "Scan and Restore Review" (id dedupeSavedReviewResume), "Discard Saved Review" (id dedupeSavedReviewDiscard).
}
```
New file `DeduplicateReviewCopy.swift` (pure, tested):
```swift
enum DeduplicateReviewCopy {
    static let restoredTitle = "Your earlier review was restored."
    static func restoredBody(_ r: DeduplicateReviewRestoration) -> String
    // "{restoredDecisionCount} choices across {restoredGroupCount} groups from {savedAt, month day hour:minute}." + when changedGroupCount > 0: " {changedGroupCount} groups changed since then and need another look." + when droppedDecisionCount > 0: " {droppedDecisionCount} files changed, so their choices were cleared."
    static let settingsChanged = "Deduplicate settings changed since that review; groups may differ."
    static func savedBody(_ s: DeduplicateReviewSnapshot) -> String
    // "{decisions.count} choices and {approvals.count} reviewed groups saved {savedAt, …}. Scanning again restores them for files that haven't changed. Nothing is moved to the Trash until you review and confirm."
}
```
`DeduplicateView.swift` edits: in `idleView` after `pausedReviewSection` (`:167`) add `savedReviewSection`; in the `.readyToReview` body, show the banner above the cluster list while `sessionStore.restoredReview != nil`; on appear and whenever `appState.deduplicateDestinationPath` changes call `sessionStore.refreshSavedReview(folderPath:)`; in the existing focus logic (`alignFocusWithVisibleClusters`, around `:886–890` and wherever the selected cluster is stored) select `sessionStore.reviewFocusClusterID` when non-nil on first appearance after restore, and write the current selection back to `sessionStore.reviewFocusClusterID` when it changes. `AccessibilityIdentifiers.swift` gains the four identifiers above as `"dedupe.restored.dismiss"`, `"dedupe.saved.resume"`, `"dedupe.saved.discard"`, plus `"dedupe.restored.banner"`.

## C-06 App wiring — `ui/Sources/ChronoframeApp/App/AppState.swift` (WP-03)

- On `NSApplication.willTerminateNotification` (observe in `AppState` init, store the token) → `deduplicateSessionStore.flushPendingReviewSave()`.
- `resetDeduplicate()` (`:721–723`) is unchanged (store's `reset()` now saves first).

## C-07 New invariant text (G1, orchestrator appends to `AGENTS.md` under `## Safety Invariants`, after INV-28)

```markdown
- **INV-29:** Saved Deduplicate review state (`Application Support/Chronoframe/dedupe_reviews/*.json`) is review state only. On restore, a saved Keep/Delete choice applies to a path only when the current scan identity equals the saved identity, and a saved group approval applies only when the group's member identities are unchanged; everything else is dropped and reported. Restoring never builds a plan, never pre-approves a commit, and never bypasses the reviewed-plan confirmation.
```
Tests covering it carry `// AGENTS-INVARIANT: 29`.

## C-08 Strings (G2) — every literal in `DeduplicateReviewCopy` and the two button titles get English keys in `Localizable.xcstrings` via `add_xcstrings_keys.py`; the WP-04 implementer writes `docs/plan/dedupe-persistence/strings-app.txt`.

## C-09 Documentation (WP-04)
- `docs/SAFETY_AND_RECOVERY.md`: "Saved Deduplicate reviews" subsection: location, what restores, what is dropped, that commit is unchanged, how to discard.
- `docs/FAQ.md`: "I quit halfway through reviewing duplicates. Is my work gone?"
- `docs/TECHNICAL.md`: artifact table row for `dedupe_reviews/<key>.json` (Application Support).
- `AGENTS.md` "Deduplicate Workspace" section: one sentence pointing at INV-29 (orchestrator, G1).
