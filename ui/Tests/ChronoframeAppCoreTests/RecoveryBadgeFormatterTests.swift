import XCTest
@testable import ChronoframeAppCore

final class RecoveryBadgeFormatterTests: XCTestCase {
    func testRecoveryBadgeCopyIsExplicit() {
        XCTAssertEqual(
            RecoveryBadgeFormatter.title(for: .needsVolume(volumeName: "Photos", volumeIdentifier: "disk4")),
            "Interrupted · Needs Drive"
        )
        XCTAssertEqual(
            RecoveryBadgeFormatter.title(for: .trashLocationUnverified),
            "Trash Location Unverified"
        )
        XCTAssertEqual(
            RecoveryBadgeFormatter.title(for: .manualActionRequired),
            "Manual Recovery Needed"
        )
        XCTAssertNil(RecoveryBadgeFormatter.title(for: nil))
    }
}
