import Darwin
import XCTest
@testable import ChronoframeCore

final class ChronoframeCorePortPreparationTests: XCTestCase {
    private struct PortPreparationPayload: Codable, Equatable {
        var state: SequenceCounterState
        var transfer: PlannedTransfer
    }

    func testFileIdentityRoundTripsChronoframeDefaultFormat() {
        let identity = FileIdentity(size: 12, digest: "abc123")
        XCTAssertEqual(identity.rawValue, "12_abc123")
        XCTAssertEqual(FileIdentity(rawValue: identity.rawValue), identity)
    }

    func testFileIdentityRejectsMalformedRawValues() {
        XCTAssertNil(FileIdentity(rawValue: ""))
        XCTAssertNil(FileIdentity(rawValue: "abc123"))
        XCTAssertNil(FileIdentity(rawValue: "size_only_"))
        XCTAssertNil(FileIdentity(rawValue: "_digest"))
    }

    func testQueueAndCacheReferenceTypesRemainStable() {
        XCTAssertEqual(CacheNamespace.source.rawValue, 1)
        XCTAssertEqual(CacheNamespace.destination.rawValue, 2)
        XCTAssertEqual(CopyJobStatus.pending.rawValue, "PENDING")
        XCTAssertEqual(CopyJobStatus.copied.rawValue, "COPIED")
        XCTAssertEqual(CopyJobStatus.failed.rawValue, "FAILED")

        let identity = FileIdentity(size: 7, digest: "digest")
        let cacheRecord = FileCacheRecord(
            namespace: .destination,
            path: "/dest/2024/02/14/2024-02-14_001.jpg",
            identity: identity,
            size: 7,
            modificationTime: 1_700_000_000
        )
        let copyJob = CopyJobRecord(
            sourcePath: "/source/IMG_20240214_080000.jpg",
            destinationPath: "/dest/2024/02/14/2024-02-14_001.jpg",
            identity: identity,
            status: .pending
        )

        XCTAssertEqual(cacheRecord.identityString, "7_digest")
        XCTAssertEqual(copyJob.identityString, "7_digest")
    }

    func testPlannerNamingAndArtifactLayoutReferenceValuesRemainStable() {
        XCTAssertEqual(PlannerNamingRules.chronoframeDefault.sequenceWidth, 3)
        XCTAssertEqual(PlannerNamingRules.chronoframeDefault.duplicateDirectoryName, "Duplicate")
        XCTAssertEqual(PlannerNamingRules.chronoframeDefault.unknownDateDirectoryName, "Unknown_Date")
        XCTAssertEqual(PlannerNamingRules.chronoframeDefault.unknownFilenamePrefix, "Unknown_")
        XCTAssertEqual(PlannerNamingRules.chronoframeDefault.collisionSuffixPrefix, "_collision_")

        XCTAssertEqual(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename, ".organize_cache.db")
        XCTAssertEqual(EngineArtifactLayout.chronoframeDefault.runLogFilename, ".organize_log.txt")
        XCTAssertEqual(EngineArtifactLayout.chronoframeDefault.logsDirectoryName, ".organize_logs")
        XCTAssertEqual(EngineArtifactLayout.chronoframeDefault.dryRunReportPrefix, "dry_run_report_")
        XCTAssertEqual(EngineArtifactLayout.chronoframeDefault.auditReceiptPrefix, "audit_receipt_")
    }

    func testReferenceRetryAndFailurePoliciesRemainStable() {
        XCTAssertEqual(RetryPolicy.chronoframeDefault.maxAttempts, 5)
        XCTAssertEqual(RetryPolicy.chronoframeDefault.minimumBackoffSeconds, 1)
        XCTAssertEqual(RetryPolicy.chronoframeDefault.maximumBackoffSeconds, 10)
        XCTAssertEqual(
            RetryPolicy.chronoframeDefault.nonRetryableErrnos,
            [
                Int32(ENOSPC),
                Int32(ENOENT),
                Int32(ENOTDIR),
                Int32(EISDIR),
                Int32(EINVAL),
                Int32(EACCES),
                Int32(EPERM),
            ]
        )

        XCTAssertEqual(FailureThresholds.chronoframeDefault.consecutive, 5)
        XCTAssertEqual(FailureThresholds.chronoframeDefault.total, 20)
    }

    func testSequenceCountersAndPlannedTransfersAreCodableValueTypes() throws {
        let identity = FileIdentity(size: 9, digest: "deadbeef")
        let state = SequenceCounterState(
            primaryByDate: ["2024-02-14": 4],
            duplicatesByDate: ["2024-02-14": 2]
        )
        let transfer = PlannedTransfer(
            sourcePath: "/source/IMG_20240214_080100.jpg",
            destinationPath: "/dest/2024/02/14/2024-02-14_005.jpg",
            identity: identity,
            dateBucket: "2024-02-14",
            isDuplicate: false
        )

        let payload = PortPreparationPayload(state: state, transfer: transfer)
        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PortPreparationPayload.self, from: data)

        XCTAssertEqual(decoded.state, state)
        XCTAssertEqual(decoded.transfer, transfer)
    }
}
