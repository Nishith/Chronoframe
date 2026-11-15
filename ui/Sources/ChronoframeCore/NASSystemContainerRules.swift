import Foundation

public enum NASSystemContainerRules {
    public static let excludedDirectoryNames: Set<String> = ["@eaDir", "#recycle", "#snapshot"]

    private static let lowercasedExcludedNames: Set<String> = Set(excludedDirectoryNames.map { $0.lowercased() })

    /// Exact whole-component match, case-insensitive. "My #recycle notes" and "backup" do not match.
    public static func isExcludedSystemContainer(name: String) -> Bool {
        lowercasedExcludedNames.contains(name.lowercased())
    }
}
