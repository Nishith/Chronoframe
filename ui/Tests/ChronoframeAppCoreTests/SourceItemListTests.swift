import Foundation
import XCTest
@testable import ChronoframeAppCore

final class SourceItemListTests: XCTestCase {
    private var root: URL!
    private let fileManager = FileManager.default

    override func setUpWithError() throws {
        try super.setUpWithError()
        let base = fileManager.temporaryDirectory
            .appendingPathComponent("SourceItemListTests-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        root = base.resolvingSymlinksInPath().standardizedFileURL
    }

    override func tearDownWithError() throws {
        if let root {
            try? fileManager.removeItem(at: root)
        }
        root = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func makeDirectory(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    private func makeFile(_ relativePath: String) throws -> URL {
        let url = root.appendingPathComponent(relativePath)
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        XCTAssertTrue(fileManager.createFile(atPath: url.path, contents: Data("x".utf8)))
        return url.resolvingSymlinksInPath().standardizedFileURL
    }

    func testAddSamePathTwiceIsNoOp() throws {
        let a = try makeDirectory("a")
        var list = SourceItemList()

        try list.add(a, destinationPath: "")
        try list.add(a, destinationPath: "")

        XCTAssertEqual(list.items, [a])
    }

    func testAddFolderInsideListedFolderThrowsInsideListed() throws {
        let parent = try makeDirectory("Photos")
        let child = try makeDirectory("Photos/2019")
        var list = SourceItemList()
        try list.add(parent, destinationPath: "")

        XCTAssertThrowsError(try list.add(child, destinationPath: "")) { error in
            XCTAssertEqual(error as? SourceItemListError, .insideListed(name: "2019", parentName: "Photos"))
        }
        XCTAssertEqual(list.items, [parent])
    }

    func testAddParentReplacesListedChildren() throws {
        let other = try makeDirectory("Other")
        let child1 = try makeDirectory("Photos/2019")
        let child2 = try makeDirectory("Photos/2020")
        let parent = try makeDirectory("Photos")
        var list = SourceItemList()
        try list.add(child1, destinationPath: "")
        try list.add(other, destinationPath: "")
        try list.add(child2, destinationPath: "")

        try list.add(parent, destinationPath: "")

        XCTAssertEqual(list.items, [other, parent])
    }

    func testAddOverlappingDestinationThrows() throws {
        let source = try makeDirectory("Photos")
        let destinationInsideSource = try makeDirectory("Photos/Organized")
        let destinationElsewhere = try makeDirectory("Elsewhere")
        let sourceInsideDestination = try makeDirectory("Elsewhere/Phone")

        // Destination sits inside the folder being added.
        var first = SourceItemList()
        XCTAssertThrowsError(try first.add(source, destinationPath: destinationInsideSource.path)) { error in
            XCTAssertEqual(error as? SourceItemListError, .overlapsDestination(name: "Photos"))
        }
        XCTAssertTrue(first.items.isEmpty)

        // The folder being added sits inside the destination.
        var second = SourceItemList()
        XCTAssertThrowsError(try second.add(sourceInsideDestination, destinationPath: destinationElsewhere.path)) { error in
            XCTAssertEqual(error as? SourceItemListError, .overlapsDestination(name: "Phone"))
        }
        XCTAssertTrue(second.items.isEmpty)

        // Same folder as the destination also overlaps.
        var third = SourceItemList()
        XCTAssertThrowsError(try third.add(source, destinationPath: source.path))
    }

    func testAddMissingPathThrowsMissing() throws {
        let missing = root.appendingPathComponent("Gone", isDirectory: true)
        var list = SourceItemList()

        XCTAssertThrowsError(try list.add(missing, destinationPath: "")) { error in
            XCTAssertEqual(error as? SourceItemListError, .missing(name: "Gone"))
        }
        XCTAssertTrue(list.items.isEmpty)
    }

    func testEmptyDestinationSkipsOverlapCheck() throws {
        let a = try makeDirectory("a")
        var list = SourceItemList()

        XCTAssertNoThrow(try list.add(a, destinationPath: ""))
        XCTAssertNoThrow(try list.add(try makeDirectory("b"), destinationPath: "   "))
        XCTAssertEqual(list.items.count, 2)
        XCTAssertNil(list.firstConflict(withDestination: ""))
    }

    func testRemoveKeepsOrder() throws {
        let a = try makeDirectory("a")
        let b = try makeDirectory("b")
        let c = try makeDirectory("c")
        var list = SourceItemList()
        try list.add(a, destinationPath: "")
        try list.add(b, destinationPath: "")
        try list.add(c, destinationPath: "")

        list.remove(b)
        XCTAssertEqual(list.items, [a, c])

        // Removing something that is not listed changes nothing.
        list.remove(b)
        XCTAssertEqual(list.items, [a, c])
    }

    func testNeedsStagingForTwoFoldersOrOneFile() throws {
        let a = try makeDirectory("a")
        let b = try makeDirectory("b")
        let file = try makeFile("loose/photo.jpg")

        var empty = SourceItemList()
        XCTAssertFalse(empty.needsStaging)

        try empty.add(a, destinationPath: "")
        XCTAssertFalse(empty.needsStaging)

        try empty.add(b, destinationPath: "")
        XCTAssertTrue(empty.needsStaging)

        var single = SourceItemList()
        try single.add(file, destinationPath: "")
        XCTAssertTrue(single.needsStaging)
    }

    func testFirstConflictWithDestination() throws {
        let a = try makeDirectory("a")
        let b = try makeDirectory("b")
        let inside = try makeDirectory("b/Organized")
        let clear = try makeDirectory("clear")
        let list = SourceItemList(items: [a, b])

        XCTAssertNil(list.firstConflict(withDestination: clear.path))
        XCTAssertEqual(
            list.firstConflict(withDestination: inside.path),
            .overlapsDestination(name: "b")
        )
        XCTAssertEqual(
            list.firstConflict(withDestination: a.path),
            .overlapsDestination(name: "a")
        )
    }

    func testSummaryLabelSingularAndPlural() {
        XCTAssertEqual(SourceItemList.summaryLabel(count: 1), "1 folder")
        XCTAssertEqual(SourceItemList.summaryLabel(count: 3), "3 folders")
        XCTAssertEqual(SourceItemList.summaryLabel(count: 1_200), "\(1_200.formatted()) folders")
    }

    func testErrorDescriptionsMatchContract() {
        XCTAssertEqual(
            SourceItemListError.insideListed(name: "2019", parentName: "Photos").errorDescription,
            "\u{201C}2019\u{201D} is already covered because it is inside \u{201C}Photos\u{201D}."
        )
        XCTAssertEqual(
            SourceItemListError.overlapsDestination(name: "Photos").errorDescription,
            "\u{201C}Photos\u{201D} and the destination overlap. Choose a destination outside the folders you are organizing; nothing was changed."
        )
        XCTAssertEqual(
            SourceItemListError.missing(name: "Card").errorDescription,
            "Chronoframe can't find \u{201C}Card\u{201D} any more. Reconnect the drive or add the folder again."
        )
    }

    func testSymlinkedPathResolvesToSameItem() throws {
        let real = try makeDirectory("Real")
        let link = root.appendingPathComponent("Link")
        try fileManager.createSymbolicLink(at: link, withDestinationURL: real)
        var list = SourceItemList()

        try list.add(link, destinationPath: "")
        XCTAssertEqual(list.items, [real])

        try list.add(real, destinationPath: "")
        XCTAssertEqual(list.items, [real])
    }
}
