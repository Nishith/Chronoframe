import Foundation

public struct MediaDiscoveryEntry: Equatable, Sendable {
    public var path: String
    public var isDirectory: Bool

    public init(path: String, isDirectory: Bool) {
        self.path = path
        self.isDirectory = isDirectory
    }
}

public enum MediaDiscovery {
    public struct DirectoryIssue: Equatable, Sendable {
        public var path: String
        public var message: String

        public init(path: String, message: String) {
            self.path = path
            self.message = message
        }
    }

    private struct DropManifest: Decodable {
        var items: [Item]
        var allowsExternalItems: Bool?

        struct Item: Decodable {
            var path: String
            var isDirectory: Bool
        }
    }

    private static let dropManifestFilename = ".chronoframe_drop_manifest.json"

    public static func discoverMediaFiles(
        at rootURL: URL,
        isCancelled: @Sendable () -> Bool = { false },
        onDirectoryIssue: (@Sendable (DirectoryIssue) -> Void)? = nil
    ) throws -> [String] {
        var results: [String] = []
        try enumerateMediaFiles(at: rootURL, isCancelled: isCancelled, onDirectoryIssue: onDirectoryIssue) { path in
            results.append(path)
        }
        return results
    }

    public static func enumerateMediaFiles(
        at rootURL: URL,
        isCancelled: @Sendable () -> Bool = { false },
        onDirectoryIssue: (@Sendable (DirectoryIssue) -> Void)? = nil,
        _ body: (String) throws -> Void
    ) throws {
        switch readDropManifest(at: rootURL) {
        case let .present(manifest):
            try enumerateManifest(manifest, rootURL: rootURL, isCancelled: isCancelled, onDirectoryIssue: onDirectoryIssue, visitFilePath: body)
            return
        case let .corrupt(manifestURL, error):
            // The staging directory only contains the manifest; falling
            // through to `walk()` would silently report "0 files to
            // organize". Surface a DirectoryIssue instead so the caller
            // can show the user something actionable.
            onDirectoryIssue?(DirectoryIssue(
                path: manifestURL.path,
                message: "Drop manifest could not be read: \(error.localizedDescription)"
            ))
            return
        case .absent:
            break
        }
        try walk(directoryURL: rootURL, isCancelled: isCancelled, onDirectoryIssue: onDirectoryIssue, visitFilePath: body)
    }

    private enum DropManifestLookup {
        case present(DropManifest)
        case corrupt(URL, Error)
        case absent
    }

    public static func walkEntries(
        at rootURL: URL,
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> [MediaDiscoveryEntry] {
        var entries: [MediaDiscoveryEntry] = []
        try walkEntries(directoryURL: rootURL, isCancelled: isCancelled, entries: &entries)
        return entries
    }

    private static func walk(
        directoryURL: URL,
        isCancelled: @Sendable () -> Bool,
        onDirectoryIssue: (@Sendable (DirectoryIssue) -> Void)?,
        visitFilePath: (String) throws -> Void
    ) throws {
        try throwIfCancelled(isCancelled)
        let partition = try partitionedChildren(of: directoryURL, onDirectoryIssue: onDirectoryIssue)

        for child in partition.files {
            try throwIfCancelled(isCancelled)
            // Drain Foundation autoreleased temporaries (URL/NSString/NSDictionary bridges,
            // FileHandle, NSRegularExpression results) per-iteration. Without this, the
            // pool only drains when plan()/executeQueuedJobs() returns, which on large
            // trees (10k+ files) can pin hundreds of MB of otherwise-dead NSObjects.
            try autoreleasepool {
                let name = child.lastPathComponent
                if name.hasPrefix(".") {
                    return
                }

                if MediaLibraryRules.shouldSkipDiscoveredFile(named: name) {
                    return
                }

                if MediaLibraryRules.isSupportedMediaFile(path: child.path) {
                    try visitFilePath(child.path)
                }
            }
        }

        for child in partition.directories {
            try throwIfCancelled(isCancelled)
            try walk(directoryURL: child, isCancelled: isCancelled, onDirectoryIssue: onDirectoryIssue, visitFilePath: visitFilePath)
        }
    }

    private static func walkEntries(
        directoryURL: URL,
        isCancelled: @Sendable () -> Bool,
        entries: inout [MediaDiscoveryEntry]
    ) throws {
        try throwIfCancelled(isCancelled)
        let children = try sortedChildren(of: directoryURL, onDirectoryIssue: nil)
        for child in children {
            try throwIfCancelled(isCancelled)
            let name = child.lastPathComponent
            if name.hasPrefix(".") {
                continue
            }

            let resourceValues = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey])
            if resourceValues.isSymbolicLink == true || resourceValues.isPackage == true {
                continue
            }
            let isDirectory = resourceValues.isDirectory == true
            entries.append(MediaDiscoveryEntry(path: child.path, isDirectory: isDirectory))

            if isDirectory {
                try walkEntries(directoryURL: child, isCancelled: isCancelled, entries: &entries)
            }
        }
    }

    private static func throwIfCancelled(_ isCancelled: @Sendable () -> Bool) throws {
        if isCancelled() {
            throw CancellationError()
        }
    }

    private static func partitionedChildren(
        of directoryURL: URL,
        onDirectoryIssue: (@Sendable (DirectoryIssue) -> Void)?
    ) throws -> (directories: [URL], files: [URL]) {
        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .ubiquitousItemDownloadingStatusKey],
                options: []
            )
        } catch {
            onDirectoryIssue?(
                DirectoryIssue(
                    path: directoryURL.path,
                    message: "Chronoframe could not read this folder, so it was skipped: \(directoryURL.path)"
                )
            )
            return ([], [])
        }

        var directories: [URL] = []
        var files: [URL] = []

        for child in children {
            let name = child.lastPathComponent
            if name.hasPrefix(".") {
                continue
            }

            let isDirectory: Bool
            do {
                let resourceValues = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .ubiquitousItemDownloadingStatusKey])
                if resourceValues.isSymbolicLink == true || resourceValues.isPackage == true {
                    continue
                }
                #if DEBUG
                let isDataless = isICloudDatalessProvider(child)
                #else
                let isDataless = resourceValues.ubiquitousItemDownloadingStatus == .notDownloaded
                #endif
                if isDataless {
                    continue
                }
                isDirectory = resourceValues.isDirectory == true
            } catch {
                continue
            }

            if isDirectory {
                directories.append(child)
            } else {
                files.append(child)
            }
        }

        let sorter: (URL, URL) -> Bool = {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }
        return (directories.sorted(by: sorter), files.sorted(by: sorter))
    }

    private static func sortedChildren(
        of directoryURL: URL,
        onDirectoryIssue: (@Sendable (DirectoryIssue) -> Void)?
    ) throws -> [URL] {
        let partition = try partitionedChildren(of: directoryURL, onDirectoryIssue: onDirectoryIssue)
        return partition.directories + partition.files
    }

    /// Returns true when `url` should NOT participate in drop-manifest
    /// traversal: it's a symbolic link, an app bundle, a package, or
    /// otherwise outside what the filesystem walk would accept as a
    /// child. Mirrors the children-filter in `partitionedChildren` so
    /// the drop-intake path enforces the same documented invariant.
    private static func isManifestEntryFiltered(url: URL) -> Bool {
        let resourceValues = try? url.resourceValues(forKeys: [.isSymbolicLinkKey, .isPackageKey])
        if resourceValues?.isSymbolicLink == true { return true }
        if resourceValues?.isPackage == true { return true }
        return false
    }

    private static func readDropManifest(at rootURL: URL) -> DropManifestLookup {
        let manifestURL = rootURL.appendingPathComponent(dropManifestFilename)
        // Distinguish "manifest is absent" (no `.chronoframe_drop_manifest.json`
        // → fall back to filesystem walk) from "manifest is present but
        // unreadable / undecodable" (surface a DirectoryIssue so the
        // user gets a real diagnosis instead of a silent empty result).
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            return .absent
        }
        do {
            let data = try Data(contentsOf: manifestURL)
            let manifest = try JSONDecoder().decode(DropManifest.self, from: data)
            return .present(manifest)
        } catch {
            return .corrupt(manifestURL, error)
        }
    }

    #if DEBUG
    nonisolated(unsafe) public static var isICloudDatalessProvider: @Sendable (URL) -> Bool = { url in
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values.ubiquitousItemDownloadingStatus {
                return status == .notDownloaded
            }
        } catch {}
        return false
    }
    #endif

    private static func isICloudDataless(_ url: URL) -> Bool {
        #if DEBUG
        return isICloudDatalessProvider(url)
        #else
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values.ubiquitousItemDownloadingStatus {
                return status == .notDownloaded
            }
        } catch {}
        return false
        #endif
    }

    private static func enumerateManifest(
        _ manifest: DropManifest,
        rootURL: URL,
        isCancelled: @Sendable () -> Bool,
        onDirectoryIssue: (@Sendable (DirectoryIssue) -> Void)?,
        visitFilePath: (String) throws -> Void
    ) throws {
        var seen = Set<String>()
        for item in manifest.items {
            try throwIfCancelled(isCancelled)
            let url = URL(fileURLWithPath: item.path).standardizedFileURL
            guard seen.insert(url.path).inserted else { continue }
            if manifest.allowsExternalItems != true,
               !SafePathContainment.isContained(url, in: rootURL) {
                onDirectoryIssue?(DirectoryIssue(
                    path: url.path,
                    message: "Skipped: manifest entry outside source root, package, symlink, or photo library."
                ))
                continue
            }

            // Phase 1 finding #9: apply the same filter the
            // filesystem walk applies to its children. `walk()` only
            // filters CHILDREN — not the root it was given — so
            // without an explicit check here, a manifest entry like
            // `~/Pictures/Photos Library.photoslibrary` (a package /
            // photo library) is descended into and library-internal
            // masters get queued as source files. The documented
            // invariant in AGENTS.md is that traversal must not
            // follow packages or photo libraries.
            if isManifestEntryFiltered(url: url) {
                onDirectoryIssue?(DirectoryIssue(
                    path: url.path,
                    message: "Skipped: drop targets cannot be symlinks, app bundles, packages, or photo libraries."
                ))
                continue
            }

            if item.isDirectory {
                try walk(directoryURL: url, isCancelled: isCancelled, onDirectoryIssue: onDirectoryIssue, visitFilePath: visitFilePath)
            } else if !url.lastPathComponent.hasPrefix("."),
                      MediaLibraryRules.isSupportedMediaFile(path: url.path) {
                if isICloudDataless(url) {
                    continue
                }
                try visitFilePath(url.path)
            }
        }
    }
}
