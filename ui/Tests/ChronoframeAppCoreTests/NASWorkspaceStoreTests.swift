import Combine
import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

// MARK: - Doubles

/// Implements exactly the six requirements of `NASAssessmentEngine`. If the protocol
/// ever grew a delete, move or trash requirement, this mock would stop compiling.
private final class MockNASEngine: NASAssessmentEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedCalls: [String] = []
    private var continuation: AsyncThrowingStream<NASAssessmentEvent, Error>.Continuation?
    private var snapshotsByLibrary: [String: NASAssessmentSnapshot] = [:]

    var assessError: Error?
    var snapshotError: Error?
    var finishStreamOnCancel = false
    var cancelEvent: NASAssessmentEvent?

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return recordedCalls }
    func count(_ name: String) -> Int { calls.filter { $0 == name }.count }
    var savedChoices: [NASReviewChoice] = []
    var savedDigests: [String?] = []
    var assessedRoots: [URL] = []

    func setSnapshot(_ snapshot: NASAssessmentSnapshot?, for uuid: String) {
        lock.lock(); snapshotsByLibrary[uuid] = snapshot; lock.unlock()
    }

    private func record(_ name: String) {
        lock.lock(); recordedCalls.append(name); lock.unlock()
    }

    func assess(_ library: NASLibraryRecord, rootURL: URL) throws -> AsyncThrowingStream<NASAssessmentEvent, Error> {
        record("assess")
        if let assessError { throw assessError }
        lock.lock(); assessedRoots.append(rootURL); lock.unlock()
        return AsyncThrowingStream { continuation in
            self.lock.lock(); self.continuation = continuation; self.lock.unlock()
        }
    }

    func emit(_ event: NASAssessmentEvent) {
        lock.lock(); let continuation = continuation; lock.unlock()
        continuation?.yield(event)
    }

    func finishStream(throwing error: Error? = nil) {
        lock.lock(); let continuation = continuation; self.continuation = nil; lock.unlock()
        if let error { continuation?.finish(throwing: error) } else { continuation?.finish() }
    }

    func cancel() {
        record("cancel")
        if let cancelEvent { emit(cancelEvent) }
        if finishStreamOnCancel { finishStream() }
    }

    func latestSnapshot(for library: NASLibraryRecord) throws -> NASAssessmentSnapshot? {
        record("latestSnapshot")
        if let snapshotError { throw snapshotError }
        lock.lock(); defer { lock.unlock() }
        return snapshotsByLibrary[library.libraryUUID]
    }

    func saveChoice(_ choice: NASReviewChoice, for library: NASLibraryRecord) throws {
        record("saveChoice")
        lock.lock(); savedChoices.append(choice); lock.unlock()
    }

    func saveSelectedDigest(_ digest: String?, for library: NASLibraryRecord) throws {
        record("saveSelectedDigest")
        lock.lock(); savedDigests.append(digest); lock.unlock()
    }

    func recordPreviewRequest(for library: NASLibraryRecord) throws {
        record("recordPreviewRequest")
    }
}

private final class MockNASFolderAccess: FolderAccessServicing, @unchecked Sendable {
    var resolved: ResolvedFolderBookmark?
    var chosen: URL?
    private(set) var chooseRequests: [(startingAt: String?, allowNetworkStart: Bool)] = []

    @MainActor func chooseFolder(startingAt path: String?, prompt: String) -> URL? {
        chooseFolder(startingAt: path, prompt: prompt, allowNetworkStart: false)
    }

    @MainActor func chooseFolder(startingAt path: String?, prompt: String, allowNetworkStart: Bool) -> URL? {
        chooseRequests.append((path, allowNetworkStart))
        return chosen
    }

    func makeBookmark(for url: URL, key: String) throws -> FolderBookmark {
        FolderBookmark(key: key, path: url.path, data: Data("bm:\(url.path)".utf8))
    }

    @MainActor func resolveBookmark(_ bookmark: FolderBookmark) -> ResolvedFolderBookmark? { resolved }
    @MainActor func scopedAccess(for bookmarks: [FolderBookmark]) -> SecurityScopedFolderAccess { SecurityScopedFolderAccess() }
    @MainActor func verifiedScopedAccess(for bookmarks: [FolderBookmark]) -> ScopedAccessOutcome {
        ScopedAccessOutcome(access: SecurityScopedFolderAccess(), startedKeys: [])
    }
    func validateFolder(_ url: URL, role: FolderRole) throws {}
}

private final class ObservationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var byPath: [String: NASLibraryObservation] = [:]
    func set(_ observation: NASLibraryObservation?, forPath path: String) {
        lock.lock(); byPath[path] = observation; lock.unlock()
    }
    func observe(_ url: URL) -> NASLibraryObservation? {
        lock.lock(); defer { lock.unlock() }
        return byPath[url.path]
    }
}

// MARK: - Tests

@MainActor
final class NASWorkspaceStoreTests: XCTestCase {
    private var directory: URL!
    private var registry: NASLibraryRegistry!
    private var engine: MockNASEngine!
    private var folderAccess: MockNASFolderAccess!
    private var observations: ObservationBox!
    private var record: NASLibraryRecord!
    private var store: NASWorkspaceStore!

    private let savedURL = URL(fileURLWithPath: "/Volumes/photo/Photos", isDirectory: true)
    private let now = Date(timeIntervalSince1970: 1_900_000_000)

    override func setUp() async throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASWorkspaceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        registry = NASLibraryRegistry(url: directory.appendingPathComponent("libraries.json"))
        engine = MockNASEngine()
        folderAccess = MockNASFolderAccess()
        folderAccess.resolved = ResolvedFolderBookmark(url: savedURL)
        observations = ObservationBox()
        record = nasTestRecord(uuid: "LIB-OLD")
        makeStore()
    }

    override func tearDown() async throws {
        store = nil
        try? FileManager.default.removeItem(at: directory)
        directory = nil
    }

    private func makeStore() {
        let box = observations!
        let fixedNow = now
        store = NASWorkspaceStore(
            engine: engine,
            registry: registry,
            folderAccess: folderAccess,
            observe: { box.observe($0) },
            now: { fixedNow }
        )
    }

    private func saveRecordAndObserve(_ observed: NASLibraryObservation?) throws {
        try registry.upsert(record)
        observations.set(observed, forPath: savedURL.path)
    }

    private func group(_ digest: String = "d1", members: [String] = ["a.jpg", "b.jpg"]) -> NASExactGroup {
        NASExactGroup(digest: digest, size: 100, kind: .photo, memberRelativePaths: members)
    }

    private func summary(_ outcome: NASScanOutcome, generation: Int64 = 1) -> NASScanSummary {
        NASScanSummary(
            generation: generation,
            mode: .exactOnly,
            startedAt: Date(timeIntervalSince1970: 1),
            finishedAt: Date(timeIntervalSince1970: 2),
            outcome: outcome,
            counts: NASScanCounts(),
            ledger: NASByteLedger(),
            exactGroupCount: 1,
            redundantLogicalBytes: 100
        )
    }

    private func snapshot(
        outcome: NASScanOutcome = .complete,
        groups: [NASExactGroup]? = nil,
        choices: [String: NASReviewChoice] = [:],
        issues: [NASIssue] = []
    ) -> NASAssessmentSnapshot {
        NASAssessmentSnapshot(
            summary: summary(outcome),
            groups: groups ?? [group()],
            directories: [],
            issues: issues,
            choices: choices,
            selectedDigest: nil
        )
    }

    private func readyStore(snapshot readySnapshot: NASAssessmentSnapshot? = nil) async throws {
        engine.setSnapshot(readySnapshot, for: record.libraryUUID)
        try saveRecordAndObserve(record.lastObservation)
        await store.loadSavedLibrary()
    }

    private func waitFor(_ condition: @escaping @MainActor () -> Bool) async -> Bool {
        await waitForCondition(timeoutNanoseconds: 3_000_000_000, condition)
    }

    // MARK: Validation

    func testLoadSavedLibrarySameGoesReady() async throws {
        XCTAssertEqual(store.state, .noLibrary)
        var states: [NASWorkspaceState] = []
        let cancellable = store.$state.sink { states.append($0) }
        defer { cancellable.cancel() }

        try saveRecordAndObserve(record.lastObservation)
        await store.loadSavedLibrary()

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.library?.libraryUUID, "LIB-OLD")
        XCTAssertEqual(store.library?.lastValidatedAt, now)
        XCTAssertTrue(states.contains(.checkingConnection), "States seen: \(states)")
        XCTAssertNil(store.snapshot)
    }

    func testLoadSavedLibraryWithNoRecordStaysNoLibrary() async {
        await store.loadSavedLibrary()
        XCTAssertEqual(store.state, .noLibrary)
        XCTAssertNil(store.library)
    }

    func testRemountUpdatesRecordAndGoesReady() async throws {
        var remounted = record.lastObservation
        remounted.volume.mountPoint = "/Volumes/photo-1"
        try saveRecordAndObserve(remounted)

        await store.loadSavedLibrary()

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.library?.lastObservation.volume.mountPoint, "/Volumes/photo-1")
        let persisted = try registry.load()
        XCTAssertEqual(persisted.first?.lastObservation.volume.mountPoint, "/Volumes/photo-1")
        XCTAssertEqual(persisted.first?.libraryUUID, "LIB-OLD")
    }

    func testAmbiguousRequiresConfirmation() async throws {
        var changedHost = record.lastObservation
        changedHost.volume.serverHost = "192.168.1.20"
        try saveRecordAndObserve(changedHost)

        await store.loadSavedLibrary()

        XCTAssertEqual(store.state, .needsIdentityConfirmation([.serverHostChanged]))
        store.startAssessment()
        XCTAssertEqual(store.state, .needsIdentityConfirmation([.serverHostChanged]), "Assessment must not start before confirmation")
        XCTAssertEqual(engine.count("assess"), 0)
        XCTAssertEqual(try registry.load().first?.lastObservation.volume.serverHost, "nas.local", "Nothing is saved until the user confirms")
    }

    func testConfirmIdentityAcceptsAndKeepsChoices() async throws {
        let choice = NASReviewChoice(digest: "d1", size: 100, keeperRelativePath: "a.jpg", reviewedAt: now)
        engine.setSnapshot(snapshot(choices: ["d1": choice]), for: "LIB-OLD")
        var changedHost = record.lastObservation
        changedHost.volume.serverHost = "192.168.1.20"
        try saveRecordAndObserve(changedHost)
        await store.loadSavedLibrary()
        XCTAssertEqual(store.state, .needsIdentityConfirmation([.serverHostChanged]))

        await store.confirmIdentity()

        XCTAssertEqual(store.state, .completeAssessment)
        XCTAssertEqual(store.library?.libraryUUID, "LIB-OLD", "Confirming keeps the same library, so choices stay")
        XCTAssertEqual(store.library?.lastObservation.volume.serverHost, "192.168.1.20")
        XCTAssertEqual(store.snapshot?.choices["d1"], choice)
        XCTAssertEqual(try registry.load().first?.lastObservation.volume.serverHost, "192.168.1.20")

        // Outside the confirmation state it does nothing.
        await store.confirmIdentity()
        XCTAssertEqual(store.state, .completeAssessment)
    }

    func testMismatchShowsDifferentFolderAndNewChoiceGetsNewUUID() async throws {
        let choice = NASReviewChoice(digest: "d1", size: 100, keeperRelativePath: "a.jpg", reviewedAt: now)
        engine.setSnapshot(snapshot(choices: ["d1": choice]), for: "LIB-OLD")
        var different = record.lastObservation
        different.rootFileID = 999
        try saveRecordAndObserve(different)

        await store.loadSavedLibrary()
        XCTAssertEqual(store.state, .differentFolder([.rootFileIDChanged]))

        let chosenURL = URL(fileURLWithPath: "/Volumes/photo/Other", isDirectory: true)
        folderAccess.chosen = chosenURL
        observations.set(nasTestObservation(relativePath: "Other", rootFileID: 555), forPath: chosenURL.path)
        await store.chooseLibrary()

        XCTAssertEqual(store.state, .ready)
        let newUUID = try XCTUnwrap(store.library?.libraryUUID)
        XCTAssertNotEqual(newUUID, "LIB-OLD")
        XCTAssertEqual(store.library?.displayName, "Other")
        XCTAssertNil(store.snapshot, "No choices or results carry over to a new library")
        let persisted = try registry.load()
        XCTAssertEqual(persisted.map(\.libraryUUID), [newUUID], "The workspace keeps one library at a time")
    }

    func testChoosingTheSameLibraryAgainKeepsItsUUID() async throws {
        try saveRecordAndObserve(nil)
        await store.loadSavedLibrary()
        XCTAssertEqual(store.state, .waitingForNAS)

        folderAccess.chosen = savedURL
        observations.set(record.lastObservation, forPath: savedURL.path)
        await store.chooseLibrary()

        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(store.library?.libraryUUID, "LIB-OLD")
        XCTAssertEqual(try registry.load().count, 1)
    }

    func testAmbiguousRepickRequiresConfirmationAndKeepsChoices() async throws {
        let choice = NASReviewChoice(digest: "d1", size: 100, keeperRelativePath: "a.jpg", reviewedAt: now)
        try await readyStore(snapshot: snapshot(choices: ["d1": choice]))
        XCTAssertEqual(store.state, .completeAssessment)

        // The user picks the same folder again, but the server name differs (D-NAS-30).
        let repicked = URL(fileURLWithPath: "/Volumes/photo-2/Photos", isDirectory: true)
        var viaIP = record.lastObservation
        viaIP.volume.serverHost = "192.168.1.20"
        viaIP.volume.mountPoint = "/Volumes/photo-2"
        folderAccess.chosen = repicked
        observations.set(viaIP, forPath: repicked.path)

        await store.chooseLibrary()

        XCTAssertEqual(store.state, .needsIdentityConfirmation([.serverHostChanged]))
        XCTAssertEqual(store.library?.libraryUUID, "LIB-OLD", "An ambiguous folder is not silently a new library")
        XCTAssertEqual(try registry.load().map(\.libraryUUID), ["LIB-OLD"])
        XCTAssertEqual(try registry.load().first?.lastObservation.volume.serverHost, "nas.local", "Nothing is saved until the user confirms")
        store.startAssessment()
        XCTAssertEqual(engine.count("assess"), 0)

        await store.confirmIdentity()

        XCTAssertEqual(store.state, .completeAssessment)
        XCTAssertEqual(store.library?.libraryUUID, "LIB-OLD")
        XCTAssertEqual(store.snapshot?.choices["d1"], choice)
        let saved = try XCTUnwrap(try registry.load().first)
        XCTAssertEqual(saved.lastObservation.volume.serverHost, "192.168.1.20")
        XCTAssertEqual(saved.bookmark.path, repicked.path, "The newly chosen folder becomes the saved bookmark")
        store.startAssessment()
        XCTAssertEqual(engine.assessedRoots, [repicked], "The confirmed folder is the one assessed")
    }

    func testMismatchClearsPreviousReviewAndBlocksEdits() async throws {
        let choice = NASReviewChoice(digest: "d1", size: 100, keeperRelativePath: "a.jpg", reviewedAt: now)
        try await readyStore(snapshot: snapshot(choices: ["d1": choice]))
        store.select(digest: "d1")
        store.requestPreview(digest: "d1")
        XCTAssertNotNil(store.snapshot)
        XCTAssertEqual(store.previewRequestedDigests, ["d1"])
        let savedBefore = engine.count("saveChoice")
        let selectedBefore = engine.count("saveSelectedDigest")
        let previewsBefore = engine.count("recordPreviewRequest")

        var different = record.lastObservation
        different.rootFileID = 999
        observations.set(different, forPath: savedURL.path)
        await store.reconnect()

        XCTAssertEqual(store.state, .differentFolder([.rootFileIDChanged]))
        XCTAssertNil(store.snapshot, "The previous library's results must not stay under 'different folder'")
        XCTAssertTrue(store.previewRequestedDigests.isEmpty)

        store.chooseKeeper(digest: "d1", relativePath: "b.jpg")
        store.select(digest: "d1")
        store.requestPreview(digest: "d1")
        XCTAssertEqual(engine.count("saveChoice"), savedBefore, "No engine call may edit the old library's review")
        XCTAssertEqual(engine.count("saveSelectedDigest"), selectedBefore)
        XCTAssertEqual(engine.count("recordPreviewRequest"), previewsBefore)
        XCTAssertTrue(store.previewRequestedDigests.isEmpty)
        XCTAssertNil(store.snapshot)
    }

    func testReviewEditsAreIgnoredOutsideResultStates() async throws {
        try await readyStore(snapshot: snapshot())
        store.startAssessment()
        XCTAssertEqual(store.state, .assessing(.enumerating))
        store.chooseKeeper(digest: "d1", relativePath: "a.jpg")
        store.select(digest: "d1")
        store.requestPreview(digest: "d1")
        XCTAssertEqual(engine.count("saveChoice"), 0)
        XCTAssertEqual(engine.count("saveSelectedDigest"), 0)
        XCTAssertEqual(engine.count("recordPreviewRequest"), 0)
        engine.finishStream()
    }

    func testUnreachableBookmarkGoesWaitingForNAS() async throws {
        try saveRecordAndObserve(record.lastObservation)
        folderAccess.resolved = nil
        await store.loadSavedLibrary()
        XCTAssertEqual(store.state, .waitingForNAS)
        XCTAssertEqual(store.library?.libraryUUID, "LIB-OLD")

        // Resolves but the share does not answer.
        folderAccess.resolved = ResolvedFolderBookmark(url: savedURL)
        observations.set(nil, forPath: savedURL.path)
        await store.reconnect()
        XCTAssertEqual(store.state, .waitingForNAS)

        // The share comes back.
        observations.set(record.lastObservation, forPath: savedURL.path)
        await store.reconnect()
        XCTAssertEqual(store.state, .ready)
    }

    func testChooseLocalFolderIsRefused() async throws {
        let localURL = URL(fileURLWithPath: "/Users/someone/Pictures", isDirectory: true)
        folderAccess.chosen = localURL
        observations.set(
            nasTestObservation(kind: .local, fileSystemType: "apfs", mountPoint: "/", serverHost: nil, shareName: nil, relativePath: "Users/someone/Pictures"),
            forPath: localURL.path
        )

        await store.chooseLibrary()

        XCTAssertEqual(store.state, .failed("Choose a folder on a network share. For folders on this Mac, use Deduplicate."))
        XCTAssertEqual(try registry.load(), [], "A refused folder is never saved")
        XCTAssertNil(store.library)
        XCTAssertEqual(folderAccess.chooseRequests.count, 1)
        XCTAssertTrue(folderAccess.chooseRequests[0].allowNetworkStart)
    }

    func testChooseCancelledLeavesStateAlone() async throws {
        folderAccess.chosen = nil
        await store.chooseLibrary()
        XCTAssertEqual(store.state, .noLibrary)
    }

    // MARK: Assessment lifecycle

    func testStartStopTransitions() async throws {
        store.startAssessment()
        XCTAssertEqual(store.state, .noLibrary, "Start is ignored without a library")
        XCTAssertEqual(engine.count("assess"), 0)

        try await readyStore()
        XCTAssertEqual(store.state, .ready)

        store.startAssessment()
        XCTAssertEqual(store.state, .assessing(.enumerating))
        XCTAssertEqual(engine.assessedRoots, [savedURL])
        store.startAssessment()
        XCTAssertEqual(engine.count("assess"), 1, "A second start while assessing is ignored")

        engine.emit(.started(generation: 1))
        engine.emit(.enumerationProgress(directories: 3, files: 40, currentRelativePath: "2020/Trip"))
        let enumerating = await waitFor { self.store.progress.files == 40 }
        XCTAssertTrue(enumerating)
        XCTAssertEqual(store.progress.directories, 3)
        XCTAssertEqual(store.progress.currentRelativePath, "2020/Trip")

        engine.emit(.phaseStarted(.hashing))
        engine.emit(.hashingProgress(completed: 5, total: 20, bytesRead: 1_000))
        let hashing = await waitFor { self.store.state == .assessing(.hashing) && self.store.progress.hashed == 5 }
        XCTAssertTrue(hashing)
        XCTAssertEqual(store.progress.hashTotal, 20)

        engine.cancelEvent = .finished(summary(.cancelled))
        engine.finishStreamOnCancel = true
        engine.setSnapshot(snapshot(outcome: .cancelled), for: "LIB-OLD")
        store.stop()
        XCTAssertEqual(store.state, .stopping)
        XCTAssertEqual(engine.count("cancel"), 1)

        let finished = await waitFor { self.store.state == .incompleteAssessment(.cancelled) }
        XCTAssertTrue(finished, "State was \(store.state)")
        XCTAssertEqual(store.snapshot?.summary.outcome, .cancelled)

        // Assess Again is allowed from an incomplete result.
        engine.cancelEvent = nil
        store.startAssessment()
        XCTAssertEqual(store.state, .assessing(.enumerating))
        XCTAssertEqual(engine.count("assess"), 2)
        engine.emit(.finished(summary(.complete, generation: 2)))
        engine.setSnapshot(snapshot(outcome: .complete), for: "LIB-OLD")
        engine.finishStream()
        let done = await waitFor { self.store.state == .completeAssessment }
        XCTAssertTrue(done, "State was \(store.state)")
    }

    func testStopOutsideAssessmentDoesNothing() async throws {
        try await readyStore()
        store.stop()
        XCTAssertEqual(store.state, .ready)
        XCTAssertEqual(engine.count("cancel"), 0)
    }

    func testVolumeInterruptionGoesWaitingForNAS() async throws {
        try await readyStore()
        store.startAssessment()
        engine.setSnapshot(snapshot(outcome: .interruptedVolumeUnavailable), for: "LIB-OLD")
        engine.emit(.finished(summary(.interruptedVolumeUnavailable)))
        engine.finishStream()

        let waiting = await waitFor { self.store.state == .waitingForNAS }
        XCTAssertTrue(waiting, "State was \(store.state)")

        // Reconnect revalidates and shows the saved partial result without scanning again.
        await store.reconnect()
        XCTAssertEqual(store.state, .incompleteAssessment(.interruptedVolumeUnavailable))
        XCTAssertEqual(engine.count("assess"), 1)
    }

    func testIncompleteOutcomeShowsIncomplete() async throws {
        try await readyStore()
        store.startAssessment()
        engine.setSnapshot(snapshot(outcome: .completedWithGaps), for: "LIB-OLD")
        engine.emit(.finished(summary(.completedWithGaps)))
        engine.finishStream()
        let incomplete = await waitFor { self.store.state == .incompleteAssessment(.completedWithGaps) }
        XCTAssertTrue(incomplete, "State was \(store.state)")
        XCTAssertEqual(store.snapshot?.summary.outcome, .completedWithGaps)

        // A saved incomplete result is shown as incomplete after a relaunch too.
        makeStore()
        await store.loadSavedLibrary()
        XCTAssertEqual(store.state, .incompleteAssessment(.completedWithGaps))

        engine.setSnapshot(snapshot(outcome: .complete), for: "LIB-OLD")
        makeStore()
        await store.loadSavedLibrary()
        XCTAssertEqual(store.state, .completeAssessment)
    }

    func testStreamErrorBecomesPlainFailure() async throws {
        try await readyStore()
        store.startAssessment()
        engine.finishStream(throwing: NASAssessmentError.storeFailed(message: "SQLITE_IOERR 10"))
        let failed = await waitFor { if case .failed = self.store.state { return true } else { return false } }
        XCTAssertTrue(failed)
        guard case let .failed(message) = store.state else { return }
        XCTAssertEqual(message, NASAssessmentError.storeFailed(message: "").errorDescription)
        XCTAssertFalse(message.contains("SQLITE"))
    }

    func testRawPOSIXErrorsAreMappedToPlainText() async throws {
        try await readyStore()
        engine.assessError = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO), userInfo: [NSLocalizedDescriptionKey: "Input/output error"])
        store.startAssessment()
        guard case let .failed(message) = store.state else { return XCTFail("State was \(store.state)") }
        XCTAssertFalse(message.contains("Input/output"))
        XCTAssertFalse(message.contains("errno"))
        XCTAssertFalse(message.contains("5"))
        XCTAssertTrue(message.contains("Nothing on the NAS was changed"))
    }

    func testUnresolvedIssueDetailIsPlainText() async throws {
        let issues = [
            NASIssue(category: .unresolvedCandidate, relativePath: "a.jpg", detail: NASUnresolvedReason.modificationTimeChanged.rawValue),
            NASIssue(category: .unresolvedCandidate, relativePath: "b.jpg", detail: NASUnresolvedReason.volumeUnavailable.rawValue),
            NASIssue(category: .skippedLink, relativePath: "c", detail: "Links are reported but never followed."),
        ]
        try await readyStore(snapshot: snapshot(outcome: .completedWithGaps, issues: issues))
        let shown = try XCTUnwrap(store.snapshot?.issues)
        for issue in shown where issue.category == .unresolvedCandidate {
            for reason in NASUnresolvedReason.allCases {
                XCTAssertNotEqual(issue.detail, reason.rawValue)
            }
            XCTAssertTrue(issue.detail.hasSuffix("."), "Plain sentence expected: \(issue.detail)")
        }
        XCTAssertEqual(shown[2], issues[2], "Other issue details are already plain and stay as they are")
    }

    // MARK: Review

    func testSelectNeverRequestsPreview() async throws {
        try await readyStore(snapshot: snapshot())
        store.select(digest: "d1")
        XCTAssertEqual(store.snapshot?.selectedDigest, "d1")
        store.select(digest: nil)
        XCTAssertNil(store.snapshot?.selectedDigest)

        XCTAssertEqual(engine.savedDigests, ["d1", nil])
        XCTAssertEqual(engine.count("recordPreviewRequest"), 0)
        XCTAssertTrue(store.previewRequestedDigests.isEmpty)
    }

    func testRequestPreviewIsTheOnlyPreviewTrigger() async throws {
        try await readyStore(snapshot: snapshot())
        store.select(digest: "d1")
        store.chooseKeeper(digest: "d1", relativePath: "a.jpg")
        store.startAssessment()
        engine.finishStream()
        _ = await waitFor { self.store.state != .assessing(.enumerating) }
        XCTAssertEqual(engine.count("recordPreviewRequest"), 0)
        XCTAssertTrue(store.previewRequestedDigests.isEmpty)

        store.requestPreview(digest: "d1")
        XCTAssertEqual(store.previewRequestedDigests, ["d1"])
        XCTAssertEqual(engine.count("recordPreviewRequest"), 1)
    }

    func testChooseKeeperSavesAChoiceKeyedByDigest() async throws {
        try await readyStore(snapshot: snapshot())
        store.chooseKeeper(digest: "d1", relativePath: "b.jpg")
        let choice = try XCTUnwrap(engine.savedChoices.last)
        XCTAssertEqual(choice, NASReviewChoice(digest: "d1", size: 100, keeperRelativePath: "b.jpg", reviewedAt: now))
        XCTAssertEqual(store.snapshot?.choices["d1"], choice)

        store.chooseKeeper(digest: "d1", relativePath: nil)
        XCTAssertNil(store.snapshot?.choices["d1"]?.keeperRelativePath)
        store.chooseKeeper(digest: "unknown", relativePath: "x")
        XCTAssertEqual(engine.savedChoices.count, 2, "A digest that is not in the results is ignored")
    }

    func testStaleChoiceDetected() async throws {
        let target = group()
        let staleChoice = NASReviewChoice(digest: "d1", size: 100, keeperRelativePath: "gone.jpg", reviewedAt: now)
        try await readyStore(snapshot: snapshot(groups: [target], choices: ["d1": staleChoice]))
        XCTAssertTrue(store.isChoiceStale(target))

        store.chooseKeeper(digest: "d1", relativePath: "a.jpg")
        XCTAssertFalse(store.isChoiceStale(target))

        store.chooseKeeper(digest: "d1", relativePath: nil)
        XCTAssertFalse(store.isChoiceStale(target), "No keeper chosen is not stale")
        XCTAssertFalse(store.isChoiceStale(group("other")), "No saved choice is not stale")
    }

    // AGENTS-INVARIANT: 27
    func testSavedReviewIsNotMutationAuthority() async throws {
        // A real library folder that must come through untouched.
        let library = directory.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(at: library, withIntermediateDirectories: true)
        try Data("one".utf8).write(to: library.appendingPathComponent("a.jpg"))
        try Data("one".utf8).write(to: library.appendingPathComponent("b.jpg"))
        func listing() throws -> [String: Data] {
            var result: [String: Data] = [:]
            for name in try FileManager.default.contentsOfDirectory(atPath: library.path).sorted() {
                result[name] = try Data(contentsOf: library.appendingPathComponent(name))
            }
            return result
        }
        let before = try listing()

        let choice = NASReviewChoice(digest: "d1", size: 3, keeperRelativePath: "a.jpg", reviewedAt: now)
        try await readyStore(snapshot: snapshot(choices: ["d1": choice]))
        store.select(digest: "d1")
        store.chooseKeeper(digest: "d1", relativePath: "b.jpg")
        store.requestPreview(digest: "d1")
        store.startAssessment()
        engine.emit(.finished(summary(.complete)))
        engine.finishStream()
        _ = await waitFor { self.store.state == .completeAssessment }
        await store.reconnect()

        let allowed: Set<String> = ["assess", "cancel", "latestSnapshot", "saveChoice", "saveSelectedDigest", "recordPreviewRequest"]
        XCTAssertTrue(Set(engine.calls).isSubset(of: allowed), "Unexpected engine calls: \(engine.calls)")
        XCTAssertEqual(try listing(), before, "Saved choices never delete, move or trash anything")
    }
}
