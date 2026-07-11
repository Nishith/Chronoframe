import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

private enum GuardianStoreTestError: Error { case boom }

/// Records engine calls and returns preset results. Tests drive it serially, but
/// the `GuardianEngine` protocol is `Sendable`, so it is `@unchecked Sendable`.
private final class MockGuardianEngine: GuardianEngine, @unchecked Sendable {
    var scanReport: GuardianIntegrityReport
    var restorePlan: GuardianRestorePlan?
    var mirrorResult = GuardianMirrorExecutionResult(copied: [], quarantinedDivergent: [], blockedAtCommit: [], receiptURL: nil)
    var restoreResult = GuardianRestoreExecutionResult(restored: [], blockedAtCommit: [], receiptURL: nil, journalURL: nil)
    var scanShouldThrow = false

    private(set) var scanCount = 0
    private(set) var acceptedPaths: Set<String> = []
    private(set) var acknowledgedPaths: Set<String> = []
    private(set) var lastRestoreContext: GuardianRestoreContext?

    init(scanReport: GuardianIntegrityReport) {
        self.scanReport = scanReport
    }

    func scan(libraryURL: URL, libraryIdentity: GuardianLibraryIdentity, isCancelled: @escaping @Sendable () -> Bool) async throws -> GuardianScanOutcome {
        scanCount += 1
        if scanShouldThrow { throw GuardianStoreTestError.boom }
        return GuardianScanOutcome(report: scanReport, libraryIdentity: libraryIdentity)
    }

    func acceptTrust(relativePaths: Set<String>, report: GuardianIntegrityReport, libraryIdentity: GuardianLibraryIdentity) async throws {
        acceptedPaths = relativePaths
    }

    func acknowledgeDeletions(relativePaths: Set<String>, report: GuardianIntegrityReport, libraryIdentity: GuardianLibraryIdentity) async throws {
        acknowledgedPaths = relativePaths
    }

    func planMirror(context: GuardianMirrorContext, libraryReport: GuardianIntegrityReport) async throws -> GuardianMirrorPlan {
        GuardianMirrorPlan(libraryRoot: context.libraryURL.path, mirrorRoot: context.mirrorURL.path, copies: [], blocked: [], retainedExtras: [], alreadyMirrored: [])
    }

    func runMirror(context: GuardianMirrorContext, plan: GuardianMirrorPlan) async throws -> GuardianMirrorExecutionResult {
        mirrorResult
    }

    func planRestore(libraryURL: URL, mirrorURL: URL, libraryReport: GuardianIntegrityReport) async throws -> GuardianRestorePlan {
        restorePlan ?? GuardianRestorePlan(libraryRoot: libraryURL.path, mirrorRoot: mirrorURL.path, restorable: [], blocked: [])
    }

    func runRestore(context: GuardianRestoreContext) async throws -> GuardianRestoreExecutionResult {
        lastRestoreContext = context
        return restoreResult
    }
}

private final class InMemorySchedulePersistence: GuardianSchedulePersisting, @unchecked Sendable {
    var state = GuardianScheduleState()
    private(set) var saveCount = 0

    func load(for identity: GuardianLibraryIdentity) -> GuardianScheduleState { state }
    func save(_ state: GuardianScheduleState, for identity: GuardianLibraryIdentity) {
        self.state = state
        saveCount += 1
    }
}

private final class RecordingNotifier: GuardianNotifying, @unchecked Sendable {
    private(set) var bitRotNotifications: [(String, Int)] = []
    func notifyBitRotDetected(libraryName: String, corruptCount: Int) {
        bitRotNotifications.append((libraryName, corruptCount))
    }
}

final class GuardianStoreTests: XCTestCase {
    private let identity = GuardianLibraryIdentity(libraryUUID: "lib-uuid")
    private let libraryURL = URL(fileURLWithPath: "/Volumes/Photos/Library")

    private func finding(_ path: String, _ status: GuardianIntegrityStatus, expected: FileIdentity? = nil, observed: FileIdentity? = nil) -> GuardianIntegrityFinding {
        GuardianIntegrityFinding(relativePath: path, status: status, trustState: .trusted, expectedIdentity: expected, observedIdentity: observed)
    }

    private func report(_ findings: [GuardianIntegrityFinding], partial: Bool = false) -> GuardianIntegrityReport {
        GuardianIntegrityReport(libraryRoot: "/lib", findings: findings, partialScan: partial)
    }

    @MainActor
    func testScanPopulatesReportAndSummary() async {
        let engine = MockGuardianEngine(scanReport: report([
            finding("a.jpg", .verified),
            finding("b.jpg", .corrupt),
            finding("c.jpg", .new),
        ]))
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)

        await store.scan()

        XCTAssertEqual(store.lastScanSummary?.verified, 1)
        XCTAssertEqual(store.lastScanSummary?.corrupt, 1)
        XCTAssertEqual(store.lastScanSummary?.newFiles, 1)
        XCTAssertTrue(store.lastScanSummary?.hasFindingsNeedingReview == true)
        XCTAssertFalse(store.isScanning)
    }

    @MainActor
    func testScanNotifiesOnCorruption() async {
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .corrupt), finding("b.jpg", .corrupt)]))
        let notifier = RecordingNotifier()
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence(), notifier: notifier)
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)

        await store.scan()

        XCTAssertEqual(notifier.bitRotNotifications.count, 1)
        XCTAssertEqual(notifier.bitRotNotifications.first?.1, 2)
    }

    @MainActor
    func testScanFailureLeavesReassuringMessageAndNoReport() async {
        let engine = MockGuardianEngine(scanReport: report([]))
        engine.scanShouldThrow = true
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)

        await store.scan()

        XCTAssertNil(store.report)
        XCTAssertNotNil(store.statusMessage)
        XCTAssertFalse(store.isScanning)
    }

    @MainActor
    func testAcceptSelectedTrustForwardsSelectionAndRescans() async {
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .new, observed: FileIdentity(size: 1, digest: "x"))]))
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)
        await store.scan()

        store.toggleTrustSelection("a.jpg")
        await store.acceptSelectedTrust()

        XCTAssertEqual(engine.acceptedPaths, ["a.jpg"])
        XCTAssertTrue(store.selectedTrustPaths.isEmpty)
        XCTAssertEqual(engine.scanCount, 2, "accepting trust re-scans to refresh the report")
    }

    @MainActor
    func testPrepareRestorePreselectsRestorablePaths() async {
        let trusted = FileIdentity(size: 10, digest: "good")
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .corrupt, expected: trusted, observed: FileIdentity(size: 10, digest: "rot"))]))
        engine.restorePlan = GuardianRestorePlan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            restorable: [GuardianRestoreAction(relativePath: "a.jpg", trustedIdentity: trusted, reason: .primaryCorrupt, expectedCurrentPrimaryIdentity: FileIdentity(size: 10, digest: "rot"))],
            blocked: []
        )
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)
        await store.scan()

        await store.prepareRestore(libraryURL: libraryURL, mirrorURL: URL(fileURLWithPath: "/Volumes/Mirror"))

        XCTAssertEqual(store.restorePlan?.restorable.count, 1)
        XCTAssertEqual(store.selectedRestorePaths, ["a.jpg"])
    }

    @MainActor
    func testRunRestoreOnlyHealsSelectedPathsAndRescans() async {
        let trusted = FileIdentity(size: 10, digest: "good")
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .corrupt, expected: trusted, observed: FileIdentity(size: 10, digest: "rot"))]))
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)
        await store.scan()

        let bookmark = FolderBookmark(key: "k", path: "/p", data: Data())
        let context = GuardianRestoreContext(
            libraryIdentity: identity, libraryURL: libraryURL, libraryBookmark: bookmark,
            mirrorURL: URL(fileURLWithPath: "/Volumes/Mirror"), mirrorBookmark: bookmark,
            plan: GuardianRestorePlan(libraryRoot: "/lib", mirrorRoot: "/mir", restorable: [], blocked: []),
            selectedPaths: ["a.jpg"]
        )
        await store.runRestore(context: context)

        XCTAssertEqual(engine.lastRestoreContext?.selectedPaths, ["a.jpg"])
        XCTAssertNil(store.restorePlan)
        XCTAssertEqual(engine.scanCount, 2, "a completed restore re-scans to confirm the heal")
    }

    func testMakeRestoreContextRefusesWhenPlanRootsDifferFromTargetRoots() async {
        let trusted = FileIdentity(size: 10, digest: "good")
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .corrupt, expected: trusted, observed: FileIdentity(size: 10, digest: "rot"))]))
        engine.restorePlan = GuardianRestorePlan(
            libraryRoot: "/lib/A", mirrorRoot: "/mir/A",
            restorable: [GuardianRestoreAction(relativePath: "a.jpg", trustedIdentity: trusted, reason: .primaryCorrupt, expectedCurrentPrimaryIdentity: FileIdentity(size: 10, digest: "rot"))],
            blocked: []
        )
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)
        await store.scan()
        await store.prepareRestore(libraryURL: URL(fileURLWithPath: "/lib/A"), mirrorURL: URL(fileURLWithPath: "/mir/A"))
        XCTAssertNotNil(store.restorePlan)

        let bookmark = FolderBookmark(key: "k", path: "/p", data: Data())
        // Different library root than the plan was built for → refused.
        let mismatched = store.makeRestoreContext(
            libraryIdentity: identity,
            libraryURL: URL(fileURLWithPath: "/lib/B"), libraryBookmark: bookmark,
            mirrorURL: URL(fileURLWithPath: "/mir/A"), mirrorBookmark: bookmark
        )
        XCTAssertNil(mismatched, "a plan reviewed against /lib/A must never be applied to /lib/B")

        // Same roots → allowed.
        let matched = store.makeRestoreContext(
            libraryIdentity: identity,
            libraryURL: URL(fileURLWithPath: "/lib/A"), libraryBookmark: bookmark,
            mirrorURL: URL(fileURLWithPath: "/mir/A"), mirrorBookmark: bookmark
        )
        XCTAssertNotNil(matched)
    }

    func testConfiguringADifferentLibraryClearsStaleReviewState() async {
        let trusted = FileIdentity(size: 10, digest: "good")
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .corrupt, expected: trusted, observed: FileIdentity(size: 10, digest: "rot"))]))
        engine.restorePlan = GuardianRestorePlan(
            libraryRoot: "/lib/A", mirrorRoot: "/mir/A",
            restorable: [GuardianRestoreAction(relativePath: "a.jpg", trustedIdentity: trusted, reason: .primaryCorrupt, expectedCurrentPrimaryIdentity: FileIdentity(size: 10, digest: "rot"))],
            blocked: []
        )
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)
        await store.scan()
        await store.prepareRestore(libraryURL: URL(fileURLWithPath: "/lib/A"), mirrorURL: URL(fileURLWithPath: "/mir/A"))
        XCTAssertNotNil(store.restorePlan)
        XCTAssertNotNil(store.report)

        // Pointing the store at a different library drops the previous library's
        // plan and report so nothing stale can be acted on.
        store.configure(libraryIdentity: GuardianLibraryIdentity(libraryUUID: "different"), libraryURL: URL(fileURLWithPath: "/lib/B"))
        XCTAssertNil(store.restorePlan)
        XCTAssertNil(store.report)
        XCTAssertTrue(store.selectedRestorePaths.isEmpty)
    }

    // MARK: - Scheduling (in-app + catch-up)

    @MainActor
    func testScheduledScrubRunsWhenDueAndPersistsAdvance() async {
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .verified)]))
        let persistence = InMemorySchedulePersistence()
        let store = GuardianStore(engine: engine, schedulePersistence: persistence)
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)

        let now = Date(timeIntervalSince1970: 2_000_000)
        let ran = await store.runDueScrubIfNeeded(interval: 3_600, autoScrubEnabled: true, now: now)

        XCTAssertTrue(ran)
        XCTAssertEqual(engine.scanCount, 1)
        XCTAssertEqual(persistence.state.lastSucceededAt, now)
        XCTAssertEqual(persistence.state.nextRunAt, now.addingTimeInterval(3_600))
        XCTAssertEqual(persistence.saveCount, 1)
    }

    @MainActor
    func testScheduledScrubDoesNotRunWhenNotDue() async {
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .verified)]))
        let persistence = InMemorySchedulePersistence()
        let now = Date(timeIntervalSince1970: 2_000_000)
        persistence.state = GuardianScheduleState(nextRunAt: now.addingTimeInterval(1_000))
        let store = GuardianStore(engine: engine, schedulePersistence: persistence)
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)

        let ran = await store.runDueScrubIfNeeded(interval: 3_600, autoScrubEnabled: true, now: now)

        XCTAssertFalse(ran)
        XCTAssertEqual(engine.scanCount, 0)
    }

    @MainActor
    func testScheduledScrubDisabledDoesNotRun() async {
        let engine = MockGuardianEngine(scanReport: report([finding("a.jpg", .verified)]))
        let store = GuardianStore(engine: engine, schedulePersistence: InMemorySchedulePersistence())
        store.configure(libraryIdentity: identity, libraryURL: libraryURL)

        let ran = await store.runDueScrubIfNeeded(interval: 3_600, autoScrubEnabled: false)

        XCTAssertFalse(ran)
        XCTAssertEqual(engine.scanCount, 0)
    }
}
