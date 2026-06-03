import AppKit
#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public struct ResolvedFolderBookmark: Equatable, Sendable {
    public let url: URL
    public let refreshedBookmark: FolderBookmark?

    public init(url: URL, refreshedBookmark: FolderBookmark? = nil) {
        self.url = url
        self.refreshedBookmark = refreshedBookmark
    }
}

public final class SecurityScopedFolderAccess: @unchecked Sendable {
    private let lock = NSLock()
    private let onClose: (([URL]) -> Void)?
    private var accessedURLs: [URL]
    private var isClosed = false

    public init(accessedURLs: [URL] = [], onClose: (([URL]) -> Void)? = nil) {
        self.accessedURLs = accessedURLs
        self.onClose = onClose
    }

    deinit {
        close()
    }

    public func close() {
        lock.lock()
        if isClosed {
            lock.unlock()
            return
        }
        isClosed = true
        let urls = accessedURLs
        accessedURLs = []
        lock.unlock()

        for url in urls {
            url.stopAccessingSecurityScopedResource()
        }
        onClose?(urls)
    }
}

public enum FolderValidationError: LocalizedError, Equatable, Sendable {
    case pathDoesNotExist(role: FolderRole, path: String)
    case notDirectory(role: FolderRole, path: String)
    case unreadable(role: FolderRole, path: String)
    case unwritable(role: FolderRole, path: String)

    public var errorDescription: String? {
        switch self {
        case let .pathDoesNotExist(role, path):
            return "The \(role.rawValue) folder is no longer available. Reconnect the drive or choose the \(role.rawValue) folder again. Path: \(path)."
        case let .notDirectory(role, path):
            return "The selected \(role.rawValue) item is not a folder. Choose a folder instead. Path: \(path)."
        case let .unreadable(role, path):
            return "Chronoframe cannot read the \(role.rawValue) folder. Choose it again to grant access, or pick a folder you have permission to open. Path: \(path)."
        case let .unwritable(role, path):
            return "Chronoframe cannot write to the \(role.rawValue) folder. Choose it again to grant access, pick a writable folder, or check that the drive is not read-only. Path: \(path)."
        }
    }
}

public protocol FolderAccessServicing: AnyObject, Sendable {
    @MainActor func chooseFolder(startingAt path: String?, prompt: String) -> URL?
    func makeBookmark(for url: URL, key: String) throws -> FolderBookmark
    @MainActor func resolveBookmark(_ bookmark: FolderBookmark) -> ResolvedFolderBookmark?
    @MainActor func scopedAccess(for bookmarks: [FolderBookmark]) -> SecurityScopedFolderAccess
    func validateFolder(_ url: URL, role: FolderRole) throws
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
        panel.directoryURL = Self.initialPanelDirectoryURL(startingAt: path)

        return panel.runModal() == .OK ? panel.url : nil
    }

    public static func initialPanelDirectoryURL(startingAt path: String?) -> URL {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        guard let path = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            return homeDirectory
        }

        let url = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        if isProtectedMediaLibraryPath(url) {
            return homeDirectory
        }

        if FileManager.default.fileExists(atPath: url.path) {
            // Path exists — ask the OS whether the volume is local. Non-local
            // volumes (SMB, NFS, AFP, WebDAV) can be slow or unresponsive, so
            // drop back to home rather than hanging the open panel.
            if let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey]),
               values.volumeIsLocal == false {
                return homeDirectory
            }
        } else if url.path.hasPrefix("/Volumes/") {
            // Path no longer exists but looks like an external/network mount
            // (stale bookmark, ejected drive). Avoid it.
            return homeDirectory
        }

        let parent = url.deletingLastPathComponent()
        guard parent.path != url.path, !parent.path.isEmpty else {
            return url
        }
        return parent
    }

    private static func isProtectedMediaLibraryPath(_ url: URL) -> Bool {
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let homePath = homeDirectory.path
        let path = url.path
        guard path == homePath || path.hasPrefix(homePath + "/") else {
            return false
        }

        let relativePath = String(path.dropFirst(homePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let firstComponent = relativePath.split(separator: "/").first else {
            return false
        }
        return firstComponent == "Music" || firstComponent == "Movies"
    }

    public nonisolated func makeBookmark(for url: URL, key: String) throws -> FolderBookmark {
        let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        return FolderBookmark(key: key, path: url.path, data: data)
    }

    public func resolveBookmark(_ bookmark: FolderBookmark) -> ResolvedFolderBookmark? {
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: bookmark.data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // Phase 1 finding #5: returning a fabricated `URL(fileURLWithPath:
            // bookmark.path)` here used to silently degrade to a plain path
            // that never had `startAccessingSecurityScopedResource` called
            // on it. Sandboxed runs then hit `EPERM` deep in file enumeration
            // and reported a generic permission error. Returning nil lets
            // callers explicitly handle the "bookmark no longer resolves"
            // case — drop it from preferences and prompt the user to re-pick.
            return nil
        }

        let refreshedBookmark = isStale ? try? makeBookmark(for: url, key: bookmark.key) : nil
        return ResolvedFolderBookmark(url: url, refreshedBookmark: refreshedBookmark)
    }

    public func scopedAccess(for bookmarks: [FolderBookmark]) -> SecurityScopedFolderAccess {
        var accessedURLs: [URL] = []
        for bookmark in bookmarks {
            var isStale = false
            guard let url = try? URL(
                resolvingBookmarkData: bookmark.data,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) else {
                continue
            }
            if url.startAccessingSecurityScopedResource() {
                accessedURLs.append(url)
            }
        }
        return SecurityScopedFolderAccess(accessedURLs: accessedURLs)
    }

    public nonisolated func validateFolder(_ url: URL, role: FolderRole) throws {
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw FolderValidationError.pathDoesNotExist(role: role, path: url.path)
        }
        guard isDirectory.boolValue else {
            throw FolderValidationError.notDirectory(role: role, path: url.path)
        }
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw FolderValidationError.unreadable(role: role, path: url.path)
        }
        if role == .destination && !FileManager.default.isWritableFile(atPath: url.path) {
            throw FolderValidationError.unwritable(role: role, path: url.path)
        }
    }
}
