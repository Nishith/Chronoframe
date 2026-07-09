#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

/// Pins the user-visible wording and spoken text for every watched-source
/// row state — the estimate must read as an estimate, incomplete checks
/// must say so, and every state must speak a human-readable label.
final class WatchedSourcesViewModelTests: XCTestCase {
    private func model(
        availability: WatchedSourceAvailability = .available,
        pendingEstimate: Int? = nil,
        isChecking: Bool = false,
        lastScanWasPartial: Bool = false,
        isDegradedWatch: Bool = false
    ) -> WatchedSourceRowModel {
        WatchedSourceRowModel(state: WatchedSourceState(
            source: WatchedSource(path: "/Users/scout/Pictures/Phone Sync", label: "Phone Sync"),
            availability: availability,
            pendingEstimate: pendingEstimate,
            isChecking: isChecking,
            lastScanWasPartial: lastScanWasPartial,
            isDegradedWatch: isDegradedWatch
        ))
    }

    func testPendingCountReadsAsEstimate() {
        XCTAssertEqual(model(pendingEstimate: 12).statusText, "About 12 new items")
        XCTAssertEqual(model(pendingEstimate: 1).statusText, "About 1 new item")
        XCTAssertEqual(
            model(pendingEstimate: 12).detailText,
            "Some may already be in your library — Review & Import shows the exact plan."
        )
    }

    func testCaughtUpAndCheckingStates() {
        XCTAssertEqual(model(pendingEstimate: 0).statusText, "Caught up")
        XCTAssertEqual(model(pendingEstimate: nil).statusText, "Checking…")
        XCTAssertEqual(model(pendingEstimate: nil, isChecking: true).statusText, "Checking…")
    }

    /// An incomplete check must be visible — never a silent "caught up".
    func testPartialScanCaveatShowsWithPreservedCount() {
        let partial = model(pendingEstimate: 4, lastScanWasPartial: true)
        XCTAssertEqual(partial.statusText, "About 4 new items")
        XCTAssertEqual(partial.detailText, "Couldn't fully check this folder.")
    }

    func testDegradedWatchCaveatShowsWhenNothingElseDoes() {
        XCTAssertEqual(
            model(pendingEstimate: 0, isDegradedWatch: true).detailText,
            "Watching with reduced detail."
        )
    }

    func testUnavailableStates() {
        XCTAssertEqual(
            model(availability: .unavailable).statusText,
            "Offline — reconnect the drive to keep watching."
        )
        XCTAssertEqual(
            model(availability: .accessLost).statusText,
            "Access lost — choose this folder again."
        )
        XCTAssertEqual(
            model(availability: .pausedConflict).statusText,
            "Paused — this folder overlaps your destination."
        )
        for availability in [WatchedSourceAvailability.unavailable, .accessLost, .pausedConflict] {
            XCTAssertNil(model(availability: availability).detailText)
            XCTAssertFalse(model(availability: availability).importEnabled)
        }
    }

    func testAffordanceFlags() {
        XCTAssertTrue(model(pendingEstimate: 3).showsWaypointAccent)
        XCTAssertFalse(model(pendingEstimate: 0).showsWaypointAccent)
        XCTAssertTrue(model(pendingEstimate: 0, isChecking: true).showsProgress)
        XCTAssertTrue(model(availability: .accessLost).showsRepickButton)
        XCTAssertFalse(model(availability: .unavailable).showsRepickButton)
        XCTAssertTrue(model().importEnabled)
    }

    /// Spoken text must be a complete human sentence per state — no
    /// paths, identifiers, or SF Symbol names.
    func testAccessibilityLabelsAreHumanReadableForEveryState() {
        XCTAssertEqual(
            model(pendingEstimate: 12).accessibilityLabel,
            "Phone Sync, About 12 new items, Some may already be in your library — Review & Import shows the exact plan."
        )
        XCTAssertEqual(model(pendingEstimate: 0).accessibilityLabel, "Phone Sync, Caught up")
        XCTAssertEqual(
            model(availability: .unavailable).accessibilityLabel,
            "Phone Sync, Offline — reconnect the drive to keep watching."
        )
        for availability in [WatchedSourceAvailability.available, .unavailable, .accessLost, .pausedConflict] {
            let label = model(availability: availability, pendingEstimate: 1).accessibilityLabel
            XCTAssertFalse(label.isEmpty)
            XCTAssertFalse(label.contains("/Users/"), "Spoken text must not be a filesystem path")
        }
    }
}
