import Foundation
import SQLite3
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreGuardianScanTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeCoreGuardianScanTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func trustedEntry(
        _ path: String,
        size: Int64,
        mtime: TimeInterval,
        digest: String
    ) -> GuardianManifestEntry {
        GuardianManifestEntry(
            relativePath: path,
            size: size,
            modificationTime: mtime,
            digest: digest,
            trustState: .trusted,
            provenance: .userAccepted,
            firstObservedAt: Date(timeIntervalSince1970: 1_600_000_000),
            lastVerifiedAt: Date(timeIntervalSince1970: 1_600_000_000)
        )
    }

    private func observation(
        _ path: String,
        size: Int64,
        mtime: TimeInterval,
        digest: String?,
        outcome: GuardianProbeOutcome
    ) -> GuardianFileObservation {
        GuardianFileObservation(relativePath: path, size: size, modificationTime: mtime, digest: digest, outcome: outcome)
    }

    // MARK: - Classifier

    func testClassifierVerifiesMatchingTrustedFile() {
        let manifest = ["a.jpg": trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")]
        let observations = [observation("a.jpg", size: 10, mtime: 100, digest: "good", outcome: .hashed)]
        let report = GuardianIntegrityClassifier().classify(
            libraryRoot: "/lib", manifest: manifest, observations: observations, partialScan: false
        )
        XCTAssertEqual(report.findings.first?.status, .verified)
        XCTAssertEqual(report.findings.first?.trustState, .trusted)
    }

    func testClassifierFlagsSilentCorruptionWhenSizeAndMtimeUnchanged() {
        let manifest = ["a.jpg": trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")]
        // Same size and mtime, different digest => silent bit rot.
        let observations = [observation("a.jpg", size: 10, mtime: 100, digest: "rotten", outcome: .hashed)]
        let report = GuardianIntegrityClassifier().classify(
            libraryRoot: "/lib", manifest: manifest, observations: observations, partialScan: false
        )
        XCTAssertEqual(report.findings.first?.status, .corrupt)
        XCTAssertEqual(report.findings.first?.trustState, .changedPendingReview)
        XCTAssertTrue(report.hasCorruption)
    }

    func testClassifierFlagsModifiedWhenMtimeAdvanced() {
        let manifest = ["a.jpg": trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")]
        let observations = [observation("a.jpg", size: 12, mtime: 200, digest: "edited", outcome: .hashed)]
        let report = GuardianIntegrityClassifier().classify(
            libraryRoot: "/lib", manifest: manifest, observations: observations, partialScan: false
        )
        XCTAssertEqual(report.findings.first?.status, .modified)
        XCTAssertEqual(report.findings.first?.trustState, .changedPendingReview)
    }

    func testClassifierReportsMissingAndNew() {
        let manifest = ["gone.jpg": trustedEntry("gone.jpg", size: 5, mtime: 50, digest: "g")]
        let observations = [observation("fresh.jpg", size: 7, mtime: 70, digest: "f", outcome: .hashed)]
        let report = GuardianIntegrityClassifier().classify(
            libraryRoot: "/lib", manifest: manifest, observations: observations, partialScan: false
        )
        XCTAssertEqual(report.count(of: .missing), 1)
        XCTAssertEqual(report.count(of: .new), 1)
    }

    func testPartialScanSuppressesMissing() {
        let manifest = ["gone.jpg": trustedEntry("gone.jpg", size: 5, mtime: 50, digest: "g")]
        let report = GuardianIntegrityClassifier().classify(
            libraryRoot: "/lib", manifest: manifest, observations: [], partialScan: true
        )
        XCTAssertEqual(report.count(of: .missing), 0, "a partial scan must not report unseen files as missing")
        XCTAssertTrue(report.partialScan)
    }

    func testClassifierPassesThroughAmbiguousReadings() {
        let manifest = ["a.jpg": trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")]
        let observations = [observation("a.jpg", size: 10, mtime: 100, digest: nil, outcome: .changedDuringScan)]
        let report = GuardianIntegrityClassifier().classify(
            libraryRoot: "/lib", manifest: manifest, observations: observations, partialScan: false
        )
        XCTAssertEqual(report.findings.first?.status, .changedDuringScan)
        XCTAssertFalse(report.hasCorruption)
    }

    func testDatalessNeverReportedAsCorruption() {
        let manifest = ["a.jpg": trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")]
        let observations = [observation("a.jpg", size: 10, mtime: 100, digest: nil, outcome: .dataless)]
        let report = GuardianIntegrityClassifier().classify(
            libraryRoot: "/lib", manifest: manifest, observations: observations, partialScan: false
        )
        XCTAssertEqual(report.findings.first?.status, .dataless)
        XCTAssertFalse(report.hasCorruption)
    }

    // MARK: - Updater (trust rules)

    // AGENTS-INVARIANT: 23
    func testScanUpsertsNeverAdvanceTrustAndDemoteWithoutRebaselining() {
        let updater = GuardianManifestUpdater()
        let now = Date(timeIntervalSince1970: 1_700_000_000)

        // A brand-new file is recorded as UNPROTECTED, never trusted.
        let newReport = GuardianIntegrityReport(
            libraryRoot: "/lib",
            findings: [
                GuardianIntegrityFinding(
                    relativePath: "new.jpg", status: .new, trustState: .unprotected,
                    observedIdentity: FileIdentity(size: 3, digest: "n"), observedModificationTime: 30
                ),
            ]
        )
        let newUpserts = updater.scanUpserts(report: newReport, manifest: [:], now: now)
        XCTAssertEqual(newUpserts.first?.trustState, .unprotected)
        XCTAssertNil(newUpserts.first?.provenance)

        // Silent corruption DEMOTES a trusted entry but keeps the good baseline
        // digest — it must never re-baseline to the corrupt bytes.
        let manifest = ["a.jpg": trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")]
        let corruptReport = GuardianIntegrityReport(
            libraryRoot: "/lib",
            findings: [
                GuardianIntegrityFinding(
                    relativePath: "a.jpg", status: .corrupt, trustState: .changedPendingReview,
                    expectedIdentity: FileIdentity(size: 10, digest: "good"),
                    observedIdentity: FileIdentity(size: 10, digest: "rotten"), observedModificationTime: 100
                ),
            ]
        )
        let corruptUpserts = updater.scanUpserts(report: corruptReport, manifest: manifest, now: now)
        XCTAssertEqual(corruptUpserts.first?.trustState, .changedPendingReview)
        XCTAssertEqual(corruptUpserts.first?.digest, "good", "baseline must keep the known-good digest, not the corrupt bytes")
    }

    func testVerifiedRefreshesLastVerifiedOnly() {
        let updater = GuardianManifestUpdater()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let manifest = ["a.jpg": trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")]
        let report = GuardianIntegrityReport(
            libraryRoot: "/lib",
            findings: [
                GuardianIntegrityFinding(
                    relativePath: "a.jpg", status: .verified, trustState: .trusted,
                    expectedIdentity: FileIdentity(size: 10, digest: "good"),
                    observedIdentity: FileIdentity(size: 10, digest: "good"), observedModificationTime: 100
                ),
            ]
        )
        let upserts = updater.scanUpserts(report: report, manifest: manifest, now: now)
        XCTAssertEqual(upserts.first?.trustState, .trusted)
        XCTAssertEqual(upserts.first?.lastVerifiedAt, now)
        XCTAssertEqual(upserts.first?.digest, "good")
    }

    func testAcceptPromotesUsingObservedDigest() {
        let updater = GuardianManifestUpdater()
        let report = GuardianIntegrityReport(
            libraryRoot: "/lib",
            findings: [
                GuardianIntegrityFinding(
                    relativePath: "a.jpg", status: .new, trustState: .unprotected,
                    observedIdentity: FileIdentity(size: 4, digest: "obs"), observedModificationTime: 40
                ),
            ]
        )
        let upserts = updater.accept(relativePaths: ["a.jpg"], report: report, manifest: [:])
        XCTAssertEqual(upserts.first?.trustState, .trusted)
        XCTAssertEqual(upserts.first?.provenance, .userAccepted)
        XCTAssertEqual(upserts.first?.digest, "obs")
    }

    func testSeedTrustedOnlyOnExactMatch() {
        let updater = GuardianManifestUpdater()
        let report = GuardianIntegrityReport(
            libraryRoot: "/lib",
            findings: [
                GuardianIntegrityFinding(
                    relativePath: "match.jpg", status: .new, trustState: .unprotected,
                    observedIdentity: FileIdentity(size: 4, digest: "x"), observedModificationTime: 40
                ),
                GuardianIntegrityFinding(
                    relativePath: "mismatch.jpg", status: .new, trustState: .unprotected,
                    observedIdentity: FileIdentity(size: 4, digest: "y"), observedModificationTime: 40
                ),
            ]
        )
        let provenance = [
            "match.jpg": FileIdentity(size: 4, digest: "x"),
            "mismatch.jpg": FileIdentity(size: 4, digest: "DIFFERENT"),
        ]
        let upserts = updater.seedTrusted(provenanceDigests: provenance, report: report, manifest: [:])
        XCTAssertEqual(upserts.map(\.relativePath), ["match.jpg"])
        XCTAssertEqual(upserts.first?.provenance, .verifiedTransfer)
    }

    func testAcknowledgeDeletionsOnlyRetiresMissing() {
        let updater = GuardianManifestUpdater()
        let manifest = [
            "gone.jpg": trustedEntry("gone.jpg", size: 5, mtime: 50, digest: "g"),
            "here.jpg": trustedEntry("here.jpg", size: 6, mtime: 60, digest: "h"),
        ]
        let report = GuardianIntegrityReport(
            libraryRoot: "/lib",
            findings: [
                GuardianIntegrityFinding(relativePath: "gone.jpg", status: .missing, trustState: .changedPendingReview),
                GuardianIntegrityFinding(relativePath: "here.jpg", status: .verified, trustState: .trusted),
            ]
        )
        let upserts = updater.acknowledgeDeletions(relativePaths: ["gone.jpg", "here.jpg"], report: report, manifest: manifest)
        XCTAssertEqual(upserts.map(\.relativePath), ["gone.jpg"])
        XCTAssertEqual(upserts.first?.trustState, .retired)
    }

    // MARK: - Manifest store

    func testManifestStoreRoundTrips() throws {
        let url = temporaryDirectoryURL.appendingPathComponent("guardian/manifest.db")
        let identity = GuardianLibraryIdentity(libraryUUID: "lib-uuid", volumeIdentifier: "vol-1")
        let store = try GuardianManifestStore(url: url, libraryIdentity: identity)
        defer { store.close() }

        let entry = trustedEntry("a.jpg", size: 10, mtime: 100, digest: "good")
        try store.upsert([entry])

        let keyed = try store.loadKeyed()
        XCTAssertEqual(keyed["a.jpg"]?.digest, "good")
        XCTAssertEqual(keyed["a.jpg"]?.trustState, .trusted)
        XCTAssertEqual(try store.libraryIdentity().libraryUUID, "lib-uuid")

        try store.delete(relativePaths: ["a.jpg"])
        XCTAssertTrue(try store.loadKeyed().isEmpty)
    }

    func testManifestStoreRejectsIncompatibleDigestAlgorithm() throws {
        let url = temporaryDirectoryURL.appendingPathComponent("guardian/manifest2.db")
        let identity = GuardianLibraryIdentity(libraryUUID: "lib-uuid")
        let store = try GuardianManifestStore(url: url, libraryIdentity: identity)
        try store.upsert([trustedEntry("a.jpg", size: 1, mtime: 1, digest: "d")])
        store.close()

        // Simulate a manifest written by a future build with a different digest
        // algorithm by rewriting the recorded algorithm to an unknown value.
        try overwriteMetaDigestAlgorithm(at: url, to: "sha256-experimental")

        XCTAssertThrowsError(try GuardianManifestStore(url: url, libraryIdentity: identity)) { error in
            guard case GuardianManifestStoreError.incompatibleManifest = error else {
                return XCTFail("expected incompatibleManifest, got \(error)")
            }
        }
    }

    // MARK: - Probe (I/O, read-only)

    func testProbeHashesFilesAndNeverWritesIntoLibrary() throws {
        let libraryURL = temporaryDirectoryURL.appendingPathComponent("library", isDirectory: true)
        try FileManager.default.createDirectory(
            at: libraryURL.appendingPathComponent("2024/04/30", isDirectory: true),
            withIntermediateDirectories: true
        )
        let fileURL = libraryURL.appendingPathComponent("2024/04/30/2024-04-30_001.jpg")
        try Data("hello".utf8).write(to: fileURL)

        let result = try GuardianLibraryProbe().probe(libraryRoot: libraryURL)
        XCTAssertEqual(result.observations.count, 1)
        let observation = try XCTUnwrap(result.observations.first)
        XCTAssertEqual(observation.relativePath, "2024/04/30/2024-04-30_001.jpg")
        XCTAssertEqual(observation.outcome, .hashed)
        XCTAssertNotNil(observation.digest)
        XCTAssertFalse(result.partialScan)

        // Read-only: probing must not create any Chronoframe artifacts in the library.
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".organize_logs").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: libraryURL.appendingPathComponent(".organize_cache.db").path))
    }

    // MARK: - Raw SQLite tamper helper

    private func overwriteMetaDigestAlgorithm(at url: URL, to value: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else {
            sqlite3_close(db)
            throw NSError(domain: "test", code: 1)
        }
        defer { sqlite3_close(db) }
        let sql = "UPDATE Meta SET value = '\(value)' WHERE key = 'digest_algorithm';"
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "test", code: 2)
        }
    }
}
