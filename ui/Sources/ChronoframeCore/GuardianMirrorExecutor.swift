import Darwin
import Foundation

// MARK: - Guardian verified-mirror executor (Phase 2)
//
// Writes the copies in a `GuardianMirrorPlan` into the mirror as verified copies,
// and nothing else. The safety rules it enforces at execution time:
//
//   * copy only from a currently-verified primary — the primary is re-hashed
//     immediately before each copy and must still equal the trusted identity the
//     plan recorded; any mismatch/unreadable blocks that item (the existing mirror
//     copy is preserved);
//   * verified copy — write to a temp file, F_FULLFSYNC it, re-hash it against the
//     expected identity, then atomically rename into place with RENAME_EXCL (never
//     overwrites);
//   * quarantine, don't erase — a divergent mirror copy is moved into a mirror-side
//     quarantine before its replacement is installed, so a recoverable copy is kept;
//   * the primary library is never written — only the mirror root is mutated, under
//     the mirror's own cross-process lock.

public enum GuardianMirrorExecutorError: LocalizedError, Sendable, Equatable {
    case verificationFailed(String)
    case renameFailed(String)

    public var errorDescription: String? {
        switch self {
        case let .verificationFailed(path):
            return "Chronoframe could not verify the mirrored copy of \(path), so it did not finalize it. Your library was not changed."
        case let .renameFailed(path):
            return "Chronoframe could not finalize the mirrored copy of \(path). Your library was not changed."
        }
    }
}

public struct GuardianMirrorReceipt: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case pending, completed, aborted }

    public var version: Int
    public var status: Status
    public var createdAt: Date
    public var libraryRoot: String
    public var mirrorRoot: String
    public var copied: [String]
    public var quarantinedDivergent: [String]
    public var blocked: [GuardianMirrorBlock]

    public init(
        version: Int = 1,
        status: Status,
        createdAt: Date,
        libraryRoot: String,
        mirrorRoot: String,
        copied: [String] = [],
        quarantinedDivergent: [String] = [],
        blocked: [GuardianMirrorBlock] = []
    ) {
        self.version = version
        self.status = status
        self.createdAt = createdAt
        self.libraryRoot = libraryRoot
        self.mirrorRoot = mirrorRoot
        self.copied = copied
        self.quarantinedDivergent = quarantinedDivergent
        self.blocked = blocked
    }
}

public struct GuardianMirrorExecutionResult: Equatable, Sendable {
    public var copied: [String]
    public var quarantinedDivergent: [String]
    public var blockedAtCommit: [GuardianMirrorBlock]
    public var receiptURL: URL?

    public init(
        copied: [String],
        quarantinedDivergent: [String],
        blockedAtCommit: [GuardianMirrorBlock],
        receiptURL: URL?
    ) {
        self.copied = copied
        self.quarantinedDivergent = quarantinedDivergent
        self.blockedAtCommit = blockedAtCommit
        self.receiptURL = receiptURL
    }
}

public struct GuardianMirrorExecutor: Sendable {
    /// Directory name for quarantined divergent mirror copies, kept inside the mirror.
    public static let quarantineDirectoryName = ".guardian_quarantine"

    private let hasher: FileIdentityHasher

    public init(hasher: FileIdentityHasher = FileIdentityHasher()) {
        self.hasher = hasher
    }

    /// Execute `plan`. `stateDirectory` is the Application Support directory where
    /// the receipt is written (never inside the library). The mirror root is locked
    /// for the duration; the library is only read.
    public func execute(
        plan: GuardianMirrorPlan,
        libraryRoot: URL,
        mirrorRoot: URL,
        stateDirectory: URL,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false }
    ) throws -> GuardianMirrorExecutionResult {
        let lease = try DestinationOperationLock.acquire(
            destinationRoot: mirrorRoot,
            surface: "app",
            operation: "guardian-mirror"
        )
        defer { lease.release() }

        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let receiptURL = stateDirectory.appendingPathComponent(
            "guardian_mirror_receipt_\(Self.timestamp(now))_\(UUID().uuidString).json"
        )

        var receipt = GuardianMirrorReceipt(
            status: .pending,
            createdAt: now,
            libraryRoot: libraryRoot.path,
            mirrorRoot: mirrorRoot.path,
            blocked: plan.blocked
        )
        try writeReceipt(receipt, to: receiptURL)

        var copied: [String] = []
        var quarantined: [String] = []
        var blockedAtCommit: [GuardianMirrorBlock] = []

        for copy in plan.copies {
            if isCancelled() { break }
            let primaryURL = libraryRoot.appendingPathComponent(copy.relativePath)
            let mirrorURL = mirrorRoot.appendingPathComponent(copy.relativePath)

            // Commit-time verification: the primary must STILL be the verified,
            // trusted file the plan recorded. Anything else preserves the mirror.
            guard let currentPrimary = try? hasher.hashIdentity(at: primaryURL),
                  currentPrimary == copy.expectedIdentity else {
                blockedAtCommit.append(
                    GuardianMirrorBlock(relativePath: copy.relativePath, reason: .primaryNotVerified)
                )
                continue
            }

            do {
                if copy.kind == .replaceDivergent,
                   FileManager.default.fileExists(atPath: mirrorURL.path) {
                    try quarantineDivergentMirror(
                        at: mirrorURL,
                        mirrorRoot: mirrorRoot,
                        relativePath: copy.relativePath,
                        now: now
                    )
                    quarantined.append(copy.relativePath)
                }
                try verifiedCopy(from: primaryURL, to: mirrorURL, expected: copy.expectedIdentity)
                copied.append(copy.relativePath)
            } catch {
                // The library is never touched; the mirror copy is simply not
                // installed (a quarantined predecessor, if any, is retained).
                blockedAtCommit.append(
                    GuardianMirrorBlock(relativePath: copy.relativePath, reason: .primaryNotVerified)
                )
            }
        }

        receipt.status = .completed
        receipt.copied = copied
        receipt.quarantinedDivergent = quarantined
        receipt.blocked = plan.blocked + blockedAtCommit
        try writeReceipt(receipt, to: receiptURL)

        return GuardianMirrorExecutionResult(
            copied: copied,
            quarantinedDivergent: quarantined,
            blockedAtCommit: blockedAtCommit,
            receiptURL: receiptURL
        )
    }

    // MARK: - Verified copy

    private func verifiedCopy(from source: URL, to target: URL, expected: FileIdentity) throws {
        let targetDirectory = target.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true)
        let temporaryURL = targetDirectory.appendingPathComponent(".guardian_tmp_\(UUID().uuidString)")

        do {
            try FileManager.default.copyItem(at: source, to: temporaryURL)
            try Self.fullFsync(atPath: temporaryURL.path)
            let identity = try hasher.hashIdentity(at: temporaryURL)
            guard identity == expected else {
                try? FileManager.default.removeItem(at: temporaryURL)
                throw GuardianMirrorExecutorError.verificationFailed(target.path)
            }
            try Self.atomicRenameNoOverwrite(from: temporaryURL.path, to: target.path)
        } catch {
            try? FileManager.default.removeItem(at: temporaryURL)
            throw error
        }
    }

    /// Move a divergent mirror copy into the mirror-side quarantine, preserving its
    /// relative layout, so a potentially recoverable copy is never erased.
    private func quarantineDivergentMirror(
        at mirrorURL: URL,
        mirrorRoot: URL,
        relativePath: String,
        now: Date
    ) throws {
        let quarantineRoot = mirrorRoot
            .appendingPathComponent(Self.quarantineDirectoryName, isDirectory: true)
            .appendingPathComponent(Self.timestamp(now), isDirectory: true)
        let destination = quarantineRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: mirrorURL, to: destination)
    }

    // MARK: - Low-level

    private func writeReceipt(_ receipt: GuardianMirrorReceipt, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        let data = try encoder.encode(receipt)
        let temporaryURL = url.appendingPathExtension("tmp")
        try data.write(to: temporaryURL, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: url)
    }

    private static func fullFsync(atPath path: String) throws {
        let descriptor = open(path, O_RDWR)
        guard descriptor >= 0 else { throw posixError() }
        defer { close(descriptor) }
        // F_FULLFSYNC flushes to the storage device on macOS, unlike fsync().
        guard fcntl(descriptor, F_FULLFSYNC) == 0 else { throw posixError() }
    }

    private static func atomicRenameNoOverwrite(from sourcePath: String, to destinationPath: String) throws {
        let result = sourcePath.withCString { sourcePointer in
            destinationPath.withCString { destinationPointer in
                renamex_np(sourcePointer, destinationPointer, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else { throw GuardianMirrorExecutorError.renameFailed(destinationPath) }
    }

    private static func posixError() -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(errno),
            userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
        )
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
