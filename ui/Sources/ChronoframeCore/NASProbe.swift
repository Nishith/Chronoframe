import Darwin
import Foundation
import SQLite3

// MARK: - Results

public enum NASProbeStatus: String, Codable, Sendable, Equatable {
    case pass
    case fail
    case unsupported
    case error
}

public struct NASProbeResult: Codable, Sendable, Equatable {
    public var id: String
    public var status: NASProbeStatus
    public var errorCode: Int32?
    public var detail: String

    public init(id: String, status: NASProbeStatus, errorCode: Int32? = nil, detail: String) {
        self.id = id
        self.status = status
        self.errorCode = errorCode
        self.detail = detail
    }
}

public struct NASProbeReport: Codable, Sendable, Equatable {
    public var generatedAt: Date
    public var testDirectory: String
    public var results: [NASProbeResult]

    public init(generatedAt: Date, testDirectory: String, results: [NASProbeResult]) {
        self.generatedAt = generatedAt
        self.testDirectory = testDirectory
        self.results = results
    }
}

public enum NASProbeError: LocalizedError, Sendable, Equatable {
    case testDirectoryUnavailable(path: String)
    case testDirectoryNotEmpty(path: String)
    case workspaceCreationFailed(path: String, errorCode: Int32)

    public var errorDescription: String? {
        switch self {
        case let .testDirectoryUnavailable(path):
            return "The probe test folder doesn't exist or isn't a folder: \(path). Nothing was created."
        case let .testDirectoryNotEmpty(path):
            return "The probe only runs in an empty folder: \(path) contains other items. Nothing was created."
        case let .workspaceCreationFailed(path, errorCode):
            return "The probe couldn't create its workspace in \(path) (errno \(errorCode)). Nothing was created."
        }
    }
}

// MARK: - Probe

/// Qualification probe for a candidate network share (C-14). It writes only
/// inside `PATH/.chronoframe-nas-probe-<uuid>/`, removes exactly what it
/// created, and then removes that directory. Local only; real-share evidence.
public struct NASProbe: Sendable {
    public static let workspacePrefix = ".chronoframe-nas-probe-"

    private let classifier: NASVolumeClassifier
    private let trashItem: @Sendable (URL) throws -> URL?
    private let writerHoldSeconds: TimeInterval

    public init(
        classifier: NASVolumeClassifier = .live,
        trashItem: @escaping @Sendable (URL) throws -> URL? = NASProbe.systemTrashItem,
        writerHoldSeconds: TimeInterval = 2
    ) {
        self.classifier = classifier
        self.trashItem = trashItem
        self.writerHoldSeconds = writerHoldSeconds
    }

    /// `FileManager.trashItem`, returning the resulting URL in the Trash.
    public static let systemTrashItem: @Sendable (URL) throws -> URL? = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    private static let payloadByteCount = 8 * 1024 * 1024

    public func run(testDirectory: URL, includeTrash: Bool) throws -> [NASProbeResult] {
        let root = testDirectory.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NASProbeError.testDirectoryUnavailable(path: root.path)
        }
        let existing: [String]
        do {
            existing = try FileManager.default.contentsOfDirectory(atPath: root.path)
        } catch {
            throw NASProbeError.testDirectoryUnavailable(path: root.path)
        }
        guard existing.allSatisfy({ $0.hasPrefix(Self.workspacePrefix) }) else {
            throw NASProbeError.testDirectoryNotEmpty(path: root.path)
        }

        let workspace = Workspace(
            url: root.appendingPathComponent("\(Self.workspacePrefix)\(UUID().uuidString.lowercased())", isDirectory: true)
        )
        guard Darwin.mkdir(workspace.url.path, 0o700) == 0 else {
            throw NASProbeError.workspaceCreationFailed(path: root.path, errorCode: errno)
        }

        var results: [NASProbeResult] = []
        results.append(volumeObservation(root: root))

        let payload = writePayload(in: workspace)
        results.append(payload.result)
        results.append(exclusiveRenameOntoNewName(in: workspace))
        results.append(exclusiveRenameOntoExistingName(in: workspace))
        results.append(readbackDigest(payload: payload, in: workspace))

        let databaseURL = workspace.path("organizer-probe.sqlite")
        workspace.register("organizer-probe.sqlite")
        for suffix in ["-journal", "-wal", "-shm"] {
            workspace.register("organizer-probe.sqlite" + suffix)
        }
        results.append(journalReadbacks(databaseURL: databaseURL))
        results.append(heldWriterLatency(databaseURL: databaseURL))

        if includeTrash {
            results.append(trashProbe(in: workspace))
        }

        if let leftovers = workspace.cleanUp() {
            results.append(NASProbeResult(
                id: "CLEANUP",
                status: .error,
                detail: "The probe could not remove everything it created in \(workspace.url.path): \(leftovers.joined(separator: ", "))"
            ))
        }
        return results
    }

    // MARK: Workspace

    /// Tracks the names the probe created so cleanup removes exactly those.
    private final class Workspace {
        let url: URL
        private var created: [String] = []

        init(url: URL) { self.url = url }

        func path(_ name: String) -> URL { url.appendingPathComponent(name) }

        func register(_ name: String) {
            if !created.contains(name) { created.append(name) }
        }

        /// Returns the names that could not be removed, or nil when the workspace is gone.
        func cleanUp() -> [String]? {
            var leftovers: [String] = []
            for name in created {
                if Darwin.unlink(path(name).path) != 0, errno != ENOENT {
                    leftovers.append(name)
                }
            }
            // rmdir only succeeds on an empty directory, so a stray foreign file is never deleted.
            if Darwin.rmdir(url.path) != 0, errno != ENOENT {
                if let remaining = try? FileManager.default.contentsOfDirectory(atPath: url.path) {
                    for name in remaining where !leftovers.contains(name) { leftovers.append(name) }
                }
                return leftovers.isEmpty ? [url.lastPathComponent] : leftovers
            }
            return leftovers.isEmpty ? nil : leftovers
        }
    }

    // MARK: P01

    private func volumeObservation(root: URL) -> NASProbeResult {
        let volume = classifier.classify(root)
        guard let library = NASLibraryIdentity.observe(rootURL: root, classifier: classifier) else {
            return NASProbeResult(
                id: "P01",
                status: .error,
                detail: "kind=\(volume.kind.rawValue) fileSystemType=\(volume.fileSystemType) mountPoint=\(volume.mountPoint); the folder could not be observed as a library root"
            )
        }
        let v = library.volume
        let detail = [
            "kind=\(v.kind.rawValue)",
            "fileSystemType=\(v.fileSystemType)",
            "mountPoint=\(v.mountPoint)",
            "serverHost=\(v.serverHost ?? "nil")",
            "shareName=\(v.shareName ?? "nil")",
            "fileSystemID=\(v.fileSystemID)",
            "rootRelativePath=\(library.rootRelativePath)",
            "rootFileID=\(library.rootFileID)",
            "shareRootFileID=\(library.shareRootFileID)",
            "rootCreationTime=\(library.rootCreationTime.map { String($0) } ?? "nil")",
        ].joined(separator: " ")
        return NASProbeResult(id: "P01", status: .pass, detail: detail)
    }

    // MARK: P02

    private struct Payload {
        var result: NASProbeResult
        var name: String?
        var size: Int64
        var digest: String?
    }

    private func writePayload(in workspace: Workspace) -> Payload {
        let name = "payload.bin"
        let path = workspace.path(name).path
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            let code = errno
            return Payload(
                result: NASProbeResult(id: "P02", status: .error, errorCode: code, detail: "could not create the 8 MiB payload (\(Self.errnoName(code)))"),
                name: nil, size: 0, digest: nil
            )
        }
        workspace.register(name)
        defer { _ = Darwin.close(descriptor) }

        var generator = SplitMix64(seed: 0x4E41_5350_524F_4245)
        var hasher = BLAKE2bHasher()
        hasher.update(Data(String(Self.payloadByteCount).utf8))
        var buffer = [UInt8](repeating: 0, count: FileIdentityHasher.chunkByteCount)
        var remaining = Self.payloadByteCount
        while remaining > 0 {
            let count = min(buffer.count, remaining)
            generator.fill(&buffer)
            buffer.withUnsafeBytes { raw in
                hasher.update(UnsafeRawBufferPointer(start: raw.baseAddress, count: count))
            }
            var offset = 0
            while offset < count {
                let written = buffer.withUnsafeBytes { raw -> Int in
                    guard let base = raw.baseAddress else { return -1 }
                    return Darwin.write(descriptor, base + offset, count - offset)
                }
                if written < 0 {
                    if errno == EINTR { continue }
                    let code = errno
                    return Payload(
                        result: NASProbeResult(id: "P02", status: .error, errorCode: code, detail: "write failed after \(Self.payloadByteCount - remaining + offset) bytes (\(Self.errnoName(code)))"),
                        name: name, size: 0, digest: nil
                    )
                }
                offset += written
            }
            remaining -= count
        }
        let digest = hasher.finalizeHexDigest()

        let fullSyncFailed = Darwin.fcntl(descriptor, F_FULLFSYNC) != 0
        let fullSyncCode = fullSyncFailed ? errno : 0
        let fsyncFailed = Darwin.fsync(descriptor) != 0
        let fsyncCode = fsyncFailed ? errno : 0
        let detail = "bytes=\(Self.payloadByteCount) fullfsync=\(fullSyncFailed ? Self.errnoName(fullSyncCode) : "ok") fsync=\(fsyncFailed ? Self.errnoName(fsyncCode) : "ok")"

        let status: NASProbeStatus
        var code: Int32?
        if !fullSyncFailed && !fsyncFailed {
            status = .pass
        } else if fullSyncFailed, [ENOTSUP, EINVAL, ENOTTY].contains(fullSyncCode), !fsyncFailed {
            // D-NAS-41: the copy path falls back to fsync in exactly these cases.
            status = .unsupported
            code = fullSyncCode
        } else {
            status = .fail
            code = fullSyncFailed ? fullSyncCode : fsyncCode
        }
        return Payload(
            result: NASProbeResult(id: "P02", status: status, errorCode: code, detail: detail),
            name: name, size: Int64(Self.payloadByteCount), digest: digest
        )
    }

    // MARK: P03, P04

    private static let renameUnsupportedCodes: [Int32] = [ENOTSUP, EINVAL, ENOSYS]

    private func renameExclusive(from source: URL, to destination: URL) -> (succeeded: Bool, errorCode: Int32) {
        let result = source.path.withCString { sourcePointer in
            destination.path.withCString { destinationPointer in
                renamex_np(sourcePointer, destinationPointer, UInt32(RENAME_EXCL))
            }
        }
        return result == 0 ? (true, 0) : (false, errno)
    }

    private func createSmallFile(named name: String, seed: UInt64, in workspace: Workspace) -> Int32? {
        let descriptor = Darwin.open(workspace.path(name).path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return errno }
        workspace.register(name)
        defer { _ = Darwin.close(descriptor) }
        var generator = SplitMix64(seed: seed)
        var bytes = [UInt8](repeating: 0, count: 4096)
        generator.fill(&bytes)
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return Darwin.write(descriptor, base + offset, bytes.count - offset)
            }
            if written < 0 {
                if errno == EINTR { continue }
                return errno
            }
            offset += written
        }
        return nil
    }

    private func exclusiveRenameOntoNewName(in workspace: Workspace) -> NASProbeResult {
        if let code = createSmallFile(named: "rename-source-1.bin", seed: 0xA1, in: workspace) {
            return NASProbeResult(id: "P03", status: .error, errorCode: code, detail: "could not create the rename source (\(Self.errnoName(code)))")
        }
        let target = workspace.path("rename-target-1.bin")
        let outcome = renameExclusive(from: workspace.path("rename-source-1.bin"), to: target)
        if outcome.succeeded {
            workspace.register("rename-target-1.bin")
            let sourceGone = !FileManager.default.fileExists(atPath: workspace.path("rename-source-1.bin").path)
            let targetPresent = FileManager.default.fileExists(atPath: target.path)
            return NASProbeResult(
                id: "P03",
                status: sourceGone && targetPresent ? .pass : .fail,
                detail: "renamex_np RENAME_EXCL onto a new name succeeded sourceGone=\(sourceGone) targetPresent=\(targetPresent)"
            )
        }
        let status: NASProbeStatus = Self.renameUnsupportedCodes.contains(outcome.errorCode) ? .unsupported : .fail
        return NASProbeResult(
            id: "P03",
            status: status,
            errorCode: outcome.errorCode,
            detail: "renamex_np RENAME_EXCL onto a new name failed (\(Self.errnoName(outcome.errorCode)))"
        )
    }

    private func exclusiveRenameOntoExistingName(in workspace: Workspace) -> NASProbeResult {
        let hasher = FileIdentityHasher()
        if let code = createSmallFile(named: "exclusive-existing.bin", seed: 0xB1, in: workspace) {
            return NASProbeResult(id: "P04", status: .error, errorCode: code, detail: "could not create the existing file (\(Self.errnoName(code)))")
        }
        if let code = createSmallFile(named: "rename-source-2.bin", seed: 0xB2, in: workspace) {
            return NASProbeResult(id: "P04", status: .error, errorCode: code, detail: "could not create the rename source (\(Self.errnoName(code)))")
        }
        let existing = workspace.path("exclusive-existing.bin")
        let source = workspace.path("rename-source-2.bin")
        let before: FileIdentity
        do {
            before = try hasher.hashIdentity(at: existing)
        } catch {
            return NASProbeResult(id: "P04", status: .error, detail: "could not hash the existing file before the rename")
        }

        let outcome = renameExclusive(from: source, to: existing)
        let after = try? hasher.hashIdentity(at: existing)
        let digestUnchanged = after == before
        let sourcePresent = FileManager.default.fileExists(atPath: source.path)
        let suffix = "existingDigestUnchanged=\(digestUnchanged) sourceStillPresent=\(sourcePresent)"

        if outcome.succeeded {
            return NASProbeResult(
                id: "P04",
                status: .fail,
                detail: "RENAME_EXCL replaced an existing file (rc=0) \(suffix)"
            )
        }
        if Self.renameUnsupportedCodes.contains(outcome.errorCode) {
            return NASProbeResult(
                id: "P04",
                status: .unsupported,
                errorCode: outcome.errorCode,
                detail: "no-replace rename is not supported (\(Self.errnoName(outcome.errorCode))) \(suffix)"
            )
        }
        let passed = outcome.errorCode == EEXIST && digestUnchanged && sourcePresent
        return NASProbeResult(
            id: "P04",
            status: passed ? .pass : .fail,
            errorCode: outcome.errorCode,
            detail: "rc=-1 errno=\(Self.errnoName(outcome.errorCode)) \(suffix)"
        )
    }

    // MARK: P05

    private func readbackDigest(payload: Payload, in workspace: Workspace) -> NASProbeResult {
        guard let name = payload.name, let written = payload.digest else {
            return NASProbeResult(id: "P05", status: .error, detail: "the payload was not written, so there is nothing to read back")
        }
        do {
            let identity = try FileIdentityHasher().hashIdentity(at: workspace.path(name))
            let matches = identity.digest == written && identity.size == payload.size
            return NASProbeResult(
                id: "P05",
                status: matches ? .pass : .fail,
                detail: "size=\(identity.size) writtenDigest=\(written.prefix(16)) readbackDigest=\(identity.digest.prefix(16)) digestsMatch=\(matches)"
            )
        } catch {
            return NASProbeResult(id: "P05", status: .error, detail: "could not read the payload back: \(error.localizedDescription)")
        }
    }

    // MARK: P06

    private func journalReadbacks(databaseURL: URL) -> NASProbeResult {
        // Rollback modes are per connection, so read both values on the
        // OrganizerDatabase connection itself, before it closes.
        let journalMode: String
        let synchronous: Int32
        do {
            let database = try OrganizerDatabase(url: databaseURL, journalPolicy: .rollbackDelete)
            defer { database.close() }
            journalMode = try database.journalMode()
            synchronous = try database.synchronousMode()
        } catch {
            return NASProbeResult(
                id: "P06",
                status: .fail,
                detail: "OrganizerDatabase refused the rollback-delete journal: \(error.localizedDescription)"
            )
        }

        // The raw handle is only for the VFS name; version and compile options are process-wide.
        var vfsName = "unknown"
        var handle: OpaquePointer?
        if sqlite3_open_v2(databaseURL.path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK {
            var vfsPointer: UnsafeMutablePointer<CChar>?
            let vfsResult = sqlite3_file_control(handle, nil, SQLITE_FCNTL_VFSNAME, &vfsPointer)
            if vfsResult == SQLITE_OK, let vfsPointer {
                vfsName = String(cString: vfsPointer)
                sqlite3_free(vfsPointer)
            } else {
                vfsName = "unknown(rc=\(vfsResult))"
            }
        }
        sqlite3_close(handle)

        let lockingStyle = sqlite3_compileoption_used("ENABLE_LOCKING_STYLE") != 0
        let detail = [
            "journalMode=\(journalMode)",
            "synchronous=\(synchronous)",
            "sqliteVersion=\(String(cString: sqlite3_libversion()))",
            "enableLockingStyle=\(lockingStyle)",
            "vfs=\(vfsName)",
        ].joined(separator: " ")
        let passed = journalMode.lowercased() == "delete" && synchronous == 2
        return NASProbeResult(id: "P06", status: passed ? .pass : .fail, detail: detail)
    }

    private static func scalarString(_ handle: OpaquePointer?, _ sql: String) -> String? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let text = sqlite3_column_text(statement, 0) else { return nil }
        return String(cString: text)
    }

    // MARK: P07

    /// One reader connection running `SELECT count(*)` on its own thread.
    private final class HeldWriterReader: @unchecked Sendable {
        private var handle: OpaquePointer?
        private let finished = DispatchSemaphore(value: 0)
        private(set) var resultCode: Int32 = -1
        private(set) var elapsedMs: Int = 0

        init?(path: String, busyTimeoutMs: Int32) {
            guard sqlite3_open_v2(path, &handle, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                sqlite3_close(handle)
                return nil
            }
            sqlite3_busy_timeout(handle, busyTimeoutMs)
        }

        deinit { sqlite3_close(handle) }

        func startQuery() {
            Thread.detachNewThread { [self] in
                let started = DispatchTime.now().uptimeNanoseconds
                var statement: OpaquePointer?
                var code = sqlite3_prepare_v2(handle, "SELECT count(*) FROM FileCache;", -1, &statement, nil)
                if code == SQLITE_OK {
                    code = sqlite3_step(statement)
                    if code == SQLITE_ROW || code == SQLITE_DONE { code = SQLITE_OK }
                }
                sqlite3_finalize(statement)
                elapsedMs = Int((DispatchTime.now().uptimeNanoseconds - started) / 1_000_000)
                resultCode = code
                finished.signal()
            }
        }

        func waitForQuery() { finished.wait() }
    }

    private func heldWriterLatency(databaseURL: URL) -> NASProbeResult {
        let writer: OrganizerDatabase
        do {
            writer = try OrganizerDatabase(url: databaseURL, journalPolicy: .rollbackDelete)
        } catch {
            return NASProbeResult(id: "P07", status: .error, detail: "could not open the writer connection: \(error.localizedDescription)")
        }
        defer { writer.close() }

        func measure(busyTimeoutMs: Int32) throws -> (rc: Int32, elapsedMs: Int)? {
            guard let reader = HeldWriterReader(path: databaseURL.path, busyTimeoutMs: busyTimeoutMs) else { return nil }
            // BEGIN EXCLUSIVE: in rollback-journal mode BEGIN IMMEDIATE only
            // takes a RESERVED lock, which never blocks a reader.
            try writer.execute("BEGIN EXCLUSIVE;")
            do {
                reader.startQuery()
                if busyTimeoutMs > 0 {
                    // The patient reader waits on the lock, so release it after the hold.
                    Thread.sleep(forTimeInterval: writerHoldSeconds)
                    try writer.execute("COMMIT;")
                    reader.waitForQuery()
                } else {
                    // The impatient reader returns at once; hold the lock until it has.
                    reader.waitForQuery()
                    try writer.execute("COMMIT;")
                }
            } catch {
                try? writer.execute("ROLLBACK;")
                throw error
            }
            return (reader.resultCode, reader.elapsedMs)
        }

        do {
            guard let patient = try measure(busyTimeoutMs: 30000), let impatient = try measure(busyTimeoutMs: 0) else {
                return NASProbeResult(id: "P07", status: .error, detail: "could not open the reader connection")
            }
            let detail = "writer=BEGIN EXCLUSIVE heldMs=\(Int(writerHoldSeconds * 1000)); "
                + "timeout30000: rc=\(patient.rc) elapsedMs=\(patient.elapsedMs); "
                + "timeout0: rc=\(impatient.rc) elapsedMs=\(impatient.elapsedMs)"
            return NASProbeResult(
                id: "P07",
                status: patient.rc == SQLITE_OK ? .pass : .fail,
                errorCode: patient.rc == SQLITE_OK ? nil : patient.rc,
                detail: detail
            )
        } catch {
            return NASProbeResult(id: "P07", status: .error, detail: "the held-writer measurement failed: \(error.localizedDescription)")
        }
    }

    // MARK: P08

    /// Runs only with `--trash`, on a file the probe owns.
    private func trashProbe(in workspace: Workspace) -> NASProbeResult {
        let name = "trash-probe.bin"
        if let code = createSmallFile(named: name, seed: 0xC1, in: workspace) {
            return NASProbeResult(id: "P08", status: .error, errorCode: code, detail: "could not create the trash probe file (\(Self.errnoName(code)))")
        }
        let original = workspace.path(name)
        let hasher = FileIdentityHasher()
        guard let before = try? hasher.hashIdentity(at: original) else {
            return NASProbeResult(id: "P08", status: .error, detail: "could not hash the trash probe file")
        }

        let resulting: URL?
        do {
            resulting = try trashItem(original)
        } catch {
            let nsError = error as NSError
            let unsupported = nsError.domain == NSCocoaErrorDomain && nsError.code == NSFeatureUnsupportedError
            return NASProbeResult(
                id: "P08",
                status: unsupported ? .unsupported : .fail,
                errorCode: Int32(truncatingIfNeeded: nsError.code),
                detail: "trashItem failed domain=\(nsError.domain) code=\(nsError.code)"
            )
        }
        guard let resulting else {
            return NASProbeResult(id: "P08", status: .error, detail: "trashItem succeeded but returned no resulting URL, so the probe file was not moved back")
        }

        let digestMatches = (try? hasher.hashIdentity(at: resulting)) == before
        var restored = false
        var restoreNote = ""
        do {
            try FileManager.default.moveItem(at: resulting, to: original)
            restored = true
        } catch {
            restoreNote = " restoreError=\(error.localizedDescription)"
        }
        return NASProbeResult(
            id: "P08",
            status: digestMatches && restored ? .pass : .fail,
            detail: "trashItem succeeded digestAtTrashMatches=\(digestMatches) restored=\(restored)\(restoreNote)"
        )
    }

    // MARK: Helpers

    static func errnoName(_ code: Int32) -> String {
        switch code {
        case EEXIST: return "EEXIST"
        case ENOTSUP: return "ENOTSUP"
        case EINVAL: return "EINVAL"
        case ENOTTY: return "ENOTTY"
        case ENOSYS: return "ENOSYS"
        case EIO: return "EIO"
        case ENOSPC: return "ENOSPC"
        case EACCES: return "EACCES"
        case EPERM: return "EPERM"
        case EROFS: return "EROFS"
        default: return "errno \(code)"
        }
    }
}
