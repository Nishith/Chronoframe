import Foundation
import XCTest
@testable import ChronoframeAppCore

final class HistoryStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeHistoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testRefreshDiscoversRunArtifacts() throws {
        let logFile = temporaryDirectoryURL.appendingPathComponent(".organize_log.txt")
        let logsDirectory = temporaryDirectoryURL.appendingPathComponent(".organize_logs", isDirectory: true)
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)

        let report = logsDirectory.appendingPathComponent("dry_run_report_20260413_120000.csv")
        let receipt = logsDirectory.appendingPathComponent("audit_receipt_20260413_121500.json")

        try "run log".write(to: logFile, atomically: true, encoding: .utf8)
        try "report".write(to: report, atomically: true, encoding: .utf8)
        try "{}".write(to: receipt, atomically: true, encoding: .utf8)

        let store = HistoryStore()
        store.refresh(destinationRoot: temporaryDirectoryURL.path)

        let normalizedPaths = Set(
            store.entries.map { URL(fileURLWithPath: $0.path).resolvingSymlinksInPath().path }
        )

        XCTAssertEqual(store.entries.count, 3)
        XCTAssertTrue(normalizedPaths.contains(logFile.resolvingSymlinksInPath().path))
        XCTAssertTrue(normalizedPaths.contains(report.resolvingSymlinksInPath().path))
        XCTAssertTrue(normalizedPaths.contains(receipt.resolvingSymlinksInPath().path))
        XCTAssertNil(store.lastRefreshError)
    }
}
