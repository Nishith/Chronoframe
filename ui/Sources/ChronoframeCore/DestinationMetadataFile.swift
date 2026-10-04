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
        try openRegularFile(
            at: url,
            flags: O_WRONLY | O_APPEND | O_CREAT,
            expecting: nil
        )
    }

    /// Opens an existing record file for reading without following a link. A
    /// path that was swapped for a link, a special file or a file with other
    /// hard links since Chronoframe last wrote it is refused, so its bytes are
    /// never read back as though Chronoframe had written them. `expecting`
    /// additionally pins the file to one seen earlier by `fileID(of:)`.
    public static func openForReading(at url: URL, expecting expectedID: FileID? = nil) throws -> FileHandle {
        try openRegularFile(at: url, flags: O_RDONLY, expecting: expectedID)
    }

    /// Reads a whole record file under the same rules as `openForReading`.
    public static func readContents(at url: URL, expecting expectedID: FileID? = nil) throws -> Data {
        let handle = try openForReading(at: url, expecting: expectedID)
        defer { try? handle.close() }
        return try handle.readToEnd() ?? Data()
    }

    /// Like `readContents`, but a record file that does not exist yet reads as
    /// `nil`. A link, even one that points nowhere, is not "absent": it is refused.
    public static func readContentsIfPresent(at url: URL, expecting expectedID: FileID? = nil) throws -> Data? {
        do {
            return try readContents(at: url, expecting: expectedID)
        } catch let error as NSError where error.domain == NSPOSIXErrorDomain && error.code == Int(ENOENT) {
            return nil
        }
    }

    /// Identifies one file on disk, so a path can be checked to still name the
    /// file Chronoframe opened earlier.
    public struct FileID: Equatable, Sendable {
        fileprivate let device: dev_t
        fileprivate let inode: ino_t
    }

    public static func fileID(of handle: FileHandle) -> FileID? {
        var status = stat()
        guard fstat(handle.fileDescriptor, &status) == 0 else { return nil }
        return FileID(device: status.st_dev, inode: status.st_ino)
    }

    private static func openRegularFile(
        at url: URL,
        flags: Int32,
        expecting expectedID: FileID?
    ) throws -> FileHandle {
        // O_NONBLOCK keeps a FIFO planted at `url` from blocking the open; it
        // is cleared again below once the file is confirmed regular.
        let descriptor = url.path.withCString {
            Darwin.open(
                $0,
                flags | O_CLOEXEC | O_NOFOLLOW | O_NONBLOCK,
                S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH
            )
        }
        guard descriptor >= 0 else {
            let openError = errno
            if openError == ELOOP || openError == EISDIR || openError == ENXIO || openError == EOPNOTSUPP {
                throw DestinationMetadataUnsafeError(itemName: url.lastPathComponent)
            }
            throw posixError(openError, path: url.path)
        }
        var status = stat()
        guard fstat(descriptor, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_nlink <= 1,
              expectedID.map({ $0 == FileID(device: status.st_dev, inode: status.st_ino) }) ?? true
        else {
            _ = Darwin.close(descriptor)
            throw DestinationMetadataUnsafeError(itemName: url.lastPathComponent)
        }
        // O_NONBLOCK was only for the open above; don't leave it on the log's descriptor.
        let handleFlags = fcntl(descriptor, F_GETFL)
        if handleFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, handleFlags & ~O_NONBLOCK)
        }
        return FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
    }

    /// An errno failure carrying the path and a plain system description, in a
    /// shape `UserFacingErrorMessage` maps (and never shows as "error 28").
    static func posixError(_ code: Int32, path: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [
                NSFilePathErrorKey: path,
                NSLocalizedDescriptionKey: String(cString: strerror(code)),
            ]
        )
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
            let openError = errno
            // The name carries a fresh UUID, so an existing entry here was
            // planted rather than left over.
            if openError == EEXIST || openError == ELOOP {
                throw DestinationMetadataUnsafeError(itemName: temporaryURL.lastPathComponent)
            }
            throw posixError(openError, path: temporaryURL.path)
        }
        return (FileHandle(fileDescriptor: descriptor, closeOnDealloc: true), temporaryURL)
    }

    /// Writes a record file by filling a temporary file beside `url` and
    /// renaming it over `url`, so `url` is never seen half-written and a link
    /// planted at `url` is replaced rather than written through. The temporary
    /// file is removed if anything fails.
    public static func replaceFile(at url: URL, writing body: (FileHandle) throws -> Void) throws {
        let (handle, temporaryURL) = try createTemporary(beside: url)
        do {
            try body(handle)
            _ = fcntl(handle.fileDescriptor, F_FULLFSYNC)
            try handle.close()
            try renameReplacing(temporaryURL, with: url)
        } catch {
            try? handle.close()
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// Atomically renames `source` over `destination`.
    static func renameReplacing(_ source: URL, with destination: URL) throws {
        let result: Int32 = source.withUnsafeFileSystemRepresentation { sourcePointer in
            destination.withUnsafeFileSystemRepresentation { destinationPointer in
                guard let sourcePointer, let destinationPointer else { return Int32(-1) }
                return Darwin.rename(sourcePointer, destinationPointer)
            }
        }
        guard result == 0 else {
            throw posixError(errno, path: destination.path)
        }
    }

    /// Removes the temporary files a writer above left behind because the
    /// process died between creating one and renaming it. They carry a random
    /// name, so no later run reuses (and so overwrites) them. Only a regular
    /// file named like one of these temporaries and untouched for `olderThan`
    /// is removed; a transfer spool, receipt, journal, link or directory is never
    /// touched. Returns how many were removed.
    @discardableResult
    public static func removeOrphanedTemporaries(
        in directory: URL,
        olderThan age: TimeInterval = 3600,
        now: Date = Date()
    ) -> Int {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path) else {
            return 0
        }
        var removed = 0
        for name in names {
            let range = NSRange(name.startIndex..<name.endIndex, in: name)
            guard orphanedTemporaryPattern.firstMatch(in: name, range: range) != nil else { continue }
            let path = directory.appendingPathComponent(name).path
            var status = stat()
            guard lstat(path, &status) == 0,
                  (status.st_mode & S_IFMT) == S_IFREG,
                  now.timeIntervalSince1970 - TimeInterval(status.st_mtimespec.tv_sec) >= age
            else { continue }
            if unlink(path) == 0 {
                removed += 1
            }
        }
        return removed
    }

    private static let orphanedTemporaryPattern = try! NSRegularExpression(
        pattern: #"^.+\.(?:json|csv|jsonl)\.[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.tmp$"#
    )

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
