import Foundation
import XCTest
@testable import ChronoframeCore

/// Golden-file tests that pin the on-disk shape of `audit_receipt_*.json` and
/// the behavior of `RevertReceipt`'s decoder for each schemaVersion the writer
/// has emitted (or could plausibly emit).
///
/// Existing roundtrip tests encode-then-decode through a single shape; they
/// cannot surface the gap where a writer emits a newer `schemaVersion` and an
/// older reader silently treats it as the version it knows. These tests load
/// hand-crafted JSON fixtures so each schema variant is exercised explicitly.
///
/// The writer emits **v3** today. The version is not cosmetic: it is what tells
/// a refund whether the receipt's `runID` is the run's reservation ID (v3) or
/// the private UUID the receipt writer used to mint for itself (v1/v2). See the
/// "Pre-v3 run IDs" cases below — that distinction is the whole reason the
/// version was bumped, and getting it wrong credits allowance against runs that
/// never existed.
///
/// Forward-version rejection lives at the executor level, not in the decoder:
/// `RevertExecutor.loadReceipt` throws `unsupportedSchema`, while the raw
/// decoder stays forward-compatible so migration and telemetry tooling can
/// still inspect a receipt it does not fully understand.
final class RevertReceiptGoldenFileTests: XCTestCase {

    // MARK: V2 — current writer shape

    private static let v2Receipt = #"""
    {
      "schemaVersion": 2,
      "timestamp": "2026-04-15T12:00:00Z",
      "status": "COMPLETED",
      "total_jobs": 2,
      "transfers": [
        {
          "source": "/Volumes/Source/IMG_0001.jpg",
          "dest": "/Volumes/Destination/2024/06/15/2024-06-15_001.jpg",
          "hash": "1024_aabbccdd"
        },
        {
          "source": "/Volumes/Source/IMG_0002.heic",
          "dest": "/Volumes/Destination/2024/06/15/2024-06-15_002.heic",
          "hash": "2048_eeff0011"
        }
      ]
    }
    """#

    func testCurrentDecoderParsesV2ReceiptIntoTransferList() throws {
        let data = Self.v2Receipt.data(using: .utf8)!
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: data)
        XCTAssertEqual(receipt.status, "COMPLETED")
        XCTAssertEqual(receipt.timestamp, "2026-04-15T12:00:00Z")
        XCTAssertEqual(receipt.totalJobs, 2)
        XCTAssertEqual(receipt.transfers.count, 2)
        XCTAssertEqual(receipt.transfers[0].source, "/Volumes/Source/IMG_0001.jpg")
        XCTAssertEqual(receipt.transfers[0].dest, "/Volumes/Destination/2024/06/15/2024-06-15_001.jpg")
        XCTAssertEqual(receipt.transfers[0].hash, "1024_aabbccdd")
    }

    // MARK: V1 — early writer shape (no status, no schemaVersion)

    private static let v1Receipt = #"""
    {
      "timestamp": "2024-01-15T10:00:00Z",
      "total_jobs": 1,
      "transfers": [
        {
          "source": "/old/IMG_0001.jpg",
          "dest": "/dest/2024/01/15/2024-01-15_001.jpg",
          "hash": "512_legacyhash"
        }
      ]
    }
    """#

    func testCurrentDecoderAcceptsLegacyV1ReceiptWithoutStatusField() throws {
        let data = Self.v1Receipt.data(using: .utf8)!
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: data)
        XCTAssertNil(receipt.status, "Legacy receipts without status should decode with status == nil")
        XCTAssertEqual(receipt.totalJobs, 1)
        XCTAssertEqual(receipt.transfers.count, 1)
    }

    // MARK: Status variants the writer can produce

    private static func receiptJSON(withStatus status: String, transferCount: Int = 1) -> String {
        let transfers = (0..<transferCount).map { i in
            #"""
            {"source": "/s/\#(i)", "dest": "/d/\#(i)", "hash": "\#(i)_h\#(i)"}
            """#
        }.joined(separator: ",\n          ")
        return #"""
        {
          "schemaVersion": 2,
          "timestamp": "2026-04-15T12:00:00Z",
          "status": "\#(status)",
          "total_jobs": \#(transferCount),
          "transfers": [
            \#(transfers)
          ]
        }
        """#
    }

    // AGENTS-INVARIANT: 9
    func testCurrentDecoderAcceptsAllStatusValuesTheWriterEmits() throws {
        for status in ["PENDING", "COMPLETED", "ABORTED", "FAILED"] {
            let data = Self.receiptJSON(withStatus: status).data(using: .utf8)!
            let receipt = try JSONDecoder().decode(RevertReceipt.self, from: data)
            XCTAssertEqual(receipt.status, status)
            XCTAssertEqual(receipt.transfers.count, 1)
        }
    }

    // MARK: Forward-compat gap — Finding #6

    private static let v99Receipt = #"""
    {
      "schemaVersion": 99,
      "timestamp": "2030-01-01T00:00:00Z",
      "status": "COMPLETED",
      "total_jobs": 1,
      "identityScheme": "blake3-v1",
      "boundary": "/Volumes/Future",
      "transfers": [
        {
          "source": "/s/a.jpg",
          "dest": "/d/a.jpg",
          "hash": "1024_future_hash_with_different_algorithm"
        }
      ]
    }
    """#

    /// Finding #6 is now FIXED. `RevertExecutor.loadReceipt` rejects
    /// receipts whose `schemaVersion` is higher than this reader
    /// understands. The decoder itself still accepts the raw JSON
    /// (forward-compatible field-dropping is the right Codable
    /// behavior) — the gate lives at the executor level where it can
    /// be reported with a user-actionable error.
    func testLoadReceiptRejectsFutureSchemaVersionWithUnsupportedSchemaError() throws {
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("v99-receipt-\(UUID().uuidString).json")
        try Self.v99Receipt.data(using: .utf8)!.write(to: tmpURL)
        defer { try? FileManager.default.removeItem(at: tmpURL) }

        let executor = RevertExecutor()
        XCTAssertThrowsError(try executor.loadReceipt(at: tmpURL)) { error in
            guard case let RevertExecutorError.unsupportedSchema(version) = error else {
                XCTFail("Expected unsupportedSchema, got \(error)")
                return
            }
            XCTAssertEqual(version, 99)
        }
    }

    /// Sanity: the raw decoder still parses v99 JSON and surfaces the
    /// version. Only the executor-level gate rejects it, so unit-level
    /// inspection (e.g. for telemetry / migration tooling) still works.
    func testRawDecoderExposesSchemaVersionField() throws {
        let data = Self.v99Receipt.data(using: .utf8)!
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: data)
        XCTAssertEqual(receipt.schemaVersion, 99)
        XCTAssertEqual(receipt.transfers.count, 1)
    }

    // MARK: V3 — run ID usable as a refund key

    private static let v3Receipt = #"""
    {
      "schemaVersion": 3,
      "runID": "6B29FC40-CA47-1067-B31D-00DD010662DA",
      "operation": "organize",
      "timestamp": "2026-08-10T12:00:00Z",
      "status": "COMPLETED",
      "total_jobs": 1,
      "transfers": [
        {
          "source": "/Volumes/Source/IMG_0003.jpg",
          "dest": "/Volumes/Destination/2024/06/15/2024-06-15_003.jpg",
          "hash": "4096_00112233"
        }
      ]
    }
    """#

    func testV3ReceiptExposesItsRunIDAsARefundKey() throws {
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: Data(Self.v3Receipt.utf8))
        let expected = UUID(uuidString: "6B29FC40-CA47-1067-B31D-00DD010662DA")
        XCTAssertEqual(receipt.schemaVersion, 3)
        XCTAssertEqual(receipt.runID, expected)
        XCTAssertEqual(receipt.reservationRunID, expected)
        XCTAssertEqual(receipt.transfers.count, 1)
    }

    func testV3RoundTripsThroughEncodeAndDecode() throws {
        let original = RevertReceipt(
            schemaVersion: 3,
            timestamp: "2026-08-10T12:00:00Z",
            status: "COMPLETED",
            totalJobs: 1,
            transfers: [RevertReceiptTransfer(source: "/s", dest: "/d", hash: "1_h")],
            runID: UUID()
        )
        let decoded = try JSONDecoder().decode(
            RevertReceipt.self,
            from: try JSONEncoder().encode(original)
        )
        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.reservationRunID, original.runID)
    }

    /// A v3 receipt that somehow lacks a run ID is simply not refundable. It
    /// must still load and still revert.
    func testV3ReceiptWithoutARunIDDecodesWithNilRunID() throws {
        let json = #"""
        {
          "schemaVersion": 3,
          "status": "COMPLETED",
          "transfers": [{ "source": "/s", "dest": "/d", "hash": "1_h" }]
        }
        """#
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: Data(json.utf8))
        XCTAssertNil(receipt.runID)
        XCTAssertNil(receipt.reservationRunID)
        XCTAssertEqual(receipt.transfers.count, 1)
    }

    // MARK: Pre-v3 run IDs must never be used as refund keys

    /// The important one. Receipts written before run IDs were threaded DO
    /// carry a `runID` — but it was a UUID private to the receipt writer,
    /// matching no reservation and no `CopyJobs` row. It is well-formed, so
    /// nothing would fail loudly if a refund keyed off it; the allowance would
    /// just be credited against a run that never existed.
    func testV2ReceiptRunIDIsDecodedButRefusedAsARefundKey() throws {
        let json = #"""
        {
          "schemaVersion": 2,
          "runID": "11111111-2222-3333-4444-555555555555",
          "status": "COMPLETED",
          "transfers": [{ "source": "/s", "dest": "/d", "hash": "1_h" }]
        }
        """#
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: Data(json.utf8))
        XCTAssertEqual(receipt.runID, UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        XCTAssertNil(receipt.reservationRunID, "A pre-v3 run ID is not a reservation key")
    }

    /// v1 has no `schemaVersion` at all, so it can never clear the v3 bar.
    func testV1ReceiptIsNeverRefundable() throws {
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: Data(Self.v1Receipt.utf8))
        XCTAssertNil(receipt.schemaVersion)
        XCTAssertNil(receipt.reservationRunID)
    }

    func testV2ReceiptWithoutARunIDIsNeverRefundable() throws {
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: Data(Self.v2Receipt.utf8))
        XCTAssertNil(receipt.runID)
        XCTAssertNil(receipt.reservationRunID)
    }

    /// A malformed run ID must not block a revert. Revert never consults the
    /// field, and refusing to load the receipt over it would strand files.
    func testMalformedRunIDDoesNotPreventDecoding() throws {
        let json = #"""
        {
          "schemaVersion": 3,
          "runID": "not-a-uuid",
          "status": "COMPLETED",
          "transfers": [{ "source": "/s", "dest": "/d", "hash": "1_h" }]
        }
        """#
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: Data(json.utf8))
        XCTAssertNil(receipt.runID)
        XCTAssertNil(receipt.reservationRunID)
        XCTAssertEqual(receipt.transfers.count, 1, "The revert itself must be unaffected")
    }

    // MARK: Malformed shapes the decoder must reject

    private static let receiptMissingHash = #"""
    {
      "status": "COMPLETED",
      "transfers": [
        { "source": "/s", "dest": "/d" }
      ]
    }
    """#

    func testDecoderRejectsTransferMissingRequiredFields() {
        let data = Self.receiptMissingHash.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(RevertReceipt.self, from: data))
    }

    private static let receiptEmptyTransfers = #"""
    { "status": "COMPLETED", "transfers": [] }
    """#

    func testDecoderAcceptsEmptyTransferList() throws {
        let data = Self.receiptEmptyTransfers.data(using: .utf8)!
        let receipt = try JSONDecoder().decode(RevertReceipt.self, from: data)
        XCTAssertTrue(receipt.transfers.isEmpty)
    }
}
