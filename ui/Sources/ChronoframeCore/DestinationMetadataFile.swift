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

    /// Creates a uniquely named temporary file beside `url`, to be written and
    /// then renamed over `url`. The name is not predictable and the file is
    /// created `O_EXCL | O_NOFOLLOW` by the same call that opens it, so there is
    /// no gap between creating and opening in which a link could be planted.
    public static func createTemporary(beside url: URL) throws -> (handle: FileHandle, url: URL) {
        let temporaryURL = url.appendingPathExtension("\(UUID().uuidString).tmp")
        let descriptor = temporaryURL.path.withCString {
            Darwin.open(
                $0,
                O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            )
        }
        guard descriptor >= 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSFilePathErrorKey: temporaryURL.path]
            )
        }
        return (FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), temporaryURL)
    }

    /// For files another library opens by path (SQLite). Creates `url` if it is
    /// missing, without following a link, and returns an anchor on the regular
    /// file found there. After the other library has opened the path, call
    /// `Anchor.confirmPathStillRefersToFile()` before anything is written: it
    /// fails if the path now names a different file, a link, or a file with
    /// extra hard links.
    public static func openAnchor(at url: URL) throws -> Anchor {
        let descriptor = url.path.withCString {
            Darwin.open(
                $0,
                O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
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
        return Anchor(url: url, descriptor: descriptor, device: status.st_dev, inode: status.st_ino)
    }

    public final class Anchor {
        private let url: URL
        private let descriptor: Int32
        private let device: dev_t
        private let inode: ino_t

        fileprivate init(url: URL, descriptor: Int32, device: dev_t, inode: ino_t) {
            self.url = url
            self.descriptor = descriptor
            self.device = device
            self.inode = inode
        }

        deinit {
            _ = Darwin.close(descriptor)
        }

        public func confirmPathStillRefersToFile() throws {
            var status = stat()
            guard lstat(url.path, &status) == 0 else {
                throw DestinationMetadataUnsafeError(itemName: url.lastPathComponent)
            }
            guard (status.st_mode & S_IFMT) == S_IFREG,
                  status.st_nlink <= 1,
                  status.st_dev == device,
                  status.st_ino == inode
            else {
                throw DestinationMetadataUnsafeError(itemName: url.lastPathComponent)
            }
        }
    }
}
