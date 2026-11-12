import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreLibraryHealthScannerTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeCoreLibraryHealthScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testHealthScannerCountsUnknownDuplicatesQueueReceiptsAndDrift() throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)

        try writeFile(destinationRoot.appendingPathComponent("Unknown_Date/Unknown_001.jpg"), contents: "unknown")
        try writeFile(destinationRoot.appendingPathComponent("Duplicate/2024/04/30/2024-04-30_001.jpg"), contents: "dup")
        try writeFile(destinationRoot.appendingPathComponent("Loose/holiday.jpg"), contents: "drift")
        let logsURL = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: logsURL.appendingPathComponent("audit_receipt_20260430.json"))

        let database = try OrganizerDatabase(
            url: destinationRoot.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
        )
        try database.saveCacheRecords(
            [
                FileCacheRecord(
                    namespace: .destination,
                    path: destinationRoot.appendingPathComponent("2024/04/30/2024-04-30_001.jpg").path,
                    identity: FileIdentity(size: 9, digest: "same"),
                    size: 9,
                    modificationTime: 1
                ),
                FileCacheRecord(
                    namespace: .destination,
                    path: destinationRoot.appendingPathComponent("2024/04/30/2024-04-30_002.jpg").path,
                    identity: FileIdentity(size: 3, digest: "same"),
                    size: 3,
                    modificationTime: 2
                ),
            ]
        )
        try database.enqueueQueuedJobs(
            [
                QueuedCopyJob(sourcePath: "/src/a.jpg", destinationPath: "/dst/a.jpg", hash: "1_hash-a", status: .pending),
                QueuedCopyJob(sourcePath: "/src/b.jpg", destinationPath: "/dst/b.jpg", hash: "1_hash-b", status: .failed),
            ]
        )
        database.close()

        let summary = LibraryHealthScanner().scan(
            sourceRoot: sourceRoot.path,
            destinationRoot: destinationRoot.path,
            folderStructure: .yyyyMMDD
        )

        XCTAssertEqual(summary.overallSeverity, .critical)
        XCTAssertEqual(card("No Date", in: summary)?.value, "1")
        XCTAssertEqual(card("Exact Copies", in: summary)?.value, "1")
        XCTAssertEqual(card("Unfinished Copies", in: summary)?.value, "2")
        XCTAssertEqual(card("Undo Records", in: summary)?.value, "1")
        XCTAssertEqual(card("Files Outside the Layout", in: summary)?.value, "1")
    }

    func testHealthScannerHandlesMissingSetupAndUnavailableDestination() {
        let summary = LibraryHealthScanner().scan(
            sourceRoot: "  ",
            destinationRoot: temporaryDirectoryURL.appendingPathComponent("missing-dest").path,
            folderStructure: .yyyyMMDD
        )

        XCTAssertEqual(summary.overallSeverity, .attention)
        XCTAssertEqual(card("Ready to Organize", in: summary)?.value, "Needs destination")
        XCTAssertEqual(card("No Date", in: summary)?.value, "0")
        XCTAssertEqual(card("Exact Copies", in: summary)?.value, "0")
        XCTAssertEqual(card("Unfinished Copies", in: summary)?.value, "0")
        XCTAssertEqual(card("Undo Records", in: summary)?.value, "0")
        XCTAssertEqual(card("Files Outside the Layout", in: summary)?.value, "0")
    }

    func testHealthScannerHandlesBlankDestinationPath() {
        let summary = LibraryHealthScanner().scan(
            sourceRoot: "/source",
            destinationRoot: "  ",
            folderStructure: .yyyyMMDD
        )

        XCTAssertEqual(summary.destinationRoot, "")
        XCTAssertEqual(summary.overallSeverity, .attention)
        XCTAssertEqual(summary.cards, [
            LibraryHealthCard(
                id: "ready",
                title: "Ready to Organize",
                value: "Needs destination",
                message: "Choose a destination folder before checking library health.",
                severity: .attention,
                action: .runPreview
            ),
        ])
    }

    func testHealthScannerReportsGoodForCleanDestinationWithReceipt() throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("clean-source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("clean-dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        let logsURL = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: logsURL.appendingPathComponent("dedupe_audit_receipt_20260430.json"))

        let summary = LibraryHealthScanner().scan(
            sourceRoot: sourceRoot.path,
            destinationRoot: destinationRoot.path,
            folderStructure: .yyyyMMDD
        )

        XCTAssertEqual(summary.overallSeverity, .good)
        XCTAssertEqual(card("Ready to Organize", in: summary)?.value, "Ready")
        XCTAssertEqual(card("No Date", in: summary)?.message, "No files are waiting in the Unknown_Date folder.")
        XCTAssertEqual(card("Exact Copies", in: summary)?.message, "No exact copies were set aside during past copies.")
        XCTAssertEqual(card("Unfinished Copies", in: summary)?.message, "No copies are waiting or failed.")
        XCTAssertEqual(card("Undo Records", in: summary)?.value, "1")
        XCTAssertEqual(card("Files Outside the Layout", in: summary)?.message, "Every recognized file follows the folder layout.")
    }

    func testLibraryHealthActionTitlesAreStable() {
        XCTAssertEqual(
            LibraryHealthAction.allCases.map(\.title),
            [
                "Run Preview",
                "Review Unknown Dates",
                "Run Deduplicate",
                "Open History",
                "Reorganize Destination",
                "Refresh Destination Index",
            ]
        )
    }

    func testNoReceiptsIsGoodAndSaysNothingToUndo() throws {
        let summary = try scanUntouchedDestination()
        let history = try XCTUnwrap(summary.cards.first { $0.id == "history" })

        XCTAssertEqual(history.title, "Undo Records")
        XCTAssertEqual(history.value, "0")
        XCTAssertEqual(history.severity, .good)
        XCTAssertEqual(history.message, "Nothing has been copied here yet, so there is nothing to undo.")
        XCTAssertEqual(history.action, .openHistory)
    }

    func testHasOrganizedHistoryFalseWithoutReceipts() throws {
        let summary = try scanUntouchedDestination()
        XCTAssertFalse(summary.hasOrganizedHistory)

        let withoutHistoryCard = LibraryHealthSummary(
            destinationRoot: "/dest",
            overallSeverity: .good,
            cards: summary.cards.filter { $0.id != "history" }
        )
        XCTAssertFalse(withoutHistoryCard.hasOrganizedHistory)

        let encoded = try JSONEncoder().encode(summary)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["hasOrganizedHistory"])
    }

    func testHasOrganizedHistoryTrueWithOneReceipt() throws {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("one-receipt-source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("one-receipt-dest", isDirectory: true)
        let logsURL = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: logsURL.appendingPathComponent("audit_receipt_20260430.json"))

        let summary = LibraryHealthScanner().scan(
            sourceRoot: sourceRoot.path,
            destinationRoot: destinationRoot.path,
            folderStructure: .yyyyMMDD
        )
        let history = try XCTUnwrap(summary.cards.first { $0.id == "history" })

        XCTAssertTrue(summary.hasOrganizedHistory)
        XCTAssertEqual(history.value, "1")
        XCTAssertEqual(history.severity, .good)
        XCTAssertEqual(history.message, "Receipts are saved for recent copies, so they can be undone.")
    }

    func testCardTitlesMatchContract() throws {
        let clean = try scanUntouchedDestination()
        XCTAssertEqual(
            clean.cards.map(\.title),
            ["Ready to Organize", "No Date", "Exact Copies", "Unfinished Copies", "Undo Records", "Files Outside the Layout"]
        )

        let populated = try scanPopulatedDestination()
        func message(_ id: String) -> String? { populated.cards.first { $0.id == id }?.message }
        XCTAssertTrue(try XCTUnwrap(message("unknown-dates")).hasSuffix(" of files need a date."))
        XCTAssertTrue(try XCTUnwrap(message("duplicates")).hasSuffix(" could be freed after you review them."))
        XCTAssertEqual(message("interrupted-work"), "1 waiting, 1 failed. Open Preview & Copy to finish them.")
        XCTAssertEqual(message("history"), "Receipts are saved for recent copies, so they can be undone.")
        XCTAssertEqual(message("structure-drift"), "Some files don't follow Chronoframe's folder layout.")
        XCTAssertEqual(clean.cards.first { $0.id == "structure-drift" }?.message, "Every recognized file follows the folder layout.")
    }

    func testOverallSeverityOfUntouchedDestinationIsGood() throws {
        let summary = try scanUntouchedDestination()
        XCTAssertEqual(summary.overallSeverity, .good)
        XCTAssertTrue(summary.cards.allSatisfy { $0.severity == .good })
    }

    func testCardIDsAndActionsUnchanged() throws {
        let clean = try scanUntouchedDestination()
        XCTAssertEqual(
            clean.cards.map(\.id),
            ["ready", "unknown-dates", "duplicates", "interrupted-work", "history", "structure-drift"]
        )
        XCTAssertEqual(clean.cards.map(\.action), [.runPreview, nil, nil, nil, .openHistory, nil])

        let populated = try scanPopulatedDestination()
        XCTAssertEqual(populated.cards.map(\.id), clean.cards.map(\.id))
        XCTAssertEqual(
            populated.cards.map(\.action),
            [.runPreview, .reviewUnknownDates, .runDeduplicate, .runPreview, .openHistory, .reorganizeDestination]
        )
        XCTAssertEqual(
            LibraryHealthAction.allCases.map(\.rawValue),
            ["runPreview", "reviewUnknownDates", "runDeduplicate", "openHistory", "reorganizeDestination", "refreshDestinationIndex"]
        )
    }

    private func scanUntouchedDestination() throws -> LibraryHealthSummary {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("untouched-source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("untouched-dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        return LibraryHealthScanner().scan(
            sourceRoot: sourceRoot.path,
            destinationRoot: destinationRoot.path,
            folderStructure: .yyyyMMDD
        )
    }

    private func scanPopulatedDestination() throws -> LibraryHealthSummary {
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("populated-source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("populated-dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try writeFile(destinationRoot.appendingPathComponent("Unknown_Date/Unknown_001.jpg"), contents: "unknown")
        try writeFile(destinationRoot.appendingPathComponent("Duplicate/2024/04/30/2024-04-30_001.jpg"), contents: "dup")
        try writeFile(destinationRoot.appendingPathComponent("Loose/holiday.jpg"), contents: "drift")
        let logsURL = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsURL, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: logsURL.appendingPathComponent("audit_receipt_20260430.json"))

        let database = try OrganizerDatabase(
            url: destinationRoot.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
        )
        try database.enqueueQueuedJobs(
            [
                QueuedCopyJob(sourcePath: "/src/a.jpg", destinationPath: "/dst/a.jpg", hash: "1_hash-a", status: .pending),
                QueuedCopyJob(sourcePath: "/src/b.jpg", destinationPath: "/dst/b.jpg", hash: "1_hash-b", status: .failed),
            ]
        )
        database.close()

        return LibraryHealthScanner().scan(
            sourceRoot: sourceRoot.path,
            destinationRoot: destinationRoot.path,
            folderStructure: .yyyyMMDD
        )
    }

    private func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func card(_ title: String, in summary: LibraryHealthSummary) -> LibraryHealthCard? {
        summary.cards.first { $0.title == title }
    }
}
