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

    // AGENTS-INVARIANT: 9
    // AGENTS-INVARIANT: 26
    func testLinkAtPredictableTempNameIsNeverWrittenThrough() throws {
        let logs = try makeDirectory()
        let sentinel = try makeSentinel(in: try makeDirectory())
        let predictableTemp = receiptURL(in: logs).appendingPathExtension("tmp")
        try FileManager.default.createSymbolicLink(at: predictableTemp, withDestinationURL: sentinel)

        try ReceiptDurability.durablyWrite(data: receiptData, to: receiptURL(in: logs))

        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "SENTINEL")
        XCTAssertEqual(try Data(contentsOf: receiptURL(in: logs)), receiptData)
    }

    // AGENTS-INVARIANT: 9
    // AGENTS-INVARIANT: 26
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

    // AGENTS-INVARIANT: 26
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

    func testFailedRenameThrowsAndRemovesOnlyItsOwnTemp() throws {
        let logs = try makeDirectory()
        // A directory at the receipt name makes the final rename fail.
        let receipt = receiptURL(in: logs)
        try FileManager.default.createDirectory(at: receipt, withIntermediateDirectories: true)
        try Data("keep".utf8).write(to: receipt.appendingPathComponent("inside.txt"))
        let bystander = logs.appendingPathComponent("audit_receipt_other.json.tmp")
        try Data("BYSTANDER".utf8).write(to: bystander)

        XCTAssertThrowsError(try ReceiptDurability.durablyWrite(data: receiptData, to: receipt))

        XCTAssertEqual(
            Set(try FileManager.default.contentsOfDirectory(atPath: logs.path)),
            [receipt.lastPathComponent, bystander.lastPathComponent]
        )
        XCTAssertEqual(try String(contentsOf: bystander, encoding: .utf8), "BYSTANDER")
        XCTAssertEqual(try Data(contentsOf: receipt.appendingPathComponent("inside.txt")), Data("keep".utf8))
    }

    func testUnwritableDirectoryThrowsWithoutLeavingFiles() throws {
        let logs = try makeDirectory()
        XCTAssertEqual(chmod(logs.path, S_IRUSR | S_IXUSR), 0)
        addTeardownBlock { _ = chmod(logs.path, S_IRWXU) }
        try XCTSkipIf(access(logs.path, W_OK) == 0, "Directory stayed writable (running with elevated privileges).")

        XCTAssertThrowsError(try ReceiptDurability.durablyWrite(data: receiptData, to: receiptURL(in: logs)))

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: logs.path), [])
    }
}
