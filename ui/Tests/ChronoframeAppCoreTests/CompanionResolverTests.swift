import Foundation
import XCTest
@testable import ChronoframeCore

final class CompanionResolverTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("CompanionResolverTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        temporaryDirectoryURL = URL(fileURLWithPath: realpath(temporaryDirectoryURL.path, nil).map { String(cString: $0) } ?? temporaryDirectoryURL.path, isDirectory: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        try super.tearDownWithError()
    }

    func testCompanionResolverMatchesExactlyOneOwner() {
        let resolution = CompanionResolver.resolve(
            companionPaths: [
                "/src/a/IMG_1.xmp",         // replaced-extension form
                "/src/a/IMG_2.jpg.xmp",     // appended form
                "/src/a/IMG_E3.AAE",        // iOS edit form
                "/src/a/IMG_4.AAE",         // plain .aae
            ],
            mediaPaths: [
                "/src/a/IMG_1.jpg", "/src/a/IMG_2.jpg", "/src/a/IMG_3.HEIC", "/src/a/IMG_4.mov",
            ]
        )

        XCTAssertEqual(resolution.ownersByCompanion, [
            "/src/a/IMG_1.xmp": "/src/a/IMG_1.jpg",
            "/src/a/IMG_2.jpg.xmp": "/src/a/IMG_2.jpg",
            "/src/a/IMG_E3.AAE": "/src/a/IMG_3.HEIC",
            "/src/a/IMG_4.AAE": "/src/a/IMG_4.mov",
        ])
        XCTAssertEqual(resolution.unresolved, [])
    }

    func testRAWPlusJPEGSharedXMPIsUnresolved() throws {
        let resolution = CompanionResolver.resolve(
            companionPaths: ["/src/photo.xmp"],
            mediaPaths: ["/src/photo.cr3", "/src/photo.jpg"]
        )
        XCTAssertEqual(resolution.ownersByCompanion, [:])
        XCTAssertEqual(resolution.unresolved, [UnresolvedCompanion(sourcePath: "/src/photo.xmp", reason: .multipleOwners)])

        // Unresolved companions never block planning: the photos still plan and
        // the companion is listed instead of copied.
        let sourceRoot = temporaryDirectoryURL.appendingPathComponent("source", isDirectory: true)
        let destinationRoot = temporaryDirectoryURL.appendingPathComponent("dest", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        try Data("raw bytes".utf8).write(to: sourceRoot.appendingPathComponent("photo.cr3"))
        try Data("jpeg bytes".utf8).write(to: sourceRoot.appendingPathComponent("photo.jpg"))
        try Data("xmp bytes".utf8).write(to: sourceRoot.appendingPathComponent("photo.xmp"))

        let result = try DryRunPlanner().plan(sourceRoot: sourceRoot, destinationRoot: destinationRoot)

        XCTAssertEqual(result.discoveredSourceCount, 2)
        XCTAssertEqual(result.transfers.count, 2)
        XCTAssertEqual(
            result.copyPlan.unresolvedCompanions,
            [UnresolvedCompanion(sourcePath: sourceRoot.appendingPathComponent("photo.xmp").path, reason: .multipleOwners)]
        )
        XCTAssertEqual(result.companionOwners, [:])
    }

    func testOrphanXMPIsUnresolved() {
        let resolution = CompanionResolver.resolve(
            companionPaths: ["/src/orphan.xmp", "/src/IMG_E9999.AAE", "/src/control.xmp"],
            mediaPaths: ["/src/other.jpg", "/src/IMG_1234.jpg", "/src/control.jpg"]
        )
        // Control: a same-directory owner and companion still resolve.
        XCTAssertEqual(resolution.ownersByCompanion, ["/src/control.xmp": "/src/control.jpg"])
        XCTAssertEqual(resolution.unresolved, [
            UnresolvedCompanion(sourcePath: "/src/IMG_E9999.AAE", reason: .noOwner),
            UnresolvedCompanion(sourcePath: "/src/orphan.xmp", reason: .noOwner),
        ])
    }

    func testCrossDirectoryXMPIsNotMatched() {
        let resolution = CompanionResolver.resolve(
            companionPaths: ["/src/a/IMG_1.xmp", "/src/a/IMG_2.xmp"],
            mediaPaths: ["/src/b/IMG_1.jpg", "/src/a/sub/IMG_1.jpg", "/src/a/IMG_2.jpg"]
        )
        // Control: the same-directory pair resolves; the cross-directory one does not.
        XCTAssertEqual(resolution.ownersByCompanion, ["/src/a/IMG_2.xmp": "/src/a/IMG_2.jpg"])
        XCTAssertEqual(resolution.unresolved, [UnresolvedCompanion(sourcePath: "/src/a/IMG_1.xmp", reason: .noOwner)])
    }

    func testHiddenAndCaseVariantsHandled() throws {
        // Case-insensitive names and extensions.
        let resolution = CompanionResolver.resolve(
            companionPaths: ["/src/img_1.XMP", "/src/IMG_E0042.aae"],
            mediaPaths: ["/src/IMG_1.JPG", "/src/img_0042.heic"]
        )
        XCTAssertEqual(resolution.ownersByCompanion, [
            "/src/img_1.XMP": "/src/IMG_1.JPG",
            "/src/IMG_E0042.aae": "/src/img_0042.heic",
        ])

        // The IMG_E rule needs exact digits and only applies to .aae.
        let strict = CompanionResolver.resolve(
            companionPaths: ["/src/IMG_E1234.AAE", "/src/IMG_E1.xmp"],
            mediaPaths: ["/src/IMG_12345.jpg", "/src/IMG_1.jpg"]
        )
        XCTAssertEqual(strict.ownersByCompanion, [:])

        XCTAssertTrue(MediaLibraryRules.isCompanionFile(path: "/a/IMG_1.AAE"))
        XCTAssertTrue(MediaLibraryRules.isCompanionFile(path: "/a/IMG_1.Xmp"))
        XCTAssertFalse(MediaLibraryRules.isCompanionFile(path: "/a/IMG_1.jpg"))
        XCTAssertFalse(MediaLibraryRules.isSupportedMediaFile(path: "/a/IMG_1.xmp"))

        // Discovery: hidden companions are skipped, upper-case ones are found,
        // and companions never appear as media.
        let root = temporaryDirectoryURL.appendingPathComponent("discovery", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in ["IMG_1.JPG", "IMG_1.XMP", "IMG_E1.AAE", ".hidden.xmp", "._IMG_1.xmp"] {
            try Data(name.utf8).write(to: root.appendingPathComponent(name))
        }
        let found = try MediaDiscovery.discoverMediaAndCompanions(at: root)
        XCTAssertEqual(found.media.map { URL(fileURLWithPath: $0).lastPathComponent }, ["IMG_1.JPG"])
        XCTAssertEqual(
            found.companions.map { URL(fileURLWithPath: $0).lastPathComponent }.sorted(),
            ["IMG_1.XMP", "IMG_E1.AAE"]
        )
        XCTAssertEqual(
            try MediaDiscovery.discoverMediaFiles(at: root).map { URL(fileURLWithPath: $0).lastPathComponent },
            ["IMG_1.JPG"]
        )
    }
    // AGENTS-INVARIANT: 15
    func testSymlinkedCompanionIsNotDiscovered() throws {
        let root = temporaryDirectoryURL.appendingPathComponent("symlinks", isDirectory: true)
        let outside = temporaryDirectoryURL.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try Data("photo".utf8).write(to: root.appendingPathComponent("IMG_1.jpg"))
        try Data("real".utf8).write(to: root.appendingPathComponent("IMG_1.xmp"))
        let target = outside.appendingPathComponent("elsewhere.xmp")
        try Data("outside".utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("IMG_1.jpg.xmp"),
            withDestinationURL: target
        )
        let linkedFolder = outside.appendingPathComponent("folder", isDirectory: true)
        try FileManager.default.createDirectory(at: linkedFolder, withIntermediateDirectories: true)
        try Data("inside linked folder".utf8).write(to: linkedFolder.appendingPathComponent("IMG_9.xmp"))
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("linked"),
            withDestinationURL: linkedFolder
        )

        let found = try MediaDiscovery.discoverMediaAndCompanions(at: root)

        XCTAssertEqual(found.companions.map { URL(fileURLWithPath: $0).lastPathComponent }, ["IMG_1.xmp"])

        // The same holds for a symlink dropped explicitly through a manifest.
        let manifest: [String: Any] = ["items": [
            ["path": root.appendingPathComponent("IMG_1.jpg").path, "isDirectory": false],
            ["path": root.appendingPathComponent("IMG_1.jpg.xmp").path, "isDirectory": false],
        ]]
        try JSONSerialization.data(withJSONObject: manifest)
            .write(to: root.appendingPathComponent(".chronoframe_drop_manifest.json"))
        let viaManifest = try MediaDiscovery.discoverMediaAndCompanions(at: root)
        XCTAssertEqual(viaManifest.media.map { URL(fileURLWithPath: $0).lastPathComponent }, ["IMG_1.jpg"])
        XCTAssertEqual(viaManifest.companions, [])
    }

    func testCompanionPlanMarksCaseVariantClashAndUnreadable() {
        let owner = PlannedTransfer(
            sourcePath: "/src/IMG_1.jpg",
            destinationPath: "/dst/2026/04/19/2026-04-19_001.jpg",
            identity: FileIdentity(size: 1, digest: "owner"),
            dateBucket: "2026-04-19",
            isDuplicate: false
        )
        let second = PlannedTransfer(
            sourcePath: "/src/IMG_2.jpg",
            destinationPath: "/dst/2026/04/19/2026-04-19_002.jpg",
            identity: FileIdentity(size: 1, digest: "second"),
            dateBucket: "2026-04-19",
            isDuplicate: false
        )
        let resolution = CompanionResolver.resolve(
            companionPaths: ["/src/IMG_1.xmp", "/src/IMG_1.XMP", "/src/IMG_2.xmp"],
            mediaPaths: [owner.sourcePath, second.sourcePath]
        )
        XCTAssertEqual(resolution.ownersByCompanion.count, 3)

        let planned = CompanionResolver.plan(
            ownerTransfers: [owner, second],
            resolution: resolution,
            identity: { $0 == "/src/IMG_2.xmp" ? nil : FileIdentity(size: 2, digest: "sidecar") },
            fileExists: { _ in false }
        )

        // Spellings that differ only by case clash on a case-insensitive volume: both stay out.
        XCTAssertEqual(planned.transfers, [])
        XCTAssertEqual(planned.companionOwners, [:])
        XCTAssertEqual(planned.unresolved, [
            UnresolvedCompanion(sourcePath: "/src/IMG_1.XMP", reason: .nameTaken),
            UnresolvedCompanion(sourcePath: "/src/IMG_1.xmp", reason: .nameTaken),
            UnresolvedCompanion(sourcePath: "/src/IMG_2.xmp", reason: .unreadable),
        ])

        // Control: without the clash the unreadable one is the only one listed.
        let single = CompanionResolver.plan(
            ownerTransfers: [owner, second],
            resolution: CompanionResolver.resolve(
                companionPaths: ["/src/IMG_1.xmp", "/src/IMG_2.xmp"],
                mediaPaths: [owner.sourcePath, second.sourcePath]
            ),
            identity: { $0 == "/src/IMG_2.xmp" ? nil : FileIdentity(size: 2, digest: "sidecar") },
            fileExists: { _ in false }
        )
        XCTAssertEqual(single.transfers.map(\.destinationPath), ["/dst/2026/04/19/2026-04-19_001.xmp"])
        XCTAssertEqual(single.unresolved, [UnresolvedCompanion(sourcePath: "/src/IMG_2.xmp", reason: .unreadable)])
    }
}
