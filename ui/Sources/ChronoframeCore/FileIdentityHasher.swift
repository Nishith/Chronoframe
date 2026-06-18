import Darwin
import Foundation

public struct ProcessedFileIdentity: Equatable, Sendable {
    public var identity: FileIdentity?
    public var size: Int64
    public var modificationTime: TimeInterval
    public var wasHashed: Bool

    public init(
        identity: FileIdentity?,
        size: Int64,
        modificationTime: TimeInterval,
        wasHashed: Bool
    ) {
        self.identity = identity
        self.size = size
        self.modificationTime = modificationTime
        self.wasHashed = wasHashed
    }
}

public struct FileIdentityHasher: Sendable {
    // 1 MiB chunk balances throughput (BLAKE2b saturates well under this)
    // with peak working-memory per concurrent hash. An 8 MiB buffer per
    // in-flight hash pushed RSS during large-tree planning considerably.
    public static let chunkByteCount = 1 * 1024 * 1024

    public init() {}

    public func hashIdentity(at url: URL, knownSize: Int64? = nil) throws -> FileIdentity {
        let size: Int64
        if let knownSize {
            size = knownSize
        } else {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        }
        let digest = try hashDigest(at: url, size: size)
        return FileIdentity(size: size, digest: digest)
    }

    public func processFile(at path: String, cachedRecord: FileCacheRecord?) -> ProcessedFileIdentity {
        let url = URL(fileURLWithPath: path)

        if isICloudDataless(url) {
            return ProcessedFileIdentity(identity: nil, size: 0, modificationTime: 0, wasHashed: false)
        }

        guard let fileMetadata = fileMetadata(atPath: path) else {
            return ProcessedFileIdentity(identity: nil, size: 0, modificationTime: 0, wasHashed: false)
        }

        if let cachedRecord,
           cachedRecord.size == fileMetadata.size,
           abs(cachedRecord.modificationTime - fileMetadata.modificationTime) < 0.001 {
            return ProcessedFileIdentity(
                identity: cachedRecord.identity,
                size: fileMetadata.size,
                modificationTime: fileMetadata.modificationTime,
                wasHashed: false
            )
        }

        do {
            let identity = try hashIdentity(at: url, knownSize: fileMetadata.size)
            return ProcessedFileIdentity(
                identity: identity,
                size: fileMetadata.size,
                modificationTime: fileMetadata.modificationTime,
                wasHashed: true
            )
        } catch {
            return ProcessedFileIdentity(
                identity: nil,
                size: 0,
                modificationTime: 0,
                wasHashed: false
            )
        }
    }

    private func hashDigest(at url: URL, size: Int64) throws -> String {
        let path = url.path
        // FileHandle.readData can raise Objective-C exceptions on read failures,
        // which Swift cannot catch. POSIX read keeps failures in the throwing path.
        let descriptor = path.withCString { pointer in
            Darwin.open(pointer, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard descriptor >= 0 else {
            throw Self.posixReadError(code: errno, path: path, operation: "open")
        }
        defer {
            _ = Darwin.close(descriptor)
        }

        return try Self.hashDigest(descriptor: descriptor, size: size, path: path)
    }

    /// Hash the contents of an already-open file descriptor. The descriptor
    /// must be positioned at the start (callers typically open with
    /// `O_RDONLY|O_NOFOLLOW|O_CLOEXEC` immediately before calling). Used by
    /// `RevertExecutor.safeUnlink` so the hash and the destructive unlink
    /// both operate on the *same* inode — closing the TOCTOU race where a
    /// path-based remove could be redirected by a symlink swap between
    /// hashing and unlinking.
    public func hashIdentity(descriptor: Int32, size: Int64) throws -> FileIdentity {
        let digest = try Self.hashDigest(descriptor: descriptor, size: size, path: "<fd:\(descriptor)>")
        return FileIdentity(size: size, digest: digest)
    }

    private static func hashDigest(descriptor: Int32, size: Int64, path: String) throws -> String {
        var hasher = BLAKE2bHasher()
        hasher.update(Data(String(size).utf8))
        var buffer = [UInt8](repeating: 0, count: chunkByteCount)

        while true {
            let readResult = readChunk(from: descriptor, into: &buffer)
            if let errorCode = readResult.errorCode {
                throw posixReadError(code: errorCode, path: path, operation: "read")
            }
            if readResult.byteCount == 0 {
                break
            }

            buffer.withUnsafeBytes { rawBuffer in
                hasher.update(UnsafeRawBufferPointer(
                    start: rawBuffer.baseAddress,
                    count: readResult.byteCount
                ))
            }
        }

        return hasher.finalizeHexDigest()
    }

    private static func readChunk(
        from descriptor: Int32,
        into buffer: inout [UInt8]
    ) -> (byteCount: Int, errorCode: Int32?) {
        while true {
            let byteCount = buffer.withUnsafeMutableBytes { rawBuffer -> Int in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return 0
                }
                return Darwin.read(descriptor, baseAddress, rawBuffer.count)
            }

            if byteCount >= 0 {
                return (byteCount, nil)
            }

            let errorCode = errno
            if errorCode == EINTR {
                continue
            }
            return (0, errorCode)
        }
    }

    private static func posixReadError(code: Int32, path: String, operation: String) -> NSError {
        let message = String(cString: strerror(code))
        return NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSFilePathErrorKey: path,
                NSLocalizedDescriptionKey: "Could not \(operation) file: \(message)",
            ]
        )
    }

    private func fileMetadata(atPath path: String) -> (size: Int64, modificationTime: TimeInterval)? {
        var fileStatus = stat()
        let result = path.withCString { pointer in
            lstat(pointer, &fileStatus)
        }
        guard result == 0 else {
            return nil
        }
        guard (fileStatus.st_mode & S_IFMT) == S_IFREG else {
            return nil
        }

        let modificationTime = TimeInterval(fileStatus.st_mtimespec.tv_sec)
            + (TimeInterval(fileStatus.st_mtimespec.tv_nsec) / 1_000_000_000)
        return (Int64(fileStatus.st_size), modificationTime)
    }

    #if DEBUG
    public var isICloudDatalessProvider: @Sendable (URL) -> Bool = { url in
        do {
            let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let status = values.ubiquitousItemDownloadingStatus {
                return status == .notDownloaded
            }
        } catch {}
        return false
    }
    #endif

    private func isICloudDataless(_ url: URL) -> Bool {
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
}
