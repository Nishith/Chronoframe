#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Combine
import Foundation

public enum NASWorkspaceState: Equatable, Sendable {
    case noLibrary
    case checkingConnection
    case needsIdentityConfirmation([NASIdentityMismatchReason])
    case differentFolder([NASIdentityMismatchReason])
    case waitingForNAS
    case ready
    case assessing(NASAssessmentPhase)
    case stopping
    case completeAssessment
    case incompleteAssessment(NASScanOutcome)
    case failed(String)
}

/// Drives the NAS Library workspace. It reads and assesses a library on a network share and
/// keeps review notes on this Mac. Nothing here deletes, moves or trashes a file on the NAS
/// (INV-27): a saved keeper choice is a note, never an instruction to change anything.
@MainActor
public final class NASWorkspaceStore: ObservableObject {
    @Published public private(set) var state: NASWorkspaceState = .noLibrary
    @Published public private(set) var library: NASLibraryRecord?
    @Published public private(set) var snapshot: NASAssessmentSnapshot?
    @Published public private(set) var progress: (directories: Int, files: Int, hashed: Int, hashTotal: Int, currentRelativePath: String) =
        (directories: 0, files: 0, hashed: 0, hashTotal: 0, currentRelativePath: "")
    @Published public private(set) var previewRequestedDigests: Set<String> = []
    /// Set when a keeper choice couldn't be saved; cleared by the next choice that saves.
    @Published public private(set) var keeperSaveMessage: String?

    private let engine: any NASAssessmentEngine
    private let registry: NASLibraryRegistry
    private let folderAccess: any FolderAccessServicing
    private let observe: @Sendable (URL) -> NASLibraryObservation?
    private let now: () -> Date

    /// The folder the saved bookmark resolved to when the connection was last validated.
    private var resolvedRootURL: URL?
    /// What the share looked like when it needed the user's confirmation.
    private var pendingObservation: NASLibraryObservation?
    private var securityScope: SecurityScopedFolderAccess?
    private var streamTask: Task<Void, Never>?
    /// Bumped whenever a newer validation or run supersedes an in-flight one, so a late
    /// answer from the older one is dropped.
    private var epoch: UInt64 = 0

    public init(
        engine: any NASAssessmentEngine,
        registry: NASLibraryRegistry,
        folderAccess: any FolderAccessServicing,
        observe: @escaping @Sendable (URL) -> NASLibraryObservation? = { NASLibraryIdentity.observe(rootURL: $0) },
        now: @escaping () -> Date = Date.init
    ) {
        self.engine = engine
        self.registry = registry
        self.folderAccess = folderAccess
        self.observe = observe
        self.now = now
    }

    // MARK: - Choosing and validating a library

    /// Shows the first saved library (one library at a time, D-NAS-52) and checks the share.
    public func loadSavedLibrary() async {
        guard !isAssessingOrStopping else { return }
        keeperSaveMessage = nil
        let records: [NASLibraryRecord]
        do {
            records = try registry.load()
        } catch {
            state = .failed(Self.message(for: error))
            return
        }
        guard let first = records.first else {
            library = nil
            snapshot = nil
            state = .noLibrary
            return
        }
        library = first
        snapshot = nil
        await validate(first)
    }

    /// Opens the folder picker. A folder that is not on a network share is refused (D-NAS-22).
    public func chooseLibrary() async {
        guard !isAssessingOrStopping else { return }
        let startPath = await validatedPickerStartPath()
        guard let url = folderAccess.chooseFolder(
            startingAt: startPath,
            prompt: "Choose Folder",
            allowNetworkStart: true
        ) else { return }

        let bookmark: FolderBookmark
        do {
            bookmark = try folderAccess.makeBookmark(for: url, key: "nasLibrary")
        } catch {
            state = .failed(Self.message(for: error))
            return
        }

        epoch &+= 1
        let currentEpoch = epoch
        state = .checkingConnection
        let scope = folderAccess.scopedAccess(for: [bookmark])
        let observed = await offMain { [observe] in observe(url) }
        guard currentEpoch == epoch else { scope.close(); return }

        guard let observed else {
            scope.close()
            state = .failed(String(localized: "Chronoframe can't use this folder. Choose a regular folder on a network share, not a link. Nothing was changed.", bundle: Bundle.module))
            return
        }
        guard observed.volume.kind == .remote else {
            scope.close()
            state = .failed(String(localized: "Choose a folder on a network share. For folders on this Mac, use Deduplicate.", bundle: Bundle.module))
            return
        }

        // The same library chosen again keeps its identity (and so its saved choices). A folder
        // that only looks slightly different (D-NAS-30) waits for the user's confirmation, the
        // same as a saved library would. Anything that failed identity checks is a new library
        // (D-NAS-31).
        var keptRecord: NASLibraryRecord?
        if let existing = library {
            switch NASLibraryIdentity.compare(recorded: existing.lastObservation, observed: observed) {
            case .same, .remounted:
                var kept = existing
                kept.bookmark = bookmark
                kept.lastObservation = observed
                kept.lastValidatedAt = now()
                keptRecord = kept
            case let .ambiguous(reasons):
                // Nothing is saved until confirmIdentity(), which keeps the UUID and the choices.
                var pending = existing
                pending.bookmark = bookmark
                securityScope?.close()
                securityScope = scope
                library = pending
                resolvedRootURL = url
                pendingObservation = observed
                state = .needsIdentityConfirmation(reasons)
                return
            case .mismatch:
                keptRecord = nil
            }
        }
        let record = keptRecord ?? {
            let name = url.lastPathComponent
            return NASLibraryRecord(
                libraryUUID: UUID().uuidString,
                displayName: name.isEmpty ? "NAS Library" : name,
                bookmark: bookmark,
                lastObservation: observed,
                lastValidatedAt: now()
            )
        }()

        do {
            try registry.upsert(record)
            if let previous = library, previous.libraryUUID != record.libraryUUID {
                try registry.remove(libraryUUID: previous.libraryUUID)
            }
        } catch {
            scope.close()
            state = .failed(Self.message(for: error))
            return
        }

        if library?.libraryUUID != record.libraryUUID {
            snapshot = nil
            keeperSaveMessage = nil
            previewRequestedDigests = []
        }
        securityScope?.close()
        securityScope = scope
        library = record
        resolvedRootURL = url
        pendingObservation = nil
        await settleAfterReady(epoch: currentEpoch)
    }

    /// Accepts the share as the same library after the user confirmed it.
    public func confirmIdentity() async {
        guard case .needsIdentityConfirmation = state,
              var record = library,
              let observed = pendingObservation
        else { return }
        record.lastObservation = observed
        record.lastValidatedAt = now()
        do {
            try registry.upsert(record)
        } catch {
            state = .failed(Self.message(for: error))
            return
        }
        library = record
        pendingObservation = nil
        epoch &+= 1
        await settleAfterReady(epoch: epoch)
    }

    /// Checks the saved library's share again.
    public func reconnect() async {
        guard !isAssessingOrStopping else { return }
        guard let library else {
            await loadSavedLibrary()
            return
        }
        await validate(library)
    }

    private func validate(_ saved: NASLibraryRecord) async {
        epoch &+= 1
        let currentEpoch = epoch
        state = .checkingConnection
        pendingObservation = nil
        keeperSaveMessage = nil

        guard let resolved = folderAccess.resolveBookmark(saved.bookmark) else {
            enterWaitingForNAS()
            return
        }
        var record = saved
        if let refreshed = resolved.refreshedBookmark {
            record.bookmark = refreshed
        }
        securityScope?.close()
        securityScope = folderAccess.scopedAccess(for: [record.bookmark])
        let url = resolved.url

        let observedOrTimedOut = await NASReconnectProbe.observeWithTimeout(url, observe: observe)
        guard currentEpoch == epoch else { return }
        // Outer nil: the share didn't answer in time. Inner nil: it answered with nothing.
        guard let answered = observedOrTimedOut, let observed = answered else {
            enterWaitingForNAS()
            return
        }

        switch NASLibraryIdentity.compare(recorded: record.lastObservation, observed: observed) {
        case .same:
            record.lastValidatedAt = now()
            guard persist(record) else { return }
        case .remounted:
            record.lastObservation = observed
            record.lastValidatedAt = now()
            guard persist(record) else { return }
        case let .ambiguous(reasons):
            library = record
            resolvedRootURL = url
            pendingObservation = observed
            state = .needsIdentityConfirmation(reasons)
            return
        case let .mismatch(reasons):
            // Another library's results and notes must not stay editable under this state (NAS-CON-03).
            library = record
            resolvedRootURL = nil
            snapshot = nil
            previewRequestedDigests = []
            state = .differentFolder(reasons)
            return
        }

        resolvedRootURL = url
        await settleAfterReady(epoch: currentEpoch)
    }

    private func persist(_ record: NASLibraryRecord) -> Bool {
        do {
            try registry.upsert(record)
            library = record
            return true
        } catch {
            state = .failed(Self.message(for: error))
            return false
        }
    }

    private func enterWaitingForNAS() {
        resolvedRootURL = nil
        securityScope?.close()
        securityScope = nil
        state = .waitingForNAS
    }

    /// Loads the library's latest saved result and lands in the matching resting state.
    private func settleAfterReady(epoch currentEpoch: UInt64) async {
        guard let library else { return }
        let engine = engine
        do {
            let latest = try await offMainThrowing { try engine.latestSnapshot(for: library) }
            guard currentEpoch == epoch else { return }
            apply(latest)
        } catch {
            guard currentEpoch == epoch else { return }
            state = .failed(Self.message(for: error))
        }
    }

    private func apply(_ latest: NASAssessmentSnapshot?) {
        keeperSaveMessage = nil
        guard var latest else {
            snapshot = nil
            state = .ready
            return
        }
        latest.issues = latest.issues.map(Self.plainIssue)
        snapshot = latest
        state = Self.restingState(for: latest.summary.outcome)
    }

    /// The state for a saved result once the share is reachable again.
    private static func restingState(for outcome: NASScanOutcome) -> NASWorkspaceState {
        outcome == .complete ? .completeAssessment : .incompleteAssessment(outcome)
    }

    /// The picker opens where the saved library lives, but only when the share answers in
    /// time; otherwise it opens at the default location.
    private func validatedPickerStartPath() async -> String? {
        guard let library else { return nil }
        let observe = observe
        return await NASReconnectProbe.validatedStartPath(
            for: library,
            resolve: { bookmark in
                var isStale = false
                return try? URL(
                    resolvingBookmarkData: bookmark.data,
                    options: [.withSecurityScope, .withoutUI],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                )
            },
            observe: { url in
                let started = url.startAccessingSecurityScopedResource()
                defer { if started { url.stopAccessingSecurityScopedResource() } }
                return observe(url)
            }
        )
    }

    // MARK: - Assessment

    public func startAssessment() {
        switch state {
        case .ready, .completeAssessment, .incompleteAssessment:
            break
        default:
            return
        }
        guard let library, let rootURL = resolvedRootURL else { return }

        progress = (directories: 0, files: 0, hashed: 0, hashTotal: 0, currentRelativePath: "")
        keeperSaveMessage = nil
        epoch &+= 1
        let runEpoch = epoch
        let stream: AsyncThrowingStream<NASAssessmentEvent, Error>
        do {
            stream = try engine.assess(library, rootURL: rootURL)
        } catch {
            state = .failed(Self.message(for: error))
            return
        }
        state = .assessing(.enumerating)

        streamTask?.cancel()
        streamTask = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self else { return }
                    guard runEpoch == self.epoch else { return }
                    await self.handle(event, runEpoch: runEpoch)
                }
                await self?.streamEnded(runEpoch: runEpoch)
            } catch {
                self?.streamFailed(error, runEpoch: runEpoch)
            }
        }
    }

    public func stop() {
        guard case .assessing = state else { return }
        state = .stopping
        engine.cancel()
    }

    private func handle(_ event: NASAssessmentEvent, runEpoch: UInt64) async {
        switch event {
        case .started, .issue:
            break
        case let .phaseStarted(phase):
            if case .assessing = state { state = .assessing(phase) }
        case let .enumerationProgress(directories, files, path):
            progress.directories = directories
            progress.files = files
            progress.currentRelativePath = path
        case let .hashingProgress(completed, total, _):
            progress.hashed = completed
            progress.hashTotal = total
        case let .finished(summary):
            await finishRun(with: summary.outcome, runEpoch: runEpoch)
        }
    }

    private func finishRun(with outcome: NASScanOutcome, runEpoch: UInt64) async {
        guard let library else { return }
        let engine = engine
        do {
            let latest = try await offMainThrowing { try engine.latestSnapshot(for: library) }
            guard runEpoch == epoch else { return }
            if var latest {
                latest.issues = latest.issues.map(Self.plainIssue)
                snapshot = latest
            }
            // A run that lost the share waits for Reconnect instead of showing a result.
            state = outcome == .interruptedVolumeUnavailable ? .waitingForNAS : Self.restingState(for: outcome)
        } catch {
            guard runEpoch == epoch else { return }
            state = .failed(Self.message(for: error))
        }
    }

    private func streamEnded(runEpoch: UInt64) async {
        guard runEpoch == epoch else { return }
        switch state {
        case .assessing, .stopping:
            // The run ended without a final event; show whatever was saved.
            await settleAfterReady(epoch: runEpoch)
        default:
            break
        }
    }

    private func streamFailed(_ error: Error, runEpoch: UInt64) {
        guard runEpoch == epoch else { return }
        state = .failed(Self.message(for: error))
    }

    /// Review notes are only edited while a saved result is on screen.
    private var showsResults: Bool {
        switch state {
        case .completeAssessment, .incompleteAssessment: return true
        default: return false
        }
    }

    private var isAssessingOrStopping: Bool {
        switch state {
        case .assessing, .stopping: return true
        default: return false
        }
    }

    // MARK: - Review

    /// Remembers which group is selected. Selecting never reads a file for display.
    public func select(digest: String?) {
        guard let library, showsResults else { return }
        snapshot?.selectedDigest = digest
        // Best effort: losing the remembered selection costs nothing.
        try? engine.saveSelectedDigest(digest, for: library)
    }

    /// Shown under the keeper controls; `NASLibraryCopy.keeperSaveFailed` carries the same words.
    static let keeperSaveFailedMessage = "Chronoframe couldn't save that choice. Your library and the assessment weren't changed. Try again."

    /// Saves which copy the user prefers to keep. It is a note on this Mac and changes nothing on the NAS.
    public func chooseKeeper(digest: String, relativePath: String?) {
        guard let library, showsResults, let group = snapshot?.groups.first(where: { $0.digest == digest }) else { return }
        if let relativePath, !group.memberRelativePaths.contains(relativePath) { return }
        let choice = NASReviewChoice(digest: digest, size: group.size, keeperRelativePath: relativePath, reviewedAt: now())
        do {
            try engine.saveChoice(choice, for: library)
            snapshot?.choices[digest] = choice
            keeperSaveMessage = nil
        } catch {
            keeperSaveMessage = Self.keeperSaveFailedMessage
        }
    }

    /// The only way a preview is asked for. The caller renders after this returns.
    public func requestPreview(digest: String) {
        guard let library, showsResults, previewRequestedDigests.insert(digest).inserted else { return }
        // The counter is a metric; failing to count must not block the preview.
        try? engine.recordPreviewRequest(for: library)
    }

    /// True when a keeper was chosen but is no longer one of the group's files.
    public func isChoiceStale(_ group: NASExactGroup) -> Bool {
        guard let keeper = snapshot?.choices[group.digest]?.keeperRelativePath else { return false }
        return !group.memberRelativePaths.contains(keeper)
    }

    // MARK: - Helpers

    private func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }

    private func offMainThrowing<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    /// Plain text for a failure. Raw system errors from the local assessment data are never shown.
    private static func message(for error: Error) -> String {
        if (error as NSError).domain == NSPOSIXErrorDomain {
            return String(localized: "Chronoframe couldn't open its assessment data on this Mac. Nothing on the NAS was changed.", bundle: Bundle.module)
        }
        return UserFacingErrorMessage.message(for: error)
    }

    /// The scanner records the reason a file couldn't be read as raw text; show a sentence instead.
    private static func plainIssue(_ issue: NASIssue) -> NASIssue {
        guard issue.category == .unresolvedCandidate else { return issue }
        var plain = issue
        switch NASUnresolvedReason(rawValue: issue.detail) {
        case .notRegularFile?:
            plain.detail = String(localized: "This item stopped being a regular file, so Chronoframe didn't read it.", bundle: Bundle.module)
        case .openFailed?:
            plain.detail = String(localized: "Chronoframe couldn't open this file.", bundle: Bundle.module)
        case .sizeChangedBeforeRead?, .modificationTimeChanged?, .sizeChangedDuringRead?:
            plain.detail = String(localized: "This file changed while Chronoframe was checking it, so it wasn't compared.", bundle: Bundle.module)
        case .readFailed?, .bytesConsumedMismatch?:
            plain.detail = String(localized: "Chronoframe couldn't finish reading this file, so it wasn't compared.", bundle: Bundle.module)
        case .volumeUnavailable?:
            plain.detail = String(localized: "The NAS became unavailable while Chronoframe was reading this file.", bundle: Bundle.module)
        case nil:
            plain.detail = String(localized: "Chronoframe couldn't check this file, so it wasn't compared.", bundle: Bundle.module)
        }
        return plain
    }
}
