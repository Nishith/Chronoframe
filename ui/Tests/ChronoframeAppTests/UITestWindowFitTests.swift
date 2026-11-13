import AppKit
import XCTest
@testable import ChronoframeApp

final class UITestWindowFitTests: XCTestCase {
    private let chrome = NSSize(width: 0, height: 52)
    private let minimum = NSSize(width: 900, height: UITestScenario.mainWindowMinHeight)

    func testPreferredSizeIsKeptWhenTheDisplayIsLargeEnough() {
        let size = UITestScenario.fittedContentSize(
            preferred: NSSize(width: 1360, height: 920), chrome: chrome,
            visible: NSSize(width: 1920, height: 1000), minimum: minimum
        )
        XCTAssertEqual(size, NSSize(width: 1360, height: 920))
    }

    func testPreferredSizeShrinksToTheVisibleAreaOfASmallDisplay() {
        let size = UITestScenario.fittedContentSize(
            preferred: NSSize(width: 1360, height: 920), chrome: chrome,
            visible: NSSize(width: 1024, height: 690), minimum: minimum
        )
        XCTAssertEqual(size, NSSize(width: 1024, height: 638))
    }

    func testFittedSizeNeverDropsBelowTheMinimum() {
        let size = UITestScenario.fittedContentSize(
            preferred: NSSize(width: 900, height: 700), chrome: chrome,
            visible: NSSize(width: 800, height: 400), minimum: minimum
        )
        XCTAssertEqual(size, minimum)
    }

    func testFrameOverhangingTheScreenIsMovedBackInside() {
        let visible = NSRect(x: 0, y: 70, width: 1024, height: 673)
        let moved = UITestScenario.frame(
            NSRect(x: -168, y: 20, width: 1000, height: 600), clampedTo: visible
        )
        XCTAssertEqual(moved, NSRect(x: 0, y: 70, width: 1000, height: 600))
        XCTAssertEqual(
            UITestScenario.frame(NSRect(x: 40, y: 300, width: 1000, height: 600), clampedTo: visible),
            NSRect(x: 24, y: 143, width: 1000, height: 600)
        )
    }

    func testFrameLargerThanTheScreenIsPinnedToItsTopLeft() {
        let visible = NSRect(x: 0, y: 70, width: 1024, height: 673)
        let pinned = UITestScenario.frame(
            NSRect(x: -168, y: 10, width: 1360, height: 752), clampedTo: visible
        )
        XCTAssertEqual(pinned.minX, 0)
        XCTAssertEqual(pinned.maxY, visible.maxY)
    }

    func testVisibleSizeOverrideParsesWidthByHeightOnly() {
        let key = UITestScenario.visibleSizeOverrideKey
        XCTAssertEqual(UITestScenario.visibleSizeOverride(environment: [key: "1024x720"]), NSSize(width: 1024, height: 720))
        XCTAssertNil(UITestScenario.visibleSizeOverride(environment: [key: "1024"]))
        XCTAssertNil(UITestScenario.visibleSizeOverride(environment: [key: "0x720"]))
        XCTAssertNil(UITestScenario.visibleSizeOverride(environment: [:]))
    }

    func testAppearanceOverrideAcceptsLightAndDarkOnly() {
        let key = UITestScenario.appearanceOverrideKey
        XCTAssertEqual(UITestScenario.appearanceOverride(environment: [key: "light"]), .aqua)
        XCTAssertEqual(UITestScenario.appearanceOverride(environment: [key: "Dark"]), .darkAqua)
        XCTAssertNil(UITestScenario.appearanceOverride(environment: [key: "sepia"]))
        XCTAssertNil(UITestScenario.appearanceOverride(environment: [:]))
    }
}
