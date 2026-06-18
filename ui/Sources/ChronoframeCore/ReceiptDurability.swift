import Foundation
import Darwin

public enum ReceiptDurability {
    public static func durablyWrite(data: Data, to url: URL) throws {
        let fileManager = FileManager.default
        let tempURL = url.appendingPathExtension("tmp")
        
        // Write the data to a temporary file
        try data.write(to: tempURL)
        
        // Perform F_FULLFSYNC on the temporary file descriptor
        let fd = tempURL.path.withCString { pointer in
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
