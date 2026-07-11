import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreGuardianModelsTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChronoframeCoreGuardianModelsTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    // MARK: - Versioning

    func testManifestVersioningRecordsAlgorithmAndNormalization() {
        XCTAssertEqual(GuardianManifestVersion.digestAlgorithm, "blake2b")
        XCTAssertEqual(GuardianManifestVersion.pathNormalization, "nfc")
        XCTAssertGreaterThanOrEqual(GuardianManifestVersion.schema, 1)
        XCTAssertGreaterThanOrEqual(GuardianManifestVersion.digestFormatVersion, 1)
    }

    // MARK: - Trust model invariants

    func testTrustStatesAreExhaustiveAndDistinct() {
        XCTAssertEqual(
            Set(GuardianTrustState.allCases.map(\.rawValue)),
            ["unprotected", "trusted", "changedPendingReview", "retired"]
        )
    }

    func testManifestEntryExposesContentIdentity() {
        let entry = GuardianManifestEntry(
            relativePath: "2024/04/30/2024-04-30_001.jpg",
            size: 42,
            modificationTime: 1_700_000_000,
            digest: "deadbeef",
            trustState: .trusted,
            provenance: .verifiedTransfer,
            firstObservedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        XCTAssertEqual(entry.identity, FileIdentity(size: 42, digest: "deadbeef"))
    }

    // MARK: - Path normalization

    func testCanonicalKeyNormalizesToNFC() {
        // "é" as base "e" + combining acute (NFD) vs. the precomposed form (NFC).
        let decomposed = "cafe\u{0301}/photo.jpg"
        let composed = "caf\u{00E9}/photo.jpg"
        // Swift's String equality already folds canonical equivalence, so compare
        // the raw scalar sequences to prove the two inputs are encoded differently.
        XCTAssertNotEqual(Array(decomposed.unicodeScalars), Array(composed.unicodeScalars))
        // canonicalKey must fold the NFD input to the same scalars as the NFC form.
        let key = GuardianPathNormalization.canonicalKey(decomposed)
        XCTAssertEqual(Array(key.unicodeScalars), Array(composed.unicodeScalars))
    }

    func testRelativeKeyDerivesPathUnderRoot() {
        let root = URL(fileURLWithPath: "/Library/Photos", isDirectory: true)
        let file = URL(fileURLWithPath: "/Library/Photos/2024/04/30/img.jpg")
        XCTAssertEqual(
            GuardianPathNormalization.relativeKey(of: file, underRoot: root),
            "2024/04/30/img.jpg"
        )
    }

    func testRelativeKeyRejectsPathOutsideRoot() {
        let root = URL(fileURLWithPath: "/Library/Photos", isDirectory: true)
        let outside = URL(fileURLWithPath: "/Library/PhotosBackup/img.jpg")
        XCTAssertNil(GuardianPathNormalization.relativeKey(of: outside, underRoot: root))
    }

    // MARK: - Report aggregation

    func testReportCountsAndCorruptionFlag() {
        let report = GuardianIntegrityReport(
            libraryRoot: "/Library/Photos",
            findings: [
                GuardianIntegrityFinding(relativePath: "a", status: .verified, trustState: .trusted),
                GuardianIntegrityFinding(relativePath: "b", status: .corrupt, trustState: .changedPendingReview),
                GuardianIntegrityFinding(relativePath: "c", status: .missing, trustState: .changedPendingReview),
            ]
        )
        XCTAssertEqual(report.count(of: .verified), 1)
        XCTAssertEqual(report.count(of: .corrupt), 1)
        XCTAssertTrue(report.hasCorruption)
    }

    // MARK: - Multi-root lock ordering & overlap

    func testCanonicalOrderingIsDeterministicRegardlessOfInputOrder() throws {
        let a = GuardianLockRoot.inRoot(URL(fileURLWithPath: "/Volumes/Alpha"), surface: "app", operation: "mirror")
        let b = GuardianLockRoot.inRoot(URL(fileURLWithPath: "/Volumes/Beta"), surface: "app", operation: "mirror")
        let forward = try GuardianMultiRootLock.canonicallyOrdered([a, b]).map { $0.url.path }
        let reverse = try GuardianMultiRootLock.canonicallyOrdered([b, a]).map { $0.url.path }
        XCTAssertEqual(forward, reverse)
        XCTAssertEqual(forward, ["/Volumes/Alpha", "/Volumes/Beta"])
    }

    func testOverlappingRootsAreRejected() {
        let parent = GuardianLockRoot.inRoot(URL(fileURLWithPath: "/Volumes/Alpha/Library"), surface: "app", operation: "restore")
        let child = GuardianLockRoot.inRoot(URL(fileURLWithPath: "/Volumes/Alpha/Library/Mirror"), surface: "app", operation: "restore")
        XCTAssertThrowsError(try GuardianMultiRootLock.canonicallyOrdered([parent, child])) { error in
            guard case GuardianMultiRootLockError.overlappingRoots = error else {
                return XCTFail("expected overlappingRoots, got \(error)")
            }
        }
    }

    func testSiblingPrefixPathsDoNotCountAsOverlap() {
        XCTAssertFalse(GuardianMultiRootLock.pathsOverlap("/a/b", "/a/bc"))
        XCTAssertTrue(GuardianMultiRootLock.pathsOverlap("/a/b", "/a/b/c"))
        XCTAssertTrue(GuardianMultiRootLock.pathsOverlap("/a/b", "/a/b"))
    }

    func testMultiRootLockAcquiresAllAndReleases() throws {
        let libraryURL = temporaryDirectoryURL.appendingPathComponent("library", isDirectory: true)
        let mirrorURL = temporaryDirectoryURL.appendingPathComponent("mirror", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorURL, withIntermediateDirectories: true)

        let lease = try GuardianMultiRootLock.acquire([
            GuardianLockRoot.inRoot(libraryURL, surface: "app", operation: "restore"),
            GuardianLockRoot.inRoot(mirrorURL, surface: "app", operation: "restore"),
        ])
        // A second acquisition of either root must fail while the lease is held.
        XCTAssertThrowsError(
            try DestinationOperationLock.acquire(destinationRoot: libraryURL, surface: "app", operation: "restore")
        )
        lease.release()
        // After release the root is free again.
        let reacquired = try DestinationOperationLock.acquire(destinationRoot: libraryURL, surface: "app", operation: "restore")
        reacquired.release()
    }

    func testLockFileCanLiveOutsideAReadOnlyRoot() throws {
        // A read-only library must not be written to just to take a lease: the lock
        // file lives in a separate coordination directory, and no .organize_logs
        // appears under the library root.
        let libraryURL = temporaryDirectoryURL.appendingPathComponent("ro-library", isDirectory: true)
        let coordinationDir = temporaryDirectoryURL.appendingPathComponent("appsupport-guardian", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        let lockFileURL = coordinationDir.appendingPathComponent("library-uuid.lock")
        let lease = try GuardianMultiRootLock.acquire([
            GuardianLockRoot(url: libraryURL, lockFileURL: lockFileURL, surface: "app", operation: "scrub"),
        ])
        defer { lease.release() }

        XCTAssertTrue(FileManager.default.fileExists(atPath: lockFileURL.path))
        XCTAssertFalse(
            FileManager.default.fileExists(
                atPath: libraryURL.appendingPathComponent(".organize_logs").path
            ),
            "acquiring a Guardian lease must not create .organize_logs in a read-only library"
        )
    }

    func testMultiRootLockReleasesAllWhenOneRootIsBusy() throws {
        let libraryURL = temporaryDirectoryURL.appendingPathComponent("library2", isDirectory: true)
        let mirrorURL = temporaryDirectoryURL.appendingPathComponent("mirror2", isDirectory: true)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: mirrorURL, withIntermediateDirectories: true)

        // Hold the mirror so multi-root acquisition must fail partway.
        let blocker = try DestinationOperationLock.acquire(destinationRoot: mirrorURL, surface: "other", operation: "mirror")
        defer { blocker.release() }

        XCTAssertThrowsError(
            try GuardianMultiRootLock.acquire([
                GuardianLockRoot.inRoot(libraryURL, surface: "app", operation: "restore"),
                GuardianLockRoot.inRoot(mirrorURL, surface: "app", operation: "restore"),
            ])
        )
        // The library lease must have been released on the partial failure, so it is
        // immediately acquirable again.
        let libraryLease = try DestinationOperationLock.acquire(destinationRoot: libraryURL, surface: "app", operation: "restore")
        libraryLease.release()
    }
}
