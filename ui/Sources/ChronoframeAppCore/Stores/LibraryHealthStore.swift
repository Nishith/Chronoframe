#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation
import Combine

@MainActor
public final class LibraryHealthStore: ObservableObject {
    @Published public private(set) var summary: LibraryHealthSummary?
    @Published public private(set) var isRefreshing = false
    @Published public private(set) var errorMessage: String?

    private let scanner: LibraryHealthScanner

    public init(scanner: LibraryHealthScanner = LibraryHealthScanner()) {
        self.scanner = scanner
    }

    public func refresh(
        sourceRoot: String,
        destinationRoot: String,
        folderStructure: FolderStructure
    ) async {
        isRefreshing = true
        errorMessage = nil

        let scanner = self.scanner
        let result = await Task.detached(priority: .userInitiated) {
            scanner.scan(
                sourceRoot: sourceRoot,
                destinationRoot: destinationRoot,
                folderStructure: folderStructure
            )
        }.value

        summary = result
        isRefreshing = false
    }
}
