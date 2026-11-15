#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public enum SourceItemListError: Error, Equatable, LocalizedError {
    case insideListed(name: String, parentName: String)
    case overlapsDestination(name: String)
    case missing(name: String)

    public var errorDescription: String? {
        switch self {
        case let .insideListed(name, parentName):
            return "\u{201C}\(name)\u{201D} is already covered because it is inside \u{201C}\(parentName)\u{201D}."
        case let .overlapsDestination(name):
            return "\u{201C}\(name)\u{201D} and the destination overlap. Choose a destination outside the folders you are organizing; nothing was changed."
        case let .missing(name):
            return "Chronoframe can't find \u{201C}\(name)\u{201D} any more. Reconnect the drive or add the folder again."
        }
    }
}

public struct SourceItemList: Equatable, Sendable {
    /// Symlink-resolved, standardized, in insertion order.
    public private(set) var items: [URL]

    public init(items: [URL] = []) {
        self.items = items
    }

    /// Same path → no-op. Inside a listed folder → throws `insideListed`. Contains listed folders →
    /// they are removed, then it is appended. A non-empty destination that overlaps → throws
    /// `overlapsDestination`. Not on disk → throws `missing`. Nothing changes when this throws.
    public mutating func add(_ url: URL, destinationPath: String, fileManager: FileManager = .default) throws {
        let resolved = Self.resolve(url)
        guard fileManager.fileExists(atPath: resolved.path) else {
            throw SourceItemListError.missing(name: Self.displayName(of: resolved))
        }
        if items.contains(resolved) {
            return
        }
        if let parent = items.first(where: { Self.path(resolved.path, isInside: $0.path) }) {
            throw SourceItemListError.insideListed(
                name: Self.displayName(of: resolved),
                parentName: Self.displayName(of: parent)
            )
        }
        let trimmedDestination = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDestination.isEmpty,
           SourceDestinationDisjointness.conflict(sourcePath: resolved.path, destinationPath: trimmedDestination) != nil {
            throw SourceItemListError.overlapsDestination(name: Self.displayName(of: resolved))
        }
        items.removeAll { Self.path($0.path, isInside: resolved.path) }
        items.append(resolved)
    }

    public mutating func remove(_ url: URL) {
        let resolved = Self.resolve(url)
        items.removeAll { $0 == resolved || $0 == url }
    }

    /// True when the list cannot be organized as a plain folder: more than one item,
    /// or a single item that is not a directory.
    public var needsStaging: Bool {
        if items.count > 1 { return true }
        guard let only = items.first else { return false }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: only.path, isDirectory: &isDirectory)
        return !(exists && isDirectory.boolValue)
    }

    public func firstConflict(withDestination destinationPath: String) -> SourceItemListError? {
        let trimmedDestination = destinationPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedDestination.isEmpty,
              SourceDestinationDisjointness.conflict(
                  sourceItemPaths: items.map(\.path),
                  destinationPath: trimmedDestination
              ) != nil
        else {
            return nil
        }
        for item in items
        where SourceDestinationDisjointness.conflict(sourcePath: item.path, destinationPath: trimmedDestination) != nil {
            return .overlapsDestination(name: Self.displayName(of: item))
        }
        return nil
    }

    public static func summaryLabel(count: Int) -> String {
        count == 1 ? "1 folder" : "\(count.formatted()) folders"
    }

    private static func resolve(_ url: URL) -> URL {
        url.resolvingSymlinksInPath().standardizedFileURL
    }

    private static func displayName(of url: URL) -> String {
        let name = url.lastPathComponent
        return name.isEmpty ? url.path : name
    }

    private static func path(_ child: String, isInside parent: String) -> Bool {
        let prefix = parent.hasSuffix("/") ? parent : parent + "/"
        return child != parent && child.hasPrefix(prefix)
    }
}
