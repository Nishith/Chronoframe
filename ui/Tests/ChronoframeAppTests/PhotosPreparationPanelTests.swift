import XCTest
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
@testable import ChronoframeAppCore
@testable import ChronoframeApp

@MainActor
final class PhotosPreparationPanelTests: XCTestCase {
    private func progress(waiting: Bool, label: String? = "IMG_0001.HEIC") -> PhotosPreparationProgress {
        PhotosPreparationProgress(
            total: 10,
            completed: 3,
            failed: 0,
            currentAssetLabel: label,
            isWaitingForCloud: waiting
        )
    }

    private func resumable(destinationMatches: Bool) -> PhotosResumableImport {
        let now = Date(timeIntervalSince1970: 1_794_393_000)
        return PhotosResumableImport(
            stagingDirectoryURL: URL(fileURLWithPath: "/tmp/staging", isDirectory: true),
            checkpoint: PhotosImportCheckpoint(
                importID: UUID(),
                createdAt: now,
                destinationPath: "/tmp/dest",
                destinationBookmarkKeys: [],
                plan: PhotosExportPlan(entries: [])
            ),
            readyCount: 3,
            totalCount: 10,
            interruptedAt: now,
            destinationMatches: destinationMatches
        )
    }

    func testStopButtonHasIdentifier() {
        XCTAssertEqual(AccessibilityIdentifiers.photosImportStopButton, "photos.import.stop")
        XCTAssertEqual(AccessibilityIdentifiers.photosImportResumeButton, "photos.import.resume")
        XCTAssertEqual(AccessibilityIdentifiers.photosImportDiscardButton, "photos.import.discard")
        XCTAssertEqual(
            PhotosPreparationPanel.stopButtonIdentifier,
            AccessibilityIdentifiers.photosImportStopButton
        )
        XCTAssertEqual(
            PhotosResumeCard.resumeButtonIdentifier,
            AccessibilityIdentifiers.photosImportResumeButton
        )
        XCTAssertEqual(
            PhotosResumeCard.discardButtonIdentifier,
            AccessibilityIdentifiers.photosImportDiscardButton
        )
    }

    func testCloudWaitShowsOnlyWhenWaiting() {
        XCTAssertTrue(PhotosPreparationPanel(progress: progress(waiting: true), onStop: {}).showsCloudWait)
        XCTAssertFalse(PhotosPreparationPanel(progress: progress(waiting: false), onStop: {}).showsCloudWait)
    }

    func testResumeCardDisablesResumeWhenDestinationDiffers() {
        let mismatched = PhotosResumeCard(resumable: resumable(destinationMatches: false), onResume: {}, onDiscard: {})
        XCTAssertTrue(mismatched.isResumeDisabled)
        XCTAssertTrue(mismatched.showsDestinationMismatch)

        let matching = PhotosResumeCard(resumable: resumable(destinationMatches: true), onResume: {}, onDiscard: {})
        XCTAssertFalse(matching.isResumeDisabled)
        XCTAssertFalse(matching.showsDestinationMismatch)
    }
}
