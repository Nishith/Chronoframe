#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// Plain-language titles and a worked example for each folder layout.
///
/// `PlanningPathBuilder` is internal to ChronoframeCore, so the App target
/// cannot call it (D-CLP-13 fallback, C-07). The example is built here by hand
/// and `FolderLayoutPresentationTests` pins it to the builder's output for
/// every `FolderStructure` case.
enum FolderLayoutPresentation {
    static func title(_ structure: FolderStructure) -> String {
        switch structure {
        case .yyyyMMDD: "Year / Month / Day"
        case .yyyyMM: "Year / Month"
        case .yyyy: "Year"
        case .yyyyMonEvent: "Year / Month / Event"
        case .flat: "One folder"
        }
    }

    /// The path the planner gives IMG_0001.jpg taken on 14 July 2019 (sequence 1,
    /// default naming rules, no event name, not a duplicate), relative to the destination.
    static func exampleRelativePath(_ structure: FolderStructure) -> String {
        let filename = "2019-07-14_001.jpg"
        switch structure {
        case .yyyyMMDD: return "2019/07/14/\(filename)"
        case .yyyyMM: return "2019/07/\(filename)"
        case .yyyy: return "2019/\(filename)"
        case .yyyyMonEvent: return "2019/Jul/\(filename)"
        case .flat: return filename
        }
    }

    static func exampleLines(_ structure: FolderStructure) -> [String] {
        let components = exampleRelativePath(structure).split(separator: "/").map(String.init)
        return components.enumerated().map { index, component in
            let indent = String(repeating: "  ", count: index)
            let isFile = index == components.count - 1
            return indent + component + (isFile ? "" : "/")
        }
    }

    static func accessibilityExample(_ structure: FolderStructure) -> String {
        "Example: \(exampleRelativePath(structure))"
    }
}
