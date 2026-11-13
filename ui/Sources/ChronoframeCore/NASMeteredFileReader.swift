import Darwin
import Foundation

/// Reads a file once through an injectable POSIX seam, counting every byte, and
/// produces the same identity digest as `FileIdentityHasher` (D-NAS-11).
public struct NASMeteredFileReader: Sendable {
    public struct FileStat: Sendable, Equatable {
        public var isRegularFile: Bool
        public var size: Int64
        public var modificationTime: TimeInterval

        public init(isRegularFile: Bool, size: Int64, modificationTime: TimeInterval) {
            self.isRegularFile = isRegularFile
            self.size = size
            self.modificationTime = modificationTime
        }
    }

    public struct SystemCalls: Sendable {
        /// Returns a descriptor, or -1 with errno set.
        public var open: @Sendable (String) -> Int32
        /// Returns nil on failure.
        public var fstat: @Sendable (Int32) -> FileStat?
        public var read: @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int
        public var close: @Sendable (Int32) -> Void
        /// errno
        public var lastError: @Sendable () -> Int32

        public static let live = SystemCalls(
            open: { path in
                path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
            },
            fstat: { descriptor in
                var status = Darwin.stat()
                guard Darwin.fstat(descriptor, &status) == 0 else { return nil }
                let modificationTime = TimeInterval(status.st_mtimespec.tv_sec)
                    + (TimeInterval(status.st_mtimespec.tv_nsec) / 1_000_000_000)
                return FileStat(
                    isRegularFile: (status.st_mode & S_IFMT) == S_IFREG,
                    size: Int64(status.st_size),
                    modificationTime: modificationTime
                )
            },
            read: { descriptor, buffer, count in
                Darwin.read(descriptor, buffer, count)
            },
            close: { descriptor in
                _ = Darwin.close(descriptor)
            },
            lastError: { errno }
        )

        public init(
            open: @escaping @Sendable (String) -> Int32,
            fstat: @escaping @Sendable (Int32) -> FileStat?,
            read: @escaping @Sendable (Int32, UnsafeMutableRawPointer, Int) -> Int,
            close: @escaping @Sendable (Int32) -> Void,
            lastError: @escaping @Sendable () -> Int32
        ) {
            self.open = open
            self.fstat = fstat
            self.read = read
            self.close = close
            self.lastError = lastError
        }
    }

    public static let chunkByteCount = 1 * 1024 * 1024
    public static let volumeUnavailableErrorCodes: Set<Int32> = [
        ENXIO, ENOTCONN, ETIMEDOUT, ESTALE, ENODEV, EHOSTDOWN, EHOSTUNREACH, ENETDOWN, ENETUNREACH,
    ]

    public var systemCalls: SystemCalls

    public init(systemCalls: SystemCalls = .live) {
        self.systemCalls = systemCalls
    }

    public func hash(
        path: String,
        expectedSize: Int64,
        expectedModificationTime: TimeInterval
    ) -> NASHashOutcome {
        let calls = systemCalls
        let none = NASReadCounters()

        let descriptor = calls.open(path)
        guard descriptor >= 0 else {
            let code = calls.lastError()
            let reason: NASUnresolvedReason = Self.volumeUnavailableErrorCodes.contains(code)
                ? .volumeUnavailable
                : .openFailed
            return .unresolved(reason, errorCode: code, counters: none)
        }
        defer { calls.close(descriptor) }

        guard let pre = calls.fstat(descriptor) else {
            return .unresolved(.readFailed, errorCode: nil, counters: none)
        }
        guard pre.isRegularFile else {
            return .unresolved(.notRegularFile, errorCode: nil, counters: none)
        }
        guard pre.size == expectedSize else {
            return .unresolved(.sizeChangedBeforeRead, errorCode: nil, counters: none)
        }
        guard abs(pre.modificationTime - expectedModificationTime) < 0.001 else {
            return .unresolved(.modificationTimeChanged, errorCode: nil, counters: none)
        }

        var hasher = BLAKE2bHasher()
        hasher.update(Data(String(expectedSize).utf8))
        var buffer = [UInt8](repeating: 0, count: Self.chunkByteCount)
        var bytesRead: Int64 = 0
        var readCalls = 0

        readLoop: while true {
            let count = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return 0 }
                return calls.read(descriptor, base, raw.count)
            }
            readCalls += 1

            if count < 0 {
                let code = calls.lastError()
                if code == EINTR { continue }
                let reason: NASUnresolvedReason = Self.volumeUnavailableErrorCodes.contains(code)
                    ? .volumeUnavailable
                    : .readFailed
                return .unresolved(
                    reason,
                    errorCode: code,
                    counters: NASReadCounters(bytesRead: bytesRead, readCalls: readCalls)
                )
            }
            if count == 0 { break readLoop }

            bytesRead += Int64(count)
            buffer.withUnsafeBytes { raw in
                hasher.update(UnsafeRawBufferPointer(start: raw.baseAddress, count: count))
            }
            if bytesRead > expectedSize {
                return .unresolved(
                    .bytesConsumedMismatch,
                    errorCode: nil,
                    counters: NASReadCounters(bytesRead: bytesRead, readCalls: readCalls)
                )
            }
        }

        let counters = NASReadCounters(bytesRead: bytesRead, readCalls: readCalls)
        guard bytesRead == expectedSize else {
            return .unresolved(.bytesConsumedMismatch, errorCode: nil, counters: counters)
        }

        guard let post = calls.fstat(descriptor) else {
            return .unresolved(.readFailed, errorCode: nil, counters: counters)
        }
        guard post.size == expectedSize else {
            return .unresolved(.sizeChangedDuringRead, errorCode: nil, counters: counters)
        }
        guard abs(post.modificationTime - pre.modificationTime) < 0.001 else {
            return .unresolved(.modificationTimeChanged, errorCode: nil, counters: counters)
        }

        return .hashed(
            FileIdentity(size: expectedSize, digest: hasher.finalizeHexDigest()),
            modificationTime: post.modificationTime,
            counters: counters
        )
    }
}
