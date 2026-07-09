import XCTest
@testable import ChronoframeCore

final class PhotosExportPlannerTests: XCTestCase {
    private func asset(
        id: String,
        kind: PhotosAssetSummary.MediaKind = .photo,
        filename: String?
    ) -> PhotosAssetSummary {
        PhotosAssetSummary(
            id: id,
            mediaKind: kind,
            creationDate: nil,
            pixelWidth: 100,
            pixelHeight: 100,
            originalFilename: filename,
            isFavorite: false,
            isCloudStoredOnly: false
        )
    }

    func testDropsNonImportableMedia() {
        let plan = PhotosExportPlanner.plan(for: [
            asset(id: "a", kind: .photo, filename: "IMG_1.HEIC"),
            asset(id: "b", kind: .unsupported, filename: "voice.m4a"),
            asset(id: "c", kind: .video, filename: "MOV_1.MOV"),
        ])
        XCTAssertEqual(plan.assetIDs, ["a", "c"])
    }

    func testStemStripsExtension() {
        let plan = PhotosExportPlanner.plan(for: [asset(id: "a", filename: "IMG_0001.HEIC")])
        XCTAssertEqual(plan.entries.first?.stagingStem, "IMG_0001")
    }

    func testDuplicateFilenamesAreDisambiguated() {
        let plan = PhotosExportPlanner.plan(for: [
            asset(id: "a", filename: "IMG_0001.HEIC"),
            asset(id: "b", filename: "IMG_0001.HEIC"),
            asset(id: "c", filename: "IMG_0001.HEIC"),
        ])
        XCTAssertEqual(plan.entries.map(\.stagingStem), ["IMG_0001", "IMG_0001-2", "IMG_0001-3"])
    }

    func testSameAssetSelectedTwiceStagedOnce() {
        let plan = PhotosExportPlanner.plan(for: [
            asset(id: "a", filename: "IMG_0001.HEIC"),
            asset(id: "a", filename: "IMG_0001.HEIC"),
        ])
        XCTAssertEqual(plan.assetIDs, ["a"])
    }

    func testMissingFilenameFallsBackByMediaKind() {
        let plan = PhotosExportPlanner.plan(for: [
            asset(id: "a", kind: .photo, filename: nil),
            asset(id: "b", kind: .video, filename: ""),
        ])
        XCTAssertEqual(plan.entries.map(\.stagingStem), ["Photo", "Video"])
    }

    func testStemStripsLeadingDotsSoStagedFileIsNotHidden() {
        // A leading-dot filename would otherwise stage a dotfile that media
        // discovery skips entirely.
        let stem = PhotosExportPlanner.sanitizedStem(from: ".hidden.jpg", mediaKind: .photo)
        XCTAssertFalse(stem.hasPrefix("."))
        XCTAssertEqual(stem, "hidden")
    }

    func testStemSanitizesPathSeparators() {
        let stem = PhotosExportPlanner.sanitizedStem(from: "a/b:c\\d.jpg", mediaKind: .photo)
        XCTAssertFalse(stem.contains("/"))
        XCTAssertFalse(stem.contains(":"))
        XCTAssertFalse(stem.contains("\\"))
    }

    func testStemFallsBackWhenSanitizesToEmpty() {
        let stem = PhotosExportPlanner.sanitizedStem(from: "...", mediaKind: .video)
        XCTAssertEqual(stem, "Video")
    }

    func testEmptyPlanIsEmpty() {
        XCTAssertTrue(PhotosExportPlanner.plan(for: []).isEmpty)
    }
}
