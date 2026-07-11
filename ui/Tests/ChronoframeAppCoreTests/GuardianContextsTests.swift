import Foundation
import XCTest
@testable import ChronoframeAppCore
@testable import ChronoframeCore

final class GuardianContextsTests: XCTestCase {
    private let identity = GuardianLibraryIdentity(libraryUUID: "lib")
    private let bookmark = FolderBookmark(key: "k", path: "/p", data: Data())

    private func action(_ path: String) -> GuardianRestoreAction {
        GuardianRestoreAction(relativePath: path, trustedIdentity: FileIdentity(size: 1, digest: "d"), reason: .primaryCorrupt, expectedCurrentPrimaryIdentity: FileIdentity(size: 1, digest: "e"))
    }

    func testSelectedActionsIsTheReviewGatedSubsetInPlanOrder() {
        let plan = GuardianRestorePlan(
            libraryRoot: "/lib", mirrorRoot: "/mir",
            restorable: [action("a.jpg"), action("b.jpg"), action("c.jpg")],
            blocked: []
        )
        let context = GuardianRestoreContext(
            libraryIdentity: identity,
            libraryURL: URL(fileURLWithPath: "/lib"), libraryBookmark: bookmark,
            mirrorURL: URL(fileURLWithPath: "/mir"), mirrorBookmark: bookmark,
            plan: plan,
            selectedPaths: ["a.jpg", "c.jpg"]
        )

        XCTAssertEqual(context.selectedActions.map(\.relativePath), ["a.jpg", "c.jpg"])
    }

    func testMirrorContextEquatablePinsBothRoots() {
        let a = GuardianMirrorContext(
            libraryIdentity: identity,
            libraryURL: URL(fileURLWithPath: "/lib"), libraryBookmark: bookmark,
            mirrorURL: URL(fileURLWithPath: "/mir"), mirrorBookmark: bookmark
        )
        let b = GuardianMirrorContext(
            libraryIdentity: identity,
            libraryURL: URL(fileURLWithPath: "/lib"), libraryBookmark: bookmark,
            mirrorURL: URL(fileURLWithPath: "/other-mirror"), mirrorBookmark: bookmark
        )
        XCTAssertEqual(a, a)
        XCTAssertNotEqual(a, b, "a different mirror root is a different pinned action")
    }
}
