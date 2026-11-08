import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class NASUserFacingErrorTests: XCTestCase {
    func testNASErrorsMapToTheirDescriptions() {
        let assessmentErrors: [NASAssessmentError] = [
            .rootUnavailable(path: "/Volumes/photo/Photos"),
            .rootIsLink(path: "/Volumes/photo/Link"),
            .stateInsideLibrary(statePath: "/Volumes/photo/Photos/state", rootPath: "/Volumes/photo/Photos"),
            .storeLibraryMismatch(expected: "A", found: "B"),
            .storeFailed(message: "SQLITE_IOERR disk I/O error"),
        ]
        for error in assessmentErrors {
            let text = UserFacingErrorMessage.message(for: error)
            XCTAssertEqual(text, error.errorDescription)
            XCTAssertFalse(text.contains("SQLITE"), "SQLite text must never reach the UI")
        }

        let copyErrors: [NASRemoteCopyError] = [
            .verificationRequired(destinationPath: "/Volumes/photo/Dest"),
            .atomicNoReplaceUnsupported(destinationPath: "/Volumes/photo/Dest"),
            .destinationVolumeChanged(mountPoint: "/Volumes/photo"),
        ]
        for error in copyErrors {
            XCTAssertEqual(UserFacingErrorMessage.message(for: error), error.errorDescription)
        }
    }
}
