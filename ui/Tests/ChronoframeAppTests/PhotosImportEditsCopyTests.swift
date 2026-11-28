import XCTest
@testable import ChronoframeApp
@testable import ChronoframeAppCore

@MainActor
final class PhotosImportEditsCopyTests: XCTestCase {
    func testPhotosImportCaptionStatesOriginalsOnlyByDefault() {
        XCTAssertEqual(
            PhotosImportEditsCaption.text(includeEditedVersions: false),
            "Imports the original photo or video. Edits made in Photos, such as crops and filters, are not included."
        )
        XCTAssertEqual(
            PhotosImportEditsCaption.text(includeEditedVersions: true),
            "Also saves the edited version of each edited photo as a separate file. Edited videos and Live Photos are not included."
        )
    }

    // MARK: - WP-07: Include edited versions

    private let enUS = Locale(identifier: "en_US")

    private func counts(
        included: Bool = true,
        originals: Int = 0,
        edited: Int = 0,
        couldNotSave: Int = 0,
        notIncluded: Int = 0
    ) -> PhotosImportEditedVersionCounts {
        PhotosImportEditedVersionCounts(
            includedEditedVersions: included,
            originals: originals,
            editedVersions: edited,
            couldNotSave: couldNotSave,
            notIncluded: notIncluded
        )
    }

    func testSummaryTextShowsOriginalsEditedAndCouldNotSaveCounts() {
        XCTAssertEqual(
            PhotosImportEditsSummaryText.lines(for: counts(originals: 1_204, edited: 37, couldNotSave: 2), locale: enUS),
            ["Originals: 1,204 \u{00B7} Edited versions: 37 \u{00B7} Could not save: 2"]
        )
        XCTAssertEqual(
            PhotosImportEditsSummaryText.lines(for: counts(originals: 5, edited: 5, notIncluded: 1), locale: enUS),
            ["Originals: 5 \u{00B7} Edited versions: 5 \u{00B7} Could not save: 0", "1 edited video or Live Photo not included"]
        )
        XCTAssertEqual(
            PhotosImportEditsSummaryText.lines(for: counts(originals: 5, notIncluded: 3), locale: enUS).last,
            "3 edited videos and Live Photos not included"
        )
        XCTAssertEqual(
            PhotosImportEditsSummaryText.lines(for: counts(originals: 1_500, notIncluded: 1_200), locale: enUS).last,
            "1,200 edited videos and Live Photos not included"
        )
        // Shown only when the import ran with edited versions on.
        XCTAssertEqual(PhotosImportEditsSummaryText.lines(for: counts(included: false, originals: 9, notIncluded: 2), locale: enUS), [])
        XCTAssertEqual(PhotosImportEditsSummaryText.lines(for: nil, locale: enUS), [])
    }

    func testCaptionSwitchesWithToggle() throws {
        let staging = FileManager.default.temporaryDirectory
            .appendingPathComponent("photos-caption-\(UUID().uuidString)", isDirectory: true)
        let store = PhotosImportStore(
            access: AppStatePhotosAccessStub(),
            catalog: AppStatePhotosCatalogStub(),
            exporter: AppStatePhotosExporterStub(),
            stagingParentURL: staging
        )
        XCTAssertFalse(store.includeEditedVersions)
        XCTAssertEqual(
            PhotosImportView.headerCaption(for: store),
            "Imports the original photo or video. Edits made in Photos, such as crops and filters, are not included."
        )

        store.includeEditedVersions = true

        XCTAssertEqual(
            PhotosImportView.headerCaption(for: store),
            "Also saves the edited version of each edited photo as a separate file. Edited videos and Live Photos are not included."
        )
    }

    func testPreviewShowsEditedPhotoCountWithoutByteTotal() {
        XCTAssertEqual(
            PhotosImportEditsSummaryText.previewLine(for: counts(originals: 4, edited: 1), locale: enUS),
            "1 edited photo will also be saved"
        )
        let many = PhotosImportEditsSummaryText.previewLine(for: counts(originals: 2_000, edited: 1_234), locale: enUS)
        XCTAssertEqual(many, "1,234 edited photos will also be saved")
        // D-PIR-05: PhotoKit exposes no public size, so the line never claims one.
        for unit in ["byte", "KB", "MB", "GB", "TB"] {
            XCTAssertFalse(try XCTUnwrap(many).localizedCaseInsensitiveContains(unit))
        }
        XCTAssertNil(PhotosImportEditsSummaryText.previewLine(for: counts(originals: 4, edited: 0), locale: enUS))
        XCTAssertNil(PhotosImportEditsSummaryText.previewLine(for: counts(included: false, originals: 4, edited: 3), locale: enUS))
        XCTAssertNil(PhotosImportEditsSummaryText.previewLine(for: nil, locale: enUS))
    }

    func testPhotosFooterSummaryLinesShowOnlyWhileTheImportIsPending() {
        let sample = counts(originals: 4, edited: 3)
        XCTAssertEqual(
            PhotosImportView.editedSummaryLines(counts: sample, hasActiveImport: true),
            ["Originals: 4 \u{00B7} Edited versions: 3 \u{00B7} Could not save: 0"]
        )
        XCTAssertEqual(PhotosImportView.editedSummaryLines(counts: sample, hasActiveImport: false), [],
                       "A finished import's summary lives in the Run view")
    }

    // MARK: - D-EPR-120: Run view

    private func runModel(
        status: RunStatus,
        counts: PhotosImportEditedVersionCounts?
    ) -> RunWorkspaceModel {
        RunWorkspaceModel(
            context: RunWorkspaceContext(
                status: status,
                currentMode: status == .finished ? .transfer : .preview,
                currentTaskTitle: "",
                currentPhase: nil,
                progress: 1,
                metrics: RunMetrics(plannedCount: 4, copiedCount: 4),
                summary: nil,
                lastErrorMessage: nil,
                warningCount: 0,
                errorCount: 0,
                issueCount: 0,
                logEntries: [],
                historyDestinationRoot: "",
                currentSourceRoot: "",
                canStartRun: true,
                photosEditedVersionCounts: counts
            )
        )
    }

    func testOrganizePreviewShowsEditedPhotoCountForPhotosImport() {
        let withEdits = counts(originals: 4, edited: 3)
        XCTAssertEqual(
            runModel(status: .dryRunFinished, counts: withEdits).photosEditedPreviewLine,
            "3 edited photos will also be saved"
        )
        XCTAssertEqual(
            runModel(status: .dryRunFinished, counts: counts(originals: 4, edited: 1)).photosEditedPreviewLine,
            "1 edited photo will also be saved"
        )
        // Not a Photos import, edits off, nothing edited, or not the preview.
        XCTAssertNil(runModel(status: .dryRunFinished, counts: nil).photosEditedPreviewLine)
        XCTAssertNil(runModel(status: .dryRunFinished, counts: counts(included: false, originals: 4, edited: 3)).photosEditedPreviewLine)
        XCTAssertNil(runModel(status: .dryRunFinished, counts: counts(originals: 4, edited: 0)).photosEditedPreviewLine)
        XCTAssertNil(runModel(status: .finished, counts: withEdits).photosEditedPreviewLine)
        XCTAssertEqual(runModel(status: .dryRunFinished, counts: nil).photosEditedSummaryLines, [])
    }

    func testRunSummaryShowsEditedVersionCountsForPhotosImport() {
        let model = runModel(status: .finished, counts: counts(originals: 4, edited: 3, couldNotSave: 1, notIncluded: 1))

        XCTAssertEqual(model.photosEditedSummaryLines, [
            "Originals: 4 \u{00B7} Edited versions: 3 \u{00B7} Could not save: 1",
            "1 edited video or Live Photo not included",
        ])
        XCTAssertEqual(model.photosEditedPreviewLine, nil)
        // A non-Photos run, or one with edited versions off, shows nothing.
        XCTAssertEqual(runModel(status: .finished, counts: nil).photosEditedSummaryLines, [])
        XCTAssertEqual(runModel(status: .finished, counts: counts(included: false, originals: 4)).photosEditedSummaryLines, [])
        XCTAssertEqual(runModel(status: .dryRunFinished, counts: counts(originals: 4, edited: 3)).photosEditedSummaryLines, [])
    }

    func testFAQMentionsPhotosEditsAreNotImported() throws {
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let fileManager = FileManager.default
        while !fileManager.fileExists(atPath: directory.appendingPathComponent("docs/FAQ.md").path) {
            let parent = directory.deletingLastPathComponent()
            if parent == directory {
                XCTFail("Could not find docs/FAQ.md above \(#filePath)")
                return
            }
            directory = parent
        }
        let faq = try String(contentsOf: directory.appendingPathComponent("docs/FAQ.md"), encoding: .utf8)

        XCTAssertTrue(faq.contains("Does importing from Photos keep my edits?"))
        XCTAssertTrue(faq.contains("edits made in Photos, such as crops and filters, are not included"))
        XCTAssertTrue(faq.contains("Your Photos library is never changed"))
    }
}
