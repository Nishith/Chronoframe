import Foundation
import XCTest
@testable import ChronoframeCore

/// Shared temp-directory helpers for the companion test files.
class CompanionFixtureTestCase: XCTestCase {
    var temporaryDirectoryURL: URL!
    var sourceRoot: URL!
    var destinationRoot: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(type(of: self))-\(UUID().uuidString)", isDirectory: true)
        // Discovery reports resolved paths (/private/var/...), so compare against those.
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        temporaryDirectoryURL = URL(fileURLWithPath: realpath(temporaryDirectoryURL.path, nil).map { String(cString: $0) } ?? temporaryDirectoryURL.path, isDirectory: true)
        sourceRoot = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        destinationRoot = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        sourceRoot = nil
        destinationRoot = nil
        try super.tearDownWithError()
    }

    @discardableResult
    func write(_ contents: String, to root: URL, _ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url)
        let timestamp = Date(timeIntervalSince1970: 1_700_000_000)
        try FileManager.default.setAttributes(
            [.modificationDate: timestamp, .creationDate: timestamp],
            ofItemAtPath: url.path
        )
        return url
    }

    func name(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }
}

final class CompanionPlanningTests: CompanionFixtureTestCase {
    func testCompanionDestinationFollowsOwnerCollisionSuffix() async throws {
        // `_001` is taken by a different photo, so the owner plans as `_002`
        // and every companion form must follow it.
        try write("someone else", to: destinationRoot, "2026/04/19/2026-04-19_001.jpg")
        let owner = try write("owner bytes", to: sourceRoot, "IMG_20260419_120000.jpg")
        let replaced = try write("xmp replaced", to: sourceRoot, "IMG_20260419_120000.xmp")
        let other = try write("other bytes", to: sourceRoot, "IMG_20260419_130000.jpg")
        let appended = try write("xmp appended", to: sourceRoot, "IMG_20260419_130000.jpg.XMP")

        let result = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)

        let byName = Dictionary(uniqueKeysWithValues: result.transfers.map { (name($0.sourcePath), $0) })
        XCTAssertEqual(name(try XCTUnwrap(byName[owner.lastPathComponent]).destinationPath), "2026-04-19_002.jpg")
        XCTAssertEqual(name(try XCTUnwrap(byName[replaced.lastPathComponent]).destinationPath), "2026-04-19_002.xmp")
        XCTAssertEqual(name(try XCTUnwrap(byName[other.lastPathComponent]).destinationPath), "2026-04-19_003.jpg")
        XCTAssertEqual(name(try XCTUnwrap(byName[appended.lastPathComponent]).destinationPath), "2026-04-19_003.jpg.XMP")
        XCTAssertEqual(
            URL(fileURLWithPath: try XCTUnwrap(byName[replaced.lastPathComponent]).destinationPath).deletingLastPathComponent(),
            URL(fileURLWithPath: try XCTUnwrap(byName[owner.lastPathComponent]).destinationPath).deletingLastPathComponent()
        )
        XCTAssertEqual(result.companionOwners, [replaced.path: owner.path, appended.path: other.path])
        XCTAssertEqual(result.copyPlan.unresolvedCompanions, [])
        XCTAssertEqual(Set(result.transfers.map(\.sourcePath)).count, result.transfers.count)

        // The sync entry point plans the same companions.
        let synchronous = try DryRunPlanner().plan(
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot,
            databaseURL: temporaryDirectoryURL.appendingPathComponent("parity.db")
        )
        XCTAssertEqual(synchronous.transfers, result.transfers)
        XCTAssertEqual(synchronous.companionOwners, result.companionOwners)
        XCTAssertEqual(synchronous.copyPlan.unresolvedCompanions, result.copyPlan.unresolvedCompanions)
    }

    func testCompanionDestinationFollowsOwnerDuplicateDirectory() async throws {
        let first = try write("same bytes", to: sourceRoot, "IMG_20260419_120000.jpg")
        let second = try write("same bytes", to: sourceRoot, "IMG_20260419_130000.jpg")
        let firstXMP = try write("sidecar bytes", to: sourceRoot, "IMG_20260419_120000.xmp")
        let secondXMP = try write("sidecar bytes", to: sourceRoot, "IMG_20260419_130000.xmp")

        let result = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)

        let byPath = Dictionary(uniqueKeysWithValues: result.transfers.map { ($0.sourcePath, $0) })
        let firstJob = try XCTUnwrap(byPath[first.path])
        let secondJob = try XCTUnwrap(byPath[second.path])
        XCTAssertFalse(firstJob.isDuplicate)
        XCTAssertTrue(secondJob.isDuplicate)
        XCTAssertTrue(secondJob.destinationPath.contains("/Duplicate/"))

        let firstCompanion = try XCTUnwrap(byPath[firstXMP.path])
        let secondCompanion = try XCTUnwrap(byPath[secondXMP.path])
        XCTAssertEqual(firstCompanion.destinationPath, (firstJob.destinationPath as NSString).deletingPathExtension + ".xmp")
        XCTAssertEqual(secondCompanion.destinationPath, (secondJob.destinationPath as NSString).deletingPathExtension + ".xmp")
        XCTAssertTrue(secondCompanion.isDuplicate)
        XCTAssertFalse(firstCompanion.isDuplicate)
        XCTAssertEqual(secondCompanion.dateBucket, secondJob.dateBucket)
        // Two byte-identical sidecars are both copied; they are not photo duplicates.
        XCTAssertEqual(firstCompanion.identity, secondCompanion.identity)
        XCTAssertEqual(result.counts.duplicateCount, 1)
        XCTAssertEqual(result.counts.newCount, 1)
    }

    func testCompanionSkippedWhenOwnerSkipped() async throws {
        // The photo is already in the destination, so it is not copied again;
        // its companion is skipped with it, quietly.
        try write("already here", to: destinationRoot, "2026/04/19/2026-04-19_001.jpg")
        try write("already here", to: sourceRoot, "IMG_20260419_120000.jpg")
        let skippedCompanion = try write("sidecar", to: sourceRoot, "IMG_20260419_120000.xmp")
        // Positive control: a second owner that is not skipped still plans with its companion.
        let control = try write("a new photo", to: sourceRoot, "IMG_20260420_120000.jpg")
        let controlCompanion = try write("control sidecar", to: sourceRoot, "IMG_20260420_120000.xmp")

        let result = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)

        XCTAssertEqual(result.counts.alreadyInDestinationCount, 1)
        XCTAssertEqual(Set(result.transfers.map(\.sourcePath)), [control.path, controlCompanion.path])
        XCTAssertFalse(result.transfers.contains { $0.sourcePath == skippedCompanion.path })
        XCTAssertEqual(result.copyPlan.unresolvedCompanions, [])
        XCTAssertEqual(result.companionOwners, [controlCompanion.path: control.path])
    }

    // AGENTS-INVARIANT: 4
    func testExistingCompanionDestinationIsNeverOverwritten() async throws {
        let existing = try write("the user's own sidecar", to: destinationRoot, "2026/04/19/2026-04-19_001.xmp")
        let owner = try write("owner bytes", to: sourceRoot, "IMG_20260419_120000.jpg")
        let companion = try write("incoming sidecar", to: sourceRoot, "IMG_20260419_120000.xmp")

        let result = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)

        XCTAssertEqual(result.transfers.map(\.sourcePath), [owner.path])
        XCTAssertEqual(result.copyPlan.unresolvedCompanions, [UnresolvedCompanion(sourcePath: companion.path, reason: .nameTaken)])
        XCTAssertEqual(result.companionOwners, [:])

        // Even running the plan leaves the existing file's bytes alone.
        try CompanionExecution.run(plan: result, destinationRoot: destinationRoot)
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "the user's own sidecar")
    }

    func testMediaCountsAndOtherScannersIgnoreCompanions() async throws {
        try write("photo", to: sourceRoot, "IMG_20260419_120000.jpg")
        try write("sidecar", to: sourceRoot, "IMG_20260419_120000.xmp")
        try write("edit instructions", to: sourceRoot, "IMG_E7777.AAE")   // orphan

        let result = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)

        XCTAssertEqual(result.discoveredSourceCount, 1)
        XCTAssertEqual(result.sourceHashedCount, 1)
        XCTAssertEqual(result.counts, CopyPlanCounts(alreadyInDestinationCount: 0, newCount: 1, duplicateCount: 0, hashErrorCount: 0))
        XCTAssertEqual(result.warningMessages, [])
        XCTAssertEqual(result.dateHistogram.map(\.plannedCount).reduce(0, +), 1)
        XCTAssertEqual(result.previewReviewItems.count, 1)
        XCTAssertEqual(result.transfers.count, 2)
        XCTAssertEqual(result.copyPlan.unresolvedCompanions.map(\.reason), [.noOwner])

        // Media-only discovery (destination indexing, Guardian, Watched Sources) is unchanged.
        XCTAssertEqual(try MediaDiscovery.discoverMediaFiles(at: sourceRoot).count, 1)

        // Deduplicate scanner: two byte-identical .aae files are not duplicates.
        let library = temporaryDirectoryURL.appendingPathComponent("library", isDirectory: true)
        try write("jpeg", to: library, "2026/04/19/2026-04-19_001.jpg")
        try write("identical aae", to: library, "2026/04/19/2026-04-19_001.aae")
        try write("identical aae", to: library, "2026/04/19/2026-04-19_002.aae")
        try write("identical xmp", to: library, "2026/04/19/2026-04-19_001.xmp")
        try write("identical xmp", to: library, "2026/04/19/2026-04-19_002.xmp")
        let configuration = DeduplicateConfiguration(
            destinationPath: library.path,
            timeWindowSeconds: 30,
            similarityThreshold: 1.0,
            dhashHammingThreshold: 5,
            treatRawJpegPairsAsUnit: true,
            treatLivePhotoPairsAsUnit: true
        )
        var summary: DeduplicateSummary?
        for try await event in DeduplicateScanner().scan(configuration: configuration) {
            if case let .complete(finalSummary) = event {
                summary = finalSummary
            }
        }
        let scanned = try XCTUnwrap(summary)
        XCTAssertEqual(scanned.totalCandidatesScanned, 1)
        XCTAssertEqual(scanned.clusterCounts[.exactDuplicate] ?? 0, 0)

        // Guardian probe sees media only.
        let probed = try GuardianLibraryProbe().probe(libraryRoot: library)
        XCTAssertEqual(probed.observations.map(\.relativePath), ["2026/04/19/2026-04-19_001.jpg"])

        // Library Health: byte-identical .aae cache rows are not "Exact Copies".
        let database = try OrganizerDatabase(
            url: library.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
        )
        try database.saveRawCacheRecords(
            [
                RawFileCacheRecord(namespace: .destination, path: library.appendingPathComponent("2026/04/19/2026-04-19_001.aae").path, hash: "13_same", size: 13, modificationTime: 1),
                RawFileCacheRecord(namespace: .destination, path: library.appendingPathComponent("2026/04/19/2026-04-19_002.aae").path, hash: "13_same", size: 13, modificationTime: 1),
                RawFileCacheRecord(namespace: .destination, path: library.appendingPathComponent("2026/04/19/2026-04-19_001.jpg").path, hash: "4_jpeg", size: 4, modificationTime: 1),
            ]
        )
        database.close()
        let health = LibraryHealthScanner().scan(
            sourceRoot: sourceRoot.path,
            destinationRoot: library.path,
            folderStructure: .yyyyMMDD
        )
        XCTAssertEqual(health.cards.first { $0.title == "Exact Copies" }?.value, "0")
    }

    func testCompanionClashOnSameDestinationLeavesBothUnresolved() async throws {
        // D-EPR-14: IMG_1234.AAE and IMG_E1234.AAE both map to <owner stem>.AAE.
        let owner = try write("heic bytes", to: sourceRoot, "IMG_1234.HEIC")
        let original = try write("original edit", to: sourceRoot, "IMG_1234.AAE")
        let edited = try write("edited edit", to: sourceRoot, "IMG_E1234.AAE")

        let result = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)

        XCTAssertEqual(result.transfers.map(\.sourcePath), [owner.path])
        XCTAssertEqual(
            result.copyPlan.unresolvedCompanions,
            [
                UnresolvedCompanion(sourcePath: edited.path, reason: .nameTaken),
                UnresolvedCompanion(sourcePath: original.path, reason: .nameTaken),
            ].sorted { $0.sourcePath < $1.sourcePath }
        )
        XCTAssertEqual(result.companionOwners, [:])
    }

    func testManifestModeOnlyPlansDroppedCompanions() async throws {
        let photo = try write("dropped photo", to: sourceRoot, "IMG_20260419_120000.jpg")
        let droppedXMP = try write("dropped sidecar", to: sourceRoot, "IMG_20260419_120000.xmp")
        let lonePhoto = try write("lone photo", to: sourceRoot, "IMG_20260420_120000.jpg")
        try write("sibling never dropped", to: sourceRoot, "IMG_20260420_120000.xmp")

        func writeManifest(_ paths: [String]) throws {
            let manifest: [String: Any] = ["items": paths.map { ["path": $0, "isDirectory": false] }]
            try JSONSerialization.data(withJSONObject: manifest)
                .write(to: sourceRoot.appendingPathComponent(".chronoframe_drop_manifest.json"))
        }

        // Manifest paths are standardized (/private/var becomes /var), so compare by name.
        // A dropped photo and its dropped .xmp plan together.
        try writeManifest([photo.path, droppedXMP.path])
        let together = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)
        XCTAssertEqual(together.transfers.map { name($0.sourcePath) }.sorted(), [droppedXMP.lastPathComponent, photo.lastPathComponent].sorted())
        XCTAssertEqual(together.companionOwners.map { [name($0.key): name($0.value)] }, [[droppedXMP.lastPathComponent: photo.lastPathComponent]])

        // A dropped photo alone does not pick up a sibling .xmp it was not dropped with.
        try writeManifest([lonePhoto.path])
        let alone = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)
        XCTAssertEqual(alone.transfers.map { name($0.sourcePath) }, [lonePhoto.lastPathComponent])
        XCTAssertEqual(alone.copyPlan.unresolvedCompanions, [])
        XCTAssertEqual(alone.companionOwners, [:])
    }

    func testCompanionIdentityMatchesItsOwnBytesWithManyWorkers() async throws {
        var companions: [URL] = []
        for index in 0..<6 {
            try write("photo \(index)", to: sourceRoot, "IMG_2026041\(index)_120000.jpg")
            companions.append(try write(
                String(repeating: "sidecar-\(index)-", count: 40 + index * 17),
                to: sourceRoot,
                "IMG_2026041\(index)_120000.xmp"
            ))
        }

        let result = try await DryRunPlanner().planAsync(
            sourceRoot: sourceRoot,
            destinationRoot: destinationRoot,
            workerCount: 4
        )

        let byPath = Dictionary(uniqueKeysWithValues: result.transfers.map { ($0.sourcePath, $0) })
        for companion in companions {
            let planned = try XCTUnwrap(byPath[companion.path])
            XCTAssertEqual(planned.identity, try FileIdentityHasher().hashIdentity(at: companion), companion.lastPathComponent)
        }
        XCTAssertEqual(Set(companions.map { byPath[$0.path]?.identity }).count, companions.count)
        XCTAssertEqual(result.companionOwners.count, companions.count)
    }

    func testFreeTestBatchDropsCompanionWithoutItsOwner() async throws {
        let owner = try write("owner bytes", to: sourceRoot, "IMG_20260419_120000.jpg")
        let companion = try write("sidecar", to: sourceRoot, "IMG_20260419_120000.xmp")
        let other = try write("other bytes", to: sourceRoot, "IMG_20260420_120000.jpg")

        let plan = try await DryRunPlanner().planAsync(sourceRoot: sourceRoot, destinationRoot: destinationRoot)
        let identities = Dictionary(uniqueKeysWithValues: plan.transfers.map { ($0.sourcePath, $0.identity) })
        XCTAssertEqual(plan.companionOwners, [companion.path: owner.path])

        // A batch that holds the companion but not its owner must not copy the
        // companion: it would land at a name its owner never takes.
        let companionOnly = FreeTestBatchSelection(confirmedIdentities: [
            companion.path: try XCTUnwrap(identities[companion.path]),
            other.path: try XCTUnwrap(identities[other.path]),
        ])
        let reducedWithoutOwner = plan.reduced(to: companionOnly)
        XCTAssertEqual(reducedWithoutOwner.transfers.map(\.sourcePath), [other.path])
        XCTAssertEqual(reducedWithoutOwner.companionOwners, [:])
        XCTAssertEqual(reducedWithoutOwner.counts.newCount, 1)
        XCTAssertEqual(reducedWithoutOwner.counts.duplicateCount, 0)
        XCTAssertEqual(reducedWithoutOwner.dateHistogram.map(\.plannedCount).reduce(0, +), 1)

        // Owner and companion together stay together.
        let both = FreeTestBatchSelection(confirmedIdentities: [
            owner.path: try XCTUnwrap(identities[owner.path]),
            companion.path: try XCTUnwrap(identities[companion.path]),
        ])
        let reducedWithBoth = plan.reduced(to: both)
        XCTAssertEqual(Set(reducedWithBoth.transfers.map(\.sourcePath)), [owner.path, companion.path])
        XCTAssertEqual(reducedWithBoth.companionOwners, [companion.path: owner.path])

        // Companions are never counted, exactly as in a full plan: the owner-and-
        // companion batch reports the same counts and histogram as the owner alone.
        let ownerOnly = plan.reduced(to: FreeTestBatchSelection(confirmedIdentities: [
            owner.path: try XCTUnwrap(identities[owner.path]),
        ]))
        XCTAssertEqual(ownerOnly.transfers.map(\.sourcePath), [owner.path])
        XCTAssertEqual(reducedWithBoth.counts, ownerOnly.counts)
        XCTAssertEqual(reducedWithBoth.counts.newCount, 1)
        XCTAssertEqual(reducedWithBoth.counts.duplicateCount, 0)
        XCTAssertEqual(reducedWithBoth.dateHistogram, ownerOnly.dateHistogram)
        XCTAssertEqual(reducedWithBoth.dateHistogram.map(\.plannedCount).reduce(0, +), 1)
        XCTAssertEqual(plan.counts.newCount, 2)
    }
}

enum CompanionExecution {
    /// Enqueues and runs a plan through the real transfer executor.
    @discardableResult
    static func run(
        plan: DryRunPlanningResult,
        destinationRoot: URL,
        executor: TransferExecutor = TransferExecutor()
    ) throws -> TransferExecutionResult {
        let database = try OrganizerDatabase(
            url: destinationRoot.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.queueDatabaseFilename)
        )
        defer { database.close() }
        let logger = PersistentRunLogger(logURL: destinationRoot.appendingPathComponent(".organize_log.txt"))
        try logger.open()
        defer { logger.close() }

        let runID = UUID()
        try database.enqueuePlannedTransfers(plan.transfers, runID: runID)
        return try executor.executeQueuedJobs(
            database: database,
            destinationRoot: destinationRoot,
            verifyCopies: true,
            runLogger: logger,
            status: .pending,
            orderByInsertion: true,
            runID: runID
        )
    }
}
