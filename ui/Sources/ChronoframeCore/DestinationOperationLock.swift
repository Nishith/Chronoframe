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

public enum NASRemoteLeaseConfiguration {
    /// Set once by the app at launch (NASStartup.configureForApp). Nil in the CLI and in tests unless set.
    public nonisolated(unsafe) static var leaseDirectory: URL?
}

/// A network destination can't be locked per share because the app never configured where the
/// share leases live. The lock refuses (INV-28) rather than run without the lease.
public enum NASShareLeaseError: LocalizedError, Equatable, Sendable {
    case leaseDirectoryNotConfigured(destinationPath: String)

    public var errorDescription: String? {
        "Chronoframe couldn't set up its safeguards for network folders, so it didn't start. Restart Chronoframe and try again. Nothing was changed."
    }
}

public final class DestinationOperationLease: @unchecked Sendable {
    private let stateLock = NSLock()
    private var descriptor: Int32?
    private var companion: DestinationOperationLease?

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
        let companion = self.companion
        self.companion = nil
        stateLock.unlock()
        _ = flock(descriptor, LOCK_UN)
        _ = Darwin.close(descriptor)
        companion?.release()
    }

    fileprivate func attach(companion: DestinationOperationLease?) {
        stateLock.lock()
        self.companion = companion
        stateLock.unlock()
    }

    deinit { release() }
}

public enum DestinationOperationLock {
    public static let filename = ".chronoframe-operation.lock"

    #if DEBUG
    /// Test seam: override remote-volume detection so tests don't need a real
    /// network mount. Production leaves this nil and queries the live volume.
    public nonisolated(unsafe) static var isRemoteVolumeProvider: (@Sendable (URL) -> Bool)?
    /// Test seam: override the volume observation used for the share lease.
    public nonisolated(unsafe) static var volumeClassifierProvider: (@Sendable (URL) -> NASVolumeObservation)?
    /// Test seam: override the share root's file ID lookup (keyed by mount point).
    public nonisolated(unsafe) static var shareRootFileIDProvider: (@Sendable (String) -> UInt64?)?
    #endif

    /// Whether `destinationRoot` lives on a non-local (network) volume. The
    /// cross-process `flock` lock only reliably guards same-machine access; on
    /// SMB/AFP mounts two machines could both proceed. Callers use this to warn
    /// the user. Since NAS v1, `acquire` also classifies the volume and takes a
    /// per-share Application Support lease when it is not local (see
    /// `acquireShareCompanion`). An unreadable or unknown volume attribute is
    /// treated as **local** here so the app never warns spuriously.
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
        let companion = try acquireShareCompanion(
            destinationRoot: destinationRoot,
            surface: surface,
            operation: operation
        )
        do {
            let lease = try acquire(
                lockFileURL: logsDirectory.appendingPathComponent(filename),
                surface: surface,
                operation: operation
            )
            lease.attach(companion: companion)
            return lease
        } catch {
            companion?.release()
            throw error
        }
    }

    /// One lease per network share, held beside the in-root lock. Nil for local
    /// destinations. A network destination with no lease directory configured is refused with
    /// `NASShareLeaseError` before anything is created (INV-28): running without the share
    /// lease would let two Chronoframe processes mutate one share.
    private static func acquireShareCompanion(
        destinationRoot: URL,
        surface: String,
        operation: String
    ) throws -> DestinationOperationLease? {
        let volume: NASVolumeObservation
        #if DEBUG
        if let volumeClassifierProvider {
            volume = volumeClassifierProvider(destinationRoot)
        } else {
            volume = NASVolumeClassifier.live.classify(destinationRoot)
        }
        #else
        volume = NASVolumeClassifier.live.classify(destinationRoot)
        #endif
        guard volume.kind != .local else { return nil }
        guard let leaseDirectory = NASRemoteLeaseConfiguration.leaseDirectory else {
            throw NASShareLeaseError.leaseDirectoryNotConfigured(destinationPath: destinationRoot.path)
        }

        var shareRootFileID: UInt64 = 0
        if !volume.mountPoint.isEmpty {
            #if DEBUG
            if let shareRootFileIDProvider {
                shareRootFileID = shareRootFileIDProvider(volume.mountPoint) ?? 0
            } else {
                shareRootFileID = liveFileID(of: volume.mountPoint)
            }
            #else
            shareRootFileID = liveFileID(of: volume.mountPoint)
            #endif
        }
        let key = NASShareLeaseKey.key(volume: volume, shareRootFileID: shareRootFileID)
        return try acquire(
            lockFileURL: leaseDirectory.appendingPathComponent("\(key).lock"),
            surface: surface,
            operation: operation
        )
    }

    private static func liveFileID(of path: String) -> UInt64 {
        var status = stat()
        guard lstat(path, &status) == 0 else { return 0 }
        return UInt64(status.st_ino)
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
            if lstat(directoryURL.path, &directoryStatus) == 0 {
                if (directoryStatus.st_mode & S_IFMT) != S_IFDIR {
                    throw DestinationLockUnsafeError(itemName: directoryURL.lastPathComponent)
                }
            } else if errno == ENOTDIR || errno == ELOOP {
                // An ancestor of the parent folder — not the parent itself —
                // is a link or special file, so `lstat` on the parent path
                // fails too. Still unsafe, not a raw filesystem error; name
                // the ancestor at fault, not the folder beneath it.
                throw DestinationLockUnsafeError(itemName: unsafeAncestorName(of: directoryURL))
            }
            // Anything else that reaches here and is still Foundation's
            // "already exists" error (a TOCTOU race, or a case the checks
            // above didn't resolve) is unsafe by construction: `createDirectory`
            // only raises it when something is already at this path. Never let
            // that raw NSCocoaErrorDomain error reach the UI.
            let nsError = error as NSError
            if nsError.domain == NSCocoaErrorDomain, nsError.code == NSFileWriteFileExistsError {
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
            // EOPNOTSUPP covers a UNIX domain socket at the lock path:
            // opening one through the filesystem fails this way on Darwin
            // instead of ELOOP/EISDIR, so it needs its own case to be
            // treated as the same "link or special file" condition.
            if openError == ELOOP || openError == EISDIR || openError == EOPNOTSUPP {
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

    /// Nearest ancestor of `directoryURL` that is not a directory (a file, or a
    /// symlink loop), so the message names the item the user must remove.
    private static func unsafeAncestorName(of directoryURL: URL) -> String {
        var ancestor = directoryURL.deletingLastPathComponent()
        while ancestor.path != "/", !ancestor.path.isEmpty {
            var status = stat()
            if stat(ancestor.path, &status) == 0 {
                if (status.st_mode & S_IFMT) != S_IFDIR { return ancestor.lastPathComponent }
            } else if errno == ELOOP {
                return ancestor.lastPathComponent
            }
            ancestor = ancestor.deletingLastPathComponent()
        }
        return directoryURL.lastPathComponent
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
