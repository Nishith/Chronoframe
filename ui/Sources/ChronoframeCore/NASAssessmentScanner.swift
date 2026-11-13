import Darwin
import Foundation

public struct NASAssessmentConfiguration: Sendable, Equatable {
    public var rootURL: URL
    /// The store file location; must not be inside `rootURL`.
    public var stateURL: URL
    /// Default 2, clamped to 1...8.
    public var workerCount: Int
    /// Default 200.
    public var checkpointDirectoryBatch: Int
    /// Default 200.
    public var hashResultBatch: Int

    public init(rootURL: URL, stateURL: URL, workerCount: Int = 2, checkpointDirectoryBatch: Int = 200, hashResultBatch: Int = 200) {
        self.rootURL = rootURL
        self.stateURL = stateURL
        self.workerCount = max(1, min(8, workerCount))
        self.checkpointDirectoryBatch = checkpointDirectoryBatch
        self.hashResultBatch = hashResultBatch
    }
}

public struct NASScanFileSystem: Sendable {
    public struct Entry: Sendable, Equatable {
        public var name: String
        public var isDirectory: Bool
        public var isRegularFile: Bool
        public var isSymbolicLink: Bool
        public var isPackage: Bool
        public var size: Int64
        public var modificationTime: TimeInterval
        public var fileID: UInt64
        public var deviceID: Int32

        public init(
            name: String,
            isDirectory: Bool,
            isRegularFile: Bool,
            isSymbolicLink: Bool,
            isPackage: Bool,
            size: Int64,
            modificationTime: TimeInterval,
            fileID: UInt64,
            deviceID: Int32
        ) {
            self.name = name
            self.isDirectory = isDirectory
            self.isRegularFile = isRegularFile
            self.isSymbolicLink = isSymbolicLink
            self.isPackage = isPackage
            self.size = size
            self.modificationTime = modificationTime
            self.fileID = fileID
            self.deviceID = deviceID
        }
    }

    /// Child names of a directory.
    public var listDirectory: @Sendable (String) throws -> [String]
    /// `lstat` plus package detection for a full path; nil on failure.
    public var entry: @Sendable (String) -> Entry?

    public init(
        listDirectory: @escaping @Sendable (String) throws -> [String],
        entry: @escaping @Sendable (String) -> Entry?
    ) {
        self.listDirectory = listDirectory
        self.entry = entry
    }

    public static let live = NASScanFileSystem(
        listDirectory: { path in try FileManager.default.contentsOfDirectory(atPath: path) },
        entry: { path in nasLiveScanEntry(atPath: path) }
    )
}

// File-scope wrapper so the Darwin call is not shadowed by any member named `entry`.
private func nasLiveScanEntry(atPath path: String) -> NASScanFileSystem.Entry? {
    var info = Darwin.stat()
    guard Darwin.lstat(path, &info) == 0 else { return nil }
    let type = info.st_mode & S_IFMT
    let isDirectory = type == S_IFDIR
    var isPackage = false
    if isDirectory {
        isPackage = (try? URL(fileURLWithPath: path, isDirectory: true).resourceValues(forKeys: [.isPackageKey]))?.isPackage == true
    }
    return NASScanFileSystem.Entry(
        name: (path as NSString).lastPathComponent,
        isDirectory: isDirectory,
        isRegularFile: type == S_IFREG,
        isSymbolicLink: type == S_IFLNK,
        isPackage: isPackage,
        size: Int64(info.st_size),
        modificationTime: TimeInterval(info.st_mtimespec.tv_sec) + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000,
        fileID: UInt64(info.st_ino),
        deviceID: Int32(truncatingIfNeeded: info.st_dev)
    )
}

public protocol NASActivityProviding: Sendable {
    func begin(reason: String) -> NSObjectProtocol
    func end(_ token: NSObjectProtocol)
}

public struct NASProcessActivityProvider: NASActivityProviding {
    public init() {}

    public func begin(reason: String) -> NSObjectProtocol {
        ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled, .userInitiated], reason: reason)
    }

    public func end(_ token: NSObjectProtocol) {
        ProcessInfo.processInfo.endActivity(token)
    }
}

public final class NASAssessmentScanner: @unchecked Sendable {
    private let store: NASAssessmentStore
    private let reader: NASMeteredFileReader
    private let fileSystem: NASScanFileSystem
    private let activity: any NASActivityProviding
    private let now: @Sendable () -> Date

    public init(
        store: NASAssessmentStore,
        reader: NASMeteredFileReader = NASMeteredFileReader(),
        fileSystem: NASScanFileSystem = .live,
        activity: any NASActivityProviding = NASProcessActivityProvider(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.reader = reader
        self.fileSystem = fileSystem
        self.activity = activity
        self.now = now
    }

    public func run(
        _ configuration: NASAssessmentConfiguration,
        isCancelled: @escaping @Sendable () -> Bool
    ) -> AsyncThrowingStream<NASAssessmentEvent, Error> {
        AsyncThrowingStream { continuation in
            let terminated = NASScanFlag()
            continuation.onTermination = { _ in terminated.set() }
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                execute(
                    configuration,
                    isCancelled: { isCancelled() || terminated.isSet },
                    continuation: continuation
                )
            }
        }
    }

    private func execute(
        _ configuration: NASAssessmentConfiguration,
        isCancelled: @escaping @Sendable () -> Bool,
        continuation: AsyncThrowingStream<NASAssessmentEvent, Error>.Continuation
    ) {
        // Step 1: preflight. Nothing is yielded and no activity begins when it refuses.
        let rootPath = configuration.rootURL.standardizedFileURL.path
        let rootDevice: Int32
        do {
            rootDevice = try preflight(configuration: configuration, rootPath: rootPath)
        } catch {
            continuation.finish(throwing: error)
            return
        }

        // Step 2: the sleep assertion ends before the stream finishes, on every path.
        let token = activity.begin(reason: "Chronoframe: assessing a NAS library")
        let outcome: Result<Void, Error>
        do {
            let session = NASScanSession(
                configuration: configuration,
                rootPath: rootPath,
                rootDevice: rootDevice,
                store: store,
                reader: reader,
                fileSystem: fileSystem,
                now: now,
                isCancelled: isCancelled,
                continuation: continuation
            )
            try session.run()
            outcome = .success(())
        } catch {
            outcome = .failure(error)
        }
        activity.end(token)

        switch outcome {
        case .success: continuation.finish()
        case let .failure(error): continuation.finish(throwing: error)
        }
    }

    private func preflight(configuration: NASAssessmentConfiguration, rootPath: String) throws -> Int32 {
        let statePath = configuration.stateURL.standardizedFileURL.path
        if Self.isInside(path: statePath, root: rootPath) || Self.resolvedStateIsInside(configuration.stateURL, root: configuration.rootURL) {
            throw NASAssessmentError.stateInsideLibrary(statePath: statePath, rootPath: rootPath)
        }
        guard let root = fileSystem.entry(rootPath) else {
            throw NASAssessmentError.rootUnavailable(path: rootPath)
        }
        if root.isSymbolicLink {
            throw NASAssessmentError.rootIsLink(path: rootPath)
        }
        guard root.isDirectory else {
            throw NASAssessmentError.rootUnavailable(path: rootPath)
        }
        return root.deviceID
    }

    private static func isInside(path: String, root: String) -> Bool {
        if path == root { return true }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        return path.hasPrefix(prefix)
    }

    /// Also catches a state path that reaches into the library through a symbolic link.
    private static func resolvedStateIsInside(_ stateURL: URL, root rootURL: URL) -> Bool {
        let standardizedState = stateURL.standardizedFileURL
        let resolvedRoot = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let resolvedParent = standardizedState.deletingLastPathComponent().resolvingSymlinksInPath()
        let resolvedState = resolvedParent.appendingPathComponent(standardizedState.lastPathComponent).path
        return isInside(path: resolvedState, root: resolvedRoot)
    }
}

// MARK: - Support types

private final class NASScanFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }
}

private func nasJoin(_ base: String, _ name: String) -> String {
    base.hasSuffix("/") ? base + name : base + "/" + name
}

private func nasRelative(_ directory: String, _ name: String) -> String {
    directory.isEmpty ? name : directory + "/" + name
}

/// Swift `String ==` is canonical-equivalence aware, so compare scalars when the spelling matters.
private func nasSameSpelling(_ lhs: String, _ rhs: String) -> Bool {
    lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
}

private let nasProgressInterval: TimeInterval = 0.25

// MARK: - One scan

/// All mutable state of a single assessment run. Enumeration is single-threaded;
/// during hashing every mutation happens under `hashLock`.
private final class NASScanSession: @unchecked Sendable {
    private struct PendingDirectory {
        var rawRelativePath: String
        var relativePath: String
    }

    private struct Child {
        var rawName: String
        var name: String
    }

    private enum DirectoryStep { case proceed, cancelled, volumeLost }

    private let configuration: NASAssessmentConfiguration
    private let rootPath: String
    private let rootDevice: Int32
    private let store: NASAssessmentStore
    private let reader: NASMeteredFileReader
    private let fileSystem: NASScanFileSystem
    private let now: @Sendable () -> Date
    private let isCancelled: @Sendable () -> Bool
    private let continuation: AsyncThrowingStream<NASAssessmentEvent, Error>.Continuation

    private var generation: Int64 = 0
    private var startedAt = Date()
    private var counts = NASScanCounts()
    private var ledger = NASByteLedger()
    private var hasGap = false
    private var volumeLost = false
    private var wasCancelled = false
    /// Consecutive `entry` failures during enumeration. A dropped share fails every child lstat
    /// while the folder listing already succeeded, so a run of them is probed for a lost root.
    private var consecutiveEntryFailures = 0
    private let entryFailuresBeforeRootProbe = 3

    private var directoryBuffer: [NASDirectoryRow] = []
    private var itemBuffer: [NASItemRow] = []
    private var issueBuffer: [NASIssue] = []
    /// NFC relative path -> on-disk relative path, only where the spellings differ.
    private var onDiskPaths: [String: String] = [:]
    private var lastProgressTime: TimeInterval = 0

    private let hashLock = NSLock()
    private var hashResultBuffer: [NASItemRow] = []
    private var nextHashIndex = 0
    private var stopHashing = false
    private var hashStoreError: Error?
    private var hashCompleted = 0
    private var hashTotal = 0

    init(
        configuration: NASAssessmentConfiguration,
        rootPath: String,
        rootDevice: Int32,
        store: NASAssessmentStore,
        reader: NASMeteredFileReader,
        fileSystem: NASScanFileSystem,
        now: @escaping @Sendable () -> Date,
        isCancelled: @escaping @Sendable () -> Bool,
        continuation: AsyncThrowingStream<NASAssessmentEvent, Error>.Continuation
    ) {
        self.configuration = configuration
        self.rootPath = rootPath
        self.rootDevice = rootDevice
        self.store = store
        self.reader = reader
        self.fileSystem = fileSystem
        self.now = now
        self.isCancelled = isCancelled
        self.continuation = continuation
    }

    func run() throws {
        // Step 3.
        startedAt = now()
        generation = try store.beginScan(mode: .exactOnly, startedAt: startedAt)
        do {
            try runPhases()
        } catch {
            // A store failure still leaves the scan row closed so it never looks like it is running.
            try? store.finishScan(generation: generation, outcome: .failed, counts: counts, ledger: ledger, finishedAt: now())
            throw error
        }
    }

    private func runPhases() throws {
        let previous = try store.latestGeneration(excluding: generation)
        continuation.yield(.started(generation: generation))
        continuation.yield(.phaseStarted(.enumerating))

        try enumerate()

        if !wasCancelled && !volumeLost {
            try markAndHash(previous: previous)
        }

        // Step 8.
        continuation.yield(.phaseStarted(.grouping))
        let outcome: NASScanOutcome
        if wasCancelled {
            outcome = .cancelled
        } else if volumeLost {
            outcome = .interruptedVolumeUnavailable
        } else if hasGap {
            outcome = .completedWithGaps
        } else {
            outcome = .complete
        }

        // Step 9.
        try store.finishScan(generation: generation, outcome: outcome, counts: counts, ledger: ledger, finishedAt: now())
        try store.pruneGenerations(keepingLatest: 2)
        let summary = try store.scanSummary(generation: generation) ?? NASScanSummary(
            generation: generation,
            mode: .exactOnly,
            startedAt: startedAt,
            finishedAt: now(),
            outcome: outcome,
            counts: counts,
            ledger: ledger,
            exactGroupCount: 0,
            redundantLogicalBytes: 0
        )
        continuation.yield(.finished(summary))
    }

    // MARK: Step 4 - enumeration

    private func enumerate() throws {
        var stack = [PendingDirectory(rawRelativePath: "", relativePath: "")]
        var directoriesSinceFlush = 0

        while let directory = stack.popLast() {
            if isCancelled() {
                wasCancelled = true
                break
            }
            var subdirectories: [PendingDirectory] = []
            let step = try autoreleasepool { try processDirectory(directory, subdirectories: &subdirectories) }
            switch step {
            case .cancelled:
                wasCancelled = true
            case .volumeLost:
                volumeLost = true
            case .proceed:
                break
            }
            if wasCancelled || volumeLost { break }
            // Sorted ascending; push reversed so the smallest name is traversed first.
            stack.append(contentsOf: subdirectories.reversed())

            directoriesSinceFlush += 1
            if directoriesSinceFlush >= max(1, configuration.checkpointDirectoryBatch) {
                try flushEnumerationBuffers()
                directoriesSinceFlush = 0
            }
        }
        try flushEnumerationBuffers()
    }

    private func processDirectory(_ directory: PendingDirectory, subdirectories: inout [PendingDirectory]) throws -> DirectoryStep {
        let directoryPath = directory.rawRelativePath.isEmpty ? rootPath : nasJoin(rootPath, directory.rawRelativePath)
        let names: [String]
        do {
            names = try fileSystem.listDirectory(directoryPath)
        } catch {
            directoryBuffer.append(NASDirectoryRow(relativePath: directory.relativePath, status: .unreadable))
            addIssue(
                NASIssue(
                    category: .unreadableDirectory,
                    relativePath: directory.relativePath,
                    detail: "Chronoframe couldn't open this folder, so its contents were not assessed."
                )
            )
            if fileSystem.entry(rootPath) == nil { return .volumeLost }
            return .proceed
        }

        let children = names.map { Child(rawName: $0, name: $0.precomposedStringWithCanonicalMapping) }.sorted { lhs, rhs in
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.rawName.utf8.lexicographicallyPrecedes(rhs.rawName.utf8)
        }

        var row = NASDirectoryRow(relativePath: directory.relativePath, status: .assessed)
        var seenNames = Set<String>()

        for (index, child) in children.enumerated() {
            if index % 256 == 255, isCancelled() { return .cancelled }
            if child.rawName.hasPrefix(".") { continue }

            let relativePath = nasRelative(directory.relativePath, child.name)
            let rawRelativePath = nasRelative(directory.rawRelativePath, child.rawName)
            guard seenNames.insert(child.name).inserted else {
                addIssue(
                    NASIssue(
                        category: .unreadableItem,
                        relativePath: relativePath,
                        detail: "Another item in this folder has the same name once accents are normalized, so this one was not assessed."
                    )
                )
                continue
            }

            let childPath = nasJoin(directoryPath, child.rawName)
            guard let entry = fileSystem.entry(childPath) else {
                addIssue(NASIssue(category: .unreadableItem, relativePath: relativePath, detail: "Chronoframe couldn't read this item's details."))
                consecutiveEntryFailures += 1
                if consecutiveEntryFailures >= entryFailuresBeforeRootProbe {
                    consecutiveEntryFailures = 0
                    if fileSystem.entry(rootPath) == nil {
                        // Same root-gone probe as the listing and hashing paths: the volume is
                        // gone, so end as interrupted instead of marking every child a gap.
                        directoryBuffer.append(NASDirectoryRow(relativePath: directory.relativePath, status: .unreadable))
                        return .volumeLost
                    }
                }
                continue
            }
            consecutiveEntryFailures = 0

            if entry.isSymbolicLink {
                addIssue(NASIssue(category: .skippedLink, relativePath: relativePath, detail: "Links are reported but never followed."))
            } else if entry.isDirectory {
                if NASSystemContainerRules.isExcludedSystemContainer(name: child.name) {
                    directoryBuffer.append(NASDirectoryRow(relativePath: relativePath, status: .excludedSystem))
                    addIssue(NASIssue(category: .excludedSystemContainer, relativePath: relativePath, detail: "NAS system folder, not part of your library."))
                } else if entry.isPackage {
                    directoryBuffer.append(NASDirectoryRow(relativePath: relativePath, status: .skippedPackage))
                    addIssue(NASIssue(category: .skippedPackage, relativePath: relativePath, detail: "Packages and bundles are reported but not opened."))
                } else if entry.deviceID != rootDevice {
                    directoryBuffer.append(NASDirectoryRow(relativePath: relativePath, status: .nestedMount))
                    addIssue(NASIssue(category: .nestedMount, relativePath: relativePath, detail: "A different volume is mounted here, so it was not entered."))
                } else {
                    if !nasSameSpelling(rawRelativePath, relativePath) { onDiskPaths[relativePath] = rawRelativePath }
                    subdirectories.append(PendingDirectory(rawRelativePath: rawRelativePath, relativePath: relativePath))
                }
            } else if entry.isRegularFile {
                if MediaLibraryRules.shouldSkipDiscoveredFile(named: child.rawName) { continue }
                if MediaLibraryRules.isSupportedMediaFile(path: childPath) {
                    let kind: NASItemKind = MediaLibraryRules.isVideoFile(path: childPath) ? .video : .photo
                    if !nasSameSpelling(rawRelativePath, relativePath) { onDiskPaths[relativePath] = rawRelativePath }
                    itemBuffer.append(NASItemRow(
                        relativePath: relativePath,
                        kind: kind,
                        size: entry.size,
                        modificationTime: entry.modificationTime,
                        fileID: entry.fileID
                    ))
                    row.mediaFileCount += 1
                    row.mediaBytes += entry.size
                    counts.mediaFiles += 1
                    counts.mediaBytes += entry.size
                } else {
                    row.unsupportedFileCount += 1
                    counts.unsupportedFiles += 1
                }
            } else {
                addIssue(NASIssue(category: .specialFile, relativePath: relativePath, detail: "Special files are reported but never opened."))
            }
        }

        directoryBuffer.append(row)
        counts.directoriesAssessed += 1
        yieldEnumerationProgress(currentRelativePath: directory.relativePath)
        return .proceed
    }

    private func addIssue(_ issue: NASIssue) {
        issueBuffer.append(issue)
        counts.issueCount += 1
        switch issue.category {
        case .unreadableDirectory, .unreadableItem, .unresolvedCandidate:
            hasGap = true
        case .skippedLink, .specialFile, .excludedSystemContainer, .skippedPackage, .nestedMount:
            break
        }
        continuation.yield(.issue(issue))
    }

    private func flushEnumerationBuffers() throws {
        if !directoryBuffer.isEmpty {
            try store.recordDirectories(directoryBuffer, generation: generation)
            directoryBuffer.removeAll(keepingCapacity: true)
        }
        if !itemBuffer.isEmpty {
            try store.recordItems(itemBuffer, generation: generation)
            itemBuffer.removeAll(keepingCapacity: true)
        }
        if !issueBuffer.isEmpty {
            try store.recordIssues(issueBuffer, generation: generation)
            issueBuffer.removeAll(keepingCapacity: true)
        }
    }

    private func yieldEnumerationProgress(currentRelativePath: String) {
        let time = ProcessInfo.processInfo.systemUptime
        guard time - lastProgressTime >= nasProgressInterval else { return }
        lastProgressTime = time
        continuation.yield(.enumerationProgress(
            directories: counts.directoriesAssessed,
            files: counts.mediaFiles + counts.unsupportedFiles,
            currentRelativePath: currentRelativePath
        ))
    }

    // MARK: Steps 5-7 - candidates, reuse, hashing

    private func markAndHash(previous: Int64?) throws {
        // Step 5.
        let marked = try store.markCandidates(generation: generation)
        counts.candidateFiles = marked.candidateFiles
        counts.emptyFiles = marked.emptyFiles
        ledger.candidateBytesH = marked.candidateBytesH

        // Step 6: reuse digests from the previous generation only after candidates are marked (D-NAS-110).
        let pending = try store.pendingItems(generation: generation)
        var remaining: [NASItemRow] = []
        var reused: [NASItemRow] = []
        if let previous {
            let earlier = try store.reusableDigests(generation: previous)
            for item in pending {
                if let old = earlier[item.relativePath],
                   old.hashState == .hashed,
                   let digest = old.digest,
                   old.size == item.size,
                   abs(old.modificationTime - item.modificationTime) < 0.001,
                   old.fileID == item.fileID {
                    var updated = item
                    updated.digest = digest
                    updated.hashState = .hashed
                    updated.unresolvedReason = nil
                    reused.append(updated)
                } else {
                    remaining.append(item)
                }
            }
        } else {
            remaining = pending
        }

        let batch = max(1, configuration.hashResultBatch)
        var index = 0
        while index < reused.count {
            let end = min(index + batch, reused.count)
            try store.updateHashResults(Array(reused[index..<end]), generation: generation)
            index = end
        }
        ledger.cacheHits = reused.count
        counts.hashedFiles = reused.count
        hashCompleted = reused.count

        // Step 7.
        continuation.yield(.phaseStarted(.hashing))
        hashTotal = pending.count
        try hash(remaining, total: pending.count)
    }

    private func hash(_ items: [NASItemRow], total: Int) throws {
        if !items.isEmpty {
            let workerCount = max(1, min(8, configuration.workerCount, items.count))
            let queue = DispatchQueue(label: "chronoframe.nas.assessment.hash", qos: .userInitiated, attributes: .concurrent)
            let group = DispatchGroup()
            for _ in 0..<workerCount {
                group.enter()
                queue.async { [self] in
                    defer { group.leave() }
                    hashWorker(items)
                }
            }
            group.wait()
        }

        hashLock.lock()
        defer { hashLock.unlock() }
        if let hashStoreError { throw hashStoreError }
        try flushHashResultsLocked()
        yieldHashingProgressLocked(total: total, force: true)
    }

    private func hashWorker(_ items: [NASItemRow]) {
        while true {
            hashLock.lock()
            if stopHashing || nextHashIndex >= items.count {
                hashLock.unlock()
                return
            }
            let item = items[nextHashIndex]
            nextHashIndex += 1
            hashLock.unlock()

            if isCancelled() {
                hashLock.lock()
                wasCancelled = true
                stopHashing = true
                hashLock.unlock()
                return
            }

            let outcome = autoreleasepool {
                reader.hash(
                    path: nasJoin(rootPath, onDiskPaths[item.relativePath] ?? item.relativePath),
                    expectedSize: item.size,
                    expectedModificationTime: item.modificationTime
                )
            }

            // Looking at the root happens outside the lock because it can block on a network share.
            var rootGone = false
            if case let .unresolved(reason, _, _) = outcome, reason == .openFailed || reason == .readFailed {
                rootGone = fileSystem.entry(rootPath) == nil
            }

            hashLock.lock()
            apply(outcome, to: item, rootGone: rootGone)
            hashLock.unlock()
        }
    }

    /// Must be called with `hashLock` held.
    private func apply(_ outcome: NASHashOutcome, to item: NASItemRow, rootGone: Bool) {
        var updated = item
        switch outcome {
        case let .hashed(identity, _, counters):
            updated.digest = identity.digest
            updated.hashState = .hashed
            updated.unresolvedReason = nil
            ledger.bytesReadClean += counters.bytesRead
            counts.hashedFiles += 1
        case let .unresolved(reason, _, counters):
            updated.digest = nil
            updated.hashState = .unresolved
            updated.unresolvedReason = reason
            ledger.bytesReadUnresolved += counters.bytesRead
            counts.unresolvedFiles += 1
            addIssue(NASIssue(category: .unresolvedCandidate, relativePath: item.relativePath, detail: reason.rawValue))
            if reason == .volumeUnavailable || rootGone {
                volumeLost = true
                stopHashing = true
            }
        }
        hashResultBuffer.append(updated)
        hashCompleted += 1

        if hashResultBuffer.count >= max(1, configuration.hashResultBatch) {
            do {
                try flushHashResultsLocked()
            } catch {
                hashStoreError = error
                stopHashing = true
            }
        }
        yieldHashingProgressLocked(total: hashTotal, force: false)
    }

    /// Must be called with `hashLock` held.
    private func flushHashResultsLocked() throws {
        if !hashResultBuffer.isEmpty {
            try store.updateHashResults(hashResultBuffer, generation: generation)
            hashResultBuffer.removeAll(keepingCapacity: true)
        }
        if !issueBuffer.isEmpty {
            try store.recordIssues(issueBuffer, generation: generation)
            issueBuffer.removeAll(keepingCapacity: true)
        }
    }

    /// Must be called with `hashLock` held.
    private func yieldHashingProgressLocked(total: Int, force: Bool) {
        let time = ProcessInfo.processInfo.systemUptime
        guard force || time - lastProgressTime >= nasProgressInterval else { return }
        lastProgressTime = time
        continuation.yield(.hashingProgress(
            completed: hashCompleted,
            total: total,
            bytesRead: ledger.bytesReadClean + ledger.bytesReadUnresolved
        ))
    }
}
