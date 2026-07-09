#if canImport(ChronoframeAppCore)
import ChronoframeAppCore
#endif
import Foundation
import XCTest
@testable import ChronoframeApp

final class PhotosImportAccessibilityTextTests: XCTestCase {
    private func asset(
        kind: PhotosAssetSummary.MediaKind = .photo,
        date: Date? = nil,
        favorite: Bool = false,
        cloudOnly: Bool = false
    ) -> PhotosAssetSummary {
        PhotosAssetSummary(
            id: "a",
            mediaKind: kind,
            creationDate: date,
            pixelWidth: 100,
            pixelHeight: 100,
            originalFilename: "a.heic",
            isFavorite: favorite,
            isCloudStoredOnly: cloudOnly
        )
    }

    func testAssetLabelIncludesMediaKindAndSelection() {
        let label = PhotosImportAccessibilityText.assetLabel(asset(kind: .video), isSelected: true)
        XCTAssertTrue(label.hasPrefix("Video"))
        XCTAssertTrue(label.contains("Selected"))
        XCTAssertFalse(label.contains("Not selected"))
    }

    func testAssetLabelMentionsFavoriteAndCloud() {
        let label = PhotosImportAccessibilityText.assetLabel(
            asset(favorite: true, cloudOnly: true),
            isSelected: false
        )
        XCTAssertTrue(label.contains("Favorite"))
        XCTAssertTrue(label.contains("Stored in iCloud"))
        XCTAssertTrue(label.contains("Not selected"))
    }

    func testAssetLabelUnsupportedIsItem() {
        let label = PhotosImportAccessibilityText.assetLabel(asset(kind: .unsupported), isSelected: false)
        XCTAssertTrue(label.hasPrefix("Item"))
    }

    func testAlbumLabelSingularAndPlural() {
        XCTAssertEqual(
            PhotosImportAccessibilityText.albumLabel(
                PhotosAlbumSummary(id: "x", title: "Trip", kind: .userAlbum, approximateCount: 1)
            ),
            "Trip, 1 item"
        )
        XCTAssertEqual(
            PhotosImportAccessibilityText.albumLabel(
                PhotosAlbumSummary(id: "x", title: "Trip", kind: .userAlbum, approximateCount: 4)
            ),
            "Trip, 4 items"
        )
    }

    func testImportButtonLabelReflectsSelection() {
        XCTAssertTrue(PhotosImportAccessibilityText.importButtonLabel(selectedCount: 0).contains("Select"))
        XCTAssertEqual(PhotosImportAccessibilityText.importButtonLabel(selectedCount: 1), "Review and import 1 selected item")
        XCTAssertEqual(PhotosImportAccessibilityText.importButtonLabel(selectedCount: 3), "Review and import 3 selected items")
    }

    func testAuthorizationGateLabelPerStatus() {
        XCTAssertTrue(PhotosImportAccessibilityText.authorizationGateLabel(.notDetermined).contains("permission"))
        XCTAssertTrue(PhotosImportAccessibilityText.authorizationGateLabel(.denied).contains("System Settings"))
        XCTAssertTrue(PhotosImportAccessibilityText.authorizationGateLabel(.restricted).contains("restricted"))
        XCTAssertEqual(PhotosImportAccessibilityText.authorizationGateLabel(.authorized), "")
        XCTAssertEqual(PhotosImportAccessibilityText.authorizationGateLabel(.limited), "")
    }
}
