import Darwin
import Foundation

/// Before an Organize preview or transfer plans anything, proves that a network destination
/// supports the atomic no-replace install INV-28 requires. Local destinations are not probed.
public struct NASCopyDestinationQualifier: Sendable {
    public var classifier: NASVolumeClassifier
    /// Stands in for `renamex_np(from, to, RENAME_EXCL)`; returns 0 or an errno.
    public var exclusiveRename: @Sendable (_ from: String, _ to: String) -> Int32

    public static let live = NASCopyDestinationQualifier(
        classifier: .live,
        exclusiveRename: { from, to in
            let result = from.withCString { fromPointer in
                to.withCString { toPointer in
                    renamex_np(fromPointer, toPointer, UInt32(RENAME_EXCL))
                }
            }
            return result == 0 ? 0 : errno
        }
    )

    /// Copies into a network folder are always verified (INV-28, INV-03). Throws
    /// `NASRemoteCopyError.verificationRequired` when the destination is remote and verification is
    /// off. Classifies only: it writes nothing, so a caller can refuse before taking the lock or
    /// creating any destination file. `TransferExecutor` repeats the check as a backstop.
    public func checkVerification(destinationRoot: URL, verifyCopies: Bool) throws {
        guard !verifyCopies,
              NASRemoteCopyPolicy.resolve(destinationRoot: destinationRoot, classifier: classifier).isRemote
        else { return }
        throw NASRemoteCopyError.verificationRequired(destinationPath: destinationRoot.path)
    }

    /// Same set as `NASProbe.renameUnsupportedCodes`.
    private static let unsupportedCodes: [Int32] = [ENOTSUP, EINVAL, ENOSYS]

    /// Throws `NASCopyDestinationRefusal.noAtomicNoReplace` when the rename reports
    /// ENOTSUP, EINVAL or ENOSYS. Any other create/rename failure is rethrown as its POSIX error.
    /// The caller must hold the destination lock (INV-19).
    public func check(destinationRoot: URL) throws {
        guard NASRemoteCopyPolicy.resolve(destinationRoot: destinationRoot, classifier: classifier).isRemote else {
            return
        }

        let logsPath = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true).path
        if Darwin.mkdir(logsPath, 0o755) != 0, errno != EEXIST {
            throw Self.posixError(errno)
        }

        let token = UUID().uuidString
        let sourcePath = logsPath + "/.chronoframe-rename-check-\(token).src"
        let destinationPath = logsPath + "/.chronoframe-rename-check-\(token).dst"

        let descriptor = Darwin.open(
            sourcePath,
            O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW | O_CLOEXEC,
            0o600
        )
        guard descriptor >= 0 else { throw Self.posixError(errno) }
        _ = Darwin.close(descriptor)

        let code = exclusiveRename(sourcePath, destinationPath)

        // Only names this call created: the source always, the destination only if the rename
        // reported success (it is then the file we just created, renamed).
        Self.removeEmptyRegularFile(atPath: sourcePath)
        if code == 0 {
            Self.removeEmptyRegularFile(atPath: destinationPath)
            return
        }
        if Self.unsupportedCodes.contains(code) {
            throw NASCopyDestinationRefusal.noAtomicNoReplace(path: destinationRoot.path, errorCode: code)
        }
        throw Self.posixError(code)
    }

    private static func posixError(_ code: Int32) -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
    }

    /// `unlink` only after `lstat` confirms a regular file of size 0. Failure is ignored: cleanup
    /// never changes the result.
    private static func removeEmptyRegularFile(atPath path: String) {
        var status = Darwin.stat()
        guard Darwin.lstat(path, &status) == 0,
              (status.st_mode & S_IFMT) == S_IFREG,
              status.st_size == 0
        else { return }
        _ = Darwin.unlink(path)
    }
}
