import AppKit
import Combine
#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation

/// Process-wide trial composition.
///
/// Deliberately outside `AppState`: the reconciler provider is a `@Sendable`,
/// non-isolated closure, and it must be able to reach the ledger without
/// hopping to the main actor. A `static let` of a `Sendable` type here is
/// reachable from both.
private enum TrialComposition {
    /// One ledger per process, opened on first use.
    ///
    /// A corrupt or unopenable ledger degrades to a fail-closed stand-in
    /// reporting zero remaining, never a fresh allowance — see
    /// `TrialLedgerOpener`.
    /// Kept as the whole outcome, not just `.ledger`. The fail-closed stand-in
    /// for an unreadable ledger answers "zero remaining" rather than throwing —
    /// correct for a gate, and indistinguishable from a spent trial by the time
    /// it reaches the UI. `TrialStatus` needs to be told which one it is.
    static let openOutcome: TrialLedgerOpenOutcome = TrialLedgerOpener.openDefault()

    static var ledger: any TrialLedger { openOutcome.ledger }
    static var isReadable: Bool { openOutcome.failure == nil }

    /// Pair ledger reconciliation with destination recovery.
    ///
    /// Idempotent: `AppState` is built once in the app but repeatedly in tests,
    /// and re-assigning the provider is harmless.
    static func installReconciler() {
        DestinationRecovery.reconcilerProvider = { TrialLedgerReconciler(ledger: ledger) }
    }
}

@MainActor
final class AppState: ObservableObject {
    private static let deduplicateDestinationBookmarkKey = "deduplicate.destination"
    private static let guardianMirrorBookmarkKey = "guardian.mirror"

    @Published var selection: SidebarDestination
    @Published var organizeSubSelection: OrganizeSubSection
    @Published var settingsSelection: SettingsTab
    @Published var transientErrorMessage: String?

    var preferencesStore: PreferencesStore
    var setupStore: SetupStore
    var runLogStore: RunLogStore
    var historyStore: HistoryStore
    var runSessionStore: RunSessionStore
    var previewReviewStore: PreviewReviewStore
    var libraryHealthStore: LibraryHealthStore
    var deduplicateSessionStore: DeduplicateSessionStore
    var watchedSourcesStore: WatchedSourcesStore
    var photosImportStore: PhotosImportStore
    let guardianStore: GuardianStore

    /// Entitlement composed with the trial ledger.
    ///
    /// Created lazily and deliberately NOT refreshed at launch: refreshing calls
    /// StoreKit, and step 3 ships dark. The unlock UI (step 5) drives the first
    /// refresh, so today this holds `.loading` and changes nothing a user can
    /// observe.
    private(set) lazy var trialStatusStore = TrialStatusStore(
        ledger: TrialComposition.ledger,
        bookkeepingAvailable: TrialComposition.isReadable
    )

    private let folderAccessService: any FolderAccessServicing
    private let finderService: any FinderServicing
    private let profilesRepository: any ProfilesRepositorying
    private let watchedSourcesRepository: any WatchedSourcesRepositorying
    private let droppedItemStager: DroppedItemStager
    private let showSettingsWindowAction: @MainActor () -> Void
    private lazy var bookmarkPathResolver = BookmarkPathResolver(
        preferencesStore: preferencesStore,
        folderAccessService: folderAccessService
    )
    private lazy var setupCoordinator = SetupCoordinator(
        preferencesStore: preferencesStore,
        setupStore: setupStore,
        historyStore: historyStore,
        folderAccessService: folderAccessService,
        profilesRepository: profilesRepository,
        droppedItemStager: droppedItemStager,
        bookmarkPathResolver: bookmarkPathResolver,
        navigate: { [weak self] route in
            self?.navigate(to: route)
        },
        setTransientErrorMessage: { [weak self] message in
            self?.transientErrorMessage = message
        }
    )
    private lazy var runCoordinator = RunCoordinator(
        preferencesStore: preferencesStore,
        setupStore: setupStore,
        historyStore: historyStore,
        runSessionStore: runSessionStore,
        finderService: finderService,
        showSettingsWindowAction: showSettingsWindowAction,
        navigate: { [weak self] route in
            self?.navigate(to: route)
        },
        canStartRun: { [weak self] in
            self?.canStartRun ?? false
        },
        makeSecurityScope: { [weak self] _ in
            self?.organizeSecurityScope()
        },
        makeWatchedImportSecurityScope: { [weak self] context in
            self?.watchedImportSecurityScope(for: context)
        },
        makePhotosImportSecurityScope: { [weak self] context in
            self?.photosImportSecurityScope(for: context)
        },
        cleanupPhotosStaging: { [weak self] context in
            self?.photosImportStore.cleanupStaging(for: context)
        },
        reportTransientError: { [weak self] message in
            self?.transientErrorMessage = message
        }
    )
    private lazy var sourceWatchCoordinator = makeSourceWatchCoordinator()

    /// Built in a factory method with the closures as separate local
    /// bindings: Swift 6.0.3's SILGen crashes (signal 10) emitting a
    /// lazy-var getter whose initializer is one giant call expression
    /// with this many inline closures.
    private func makeSourceWatchCoordinator() -> SourceWatchCoordinator {
        let deduplicateDestinationPath: @MainActor () -> String = { [weak self] in
            self?.deduplicateDestinationPath ?? ""
        }
        let activeDestinationBookmarkKeys: @MainActor () -> [String] = { [weak self] in
            self?.activeDestinationBookmarkKeys() ?? []
        }
        let startImportPreview: @MainActor (WatchedImportContext) async -> Void = { [weak self] context in
            guard let self else { return }
            guard !self.deduplicateSessionStore.isWorking else {
                self.transientErrorMessage = "Finish the duplicate cleanup before starting an organize run."
                return
            }
            self.previewReviewStore.reset()
            await self.runCoordinator.startPreview(importContext: context)
        }
        let invalidateImportContext: @MainActor () -> Void = { [weak self] in
            self?.runCoordinator.invalidateWatchedImportContext()
        }
        let reportTransientError: @MainActor (String) -> Void = { [weak self] message in
            self?.transientErrorMessage = message
        }

        return SourceWatchCoordinator(
            store: watchedSourcesStore,
            preferencesStore: preferencesStore,
            setupStore: setupStore,
            runSessionStore: runSessionStore,
            folderAccessService: folderAccessService,
            repository: watchedSourcesRepository,
            deduplicateDestinationPath: deduplicateDestinationPath,
            activeDestinationBookmarkKeys: activeDestinationBookmarkKeys,
            startImportPreview: startImportPreview,
            invalidateImportContext: invalidateImportContext,
            reportTransientError: reportTransientError
        )
    }
    private lazy var historyCoordinator = HistoryCoordinator(
        preferencesStore: preferencesStore,
        setupStore: setupStore,
        historyStore: historyStore,
        runSessionStore: runSessionStore,
        deduplicateSessionStore: deduplicateSessionStore,
        finderService: finderService,
        navigate: { [weak self] route in
            self?.navigate(to: route)
        },
        reportTransientError: { [weak self] message in
            self?.transientErrorMessage = message
        },
        makeSecurityScopeForDestination: { [weak self] destinationRoot in
            self?.destinationSecurityScope(destinationRoot: destinationRoot)
        }
    )

    private var menuBarManager: MenuBarStatusManager?

    convenience init() {
        let preferencesStore = PreferencesStore()
        let profilesRepository = ProfilesRepository()
        let folderAccessService = FolderAccessService()
        let finderService = FinderService()
        let setupStore = SetupStore(
            sourcePath: preferencesStore.lastManualSourcePath,
            destinationPath: preferencesStore.lastManualDestinationPath,
            selectedProfileName: preferencesStore.lastSelectedProfileName
        )
        let runLogStore = RunLogStore(capacity: preferencesStore.logBufferCapacity)
        let historyStore = HistoryStore()
        let engine: any OrganizerEngine = SwiftOrganizerEngine(profilesRepository: profilesRepository)
        let runSessionStore = RunSessionStore(engine: engine, logStore: runLogStore, historyStore: historyStore)
        let libraryHealthStore = LibraryHealthStore()
        let deduplicateEngine = NativeDeduplicateEngine()
        let deduplicateSessionStore = DeduplicateSessionStore(engine: deduplicateEngine)

        self.init(
            preferencesStore: preferencesStore,
            setupStore: setupStore,
            runLogStore: runLogStore,
            historyStore: historyStore,
            runSessionStore: runSessionStore,
            previewReviewStore: nil,
            libraryHealthStore: libraryHealthStore,
            deduplicateSessionStore: deduplicateSessionStore,
            folderAccessService: folderAccessService,
            finderService: finderService,
            profilesRepository: profilesRepository,
            restoreBookmarksDuringBootstrap: false
        )
    }

    init(
        route: AppRoute = .organize(.setup),
        preferencesStore: PreferencesStore,
        setupStore: SetupStore,
        runLogStore: RunLogStore,
        historyStore: HistoryStore,
        runSessionStore: RunSessionStore,
        previewReviewStore: PreviewReviewStore? = nil,
        libraryHealthStore: LibraryHealthStore? = nil,
        deduplicateSessionStore: DeduplicateSessionStore? = nil,
        watchedSourcesStore: WatchedSourcesStore? = nil,
        photosImportStore: PhotosImportStore? = nil,
        folderAccessService: any FolderAccessServicing,
        finderService: any FinderServicing,
        profilesRepository: any ProfilesRepositorying,
        watchedSourcesRepository: (any WatchedSourcesRepositorying)? = nil,
        droppedItemStager: DroppedItemStager = DroppedItemStager(),
        performInitialBootstrap: Bool = true,
        restoreBookmarksDuringBootstrap: Bool = true,
        showSettingsWindowAction: @escaping @MainActor () -> Void = {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    ) {
        self.selection = route.sidebar
        self.organizeSubSelection = route.organizeSubSection ?? .setup
        self.settingsSelection = .general
        self.transientErrorMessage = nil
        self.preferencesStore = preferencesStore
        self.setupStore = setupStore
        self.runLogStore = runLogStore
        self.historyStore = historyStore
        self.runSessionStore = runSessionStore
        self.previewReviewStore = previewReviewStore ?? PreviewReviewStore()
        self.libraryHealthStore = libraryHealthStore ?? LibraryHealthStore()
        self.deduplicateSessionStore = deduplicateSessionStore ?? DeduplicateSessionStore(engine: NativeDeduplicateEngine())
        self.watchedSourcesStore = watchedSourcesStore ?? WatchedSourcesStore()
        self.photosImportStore = photosImportStore ?? AppState.makePhotosImportStore()
        self.guardianStore = GuardianStore(engine: SwiftGuardianEngine(), notifier: GuardianUserNotifier())
        self.folderAccessService = folderAccessService
        self.finderService = finderService
        self.profilesRepository = profilesRepository
        self.watchedSourcesRepository = watchedSourcesRepository ?? WatchedSourcesRepository()
        self.droppedItemStager = droppedItemStager
        self.showSettingsWindowAction = showSettingsWindowAction
        self.previewReviewStore.setDestinationScopeProvider { [weak self] destinationRoot in
            self?.destinationSecurityScope(destinationRoot: destinationRoot)
        }

        // Supply the reconciler T5 left unwired. `DestinationRecovery` pairs
        // filesystem recovery with settling any trial reservation the recovered
        // run left open; without a provider that second half is skipped.
        //
        // A no-op today, because nothing reserves until step 4 — an empty ledger
        // has no open reservations to settle. Wiring it here rather than leaving
        // it for step 4 keeps enforcement a pure gating change, and keeps this
        // decision at the composition root where it belongs.
        TrialComposition.installReconciler()

        if performInitialBootstrap {
            setupCoordinator.bootstrap(restoreBookmarks: restoreBookmarksDuringBootstrap)
            restoreDeduplicateDestinationBookmark()
            recoverInterruptedMutationsAfterBootstrap()
        }
        self.menuBarManager = MenuBarStatusManager(appState: self)
    }

    private func recoverInterruptedMutationsAfterBootstrap() {
        let paths = Set([
            setupStore.destinationPath,
            deduplicateDestinationPath,
        ].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })
        for path in paths {
            let scope = destinationSecurityScope(destinationRoot: path)
            let root = URL(fileURLWithPath: path, isDirectory: true)
            do {
                let lease = try DestinationOperationLock.acquire(
                    destinationRoot: root,
                    surface: "app launch",
                    operation: "recovery"
                )
                _ = DestinationRecovery.recoverAndReconcile(destinationRoot: root)
                lease.release()
            } catch is DestinationBusyError {
                // A live process owns the destination. Its journal remains
                // intact and recovery will be retried on history refresh.
            } catch {
                transientErrorMessage = UserFacingErrorMessage.message(for: error, context: .history)
            }
            scope?.close()
        }
    }

    var canStartRun: Bool {
        hasActiveWatchedImport
            || hasActivePhotosImport
            || setupStore.usingProfile
            || (!setupStore.sourcePath.isEmpty && !setupStore.destinationPath.isEmpty)
    }

    /// True while a watched-source Review & Import flow is in flight;
    /// the toolbar Transfer button stays enabled from the import context
    /// even when Setup paths are empty.
    var hasActiveWatchedImport: Bool {
        runCoordinator.activeWatchedImportContext != nil
    }

    /// True while an Apple Photos Review & Import flow is in flight; keeps the
    /// Transfer button enabled from the pinned context even with empty Setup.
    var hasActivePhotosImport: Bool {
        runCoordinator.activePhotosImportContext != nil
    }

    /// Single navigation entry point. Setting both sidebar selection and the
    /// nested Organize sub-section in one place keeps the two-axis routing
    /// consistent across coordinators and views.
    func navigate(to route: AppRoute) {
        selection = route.sidebar
        if let sub = route.organizeSubSection {
            organizeSubSelection = sub
        }
    }

    func dismissTransientError() {
        transientErrorMessage = nil
    }

    func chooseSourceFolder() async {
        runCoordinator.invalidateWatchedImportContext()
        await setupCoordinator.chooseSourceFolder()
    }

    func selectSourceFolder(_ url: URL) async {
        runCoordinator.invalidateWatchedImportContext()
        await setupCoordinator.selectSourceFolder(url)
    }

    func selectDestinationFolder(_ url: URL) async {
        runCoordinator.invalidateWatchedImportContext()
        await setupCoordinator.selectDestinationFolder(url)
    }

    /// Handles files/folders dragged onto the app. Single-folder drops
    /// are used directly; file drops and multi-item drops get staged into
    /// a symlink directory so the existing pipeline can walk them. Falls
    /// back to `transientErrorMessage` on failure.
    func applyDrop(urls: [URL]) async {
        runCoordinator.invalidateWatchedImportContext()
        await setupCoordinator.applyDrop(urls: urls)
    }

    func chooseDestinationFolder() async {
        runCoordinator.invalidateWatchedImportContext()
        await setupCoordinator.chooseDestinationFolder()
    }

    func useProfile(named name: String) {
        runCoordinator.invalidateWatchedImportContext()
        setupCoordinator.useProfile(named: name)
    }

    func clearSelectedProfile() {
        runCoordinator.invalidateWatchedImportContext()
        setupCoordinator.clearSelectedProfile()
    }

    func refreshProfiles() {
        setupCoordinator.refreshProfiles()
    }

    func saveCurrentPathsAsProfile() {
        setupCoordinator.saveCurrentPathsAsProfile()
    }

    func overwriteProfile(named name: String) {
        setupCoordinator.overwriteProfile(named: name)
    }

    func deleteProfile(named name: String) {
        setupCoordinator.deleteProfile(named: name)
    }

    func startPreview() async {
        // Finding #7: organize and deduplicate mutate the same destination, so
        // they must never run concurrently. Reject an organize run while a
        // deduplicate scan/commit is in flight.
        guard !deduplicateSessionStore.isWorking else {
            transientErrorMessage = "Finish the duplicate cleanup before starting an organize run."
            return
        }
        previewReviewStore.reset()
        await runCoordinator.startPreview()
    }

    func startTransfer() async {
        guard !deduplicateSessionStore.isWorking else {
            transientErrorMessage = "Finish the duplicate cleanup before starting an organize run."
            return
        }
        if previewReviewStore.isStale {
            transientErrorMessage = "Rebuild the preview before transferring so Chronoframe copies exactly the corrected plan."
            return
        }
        await runCoordinator.startTransfer()
    }

    func confirmRunPrompt() {
        runCoordinator.confirmRunPrompt()
    }

    func confirmRunPromptStartFresh() {
        runCoordinator.confirmRunPromptStartFresh()
    }

    func dismissRunPrompt() {
        runCoordinator.dismissRunPrompt()
    }

    func cancelRun() {
        switch selection {
        case .organize:
            runCoordinator.cancelRun()
        case .photos:
            runCoordinator.cancelRun()
        case .deduplicate:
            deduplicateSessionStore.cancel()
        case .guardian:
            guardianStore.cancelScan()
        case .profiles:
            runCoordinator.cancelRun()
        }
    }

    func cancelOrganizeRun() {
        runCoordinator.cancelRun()
    }

    func cancelDeduplicateRun() {
        deduplicateSessionStore.cancel()
    }

    /// Where dedupe scans run. A folder chosen from Deduplicate wins; until
    /// then, the app falls back to the active organized destination.
    var deduplicateDestinationPath: String {
        if !preferencesStore.lastDeduplicateDestinationPath.isEmpty {
            return preferencesStore.lastDeduplicateDestinationPath
        }
        if !setupStore.destinationPath.isEmpty {
            return setupStore.destinationPath
        }
        return historyStore.destinationRoot
    }

    var hasDedicatedDeduplicateDestinationPath: Bool {
        !preferencesStore.lastDeduplicateDestinationPath.isEmpty
    }

    var deduplicateDestinationHelper: String {
        if hasDedicatedDeduplicateDestinationPath {
            return "Only this folder is scanned for duplicates."
        }
        if deduplicateDestinationPath.isEmpty {
            return "Choose the folder to scan for duplicate photos."
        }
        return "Using the Organize destination until you choose a Deduplicate folder."
    }

    func chooseDeduplicateDestinationFolder() async {
        guard let url = folderAccessService.chooseFolder(
            startingAt: deduplicateDestinationPath,
            prompt: "Choose Deduplicate Folder"
        ) else {
            return
        }

        do {
            try folderAccessService.validateFolder(url, role: .destination)
        } catch {
            transientErrorMessage = UserFacingErrorMessage.message(for: error, context: .setup)
            return
        }

        // Persist the bookmark BEFORE the path so the two never drift. If
        // bookmark creation fails (e.g. APFS volume not bookmarkable, sandbox
        // mismatch), surface the error and leave the destination unchanged
        // — the previously-chosen folder, if any, stays valid.
        do {
            let bookmark = try folderAccessService.makeBookmark(for: url, key: Self.deduplicateDestinationBookmarkKey)
            preferencesStore.storeBookmark(bookmark)
            preferencesStore.lastDeduplicateDestinationPath = url.path
        } catch {
            transientErrorMessage = UserFacingErrorMessage.message(for: error, context: .setup)
        }
    }

    /// Drop the dedicated Deduplicate folder and any bookmark backing it.
    /// `deduplicateDestinationPath` then falls back to the active Organize
    /// destination (or the most recently used history root) on next access.
    func clearDeduplicateDestinationFolder() {
        preferencesStore.removeBookmark(for: Self.deduplicateDestinationBookmarkKey)
        preferencesStore.lastDeduplicateDestinationPath = ""
    }

    func useDeduplicateHistoryFolder(_ record: DeduplicateFolderHistoryRecord) {
        let path = record.folderPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        do {
            try folderAccessService.validateFolder(url, role: .destination)
        } catch {
            transientErrorMessage = "That Deduplicate folder is no longer available. Choose it again to continue."
            return
        }

        do {
            let bookmark = try folderAccessService.makeBookmark(for: url, key: Self.deduplicateDestinationBookmarkKey)
            preferencesStore.storeBookmark(bookmark)
            preferencesStore.lastDeduplicateDestinationPath = path
            resetDeduplicate()
        } catch {
            transientErrorMessage = UserFacingErrorMessage.message(for: error, context: .setup)
        }
    }

    /// Open Finder with the active Deduplicate destination selected. Only
    /// meaningful when `hasDedicatedDeduplicateDestinationPath` is true —
    /// the Organize destination already has its own reveal in Setup.
    func revealDeduplicateDestinationInFinder() {
        let path = deduplicateDestinationPath
        guard !path.isEmpty else { return }
        finderService.revealInFinder(path)
    }

    func openDeduplicateRunHistory() async {
        let destination = deduplicateDestinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty else {
            transientErrorMessage = "Choose a Deduplicate folder before opening its run history."
            return
        }

        navigate(to: .organize(.history))
        let scope = deduplicateSecurityScope(destination: destination)
        await historyStore.refresh(destinationRoot: destination)
        scope?.close()
    }

    func startDeduplicateScan() {
        // Finding #7: don't scan for duplicates while an organize run (including
        // its preflight) is mutating or about to mutate the destination.
        guard !runSessionStore.isRunning else {
            transientErrorMessage = "Finish the current organize run before scanning for duplicates."
            return
        }
        let destination = deduplicateDestinationPath
        guard !destination.isEmpty else {
            transientErrorMessage = "Choose a destination folder before running a deduplicate scan."
            return
        }
        let configuration = preferencesStore.makeDeduplicateConfiguration(destinationPath: destination)
        deduplicateSessionStore.startScan(
            configuration: configuration,
            securityScope: deduplicateSecurityScope(destination: destination)
        )
    }

    func commitDeduplicateDecisions() {
        guard !runSessionStore.isRunning else {
            transientErrorMessage = "Finish the current organize run before deleting duplicates."
            return
        }
        let destination = deduplicateDestinationPath
        guard !destination.isEmpty else { return }
        let configuration = preferencesStore.makeDeduplicateConfiguration(destinationPath: destination)
        // Commit only clusters the user has reviewed/approved. The full-plan
        // path would also trash scan-time preselects in unreviewed
        // low/medium-confidence clusters (incl. dHash-only weak matches),
        // violating the review-only invariant and deleting more files than
        // the confirmation dialog (which shows the reviewed count) states.
        deduplicateSessionStore.commitReviewed(
            configuration: configuration,
            securityScope: deduplicateSecurityScope(destination: destination)
        )
    }

    func resetDeduplicate() {
        deduplicateSessionStore.reset()
    }

    private func restoreDeduplicateDestinationBookmark() {
        guard let bookmark = preferencesStore.bookmark(for: Self.deduplicateDestinationBookmarkKey) else {
            // Never set a Deduplicate folder; nothing to restore.
            return
        }
        let resolvedBookmark = folderAccessService.resolveBookmark(bookmark)
        // FolderAccessService.resolveBookmark returns a fallback URL
        // built from the stored path when the bookmark data is no
        // longer valid. That URL may point at a folder that no longer
        // exists — checking only `resolveBookmark != nil` would leave
        // a dead path persisted. Validate the resolved URL is still a
        // readable, writable directory before keeping it.
        let isLive: Bool = {
            guard let url = resolvedBookmark?.url else { return false }
            do {
                try folderAccessService.validateFolder(url, role: .destination)
                return true
            } catch {
                return false
            }
        }()
        guard let resolvedBookmark, isLive else {
            // Drop both the path and the bookmark so
            // `deduplicateDestinationPath` falls back to the Organize
            // destination instead of silently scanning a stale location.
            preferencesStore.removeBookmark(for: Self.deduplicateDestinationBookmarkKey)
            preferencesStore.lastDeduplicateDestinationPath = ""
            return
        }

        if let refreshedBookmark = resolvedBookmark.refreshedBookmark {
            preferencesStore.storeBookmark(refreshedBookmark)
        }
        preferencesStore.lastDeduplicateDestinationPath = resolvedBookmark.url.path
    }

    func openDestination() {
        runCoordinator.openDestination()
    }

    func openReport() {
        runCoordinator.openReport()
    }

    func openLogsDirectory() {
        runCoordinator.openLogsDirectory()
    }

    func refreshLibraryHealth() async {
        let destination = setupStore.destinationPath.isEmpty
            ? historyStore.destinationRoot
            : setupStore.destinationPath
        await libraryHealthStore.refresh(
            sourceRoot: setupStore.sourcePath,
            destinationRoot: destination,
            folderStructure: preferencesStore.folderStructure
        )
    }

    func performLibraryHealthAction(_ action: LibraryHealthAction) {
        switch action {
        case .runPreview, .refreshDestinationIndex, .reviewUnknownDates:
            navigate(to: .organize(.run))
            Task { await startPreview() }
        case .runDeduplicate:
            selection = .deduplicate
        case .openHistory:
            navigate(to: .organize(.history))
        case .reorganizeDestination:
            reorganizeDestination(targetStructure: preferencesStore.folderStructure)
        }
    }

    func openSettingsWindow() {
        runCoordinator.openSettingsWindow()
    }

    func openProfilesSettings() {
        settingsSelection = .profiles
        openSettingsWindow()
    }

    func revealHistoryEntry(_ entry: RunHistoryEntry) {
        historyCoordinator.revealHistoryEntry(entry)
    }

    func openHistoryEntry(_ entry: RunHistoryEntry) {
        historyCoordinator.openHistoryEntry(entry)
    }

    /// Revert the transfer described by `entry`'s audit receipt. Switches to the
    /// Run workspace and streams progress + the final summary there.
    func revertHistoryEntry(_ entry: RunHistoryEntry) {
        historyCoordinator.revertHistoryEntry(entry)
    }

    /// Reorganize the current destination so its folder layout matches the
    /// preferred `FolderStructure`. Streams progress through the Run workspace.
    func reorganizeDestination(targetStructure: FolderStructure) {
        guard !runSessionStore.isRunning, !deduplicateSessionStore.isWorking else {
            transientErrorMessage = "Stop the current run before reorganizing."
            return
        }

        let destination = historyStore.destinationRoot.isEmpty
            ? setupStore.destinationPath
            : historyStore.destinationRoot
        guard !destination.isEmpty else {
            transientErrorMessage = "Choose a destination folder before reorganizing."
            return
        }
        navigate(to: .organize(.run))
        runSessionStore.requestReorganize(
            destinationRoot: destination,
            targetStructure: targetStructure,
            securityScope: destinationSecurityScope(destinationRoot: destination)
        )
    }

    private func organizeSecurityScope() -> SecurityScopedFolderAccess? {
        scopedAccess(forKeys: activeOrganizeBookmarkKeys())
    }

    /// Scope for a watched-source import: the context's own source
    /// bookmark plus the destination bookmarks it captured. Setup,
    /// profile, and manual bookmarks are deliberately not consulted.
    private func watchedImportSecurityScope(for context: WatchedImportContext) -> SecurityScopedFolderAccess? {
        let destinationBookmarks = context.destinationBookmarkKeys.compactMap {
            preferencesStore.bookmark(for: $0)
        }
        return folderAccessService.scopedAccess(for: [context.sourceBookmark] + destinationBookmarks)
    }

    /// Scope for a Photos import: only the captured destination bookmarks. The
    /// staging source lives in the app's own container, so it needs no
    /// security-scoped bookmark.
    private func photosImportSecurityScope(for context: PhotosImportContext) -> SecurityScopedFolderAccess? {
        let destinationBookmarks = context.destinationBookmarkKeys.compactMap {
            preferencesStore.bookmark(for: $0)
        }
        guard !destinationBookmarks.isEmpty else { return nil }
        return folderAccessService.scopedAccess(for: destinationBookmarks)
    }

    private static func makePhotosImportStore() -> PhotosImportStore {
        let staging = RuntimePaths.applicationSupportDirectory()
            .appendingPathComponent("photos_import_staging", isDirectory: true)
        return PhotosImportStore(
            access: PhotosLibraryAccessService(),
            catalog: PhotosCatalogService(),
            exporter: PhotosResourceExportService(),
            stagingParentURL: staging
        )
    }

    private func deduplicateSecurityScope(destination: String) -> SecurityScopedFolderAccess? {
        if hasDedicatedDeduplicateDestinationPath {
            return scopedAccess(forKeys: [Self.deduplicateDestinationBookmarkKey])
        }
        return destinationSecurityScope(destinationRoot: destination)
    }

    private func destinationSecurityScope(destinationRoot: String) -> SecurityScopedFolderAccess? {
        let keys = activeDestinationBookmarkKeys()
        let matchingKeys = keys.filter { key in
            guard let bookmark = preferencesStore.bookmark(for: key) else { return false }
            return pathsOverlap(bookmark.path, destinationRoot)
        }
        return scopedAccess(forKeys: matchingKeys.isEmpty ? keys : matchingKeys)
    }

    private func activeOrganizeBookmarkKeys() -> [String] {
        activeSourceBookmarkKeys() + activeDestinationBookmarkKeys()
    }

    private func activeSourceBookmarkKeys() -> [String] {
        var keys = [bookmarkPathResolver.bookmarkKey(for: .source, profileName: nil)]
        if setupStore.usingProfile, !setupStore.selectedProfileName.isEmpty {
            keys.append(bookmarkPathResolver.bookmarkKey(for: .source, profileName: setupStore.selectedProfileName))
        }
        return keys
    }

    private func activeDestinationBookmarkKeys() -> [String] {
        var keys = [bookmarkPathResolver.bookmarkKey(for: .destination, profileName: nil)]
        if setupStore.usingProfile, !setupStore.selectedProfileName.isEmpty {
            keys.append(bookmarkPathResolver.bookmarkKey(for: .destination, profileName: setupStore.selectedProfileName))
        }
        keys.append(Self.deduplicateDestinationBookmarkKey)
        return keys
    }

    private func scopedAccess(forKeys keys: [String]) -> SecurityScopedFolderAccess? {
        let bookmarks = keys.compactMap { preferencesStore.bookmark(for: $0) }
        guard !bookmarks.isEmpty else { return nil }
        return folderAccessService.scopedAccess(for: bookmarks)
    }

    private func pathsOverlap(_ bookmarkPath: String, _ requestedPath: String) -> Bool {
        let bookmark = URL(fileURLWithPath: bookmarkPath).standardizedFileURL.path
        let requested = URL(fileURLWithPath: requestedPath).standardizedFileURL.path
        return requested == bookmark || requested.hasPrefix(bookmark + "/") || bookmark.hasPrefix(requested + "/")
    }

    /// Repopulates the Setup view with a previously-used source path and switches to it.
    /// Clears any active profile selection so the manual source path takes effect.
    func useHistoricalSource(_ record: TransferredSourceRecord) {
        runCoordinator.invalidateWatchedImportContext()
        historyCoordinator.useHistoricalSource(record)
    }

    // MARK: - Watched sources

    /// Starts watching registered source folders. Called from the app's
    /// post-launch async hook — never from init, which must not do
    /// filesystem work. UI-test scenarios seed the store directly and
    /// must not have it replaced by the real (empty) registry.
    func startWatchingSources() async {
        guard ProcessInfo.processInfo.environment["CHRONOFRAME_UI_TEST_SCENARIO"] == nil else { return }
        await sourceWatchCoordinator.start()
    }

    func stopWatchingSources() {
        sourceWatchCoordinator.stop()
    }

    func addWatchedSourceFolder() async {
        await sourceWatchCoordinator.addSourceFolder()
    }

    func addWatchedSource(url: URL) async {
        await sourceWatchCoordinator.addSource(url: url)
    }

    func removeWatchedSource(id: UUID) {
        sourceWatchCoordinator.removeSource(id: id)
    }

    func refreshWatchedSources() {
        sourceWatchCoordinator.refreshAll()
    }

    func ignoreWatchedSourceCurrentItems(id: UUID) async {
        await sourceWatchCoordinator.ignoreCurrentItems(id: id)
    }

    func repickWatchedSource(id: UUID) async {
        await sourceWatchCoordinator.repickSource(id: id)
    }

    func reviewAndImportWatchedSource(id: UUID) async {
        await sourceWatchCoordinator.reviewAndImport(id: id)
    }

    func revealWatchedSource(id: UUID) {
        guard let state = watchedSourcesStore.state(for: id) else { return }
        finderService.revealInFinder(state.source.path)
    }

    // MARK: - Library Guardian

    /// The library Guardian protects — the active Organize destination (or the most
    /// recent history root). Guardian only ever works on an already-organized
    /// library, so it reuses the destination rather than introducing a new picker.
    var guardianLibraryPath: String {
        if !setupStore.destinationPath.isEmpty {
            return setupStore.destinationPath
        }
        return historyStore.destinationRoot
    }

    /// The configured mirror volume path, or empty when none is set.
    var guardianMirrorPath: String {
        preferencesStore.bookmark(for: Self.guardianMirrorBookmarkKey)?.path ?? ""
    }

    /// Resolve a stable Guardian library identity for `path`: a persisted UUID keyed
    /// by the path, plus the volume UUID when the filesystem exposes one. The UUID
    /// keys all of Guardian's Application Support state, so it must stay stable
    /// across launches for the same library.
    private func guardianLibraryIdentity(for path: String) -> GuardianLibraryIdentity {
        let defaultsKey = "guardian.libraryUUID." + path
        let uuid: String
        if let existing = UserDefaults.standard.string(forKey: defaultsKey) {
            uuid = existing
        } else {
            uuid = UUID().uuidString
            UserDefaults.standard.set(uuid, forKey: defaultsKey)
        }
        let volumeID = (try? URL(fileURLWithPath: path).resourceValues(forKeys: [.volumeUUIDStringKey]))?.volumeUUIDString
        return GuardianLibraryIdentity(libraryUUID: uuid, volumeIdentifier: volumeID)
    }

    private func guardianBookmark(forKey key: String, path: String) -> FolderBookmark {
        // The current engine works from the pinned URLs; the bookmark is carried for
        // the pin-at-action-time contract. Use the stored bookmark when present,
        // otherwise a path-only placeholder so the context is still well-formed.
        preferencesStore.bookmark(for: key) ?? FolderBookmark(key: key, path: path, data: Data())
    }

    /// Configure the store for the current library and run a read-only scan. The
    /// destination scope is held for the whole scan so the probe can read the library.
    func scanGuardianLibrary() async {
        let path = guardianLibraryPath
        guard !path.isEmpty else { return }
        let identity = guardianLibraryIdentity(for: path)
        guardianStore.configure(libraryIdentity: identity, libraryURL: URL(fileURLWithPath: path, isDirectory: true))
        let scope = destinationSecurityScope(destinationRoot: path)
        await guardianStore.scan()
        scope?.close()
    }

    func acceptGuardianTrust() async {
        let scope = destinationSecurityScope(destinationRoot: guardianLibraryPath)
        await guardianStore.acceptSelectedTrust()
        scope?.close()
    }

    func acknowledgeGuardianDeletions() async {
        let scope = destinationSecurityScope(destinationRoot: guardianLibraryPath)
        await guardianStore.acknowledgeSelectedDeletions()
        scope?.close()
    }

    /// True when `pathA` and `pathB` are the same folder or one contains the other,
    /// after resolving symlinks. Guardian uses this to keep the mirror strictly
    /// outside the library it protects.
    private func guardianRootsOverlap(_ pathA: String, _ pathB: String) -> Bool {
        guard !pathA.isEmpty, !pathB.isEmpty else { return false }
        return GuardianMultiRootLock.pathsOverlap(
            GuardianMultiRootLock.canonicalPath(URL(fileURLWithPath: pathA, isDirectory: true)),
            GuardianMultiRootLock.canonicalPath(URL(fileURLWithPath: pathB, isDirectory: true))
        )
    }

    /// Choose the mirror volume folder and persist its bookmark under `guardian.mirror`.
    /// The mirror must be a separate location — never inside the library (or the
    /// library inside it), or a mirror pass would write copies into the protected
    /// library and future scrubs would treat those backups as library media.
    func chooseGuardianMirrorFolder() async {
        guard let url = folderAccessService.chooseFolder(
            startingAt: guardianMirrorPath,
            prompt: "Choose Mirror Folder"
        ) else {
            return
        }
        do {
            try folderAccessService.validateFolder(url, role: .destination)
        } catch {
            transientErrorMessage = UserFacingErrorMessage.message(for: error, context: .setup)
            return
        }
        if guardianRootsOverlap(url.path, guardianLibraryPath) {
            transientErrorMessage = "Choose a mirror folder outside your library. The mirror must be a separate location so it never writes into the library it protects."
            return
        }
        do {
            let bookmark = try folderAccessService.makeBookmark(for: url, key: Self.guardianMirrorBookmarkKey)
            preferencesStore.storeBookmark(bookmark)
        } catch {
            transientErrorMessage = UserFacingErrorMessage.message(for: error, context: .setup)
        }
    }

    func runGuardianMirror() async {
        let libraryPath = guardianLibraryPath
        let mirrorPath = guardianMirrorPath
        guard !libraryPath.isEmpty, !mirrorPath.isEmpty else { return }
        // Guard against the library having changed to now contain (or sit inside)
        // the previously-chosen mirror — mirroring would then write into the library.
        if guardianRootsOverlap(mirrorPath, libraryPath) {
            transientErrorMessage = "The mirror folder is inside your library. Choose a mirror outside the library before mirroring."
            return
        }
        let context = GuardianMirrorContext(
            libraryIdentity: guardianLibraryIdentity(for: libraryPath),
            libraryURL: URL(fileURLWithPath: libraryPath, isDirectory: true),
            libraryBookmark: guardianBookmark(forKey: activeDestinationBookmarkKeys().first ?? "guardian.library", path: libraryPath),
            mirrorURL: URL(fileURLWithPath: mirrorPath, isDirectory: true),
            mirrorBookmark: guardianBookmark(forKey: Self.guardianMirrorBookmarkKey, path: mirrorPath)
        )
        let libraryScope = destinationSecurityScope(destinationRoot: libraryPath)
        let mirrorScope = scopedAccess(forKeys: [Self.guardianMirrorBookmarkKey])
        await guardianStore.runMirror(context: context)
        mirrorScope?.close()
        libraryScope?.close()
    }

    func prepareGuardianRestore() async {
        let libraryPath = guardianLibraryPath
        let mirrorPath = guardianMirrorPath
        guard !libraryPath.isEmpty, !mirrorPath.isEmpty else { return }
        let libraryScope = destinationSecurityScope(destinationRoot: libraryPath)
        let mirrorScope = scopedAccess(forKeys: [Self.guardianMirrorBookmarkKey])
        await guardianStore.prepareRestore(
            libraryURL: URL(fileURLWithPath: libraryPath, isDirectory: true),
            mirrorURL: URL(fileURLWithPath: mirrorPath, isDirectory: true)
        )
        mirrorScope?.close()
        libraryScope?.close()
    }

    func runGuardianRestore() async {
        let libraryPath = guardianLibraryPath
        let mirrorPath = guardianMirrorPath
        guard !libraryPath.isEmpty, !mirrorPath.isEmpty else { return }
        // Refuse to run a plan that was reviewed against a different library/mirror
        // (e.g. the Organize destination changed after the restore was reviewed).
        // The store also enforces this when building the context; here we surface a
        // clear message and drop the stale plan so the user re-reviews.
        if let plan = guardianStore.restorePlan,
           plan.libraryRoot != URL(fileURLWithPath: libraryPath, isDirectory: true).path
            || plan.mirrorRoot != URL(fileURLWithPath: mirrorPath, isDirectory: true).path {
            guardianStore.discardRestorePlan()
            transientErrorMessage = "The library or mirror changed since this restore was reviewed. Review the restore again before running it."
            return
        }
        guard let context = guardianStore.makeRestoreContext(
            libraryIdentity: guardianLibraryIdentity(for: libraryPath),
            libraryURL: URL(fileURLWithPath: libraryPath, isDirectory: true),
            libraryBookmark: guardianBookmark(forKey: activeDestinationBookmarkKeys().first ?? "guardian.library", path: libraryPath),
            mirrorURL: URL(fileURLWithPath: mirrorPath, isDirectory: true),
            mirrorBookmark: guardianBookmark(forKey: Self.guardianMirrorBookmarkKey, path: mirrorPath)
        ) else {
            return
        }
        let libraryScope = destinationSecurityScope(destinationRoot: libraryPath)
        let mirrorScope = scopedAccess(forKeys: [Self.guardianMirrorBookmarkKey])
        await guardianStore.runRestore(context: context)
        mirrorScope?.close()
        libraryScope?.close()
    }

    // MARK: - Apple Photos import

    /// Loads the Photos catalog when the workspace appears, if access is
    /// already granted. Prompting is an explicit user action (`requestPhotosAccess`).
    func preparePhotosWorkspace() {
        photosImportStore.refreshAuthorization()
    }

    func requestPhotosAccess() async {
        await photosImportStore.requestAccess()
    }

    /// Exports the current Photos selection into staging and hands off to the
    /// normal preview → consent → verified-transfer flow, pinning the
    /// destination active at click time. The Photos library is only read.
    func reviewAndImportSelectedPhotos() async {
        guard !runSessionStore.isRunning else { return }
        guard !deduplicateSessionStore.isWorking else {
            transientErrorMessage = "Finish the duplicate cleanup before importing from Photos."
            return
        }
        let destinationPath = setupStore.destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let capture = PhotosImportStore.DestinationCapture(
            path: destinationPath,
            bookmarkKeys: activeDestinationBookmarkKeys()
        )
        guard let context = await photosImportStore.prepareImport(destination: capture) else {
            if let message = photosImportStore.statusMessage {
                transientErrorMessage = message
            }
            return
        }
        previewReviewStore.reset()
        await runCoordinator.startPreview(photosImportContext: context)
    }

    func revealTransferredSource(_ record: TransferredSourceRecord) {
        historyCoordinator.revealTransferredSource(record)
    }

    func forgetTransferredSource(_ record: TransferredSourceRecord) {
        historyCoordinator.forgetTransferredSource(record)
    }
}

@MainActor
final class MenuBarStatusManager: NSObject {
    private weak var appState: AppState?
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        super.init()
        setup()
    }

    func setup() {
        // Skip setup when running unit tests or UI tests to avoid WindowServer/MenuBar hangs in CI
        if NSClassFromString("XCTestCase") != nil || ProcessInfo.processInfo.environment["CHRONOFRAME_UI_TEST_SCENARIO"] != nil {
            return
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItem()
        startObserving()
    }

    private func startObserving() {
        guard let appState = appState else { return }

        appState.runSessionStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        appState.deduplicateSessionStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)

        appState.watchedSourcesStore.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateStatusItem()
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let appState = appState, let button = statusItem?.button else { return }

        let runStatus = appState.runSessionStore.status
        let deduplicateStatus = appState.deduplicateSessionStore.status

        if runStatus == .running {
            let progressStr = String(format: "%.0f%%", appState.runSessionStore.progress * 100)
            button.title = " ⚬ \(progressStr)"
            button.image = NSImage(systemSymbolName: "circle.dashed", accessibilityDescription: "Chronoframe Running")
            DockProgressRenderer.update(progress: appState.runSessionStore.progress, isRunning: true)
        } else if deduplicateStatus == .committing {
            button.title = " ⚬ Trashing"
            button.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: "Chronoframe Deduplicating")
            DockProgressRenderer.update(progress: 0, isRunning: false)
        } else {
            button.title = ""
            button.image = NSImage(systemSymbolName: "circle", accessibilityDescription: "Chronoframe Idle")
            button.image?.isTemplate = true
            DockProgressRenderer.update(progress: 0, isRunning: false)
        }

        let menu = NSMenu()
        menu.autoenablesItems = false

        if runStatus == .running {
            let item = NSMenuItem(title: "Chronoframe: Organizing...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)

            let phaseTitle = appState.runSessionStore.currentPhase?.title ?? "Processing"
            let detailItem = NSMenuItem(title: "Phase: \(phaseTitle)", action: nil, keyEquivalent: "")
            detailItem.isEnabled = false
            menu.addItem(detailItem)
        } else if deduplicateStatus == .committing {
            let item = NSMenuItem(title: "Chronoframe: Trashing duplicates...", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        } else {
            let item = NSMenuItem(title: "Chronoframe is Idle", action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)

            let pendingEstimate = appState.watchedSourcesStore.totalPendingEstimate
            if pendingEstimate > 0 {
                let pendingItem = NSMenuItem(
                    title: "New items in watched folders: \(pendingEstimate)",
                    action: nil,
                    keyEquivalent: ""
                )
                pendingItem.isEnabled = false
                menu.addItem(pendingItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        if runStatus == .running {
            let pauseCancelItem = NSMenuItem(title: "Cancel Transfer", action: #selector(cancelTransferAction), keyEquivalent: "")
            pauseCancelItem.target = self
            menu.addItem(pauseCancelItem)
        } else if deduplicateStatus == .committing {
            let cancelItem = NSMenuItem(title: "Cancel Commit", action: #selector(cancelDedupeAction), keyEquivalent: "")
            cancelItem.target = self
            menu.addItem(cancelItem)
        }

        let openAppItem = NSMenuItem(title: "Open Chronoframe", action: #selector(openAppAction), keyEquivalent: "o")
        openAppItem.target = self
        menu.addItem(openAppItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "Quit Chronoframe", action: #selector(quitAction), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openAppAction() {
        let mainWindow = NSApp.windows.first { $0.title == "Chronoframe" } ?? NSApp.windows.first
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func cancelTransferAction() {
        appState?.cancelOrganizeRun()
    }

    @objc private func cancelDedupeAction() {
        appState?.cancelDeduplicateRun()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
