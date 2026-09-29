import Darwin
import Foundation

/// A file Chronoframe keeps its own records in, inside a user-selected
/// destination, is a link or special file instead. Chronoframe refuses to
/// write through it so a planted link can never redirect that write elsewhere.
public struct DestinationMetadataUnsafeError: LocalizedError, Sendable, Equatable {
    public let itemName: String

    public init(itemName: String) {
        self.itemName = itemName
    }

    public var errorDescription: String? {
        "Chronoframe didn't start because “\(itemName)” in the destination is a link or special file where it keeps its own records. Nothing was changed. Remove “\(itemName)” or choose a different destination, then try again."
    }
}

/// Opens Chronoframe's own record files inside a user-selected destination.
/// The destination is not trusted to hold only what Chronoframe put there, so
/// the file is opened without following a link, and must be a regular file
/// with no other hard links before anything is written to it.
public enum DestinationMetadataFile {
    /// Opens (creating if needed) `url` for appending.
    public static func openForAppending(at url: URL) throws -> FileHandle {
        // O_NONBLOCK keeps a FIFO planted at `url` from blocking the open; it
        // is cleared again below once the file is confirmed regular.
        let descriptor = url.path.withCString {
            Darwin.open(
                $0,
                O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            )
        }
        guard descriptor >= 0 else {
            let openError = errno
            if openError == ELOOP || openError == EISDIR || openError == ENXIO || openError == EOPNOTSUPP {
                throw DestinationMetadataUnsafeError(itemName: url.lastPathComponent)
            }
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(openError),
                userInfo: [NSFilePathErrorKey: url.path]
            )
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink <= 1
        else {
            _ = Darwin.close(descriptor)
            throw DestinationMetadataUnsafeError(itemName: url.lastPathComponent)
        }
        // O_NONBLOCK was only for the open above; don't leave it on the log's descriptor.
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags & ~O_NONBLOCK)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }
}
