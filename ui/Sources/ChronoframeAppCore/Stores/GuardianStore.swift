#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Combine
import Foundation

/// A cancellation flag safe to hand to an off-main-actor scan closure.
public final class GuardianCancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    public func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

/// View-model for the Guardian workspace: integrity report, trust decisions,
/// mirror status, and restore review. All destination-mutating work is delegated
/// to a `GuardianEngine` off the main actor; the store only holds `@MainActor`
/// UI state and pins actions through the Phase 4 contexts.
///
/// The store never advances trust on its own: `scan` reports, and only an explicit
/// `acceptSelectedTrust` / `acknowledgeSelectedDeletions` changes the manifest.
/// Restore is always review-gated — `runRestore` heals only the paths the user
/// selected, carried in the pinned `GuardianRestoreContext`.
@MainActor
public final class GuardianStore: ObservableObject {
    /// A compact, UI-facing summary of the last scan.
    public struct ScanSummary: Equatable, Sendable {
        public let verified: Int
        public let corrupt: Int
        public let modified: Int
        public let missing: Int
        public let newFiles: Int
        public let partialScan: Bool
        public let generatedAt: Date

        public var hasFindingsNeedingReview: Bool {
            corrupt > 0 || modified > 0 || missing > 0
        }
    }

    @Published public private(set) var libraryIdentity: GuardianLibraryIdentity?
    @Published public private(set) var libraryURL: URL?
    @Published public private(set) var report: GuardianIntegrityReport?
    @Published public private(set) var lastScanSummary: ScanSummary?
    @Published public private(set) var scheduleState: GuardianScheduleState = GuardianScheduleState()

    @Published public private(set) var isScanning = false
    @Published public private(set) var isMirroring = false
    @Published public private(set) var isRestoring = false
    /// A plain, reassuring status/error line. Never raw error text.
    @Published public private(set) var statusMessage: String?

    @Published public var selectedTrustPaths: Set<String> = []
    @Published public var selectedRestorePaths: Set<String> = []
    @Published public private(set) var restorePlan: GuardianRestorePlan?
    @Published public private(set) var lastMirrorResult: GuardianMirrorExecutionResult?
    @Published public private(set) var lastRestoreResult: GuardianRestoreExecutionResult?

    private let engine: any GuardianEngine
    private let scheduler: GuardianScheduler
    private let schedulePersistence: any GuardianSchedulePersisting
    private let notifier: (any GuardianNotifying)?
    private var activeToken: GuardianCancellationToken?

    public init(
        engine: any GuardianEngine,
        scheduler: GuardianScheduler = GuardianScheduler(),
        schedulePersistence: any GuardianSchedulePersisting = GuardianFileSchedulePersistence(),
        notifier: (any GuardianNotifying)? = nil
    ) {
        self.engine = engine
        self.scheduler = scheduler
        self.schedulePersistence = schedulePersistence
        self.notifier = notifier
    }

    // MARK: - Configuration

    /// Point the store at a library. Loads its persisted schedule state.
    public func configure(libraryIdentity: GuardianLibraryIdentity, libraryURL: URL) {
        self.libraryIdentity = libraryIdentity
        self.libraryURL = libraryURL
        self.scheduleState = schedulePersistence.load(for: libraryIdentity)
    }

    // MARK: - Scan

    /// Run a manual integrity scan of the configured library.
    public func scan() async {
        guard let libraryIdentity, let libraryURL, !isScanning else { return }
        await runScan(libraryIdentity: libraryIdentity, libraryURL: libraryURL)
    }

    /// Cancel an in-flight scan.
    public func cancelScan() {
        activeToken?.cancel()
    }

    private func runScan(libraryIdentity: GuardianLibraryIdentity, libraryURL: URL) async {
        isScanning = true
        statusMessage = nil
        let token = GuardianCancellationToken()
        activeToken = token
        defer {
            isScanning = false
            activeToken = nil
        }

        do {
            let outcome = try await engine.scan(
                libraryURL: libraryURL,
                libraryIdentity: libraryIdentity,
                isCancelled: { token.isCancelled() }
            )
            report = outcome.report
            restorePlan = nil
            selectedTrustPaths = []
            selectedRestorePaths = []
            lastScanSummary = Self.summarize(outcome.report)

            if outcome.report.partialScan {
                statusMessage = "Chronoframe couldn't fully check this library. Some folders couldn't be read, so the results are incomplete."
            }
            if outcome.report.hasCorruption, let notifier {
                notifier.notifyBitRotDetected(
                    libraryName: libraryURL.lastPathComponent,
                    corruptCount: outcome.report.count(of: .corrupt)
                )
            }
        } catch {
            statusMessage = "Chronoframe couldn't complete the integrity scan. Your files were not changed."
        }
    }

    // MARK: - Trust decisions (explicit only)

    public func toggleTrustSelection(_ relativePath: String) {
        if selectedTrustPaths.contains(relativePath) {
            selectedTrustPaths.remove(relativePath)
        } else {
            selectedTrustPaths.insert(relativePath)
        }
    }

    /// Promote the selected paths to `trusted`, recording their current bytes as the
    /// new known-good baseline.
    public func acceptSelectedTrust() async {
        guard let libraryIdentity, let report, !selectedTrustPaths.isEmpty else { return }
        let paths = selectedTrustPaths
        do {
            try await engine.acceptTrust(relativePaths: paths, report: report, libraryIdentity: libraryIdentity)
            selectedTrustPaths = []
            await scan()
        } catch {
            statusMessage = "Chronoframe couldn't update the trusted baseline. Your files were not changed."
        }
    }

    /// Mark the selected missing paths as intentionally deleted (`retired`).
    public func acknowledgeSelectedDeletions() async {
        guard let libraryIdentity, let report, !selectedTrustPaths.isEmpty else { return }
        let paths = selectedTrustPaths
        do {
            try await engine.acknowledgeDeletions(relativePaths: paths, report: report, libraryIdentity: libraryIdentity)
            selectedTrustPaths = []
            await scan()
        } catch {
            statusMessage = "Chronoframe couldn't update the trusted baseline. Your files were not changed."
        }
    }

    // MARK: - Mirror

    /// Run a verified mirror using the pinned context. Copies only from currently-
    /// verified primaries; never writes the library.
    public func runMirror(context: GuardianMirrorContext) async {
        guard let report, !isMirroring else { return }
        isMirroring = true
        statusMessage = nil
        defer { isMirroring = false }
        do {
            let plan = try await engine.planMirror(context: context, libraryReport: report)
            let result = try await engine.runMirror(context: context, plan: plan)
            lastMirrorResult = result
        } catch {
            statusMessage = Self.message(for: error)
        }
    }

    // MARK: - Restore (review-gated)

    /// Build a restore plan for review. Populates `restorePlan`; the user then picks
    /// which restorable paths to heal before `runRestore`.
    public func prepareRestore(libraryURL: URL, mirrorURL: URL) async {
        guard let report else { return }
        do {
            let plan = try await engine.planRestore(libraryURL: libraryURL, mirrorURL: mirrorURL, libraryReport: report)
            restorePlan = plan
            selectedRestorePaths = Set(plan.restorable.map(\.relativePath))
        } catch {
            statusMessage = Self.message(for: error)
        }
    }

    public func toggleRestoreSelection(_ relativePath: String) {
        if selectedRestorePaths.contains(relativePath) {
            selectedRestorePaths.remove(relativePath)
        } else if restorePlan?.restorable.contains(where: { $0.relativePath == relativePath }) == true {
            selectedRestorePaths.insert(relativePath)
        }
    }

    /// Heal the selected paths from the mirror using the pinned context.
    public func runRestore(context: GuardianRestoreContext) async {
        guard !isRestoring, !context.selectedPaths.isEmpty else { return }
        isRestoring = true
        statusMessage = nil
        defer { isRestoring = false }
        do {
            let result = try await engine.runRestore(context: context)
            lastRestoreResult = result
            restorePlan = nil
            selectedRestorePaths = []
            await scan()
        } catch {
            statusMessage = Self.message(for: error)
        }
    }

    /// Build a pinned restore context from the current plan and selection.
    public func makeRestoreContext(
        libraryIdentity: GuardianLibraryIdentity,
        libraryURL: URL,
        libraryBookmark: FolderBookmark,
        mirrorURL: URL,
        mirrorBookmark: FolderBookmark
    ) -> GuardianRestoreContext? {
        guard let restorePlan, !selectedRestorePaths.isEmpty else { return nil }
        return GuardianRestoreContext(
            libraryIdentity: libraryIdentity,
            libraryURL: libraryURL,
            libraryBookmark: libraryBookmark,
            mirrorURL: mirrorURL,
            mirrorBookmark: mirrorBookmark,
            plan: restorePlan,
            selectedPaths: selectedRestorePaths
        )
    }

    // MARK: - Scheduling (in-app + catch-up)

    /// Called on launch, wake, and each in-app tick. If auto-scrub is due (including
    /// a single catch-up run missed while the app was quit), runs one scan and
    /// re-anchors the schedule. Never runs restore. Auto-mirror is decided by the
    /// caller via `scheduler.shouldAutoMirror` after a clean, complete scrub.
    @discardableResult
    public func runDueScrubIfNeeded(
        interval: TimeInterval,
        autoScrubEnabled: Bool,
        now: Date = Date()
    ) async -> Bool {
        guard let libraryIdentity, let libraryURL, !isScanning else { return false }
        let decision = scheduler.scrubDecision(
            state: scheduleState,
            interval: interval,
            autoScrubEnabled: autoScrubEnabled,
            now: now
        )
        guard decision == .run else { return false }

        isScanning = true
        statusMessage = nil
        let token = GuardianCancellationToken()
        activeToken = token
        var succeeded = false
        do {
            let outcome = try await engine.scan(
                libraryURL: libraryURL,
                libraryIdentity: libraryIdentity,
                isCancelled: { token.isCancelled() }
            )
            report = outcome.report
            lastScanSummary = Self.summarize(outcome.report)
            succeeded = !outcome.report.partialScan
            if outcome.report.hasCorruption, let notifier {
                notifier.notifyBitRotDetected(
                    libraryName: libraryURL.lastPathComponent,
                    corruptCount: outcome.report.count(of: .corrupt)
                )
            }
        } catch {
            statusMessage = "Chronoframe couldn't complete the scheduled integrity scan. Your files were not changed."
        }
        isScanning = false
        activeToken = nil

        scheduleState = scheduler.advance(
            state: scheduleState,
            interval: interval,
            attemptedAt: now,
            succeeded: succeeded
        )
        schedulePersistence.save(scheduleState, for: libraryIdentity)
        return true
    }

    // MARK: - Helpers

    private static func summarize(_ report: GuardianIntegrityReport) -> ScanSummary {
        ScanSummary(
            verified: report.count(of: .verified),
            corrupt: report.count(of: .corrupt),
            modified: report.count(of: .modified),
            missing: report.count(of: .missing),
            newFiles: report.count(of: .new),
            partialScan: report.partialScan,
            generatedAt: report.generatedAt
        )
    }

    private static func message(for error: Error) -> String {
        if let engineError = error as? GuardianEngineError, let description = engineError.errorDescription {
            return description
        }
        return "Chronoframe couldn't complete the Guardian operation. Your files were not changed."
    }
}
