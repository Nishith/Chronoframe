import XCTest
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
@testable import ChronoframeAppCore
@testable import ChronoframeApp

final class PhotosPreparationTextTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    private func progress(
        total: Int = 4_800,
        completed: Int = 1_204,
        failed: Int = 0
    ) -> PhotosPreparationProgress {
        PhotosPreparationProgress(
            total: total,
            completed: completed,
            failed: failed,
            currentAssetLabel: nil,
            isWaitingForCloud: false
        )
    }

    private func resumable(ready: Int, total: Int, at date: Date) -> PhotosResumableImport {
        let checkpoint = PhotosImportCheckpoint(
            importID: UUID(),
            createdAt: date,
            destinationPath: "/tmp/dest",
            destinationBookmarkKeys: [],
            plan: PhotosExportPlan(entries: [])
        )
        return PhotosResumableImport(
            stagingDirectoryURL: URL(fileURLWithPath: "/tmp/staging", isDirectory: true),
            checkpoint: checkpoint,
            readyCount: ready,
            totalCount: total,
            interruptedAt: date,
            destinationMatches: true
        )
    }

    func testProgressLineUsesDecimalCounts() {
        XCTAssertEqual(
            PhotosPreparationText.progressLine(progress(), locale: enUS),
            "Preparing 1,204 of 4,800…"
        )
        XCTAssertEqual(
            PhotosPreparationText.progressLine(progress(total: 480, completed: 12), locale: enUS),
            "Preparing 12 of 480…"
        )
    }

    func testFailuresLineSingularAndPlural() {
        XCTAssertEqual(
            PhotosPreparationText.failuresLine(1, locale: enUS),
            "1 item couldn't be read and will be skipped."
        )
        XCTAssertEqual(
            PhotosPreparationText.failuresLine(3, locale: enUS),
            "3 couldn't be read and will be skipped."
        )
        XCTAssertEqual(
            PhotosPreparationText.failuresLine(1_250, locale: enUS),
            "1,250 couldn't be read and will be skipped."
        )
    }

    func testResumeBodyFormatsCountsAndDate() {
        let date = Date(timeIntervalSince1970: 1_794_393_000) // 2026-11-12 10:30:00 UTC
        let body = PhotosPreparationText.resumeBody(
            resumable(ready: 1_204, total: 4_800, at: date),
            locale: enUS,
            timeZone: utc
        )
        var style = Date.FormatStyle().month().day().hour().minute().locale(enUS)
        style.timeZone = utc
        let formattedDate = date.formatted(style)
        XCTAssertTrue(formattedDate.contains("Nov"), formattedDate)
        XCTAssertEqual(
            body,
            "1,204 of 4,800 items from Photos were prepared on \(formattedDate) and are ready to import. Your Photos library was not changed."
        )
    }

    func testDestinationMismatchTextIsExact() {
        XCTAssertEqual(
            PhotosPreparationText.destinationMismatch,
            "This import was prepared for a different destination. Choose that destination again to resume, or discard it."
        )
        XCTAssertEqual(PhotosPreparationText.waitingForCloud, "Downloading from iCloud…")
        XCTAssertEqual(
            PhotosPreparationText.supersedeMessage(readyCount: 1_204, locale: enUS),
            "Starting a new import discards the 1,204 prepared items from the interrupted one. Your Photos library is not affected either way."
        )
    }
}
