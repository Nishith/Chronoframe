import Darwin
import Foundation

public struct NASStatfsSnapshot: Sendable, Equatable {
    public var fileSystemType: String   // f_fstypename
    public var mountedOn: String        // f_mntonname
    public var mountedFrom: String      // f_mntfromname
    public var flags: UInt32            // f_flags
    public var fileSystemID: UInt64     // packed as in C-01

    public init(fileSystemType: String, mountedOn: String, mountedFrom: String, flags: UInt32, fileSystemID: UInt64) {
        self.fileSystemType = fileSystemType
        self.mountedOn = mountedOn
        self.mountedFrom = mountedFrom
        self.flags = flags
        self.fileSystemID = fileSystemID
    }
}

public struct NASVolumeClassifier: Sendable {
    public static let remoteFileSystemTypes: Set<String> = ["smbfs", "afpfs", "nfs", "webdav", "cifs", "ftp"]

    public var statfs: @Sendable (String) -> NASStatfsSnapshot?

    public init(statfs: @escaping @Sendable (String) -> NASStatfsSnapshot?) {
        self.statfs = statfs
    }

    public static let live = NASVolumeClassifier { path in
        var buffer = Darwin.statfs()
        guard callStatfs(path, &buffer) == 0 else { return nil }
        let low = UInt64(UInt32(bitPattern: buffer.f_fsid.val.0))
        let high = UInt64(UInt32(bitPattern: buffer.f_fsid.val.1))
        return NASStatfsSnapshot(
            fileSystemType: string(fromCChars: &buffer.f_fstypename),
            mountedOn: string(fromCChars: &buffer.f_mntonname),
            mountedFrom: string(fromCChars: &buffer.f_mntfromname),
            flags: buffer.f_flags,
            fileSystemID: low | (high << 32)
        )
    }

    public func classify(_ url: URL) -> NASVolumeObservation {
        var path = url.standardizedFileURL.path
        while true {
            if let snapshot = statfs(path) {
                return observation(from: snapshot, observedPath: path)
            }
            let parent = URL(fileURLWithPath: path).deletingLastPathComponent().path
            if path == "/" || parent == path || parent.isEmpty {
                return .unknown(observedPath: url.path)
            }
            path = parent
        }
    }

    public static func parseMountedFrom(_ value: String, fileSystemType: String) -> (serverHost: String?, shareName: String?) {
        if value.hasPrefix("//") {
            let remainder = value.dropFirst(2)
            let authority: Substring
            var rawShare: Substring = ""
            if let slash = remainder.firstIndex(of: "/") {
                authority = remainder[remainder.startIndex..<slash]
                rawShare = remainder[remainder.index(after: slash)...]
            } else {
                authority = remainder
            }

            var host = authority
            if let at = host.lastIndex(of: "@") {
                host = host[host.index(after: at)...]
            }
            if let semicolon = host.lastIndex(of: ";") {
                host = host[host.index(after: semicolon)...]
            }
            if let colon = host.firstIndex(of: ":") {
                host = host[host.startIndex..<colon]
            }
            let serverHost = host.isEmpty ? nil : host.lowercased()

            var share = String(rawShare)
            share = share.removingPercentEncoding ?? share
            while share.hasSuffix("/") { share.removeLast() }
            return (serverHost, share.isEmpty ? nil : share)
        }

        if fileSystemType == "nfs", let colon = value.firstIndex(of: ":") {
            let host = value[value.startIndex..<colon]
            var path = value[value.index(after: colon)...]
            if path.hasPrefix("/") { path = path.dropFirst() }
            return (host.isEmpty ? nil : host.lowercased(), path.isEmpty ? nil : String(path))
        }

        return (nil, nil)
    }

    private func observation(from snapshot: NASStatfsSnapshot, observedPath: String) -> NASVolumeObservation {
        let isRemoteType = Self.remoteFileSystemTypes.contains(snapshot.fileSystemType)
        let kind: NASVolumeKind
        if isRemoteType || snapshot.flags & UInt32(MNT_LOCAL) == 0 {
            kind = .remote
        } else {
            kind = .local
        }
        let parsed = isRemoteType
            ? Self.parseMountedFrom(snapshot.mountedFrom, fileSystemType: snapshot.fileSystemType)
            : (serverHost: nil as String?, shareName: nil as String?)
        return NASVolumeObservation(
            kind: kind,
            fileSystemType: snapshot.fileSystemType,
            mountPoint: snapshot.mountedOn,
            serverHost: parsed.serverHost,
            shareName: parsed.shareName,
            fileSystemID: snapshot.fileSystemID,
            observedPath: observedPath
        )
    }
}

private func string<T>(fromCChars tuple: inout T) -> String {
    withUnsafePointer(to: &tuple) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) { String(cString: $0) }
    }
}

/// The C struct and function share the name `statfs`, and `NASVolumeClassifier.statfs`
/// shadows both inside the type, so the system call is made from file scope.
private func callStatfs(_ path: String, _ buffer: inout Darwin.statfs) -> Int32 {
    statfs(path, &buffer)
}
