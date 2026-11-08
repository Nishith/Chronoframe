#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

// MARK: - Shared doubles (also used by NASPreviewLoaderTests)

/// Implements exactly the six requirements of `NASAssessmentEngine`. If the protocol
/// ever grew a delete, move or trash requirement, this double would stop compiling.
final class NASViewTestEngine: NASAssessmentEngine, @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [String: NASAssessmentSnapshot] = [:]
    private var recordedCalls: [String] = []

    var calls: [String] { lock.lock(); defer { lock.unlock() }; return recordedCalls }

    func setSnapshot(_ snapshot: NASAssessmentSnapshot?, for uuid: String) {
        lock.lock(); snapshots[uuid] = snapshot; lock.unlock()
    }

    private func record(_ name: String) {
        lock.lock(); recordedCalls.append(name); lock.unlock()
    }

    func assess(_ library: NASLibraryRecord, rootURL: URL) throws -> AsyncThrowingStream<NASAssessmentEvent, Error> {
        record("assess")
        return AsyncThrowingStream { _ in }
    }

    func cancel() { record("cancel") }

    func latestSnapshot(for library: NASLibraryRecord) throws -> NASAssessmentSnapshot? {
        record("latestSnapshot")
        lock.lock(); defer { lock.unlock() }
        return snapshots[library.libraryUUID]
    }

    func saveChoice(_ choice: NASReviewChoice, for library: NASLibraryRecord) throws { record("saveChoice") }
    func saveSelectedDigest(_ digest: String?, for library: NASLibraryRecord) throws { record("saveSelectedDigest") }
    func recordPreviewRequest(for library: NASLibraryRecord) throws { record("recordPreviewRequest") }
}

final class NASViewTestFolderAccess: FolderAccessServicing, @unchecked Sendable {
    var resolved: ResolvedFolderBookmark?

    @MainActor func chooseFolder(startingAt path: String?, prompt: String) -> URL? { nil }
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

enum NASViewFixtures {
    static let rootPath = "/Volumes/photo/Photos"

    static func observation() -> NASLibraryObservation {
        NASLibraryObservation(
            volume: NASVolumeObservation(
                kind: .remote,
                fileSystemType: "smbfs",
                mountPoint: "/Volumes/photo",
                serverHost: "diskstation.local",
                shareName: "photo",
                fileSystemID: 7,
                observedPath: rootPath
            ),
            rootRelativePath: "Photos",
            rootFileID: 42,
            shareRootFileID: 2,
            rootCreationTime: 1_700_000_000
        )
    }

    static func record() -> NASLibraryRecord {
        NASLibraryRecord(
            libraryUUID: "LIB-VIEW",
            displayName: "Photos",
            bookmark: FolderBookmark(key: "nasLibrary", path: rootPath, data: Data("bookmark-bytes".utf8)),
            lastObservation: observation(),
            lastValidatedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
    }

    static func group(_ digest: String = "digest-1", members: [String] = ["2019/b.jpg", "2018/a.jpg"]) -> NASExactGroup {
        NASExactGroup(digest: digest, size: 1_000, kind: .photo, memberRelativePaths: members)
    }

    static func snapshot(groups: [NASExactGroup]) -> NASAssessmentSnapshot {
        NASAssessmentSnapshot(
            summary: NASScanSummary(
                generation: 1,
                mode: .exactOnly,
                startedAt: Date(timeIntervalSince1970: 1),
                finishedAt: Date(timeIntervalSince1970: 2),
                outcome: .complete,
                counts: NASScanCounts(),
                ledger: NASByteLedger(),
                exactGroupCount: groups.count,
                redundantLogicalBytes: groups.reduce(0) { $0 + $1.redundantLogicalBytes }
            ),
            groups: groups,
            directories: [],
            issues: [],
            choices: [:],
            selectedDigest: nil
        )
    }
}

/// A store in `completeAssessment` over a temp registry, with every file-system and
/// network seam replaced. Nothing here reads a real NAS.
@MainActor
final class NASViewTestHarness {
    let directory: URL
    let engine = NASViewTestEngine()
    let folderAccess = NASViewTestFolderAccess()
    let store: NASWorkspaceStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("NASLibraryViewTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let registry = NASLibraryRegistry(url: directory.appendingPathComponent("libraries.json"))
        try registry.upsert(NASViewFixtures.record())
        folderAccess.resolved = ResolvedFolderBookmark(url: URL(fileURLWithPath: NASViewFixtures.rootPath, isDirectory: true))
        let observed = NASViewFixtures.observation()
        store = NASWorkspaceStore(
            engine: engine,
            registry: registry,
            folderAccess: folderAccess,
            observe: { _ in observed }
        )
    }

    func loadResults(groups: [NASExactGroup]) async {
        engine.setSnapshot(NASViewFixtures.snapshot(groups: groups), for: "LIB-VIEW")
        await store.loadSavedLibrary()
    }

    func tearDown() {
        try? FileManager.default.removeItem(at: directory)
    }
}

final class NASViewRenderCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var urls: [URL] = []
    func record(_ url: URL) { lock.lock(); urls.append(url); lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return urls.count }
}

// MARK: - Tests

@MainActor
final class NASLibraryViewTests: XCTestCase {
    private var harness: NASViewTestHarness!

    override func setUpWithError() throws {
        harness = try NASViewTestHarness()
    }

    override func tearDown() {
        harness.tearDown()
        harness = nil
    }

    func testNavigationTitleIsNASLibrary() {
        XCTAssertEqual(NASLibraryView.navigationTitle, "NAS Library")
        XCTAssertEqual(NASLibraryView.navigationTitle, SidebarDestination.nasLibrary.title)
    }

    func testEveryStateHasBannerCopy() {
        let expectations: [(NASWorkspaceState, String)] = [
            (.noLibrary, "Choose the top folder of your collection. Chronoframe reads it to find identical copies and changes nothing on the NAS."),
            (.checkingConnection, "Checking the connection to your NAS…"),
            (.needsIdentityConfirmation([.serverHostChanged]), "This share looks slightly different (for example, a new network name). Confirm it's the same library to keep your saved choices."),
            (.differentFolder([.rootFileIDChanged]), "This isn't the library you assessed before. Choose the folder again to start a new assessment."),
            (.waitingForNAS, "Waiting for your NAS. Reconnect the share, then choose Reconnect. Nothing was changed."),
            (.stopping, "Stopping… Chronoframe is finishing the file it's reading."),
            (.completeAssessment, "Assessment complete. Every included folder was checked."),
            (.incompleteAssessment(.completedWithGaps), "Assessment incomplete. Some folders or files couldn't be read, so this isn't a full picture."),
            (.incompleteAssessment(.failed), "Assessment incomplete. Some folders or files couldn't be read, so this isn't a full picture."),
            (.incompleteAssessment(.interruptedVolumeUnavailable), "Assessment incomplete. Some folders or files couldn't be read, so this isn't a full picture."),
            (.incompleteAssessment(.cancelled), "Assessment stopped. Results so far are saved; assess again to finish."),
            (.failed("Choose a folder on a network share. For folders on this Mac, use Deduplicate."), "Choose a folder on a network share. For folders on this Mac, use Deduplicate."),
        ]
        for (state, expected) in expectations {
            XCTAssertEqual(NASLibraryCopy.bannerText(for: state), expected, "\(state)")
        }

        // States whose C-13 copy is not fixed text still say something specific and non-empty.
        let ready = NASLibraryCopy.bannerText(for: .ready)
        XCTAssertFalse(ready.isEmpty)
        XCTAssertTrue(ready.contains("changes nothing on the NAS"))
        for phase in [NASAssessmentPhase.enumerating, .hashing, .grouping] {
            XCTAssertFalse(NASLibraryCopy.bannerText(for: .assessing(phase)).isEmpty, "\(phase)")
        }
        XCTAssertEqual(
            Set([NASAssessmentPhase.enumerating, .hashing, .grouping].map { NASLibraryCopy.bannerText(for: .assessing($0)) }).count,
            3,
            "Each phase reads differently"
        )
    }

    func testButtonCopyMatchesContract() {
        XCTAssertEqual(NASLibraryCopy.emptyTitle, "Assess a photo library on your NAS")
        XCTAssertEqual(NASLibraryCopy.chooseButton, "Choose Folder…")
        XCTAssertEqual(NASLibraryCopy.startButton, "Assess Library")
        XCTAssertEqual(NASLibraryCopy.rescanButton, "Assess Again")
        XCTAssertEqual(NASLibraryCopy.stopButton, "Stop")
        XCTAssertEqual(NASLibraryCopy.reconnectButton, "Reconnect")
        XCTAssertEqual(NASLibraryCopy.confirmButton, "This Is the Same Library")
        XCTAssertEqual(NASLibraryCopy.loadPreviewButton, "Load Preview")
        XCTAssertEqual(NASLibraryCopy.modeBadge, "Assess only")
        XCTAssertEqual(NASLibraryCopy.singleMacNote, "Use one Mac at a time for Chronoframe changes on this NAS.")
        XCTAssertEqual(NASLibraryCopy.keeperNone, "No choice yet")
        XCTAssertEqual(NASLibraryCopy.keeperStale, "Your earlier choice no longer matches these files. Choose again.")
        XCTAssertEqual(NASLibraryCopy.previewCaption, "Loading a preview may read the whole file over the network.")
        XCTAssertEqual(NASLibraryCopy.issuesTitle, "Not checked")
    }

    func testRedundantBytesLabelSaysNotSpaceFreed() {
        let label = NASLibraryCopy.redundantBytesLabel(bytes: 5_000_000)
        XCTAssertTrue(label.contains("in identical extra copies"), label)
        XCTAssertTrue(label.contains("logical size, not space freed"), label)
        XCTAssertFalse(label.lowercased().contains("reclaim"))
        XCTAssertFalse(label.lowercased().contains("save"))
        let formatted = ByteCountFormatter.string(fromByteCount: 5_000_000, countStyle: .file)
        XCTAssertTrue(label.hasPrefix(formatted), label)
    }

    func testKeeperCaptionStatesNoDeletion() {
        XCTAssertEqual(
            NASLibraryCopy.keeperCaption,
            "Your choice is saved on this Mac. Chronoframe doesn't delete or move files on a NAS in this version."
        )
        XCTAssertTrue(NASLibraryCopy.keeperCaption.contains("doesn't delete or move files on a NAS"))
    }

    // AGENTS-INVARIANT: 27
    func testNoDestructiveControlsExist() {
        let forbidden = ["delete", "remove", "move", "trash", "discard", "erase", "clean", "dispose"]

        // The view model's action surface is a closed list; none of it is destructive.
        for action in NASLibraryViewModel.Action.allCases {
            let name = action.rawValue.lowercased()
            for word in forbidden {
                XCTAssertFalse(name.contains(word), "Action \(action.rawValue) looks destructive")
            }
        }
        XCTAssertEqual(
            Set(NASLibraryViewModel.Action.allCases.map(\.rawValue)),
            ["chooseFolder", "startAssessment", "stop", "reconnect", "confirmIdentity", "select", "chooseKeeper", "loadPreview"]
        )

        // Neither the identifiers nor the spoken labels nor the button titles name one.
        let buttonTitles = [
            NASLibraryCopy.chooseButton, NASLibraryCopy.startButton, NASLibraryCopy.rescanButton,
            NASLibraryCopy.stopButton, NASLibraryCopy.reconnectButton, NASLibraryCopy.confirmButton,
            NASLibraryCopy.loadPreviewButton,
        ]
        let everyControlText = AccessibilityIdentifiers.NAS.all
            + Array(NASAccessibilityText.controlLabels.values)
            + buttonTitles
        for text in everyControlText {
            for word in forbidden {
                XCTAssertFalse(text.lowercased().contains(word), "Control text \"\(text)\" looks destructive")
            }
        }
    }

    func testDifferentFolderOffersOnlyChooseFolder() {
        XCTAssertEqual(NASLibraryViewModel.visibleActions(for: .differentFolder([.rootFileIDChanged]), hasLibrary: true), [.chooseFolder])
        XCTAssertEqual(NASLibraryViewModel.visibleActions(for: .noLibrary, hasLibrary: false), [.chooseFolder])
        XCTAssertEqual(NASLibraryViewModel.visibleActions(for: .assessing(.hashing), hasLibrary: true), [.stop])
        XCTAssertEqual(NASLibraryViewModel.visibleActions(for: .needsIdentityConfirmation([.serverHostChanged]), hasLibrary: true), [.confirmIdentity, .chooseFolder])
        XCTAssertEqual(NASLibraryViewModel.visibleActions(for: .waitingForNAS, hasLibrary: true), [.reconnect, .chooseFolder])
        XCTAssertEqual(NASLibraryViewModel.visibleActions(for: .stopping, hasLibrary: true), [])
        XCTAssertEqual(NASLibraryCopy.startTitle(for: .ready), "Assess Library")
        XCTAssertEqual(NASLibraryCopy.startTitle(for: .completeAssessment), "Assess Again")
    }

    func testViewModelNeverTouchesTheEngineOutsideReviewNotes() async {
        await harness.loadResults(groups: [NASViewFixtures.group()])
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: NASPreviewLoader(renderer: { _, _, _ in nil }))
        viewModel.select(digest: "digest-1")
        viewModel.chooseKeeper(digest: "digest-1", relativePath: "2018/a.jpg")
        let allowed: Set<String> = ["latestSnapshot", "saveSelectedDigest", "saveChoice"]
        XCTAssertTrue(Set(harness.engine.calls).isSubset(of: allowed), "\(harness.engine.calls)")
        XCTAssertTrue(harness.engine.calls.contains("saveChoice"))
    }

    func testPreviewURLUsesTheFirstMemberBySortedPath() async {
        await harness.loadResults(groups: [NASViewFixtures.group()])
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: NASPreviewLoader(renderer: { _, _, _ in nil }))
        let url = viewModel.previewURL(for: NASViewFixtures.group())
        XCTAssertEqual(url?.path, "/Volumes/photo/Photos/2018/a.jpg")
    }

    func testPreviewURLRejectsPathsEscapingTheLibraryRoot() async {
        let escaping = NASViewFixtures.group("escape", members: ["../outside.jpg", "../../etc/other.jpg"])
        await harness.loadResults(groups: [escaping])
        let calls = NASViewRenderCalls()
        let loader = NASPreviewLoader(renderer: { url, _, _ in calls.record(url); return nil })
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: loader)

        XCTAssertNil(viewModel.previewURL(for: escaping))
        await viewModel.loadPreview(for: escaping)
        XCTAssertEqual(calls.count, 0, "A path outside the library root must never be rendered")

        // A normal member still resolves inside the root.
        XCTAssertEqual(viewModel.previewURL(for: NASViewFixtures.group())?.path, "/Volumes/photo/Photos/2018/a.jpg")
    }

    func testGroupSelectionRoundTripsThroughTheStore() async {
        await harness.loadResults(groups: [NASViewFixtures.group()])
        let viewModel = NASLibraryViewModel(store: harness.store, previewLoader: NASPreviewLoader(renderer: { _, _, _ in nil }))
        viewModel.select(digest: "digest-1")
        XCTAssertEqual(harness.store.snapshot?.selectedDigest, "digest-1")
        XCTAssertEqual(viewModel.selectedGroup?.digest, "digest-1")
        viewModel.select(digest: nil)
        XCTAssertNil(viewModel.selectedGroup)
    }
}
