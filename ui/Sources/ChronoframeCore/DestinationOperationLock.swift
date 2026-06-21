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
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let lockURL = logsDirectory.appendingPathComponent(filename)
        let descriptor = lockURL.path.withCString {
            Darwin.open($0, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        }
        guard descriptor >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: "Chronoframe could not open the destination operation lock."]
            )
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
