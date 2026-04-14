import XCTest
@testable import ChronoframeAppCore

final class RunLogStoreTests: XCTestCase {
    func testRingBufferDropsOldestLines() {
        let store = RunLogStore(capacity: PreferencesStore.minimumLogCapacity)

        for index in 0...PreferencesStore.minimumLogCapacity {
            store.append("line \(index)")
        }

        XCTAssertEqual(store.lines.count, PreferencesStore.minimumLogCapacity)
        XCTAssertEqual(store.lines.first, "line 1")
        XCTAssertEqual(store.lines.last, "line \(PreferencesStore.minimumLogCapacity)")
    }

    func testSeverityCountersTrackRenderedLines() {
        let store = RunLogStore(capacity: PreferencesStore.minimumLogCapacity)

        store.append(issue: RunIssue(severity: .info, message: "Discovery started"))
        store.append(issue: RunIssue(severity: .warning, message: "Slow destination scan"))
        store.append(issue: RunIssue(severity: .error, message: "Verification failed"))

        XCTAssertEqual(store.infoCount, 1)
        XCTAssertEqual(store.warningCount, 1)
        XCTAssertEqual(store.errorCount, 1)
    }
}
