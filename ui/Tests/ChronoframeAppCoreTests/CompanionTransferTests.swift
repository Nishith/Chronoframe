import Foundation
import XCTest
@testable import ChronoframeCore

/// Runs the real plan, enqueue, TransferExecutor and RevertExecutor path with
/// companion files, to show a companion is an ordinary copy job.
final class CompanionTransferTests: CompanionFixtureTestCase {
    private struct Fixture {
        var owner: URL
        var companion: URL
        var plan: DryRunPlanningResult
        var ownerDestination: URL
        var companionDestination: URL
    }

    private final class Box<Value>: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Value] = []
        func append(_ value: Value) { lock.lock(); stored.append(value); lock.unlock() }
        var values: [Value] { lock.lock(); defer { lock.unlock() }; return stored }
    }

    private func makeFixture() throws -> Fixture {
        let owner = try write("owner photo bytes", to: sourceRoot, "IMG_20260419_120000.jpg")
        let companion = try write("<x:xmpmeta>edits</x:xmpmeta>", to: sourceRoot, "IMG_20260419_120000.xmp")
        let plan = try DryRunPlanner().plan(sourceRoot: sourceRoot, destinationRoot: destinationRoot)
        let ownerJob = try XCTUnwrap(plan.transfers.first { $0.sourcePath == owner.path })
        let companionJob = try XCTUnwrap(plan.transfers.first { $0.sourcePath == companion.path })
        XCTAssertEqual(plan.transfers.count, 2)
        return Fixture(
            owner: owner,
            companion: companion,
            plan: plan,
            ownerDestination: URL(fileURLWithPath: ownerJob.destinationPath),
            companionDestination: URL(fileURLWithPath: companionJob.destinationPath)
        )
    }

    private func loadAuditReceipt() throws -> RevertReceipt {
        let logs = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        let receiptURL = try XCTUnwrap(
            try FileManager.default.contentsOfDirectory(at: logs, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasPrefix("audit_receipt_") && $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
                .last
        )
        return try RevertExecutor().loadReceipt(at: receiptURL)
    }

    /// Regular, non-hidden files under `root`, keyed by relative path.
    private func snapshot(of root: URL) throws -> [String: Data] {
        var result: [String: Data] = [:]
        let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { continue }
            let relative = String(url.path.dropFirst(root.path.count))
            result[relative] = try Data(contentsOf: url)
        }
        return result
    }

    // AGENTS-INVARIANT: 9
    func testCompanionIsReceiptedBeforeCopy() throws {
        let fixture = try makeFixture()
        let observations = Box<Bool>()
        let logs = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        let companionPath = fixture.companion.path

        // At the moment the companion's bytes are copied, a PENDING audit
        // receipt must already exist on disk.
        @Sendable func pendingReceiptExists() -> Bool {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: logs.path)) ?? []
            return names.contains { name in
                guard name.hasPrefix("audit_receipt_"), name.hasSuffix(".json"),
                      let data = try? Data(contentsOf: logs.appendingPathComponent(name)),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    return false
                }
                return object["status"] as? String == "PENDING"
            }
        }
        let system = TransferFileCopyStrategy.system
        let strategy = TransferFileCopyStrategy(
            clone: { source, destination in
                if source == companionPath { observations.append(pendingReceiptExists()) }
                return system.clone(source, destination)
            },
            copyAll: { source, destination in
                if source == companionPath { observations.append(pendingReceiptExists()) }
                return system.copyAll(source, destination)
            },
            copyMetadata: system.copyMetadata
        )

        let result = try CompanionExecution.run(
            plan: fixture.plan,
            destinationRoot: destinationRoot,
            executor: TransferExecutor(fileCopyStrategy: strategy)
        )

        XCTAssertEqual(result.copiedCount, 2)
        XCTAssertFalse(observations.values.isEmpty)
        XCTAssertTrue(observations.values.allSatisfy { $0 })

        // And the finished receipt lists the companion like any other file.
        let receipt = try loadAuditReceipt()
        let companionJob = try XCTUnwrap(fixture.plan.transfers.first { $0.sourcePath == companionPath })
        let entry = try XCTUnwrap(receipt.transfers.first { $0.source == companionPath })
        XCTAssertEqual(entry.dest, fixture.companionDestination.path)
        XCTAssertEqual(entry.hash, companionJob.identity.rawValue)
        XCTAssertEqual(try String(contentsOf: fixture.companionDestination, encoding: .utf8), "<x:xmpmeta>edits</x:xmpmeta>")
    }

    // AGENTS-INVARIANT: 8
    func testRevertRemovesCompanionWithOwnerAndChecksHash() throws {
        let fixture = try makeFixture()
        try CompanionExecution.run(plan: fixture.plan, destinationRoot: destinationRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.companionDestination.path))

        let receipt = try loadAuditReceipt()
        XCTAssertEqual(
            Set(receipt.transfers.map(\.dest)),
            [fixture.ownerDestination.path, fixture.companionDestination.path]
        )
        XCTAssertTrue(receipt.transfers.allSatisfy { !$0.hash.isEmpty })

        let result = RevertExecutor().revert(receipt: receipt, destinationBoundary: destinationRoot)

        XCTAssertEqual(
            Set(result.revertedPaths.map { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path }),
            Set([fixture.ownerDestination, fixture.companionDestination].map { $0.resolvingSymlinksInPath().path })
        )
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.ownerDestination.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.companionDestination.path))
    }

    // AGENTS-INVARIANT: 8
    func testRevertLeavesModifiedCompanion() throws {
        let fixture = try makeFixture()
        try CompanionExecution.run(plan: fixture.plan, destinationRoot: destinationRoot)
        try Data("the user kept editing this sidecar".utf8).write(to: fixture.companionDestination)

        let result = RevertExecutor().revert(
            receipt: try loadAuditReceipt(),
            destinationBoundary: destinationRoot
        )

        XCTAssertEqual(result.revertedCount, 1)
        XCTAssertEqual(result.skippedCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.ownerDestination.path))
        XCTAssertEqual(
            try String(contentsOf: fixture.companionDestination, encoding: .utf8),
            "the user kept editing this sidecar"
        )
    }

    func testOrganizeThenRevertRestoresDestinationByteForByte() throws {
        try write("an earlier photo", to: destinationRoot, "2026/04/18/2026-04-18_001.jpg")
        try write("<earlier/>", to: destinationRoot, "2026/04/18/2026-04-18_001.xmp")
        let before = try snapshot(of: destinationRoot)
        let fixture = try makeFixture()

        let run = try CompanionExecution.run(plan: fixture.plan, destinationRoot: destinationRoot)
        XCTAssertEqual(run.copiedCount, 2)
        XCTAssertEqual(try snapshot(of: destinationRoot).count, before.count + 2)

        let result = RevertExecutor().revert(receipt: try loadAuditReceipt(), destinationBoundary: destinationRoot)

        XCTAssertEqual(result.revertedCount, 2)
        XCTAssertEqual(result.skippedCount, 0)
        XCTAssertEqual(try snapshot(of: destinationRoot), before)
    }

    // AGENTS-INVARIANT: 1
    func testSourceFilesAreUntouched() throws {
        let fixture = try makeFixture()
        let sourceBefore = try snapshot(of: sourceRoot)
        let modificationDates = try [fixture.owner, fixture.companion].map {
            try XCTUnwrap(FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date)
        }

        try CompanionExecution.run(plan: fixture.plan, destinationRoot: destinationRoot)
        _ = RevertExecutor().revert(receipt: try loadAuditReceipt(), destinationBoundary: destinationRoot)

        XCTAssertEqual(try snapshot(of: sourceRoot), sourceBefore)
        XCTAssertEqual(
            try [fixture.owner, fixture.companion].map {
                try XCTUnwrap(FileManager.default.attributesOfItem(atPath: $0.path)[.modificationDate] as? Date)
            },
            modificationDates
        )
        // Nothing is written beside the sources, hidden files included.
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: sourceRoot.path).sorted(),
            ["IMG_20260419_120000.jpg", "IMG_20260419_120000.xmp"]
        )
    }
}
