import Darwin
import Foundation

/// Builds a throwaway library tree plus a separate state directory under the
/// system temporary directory. Used by the NAS assessment tests (WP-05).
final class NASFixtureBuilder: @unchecked Sendable {
    enum Node {
        case file(String, Data)
        case directory(String)
        case symlink(String, target: String)
        case fifo(String)
    }

    struct EntrySnapshot: Equatable {
        var size: Int64
        var modificationTime: TimeInterval
        var inode: UInt64
        var mode: UInt16
    }

    /// Holds both `library` and `state`; the state directory is never inside the library.
    let containerURL: URL
    let rootURL: URL
    let stateDirectoryURL: URL

    var stateURL: URL { stateDirectoryURL.appendingPathComponent("assessment.sqlite") }
    var rootPath: String { rootURL.standardizedFileURL.path }

    init(_ nodes: [Node]) throws {
        let fileManager = FileManager.default
        containerURL = fileManager.temporaryDirectory
            .appendingPathComponent("NASFixture-\(UUID().uuidString)", isDirectory: true)
        rootURL = containerURL.appendingPathComponent("library", isDirectory: true)
        stateDirectoryURL = containerURL.appendingPathComponent("state", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: stateDirectoryURL, withIntermediateDirectories: true)

        for node in nodes {
            switch node {
            case let .directory(path):
                try fileManager.createDirectory(at: rootURL.appendingPathComponent(path), withIntermediateDirectories: true)
            case let .file(path, bytes):
                let url = rootURL.appendingPathComponent(path)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try bytes.write(to: url)
            case let .symlink(path, target):
                let url = rootURL.appendingPathComponent(path)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.createSymbolicLink(atPath: url.path, withDestinationPath: target)
            case let .fifo(path):
                let url = rootURL.appendingPathComponent(path)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                guard mkfifo(url.path, 0o644) == 0 else {
                    throw CocoaError(.fileWriteUnknown)
                }
            }
        }
    }

    /// `lstat` metadata for the root ("."), and every entry below it, dot files included.
    func snapshot() throws -> [String: EntrySnapshot] {
        var result: [String: EntrySnapshot] = [:]
        try collect(path: rootURL.path, relative: ".", into: &result)
        return result
    }

    private func collect(path: String, relative: String, into result: inout [String: EntrySnapshot]) throws {
        var info = Darwin.stat()
        guard Darwin.lstat(path, &info) == 0 else { throw CocoaError(.fileReadUnknown) }
        result[relative] = EntrySnapshot(
            size: Int64(info.st_size),
            modificationTime: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000,
            inode: UInt64(info.st_ino),
            mode: UInt16(info.st_mode)
        )
        guard (info.st_mode & S_IFMT) == S_IFDIR else { return }
        for name in try FileManager.default.contentsOfDirectory(atPath: path) {
            let childRelative = relative == "." ? name : relative + "/" + name
            try collect(path: path + "/" + name, relative: childRelative, into: &result)
        }
    }

    /// Removes write permission from every directory and file in the library (symlinks are left alone).
    func makeReadOnly() throws {
        try applyPermissions(at: rootURL.path, directoryMode: 0o555, fileMode: 0o444)
    }

    func restorePermissions() {
        try? applyPermissions(at: rootURL.path, directoryMode: 0o755, fileMode: 0o644)
    }

    private func applyPermissions(at path: String, directoryMode: mode_t, fileMode: mode_t) throws {
        var info = Darwin.stat()
        guard Darwin.lstat(path, &info) == 0 else { return }
        let type = info.st_mode & S_IFMT
        if type == S_IFDIR {
            // Make the directory searchable and writable first so its children can be listed and changed.
            _ = Darwin.chmod(path, 0o755)
            for name in (try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [] {
                try applyPermissions(at: path + "/" + name, directoryMode: directoryMode, fileMode: fileMode)
            }
            _ = Darwin.chmod(path, directoryMode)
        } else if type == S_IFREG {
            _ = Darwin.chmod(path, fileMode)
        }
    }

    /// Restores permissions, then removes only what this fixture created.
    func tearDown() {
        restorePermissions()
        try? FileManager.default.removeItem(at: containerURL)
    }
}
