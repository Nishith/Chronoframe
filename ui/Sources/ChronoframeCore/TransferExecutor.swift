import Darwin
import Foundation
import os

public struct TransferExecutionObserver: Sendable {
    public var onPhaseStarted: @Sendable (_ total: Int, _ bytesTotal: Int64) -> Void
    public var onPhaseProgress: @Sendable (_ completed: Int, _ total: Int, _ bytesCopied: Int64, _ bytesTotal: Int64, _ currentSourcePath: String?) -> Void
    public var onIssue: @Sendable (_ issue: RunIssue) -> Void

    public init(
        onPhaseStarted: @escaping @Sendable (_ total: Int, _ bytesTotal: Int64) -> Void = { _, _ in },
        onPhaseProgress: @escaping @Sendable (_ completed: Int, _ total: Int, _ bytesCopied: Int64, _ bytesTotal: Int64, _ currentSourcePath: String?) -> Void = { _, _, _, _, _ in },
        onIssue: @escaping @Sendable (_ issue: RunIssue) -> Void = { _ in }
    ) {
        self.onPhaseStarted = onPhaseStarted
        self.onPhaseProgress = onPhaseProgress
        self.onIssue = onIssue
    }
}

public struct TransferExecutionResult: Equatable, Sendable {
    public var copiedCount: Int
    public var failedCount: Int
    public var skippedCount: Int
    public var bytesCopied: Int64
    public var bytesTotal: Int64
    public var status: String
    public var abortReason: String?
    public var artifacts: RunArtifactPaths

    public init(
        copiedCount: Int,
        failedCount: Int,
        skippedCount: Int = 0,
        bytesCopied: Int64,
        bytesTotal: Int64,
        status: String = "COMPLETED",
        abortReason: String? = nil,
        artifacts: RunArtifactPaths
    ) {
        self.copiedCount = copiedCount
        self.failedCount = failedCount
        self.skippedCount = skippedCount
        self.bytesCopied = bytesCopied
        self.bytesTotal = bytesTotal
        self.status = status
        self.abortReason = abortReason
        self.artifacts = artifacts
    }
}

struct TransferFileCopyStrategy: Sendable {
    var clone: @Sendable (_ sourcePath: String, _ destinationPath: String) -> Int32
    var copyAll: @Sendable (_ sourcePath: String, _ destinationPath: String) -> Int32
    var copyMetadata: @Sendable (_ sourcePath: String, _ destinationPath: String) -> Int32

    static let system = TransferFileCopyStrategy(
        clone: { sourcePath, destinationPath in
            sourcePath.withCString { sourcePointer in
                destinationPath.withCString { destinationPointer in
                    clonefile(sourcePointer, destinationPointer, 0)
                }
            }
        },
        copyAll: { sourcePath, destinationPath in
            sourcePath.withCString { sourcePointer in
                destinationPath.withCString { destinationPointer in
                    copyfile(sourcePointer, destinationPointer, nil, copyfile_flags_t(COPYFILE_ALL))
                }
            }
        },
        copyMetadata: { sourcePath, destinationPath in
            sourcePath.withCString { sourcePointer in
                destinationPath.withCString { destinationPointer in
                    copyfile(
                        sourcePointer,
                        destinationPointer,
                        nil,
                        copyfile_flags_t(COPYFILE_STAT | COPYFILE_XATTR | COPYFILE_ACL)
                    )
                }
            }
        }
    )
}

public final class PersistentRunLogger: @unchecked Sendable {
    public static let maxLogBytes: UInt64 = 5 * 1024 * 1024

    public let logURL: URL

    // OSAllocatedUnfairLock guards all access to `handle`, making concurrent
    // open/close/append calls safe from multiple async contexts.
    private let lock = OSAllocatedUnfairLock<FileHandle?>(initialState: nil)

    public init(logURL: URL) {
        self.logURL = logURL
    }

    deinit {
        close()
    }

    public func open() throws {
        try FileManager.default.createDirectory(
            at: logURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Rotate when the existing log is past the cap so the file stays bounded.
        // Keep at most one prior generation as <log>.1.
        if FileManager.default.fileExists(atPath: logURL.path),
           let attrs = try? FileManager.default.attributesOfItem(atPath: logURL.path),
           let size = attrs[.size] as? UInt64,
           size > Self.maxLogBytes {
            let rotatedURL = logURL.appendingPathExtension("1")
            try? FileManager.default.removeItem(at: rotatedURL)
            try? FileManager.default.moveItem(at: logURL, to: rotatedURL)
        }

        if !FileManager.default.fileExists(atPath: logURL.path) {
            FileManager.default.createFile(atPath: logURL.path, contents: Data())
        }

        let newHandle = try FileHandle(forWritingTo: logURL)
        try newHandle.seekToEnd()
        lock.withLock { $0 = newHandle }
    }

    public func close() {
        lock.withLock { handle in
            try? handle?.close()
            handle = nil
        }
    }

    public func log(_ message: String) {
        append(line: message)
    }

    public func warn(_ message: String) {
        append(line: "WARNING: \(message)")
    }

    public func error(_ message: String) {
        append(line: "ERROR: \(message)")
    }

    private func append(line: String) {
        let renderedLine = "[\(Self.timestampFormatter.string(from: Date()))] \(line)\n"
        guard let data = renderedLine.data(using: .utf8) else {
            return
        }

        lock.withLock { handle in
            try? handle?.write(contentsOf: data)
        }
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

public struct TransferExecutor: Sendable {
    public static let orphanedTemporarySuffix = ".tmp"
    public static let safetyBufferBytes: Int64 = 10 * 1024 * 1024
    public static let maxCollisionCount = 9_999
    public static let destinationCacheBatchSize = 256

    // Matches Chronoframe's own .tmp files only. Update both sides if the
    // filename convention changes.
    private static let chronoframeTmpPattern: NSRegularExpression? = try? NSRegularExpression(
        pattern: #"^(?:\d{4}-\d{2}-\d{2}|Unknown)_\d+(?:_collision_\d+)?\.[a-zA-Z0-9]+(?:\.[0-9a-fA-F-]{36})?\.tmp$"#
    )

    public var fileHasher: FileIdentityHasher
    public var retryPolicy: RetryPolicy
    public var failureThresholds: FailureThresholds
    public var namingRules: PlannerNamingRules
    var fileCopyStrategy: TransferFileCopyStrategy

    #if DEBUG
    public var isLowPowerModeEnabledProvider: @Sendable () -> Bool = { ProcessInfo.processInfo.isLowPowerModeEnabled }
    public var thermalStateProvider: @Sendable () -> ProcessInfo.ThermalState = { ProcessInfo.processInfo.thermalState }
    public var freeDiskSpaceProvider: @Sendable (String) -> Int64? = { path in
        var fileSystemStatus = statvfs()
        let result = path.withCString { pointer in
            statvfs(pointer, &fileSystemStatus)
        }
        guard result == 0 else { return nil }
        return Int64(fileSystemStatus.f_bavail) * Int64(fileSystemStatus.f_frsize)
    }
    #endif

    public init(
        fileHasher: FileIdentityHasher = FileIdentityHasher(),
        retryPolicy: RetryPolicy = .chronoframeDefault,
        failureThresholds: FailureThresholds = .chronoframeDefault,
        namingRules: PlannerNamingRules = .chronoframeDefault
    ) {
        self.fileHasher = fileHasher
        self.retryPolicy = retryPolicy
        self.failureThresholds = failureThresholds
        self.namingRules = namingRules
        self.fileCopyStrategy = .system
    }

    init(
        fileHasher: FileIdentityHasher = FileIdentityHasher(),
        retryPolicy: RetryPolicy = .chronoframeDefault,
        failureThresholds: FailureThresholds = .chronoframeDefault,
        namingRules: PlannerNamingRules = .chronoframeDefault,
        fileCopyStrategy: TransferFileCopyStrategy
    ) {
        self.fileHasher = fileHasher
        self.retryPolicy = retryPolicy
        self.failureThresholds = failureThresholds
        self.namingRules = namingRules
        self.fileCopyStrategy = fileCopyStrategy
    }

    public func artifactPaths(destinationRoot: URL) -> RunArtifactPaths {
        let logsDirectoryURL = destinationRoot.appendingPathComponent(
            EngineArtifactLayout.chronoframeDefault.logsDirectoryName,
            isDirectory: true
        )
        let logURL = destinationRoot.appendingPathComponent(EngineArtifactLayout.chronoframeDefault.runLogFilename)

        return RunArtifactPaths(
            destinationRoot: destinationRoot.path,
            reportPath: nil,
            logFilePath: logURL.path,
            logsDirectoryPath: logsDirectoryURL.path
        )
    }

    public func cleanupTemporaryFiles(at destinationRoot: URL) -> Int {
        guard let enumerator = FileManager.default.enumerator(
            at: destinationRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var cleanedCount = 0
        for case let fileURL as URL in enumerator {
            let filename = fileURL.lastPathComponent
            guard filename.hasSuffix(Self.orphanedTemporarySuffix) else { continue }
            guard let pattern = Self.chronoframeTmpPattern else { continue }

            let range = NSRange(filename.startIndex..<filename.endIndex, in: filename)
            guard pattern.firstMatch(in: filename, range: range) != nil else { continue }

            do {
                try FileManager.default.removeItem(at: fileURL)
                cleanedCount += 1
            } catch {
                continue
            }
        }

        return cleanedCount
    }

    /// Phase 1 finding #3: detect audit receipts left in PENDING state
    /// by a crashed run, read the associated `.transfers.tmp` spool,
    /// and rewrite the receipt as an ABORTED receipt that includes the
    /// transfers actually completed before the interruption. The user
    /// then sees the recovered run in Run History and can revert it
    /// like any other run.
    ///
    /// Best-effort: any failure leaves the PENDING receipt + spool in
    /// place for the next attempt. Returns the number of receipts
    /// successfully consolidated.
    @discardableResult
    public func recoverInterruptedRuns(at destinationRoot: URL) -> Int {
        let logsDirectory = destinationRoot.appendingPathComponent(
            EngineArtifactLayout.chronoframeDefault.logsDirectoryName,
            isDirectory: true
        )
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return 0
        }

        var recovered = 0
        for receiptURL in files where receiptURL.lastPathComponent.hasPrefix(
            EngineArtifactLayout.chronoframeDefault.auditReceiptPrefix
        ) && receiptURL.pathExtension == "json" {
            guard let data = try? Data(contentsOf: receiptURL),
                  let raw = try? JSONSerialization.jsonObject(with: data),
                  let receipt = raw as? [String: Any],
                  (receipt["status"] as? String) == "PENDING"
            else {
                continue
            }
            let stem = receiptURL.deletingPathExtension().lastPathComponent
            let spoolURL = logsDirectory.appendingPathComponent("\(stem).transfers.tmp")
            // Try to consolidate; on failure, leave the receipt for the
            // next pass instead of removing it.
            if consolidatePendingReceipt(
                receiptURL: receiptURL,
                spoolURL: spoolURL,
                header: receipt
            ) {
                recovered += 1
            }
        }
        return recovered
    }

    private func consolidatePendingReceipt(
        receiptURL: URL,
        spoolURL: URL,
        header: [String: Any]
    ) -> Bool {
        // Read the spool's contents as a UTF-8 substring. The spool is
        // already JSON-array-element-shaped (each entry is a `{...}`
        // object indented by four spaces and comma-separated), exactly
        // matching what `pipeTransferSpool` writes into the receipt's
        // "transfers" array during normal `finish()`.
        let spoolBody: String
        if FileManager.default.fileExists(atPath: spoolURL.path),
           let data = try? Data(contentsOf: spoolURL),
           let body = String(data: data, encoding: .utf8) {
            spoolBody = body
        } else {
            spoolBody = ""
        }

        // Compose a final receipt that reflects "this run was
        // interrupted; here is what completed before". Status is
        // ABORTED rather than COMPLETED so callers can distinguish.
        var out = "{\n"
        out += "  \"schemaVersion\" : 2,\n"
        if let runID = header["runID"] as? String {
            out += "  \"runID\" : \(jsonStringEscape(runID)),\n"
        }
        out += "  \"operation\" : \"organize\",\n"
        out += "  \"status\" : \"ABORTED\",\n"
        if let timestamp = header["timestamp"] as? String {
            out += "  \"timestamp\" : \(jsonStringEscape(timestamp)),\n"
        }
        if let startedAt = header["startedAt"] as? String {
            out += "  \"startedAt\" : \(jsonStringEscape(startedAt)),\n"
        }
        out += "  \"recoveredAt\" : \(jsonStringEscape(ISO8601DateFormatter().string(from: Date()))),\n"
        out += "  \"abortReason\" : \"Chronoframe was interrupted before this run finished. The transfers below completed and are revertable.\",\n"
        out += "  \"transfers\" : [\n"
        out += sanitizedSpoolBody(spoolBody)
        out += "\n  ]\n}\n"

        let tempURL = receiptURL.appendingPathExtension("recovery.tmp")
        do {
            try out.data(using: .utf8)?.write(to: tempURL, options: [.atomic])
            try FileManager.default.removeItem(at: receiptURL)
            try FileManager.default.moveItem(at: tempURL, to: receiptURL)
            try? FileManager.default.removeItem(at: spoolURL)
            return true
        } catch {
            try? FileManager.default.removeItem(at: tempURL)
            return false
        }
    }

    /// Parse the transfer spool into individually-validated JSON object
    /// fragments and re-frame them for embedding in the receipt's
    /// "transfers" array. A process can be SIGKILL'd / lose power between
    /// `appendTransfer`'s separate `,\n`, indent, and object writes, leaving
    /// the spool ending in a trailing separator or a half-written object.
    /// Splicing that raw tail into the receipt produced invalid JSON that
    /// `RevertExecutor.loadReceipt` then rejected — losing revertability for
    /// the *entire* recovered run, not just the partial last entry. Each
    /// `appendTransfer` object is compact (no interior newlines), so the
    /// `,\n` separator is unambiguous; we validate every fragment as a JSON
    /// object and drop only the malformed trailing one.
    private func sanitizedSpoolBody(_ body: String) -> String {
        body
            .components(separatedBy: ",\n")
            .compactMap { fragment -> String? in
                let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
                guard
                    !trimmed.isEmpty,
                    let data = trimmed.data(using: .utf8),
                    let object = try? JSONSerialization.jsonObject(with: data),
                    object is [String: Any]
                else {
                    return nil
                }
                return "    " + trimmed
            }
            .joined(separator: ",\n")
    }

    private func jsonStringEscape(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.fragmentsAllowed]
        ) else {
            return "\"\""
        }
        return String(data: data, encoding: .utf8) ?? "\"\""
    }

    public func execute(
        queuedJobs: [QueuedCopyJob],
        database: OrganizerDatabase,
        destinationRoot: URL,
        verifyCopies: Bool,
        runLogger: PersistentRunLogger,
        maxConcurrentCopies: Int = 1,
        observer: TransferExecutionObserver = TransferExecutionObserver(),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> TransferExecutionResult {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Chronoframe: active photo/video transfer"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }

        let totalJobs = queuedJobs.count
        let bytesTotal = queuedJobs.reduce(into: Int64(0)) { partialResult, job in
            partialResult += safeFileSize(atPath: job.sourcePath) ?? 0
        }
        let context = try TransferExecutionContext(
            executor: self,
            database: database,
            destinationRoot: destinationRoot,
            verifyCopies: verifyCopies,
            runLogger: runLogger,
            observer: observer,
            isCancelled: isCancelled,
            totalJobs: totalJobs,
            bytesTotal: bytesTotal
        )
        context.start()

        if maxConcurrentCopies > 1 {
            return try executeParallel(
                queuedJobs: queuedJobs,
                context: context,
                maxConcurrentCopies: maxConcurrentCopies,
                isCancelled: isCancelled
            )
        }

        var attemptedJobs = 0
        for job in queuedJobs {
            if isCancelled() {
                break
            }

            attemptedJobs += 1
            let shouldContinue = try context.process(job: job, attemptedJobs: attemptedJobs)
            if !shouldContinue {
                break
            }
        }

        return try context.finish(attemptedJobs: attemptedJobs)
    }

    public func executeQueuedJobs(
        database: OrganizerDatabase,
        destinationRoot: URL,
        verifyCopies: Bool,
        runLogger: PersistentRunLogger,
        status: CopyJobStatus = .pending,
        orderByInsertion: Bool = true,
        batchSize: Int = 512,
        maxConcurrentCopies: Int = 1,
        observer: TransferExecutionObserver = TransferExecutionObserver(),
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) throws -> TransferExecutionResult {
        let activity = ProcessInfo.processInfo.beginActivity(
            options: [.idleSystemSleepDisabled, .userInitiated],
            reason: "Chronoframe: active photo/video transfer"
        )
        defer {
            ProcessInfo.processInfo.endActivity(activity)
        }

        if maxConcurrentCopies > 1 {
            let totalJobs = try database.queuedJobCount(status: status)
            let bytesTotal = try totalBytesForQueuedJobs(
                database: database,
                status: status,
                orderByInsertion: orderByInsertion,
                batchSize: batchSize
            )
            let context = try TransferExecutionContext(
                executor: self,
                database: database,
                destinationRoot: destinationRoot,
                verifyCopies: verifyCopies,
                runLogger: runLogger,
                observer: observer,
                isCancelled: isCancelled,
                totalJobs: totalJobs,
                bytesTotal: bytesTotal
            )
            context.start()

            var attemptedJobs = 0
            var lastThrottledReason: String? = nil

            do {
                try database.enumerateQueuedJobBatches(
                    status: status,
                    orderByInsertion: orderByInsertion,
                    batchSize: batchSize
                ) { batch in
                    if isCancelled() {
                        throw TransferExecutionStopSignal.stopRequested
                    }

                    var batchStart = 0
                    while batchStart < batch.count {
                        if isCancelled() {
                            throw TransferExecutionStopSignal.stopRequested
                        }

                        let (concurrency, currentReason) = determineConcurrency(requested: maxConcurrentCopies)

                        if currentReason != lastThrottledReason {
                            lastThrottledReason = currentReason
                            if let reason = currentReason {
                                context.observer.onIssue(RunIssue(severity: .warning, message: "Running gently: \(reason)"))
                            } else {
                                context.observer.onIssue(RunIssue(severity: .warning, message: "Resuming standard speed: Low Power Mode/Thermal restriction cleared"))
                            }
                        }

                        let batchEnd = min(batchStart + concurrency, batch.count)
                        let batchJobs = Array(batch[batchStart..<batchEnd])

                        let outcomes = runBlockingPrepare(
                            batchJobs: batchJobs,
                            context: context,
                            concurrency: concurrency
                        )

                        for offset in batchJobs.indices {
                            if isCancelled() {
                                outcomes.removePreparedCopies(after: offset - 1, runLogger: runLogger, executor: self)
                                throw TransferExecutionStopSignal.stopRequested
                            }

                            attemptedJobs += 1
                            let shouldContinue = try context.apply(
                                outcome: outcomes.value(at: offset),
                                for: batchJobs[offset],
                                attemptedJobs: attemptedJobs
                            )
                            if !shouldContinue {
                                outcomes.removePreparedCopies(after: offset, runLogger: runLogger, executor: self)
                                throw TransferExecutionStopSignal.stopRequested
                            }
                        }

                        batchStart = batchEnd
                    }
                }
            } catch TransferExecutionStopSignal.stopRequested {
                // Stop requested via cancellation or abort threshold.
            }

            return try context.finish(attemptedJobs: attemptedJobs)
        }

        let totalJobs = try database.queuedJobCount(status: status)
        let bytesTotal = try totalBytesForQueuedJobs(
            database: database,
            status: status,
            orderByInsertion: orderByInsertion,
            batchSize: batchSize
        )
        let context = try TransferExecutionContext(
            executor: self,
            database: database,
            destinationRoot: destinationRoot,
            verifyCopies: verifyCopies,
            runLogger: runLogger,
            observer: observer,
            isCancelled: isCancelled,
            totalJobs: totalJobs,
            bytesTotal: bytesTotal
        )
        context.start()

        var attemptedJobs = 0

        do {
            try database.enumerateQueuedJobBatches(
                status: status,
                orderByInsertion: orderByInsertion,
                batchSize: batchSize
            ) { batch in
                for job in batch {
                    if isCancelled() {
                        throw TransferExecutionStopSignal.stopRequested
                    }

                    attemptedJobs += 1
                    // Drain autoreleased URL/NSString/FileManager temporaries per job;
                    // across 14k+ copies this otherwise retains until the outer call returns.
                    let shouldContinue: Bool = try autoreleasepool {
                        try context.process(job: job, attemptedJobs: attemptedJobs)
                    }
                    if !shouldContinue {
                        throw TransferExecutionStopSignal.stopRequested
                    }
                }
            }
        } catch TransferExecutionStopSignal.stopRequested {
            // Stop requested via cancellation or abort threshold.
        }

        return try context.finish(attemptedJobs: attemptedJobs)
    }

    private func executeParallel(
        queuedJobs: [QueuedCopyJob],
        context: TransferExecutionContext,
        maxConcurrentCopies: Int,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> TransferExecutionResult {
        var attemptedJobs = 0
        var batchStart = 0
        var lastThrottledReason: String? = nil

        while batchStart < queuedJobs.count {
            if isCancelled() {
                break
            }

            let (concurrency, currentReason) = determineConcurrency(requested: maxConcurrentCopies)

            if currentReason != lastThrottledReason {
                lastThrottledReason = currentReason
                if let reason = currentReason {
                    context.observer.onIssue(RunIssue(severity: .warning, message: "Running gently: \(reason)"))
                } else {
                    context.observer.onIssue(RunIssue(severity: .warning, message: "Resuming standard speed: Low Power Mode/Thermal restriction cleared"))
                }
            }

            let batchEnd = min(batchStart + concurrency, queuedJobs.count)
            let batchJobs = Array(queuedJobs[batchStart..<batchEnd])

            let outcomes = runBlockingPrepare(
                batchJobs: batchJobs,
                context: context,
                concurrency: concurrency
            )

            for offset in batchJobs.indices {
                if isCancelled() {
                    outcomes.removePreparedCopies(after: offset - 1, runLogger: context.runLogger, executor: self)
                    return try context.finish(attemptedJobs: attemptedJobs)
                }

                attemptedJobs += 1
                let shouldContinue = try context.apply(
                    outcome: outcomes.value(at: offset),
                    for: batchJobs[offset],
                    attemptedJobs: attemptedJobs
                )
                if !shouldContinue {
                    outcomes.removePreparedCopies(after: offset, runLogger: context.runLogger, executor: self)
                    return try context.finish(attemptedJobs: attemptedJobs)
                }
            }

            batchStart = batchEnd
        }

        return try context.finish(attemptedJobs: attemptedJobs)
    }

    func determineConcurrency(requested: Int) -> (Int, String?) {
        #if DEBUG
        let isLPM = isLowPowerModeEnabledProvider()
        let thermal = thermalStateProvider()
        #else
        let isLPM = ProcessInfo.processInfo.isLowPowerModeEnabled
        let thermal = ProcessInfo.processInfo.thermalState
        #endif

        if isLPM {
            return (1, "Low Power Mode is on")
        }
        if thermal == .serious || thermal == .critical {
            return (1, "Device thermal state is elevated")
        }

        let activeProcessors = ProcessInfo.processInfo.activeProcessorCount
        let maxLimit = min(max(4, activeProcessors), 6)
        let concurrency = min(max(1, requested), maxLimit)
        return (concurrency, nil)
    }

    private func runBlockingPrepare(
        batchJobs: [QueuedCopyJob],
        context: TransferExecutionContext,
        concurrency: Int
    ) -> ParallelTransferOutcomes {
        let outcomes = ParallelTransferOutcomes(count: batchJobs.count)
        let verifyCopies = context.verifyCopies
        let runLogger = context.runLogger
        let isCancelledRef = context.isCancelled
        let observerRef = context.observer

        let semaphore = DispatchSemaphore(value: concurrency)
        let group = DispatchGroup()

        for (offset, job) in batchJobs.enumerated() {
            semaphore.wait()
            DispatchQueue.global().async(group: group) {
                let outcome = autoreleasepool {
                    self.prepareCopy(
                        job: job,
                        verifyCopies: verifyCopies,
                        runLogger: runLogger,
                        isCancelled: isCancelledRef,
                        onIssue: { issue in observerRef.onIssue(issue) }
                    )
                }
                outcomes.store(outcome, at: offset)
                semaphore.signal()
            }
        }

        group.wait()
        return outcomes
    }

    func abortReason(
        consecutiveFailures: Int,
        totalFailures: Int,
        attemptedJobs: Int
    ) -> String? {
        if consecutiveFailures >= failureThresholds.consecutive {
            return "Aborting: \(consecutiveFailures) consecutive failures (out of \(attemptedJobs) attempted)"
        }
        if totalFailures >= failureThresholds.total {
            return "Aborting: \(totalFailures) total failures (out of \(attemptedJobs) attempted)"
        }
        return nil
    }

    fileprivate func removeUnverifiedCopyIfNeeded(
        atPath path: String,
        runLogger: PersistentRunLogger
    ) {
        do {
            if FileManager.default.fileExists(atPath: path) {
                try FileManager.default.removeItem(atPath: path)
            }
        } catch {
            runLogger.warn("Failed to remove unverified copy: \(path): \(error.localizedDescription)")
        }
    }

    func flushDestinationUpdates(
        _ updates: [RawFileCacheRecord],
        database: OrganizerDatabase
    ) throws {
        guard !updates.isEmpty else {
            return
        }

        try database.saveRawCacheRecords(updates)
    }

    fileprivate func prepareCopy(
        job: QueuedCopyJob,
        verifyCopies: Bool,
        runLogger: PersistentRunLogger,
        precomputedSourceIdentity: FileIdentity? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onIssue: @escaping @Sendable (RunIssue) -> Void = { _ in }
    ) -> TransferJobOutcome {
        do {
            // The serial path re-hashes the source in `process()` to decide
            // whether to skip; reuse that identity instead of reading the
            // whole file a second time. The parallel path passes nil and
            // hashes here once.
            let identity = try precomputedSourceIdentity
                ?? fileHasher.hashIdentity(at: URL(fileURLWithPath: job.sourcePath))
            if isTrustedPlannedIdentity(job.hash), identity.rawValue != job.hash {
                let message = "Source modified since planning, skipping: \(job.sourcePath)"
                return .skipped(message: message, logMessage: message)
            }
        } catch {
            let message = "Source unreadable, skipping: \(job.sourcePath): \(error.localizedDescription)"
            return .skipped(message: message, logMessage: message)
        }

        do {
            let temporaryPath = try prepareAtomicCopyWithRetry(
                sourcePath: job.sourcePath,
                requestedDestinationPath: job.destinationPath,
                isCancelled: isCancelled,
                onIssue: onIssue
            )

            var verifiedHash: String?
            if verifyCopies {
                do {
                    let verifiedIdentity = try fileHasher.hashIdentity(at: URL(fileURLWithPath: temporaryPath))
                    verifiedHash = verifiedIdentity.rawValue
                    if verifiedIdentity.rawValue != job.hash {
                        removeUnverifiedCopyIfNeeded(atPath: temporaryPath, runLogger: runLogger)
                        return .failed(
                            message: "Verification failed: \(job.sourcePath) -> \(job.destinationPath)",
                            logMessage: "Verification failed: \(job.sourcePath) → \(job.destinationPath)"
                        )
                    }
                } catch {
                    runLogger.warn("Verification could not read prepared copy; temp copy retained for cleanup: \(temporaryPath): \(error.localizedDescription)")
                    return .failed(
                        message: "Verification could not read the prepared copy, so Chronoframe did not finalize it: \(job.destinationPath)",
                        logMessage: "Verification hash error before finalize: \(job.sourcePath) → \(job.destinationPath): \(error.localizedDescription)"
                    )
                }
            }

            return .prepared(temporaryPath: temporaryPath, verifiedHash: verifiedHash)
        } catch {
            return .failed(
                message: "Copy failed: \(job.sourcePath) -> \(job.destinationPath): \(error.localizedDescription)",
                logMessage: "Copy failed: \(job.sourcePath) → \(job.destinationPath): \(error.localizedDescription)"
            )
        }
    }

    private func prepareAtomicCopy(
        sourcePath: String,
        requestedDestinationPath: String,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onIssue: @escaping @Sendable (RunIssue) -> Void = { _ in }
    ) throws -> String {
        let destinationURL = URL(fileURLWithPath: requestedDestinationPath)
        let destinationDirectoryURL = destinationURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: destinationDirectoryURL, withIntermediateDirectories: true)
        try checkDiskSpace(
            sourcePath: sourcePath,
            destinationDirectoryPath: destinationDirectoryURL.path,
            isCancelled: isCancelled,
            onIssue: onIssue
        )

        let temporaryDestinationPath = try uniqueTemporaryCopyPath(for: requestedDestinationPath)

        do {
            try copyFileContents(from: sourcePath, to: temporaryDestinationPath)
            try fsyncFile(atPath: temporaryDestinationPath)
            return temporaryDestinationPath
        } catch {
            if FileManager.default.fileExists(atPath: temporaryDestinationPath) {
                try? FileManager.default.removeItem(atPath: temporaryDestinationPath)
            }
            throw error
        }
    }

    private func prepareAtomicCopyWithRetry(
        sourcePath: String,
        requestedDestinationPath: String,
        isCancelled: @escaping @Sendable () -> Bool,
        onIssue: @escaping @Sendable (RunIssue) -> Void
    ) throws -> String {
        var lastError: Error?

        for attempt in 1...max(1, retryPolicy.maxAttempts) {
            do {
                return try prepareAtomicCopy(
                    sourcePath: sourcePath,
                    requestedDestinationPath: requestedDestinationPath,
                    isCancelled: isCancelled,
                    onIssue: onIssue
                )
            } catch {
                lastError = error
                guard shouldRetry(after: error), attempt < retryPolicy.maxAttempts else {
                    throw error
                }

                let backoff = min(
                    retryPolicy.maximumBackoffSeconds,
                    max(
                        retryPolicy.minimumBackoffSeconds,
                        pow(2, Double(attempt - 1)) * retryPolicy.minimumBackoffSeconds
                    )
                )
                Thread.sleep(forTimeInterval: backoff)
                if isCancelled() { throw error }
            }
        }

        throw lastError ?? CocoaError(.fileWriteUnknown)
    }

    fileprivate func finalizePreparedCopy(
        temporaryPath: String,
        requestedDestinationPath: String,
        beforeRename: (String) throws -> Void = { _ in }
    ) throws -> (destinationPath: String, size: Int64, modificationTime: TimeInterval) {
        var lastExclusiveRenameError: Error?

        for _ in 0...Self.maxCollisionCount {
            let finalDestinationPath = try collisionResolvedPath(for: requestedDestinationPath)
            do {
                // Persist the exact collision-free destination before the
                // namespace mutation. Recovery can now distinguish a missing
                // final from a finalized copy after process termination.
                try beforeRename(finalDestinationPath)
                try renameFile(from: temporaryPath, to: finalDestinationPath)
                let fileAttributes = try FileManager.default.attributesOfItem(atPath: finalDestinationPath)
                return (
                    destinationPath: finalDestinationPath,
                    size: (fileAttributes[.size] as? NSNumber)?.int64Value ?? 0,
                    modificationTime: (fileAttributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                )
            } catch {
                guard posixCode(from: error) == .EEXIST else {
                    throw error
                }
                lastExclusiveRenameError = error
            }
        }

        throw lastExclusiveRenameError ?? posixError(
            code: EEXIST,
            description: "Too many collisions for destination path: \(requestedDestinationPath)"
        )
    }

    func collisionResolvedPath(for requestedPath: String) throws -> String {
        if !FileManager.default.fileExists(atPath: requestedPath) {
            return requestedPath
        }

        let requestedURL = URL(fileURLWithPath: requestedPath)
        let destinationDirectoryURL = requestedURL.deletingLastPathComponent()
        let extensionName = requestedURL.pathExtension
        let basename = requestedURL.deletingPathExtension().lastPathComponent

        for collisionIndex in 1...Self.maxCollisionCount {
            let filename: String
            if extensionName.isEmpty {
                filename = "\(basename)\(namingRules.collisionSuffixPrefix)\(collisionIndex)"
            } else {
                filename = "\(basename)\(namingRules.collisionSuffixPrefix)\(collisionIndex).\(extensionName)"
            }

            let candidatePath = destinationDirectoryURL.appendingPathComponent(filename).path
            if !FileManager.default.fileExists(atPath: candidatePath) {
                return candidatePath
            }
        }

        throw posixError(code: EEXIST, description: "Too many collisions for destination path: \(requestedPath)")
    }

    private func uniqueTemporaryCopyPath(for requestedPath: String) throws -> String {
        for _ in 0...Self.maxCollisionCount {
            let candidatePath = "\(requestedPath).\(UUID().uuidString)\(Self.orphanedTemporarySuffix)"
            if !FileManager.default.fileExists(atPath: candidatePath) {
                return candidatePath
            }
        }

        throw posixError(code: EEXIST, description: "Too many temporary copy collisions for destination path: \(requestedPath)")
    }

    private func checkDiskSpace(
        sourcePath: String,
        destinationDirectoryPath: String,
        isCancelled: @escaping @Sendable () -> Bool = { false },
        onIssue: @escaping @Sendable (RunIssue) -> Void = { _ in }
    ) throws {
        guard let sourceSize = safeFileSize(atPath: sourcePath) else {
            return
        }

        var warnedLowSpace = false

        while !isCancelled() {
            #if DEBUG
            let freeBytesOpt = freeDiskSpaceProvider(destinationDirectoryPath)
            #else
            var fileSystemStatus = statvfs()
            let result = destinationDirectoryPath.withCString { pointer in
                statvfs(pointer, &fileSystemStatus)
            }
            let freeBytesOpt: Int64? = (result == 0) ? (Int64(fileSystemStatus.f_bavail) * Int64(fileSystemStatus.f_frsize)) : nil
            #endif

            guard let freeBytes = freeBytesOpt else {
                return
            }

            if freeBytes >= sourceSize + Self.safetyBufferBytes {
                if warnedLowSpace {
                    onIssue(RunIssue(severity: .warning, message: "Disk space check passed. Resuming run."))
                }
                return
            }

            warnedLowSpace = true
            let mbFree = freeBytes / (1024 * 1024)
            let mbNeeded = (sourceSize + Self.safetyBufferBytes) / (1024 * 1024)
            onIssue(RunIssue(
                severity: .warning,
                message: "Paused: Insufficient disk space on destination (\(mbFree) MB free, \(mbNeeded) MB needed). Free up space to resume automatically."
            ))

            Thread.sleep(forTimeInterval: 2.0)
        }

        throw posixError(
            code: ENOSPC,
            description: "Run cancelled while waiting for disk space."
        )
    }

    private func copyFileContents(from sourcePath: String, to destinationPath: String) throws {
        let cloneResult = fileCopyStrategy.clone(sourcePath, destinationPath)
        if cloneResult == 0 {
            _ = fileCopyStrategy.copyMetadata(sourcePath, destinationPath)
            return
        }

        let result = fileCopyStrategy.copyAll(sourcePath, destinationPath)
        guard result == 0 else {
            throw currentPOSIXError()
        }
    }

    private func fsyncFile(atPath path: String) throws {
        let fileDescriptor = open(path, O_RDWR)
        guard fileDescriptor >= 0 else {
            throw currentPOSIXError()
        }
        defer {
            close(fileDescriptor)
        }

        // F_FULLFSYNC flushes all the way to the storage device on macOS,
        // unlike fsync() which only guarantees flush to the disk controller.
        guard fcntl(fileDescriptor, F_FULLFSYNC) == 0 else {
            throw currentPOSIXError()
        }
    }

    private func renameFile(from sourcePath: String, to destinationPath: String) throws {
        let result = sourcePath.withCString { sourcePointer in
            destinationPath.withCString { destinationPointer in
                renamex_np(sourcePointer, destinationPointer, UInt32(RENAME_EXCL))
            }
        }
        guard result == 0 else {
            throw currentPOSIXError()
        }
        // Phase 1 finding (P1, ranked-out from Top 10): fsync the parent
        // directory after the rename so the directory entry survives
        // power loss between rename and inode-cache flush. Without this,
        // a clean COMPLETED run could lose its destination file on
        // sudden reboot even though the file's own contents were
        // F_FULLFSYNC'd before rename. APFS is durable-enough in
        // practice that this rarely bites, but the safety contract
        // requires the parent-dir fsync to actually make a completed
        // run crash-recoverable.
        fsyncParentDirectory(of: destinationPath)
    }

    /// Best-effort fsync of the directory containing `childPath`. Logs
    /// nothing on failure: if the directory itself disappeared or was
    /// unmounted between the rename and this fsync, the rename has
    /// already returned success and the caller's contract is unaffected.
    private func fsyncParentDirectory(of childPath: String) {
        let parentPath = (childPath as NSString).deletingLastPathComponent
        guard !parentPath.isEmpty else { return }
        let descriptor = open(parentPath, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_FULLFSYNC)
    }

    private func shouldRetry(after error: Error) -> Bool {
        let code = posixCode(from: error)
        guard let code else {
            return false
        }

        return !retryPolicy.nonRetryableErrnos.contains(Int32(code.rawValue))
    }

    func safeFileSize(atPath path: String) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    private func totalBytesForQueuedJobs(
        database: OrganizerDatabase,
        status: CopyJobStatus,
        orderByInsertion: Bool,
        batchSize: Int
    ) throws -> Int64 {
        var bytesTotal: Int64 = 0
        try database.enumerateQueuedJobBatches(
            status: status,
            orderByInsertion: orderByInsertion,
            batchSize: batchSize
        ) { batch in
            for job in batch {
                bytesTotal += safeFileSize(atPath: job.sourcePath) ?? 0
            }
        }
        return bytesTotal
    }

    private func currentPOSIXError() -> NSError {
        posixError(code: errno, description: String(cString: strerror(errno)))
    }

    private func posixError(code: Int32, description: String) -> NSError {
        NSError(
            domain: NSPOSIXErrorDomain,
            code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: description]
        )
    }

    private func posixCode(from error: Error) -> POSIXErrorCode? {
        let nsError = error as NSError
        guard nsError.domain == NSPOSIXErrorDomain else {
            return nil
        }
        return POSIXErrorCode(rawValue: Int32(nsError.code))
    }

    fileprivate static let receiptTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()
}

private enum TransferExecutionStopSignal: Error {
    case stopRequested
}

fileprivate enum TransferJobOutcome: Sendable {
    case prepared(temporaryPath: String, verifiedHash: String?)
    case copied(destinationPath: String, size: Int64, modificationTime: TimeInterval, verifiedHash: String?)
    case failed(message: String, logMessage: String)
    case skipped(message: String, logMessage: String)
}

private final class ParallelTransferOutcomes: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [TransferJobOutcome?]

    init(count: Int) {
        storage = Array(repeating: nil, count: count)
    }

    func store(_ outcome: TransferJobOutcome, at index: Int) {
        lock.lock()
        storage[index] = outcome
        lock.unlock()
    }

    func value(at index: Int) -> TransferJobOutcome {
        lock.lock()
        let outcome = storage[index]
        lock.unlock()
        return outcome ?? .failed(message: "Copy was cancelled before it started.", logMessage: "Copy was cancelled before it started.")
    }

    func removePreparedCopies(after appliedIndex: Int, runLogger: PersistentRunLogger, executor: TransferExecutor) {
        lock.lock()
        let remaining = Array(storage.dropFirst(appliedIndex + 1))
        lock.unlock()

        for outcome in remaining {
            guard case let .prepared(temporaryPath, _) = outcome else {
                continue
            }
            executor.removeUnverifiedCopyIfNeeded(atPath: temporaryPath, runLogger: runLogger)
        }
    }
}

private final class StreamingAuditReceiptWriter {
    private let finalReceiptURL: URL
    private let transferSpoolURL: URL
    private let createdAt: Date
    private let timestampString: String
    private let runID: UUID
    private let fileManager: FileManager

    private var spoolHandle: FileHandle?
    private var transferCount = 0
    private var finished = false

    init(
        destinationRoot: URL,
        fileManager: FileManager = .default,
        createdAt: Date = Date()
    ) throws {
        self.fileManager = fileManager
        self.createdAt = createdAt
        self.timestampString = ISO8601DateFormatter().string(from: createdAt)
        self.runID = UUID()

        let logsDirectoryURL = destinationRoot.appendingPathComponent(
            EngineArtifactLayout.chronoframeDefault.logsDirectoryName,
            isDirectory: true
        )
        try fileManager.createDirectory(at: logsDirectoryURL, withIntermediateDirectories: true)

        let stem = "\(EngineArtifactLayout.chronoframeDefault.auditReceiptPrefix)\(TransferExecutor.receiptTimestampFormatter.string(from: createdAt))_\(runID.uuidString)"
        self.finalReceiptURL = logsDirectoryURL.appendingPathComponent("\(stem).json")
        self.transferSpoolURL = logsDirectoryURL.appendingPathComponent("\(stem).transfers.tmp")

        fileManager.createFile(atPath: transferSpoolURL.path, contents: Data())
        self.spoolHandle = try FileHandle(forWritingTo: transferSpoolURL)

        // Phase 1 finding #3: write a PENDING receipt header BEFORE
        // any transfer happens. If the run dies (SIGKILL, power loss,
        // app crash) before `finish()` runs, the next engine startup
        // sees this PENDING receipt + its spool and consolidates them
        // into a recoverable ABORTED receipt — so files left in the
        // destination after a crashed run are revertable from Run
        // History instead of becoming orphaned forever.
        try writePendingHeader(in: logsDirectoryURL)
    }

    private func writePendingHeader(in logsDirectoryURL: URL) throws {
        let pendingJSON: [String: Any] = [
            "schemaVersion": 2,
            "runID": runID.uuidString,
            "operation": "organize",
            "status": "PENDING",
            "timestamp": timestampString,
            "startedAt": timestampString,
            "transferSpool": transferSpoolURL.lastPathComponent,
            "transfers": [],
        ]
        let data = try JSONSerialization.data(
            withJSONObject: pendingJSON,
            options: [.prettyPrinted, .sortedKeys]
        )
        try ReceiptDurability.durablyWrite(data: data, to: finalReceiptURL)
    }

    deinit {
        discardUnfinishedFiles()
    }

    func appendTransfer(sourcePath: String, destinationPath: String, hash: String) throws {
        let payload: [String: String] = [
            "dest": destinationPath,
            "hash": hash,
            "source": sourcePath,
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])

        if transferCount > 0 {
            try spoolHandle?.write(contentsOf: Data(",\n".utf8))
        }
        try spoolHandle?.write(contentsOf: Data("    ".utf8))
        try spoolHandle?.write(contentsOf: data)
        try spoolHandle?.synchronize()
        transferCount += 1
    }

    func finish(
        status: String,
        abortReason: String?,
        attemptedJobs: Int,
        failedCount: Int,
        verifyCopies: Bool
    ) throws {
        guard !finished else {
            return
        }

        try spoolHandle?.close()
        spoolHandle = nil

        let temporaryReceiptURL = finalReceiptURL.appendingPathExtension("tmp")
        fileManager.createFile(atPath: temporaryReceiptURL.path, contents: Data())
        let receiptHandle = try FileHandle(forWritingTo: temporaryReceiptURL)

        do {
            try receiptHandle.write(contentsOf: Data("{\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"schemaVersion\" : 2,\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"runID\" : \(try Self.jsonString(runID.uuidString)),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"operation\" : \"organize\",\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"status\" : \(try Self.jsonString(status)),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"timestamp\" : \(try Self.jsonString(timestampString)),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"startedAt\" : \(try Self.jsonString(timestampString)),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"finishedAt\" : \(try Self.jsonString(ISO8601DateFormatter().string(from: Date()))),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"attempted_jobs\" : \(attemptedJobs),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"failed_jobs\" : \(failedCount),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"total_jobs\" : \(transferCount),\n".utf8))
            try receiptHandle.write(contentsOf: Data("  \"verification\" : { \"enabled\" : \(verifyCopies ? "true" : "false") },\n".utf8))
            if let abortReason {
                try receiptHandle.write(contentsOf: Data("  \"abortReason\" : \(try Self.jsonString(abortReason)),\n".utf8))
            }
            try receiptHandle.write(contentsOf: Data("  \"transfers\" : [\n".utf8))
            try pipeTransferSpool(into: receiptHandle)
            try receiptHandle.write(contentsOf: Data("\n  ]\n}\n".utf8))

            _ = fcntl(receiptHandle.fileDescriptor, F_FULLFSYNC)
            try receiptHandle.close()

            let renameResult: Int32 = temporaryReceiptURL.withUnsafeFileSystemRepresentation { sourcePointer in
                finalReceiptURL.withUnsafeFileSystemRepresentation { destinationPointer in
                    guard let sourcePointer, let destinationPointer else { return Int32(-1) }
                    return Darwin.rename(sourcePointer, destinationPointer)
                }
            }
            if renameResult != 0 {
                let code = errno
                throw NSError(
                    domain: NSPOSIXErrorDomain,
                    code: Int(code),
                    userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(code))]
                )
            }
            let parentPath = (finalReceiptURL.path as NSString).deletingLastPathComponent
            if !parentPath.isEmpty {
                try? ReceiptDurability.fsyncDirectory(atPath: parentPath)
            }
            try? fileManager.removeItem(at: transferSpoolURL)
            finished = true
        } catch {
            try? receiptHandle.close()
            try? fileManager.removeItem(at: temporaryReceiptURL)
            throw error
        }
    }

    func discardUnfinishedFiles() {
        guard !finished else {
            return
        }

        try? spoolHandle?.close()
        spoolHandle = nil
        // Phase 1 finding #3: do NOT delete the PENDING receipt or its
        // spool here. `deinit` runs at the end of a normal Swift
        // scope as well as on engine crash; in the crash case the
        // PENDING receipt + spool are exactly what the next startup
        // needs to recover the run. The only thing that should be
        // cleaned up here is the per-finalize temp receipt
        // (`.json.tmp`) that the `finish()` path may have left mid-
        // write — that's an internal artifact of finalization and
        // not the durable record of the run.
        try? fileManager.removeItem(at: finalReceiptURL.appendingPathExtension("tmp"))
    }

    private func pipeTransferSpool(into receiptHandle: FileHandle) throws {
        let sourceHandle = try FileHandle(forReadingFrom: transferSpoolURL)
        defer {
            try? sourceHandle.close()
        }

        while true {
            let chunk = try sourceHandle.read(upToCount: 64 * 1024) ?? Data()
            if chunk.isEmpty {
                break
            }
            try receiptHandle.write(contentsOf: chunk)
        }
    }

    private static func jsonString(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed])
        return String(data: data, encoding: .utf8) ?? "\"\""
    }
}

private final class TransferExecutionContext {
    private let executor: TransferExecutor
    private let database: OrganizerDatabase
    fileprivate let verifyCopies: Bool
    fileprivate let runLogger: PersistentRunLogger
    fileprivate let observer: TransferExecutionObserver
    fileprivate let isCancelled: @Sendable () -> Bool
    private let totalJobs: Int
    private let bytesTotal: Int64
    private let artifacts: RunArtifactPaths
    private let receiptWriter: StreamingAuditReceiptWriter
    private let runID = UUID()

    private var copiedCount = 0
    private var failedCount = 0
    private var skippedCount = 0
    private var consecutiveFailures = 0
    private var bytesCopied: Int64 = 0
    private var destinationUpdates: [RawFileCacheRecord]
    private var finished = false
    private var abortReason: String?

    init(
        executor: TransferExecutor,
        database: OrganizerDatabase,
        destinationRoot: URL,
        verifyCopies: Bool,
        runLogger: PersistentRunLogger,
        observer: TransferExecutionObserver,
        isCancelled: @escaping @Sendable () -> Bool,
        totalJobs: Int,
        bytesTotal: Int64
    ) throws {
        self.executor = executor
        self.database = database
        self.verifyCopies = verifyCopies
        self.runLogger = runLogger
        self.observer = observer
        self.isCancelled = isCancelled
        self.totalJobs = totalJobs
        self.bytesTotal = bytesTotal
        self.artifacts = executor.artifactPaths(destinationRoot: destinationRoot)
        self.receiptWriter = try StreamingAuditReceiptWriter(destinationRoot: destinationRoot)
        self.destinationUpdates = []
        self.destinationUpdates.reserveCapacity(min(TransferExecutor.destinationCacheBatchSize, totalJobs))
    }

    deinit {
        if !finished {
            receiptWriter.discardUnfinishedFiles()
        }
    }

    func start() {
        observer.onPhaseStarted(totalJobs, bytesTotal)
    }

    func process(job: QueuedCopyJob, attemptedJobs: Int) throws -> Bool {
        let preflight = sourceSkipOutcomeIfNeeded(for: job)
        if let skippedOutcome = preflight.outcome {
            return try apply(outcome: skippedOutcome, for: job, attemptedJobs: attemptedJobs)
        }
        let observerRef = self.observer
        try database.updateJobMutation(
            sourcePath: job.sourcePath,
            runID: runID,
            intendedDestinationPath: job.destinationPath,
            actualDestinationPath: nil,
            mutationState: .intended
        )
        let outcome = executor.prepareCopy(
            job: job,
            verifyCopies: verifyCopies,
            runLogger: runLogger,
            precomputedSourceIdentity: preflight.identity,
            isCancelled: isCancelled,
            onIssue: { issue in observerRef.onIssue(issue) }
        )
        return try apply(outcome: outcome, for: job, attemptedJobs: attemptedJobs)
    }

    func apply(
        outcome: TransferJobOutcome,
        for job: QueuedCopyJob,
        attemptedJobs: Int
    ) throws -> Bool {
        var emittedProgress = false
        var completedCopy: (destinationPath: String, actualSize: Int64, actualModificationDate: TimeInterval, verifiedHash: String?)?

        switch outcome {
        case let .prepared(temporaryPath, verifiedHash):
            do {
                try database.updateJobMutation(
                    sourcePath: job.sourcePath,
                    runID: runID,
                    intendedDestinationPath: job.destinationPath,
                    actualDestinationPath: temporaryPath,
                    mutationState: .temporaryWritten
                )
                let finalizedCopy = try executor.finalizePreparedCopy(
                    temporaryPath: temporaryPath,
                    requestedDestinationPath: job.destinationPath,
                    beforeRename: { finalPath in
                        try self.database.updateJobMutation(
                            sourcePath: job.sourcePath,
                            runID: self.runID,
                            intendedDestinationPath: finalPath,
                            actualDestinationPath: nil,
                            mutationState: .intended
                        )
                    }
                )
                try database.updateJobMutation(
                    sourcePath: job.sourcePath,
                    runID: runID,
                    intendedDestinationPath: finalizedCopy.destinationPath,
                    actualDestinationPath: finalizedCopy.destinationPath,
                    mutationState: .finalized
                )
                try database.updateJobStatus(sourcePath: job.sourcePath, status: .copied)
                completedCopy = (
                    destinationPath: finalizedCopy.destinationPath,
                    actualSize: finalizedCopy.size,
                    actualModificationDate: finalizedCopy.modificationTime,
                    verifiedHash: verifiedHash
                )
            } catch {
                executor.removeUnverifiedCopyIfNeeded(atPath: temporaryPath, runLogger: runLogger)
                try? database.updateJobMutation(
                    sourcePath: job.sourcePath,
                    runID: runID,
                    intendedDestinationPath: job.destinationPath,
                    actualDestinationPath: nil,
                    mutationState: .failed
                )
                try database.updateJobStatus(sourcePath: job.sourcePath, status: .failed)

                let message = "Copy failed: \(job.sourcePath) -> \(job.destinationPath): \(error.localizedDescription)"
                let logMessage = "Copy failed: \(job.sourcePath) → \(job.destinationPath): \(error.localizedDescription)"
                runLogger.error(logMessage)
                observer.onIssue(RunIssue(severity: .error, message: message))

                consecutiveFailures += 1
                failedCount += 1
                observer.onPhaseProgress(attemptedJobs, totalJobs, bytesCopied, bytesTotal, job.sourcePath)
                emittedProgress = true

                if let reason = executor.abortReason(
                    consecutiveFailures: consecutiveFailures,
                    totalFailures: failedCount,
                    attemptedJobs: attemptedJobs
                ) {
                    abortReason = reason
                    runLogger.error(reason)
                    return false
                }
            }

        case let .copied(destinationPath, size, modificationTime, verifiedHash):
            try database.updateJobMutation(
                sourcePath: job.sourcePath,
                runID: runID,
                intendedDestinationPath: destinationPath,
                actualDestinationPath: destinationPath,
                mutationState: .finalized
            )
            try database.updateJobStatus(sourcePath: job.sourcePath, status: .copied)
            completedCopy = (
                destinationPath: destinationPath,
                actualSize: size,
                actualModificationDate: modificationTime,
                verifiedHash: verifiedHash
            )

        case let .failed(message, logMessage):
            try? database.updateJobMutation(
                sourcePath: job.sourcePath,
                runID: runID,
                intendedDestinationPath: job.destinationPath,
                actualDestinationPath: nil,
                mutationState: .failed
            )
            try database.updateJobStatus(sourcePath: job.sourcePath, status: .failed)

            runLogger.error(logMessage)
            observer.onIssue(RunIssue(severity: .error, message: message))

            consecutiveFailures += 1
            failedCount += 1
            observer.onPhaseProgress(attemptedJobs, totalJobs, bytesCopied, bytesTotal, job.sourcePath)
            emittedProgress = true

            if let reason = executor.abortReason(
                consecutiveFailures: consecutiveFailures,
                totalFailures: failedCount,
                attemptedJobs: attemptedJobs
            ) {
                abortReason = reason
                runLogger.error(reason)
                return false
            }

        case let .skipped(message, logMessage):
            try? database.updateJobMutation(
                sourcePath: job.sourcePath,
                runID: runID,
                intendedDestinationPath: job.destinationPath,
                actualDestinationPath: nil,
                mutationState: .failed
            )
            try database.updateJobStatus(sourcePath: job.sourcePath, status: .skipped)

            runLogger.warn(logMessage)
            observer.onIssue(RunIssue(severity: .warning, message: message))
            skippedCount += 1
            observer.onPhaseProgress(attemptedJobs, totalJobs, bytesCopied, bytesTotal, job.sourcePath)
            emittedProgress = true
        }

        guard let completedCopy else {
            return !isCancelled()
        }

        destinationUpdates.append(
            RawFileCacheRecord(
                namespace: .destination,
                path: completedCopy.destinationPath,
                hash: completedCopy.verifiedHash ?? job.hash,
                size: completedCopy.actualSize,
                modificationTime: completedCopy.actualModificationDate
            )
        )
        if destinationUpdates.count >= TransferExecutor.destinationCacheBatchSize {
            try executor.flushDestinationUpdates(destinationUpdates, database: database)
            destinationUpdates.removeAll(keepingCapacity: true)
        }

        try receiptWriter.appendTransfer(
            sourcePath: job.sourcePath,
            destinationPath: completedCopy.destinationPath,
            hash: completedCopy.verifiedHash ?? job.hash
        )
        bytesCopied += executor.safeFileSize(atPath: job.sourcePath) ?? completedCopy.actualSize
        consecutiveFailures = 0
        copiedCount += 1

        if !emittedProgress, totalJobs > 0 {
            observer.onPhaseProgress(attemptedJobs, totalJobs, bytesCopied, bytesTotal, job.sourcePath)
        }

        return !isCancelled()
    }

    /// Re-hash the source once to decide whether it changed since planning.
    /// Returns the skip outcome when it did (or is unreadable), otherwise the
    /// freshly computed identity so `prepareCopy` can reuse it instead of
    /// reading the whole file a second time.
    private func sourceSkipOutcomeIfNeeded(
        for job: QueuedCopyJob
    ) -> (outcome: TransferJobOutcome?, identity: FileIdentity?) {
        do {
            let identity = try executor.fileHasher.hashIdentity(at: URL(fileURLWithPath: job.sourcePath))
            if isTrustedPlannedIdentity(job.hash), identity.rawValue != job.hash {
                let message = "Source modified since planning, skipping: \(job.sourcePath)"
                return (.skipped(message: message, logMessage: message), nil)
            }
            return (nil, identity)
        } catch {
            let message = "Source unreadable, skipping: \(job.sourcePath): \(error.localizedDescription)"
            return (.skipped(message: message, logMessage: message), nil)
        }
    }

    func finish(attemptedJobs: Int) throws -> TransferExecutionResult {
        try executor.flushDestinationUpdates(destinationUpdates, database: database)
        if abortReason == nil, isCancelled(), attemptedJobs < totalJobs {
            abortReason = "Transfer was cancelled before all queued files were processed."
        }
        let status = abortReason == nil ? "COMPLETED" : "ABORTED"
        try receiptWriter.finish(
            status: status,
            abortReason: abortReason,
            attemptedJobs: attemptedJobs,
            failedCount: failedCount,
            verifyCopies: verifyCopies
        )

        if totalJobs > 0, attemptedJobs == 0 {
            observer.onPhaseProgress(attemptedJobs, totalJobs, bytesCopied, bytesTotal, nil)
        }

        finished = true

        return TransferExecutionResult(
            copiedCount: copiedCount,
            failedCount: failedCount,
            skippedCount: skippedCount,
            bytesCopied: bytesCopied,
            bytesTotal: bytesTotal,
            status: status,
            abortReason: abortReason,
            artifacts: artifacts
        )
    }
}

private func isTrustedPlannedIdentity(_ rawValue: String) -> Bool {
    guard let identity = FileIdentity(rawValue: rawValue), identity.digest.count == 128 else {
        return false
    }
    return identity.digest.allSatisfy { character in
        character.isHexDigit
    }
}
