import Foundation
import XCTest
@testable import ChronoframeCore

final class ChronoframeCoreGuardianRestoreExecutorTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("GuardianRestoreExecutorTests-\(UUID().uuidString)", isDirectory: true)
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
        restorable: [GuardianRestoreAction]
    ) -> GuardianRestorePlan {
        GuardianRestorePlan(
            libraryRoot: library.path,
            mirrorRoot: mirror.path,
            restorable: restorable,
            blocked: []
        )
    }

    private func locate(prefix: String, ext: String, under root: URL) throws -> URL {
        let contents = try FileManager.default.contentsOfDirectory(atPath: root.path)
        for name in contents where name.hasPrefix(prefix) && name.hasSuffix(ext) {
            return root.appendingPathComponent(name)
        }
        throw XCTSkip("no \(prefix)*\(ext) found under \(root.path)")
    }

    private func locateFile(named name: String, under root: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let candidate = enumerator?.nextObject() as? URL {
            if candidate.lastPathComponent == name { return candidate }
        }
        return nil
    }

    // AGENTS-INVARIANT: 25
    func testRestoresCorruptPrimaryFromVerifiedMirrorAndQuarantinesTheOriginal() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "2024/04/30/a.jpg"

        // The primary is rotten; the mirror still holds the good, trusted bytes.
        try write("rotten-bytes", to: library.appendingPathComponent(relative))
        try write("good-bytes", to: mirror.appendingPathComponent(relative))
        let trusted = try FileIdentityHasher().hashIdentity(at: mirror.appendingPathComponent(relative))
        let currentPrimary = try FileIdentityHasher().hashIdentity(at: library.appendingPathComponent(relative))

        let result = try GuardianRestoreExecutor().execute(
            plan: plan(library: library, mirror: mirror, restorable: [
                GuardianRestoreAction(
                    relativePath: relative,
                    trustedIdentity: trusted,
                    reason: .primaryCorrupt,
                    expectedCurrentPrimaryIdentity: currentPrimary
                ),
            ]),
            selectedPaths: [relative],
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertEqual(result.restored, [relative])
        XCTAssertTrue(result.blockedAtCommit.isEmpty)

        // The primary now holds the trusted mirror bytes.
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(relative)), Data("good-bytes".utf8))

        // The corrupt original was preserved in a same-directory quarantine, never erased.
        let quarantineRoot = library.appendingPathComponent(GuardianRestoreExecutor.quarantineDirectoryName)
        let quarantined = try XCTUnwrap(locateFile(named: "a.jpg", under: quarantineRoot))
        XCTAssertEqual(try Data(contentsOf: quarantined), Data("rotten-bytes".utf8))

        // The receipt lives in the state directory (Application Support), not the library.
        let receiptURL = try XCTUnwrap(result.receiptURL)
        XCTAssertTrue(receiptURL.path.hasPrefix(state.path))
    }

    func testRestoresMissingPrimaryFromVerifiedMirror() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "gone.jpg"

        try write("recovered", to: mirror.appendingPathComponent(relative))
        let trusted = try FileIdentityHasher().hashIdentity(at: mirror.appendingPathComponent(relative))

        let result = try GuardianRestoreExecutor().execute(
            plan: plan(library: library, mirror: mirror, restorable: [
                GuardianRestoreAction(relativePath: relative, trustedIdentity: trusted, reason: .primaryMissing),
            ]),
            selectedPaths: [relative],
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertEqual(result.restored, [relative])
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(relative)), Data("recovered".utf8))
    }

    func testRefusesWhenMirrorNoLongerMatchesTrustedDigestAtCommit() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "a.jpg"

        try write("rotten", to: library.appendingPathComponent(relative))
        try write("mirror-also-changed", to: mirror.appendingPathComponent(relative))
        // The trusted identity the plan carries no longer matches the mirror bytes on disk.
        let trusted = FileIdentity(size: 4, digest: "trusted-but-gone")
        let currentPrimary = try FileIdentityHasher().hashIdentity(at: library.appendingPathComponent(relative))

        let result = try GuardianRestoreExecutor().execute(
            plan: plan(library: library, mirror: mirror, restorable: [
                GuardianRestoreAction(
                    relativePath: relative,
                    trustedIdentity: trusted,
                    reason: .primaryCorrupt,
                    expectedCurrentPrimaryIdentity: currentPrimary
                ),
            ]),
            selectedPaths: [relative],
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertEqual(result.blockedAtCommit.first?.reason, .mirrorChangedSincePlanning)
        // The rotten primary is left exactly as it was — never overwritten from an unverified mirror.
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(relative)), Data("rotten".utf8))
    }

    func testRefusesToOverwriteAPrimaryThatReappearedAfterAMissingPlan() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "gone.jpg"

        try write("mirror-copy", to: mirror.appendingPathComponent(relative))
        let trusted = try FileIdentityHasher().hashIdentity(at: mirror.appendingPathComponent(relative))
        // The primary was planned as missing but has reappeared on disk since planning.
        try write("reappeared", to: library.appendingPathComponent(relative))

        let result = try GuardianRestoreExecutor().execute(
            plan: plan(library: library, mirror: mirror, restorable: [
                GuardianRestoreAction(relativePath: relative, trustedIdentity: trusted, reason: .primaryMissing),
            ]),
            selectedPaths: [relative],
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertEqual(result.blockedAtCommit.first?.reason, .primaryReappeared)
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(relative)), Data("reappeared".utf8))
    }

    func testRefusesWhenCorruptPrimaryChangedAgainSincePlanning() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "a.jpg"

        try write("good-bytes", to: mirror.appendingPathComponent(relative))
        let trusted = try FileIdentityHasher().hashIdentity(at: mirror.appendingPathComponent(relative))
        // Plan expected one corrupt identity, but the primary has changed to something else.
        try write("now-different", to: library.appendingPathComponent(relative))
        let stalePrimary = FileIdentity(size: 3, digest: "what-we-planned-for")

        let result = try GuardianRestoreExecutor().execute(
            plan: plan(library: library, mirror: mirror, restorable: [
                GuardianRestoreAction(
                    relativePath: relative,
                    trustedIdentity: trusted,
                    reason: .primaryCorrupt,
                    expectedCurrentPrimaryIdentity: stalePrimary
                ),
            ]),
            selectedPaths: [relative],
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertTrue(result.restored.isEmpty)
        XCTAssertEqual(result.blockedAtCommit.first?.reason, .primaryChangedSincePlanning)
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(relative)), Data("now-different".utf8))
    }

    func testOnlySelectedPathsAreRestored() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")

        try write("rot-a", to: library.appendingPathComponent("a.jpg"))
        try write("good-a", to: mirror.appendingPathComponent("a.jpg"))
        try write("rot-b", to: library.appendingPathComponent("b.jpg"))
        try write("good-b", to: mirror.appendingPathComponent("b.jpg"))
        let hasher = FileIdentityHasher()

        let result = try GuardianRestoreExecutor().execute(
            plan: plan(library: library, mirror: mirror, restorable: [
                GuardianRestoreAction(
                    relativePath: "a.jpg",
                    trustedIdentity: try hasher.hashIdentity(at: mirror.appendingPathComponent("a.jpg")),
                    reason: .primaryCorrupt,
                    expectedCurrentPrimaryIdentity: try hasher.hashIdentity(at: library.appendingPathComponent("a.jpg"))
                ),
                GuardianRestoreAction(
                    relativePath: "b.jpg",
                    trustedIdentity: try hasher.hashIdentity(at: mirror.appendingPathComponent("b.jpg")),
                    reason: .primaryCorrupt,
                    expectedCurrentPrimaryIdentity: try hasher.hashIdentity(at: library.appendingPathComponent("b.jpg"))
                ),
            ]),
            selectedPaths: ["a.jpg"],
            libraryRoot: library,
            mirrorRoot: mirror,
            stateDirectory: state
        )

        XCTAssertEqual(result.restored, ["a.jpg"])
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent("a.jpg")), Data("good-a".utf8))
        // The unselected file is untouched.
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent("b.jpg")), Data("rot-b".utf8))
    }

    func testRecoveryRollsBackAnOriginalQuarantinedBeforeInstall() throws {
        let library = try dir("library")
        let mirror = try dir("mirror")
        let state = try dir("state")
        let relative = "2024/04/30/a.jpg"

        try write("rotten-bytes", to: library.appendingPathComponent(relative))
        try write("good-bytes", to: mirror.appendingPathComponent(relative))
        let hasher = FileIdentityHasher()
        let trusted = try hasher.hashIdentity(at: mirror.appendingPathComponent(relative))
        let currentPrimary = try hasher.hashIdentity(at: library.appendingPathComponent(relative))

        let executor = GuardianRestoreExecutor()
        let action = GuardianRestoreAction(
            relativePath: relative,
            trustedIdentity: trusted,
            reason: .primaryCorrupt,
            expectedCurrentPrimaryIdentity: currentPrimary
        )

        // Simulate a crash immediately after the original is quarantined but before
        // the replacement is installed.
        struct SimulatedCrash: Error {}
        XCTAssertThrowsError(
            try executor.execute(
                plan: plan(library: library, mirror: mirror, restorable: [action]),
                selectedPaths: [relative],
                libraryRoot: library,
                mirrorRoot: mirror,
                stateDirectory: state,
                afterState: { restoreState, _ in
                    if restoreState == .originalQuarantined { throw SimulatedCrash() }
                }
            )
        )

        // Mid-crash the library is left without the primary (moved to quarantine).
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.appendingPathComponent(relative).path))

        // Recovery rolls the quarantined original back into place so the library is
        // never left missing after an interrupted restore.
        let journalURL = try locate(prefix: "guardian_restore_journal_", ext: ".jsonl", under: state)
        let rolledBack = try executor.recover(journalURL: journalURL, libraryRoot: library)
        XCTAssertEqual(rolledBack, [relative])
        XCTAssertEqual(try Data(contentsOf: library.appendingPathComponent(relative)), Data("rotten-bytes".utf8))
    }
}
