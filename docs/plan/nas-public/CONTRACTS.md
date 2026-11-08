# NAS public — contracts

Plan prefix `NASP`. Branch `feature/nas-v1` (existing). Read `docs/plan/next-half/AGENT_RULES.md` first; `docs/plan/nas-v1/` remains the record of the v1 build and its contracts C-01…C-14 still bind. Line numbers refer to `feature/nas-v1` at `4b992a4`.

Goal: close the owner decisions in `docs/plan/nas-v1/FINAL_REPORT.md` that are agent work (items 1–5), so the branch is ready for the owner's hardware checks and release flag flip. Nothing here touches the flag's release value, StoreKit, or App Review.

## C-01 Deduplicate folder refusal — `ui/Sources/ChronoframeCore/NASDeduplicateFolderRefusal.swift` (WP-01, new, Core)

```swift
import Foundation

/// Deduplicate moves files to the macOS Trash. Trash on SMB/AFP/NFS mounts is unverified
/// (docs/NAS_REQUIREMENTS.md ADR-NAS-04), so Deduplicate refuses any folder that is not on a
/// local volume. `.unknown` is refused too (fail closed), matching the CLI (CLI.swift:536).
public enum NASDeduplicateFolderRefusal: LocalizedError, Equatable, Sendable {
    case notLocal(path: String, kind: NASVolumeKind)

    public static func refusal(for folder: URL, classifier: NASVolumeClassifier = .live) -> NASDeduplicateFolderRefusal? {
        let observation = classifier.classify(folder)
        return observation.kind == .local ? nil : .notLocal(path: folder.path, kind: observation.kind)
    }

    public var errorDescription: String? {
        switch self {
        case .notLocal:
            return NASCapability.isEnabled
                ? "Choose a folder on this Mac or an attached drive. Deduplicate can't move files on a network share to the Trash safely yet, so nothing was changed. For a NAS, use NAS Library."
                : "Choose a folder on this Mac or an attached drive. Deduplicate can't move files on a network share to the Trash safely yet, so nothing was changed."
        }
    }
}
```
Plain string literals, like `NASRemoteCopyError` (`NASModels.swift:353`). The `.xcstrings` key for each variant is added at G2.

## C-02 Engine refusal — `ui/Sources/ChronoframeAppCore/Services/DeduplicateEngine.swift` (WP-01)

In `NativeDeduplicateEngine`:
- Add, next to `networkAdvisory` (`:57–59`): `var volumeClassifier: NASVolumeClassifier = .live` (internal, test seam).
- `scan(_:)` (`:84`): after the `destinationMissing` guard (`:85–87`) and **before** `DestinationOperationLock.acquire` (`:90`): `if let refusal = NASDeduplicateFolderRefusal.refusal(for: destinationURL, classifier: volumeClassifier) { throw refusal }`. No lock is taken, no recovery runs, nothing is written.
- `commit(plan:configuration:)` (`:116`): same check as the first statement, before the lock re-acquire at `:122`.
- `networkAdvisory` and its warning stay in place (surgical change; see D-NASP-05).
- `DeduplicateSessionStore` is unchanged: a thrown scan error already lands as `status = .failed(error.localizedDescription)` (`DeduplicateSessionStore.swift:310–315`).

## C-03 App-layer refusal — `ui/Sources/ChronoframeApp/App/AppState.swift` (WP-01)

- Designated init (`:213–239`) gains `volumeClassifier: NASVolumeClassifier = .live` (stored `private let volumeClassifier`). The convenience/default construction path passes `.live`; `AppStateHarness.makeAppState` (test support) passes a stub.
- `chooseDeduplicateDestinationFolder()` (`:603–629`): after `validateFolder` succeeds and before `makeBookmark`, `if let refusal = NASDeduplicateFolderRefusal.refusal(for: url, classifier: volumeClassifier) { transientErrorMessage = UserFacingErrorMessage.message(for: refusal, context: .setup); return }`. The bookmark and `lastDeduplicateDestinationPath` are not written.
- `useDeduplicateHistoryFolder(_:)` (`:639–659`): same check after its validate; message set the same way.
- `startDeduplicateScan()` (`:683–700`): after the empty-destination guard, classify `URL(fileURLWithPath: deduplicateDestinationPath)`; on refusal set `transientErrorMessage` and return without calling `startScan`. This covers the fallback destinations in `deduplicateDestinationPath` (`:579–587`).
- `UserFacingErrorMessage.specificMessage` (`UserFacingErrorMessage.swift:176–211`) gains `case let error as NASDeduplicateFolderRefusal: return error.errorDescription`.

## C-04 `TransferExecutor.execute(queuedJobs:)` access — `ui/Sources/ChronoframeCore/TransferExecutor.swift:447` (WP-02, safety-critical)

Change `public func execute(queuedJobs:` to `func execute(queuedJobs:` (internal). No other line changes. Production has no callers (`FINAL_REPORT` item 2); tests use `@testable import ChronoframeCore` and keep compiling. Resolves D-NAS-115 by removing the policy-less entry point from the public surface.

## C-05 Workspace validate timeout and keeper save failure — `ui/Sources/ChronoframeAppCore/Stores/NASWorkspaceStore.swift` (WP-03)

- `validate(_ saved:)` (`:214`): wrap the `offMain { observe(url) }` call (`:232`) in the same 2-second gate `NASReconnectProbe` uses (`NASReconnectProbe.swift:41–56`, `ProbeGate`). Make the gate reusable: move `ProbeGate` to `internal` scope in `NASReconnectProbe.swift` if it is `private`, or add `static func observeWithTimeout(_ url: URL, observe:, timeoutSeconds: Double = 2.0) async -> NASLibraryObservation??` (outer nil = timed out). On timeout: `enterWaitingForNAS()` exactly as the unresolved-bookmark branch (`:220`) does. Bookmark resolution (`:220`) stays on the main actor (it is fast; D-NASP-06).
- `chooseKeeper(digest:relativePath:)` (`:461–473`): on save failure, keep the current results state and set a new `@Published public private(set) var keeperSaveMessage: String?` to `"Chronoframe couldn't save that choice. Your library and the assessment weren't changed. Try again."`; clear it on the next successful `chooseKeeper`. The `.failed` transition at `:468–472` is removed for this path only.
- `NASLibraryView.swift` shows `keeperSaveMessage` as a one-line status under the keeper controls when non-nil (owned by WP-03 as well: file `ui/Sources/ChronoframeApp/Views/NAS/NASLibraryView.swift`, add the `Text` only; copy constant added to `NASLibraryCopy`).

## C-06 Lock doc comment — `ui/Sources/ChronoframeCore/DestinationOperationLock.swift:99–103` (WP-04, comment-only change in a safety-critical file)

Replace the five comment lines with:
```swift
    /// Whether `destinationRoot` lives on a non-local (network) volume. The
    /// cross-process `flock` lock only reliably guards same-machine access; on
    /// SMB/AFP mounts two machines could both proceed. Callers use this to warn
    /// the user. Since NAS v1, `acquire` also classifies the volume and takes a
    /// per-share Application Support lease when it is not local (see
    /// `acquireShareCompanion`). An unreadable or unknown volume attribute is
    /// treated as **local** here so the app never warns spuriously.
```
No code line changes.

## C-07 Contract errata — `docs/plan/nas-v1/CONTRACTS.md` (WP-04)

Append a section `## Errata (post-G3)` listing, each as one bullet quoting the decision ID and the code location: D-NAS-118 (CLI classifies a named profile's destination, `CLI.swift:536`), D-NAS-120 (P07 uses `BEGIN EXCLUSIVE`), D-NAS-124 (probe placed in `chooseLibrary`, and the WP-03 validate timeout), D-NAS-134 (lease-folder failure fails closed). Text of each decision copied from `docs/plan/nas-v1/DECISIONS.md:108, :112, :120, :140`.

## C-08 Documentation (WP-04)

- `README.md` "Safety First" bullet 7 (`:39`) gains the sentence: "Deduplicate works on folders on this Mac or an attached drive; it refuses folders on a network share because recoverable Trash there is unverified."
- `docs/FAQ.md`: "Can I deduplicate a folder on my NAS?" → No for now; the exact C-01 copy; NAS Library assesses read-only.
- `docs/TROUBLESHOOTING.md`: entry for the refusal text.
- `docs/TECHNICAL.md:124` keeps saying the flag is off; add one sentence that Deduplicate refuses non-local folders via `NASDeduplicateFolderRefusal`.
- `docs/plan/nas-v1/ACCEPTANCE_MATRIX.md:36` gate 6 note: replace the D-NAS-135 caveat with "closed by NASP WP-01 (<commit>)" (orchestrator fills the hash at G2 via cf-data-entry).

## C-09 Strings added at G2 (orchestrator)

Run `add_xcstrings_keys.py` on `ui/Sources/ChronoframeApp/Resources/Localizable.xcstrings` with every literal in `NASLibraryCopy` (`NASLibraryView.swift:15–49`), `NASAccessibilityText.swift` (`:30–40, :63, :77–79`) and the new keeper message; on `ui/Sources/ChronoframeAppCore/Resources/LocalizableCore.xcstrings` with the `String(localized:)` literals in `NASWorkspaceStore.swift` (`:113, :118, :509, :520–530`) and both C-01 variants. The implementer of WP-04 writes the two key lists to `docs/plan/nas-public/strings-app.txt` and `strings-core.txt` (one literal per line, exact).
