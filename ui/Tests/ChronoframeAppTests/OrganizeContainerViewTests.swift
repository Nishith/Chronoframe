import ChronoframeCore
import XCTest
@testable import ChronoframeApp

@MainActor
final class OrganizeContainerViewTests: XCTestCase {
    func testNextActionBannerStaysOutOfTopChrome() {
        XCTAssertFalse(OrganizeContainerView.showsNextActionBanner(setupIsIncomplete: true))
        XCTAssertFalse(OrganizeContainerView.showsNextActionBanner(setupIsIncomplete: false))
    }

    func testTabsFollowDisplayOrder() {
        XCTAssertEqual(OrganizeContainerView.tabs, OrganizeSubSection.displayOrder)
        XCTAssertEqual(OrganizeContainerView.tabs, [.setup, .run, .history, .sources, .health])
    }

    func testDividerPrecedesFirstSecondaryTabOnly() {
        let withDivider = OrganizeContainerView.tabs.filter { OrganizeContainerView.showsDividerBefore($0) }
        XCTAssertEqual(withDivider, [OrganizeSubSection.secondary.first].compactMap { $0 })
        XCTAssertFalse(OrganizeContainerView.showsDividerBefore(.setup))
        XCTAssertFalse(OrganizeContainerView.showsDividerBefore(.health))
    }

    func testTabIdentifiersUseRawValues() {
        for tab in OrganizeSubSection.allCases {
            XCTAssertEqual(OrganizeContainerView.tabIdentifier(tab), "organizeTab.\(tab.rawValue)")
        }
        XCTAssertEqual(
            OrganizeContainerView.tabs.map(OrganizeContainerView.tabIdentifier),
            ["organizeTab.setup", "organizeTab.run", "organizeTab.history", "organizeTab.sources", "organizeTab.health"]
        )
    }
}
