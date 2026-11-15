#if canImport(ChronoframeCore)
@testable import ChronoframeCore
#endif
import XCTest
@testable import ChronoframeApp

final class FolderLayoutPresentationTests: XCTestCase {
    private let placeholderRoot = "/chronoframe-example-root"

    func testTitlesForEveryStructure() {
        XCTAssertEqual(FolderLayoutPresentation.title(.yyyyMMDD), "Year / Month / Day")
        XCTAssertEqual(FolderLayoutPresentation.title(.yyyyMM), "Year / Month")
        XCTAssertEqual(FolderLayoutPresentation.title(.yyyy), "Year")
        XCTAssertEqual(FolderLayoutPresentation.title(.yyyyMonEvent), "Year / Month / Event")
        XCTAssertEqual(FolderLayoutPresentation.title(.flat), "One folder")
    }

    func testExampleRelativePathEqualsPathBuilderOutput() {
        for structure in FolderStructure.allCases {
            let built = PlanningPathBuilder.buildDestinationPath(
                for: "IMG_0001.jpg",
                destinationRoot: placeholderRoot,
                dateBucket: "2019-07-14",
                sequence: 1,
                duplicateDirectoryName: nil,
                namingRules: .chronoframeDefault,
                folderStructure: structure,
                sourceRoot: nil,
                eventNameOverride: nil,
                minimumSequenceWidth: nil
            )
            XCTAssertTrue(built.hasPrefix(placeholderRoot + "/"), "\(structure)")
            let stripped = String(built.dropFirst(placeholderRoot.count + 1))
            XCTAssertEqual(
                FolderLayoutPresentation.exampleRelativePath(structure),
                stripped,
                "\(structure)"
            )
        }
    }

    func testExampleLinesIndentOneLevelPerComponent() {
        for structure in FolderStructure.allCases {
            let components = FolderLayoutPresentation.exampleRelativePath(structure)
                .split(separator: "/")
                .map(String.init)
            let lines = FolderLayoutPresentation.exampleLines(structure)
            XCTAssertEqual(lines.count, components.count, "\(structure)")
            for (index, component) in components.enumerated() {
                let isFile = index == components.count - 1
                let expected = String(repeating: "  ", count: index) + component + (isFile ? "" : "/")
                XCTAssertEqual(lines[index], expected, "\(structure) line \(index)")
            }
        }
        XCTAssertEqual(
            FolderLayoutPresentation.exampleLines(.yyyyMMDD),
            ["2019/", "  07/", "    14/", "      2019-07-14_001.jpg"]
        )
    }

    func testFlatLayoutIsOneLine() {
        XCTAssertEqual(FolderLayoutPresentation.exampleLines(.flat), ["2019-07-14_001.jpg"])
        XCTAssertEqual(FolderLayoutPresentation.exampleRelativePath(.flat), "2019-07-14_001.jpg")
    }

    func testAccessibilityExampleStartsWithExample() {
        for structure in FolderStructure.allCases {
            XCTAssertEqual(
                FolderLayoutPresentation.accessibilityExample(structure),
                "Example: " + FolderLayoutPresentation.exampleRelativePath(structure)
            )
        }
    }

    func testEveryStructureHasDistinctTitle() {
        let titles = FolderStructure.allCases.map(FolderLayoutPresentation.title)
        XCTAssertEqual(Set(titles).count, FolderStructure.allCases.count)
        XCTAssertFalse(titles.contains { $0.isEmpty })
    }
}
