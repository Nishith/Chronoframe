import Darwin
import Foundation
import XCTest
@testable import ChronoframeCore

/// Receipts are written into `.organize_logs` inside the user-selected
/// destination, where a receipt's name is visible for the whole run (the
/// pending receipt uses it). Whatever sits at the old predictable
/// `<receipt>.tmp` name must never receive the write.
final class ReceiptDurabilityTests: XCTestCase {
    private func makeDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ReceiptDurability-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeSentinel(in directory: URL) throws -> URL {
        let sentinel = directory.appendingPathComponent("sentinel-\(UUID().uuidString).txt")
        try Data("SENTINEL".utf8).write(to: sentinel)
        return sentinel
    }

    private let receiptData = Data(#"{"status":"COMPLETED"}"#.utf8)

    private func receiptURL(in logs: URL) -> URL {
        logs.appendingPathComponent("audit_receipt_20260927_120000_run.json")
    }

    func testLinkAtPredictableTempNameIsNeverWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        let predictableTemp = receiptURL(in: logs).appendingPathExtension("tmp")
        try FileManager.default.createSymbolicLink(at: predictableTemp, withDestinationURL: sentinel)

        try ReceiptDurability.durablyWrite(data: receiptData, to: receiptURL(in: logs))

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
        XCTAssertEqual(try Data(contentsOf: receiptURL(in: logs)), receiptData)
    }

    func testHardLinkAtPredictableTempNameIsNeverWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: logs)
        try FileManager.default.linkItem(at: sentinel, to: receiptURL(in: logs).appendingPathExtension("tmp"))

        try ReceiptDurability.durablyWrite(data: receiptData, to: receiptURL(in: logs))

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
        XCTAssertEqual(try Data(contentsOf: receiptURL(in: logs)), receiptData)
    }

    func testFifoAtPredictableTempNameDoesNotBlockTheWrite() throws {
        let logs = try makeDirectory()
        XCTAssertEqual(mkfifo(receiptURL(in: logs).appendingPathExtension("tmp").path, S_IRUSR | S_IWUSR), 0)

        try ReceiptDurability.durablyWrite(data: receiptData, to: receiptURL(in: logs))

        XCTAssertEqual(try Data(contentsOf: receiptURL(in: logs)), receiptData)
    }

    func testLinkAtReceiptNameIsReplacedNotWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        try FileManager.default.createSymbolicLink(at: receiptURL(in: logs), withDestinationURL: sentinel)

        try ReceiptDurability.durablyWrite(data: receiptData, to: receiptURL(in: logs))

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
        let attributes = try FileManager.default.attributesOfItem(atPath: receiptURL(in: logs).path)
        XCTAssertEqual(attributes[.type] as? FileAttributeType, .typeRegular)
        XCTAssertEqual(try Data(contentsOf: receiptURL(in: logs)), receiptData)
    }

    func testRewritingAReceiptReplacesItAndLeavesNoTemporaryFiles() throws {
        let logs = try makeDirectory()
        try ReceiptDurability.durablyWrite(data: Data(#"{"status":"PENDING"}"#.utf8), to: receiptURL(in: logs))

        try ReceiptDurability.durablyWrite(data: receiptData, to: receiptURL(in: logs))

        XCTAssertEqual(try Data(contentsOf: receiptURL(in: logs)), receiptData)
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: logs.path),
            [receiptURL(in: logs).lastPathComponent]
        )
    }
}
