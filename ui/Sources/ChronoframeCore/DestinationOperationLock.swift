import Darwin
import Foundation

public struct DestinationOperationDiagnostic: Codable, Sendable, Equatable {
    public var processID: Int32
    public var surface: String
    public var operation: String
    public var startedAt: Date

    public init(processID: Int32 = getpid(), surface: String, operation: String, startedAt: Date = Date()) {
        self.processID = processID
        self.surface = surface
        self.operation = operation
        self.startedAt = startedAt
    }
}

public struct DestinationBusyError: LocalizedError, Sendable, Equatable {
    public let diagnostic: DestinationOperationDiagnostic?

    public init(diagnostic: DestinationOperationDiagnostic?) {
        self.diagnostic = diagnostic
    }

    public var errorDescription: String? {
        guard let diagnostic else {
            return "Another Chronoframe operation is already using this destination. Wait for it to finish, then try again."
        }
        return "Chronoframe is already running \(diagnostic.operation) from \(diagnostic.surface) for this destination. Wait for it to finish, then try again."
    }
}

/// The lock file, or the folder holding it, is a link or special file rather
/// than Chronoframe's own regular lock file. The lock refuses to open or
/// truncate it so a planted link can never redirect that write elsewhere.
public struct DestinationLockUnsafeError: LocalizedError, Sendable, Equatable {
    public let itemName: String

    public init(itemName: String) {
        self.itemName = itemName
    }

    public var errorDescription: String? {
        "Chronoframe didn't start because “\(itemName)” is a link or special file where it expected its own lock file. Nothing was changed. Remove “\(itemName)” or choose a different destination, then try again."
    }
}

public final class DestinationOperationLease: @unchecked Sendable {
    private let stateLock = NSLock()
    private var descriptor: Int32?

    fileprivate init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    public func release() {
        stateLock.lock()
        guard let descriptor else {
            stateLock.unlock()
            return
        }
        self.descriptor = nil
        stateLock.unlock()
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
    }

    deinit { release() }
}

public enum DestinationOperationLock {
    public static let filename = ".chronoframe-operation.lock"

    #if DEBUG
    /// Test seam: override remote-volume detection so tests don't need a real
    /// network mount. Production leaves this nil and queries the live volume.
    public nonisolated(unsafe) static var isRemoteVolumeProvider: (@Sendable (URL) -> Bool)?
    #endif

    /// Whether `destinationRoot` lives on a non-local (network) volume. The
    /// cross-process `flock` lock only reliably guards same-machine access; on
    /// SMB/AFP mounts two machines could both proceed. Callers use this to warn
    /// the user — it does not change locking behavior. An unreadable or unknown
    /// volume attribute is treated as **local** so the app never warns spuriously.
    public static func isRemoteVolume(_ destinationRoot: URL) -> Bool {
        #if DEBUG
        if let isRemoteVolumeProvider {
            return isRemoteVolumeProvider(destinationRoot)
        }
        #endif
        let values = try? destinationRoot.resourceValues(forKeys: [.volumeIsLocalKey])
        return values?.volumeIsLocal == false
    }

    public static func acquire(
        destinationRoot: URL,
        surface: String,
        operation: String
    ) throws -> DestinationOperationLease {
        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        return try acquire(
            lockFileURL: logsDirectory.appendingPathComponent(filename),
            surface: surface,
            operation: operation
        )
    }

    /// Acquire the exclusive operation lock at an explicit lock-file location,
    /// creating only the lock file's parent directory. Callers that must not write
    /// into the protected root — Library Guardian's read-only scrub/mirror against a
    /// library whose bytes stay untouched — point this at an Application Support path
    /// keyed by the library's identity instead of `<root>/.organize_logs`. The
    /// `destinationRoot`-based overload above preserves the historical in-root
    /// location so organize/dedupe keep coordinating through the same file.
    public static func acquire(
        lockFileURL: URL,
        surface: String,
        operation: String
    ) throws -> DestinationOperationLease {
        let directoryURL = lockFileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        } catch {
            // `createDirectory` throws here when the parent path already
            // exists as something other than a directory (a FIFO or a
            // regular file, for example). `lstat` — not `stat` — so a
            // symlink parent is also treated as unsafe rather than silently
            // resolved; report it the same way as the other unsafe-parent
            // cases below instead of surfacing Foundation's raw error text.
            var directoryStatus = stat()
            if lstat(directoryURL.path, &directoryStatus) == 0,
               (directoryStatus.st_mode & S_IFMT) != S_IFDIR {
                throw DestinationLockUnsafeError(itemName: directoryURL.lastPathComponent)
            }
            throw error
        }
        // The lock lives in a user-selected folder, so neither it nor its
        // parent folder is trusted: open both without following links, then
        // require the lock to be a regular file with no other hard links
        // before it is truncated and rewritten below.
        let directoryDescriptor = directoryURL.path.withCString {
            Darwin.open($0, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        }
        guard directoryDescriptor >= 0 else {
            let openError = errno
            if openError == ELOOP || openError == ENOTDIR {
                throw DestinationLockUnsafeError(itemName: directoryURL.lastPathComponent)
            }
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(openError),
                userInfo: [NSLocalizedDescriptionKey: "Chronoframe could not open the destination operation lock."]
            )
        }
        defer { _ = Darwin.close(directoryDescriptor) }

        let lockName = lockFileURL.lastPathComponent
        let descriptor = lockName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                S_IRUSR | S_IWUSR
            )
        }
        guard descriptor >= 0 else {
            let openError = errno
            if openError == ELOOP || openError == EISDIR {
                throw DestinationLockUnsafeError(itemName: lockName)
            }
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(openError),
                userInfo: [NSLocalizedDescriptionKey: "Chronoframe could not open the destination operation lock."]
            )
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink <= 1
        else {
            _ = Darwin.close(descriptor)
            throw DestinationLockUnsafeError(itemName: lockName)
        }

        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            let lockError = errno
            let diagnostic = readDiagnosticTwice(descriptor: descriptor)
            _ = Darwin.close(descriptor)
            if lockError == EWOULDBLOCK || lockError == EAGAIN {
                throw DestinationBusyError(diagnostic: diagnostic)
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(lockError))
        }

        do {
            let diagnostic = DestinationOperationDiagnostic(surface: surface, operation: operation)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(diagnostic)
            guard ftruncate(descriptor, 0) == 0, lseek(descriptor, 0, SEEK_SET) >= 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            try data.withUnsafeBytes { rawBuffer in
                var written = 0
                while written < rawBuffer.count {
                    let result = Darwin.write(
                        descriptor,
                        rawBuffer.baseAddress!.advanced(by: written),
                        rawBuffer.count - written
                    )
                    guard result > 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                    written += result
                }
            }
            guard fsync(descriptor) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            return DestinationOperationLease(descriptor: descriptor)
        } catch {
            _ = flock(descriptor, LOCK_UN)
            _ = Darwin.close(descriptor)
            throw error
        }
    }

    private static func readDiagnosticTwice(descriptor: Int32) -> DestinationOperationDiagnostic? {
        if let diagnostic = readDiagnostic(descriptor: descriptor) { return diagnostic }
        usleep(10_000)
        return readDiagnostic(descriptor: descriptor)
    }

    private static func readDiagnostic(descriptor: Int32) -> DestinationOperationDiagnostic? {
        guard lseek(descriptor, 0, SEEK_SET) >= 0 else { return nil }
        var bytes = [UInt8](repeating: 0, count: 8 * 1024)
        let count = bytes.withUnsafeMutableBytes { buffer in
            Darwin.read(descriptor, buffer.baseAddress, buffer.count)
        }
        guard count > 0 else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(DestinationOperationDiagnostic.self, from: Data(bytes.prefix(count)))
    }
}
