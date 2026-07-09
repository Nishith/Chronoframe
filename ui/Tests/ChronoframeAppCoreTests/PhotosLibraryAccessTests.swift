import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore
#if canImport(Photos)
import Photos
#endif

final class PhotosAuthorizationStatusTests: XCTestCase {
    func testAllowsReadingOnlyForAuthorizedAndLimited() {
        XCTAssertTrue(PhotosAuthorizationStatus.authorized.allowsReading)
        XCTAssertTrue(PhotosAuthorizationStatus.limited.allowsReading)
        XCTAssertFalse(PhotosAuthorizationStatus.notDetermined.allowsReading)
        XCTAssertFalse(PhotosAuthorizationStatus.denied.allowsReading)
        XCTAssertFalse(PhotosAuthorizationStatus.restricted.allowsReading)
    }

    func testCanPromptOnlyWhenNotDetermined() {
        XCTAssertTrue(PhotosAuthorizationStatus.notDetermined.canPromptForAccess)
        for status in PhotosAuthorizationStatus.allCases where status != .notDetermined {
            XCTAssertFalse(status.canPromptForAccess, "\(status) must not offer an in-app prompt")
        }
    }

    func testIsBlockedForDeniedAndRestrictedOnly() {
        XCTAssertTrue(PhotosAuthorizationStatus.denied.isBlocked)
        XCTAssertTrue(PhotosAuthorizationStatus.restricted.isBlocked)
        XCTAssertFalse(PhotosAuthorizationStatus.notDetermined.isBlocked)
        XCTAssertFalse(PhotosAuthorizationStatus.authorized.isBlocked)
        XCTAssertFalse(PhotosAuthorizationStatus.limited.isBlocked)
    }

    func testReadingAndBlockedArePartitioned() {
        // A status is never both readable and blocked; notDetermined is
        // neither (it is promptable).
        for status in PhotosAuthorizationStatus.allCases {
            XCTAssertFalse(status.allowsReading && status.isBlocked, "\(status) cannot be both readable and blocked")
        }
    }

    func testAllCasesCovered() {
        XCTAssertEqual(Set(PhotosAuthorizationStatus.allCases), [
            .notDetermined, .denied, .restricted, .authorized, .limited,
        ])
    }

    #if canImport(Photos)
    func testMapsPHAuthorizationStatus() {
        XCTAssertEqual(PhotosAuthorizationStatus(.authorized), .authorized)
        XCTAssertEqual(PhotosAuthorizationStatus(.limited), .limited)
        XCTAssertEqual(PhotosAuthorizationStatus(.denied), .denied)
        XCTAssertEqual(PhotosAuthorizationStatus(.restricted), .restricted)
        XCTAssertEqual(PhotosAuthorizationStatus(.notDetermined), .notDetermined)
    }
    #endif
}

/// Test double proving the `PhotosLibraryAccessing` seam is injectable
/// without PhotoKit — later phases depend on this for unit testing.
private final class FakePhotosLibraryAccess: PhotosLibraryAccessing, @unchecked Sendable {
    let currentStatus: PhotosAuthorizationStatus
    let promptResult: PhotosAuthorizationStatus
    private(set) var promptCount = 0

    init(currentStatus: PhotosAuthorizationStatus, promptResult: PhotosAuthorizationStatus) {
        self.currentStatus = currentStatus
        self.promptResult = promptResult
    }

    func currentAuthorization() -> PhotosAuthorizationStatus { currentStatus }
    func requestReadAccess() async -> PhotosAuthorizationStatus {
        promptCount += 1
        return promptResult
    }
}

final class PhotosLibraryAccessingSeamTests: XCTestCase {
    func testSeamReportsCurrentAndPromptedStatus() async {
        let fake = FakePhotosLibraryAccess(currentStatus: .notDetermined, promptResult: .authorized)
        let access: any PhotosLibraryAccessing = fake

        XCTAssertEqual(access.currentAuthorization(), .notDetermined)
        let result = await access.requestReadAccess()
        XCTAssertEqual(result, .authorized)
        XCTAssertEqual(fake.promptCount, 1)
    }
}
