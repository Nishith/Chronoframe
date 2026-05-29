import SwiftUI
import XCTest
@testable import ChronoframeApp

/// Unit tests for the single reduce-motion decision point that every animation
/// helper routes through. Keeping this logic in a pure function
/// (`Motion.resolved`) lets us verify the Reduce Motion contract without a
/// running SwiftUI environment.
final class MotionTests: XCTestCase {

    func testResolvedReturnsNilWhenReduceMotionIsOn() {
        XCTAssertNil(Motion.resolved(.default, reduceMotion: true))
        XCTAssertNil(Motion.resolved(Motion.filmic, reduceMotion: true))
        XCTAssertNil(Motion.resolved(.easeInOut(duration: 0.2), reduceMotion: true))
    }

    func testResolvedReturnsAnimationWhenReduceMotionIsOff() {
        XCTAssertEqual(Motion.resolved(.default, reduceMotion: false), .default)
        XCTAssertEqual(Motion.resolved(Motion.filmic, reduceMotion: false), Motion.filmic)
        XCTAssertEqual(
            Motion.resolved(.easeInOut(duration: 0.2), reduceMotion: false),
            .easeInOut(duration: 0.2)
        )
    }

    @MainActor
    func testWithMotionRunsBodyAndReturnsItsResultRegardlessOfReduceMotion() {
        var sideEffect = 0
        let onResult = Motion.withMotion(Motion.filmic, reduceMotion: false) { () -> Int in
            sideEffect += 1
            return 7
        }
        XCTAssertEqual(onResult, 7)

        let offResult = Motion.withMotion(Motion.filmic, reduceMotion: true) { () -> Int in
            sideEffect += 1
            return 9
        }
        XCTAssertEqual(offResult, 9)
        XCTAssertEqual(sideEffect, 2, "withMotion must always execute its body")
    }
}
