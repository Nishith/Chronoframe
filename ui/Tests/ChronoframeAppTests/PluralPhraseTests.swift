import XCTest
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
@testable import ChronoframeAppCore
@testable import ChronoframeApp

/// A count of 1 chooses a complete singular phrase ("1 frame", "Show this file")
/// and German agrees in case and number. Zero stays plural.
@MainActor
final class PluralPhraseTests: XCTestCase {
    private let enUS = Locale(identifier: "en_US")
    private let utc = TimeZone(identifier: "UTC")!

    // MARK: Noun phrases

    func testNounPhrases() {
        XCTAssertEqual(PluralPhrases.files(1), "1 file")
        XCTAssertEqual(PluralPhrases.files(0), "0 files")
        XCTAssertEqual(PluralPhrases.folders(1), "1 folder")
        XCTAssertEqual(PluralPhrases.folders(2), "2 folders")
        XCTAssertEqual(PluralPhrases.frames(1), "1 frame")
        XCTAssertEqual(PluralPhrases.frames(0), "0 frames")
        XCTAssertEqual(PluralPhrases.copies(1), "1 copy")
        XCTAssertEqual(PluralPhrases.copies(3), "3 copies")
        XCTAssertEqual(PluralPhrases.months(1), "1 month")
        XCTAssertEqual(PluralPhrases.months(12), "12 months")
        XCTAssertEqual(PluralPhrases.workers(1), "1 worker")
        XCTAssertEqual(PluralPhrases.workers(8), "8 workers")
    }

    func testHistorySummaryJoinsTwoIndependentPhrases() {
        XCTAssertEqual(PluralPhrases.historySummary(reports: 1, folders: 1), "1 report or log · 1 reusable folder.")
        XCTAssertEqual(PluralPhrases.historySummary(reports: 1, folders: 4), "1 report or log · 4 reusable folders.")
        XCTAssertEqual(PluralPhrases.historySummary(reports: 3, folders: 0), "3 reports and logs · 0 reusable folders.")
    }

    // MARK: Timelines

    func testArchiveOverviewLabel() {
        XCTAssertEqual(
            PluralPhrases.archiveOverview(frames: 1, copies: 1),
            "Archive overview: 1 frame archived across 1 copy."
        )
        XCTAssertEqual(
            PluralPhrases.archiveOverview(frames: 12, copies: 3),
            "Archive overview: 12 frames archived across 3 copies."
        )
    }

    func testTimelineAccessibilityValues() {
        XCTAssertEqual(
            PluralPhrases.timelineSelectedValue(month: "Apr 2021", countPhrase: PluralPhrases.copies(1), monthCount: 1),
            "Selected month: Apr 2021, 1 copy. Timeline contains 1 month."
        )
        XCTAssertEqual(
            PluralPhrases.timelineSelectedValue(month: "2021-04", countPhrase: TimelinePlurals.plannedFiles(40), monthCount: 3),
            "Selected month: 2021-04, 40 planned files. Timeline contains 3 months."
        )
        XCTAssertEqual(
            PluralPhrases.timelineUnselectedValue(countPhrase: PluralPhrases.copies(1), monthCount: 1),
            "Timeline containing 1 copy across 1 month. Unselected."
        )
        XCTAssertEqual(
            PluralPhrases.timelineUnselectedValue(countPhrase: TimelinePlurals.plannedFiles(0), monthCount: 2),
            "Timeline containing 0 planned files across 2 months. Unselected."
        )
    }

    // MARK: Contact sheet, dedupe, triage

    func testContactSheetLabel() {
        XCTAssertEqual(PluralPhrases.contactSheetShowing(1), "Contact sheet showing 1 preview frame from the source.")
        XCTAssertEqual(PluralPhrases.contactSheetShowing(0), "Contact sheet showing 0 preview frames from the source.")
        XCTAssertEqual(PluralPhrases.contactSheetShowing(9), "Contact sheet showing 9 preview frames from the source.")
    }

    func testTrustProofGroupSentences() {
        XCTAssertEqual(PluralPhrases.groupsWillBeProcessed(1), "1 group will be processed.")
        XCTAssertEqual(PluralPhrases.groupsWillBeProcessed(0), "0 groups will be processed.")
        XCTAssertEqual(PluralPhrases.unreviewedGroupsUntouched(1), "1 unreviewed group remains completely untouched.")
        XCTAssertEqual(PluralPhrases.unreviewedGroupsUntouched(5), "5 unreviewed groups remain completely untouched.")
        XCTAssertEqual(PluralPhrases.groupsReviewedLabel(1), "1 group reviewed.")
        XCTAssertEqual(PluralPhrases.groupsReviewedLabel(2), "2 groups reviewed.")
        XCTAssertEqual(PluralPhrases.groupsUntouchedLabel(1), "1 group untouched.")
        XCTAssertEqual(PluralPhrases.groupsUntouchedLabel(0), "0 groups untouched.")
    }

    func testTriageProgressFollowsTheTotal() {
        XCTAssertEqual(PluralPhrases.triageProgress(current: 1, total: 1), "1 of 1 group reviewed")
        XCTAssertEqual(PluralPhrases.triageProgress(current: 1, total: 6), "1 of 6 groups reviewed")
        XCTAssertEqual(PluralPhrases.triageProgress(current: 0, total: 0), "0 of 0 groups reviewed")
    }

    // MARK: Unlock sheet

    func testFreeTestBatchFileButtons() {
        XCTAssertEqual(PluralPhrases.showTheseFiles(1), "Show this file")
        XCTAssertEqual(PluralPhrases.showTheseFiles(25), "Show these 25 files")
        XCTAssertEqual(PluralPhrases.copyTheseFiles(1), "Copy This File")
        XCTAssertEqual(PluralPhrases.copyTheseFiles(25), "Copy These 25 Files")
    }

    // MARK: NAS

    func testNASSummaryAndProgressLines() {
        XCTAssertEqual(PluralPhrases.foldersChecked(1), "1 folder checked")
        XCTAssertEqual(PluralPhrases.foldersChecked(0), "0 folders checked")
        XCTAssertEqual(PluralPhrases.photosAndVideos(count: 1, size: "4 MB"), "1 photo or video, 4 MB")
        XCTAssertEqual(PluralPhrases.photosAndVideos(count: 2, size: "4 MB"), "2 photos and videos, 4 MB")
        XCTAssertEqual(PluralPhrases.groupsOfIdenticalFiles(1), "1 group of identical files")
        XCTAssertEqual(PluralPhrases.groupsOfIdenticalFiles(3), "3 groups of identical files")
        XCTAssertEqual(PluralPhrases.scanProgress(folders: 1, files: 1), "1 folder, 1 file")
        XCTAssertEqual(PluralPhrases.scanProgress(folders: 3, files: 1), "3 folders, 1 file")
        XCTAssertEqual(PluralPhrases.scanProgress(folders: 1, files: 0), "1 folder, 0 files")
    }

    func testOrganizeIntentResultMessage() {
        XCTAssertEqual(OrganizeFolderIntent.finishedMessage(copiedCount: 1), "Successfully organized folder. Transferred 1 file.")
        XCTAssertEqual(OrganizeFolderIntent.finishedMessage(copiedCount: 0), "Successfully organized folder. Transferred 0 files.")
        XCTAssertEqual(OrganizeFolderIntent.finishedMessage(copiedCount: 12), "Successfully organized folder. Transferred 12 files.")
    }

    // MARK: Review and Photos

    func testNeedsAttentionMessage() {
        XCTAssertEqual(PluralPhrases.itemsNeedAttention(1), "1 item needs attention. Originals stay untouched.")
        XCTAssertEqual(PluralPhrases.itemsNeedAttention(4), "4 items need attention. Originals stay untouched.")
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

    func testPhotosResumeBodyFollowsTheTotal() {
        let date = Date(timeIntervalSince1970: 1_794_393_000)
        var style = Date.FormatStyle().month().day().hour().minute().locale(enUS)
        style.timeZone = utc
        let formatted = date.formatted(style)
        XCTAssertEqual(
            PhotosPreparationText.resumeBody(resumable(ready: 1, total: 1, at: date), locale: enUS, timeZone: utc),
            "1 of 1 item from Photos was prepared on \(formatted) and is ready to import. Your Photos library was not changed."
        )
        XCTAssertEqual(
            PhotosPreparationText.resumeBody(resumable(ready: 1, total: 2, at: date), locale: enUS, timeZone: utc),
            "1 of 2 items from Photos were prepared on \(formatted) and are ready to import. Your Photos library was not changed."
        )
    }

    func testPhotosSupersedeMessageIsSingularForOne() {
        XCTAssertEqual(
            PhotosPreparationText.supersedeMessage(readyCount: 1, locale: enUS),
            "Starting a new import discards the prepared item from the interrupted one. Your Photos library is not affected either way."
        )
        XCTAssertEqual(
            PhotosPreparationText.supersedeMessage(readyCount: 0, locale: enUS),
            "Starting a new import discards the 0 prepared items from the interrupted one. Your Photos library is not affected either way."
        )
    }

    // MARK: German agreement

    func testGermanSingularPhrasesAgreeInCaseAndNumber() throws {
        let de = try germanAppBundle()
        XCTAssertEqual(PluralPhrases.frames(1, bundle: de), "1 Aufnahme")
        XCTAssertEqual(PluralPhrases.frames(5, bundle: de), "5 Aufnahmen")
        XCTAssertEqual(PluralPhrases.copies(1, bundle: de), "1 Kopie")
        XCTAssertEqual(PluralPhrases.copies(2, bundle: de), "2 Kopien")
        XCTAssertEqual(PluralPhrases.months(1, bundle: de), "1 Monat")
        XCTAssertEqual(PluralPhrases.months(2, bundle: de), "2 Monate")
        XCTAssertEqual(PluralPhrases.workers(1, bundle: de), "1 Arbeits-Thread")
        XCTAssertEqual(PluralPhrases.workers(4, bundle: de), "4 Arbeits-Threads")
        XCTAssertEqual(
            PluralPhrases.historySummary(reports: 1, folders: 1, bundle: de),
            "1 Bericht oder Protokoll · 1 wiederverwendbarer Ordner."
        )
        XCTAssertEqual(
            PluralPhrases.historySummary(reports: 3, folders: 2, bundle: de),
            "3 Berichte und Protokolle · 2 wiederverwendbare Ordner."
        )
        XCTAssertEqual(
            PluralPhrases.archiveOverview(frames: 1, copies: 1, bundle: de),
            "Archivübersicht: 1 Aufnahme archiviert in 1 Kopie."
        )
        XCTAssertEqual(
            PluralPhrases.archiveOverview(frames: 5, copies: 3, bundle: de),
            "Archivübersicht: 5 Aufnahmen archiviert in 3 Kopien."
        )
        XCTAssertEqual(
            PluralPhrases.timelineSelectedValue(month: "Apr 2021", countPhrase: PluralPhrases.copies(1, bundle: de), monthCount: 1, bundle: de),
            "Ausgewählter Monat: Apr 2021, 1 Kopie. Die Zeitleiste umfasst 1 Monat."
        )
        XCTAssertEqual(
            PluralPhrases.timelineUnselectedValue(countPhrase: PluralPhrases.copies(2, bundle: de), monthCount: 3, bundle: de),
            "Zeitleiste mit 2 Kopien in 3 Monaten. Keine Auswahl."
        )
        XCTAssertEqual(
            PluralPhrases.contactSheetShowing(1, bundle: de),
            "Kontaktbogen mit 1 Vorschaubild aus der Quelle."
        )
        XCTAssertEqual(PluralPhrases.groupsWillBeProcessed(1, bundle: de), "1 Gruppe wird bearbeitet.")
        XCTAssertEqual(PluralPhrases.groupsWillBeProcessed(3, bundle: de), "3 Gruppen werden bearbeitet.")
        XCTAssertEqual(
            PluralPhrases.unreviewedGroupsUntouched(1, bundle: de),
            "1 ungeprüfte Gruppe bleibt vollständig unangetastet."
        )
        XCTAssertEqual(
            PluralPhrases.unreviewedGroupsUntouched(3, bundle: de),
            "3 ungeprüfte Gruppen bleiben vollständig unangetastet."
        )
        XCTAssertEqual(PluralPhrases.groupsReviewedLabel(1, bundle: de), "1 Gruppe geprüft.")
        XCTAssertEqual(PluralPhrases.groupsUntouchedLabel(1, bundle: de), "1 Gruppe unangetastet.")
        XCTAssertEqual(PluralPhrases.triageProgress(current: 1, total: 1, bundle: de), "1 von 1 Gruppe geprüft")
        XCTAssertEqual(PluralPhrases.triageProgress(current: 1, total: 4, bundle: de), "1 von 4 Gruppen geprüft")
        XCTAssertEqual(PluralPhrases.showTheseFiles(1, bundle: de), "Diese Datei anzeigen")
        XCTAssertEqual(PluralPhrases.showTheseFiles(3, bundle: de), "Diese 3 Dateien anzeigen")
        XCTAssertEqual(PluralPhrases.copyTheseFiles(1, bundle: de), "Diese Datei kopieren")
        XCTAssertEqual(PluralPhrases.copyTheseFiles(3, bundle: de), "Diese 3 Dateien kopieren")
        XCTAssertEqual(PluralPhrases.foldersChecked(1, bundle: de), "1 Ordner geprüft")
        XCTAssertEqual(PluralPhrases.photosAndVideos(count: 1, size: "4 MB", bundle: de), "1 Foto oder Video, 4 MB")
        XCTAssertEqual(PluralPhrases.photosAndVideos(count: 2, size: "4 MB", bundle: de), "2 Fotos und Videos, 4 MB")
        XCTAssertEqual(PluralPhrases.groupsOfIdenticalFiles(1, bundle: de), "1 Gruppe identischer Dateien")
        XCTAssertEqual(PluralPhrases.scanProgress(folders: 1, files: 1, bundle: de), "1 Ordner, 1 Datei")
        XCTAssertEqual(PluralPhrases.itemsNeedAttention(1, bundle: de), "1 Element braucht Aufmerksamkeit. Originale bleiben unangetastet.")
        XCTAssertEqual(PluralPhrases.itemsNeedAttention(2, bundle: de), "2 Elemente brauchen Aufmerksamkeit. Originale bleiben unangetastet.")
    }

    func testGermanPhotosPhrases() throws {
        let de = try germanAppBundle()
        let date = Date(timeIntervalSince1970: 1_794_393_000)
        XCTAssertTrue(
            PhotosPreparationText.resumeBody(resumable(ready: 1, total: 1, at: date), locale: enUS, timeZone: utc, bundle: de)
                .hasPrefix("1 von 1 Element aus Fotos wurde am")
        )
        XCTAssertTrue(
            PhotosPreparationText.resumeBody(resumable(ready: 1, total: 3, at: date), locale: enUS, timeZone: utc, bundle: de)
                .hasPrefix("1 von 3 Elementen aus Fotos wurden am")
        )
        XCTAssertEqual(
            PhotosPreparationText.supersedeMessage(readyCount: 1, locale: enUS, bundle: de),
            "Ein neuer Import verwirft das vorbereitete Element des unterbrochenen Imports. Deine Fotos-Mediathek bleibt in beiden Fällen unverändert."
        )
    }
}
