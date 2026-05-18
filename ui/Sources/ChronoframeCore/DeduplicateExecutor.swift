import Foundation

/// Applies a `DeduplicationPlan` to disk: each item is moved to Trash, while
/// a `dedupe_audit_receipt_<timestamp>_<runID>.json` is kept durable
/// next to the existing organize artifacts so the receipt surfaces in the
/// Run History tab and can be reverted.
///
/// The receipt directory is **preflighted** before any mutation. If the
/// log directory cannot be created or written to (read-only volume,
/// permission denied), the commit fails with no files touched. This
/// guarantees that every successful deletion is recorded.
public final class DeduplicateExecutor: @unchecked Sendable {
    private var cancelFlag = ManagedAtomicBool()
    private let fileOperations: DeduplicateFileOperations

    public init() {
        self.fileOperations = FileManagerDeduplicateFileOperations()
    }

    init(fileOperations: DeduplicateFileOperations) {
        self.fileOperations = fileOperations
    }

    public func cancel() {
        cancelFlag.set(true)
    }

    /// Convenience overload that builds the deletion plan from raw user
    /// decisions. Existing callers continue to use this; the UI footer
    /// uses `DeduplicationPlanner.plan` directly so its preview matches
    /// the executor exactly.
    public func commit(
        decisions: DedupeDecisions,
        clusters: [DuplicateCluster],
        configuration: DeduplicateConfiguration
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        let plan = DeduplicationPlanner.plan(
            decisions: decisions,
            clusters: clusters,
            configuration: configuration
        )
        return commit(
            plan: plan,
            destinationRoot: configuration.destinationPath,
            additionalSourceRoots: configuration.additionalSources.map(\.path),
            hardDelete: false
        )
    }

    /// Stream the commit. Preflights the receipt directory first; aborts
    /// the entire commit if it isn't writable. Once mutation begins,
    /// every plan item produces either an `itemTrashed` or `itemFailed`
    /// event, and every successful mutation contributes a receipt entry
    /// (using its plan-attached cluster ownership — Live Photo MOV halves
    /// and other paired partners are no longer dropped).
    ///
    /// `additionalSourceRoots` records any cross-folder scan roots so
    /// revert can accept items whose `originalPath` lives outside
    /// `destinationRoot` (Phase 1 finding #8).
    public func commit(
        plan: DeduplicationPlan,
        destinationRoot: String,
        additionalSourceRoots: [String] = [],
        hardDelete: Bool
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        cancelFlag.set(false)
        let cancelFlag = self.cancelFlag
        let fileOperations = self.fileOperations

        return AsyncThrowingStream<DeduplicateCommitEvent, Error> { continuation in
            Task.detached {
                let logsDirectory: URL
                do {
                    logsDirectory = try Self.preflightReceiptDirectory(destinationRoot: destinationRoot)
                } catch {
                    continuation.finish(throwing: ReceiptPreflightError(underlying: error))
                    return
                }

                continuation.yield(.started(totalToDelete: plan.items.count))

                let runID = UUID()
                let startedAt = Date()
                let receiptURL: URL
                var receiptItems = plan.items.map { planItem in
                    DeduplicateAuditReceipt.Item(
                        originalPath: planItem.path,
                        sizeBytes: planItem.sizeBytes,
                        trashURL: nil,
                        method: .trash,
                        clusterID: planItem.owningClusterID,
                        clusterKind: planItem.owningClusterKind
                    )
                }
                do {
                    receiptURL = try Self.makeReceiptURL(logsDirectory: logsDirectory, runID: runID, createdAt: startedAt)
                    try Self.writeReceipt(
                        receiptURL: receiptURL,
                        runID: runID,
                        status: "PENDING",
                        createdAt: startedAt,
                        finishedAt: nil,
                        destinationRoot: destinationRoot,
                        additionalSourceRoots: additionalSourceRoots,
                        items: receiptItems,
                        bytesReclaimed: 0,
                        abortReason: nil
                    )
                } catch {
                    continuation.finish(throwing: ReceiptPreflightError(underlying: error))
                    return
                }

                var deletedCount = 0
                var failedCount = 0
                var bytesReclaimed: Int64 = 0
                var abortReason: String?

                for (index, planItem) in plan.items.enumerated() {
                    if cancelFlag.get() {
                        abortReason = "Deduplicate was cancelled before all selected files moved to Trash."
                        break
                    }
                    let url = URL(fileURLWithPath: planItem.path)

                    // Phase 1 finding #7: split trash from receipt write
                    // so a successful trash + failed receipt update
                    // doesn't get double-reported as `itemFailed` for
                    // the SAME path (a false negative: the file is
                    // really in Trash). Use a distinct event class for
                    // "trashed but receipt is stale".
                    let trashedURL: URL?
                    do {
                        trashedURL = try fileOperations.trashItem(at: url)
                    } catch {
                        failedCount += 1
                        continuation.yield(.itemFailed(
                            originalPath: planItem.path,
                            errorMessage: error.localizedDescription
                        ))
                        continue
                    }

                    deletedCount += 1
                    bytesReclaimed += planItem.sizeBytes
                    receiptItems[index].trashURL = trashedURL?.absoluteString
                    do {
                        try Self.writeReceipt(
                            receiptURL: receiptURL,
                            runID: runID,
                            status: "PENDING",
                            createdAt: startedAt,
                            finishedAt: nil,
                            destinationRoot: destinationRoot,
                            additionalSourceRoots: additionalSourceRoots,
                            items: receiptItems,
                            bytesReclaimed: bytesReclaimed,
                            abortReason: nil
                        )
                        continuation.yield(.itemTrashed(
                            originalPath: planItem.path,
                            trashURL: trashedURL,
                            sizeBytes: planItem.sizeBytes
                        ))
                    } catch {
                        // File IS in Trash; only the receipt update
                        // failed. Surface the distinction so the UI
                        // doesn't tell the user "this file failed".
                        continuation.yield(.itemTrashedReceiptStale(
                            originalPath: planItem.path,
                            trashURL: trashedURL,
                            sizeBytes: planItem.sizeBytes,
                            errorMessage: error.localizedDescription
                        ))
                    }
                }

                var receiptError: Error?
                let finalStatus = abortReason == nil ? "COMPLETED" : "ABORTED"
                do {
                    try Self.writeReceipt(
                        receiptURL: receiptURL,
                        runID: runID,
                        status: finalStatus,
                        createdAt: startedAt,
                        finishedAt: Date(),
                        destinationRoot: destinationRoot,
                        additionalSourceRoots: additionalSourceRoots,
                        items: receiptItems,
                        bytesReclaimed: bytesReclaimed,
                        abortReason: abortReason
                    )
                } catch {
                    receiptError = error
                    // Phase 1 finding #7: emit a dedicated event for a
                    // finalize-failure. The previous code reused
                    // `.itemFailed(originalPath: "", …)` which made any
                    // listener that treats itemFailed as "this path
                    // failed" render a phantom row for the empty path.
                    continuation.yield(.criticalReceiptFailure(
                        errorMessage: "Critical: dedupe audit receipt could not be finalized. The last pending receipt remains in Run History. Details: \(error.localizedDescription)"
                    ))
                }

                continuation.yield(.complete(
                    DeduplicateCommitSummary(
                        deletedCount: deletedCount,
                        failedCount: failedCount + (receiptError == nil ? 0 : 1),
                        bytesReclaimed: bytesReclaimed,
                        receiptPath: receiptURL.path,
                        hardDelete: false
                    )
                ))
                continuation.finish()
            }
        }
    }

    /// Restore items listed in `receiptURL` from Trash back to their original
    /// paths. Items that were hard-deleted (or evicted from Trash) are
    /// reported as failures. Returns a stream of the same commit events the
    /// forward path uses, so the UI can reuse its progress surface.
    public func revert(
        receiptURL: URL,
        destinationBoundary: URL? = nil
    ) -> AsyncThrowingStream<DeduplicateCommitEvent, Error> {
        let fileOperations = self.fileOperations
        return AsyncThrowingStream<DeduplicateCommitEvent, Error> { continuation in
            Task.detached {
                do {
                    let data = try Data(contentsOf: receiptURL)
                    let receipt = try JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: data)
                    guard receipt.kind == "dedupe" || receipt.operation == "deduplicate" else {
                        throw DeduplicateReceiptValidationError.invalidKind
                    }
                    guard ["PENDING", "COMPLETED", "ABORTED", "FAILED"].contains(receipt.status) else {
                        throw DeduplicateReceiptValidationError.invalidStatus(receipt.status)
                    }
                    continuation.yield(.started(totalToDelete: receipt.items.count))

                    let primaryBoundaryURL = destinationBoundary
                        ?? Self.inferredDestinationBoundary(for: receiptURL)
                        ?? URL(fileURLWithPath: receipt.destinationRoot, isDirectory: true)
                    // Phase 1 finding #8: cross-folder dedup writes
                    // items whose `originalPath` is outside
                    // `destinationRoot`. Accept the
                    // `additionalSourceRoots` recorded in the receipt
                    // as additional containment boundaries — BUT
                    // validate each one before trusting it (Codex
                    // P1 review). The receipt lives on disk inside
                    // the destination, so a tampered or corrupt
                    // receipt could otherwise inject `/` as a root
                    // and let revert restore Trash items to
                    // arbitrary paths.
                    let extraBoundaries = receipt.additionalSourceRoots.compactMap { rootPath -> URL? in
                        guard Self.isPlausibleSourceRoot(rootPath, near: primaryBoundaryURL) else {
                            continuation.yield(.itemFailed(
                                originalPath: rootPath,
                                errorMessage: "Receipt named an additional source root that is not safe to restore into; that subset of items will be skipped."
                            ))
                            return nil
                        }
                        return URL(fileURLWithPath: rootPath, isDirectory: true)
                    }
                    let allBoundaries: [URL] = [primaryBoundaryURL] + extraBoundaries
                    var deletedCount = 0
                    var failedCount = 0
                    var bytesReclaimed: Int64 = 0

                    for item in receipt.items {
                        if item.method == .hardDelete {
                            failedCount += 1
                            continuation.yield(.itemFailed(originalPath: item.originalPath, errorMessage: "Hard-deleted items cannot be restored."))
                            continue
                        }
                        guard let trashURLString = item.trashURL, let trashURL = URL(string: trashURLString) else {
                            failedCount += 1
                            continuation.yield(.itemFailed(originalPath: item.originalPath, errorMessage: "Receipt is missing the Trash URL for this item."))
                            continue
                        }
                        let originalURL = URL(fileURLWithPath: item.originalPath)
                        let isContained = allBoundaries.contains { boundary in
                            SafePathContainment.isContained(originalURL, in: boundary)
                        }
                        guard isContained else {
                            failedCount += 1
                            continuation.yield(.itemFailed(originalPath: item.originalPath, errorMessage: "Receipt path is outside the dedupe destination."))
                            continue
                        }
                        if FileManager.default.fileExists(atPath: originalURL.path) {
                            failedCount += 1
                            continuation.yield(.itemFailed(originalPath: item.originalPath, errorMessage: "Original path already exists. Chronoframe left it untouched."))
                            continue
                        }
                        do {
                            try fileOperations.createDirectory(
                                at: originalURL.deletingLastPathComponent(),
                                withIntermediateDirectories: true
                            )
                            try fileOperations.moveItem(at: trashURL, to: originalURL)
                            deletedCount += 1
                            bytesReclaimed += item.sizeBytes
                            continuation.yield(.itemTrashed(originalPath: item.originalPath, trashURL: trashURL, sizeBytes: item.sizeBytes))
                        } catch {
                            failedCount += 1
                            continuation.yield(.itemFailed(originalPath: item.originalPath, errorMessage: error.localizedDescription))
                        }
                    }

                    continuation.yield(.complete(
                        DeduplicateCommitSummary(
                            deletedCount: deletedCount,
                            failedCount: failedCount,
                            bytesReclaimed: bytesReclaimed,
                            receiptPath: receiptURL.path,
                            hardDelete: false
                        )
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    /// Verify the receipt directory exists and is writable BEFORE we
    /// touch any user file. Probes by writing + removing a tiny file.
    static func preflightReceiptDirectory(destinationRoot: String) throws -> URL {
        let logsDirectory = URL(fileURLWithPath: destinationRoot).appendingPathComponent(".organize_logs")
        try FileManager.default.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        let probe = logsDirectory.appendingPathComponent(".dedupe_preflight_\(UUID().uuidString)")
        try Data().write(to: probe)
        try FileManager.default.removeItem(at: probe)
        return logsDirectory
    }

    static func inferredDestinationBoundary(for receiptURL: URL) -> URL? {
        let logsDirectory = receiptURL.deletingLastPathComponent()
        guard logsDirectory.lastPathComponent == ".organize_logs" else { return nil }
        return logsDirectory.deletingLastPathComponent()
    }

    /// Validates an `additionalSourceRoots` entry from a dedupe
    /// receipt before trusting it as a revert containment boundary.
    ///
    /// The receipt lives on disk inside the destination, so a
    /// tampered/corrupt receipt could otherwise inject a broad root
    /// (`/`, `/etc`, `/Library`) and let `revert(...)` move Trash
    /// items into arbitrary writable locations. Restrict accepted
    /// roots to plausible photo-library parents via a positive
    /// allowlist — anything outside the trusted neighborhood is
    /// rejected without further analysis:
    ///
    /// - descendants of the primary destination's parent directory
    ///   (covers typical setups where the destination and additional
    ///   sources live next to each other in the same folder);
    /// - descendants of `$HOME` (covers `~/Pictures/...` style
    ///   sources);
    /// - paths under `/Volumes/<name>/` (covers external drives, but
    ///   never `/Volumes` itself).
    ///
    /// Each candidate must additionally resolve to an existing
    /// directory at the time of revert. Both the candidate and every
    /// trusted parent are resolved through
    /// `standardizedFileURL.resolvingSymlinksInPath()` first so
    /// platform symlinks (e.g., macOS's `/var` → `/private/var`)
    /// don't accidentally land inside or outside the allow set.
    static func isPlausibleSourceRoot(_ rootPath: String, near destinationURL: URL) -> Bool {
        let trimmed = rootPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        let candidate = URL(fileURLWithPath: trimmed, isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
        let candidatePath = candidate.path

        // Require an existing directory on disk.
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidatePath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            return false
        }

        // Build the trusted-parents allowlist. Each parent is
        // standardized + symlink-resolved so the prefix comparison
        // below matches identical canonical paths.
        let homeDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let destinationParent = destinationURL
            .deletingLastPathComponent()
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        var trustedParents: Set<String> = [homeDirectory]
        if !destinationParent.isEmpty, destinationParent != "/" {
            trustedParents.insert(destinationParent)
        }

        // Accept descendants of any trusted parent. We don't accept
        // the parent itself — that would let a single-element
        // `additionalSourceRoots: ["/Users/x"]` cover the whole home.
        for parent in trustedParents {
            if candidatePath.hasPrefix(parent + "/") { return true }
        }

        // Special-case `/Volumes/<name>/...` (external drives).
        // `/Volumes` itself is rejected — must have at least one
        // path component below it.
        if candidatePath.hasPrefix("/Volumes/") {
            let suffix = candidatePath.dropFirst("/Volumes/".count)
            // Require a non-empty volume name (at least one
            // component before any sub-path).
            if !suffix.isEmpty,
               !suffix.hasPrefix("/")
            {
                return true
            }
        }

        return false
    }

    static func makeReceiptURL(
        logsDirectory: URL,
        runID: UUID,
        createdAt: Date
    ) throws -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: createdAt)
        return logsDirectory.appendingPathComponent("dedupe_audit_receipt_\(timestamp)_\(runID.uuidString).json")
    }

    static func writeReceipt(
        receiptURL: URL,
        runID: UUID,
        status: String,
        createdAt: Date,
        finishedAt: Date?,
        destinationRoot: String,
        additionalSourceRoots: [String] = [],
        items: [DeduplicateAuditReceipt.Item],
        bytesReclaimed: Int64,
        abortReason: String?
    ) throws {
        let receipt = DeduplicateAuditReceipt(
            runID: runID,
            status: status,
            createdAt: createdAt,
            finishedAt: finishedAt,
            destinationRoot: destinationRoot,
            additionalSourceRoots: additionalSourceRoots,
            items: items,
            bytesReclaimed: bytesReclaimed,
            abortReason: abortReason
        )
        let data = try JSONEncoder.dedupe.encode(receipt)
        try data.write(to: receiptURL, options: .atomic)
    }
}

public enum DeduplicateReceiptValidationError: LocalizedError, Equatable {
    case invalidKind
    case invalidStatus(String)

    public var errorDescription: String? {
        switch self {
        case .invalidKind:
            return "This receipt is not a deduplicate receipt."
        case let .invalidStatus(status):
            return "This deduplicate receipt has an unknown status: \(status)."
        }
    }
}

protocol DeduplicateFileOperations: Sendable {
    func removeItem(at url: URL) throws
    func trashItem(at url: URL) throws -> URL?
    func moveItem(at sourceURL: URL, to destinationURL: URL) throws
    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws
}

private struct FileManagerDeduplicateFileOperations: DeduplicateFileOperations {
    func removeItem(at url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    func trashItem(at url: URL) throws -> URL? {
        var trashURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &trashURL)
        return trashURL as URL?
    }

    func moveItem(at sourceURL: URL, to destinationURL: URL) throws {
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }

    func createDirectory(at url: URL, withIntermediateDirectories createIntermediates: Bool) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: createIntermediates)
    }
}

/// Thrown from `commit` when the receipt directory is not usable. The
/// commit stream finishes with this error before any file is mutated, so
/// the caller can surface it as "deduplicate could not start" rather than
/// "some files were deleted but the audit failed".
public struct ReceiptPreflightError: LocalizedError {
    public let underlying: Error

    public var errorDescription: String? {
        "Chronoframe cannot write the dedupe audit receipt to this destination, so the deduplicate run was aborted before any files changed. Ensure the destination volume is writable and try again. Details: \(underlying.localizedDescription)"
    }
}

extension JSONEncoder {
    static let dedupe: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()
}

extension JSONDecoder {
    static let dedupe: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}
