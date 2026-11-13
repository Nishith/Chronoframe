import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreNASSystemContainerRulesTests: XCTestCase {
    func testExcludesSynologyContainersCaseInsensitively() {
        XCTAssertTrue(NASSystemContainerRules.isExcludedSystemContainer(name: "@eaDir"))
        XCTAssertTrue(NASSystemContainerRules.isExcludedSystemContainer(name: "@EADIR"))
        XCTAssertTrue(NASSystemContainerRules.isExcludedSystemContainer(name: "#recycle"))
        XCTAssertTrue(NASSystemContainerRules.isExcludedSystemContainer(name: "#RECYCLE"))
        XCTAssertTrue(NASSystemContainerRules.isExcludedSystemContainer(name: "#snapshot"))
        XCTAssertTrue(NASSystemContainerRules.isExcludedSystemContainer(name: "#Snapshot"))
    }

    func testDoesNotMatchSubstringsOrSimilarNames() {
        XCTAssertFalse(NASSystemContainerRules.isExcludedSystemContainer(name: "backup"))
        XCTAssertFalse(NASSystemContainerRules.isExcludedSystemContainer(name: "My #recycle notes"))
        XCTAssertFalse(NASSystemContainerRules.isExcludedSystemContainer(name: "@eaDirX"))
        XCTAssertFalse(NASSystemContainerRules.isExcludedSystemContainer(name: "eaDir"))
        XCTAssertFalse(NASSystemContainerRules.isExcludedSystemContainer(name: ""))
    }
}
