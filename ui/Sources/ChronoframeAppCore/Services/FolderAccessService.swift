import AppKit
import Foundation

@MainActor
public protocol FolderAccessServicing: AnyObject {
    func chooseFolder(startingAt path: String?, prompt: String) -> URL?
    func makeBookmark(for url: URL, key: String) throws -> FolderBookmark
    func resolveBookmark(_ bookmark: FolderBookmark) -> URL?
}

@MainActor
public final class FolderAccessService: FolderAccessServicing {
    public init() {}

    public func chooseFolder(startingAt path: String? = nil, prompt: String = "Choose Folder") -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = prompt

        if let path, !path.isEmpty {
            panel.directoryURL = URL(fileURLWithPath: path)
        }

        return panel.runModal() == .OK ? panel.url : nil
    }

    public func makeBookmark(for url: URL, key: String) throws -> FolderBookmark {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return FolderBookmark(key: key, path: url.path, data: data)
    }

    public func resolveBookmark(_ bookmark: FolderBookmark) -> URL? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark.data,
            options: [.withSecurityScope],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return URL(fileURLWithPath: bookmark.path)
        }

        _ = url.startAccessingSecurityScopedResource()
        return url
    }
}
