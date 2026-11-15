import Darwin
import Foundation

public enum NASLibraryIdentity {
    public struct FileStatus: Sendable, Equatable {
        public var fileID: UInt64
        public var isDirectory: Bool
        public var isSymbolicLink: Bool
        public var birthTime: TimeInterval

        public init(fileID: UInt64, isDirectory: Bool, isSymbolicLink: Bool, birthTime: TimeInterval) {
            self.fileID = fileID
            self.isDirectory = isDirectory
            self.isSymbolicLink = isSymbolicLink
            self.birthTime = birthTime
        }
    }

    public static let liveLstat: @Sendable (String) -> FileStatus? = { path in
        var info = Darwin.stat()
        guard Darwin.lstat(path, &info) == 0 else { return nil }
        let mode = info.st_mode & S_IFMT
        let birth = info.st_birthtimespec
        return FileStatus(
            fileID: UInt64(info.st_ino),
            isDirectory: mode == S_IFDIR,
            isSymbolicLink: mode == S_IFLNK,
            birthTime: TimeInterval(birth.tv_sec) + TimeInterval(birth.tv_nsec) / 1_000_000_000
        )
    }

    /// Returns nil when the root can't be lstat'd or is not a directory.
    public static func observe(
        rootURL: URL,
        classifier: NASVolumeClassifier = .live,
        lstat: @Sendable (String) -> FileStatus? = NASLibraryIdentity.liveLstat
    ) -> NASLibraryObservation? {
        let rootPath = rootURL.standardizedFileURL.path
        guard let root = lstat(rootPath), !root.isSymbolicLink, root.isDirectory else { return nil }

        let volume = classifier.classify(rootURL)
        let mountPoint = volume.mountPoint

        let relative: String
        if mountPoint.isEmpty {
            relative = dropLeadingSlash(rootPath)
        } else if rootPath == mountPoint {
            relative = ""
        } else {
            let prefix = mountPoint.hasSuffix("/") ? mountPoint : mountPoint + "/"
            if rootPath.hasPrefix(prefix) {
                relative = String(rootPath.dropFirst(prefix.count))
            } else {
                relative = dropLeadingSlash(rootPath)
            }
        }

        let shareRootFileID: UInt64
        if mountPoint.isEmpty {
            shareRootFileID = 0
        } else {
            shareRootFileID = lstat(mountPoint)?.fileID ?? 0
        }

        return NASLibraryObservation(
            volume: volume,
            rootRelativePath: relative.precomposedStringWithCanonicalMapping,
            rootFileID: root.fileID,
            shareRootFileID: shareRootFileID,
            rootCreationTime: root.birthTime > 0 ? root.birthTime : nil
        )
    }

    public static func compare(recorded: NASLibraryObservation, observed: NASLibraryObservation) -> NASIdentityMatch {
        var mismatches: [NASIdentityMismatchReason] = []
        var ambiguities: [NASIdentityMismatchReason] = []

        if observed.volume.kind != .remote {
            mismatches.append(.notRemote)
        }

        let recordedShare = recorded.volume.shareName
        let observedShare = observed.volume.shareName
        if recordedShare == nil || observedShare == nil {
            ambiguities.append(.missingShareName)
        }

        if recorded.volume.fileSystemType != observed.volume.fileSystemType {
            mismatches.append(.fileSystemTypeChanged)
        }

        if let recordedShare, let observedShare, recordedShare.lowercased() != observedShare.lowercased() {
            mismatches.append(.shareNameChanged)
        }

        if normalizedPath(recorded.rootRelativePath) != normalizedPath(observed.rootRelativePath) {
            mismatches.append(.rootRelativePathChanged)
        }

        if recorded.rootFileID != observed.rootFileID {
            mismatches.append(.rootFileIDChanged)
        }

        if recorded.shareRootFileID != observed.shareRootFileID,
           recorded.shareRootFileID != 0, observed.shareRootFileID != 0 {
            mismatches.append(.shareRootFileIDChanged)
        }

        if let recordedTime = recorded.rootCreationTime,
           let observedTime = observed.rootCreationTime,
           abs(recordedTime - observedTime) > 1.0 {
            mismatches.append(.rootCreationTimeChanged)
        }

        if let recordedHost = recorded.volume.serverHost,
           let observedHost = observed.volume.serverHost,
           recordedHost != observedHost {
            ambiguities.append(.serverHostChanged)
        }

        if !mismatches.isEmpty { return .mismatch(mismatches) }
        if !ambiguities.isEmpty { return .ambiguous(ambiguities) }
        if recorded.volume.mountPoint == observed.volume.mountPoint { return .same }
        return .remounted(newMountPoint: observed.volume.mountPoint)
    }

    private static func normalizedPath(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func dropLeadingSlash(_ path: String) -> String {
        path.hasPrefix("/") ? String(path.dropFirst()) : path
    }
}

public enum NASShareLeaseKey {
    /// 32 lowercase hex characters: the first 32 of BLAKE2bHasher's hex digest of
    /// "v1|<fileSystemType>|<lowercased shareName, or "fsid:<fileSystemID>" when shareName is nil>|<shareRootFileID>".
    /// Server host is deliberately excluded so DNS/IP aliases of one share collide (safe over-serialization).
    public static func key(volume: NASVolumeObservation, shareRootFileID: UInt64) -> String {
        let share = volume.shareName?.lowercased() ?? "fsid:\(volume.fileSystemID)"
        var hasher = BLAKE2bHasher()
        hasher.update(Data("v1|\(volume.fileSystemType)|\(share)|\(shareRootFileID)".utf8))
        return String(hasher.finalizeHexDigest().prefix(32))
    }
}
