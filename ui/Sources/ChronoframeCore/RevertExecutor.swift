import Foundation

public enum SafePathContainment {
    public static func isContained(_ candidateURL: URL, in rootURL: URL) -> Bool {
        let rootPath = resolvedPath(for: rootURL, treatAsDirectory: true)
        let candidatePath = resolvedPath(for: candidateURL, treatAsDirectory: false)
        return candidatePath == rootPath || candidatePath.hasPrefix(rootPath + "/")
    }

    public static func resolvedPath(for url: URL, treatAsDirectory: Bool) -> String {
        let standardized = url.standardizedFileURL
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: standardized.path) {
            return standardized.resolvingSymlinksInPath().standardizedFileURL.path
        }
        if treatAsDirectory {
            return standardized.resolvingSymlinksInPath().standardizedFileURL.path
        }
        let parent = standardized.deletingLastPathComponent()
            .resolvingSymlinksInPath()
            .standardizedFileURL
        return parent.appendingPathComponent(standardized.lastPathComponent).path
    }
}

// MARK: - Receipt model (decoded from audit_receipt_*.json)

public struct RevertReceiptTransfer: Equatable, Codable, Sendable {
    public let source: String
    public let dest: String
    public let hash: String

    public init(source: String, dest: String, hash: String) {
        self.source = source
        self.dest = dest
        self.hash = hash
    }
}

public struct RevertReceipt: Equatable, Codable, Sendable {
    public let timestamp: String?
    public let status: String?
    public let totalJobs: Int?
    public let transfers: [RevertReceiptTransfer]

    public init(
        timestamp: String? = nil,
        status: String? = nil,
        totalJobs: Int? = nil,
        transfers: [RevertReceiptTransfer]
    ) {
        self.timestamp = timestamp
        self.status = status
        self.totalJobs = totalJobs
        self.transfers = transfers
    }

    private enum CodingKeys: String, CodingKey {
        case timestamp
        case status
        case totalJobs = "total_jobs"
        case transfers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.timestamp = try container.decodeIfPresent(String.self, forKey: .timestamp)
        self.status = try container.decodeIfPresent(String.self, forKey: .status)
        self.totalJobs = try container.decodeIfPresent(Int.self, forKey: .totalJobs)
        self.transfers = try container.decodeIfPresent([RevertReceiptTransfer].self, forKey: .transfers) ?? []
    }
}

// MARK: - Result + observer

public struct RevertExecutionResult: Equatable, Sendable {
    /// Files whose destination still hashed to the receipt value and were removed.
    public var revertedCount: Int
    /// Files preserved due to hash mismatch (user-modified) or OS error during remove.
    public var skippedCount: Int
    /// Files already missing from disk are treated as "trivially reverted"
    /// and does not increment either counter. Tracked separately for richer UI.
    public var missingCount: Int
    /// Total receipt entries considered.
    public var totalTransfers: Int

    public init(
        revertedCount: Int,
        skippedCount: Int,
        missingCount: Int,
        totalTransfers: Int
    ) {
        self.revertedCount = revertedCount
        self.skippedCount = skippedCount
        self.missingCount = missingCount
        self.totalTransfers = totalTransfers
    }
}

public struct RevertExecutionObserver: Sendable {
    public var onTaskStart: @Sendable (_ total: Int) -> Void
    /// `completed` is reverted + skipped, not including missing files.
    public var onTaskProgress: @Sendable (_ completed: Int, _ total: Int) -> Void
    public var onIssue: @Sendable (_ issue: RunIssue) -> Void

    public init(
        onTaskStart: @escaping @Sendable (_ total: Int) -> Void = { _ in },
        onTaskProgress: @escaping @Sendable (_ completed: Int, _ total: Int) -> Void = { _, _ in },
        onIssue: @escaping @Sendable (_ issue: RunIssue) -> Void = { _ in }
    ) {
        self.onTaskStart = onTaskStart
        self.onTaskProgress = onTaskProgress
        self.onIssue = onIssue
    }
}

// MARK: - Errors

public enum RevertExecutorError: LocalizedError, Equatable {
    case receiptNotFound(path: String)
    case invalidReceipt(reason: String)

    public var errorDescription: String? {
        switch self {
        case let .receiptNotFound(path):
            return "The selected revert receipt could not be found. It may have been moved or deleted. Receipt: \(path)."
        case let .invalidReceipt(reason):
            return "Chronoframe could not read this revert receipt. Choose a different receipt or run a new transfer. Details: \(reason)"
        }
    }
}

// MARK: - Executor

public struct RevertExecutor: Sendable {
    private let hasher: FileIdentityHasher

    /// Testability seam: overrides the path resolver used in both the pre-hash and
    /// post-hash boundary checks.  Production callers leave this nil, which falls
    /// through to the real `SafePathContainment.resolvedPath` call.  Tests inject a
    /// closure that can return different values on successive calls to simulate a
    /// symlink-swap race (TOCTOU) without needing OS-level timing control.
    var _boundaryPathResolver: (@Sendable (URL) -> String)?

    public init(hasher: FileIdentityHasher = FileIdentityHasher()) {
        self.hasher = hasher
        self._boundaryPathResolver = nil
    }

    /// Resolve the canonical path for a destination file URL.
    /// Uses the injected resolver when set (tests only); otherwise delegates to
    /// `SafePathContainment.resolvedPath` which follows symlinks via the real FS.
    private func resolveDestPath(_ url: URL) -> String {
        _boundaryPathResolver.map { $0(url) }
            ?? SafePathContainment.resolvedPath(for: url, treatAsDirectory: false)
    }

    /// FileManager.default is process-wide and thread-safe for the read/remove
    /// operations we use; we look it up at call sites to keep the struct Sendable.
    private var fileManager: FileManager { .default }

    /// Load a Chronoframe audit receipt from disk.
    public func loadReceipt(at url: URL) throws -> RevertReceipt {
        guard fileManager.fileExists(atPath: url.path) else {
            throw RevertExecutorError.receiptNotFound(path: url.path)
        }

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw RevertExecutorError.invalidReceipt(
                reason: "Could not read receipt: \(error.localizedDescription)"
            )
        }

        do {
            return try JSONDecoder().decode(RevertReceipt.self, from: data)
        } catch {
            throw RevertExecutorError.invalidReceipt(
                reason: "Malformed JSON: \(error.localizedDescription)"
            )
        }
    }

    /// Revert every transfer in `receipt`. Honors the same hash-guard contract as
    /// `chronoframe.core.revert_receipt`: a destination file is removed only when
    /// its current BLAKE2b identity still matches the value recorded at copy time.
    /// Modified or replaced files are left in place.
    ///
    /// When `destinationBoundary` is supplied, any transfer whose `dest` path
    /// resolves outside that directory is refused even if the hash matches.
    /// Production callers should always pass the run's destination root so a
    /// crafted or accidentally edited receipt cannot reach files outside the
    /// organized library.
    @discardableResult
    public func revert(
        receipt: RevertReceipt,
        observer: RevertExecutionObserver = RevertExecutionObserver(),
        destinationBoundary: URL? = nil,
        isCancelled: @escaping @Sendable () -> Bool = { false }
    ) -> RevertExecutionResult {
        let transfers = receipt.transfers
        observer.onTaskStart(transfers.count)

        var revertedCount = 0
        var skippedCount = 0
        var missingCount = 0

        let boundaryPath: String? = destinationBoundary.map {
            SafePathContainment.resolvedPath(for: $0, treatAsDirectory: true)
        }

        for transfer in transfers {
            if isCancelled() {
                break
            }

            let destinationPath = transfer.dest
            let destinationURL = URL(fileURLWithPath: destinationPath)

            if let boundaryPath {
                let resolvedPath = resolveDestPath(destinationURL)
                let isInside = resolvedPath == boundaryPath
                    || resolvedPath.hasPrefix(boundaryPath + "/")
                if !isInside {
                    skippedCount += 1
                    observer.onIssue(
                        RunIssue(
                            severity: .warning,
                            message: "Refusing to revert path outside destination: \(destinationPath)"
                        )
                    )
                    observer.onTaskProgress(revertedCount + skippedCount, transfers.count)
                    continue
                }
            }

            if !fileManager.fileExists(atPath: destinationPath) {
                // Missing destination is counted as trivially reverted.
                // and does NOT advance the progress counter (which is reverted+skipped).
                missingCount += 1
                continue
            }

            do {
                let currentIdentity = try hasher.hashIdentity(at: destinationURL)
                if currentIdentity.rawValue == transfer.hash {
                    // Second containment check: close the TOCTOU window between
                    // the first boundary check and removeItem. A symlink swap in
                    // that interval could redirect the delete outside the boundary.
                    if let boundaryPath {
                        let recheckPath = resolveDestPath(destinationURL)
                        let isStillInside = recheckPath == boundaryPath
                            || recheckPath.hasPrefix(boundaryPath + "/")
                        if !isStillInside {
                            skippedCount += 1
                            observer.onIssue(
                                RunIssue(
                                    severity: .warning,
                                    message: "Refusing to revert path outside destination (post-hash re-check): \(destinationPath)"
                                )
                            )
                            observer.onTaskProgress(revertedCount + skippedCount, transfers.count)
                            continue
                        }
                    }
                    do {
                        try fileManager.removeItem(at: destinationURL)
                        revertedCount += 1

                        // Best-effort empty-directory cleanup.
                        // Ignore cleanup failures because reverting the file is the important step.
                        let parentURL = destinationURL.deletingLastPathComponent()
                        if let contents = try? fileManager.contentsOfDirectory(
                            atPath: parentURL.path
                        ), contents.isEmpty {
                            try? fileManager.removeItem(at: parentURL)
                        }
                    } catch {
                        skippedCount += 1
                        observer.onIssue(
                            RunIssue(
                                severity: .warning,
                                message: "Could not remove \(destinationPath): \(error.localizedDescription)"
                            )
                        )
                    }
                } else {
                    skippedCount += 1
                    observer.onIssue(
                        RunIssue(
                            severity: .info,
                            message: "Preserved (modified since copy): \(destinationPath)"
                        )
                    )
                }
            } catch {
                skippedCount += 1
                observer.onIssue(
                    RunIssue(
                        severity: .warning,
                        message: "Could not re-hash \(destinationPath): \(error.localizedDescription)"
                    )
                )
            }

            observer.onTaskProgress(revertedCount + skippedCount, transfers.count)
        }

        return RevertExecutionResult(
            revertedCount: revertedCount,
            skippedCount: skippedCount,
            missingCount: missingCount,
            totalTransfers: transfers.count
        )
    }
}
