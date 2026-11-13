import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreOrganizeNavigationTests: XCTestCase {
    func testDisplayOrderIsPrimaryFlowThenSecondary() {
        XCTAssertEqual(OrganizeSubSection.primaryFlow, [.setup, .run, .history])
        XCTAssertEqual(OrganizeSubSection.secondary, [.sources, .health])
        XCTAssertEqual(
            OrganizeSubSection.displayOrder,
            [.setup, .run, .history, .sources, .health]
        )
    }

    func testDisplayOrderCoversEveryCaseOnce() {
        let order = OrganizeSubSection.displayOrder
        XCTAssertEqual(order.count, OrganizeSubSection.allCases.count)
        XCTAssertEqual(Set(order), Set(OrganizeSubSection.allCases))
    }

    func testRawValuesAreUnchanged() {
        XCTAssertEqual(
            OrganizeSubSection.allCases.map(\.rawValue),
            ["sources", "setup", "run", "health", "history"]
        )
    }

    func testTitlesAndSubtitlesMatchContract() {
        let expected: [(OrganizeSubSection, String, String)] = [
            (.setup, "Choose Folders", "What to organize and where it goes"),
            (.run, "Preview & Copy", "Check the plan, then copy"),
            (.history, "History", "Past copies, reports and undo"),
            (.sources, "Watched Folders", "Get told when new photos arrive"),
            (.health, "Health", "Checks on your organized library"),
        ]
        XCTAssertEqual(expected.count, OrganizeSubSection.allCases.count)
        for (section, title, subtitle) in expected {
            XCTAssertEqual(section.title, title, "title for \(section.rawValue)")
            XCTAssertEqual(section.subtitle, subtitle, "subtitle for \(section.rawValue)")
        }
    }

    func testSidebarSubtitlesAreShort() {
        let expected: [(SidebarDestination, String)] = [
            (.organize, "Sort into dated folders"),
            (.photos, "Copy from Apple Photos"),
            (.deduplicate, "Remove extra copies"),
        ]
        for (destination, subtitle) in expected {
            XCTAssertEqual(destination.subtitle, subtitle, "subtitle for \(destination.rawValue)")
            XCTAssertLessThanOrEqual(destination.subtitle.count, 24)
        }
    }

    func testNearDuplicateTitleIsLookAlikes() {
        XCTAssertEqual(ClusterKind.nearDuplicate.title, "Look-alikes")
    }
}
