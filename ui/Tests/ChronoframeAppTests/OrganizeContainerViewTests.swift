import XCTest
@testable import ChronoframeApp

@MainActor
final class OrganizeContainerViewTests: XCTestCase {
    func testNextActionBannerStaysOutOfTopChrome() {
        XCTAssertFalse(OrganizeContainerView.showsNextActionBanner(setupIsIncomplete: true))
        XCTAssertFalse(OrganizeContainerView.showsNextActionBanner(setupIsIncomplete: false))
    }
}
