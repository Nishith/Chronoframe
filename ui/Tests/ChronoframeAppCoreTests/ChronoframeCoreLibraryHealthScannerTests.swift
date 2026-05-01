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
            url: destinationRoot.appendingPathComponent(EngineArtifactLayout.pythonReference.queueDatabaseFilename)
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
        XCTAssertEqual(card("Unknown Dates", in: summary)?.value, "1")
        XCTAssertEqual(card("Duplicates", in: summary)?.value, "1")
        XCTAssertEqual(card("Interrupted Work", in: summary)?.value, "2")
        XCTAssertEqual(card("History & Revert Safety", in: summary)?.value, "1")
        XCTAssertEqual(card("Structure Drift", in: summary)?.value, "1")
    }

    func testHealthScannerHandlesMissingSetupAndUnavailableDestination() {
        let summary = LibraryHealthScanner().scan(
            sourceRoot: "  ",
            destinationRoot: temporaryDirectoryURL.appendingPathComponent("missing-dest").path,
            folderStructure: .yyyyMMDD
        )

        XCTAssertEqual(summary.overallSeverity, .attention)
        XCTAssertEqual(card("Ready to Organize", in: summary)?.value, "Needs destination")
        XCTAssertEqual(card("Unknown Dates", in: summary)?.value, "0")
        XCTAssertEqual(card("Duplicates", in: summary)?.value, "0")
        XCTAssertEqual(card("Interrupted Work", in: summary)?.value, "0")
        XCTAssertEqual(card("History & Revert Safety", in: summary)?.value, "0")
        XCTAssertEqual(card("Structure Drift", in: summary)?.value, "0")
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
        XCTAssertEqual(card("Unknown Dates", in: summary)?.message, "No files are currently parked in Unknown_Date.")
        XCTAssertEqual(card("Duplicates", in: summary)?.message, "No exact duplicate hints are visible from the destination cache.")
        XCTAssertEqual(card("Interrupted Work", in: summary)?.message, "There are no pending or failed copy jobs in the queue.")
        XCTAssertEqual(card("History & Revert Safety", in: summary)?.value, "1")
        XCTAssertEqual(card("Structure Drift", in: summary)?.message, "Recognized media filenames match Chronoframe's naming pattern.")
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

    private func writeFile(_ url: URL, contents: String) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func card(_ title: String, in summary: LibraryHealthSummary) -> LibraryHealthCard? {
        summary.cards.first { $0.title == title }
    }
}
