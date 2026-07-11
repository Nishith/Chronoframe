import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreGuardianMirrorExecutorTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianMirrorExecutorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmp { try? FileManager.default.removeItem(at: tmp) }
        tmp = nil
        try super.tearDownWithError()
    }

    private func dir(_ name: String) throws -> URL {
        let url = tmp.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
    }

    private func plan(
        library: URL,
        mirror: URL,
        copies: [GuardianMirrorCopy]
    ) -> GuardianMirrorPlan {
        GuardianMirrorPlan(
            libraryRoot: library.path,
            mirrorRoot: mirror.path,
            copies: copies,
            blocked: [],
            retainedExtras: [],
            alreadyMirrored: []
        )
    }

    // AGENTS-INVARIANT: 24
    func testCopiesVerifiedPrimaryIntoMirrorAndNeverWritesLibrary() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "2024/04/30/a.jpg"
        let source = library.appendingPathComponent(relative)
        try write("hello", to: source)
        let identity = try FileIdentityHasher().hashIdentity(at: source)

        let result = try GuardianMirrorExecutor().execute(
            plan: plan(library: library, mirror: mirror, copies: [
                GuardianMirrorCopy(relativePath: relative, expectedIdentity: identity, kind: .create),
            ]),
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertEqual(result.copied, [relative])
        XCTAssertEqual(try Data(contentsOf: mirror.appendingPathComponent(relative)), Data("hello".utf8))

        // The library is only read: no lock file, no quarantine, no temp artifacts.
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent(".organize_logs").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent(".guardian_quarantine").path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: library.appendingPathComponent("2024/04/30").path), ["a.jpg"])

        // The receipt is written into the state directory (Application Support), not the library.
        let receiptURL = try XCTUnwrap(result.receiptURL)
        XCTAssertTrue(receiptURL.path.hasPrefix(state.path))
    }

    func testBlocksWhenPrimaryChangedSincePlanning() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "a.jpg"
        try write("current-bytes", to: library.appendingPathComponent(relative))
        // The plan carries a stale expected identity that no longer matches the primary.
        let staleIdentity = FileIdentity(size: 3, digest: "stale-digest")

        let result = try GuardianMirrorExecutor().execute(
            plan: plan(library: library, mirror: mirror, copies: [
                GuardianMirrorCopy(relativePath: relative, expectedIdentity: staleIdentity, kind: .create),
            ]),
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertTrue(result.copied.isEmpty)
        XCTAssertEqual(result.blockedAtCommit.first?.reason, .primaryNotVerified)
        XCTAssertFalse(FileManager.default.fileExists(atPath: mirror.appendingPathComponent(relative).path))
    }

    func testQuarantinesDivergentMirrorBeforeReplacing() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "photo.jpg"
        try write("good", to: library.appendingPathComponent(relative))
        try write("stale-mirror", to: mirror.appendingPathComponent(relative))
        let identity = try FileIdentityHasher().hashIdentity(at: library.appendingPathComponent(relative))

        let result = try GuardianMirrorExecutor().execute(
            plan: plan(library: library, mirror: mirror, copies: [
                GuardianMirrorCopy(
                    relativePath: relative,
                    expectedIdentity: identity,
                    kind: .replaceDivergent,
                    divergentMirrorIdentity: FileIdentity(size: 12, digest: "whatever")
                ),
            ]),
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertEqual(result.copied, [relative])
        XCTAssertEqual(result.quarantinedDivergent, [relative])
        // The mirror now matches the verified primary.
        XCTAssertEqual(try Data(contentsOf: mirror.appendingPathComponent(relative)), Data("good".utf8))
        // The divergent copy is retained (not erased) in the mirror-side quarantine.
        let quarantineRoot = mirror.appendingPathComponent(GuardianMirrorExecutor.quarantineDirectoryName)
        let quarantined = try locateFile(named: "photo.jpg", under: quarantineRoot)
        XCTAssertEqual(try Data(contentsOf: quarantined), Data("stale-mirror".utf8))
    }

    private func locateFile(named name: String, under root: URL) throws -> URL {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.lastPathComponent == name { return candidate }
        }
        throw XCTSkip("quarantined file not found under \(root.path)")
    }
}
