import Foundation
import Darwin

public enum ReceiptDurability {
    public static func durablyWrite(data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        // Receipts live in a user-selected destination, so a predictable temp
        // name could already hold a planted link. Create a uniquely named temp
        // file exclusively (O_EXCL never follows or reuses an existing entry)
        // and write and flush through that one descriptor.
        let tempURL = url.appendingPathExtension("\(UUID().uuidString).tmp")
        let fd = tempURL.path.withCString { pointer in
            open(pointer, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)
        }
        guard fd >= 0 else {
            let code = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
            )
        }
        defer {
            close(fd)
        }

        do {
            try data.withUnsafeBytes { rawBuffer in
                var written = 0
                while written < rawBuffer.count {
                    let result = Darwin.write(fd, rawBuffer.baseAddress!.advanced(by: written), rawBuffer.count - written)
                    guard result > 0 else {
                        let code = errno
                        throw NSError(
                            domain: NSPOSIXErrorDomain,
                            code: Int(code),
                            userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
                        )
                    }
                    written += result
                }
            }

            // Perform F_FULLFSYNC on the temporary file descriptor
            guard fcntl(fd, F_FULLFSYNC) == 0 else {
                let code = errno
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(code),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
                )
            }
        } catch {
            try? fileManager.removeItem(at: tempURL)
            throw error
        }
        
        // Atomic rename
        let renameResult = tempURL.withUnsafeFileSystemRepresentation { sourcePointer in
            url.withUnsafeFileSystemRepresentation { destinationPointer in
                guard let sourcePointer, let destinationPointer else { return Int32(-1) }
                return Darwin.rename(sourcePointer, destinationPointer)
            }
        }
        if renameResult != 0 {
            let code = errno
            try? fileManager.removeItem(at: tempURL)
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
            )
        }
        
        // Perform F_FULLFSYNC on the parent directory
        let parentPath = (url.path as NSString).deletingLastPathComponent
        if !parentPath.isEmpty {
            try fsyncDirectory(atPath: parentPath)
        }
    }
    
    public static func fsyncFile(atPath path: String) throws {
        let fd = path.withCString { pointer in
            open(pointer, O_RDWR | O_CLOEXEC)
        }
        guard fd >= 0 else {
            let code = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
            )
        }
        defer {
            close(fd)
        }
        
        guard fcntl(fd, F_FULLFSYNC) == 0 else {
            let code = errno
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(code),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
            )
        }
    }
    
    public static func fsyncDirectory(atPath path: String) throws {
        let fd = path.withCString { pointer in
            open(pointer, O_RDONLY | O_CLOEXEC)
        }
        if fd >= 0 {
            defer {
                close(fd)
            }
            _ = fcntl(fd, F_FULLFSYNC)
        }
    }
}
