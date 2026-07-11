import Darwin
import Foundation

// MARK: - Guardian verified-restore executor (Phase 3)
//
// Heals selected corrupt/missing library files from the mirror. This is the only
// Guardian surface that writes into the library, so it is the most defensive:
//
//   * commit-time re-verification (the immutable plan is necessary but not
//     sufficient against races): the mirror file is opened O_NOFOLLOW and the bytes
//     that are hashed are the same descriptor that is then used as the copy source,
//     so a symlink swap or content change between plan and commit cannot slip
//     through; a corrupt primary must still have its expected corrupt identity, and
//     a missing primary must still be absent (a file that reappeared is refused);
//   * preserve, don't erase: a corrupt primary is moved into a same-directory
//     quarantine BEFORE the replacement is installed — never Trashed first (Trash
//     naming/volume availability must not be a rollback dependency);
//   * durable crash state machine: every transition is journaled so an interrupted
//     restore can be reconciled — a run killed after quarantine but before install
//     rolls the original back into place rather than leaving the library missing;
//   * the whole run holds both the library and mirror locks (multi-root, canonical
//     order) and is receipt-backed.

public enum GuardianRestoreState: String, Codable, Sendable {
    case intentRecorded
    case originalQuarantined
    case replacementInstalled
    case finalized
}

public enum GuardianRestoreCommitBlockReason: String, Codable, Sendable {
    /// The mirror copy no longer hashes to the trusted digest at commit time.
    case mirrorChangedSincePlanning
    /// A corrupt primary changed again since planning.
    case primaryChangedSincePlanning
    /// A primary that was missing has reappeared; refuse to overwrite it.
    case primaryReappeared
    /// An I/O error prevented the restore of this item; the library was not changed.
    case ioError
}

public struct GuardianRestoreCommitBlock: Equatable, Codable, Sendable {
    public var relativePath: String
    public var reason: GuardianRestoreCommitBlockReason

    public init(relativePath: String, reason: GuardianRestoreCommitBlockReason) {
        self.relativePath = relativePath
        self.reason = reason
    }
}

public struct GuardianRestoreReceipt: Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable { case pending, completed, aborted }
    public var version: Int
    public var status: Status
    public var createdAt: Date
    public var libraryRoot: String
    public var mirrorRoot: String
    public var restored: [String]
    public var blocked: [GuardianRestoreCommitBlock]

    public init(
        version: Int = 1,
        status: Status,
        createdAt: Date,
        libraryRoot: String,
        mirrorRoot: String,
        restored: [String] = [],
        blocked: [GuardianRestoreCommitBlock] = []
    ) {
        self.version = version
        self.status = status
        self.createdAt = createdAt
        self.libraryRoot = libraryRoot
        self.mirrorRoot = mirrorRoot
        self.restored = restored
        self.blocked = blocked
    }
}

public struct GuardianRestoreExecutionResult: Equatable, Sendable {
    public var restored: [String]
    public var blockedAtCommit: [GuardianRestoreCommitBlock]
    public var receiptURL: URL?
    public var journalURL: URL?

    public init(
        restored: [String],
        blockedAtCommit: [GuardianRestoreCommitBlock],
        receiptURL: URL?,
        journalURL: URL?
    ) {
        self.restored = restored
        self.blockedAtCommit = blockedAtCommit
        self.receiptURL = receiptURL
        self.journalURL = journalURL
    }
}

public struct GuardianRestoreExecutor: Sendable {
    public static let quarantineDirectoryName = ".guardian_restore_quarantine"

    private struct JournalEntry: Codable {
        var relativePath: String
        var state: GuardianRestoreState
        var quarantinePath: String?
    }

    private let hasher: FileIdentityHasher

    public init(hasher: FileIdentityHasher = FileIdentityHasher()) {
        self.hasher = hasher
    }

    /// Restore the actions in `plan` whose relative path is in `selectedPaths`
    /// (review-gated). `stateDirectory` holds the receipt and journal (Application
    /// Support). `afterState` is a test seam invoked after each journaled
    /// transition; a throw simulates a crash and leaves the on-disk state for
    /// `recover(...)` to reconcile. In production it is a no-op.
    public func execute(
        plan: GuardianRestorePlan,
        selectedPaths: Set<String>,
        libraryRoot: URL,
        mirrorRoot: URL,
        stateDirectory: URL,
        now: Date = Date(),
        isCancelled: @Sendable () -> Bool = { false },
        afterState: (GuardianRestoreState, String) throws -> Void = { _, _ in }
    ) throws -> GuardianRestoreExecutionResult {
        let lease = try GuardianMultiRootLock.acquire([
            GuardianLockRoot.inRoot(libraryRoot, surface: "app", operation: "guardian-restore"),
            GuardianLockRoot.inRoot(mirrorRoot, surface: "app", operation: "guardian-restore"),
        ])
        defer { lease.release() }

        try FileManager.default.createDirectory(at: stateDirectory, withIntermediateDirectories: true)
        let stamp = Self.timestamp(now)
        let unique = UUID().uuidString
        let receiptURL = stateDirectory.appendingPathComponent("guardian_restore_receipt_\(stamp)_\(unique).json")
        let journalURL = stateDirectory.appendingPathComponent("guardian_restore_journal_\(stamp)_\(unique).jsonl")
        FileManager.default.createFile(atPath: journalURL.path, contents: nil)

        var receipt = GuardianRestoreReceipt(
            status: .pending, createdAt: now, libraryRoot: libraryRoot.path, mirrorRoot: mirrorRoot.path
        )
        try writeReceipt(receipt, to: receiptURL)

        var restored: [String] = []
        var blocked: [GuardianRestoreCommitBlock] = []

        for action in plan.restorable where selectedPaths.contains(action.relativePath) {
            if isCancelled() { break }
            switch try restoreOne(
                action: action,
                libraryRoot: libraryRoot,
                mirrorRoot: mirrorRoot,
                journalURL: journalURL,
                stamp: stamp,
                afterState: afterState
            ) {
            case .restored:
                restored.append(action.relativePath)
            case let .blocked(reason):
                blocked.append(GuardianRestoreCommitBlock(relativePath: action.relativePath, reason: reason))
            }
        }

        receipt.status = .completed
        receipt.restored = restored
        receipt.blocked = blocked
        try writeReceipt(receipt, to: receiptURL)

        return GuardianRestoreExecutionResult(
            restored: restored, blockedAtCommit: blocked, receiptURL: receiptURL, journalURL: journalURL
        )
    }

    private enum ItemOutcome {
        case restored
        case blocked(GuardianRestoreCommitBlockReason)
    }

    private func restoreOne(
        action: GuardianRestoreAction,
        libraryRoot: URL,
        mirrorRoot: URL,
        journalURL: URL,
        stamp: String,
        afterState: (GuardianRestoreState, String) throws -> Void
    ) throws -> ItemOutcome {
        let primaryURL = libraryRoot.appendingPathComponent(action.relativePath)
        let mirrorURL = mirrorRoot.appendingPathComponent(action.relativePath)

        try appendJournal(JournalEntry(relativePath: action.relativePath, state: .intentRecorded, quarantinePath: nil), to: journalURL)
        try afterState(.intentRecorded, action.relativePath)

        // Commit-time verification: open the mirror O_NOFOLLOW and hash the SAME
        // descriptor we will copy from.
        let mirrorDescriptor = mirrorURL.path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
        guard mirrorDescriptor >= 0 else { return .blocked(.ioError) }
        defer { Darwin.close(mirrorDescriptor) }

        let mirrorEnd = lseek(mirrorDescriptor, 0, SEEK_END)
        guard mirrorEnd >= 0, lseek(mirrorDescriptor, 0, SEEK_SET) >= 0 else { return .blocked(.ioError) }
        guard let mirrorIdentity = try? hasher.hashIdentity(descriptor: mirrorDescriptor, size: Int64(mirrorEnd)),
              mirrorIdentity == action.trustedIdentity else {
            return .blocked(.mirrorChangedSincePlanning)
        }

        // Revalidate the primary's expected state before mutating anything.
        switch action.reason {
        case .primaryMissing:
            if FileManager.default.fileExists(atPath: primaryURL.path) {
                return .blocked(.primaryReappeared)
            }
        case .primaryCorrupt:
            guard let expected = action.expectedCurrentPrimaryIdentity,
                  let current = try? hasher.hashIdentity(at: primaryURL),
                  current == expected else {
                return .blocked(.primaryChangedSincePlanning)
            }
        }

        do {
            // Quarantine the corrupt original (same directory) before installing.
            var quarantineURL: URL?
            if action.reason == .primaryCorrupt {
                let q = try quarantineOriginal(primaryURL: primaryURL, libraryRoot: libraryRoot, relativePath: action.relativePath, stamp: stamp)
                quarantineURL = q
                try appendJournal(JournalEntry(relativePath: action.relativePath, state: .originalQuarantined, quarantinePath: q.path), to: journalURL)
                try afterState(.originalQuarantined, action.relativePath)
            }

            // Prepare + install the replacement from the verified descriptor.
            try FileManager.default.createDirectory(at: primaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let temporaryURL = primaryURL.deletingLastPathComponent().appendingPathComponent(".guardian_restore_tmp_\(UUID().uuidString)")
            do {
                try Self.copyFromDescriptor(mirrorDescriptor, toPath: temporaryURL.path)
                let installedIdentity = try hasher.hashIdentity(at: temporaryURL)
                guard installedIdentity == action.trustedIdentity else {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    // Roll the original back so the library is not left missing.
                    if let quarantineURL { try? FileManager.default.moveItem(at: quarantineURL, to: primaryURL) }
                    return .blocked(.ioError)
                }
                try Self.atomicRenameNoOverwrite(from: temporaryURL.path, to: primaryURL.path)
            } catch {
                try? FileManager.default.removeItem(at: temporaryURL)
                if let quarantineURL { try? FileManager.default.moveItem(at: quarantineURL, to: primaryURL) }
                return .blocked(.ioError)
            }

            try appendJournal(JournalEntry(relativePath: action.relativePath, state: .replacementInstalled, quarantinePath: quarantineURL?.path), to: journalURL)
            try afterState(.replacementInstalled, action.relativePath)

            try appendJournal(JournalEntry(relativePath: action.relativePath, state: .finalized, quarantinePath: quarantineURL?.path), to: journalURL)
            try afterState(.finalized, action.relativePath)
            return .restored
        }
    }

    // MARK: - Recovery

    /// Reconcile an interrupted restore from its journal. A file left in
    /// `originalQuarantined` without a following `replacementInstalled` is rolled
    /// back (the quarantined original is moved into place) so the library is never
    /// left missing. Returns the relative paths that were rolled back.
    @discardableResult
    public func recover(journalURL: URL, libraryRoot: URL) throws -> [String] {
        guard let data = try? Data(contentsOf: journalURL), !data.isEmpty else { return [] }
        let decoder = JSONDecoder()
        var lastState: [String: GuardianRestoreState] = [:]
        var quarantineByPath: [String: String] = [:]
        var order: [String] = []
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let entry = try? decoder.decode(JournalEntry.self, from: Data(line)) else { continue }
            if lastState[entry.relativePath] == nil { order.append(entry.relativePath) }
            lastState[entry.relativePath] = entry.state
            if let q = entry.quarantinePath { quarantineByPath[entry.relativePath] = q }
        }

        var rolledBack: [String] = []
        for path in order {
            guard lastState[path] == .originalQuarantined, let quarantinePath = quarantineByPath[path] else { continue }
            let primaryURL = libraryRoot.appendingPathComponent(path)
            let quarantineURL = URL(fileURLWithPath: quarantinePath)
            guard FileManager.default.fileExists(atPath: quarantineURL.path),
                  !FileManager.default.fileExists(atPath: primaryURL.path) else { continue }
            try FileManager.default.createDirectory(at: primaryURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: quarantineURL, to: primaryURL)
            rolledBack.append(path)
        }
        return rolledBack
    }

    // MARK: - Helpers

    private func quarantineOriginal(primaryURL: URL, libraryRoot: URL, relativePath: String, stamp: String) throws -> URL {
        let quarantineRoot = libraryRoot
            .appendingPathComponent(Self.quarantineDirectoryName, isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        let destination = quarantineRoot.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: primaryURL, to: destination)
        return destination
    }

    private func appendJournal(_ entry: JournalEntry, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var line = try encoder.encode(entry)
        line.append(UInt8(ascii: "\n"))
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        try handle.synchronize()
    }

    private func writeReceipt(_ receipt: GuardianRestoreReceipt, to url: URL) throws {
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

    private static func copyFromDescriptor(_ sourceDescriptor: Int32, toPath path: String) throws {
        guard lseek(sourceDescriptor, 0, SEEK_SET) >= 0 else { throw posixError() }
        let out = path.withCString { Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, S_IRUSR | S_IWUSR) }
        guard out >= 0 else { throw posixError() }
        defer { Darwin.close(out) }

        let capacity = 1 << 20
        var buffer = [UInt8](repeating: 0, count: capacity)
        while true {
            let readCount = buffer.withUnsafeMutableBytes { Darwin.read(sourceDescriptor, $0.baseAddress, capacity) }
            if readCount == 0 { break }
            guard readCount > 0 else { throw posixError() }
            try buffer.withUnsafeBytes { rawBuffer in
                var written = 0
                while written < readCount {
                    let result = Darwin.write(out, rawBuffer.baseAddress!.advanced(by: written), readCount - written)
                    guard result > 0 else { throw posixError() }
                    written += result
                }
            }
        }
        guard fcntl(out, F_FULLFSYNC) == 0 else { throw posixError() }
    }

    private static func atomicRenameNoOverwrite(from sourcePath: String, to destinationPath: String) throws {
        let result = sourcePath.withCString { sourcePointer in
            destinationPath.withCString { destinationPointer in
                renamex_np(sourcePointer, destinationPointer, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else { throw posixError() }
    }

    private static func posixError() -> NSError {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))])
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter.string(from: date)
    }
}
