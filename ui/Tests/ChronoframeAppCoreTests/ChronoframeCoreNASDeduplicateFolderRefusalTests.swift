import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreNASDeduplicateFolderRefusalTests: XCTestCase {
    private let folder = URL(fileURLWithPath: "/Volumes/Share/Photos", isDirectory: true)

    override func tearDown() {
        #if DEBUG
        NASCapability.isEnabledOverride = nil
        #endif
        super.tearDown()
    }

    private func classifier(type: String, flags: UInt32) -> NASVolumeClassifier {
        NASVolumeClassifier { _ in
            NASStatfsSnapshot(
                fileSystemType: type,
                mountedOn: "/Volumes/Share",
                mountedFrom: "//user@nas.local/Share",
                flags: flags,
                fileSystemID: 1
            )
        }
    }

    // AGENTS-INVARIANT: 12
    func testRemoteVolumeIsRefused() {
        let refusal = NASDeduplicateFolderRefusal.refusal(
            for: folder,
            classifier: classifier(type: "smbfs", flags: 0)
        )

        XCTAssertEqual(refusal, .notLocal(path: folder.path, kind: .remote))
    }

    func testUnknownVolumeIsRefused() {
        let refusal = NASDeduplicateFolderRefusal.refusal(
            for: folder,
            classifier: NASVolumeClassifier { _ in nil }
        )

        XCTAssertEqual(refusal, .notLocal(path: folder.path, kind: .unknown))
    }

    func testLocalVolumeIsAllowed() {
        let refusal = NASDeduplicateFolderRefusal.refusal(
            for: folder,
            classifier: classifier(type: "apfs", flags: UInt32(MNT_LOCAL))
        )

        XCTAssertNil(refusal)
    }

    func testMessageMentionsNASLibraryOnlyWhenEnabled() {
        #if DEBUG
        let refusal = NASDeduplicateFolderRefusal.notLocal(path: folder.path, kind: .remote)

        NASCapability.isEnabledOverride = true
        let enabled = refusal.errorDescription
        XCTAssertEqual(
            enabled,
            "Choose a folder on this Mac or an attached drive. Deduplicate can't move files on a network share to the Trash safely yet, so nothing was changed. For a NAS, use NAS Library."
        )

        NASCapability.isEnabledOverride = false
        let disabled = refusal.errorDescription
        XCTAssertEqual(
            disabled,
            "Choose a folder on this Mac or an attached drive. Deduplicate can't move files on a network share to the Trash safely yet, so nothing was changed."
        )
        XCTAssertFalse(disabled?.contains("NAS Library") ?? true)
        #endif
    }
}
