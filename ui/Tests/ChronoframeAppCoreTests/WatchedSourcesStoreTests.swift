import Foundation
import XCTest
@testable import ChronoframeAppCore

@MainActor
final class WatchedSourcesStoreTests: XCTestCase {
    private func makeSource(path: String = "/tmp/watched", label: String = "watched", generation: Int64 = 0) -> WatchedSource {
        WatchedSource(path: path, label: label, changeGeneration: generation)
    }

    // MARK: - Registration guard

    func testRegistrationRejectsSourceInsideDestination() {
        let conflict = WatchedSourcesStore.registrationConflict(
            candidatePath: "/library/incoming",
            destinationPaths: ["/library"],
            existingWatchedPaths: []
        )
        XCTAssertEqual(conflict, .overlapsDestination(.sourceInsideDestination))
    }

    func testRegistrationRejectsDestinationInsideCandidate() {
        let conflict = WatchedSourcesStore.registrationConflict(
            candidatePath: "/photos",
            destinationPaths: ["/photos/organized"],
            existingWatchedPaths: []
        )
        XCTAssertEqual(conflict, .overlapsDestination(.destinationInsideSource))
    }

    func testRegistrationRejectsEqualCandidateAndDestination() {
        let conflict = WatchedSourcesStore.registrationConflict(
            candidatePath: "/library",
            destinationPaths: ["/library"],
            existingWatchedPaths: []
        )
        XCTAssertEqual(conflict, .overlapsDestination(.sourceInsideDestination))
    }

    func testRegistrationChecksDedupeDestinationToo() {
        let conflict = WatchedSourcesStore.registrationConflict(
            candidatePath: "/dedupe-folder/sub",
            destinationPaths: ["/library", "/dedupe-folder"],
            existingWatchedPaths: []
        )
        XCTAssertEqual(conflict, .overlapsDestination(.sourceInsideDestination))
    }

    func testRegistrationRejectsNestingWithExistingWatchedFolder() {
        XCTAssertEqual(
            WatchedSourcesStore.registrationConflict(
                candidatePath: "/watched/sub",
                destinationPaths: [],
                existingWatchedPaths: ["/watched"]
            ),
            .overlapsWatchedFolder(existingPath: "/watched")
        )
        XCTAssertEqual(
            WatchedSourcesStore.registrationConflict(
                candidatePath: "/parent",
                destinationPaths: [],
                existingWatchedPaths: ["/parent/child"]
            ),
            .overlapsWatchedFolder(existingPath: "/parent/child")
        )
    }

    func testRegistrationRejectsDuplicatePath() {
        XCTAssertEqual(
            WatchedSourcesStore.registrationConflict(
                candidatePath: "/watched",
                destinationPaths: [],
                existingWatchedPaths: ["/watched"]
            ),
            .alreadyWatched(path: "/watched")
        )
    }

    func testRegistrationStandardizesPathsBeforeComparing() {
        let conflict = WatchedSourcesStore.registrationConflict(
            candidatePath: "/library/a/../incoming",
            destinationPaths: ["/library"],
            existingWatchedPaths: []
        )
        XCTAssertEqual(conflict, .overlapsDestination(.sourceInsideDestination))
    }

    func testRegistrationAcceptsDisjointSiblings() {
        XCTAssertNil(
            WatchedSourcesStore.registrationConflict(
                candidatePath: "/photos-inbox",
                destinationPaths: ["/photos", ""],
                existingWatchedPaths: ["/downloads"]
            )
        )
    }

    func testRegistrationIgnoresEmptyDestinationPaths() {
        XCTAssertNil(
            WatchedSourcesStore.registrationConflict(
                candidatePath: "/anywhere",
                destinationPaths: ["", "   "],
                existingWatchedPaths: []
            )
        )
    }

    func testRegistrationErrorCopyIsPlainAndActionable() {
        let inside = WatchedSourceRegistrationError.overlapsDestination(.sourceInsideDestination)
        XCTAssertTrue(inside.errorDescription?.contains("see its own copies as new items") == true)
        let nested = WatchedSourceRegistrationError.overlapsWatchedFolder(existingPath: "/x")
        XCTAssertTrue(nested.errorDescription?.contains("count the same photos twice") == true)
    }

    // MARK: - State mutators

    func testLoadInsertRemoveAndLookup() {
        let store = WatchedSourcesStore()
        let a = makeSource(path: "/a", label: "a")
        let b = makeSource(path: "/b", label: "b")

        store.load([a])
        XCTAssertEqual(store.states.map(\.id), [a.id])

        store.insert(b)
        XCTAssertEqual(store.states.count, 2)
        store.insert(b)
        XCTAssertEqual(store.states.count, 2, "Duplicate insert is a no-op")

        store.remove(id: a.id)
        XCTAssertEqual(store.states.map(\.id), [b.id])
        XCTAssertNil(store.state(for: a.id))
    }

    func testAvailabilityTransitionsClearCheckingWhenLeavingAvailable() {
        let store = WatchedSourcesStore()
        let source = makeSource()
        store.load([source])
        store.setAvailability(id: source.id, .available)
        store.setChecking(id: source.id, true)

        store.setAvailability(id: source.id, .unavailable)

        let state = store.state(for: source.id)
        XCTAssertEqual(state?.availability, .unavailable)
        XCTAssertEqual(state?.isChecking, false)
    }

    func testCompleteScanUpdatesEstimateAndClearsPartialFlag() {
        let store = WatchedSourcesStore()
        let source = makeSource()
        store.load([source])
        store.markPartialScan(id: source.id)
        XCTAssertEqual(store.state(for: source.id)?.lastScanWasPartial, true)

        let scanDate = Date(timeIntervalSince1970: 1_000)
        store.applyCompleteScan(id: source.id, pendingEstimate: 7, capturedAt: scanDate)

        let state = store.state(for: source.id)
        XCTAssertEqual(state?.pendingEstimate, 7)
        XCTAssertEqual(state?.lastCompleteScanAt, scanDate)
        XCTAssertEqual(state?.lastScanWasPartial, false)
        XCTAssertEqual(state?.isChecking, false)
    }

    /// A partial scan preserves the previous complete estimate — it only
    /// flags the incomplete check.
    func testPartialScanPreservesPreviousEstimate() {
        let store = WatchedSourcesStore()
        let source = makeSource()
        store.load([source])
        store.applyCompleteScan(id: source.id, pendingEstimate: 4, capturedAt: Date())

        store.markPartialScan(id: source.id)

        let state = store.state(for: source.id)
        XCTAssertEqual(state?.pendingEstimate, 4, "Incomplete scans must not hide known pending work")
        XCTAssertEqual(state?.lastScanWasPartial, true)
    }

    // MARK: - Totals and attention token

    func testTotalPendingEstimateIgnoresUnavailableSources() {
        let store = WatchedSourcesStore()
        let a = makeSource(path: "/a", label: "a")
        let b = makeSource(path: "/b", label: "b")
        store.load([a, b])
        store.setAvailability(id: a.id, .available)
        store.setAvailability(id: b.id, .unavailable)
        store.applyCompleteScan(id: a.id, pendingEstimate: 3, capturedAt: Date())
        store.setAvailability(id: b.id, .available)
        store.applyCompleteScan(id: b.id, pendingEstimate: 5, capturedAt: Date())
        store.setAvailability(id: b.id, .unavailable)

        XCTAssertEqual(store.totalPendingEstimate, 3)
    }

    /// The token is generation-based: the same count reached twice
    /// (1 → 0 → 1) yields a different token when the generation was
    /// bumped, so a previously-seen token cannot mask a new arrival.
    func testAttentionTokenChangesWithGenerationNotJustCount() {
        let store = WatchedSourcesStore()
        var source = makeSource(generation: 1)
        store.load([source])
        store.setAvailability(id: source.id, .available)

        store.applyCompleteScan(id: source.id, pendingEstimate: 1, capturedAt: Date())
        let firstToken = store.attentionToken
        XCTAssertFalse(firstToken.isEmpty)

        store.applyCompleteScan(id: source.id, pendingEstimate: 0, capturedAt: Date())
        XCTAssertTrue(store.attentionToken.isEmpty, "No pending items — nothing to point at")

        source.changeGeneration = 2
        store.updateSource(source)
        store.applyCompleteScan(id: source.id, pendingEstimate: 1, capturedAt: Date())
        let secondToken = store.attentionToken
        XCTAssertNotEqual(secondToken, firstToken,
                          "Same count, new generation → new attention")
    }

    func testStoreNoticeRoundTrip() {
        let store = WatchedSourcesStore()
        XCTAssertNil(store.storeNotice)
        store.setStoreNotice("rebuilt")
        XCTAssertEqual(store.storeNotice, "rebuilt")
        store.setStoreNotice(nil)
        XCTAssertNil(store.storeNotice)
    }
}
