import Darwin
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
                let activity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .userInitiated],
                    reason: "Chronoframe: active deduplicate commit"
                )
                defer {
                    ProcessInfo.processInfo.endActivity(activity)
                }

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
                let spoolURL: URL
                var receiptItems = plan.items.map { planItem in
                    DeduplicateAuditReceipt.Item(
                        originalPath: planItem.path,
                        sizeBytes: planItem.sizeBytes,
                        trashURL: nil,
                        method: .trash,
                        clusterID: planItem.owningClusterID,
                        clusterKind: ReceiptClusterKind(planItem.owningClusterKind),
                        mediaKind: ReceiptMediaKind(planItem.mediaKind),
                        expectedIdentity: planItem.expectedIdentity
                    )
                }
                do {
                    receiptURL = try Self.makeReceiptURL(logsDirectory: logsDirectory, runID: runID, createdAt: startedAt)
                    spoolURL = Self.spoolURL(for: receiptURL)
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
                    FileManager.default.createFile(atPath: spoolURL.path, contents: Data())
                } catch {
                    continuation.finish(throwing: ReceiptPreflightError(underlying: error))
                    return
                }

                let spoolHandle: FileHandle
                do {
                    spoolHandle = try FileHandle(forWritingTo: spoolURL)
                    try spoolHandle.seekToEnd()
                } catch {
                    continuation.finish(throwing: ReceiptPreflightError(underlying: error))
                    return
                }
                defer {
                    try? spoolHandle.close()
                }

                var deletedCount = 0
                var failedCount = 0
                var bytesReclaimed: Int64 = 0
                var abortReason: String?
                // Indices of plan items deliberately left untouched because the
                // live file no longer matches what was scanned (Finding #1).
                // They are dropped from the final receipt so revert never tries
                // to restore something that was never trashed.
                var staleIndices: Set<Int> = []
                var unresolvedIndices: Set<Int> = []
                var journalFailure = false
                var outcomes: [String: MutationOutcome] = [:]
                let receiptIndexByPath = Dictionary(uniqueKeysWithValues: plan.items.enumerated().map {
                    ($0.element.path, $0.offset)
                })
                let mediaItems = plan.items.filter { $0.pairOrigin != .sidecar }
                let sidecarItems = plan.items.filter { $0.pairOrigin == .sidecar }
                var processedPaths = Set<String>()

                // Media always precedes sidecars. A sidecar's mutation is
                // conditional on the observed outcomes of every owner.
                for planItem in mediaItems + sidecarItems {
                    guard !processedPaths.contains(planItem.path) else { continue }
                    if cancelFlag.get() {
                        abortReason = "Deduplicate was cancelled before all selected files moved to Trash."
                        break
                    }

                    if planItem.pairOrigin == .sidecar {
                        let currentOwners = Self.currentSidecarOwners(for: planItem.path)
                        let allCurrentOwnersCaptured = currentOwners.isSubset(of: planItem.sidecarOwnerPaths)
                        let everyCapturedOwnerTrashed = planItem.sidecarOwnerPaths.allSatisfy {
                            if case .trashed = outcomes[$0] { return true }
                            return false
                        }
                        guard allCurrentOwnersCaptured, everyCapturedOwnerTrashed else {
                            let reason = allCurrentOwnersCaptured
                                ? "A photo that owns this metadata sidecar was kept, so the sidecar was left untouched."
                                : "A new photo now shares this metadata sidecar, so the sidecar was left untouched. Scan again to review the updated group."
                            outcomes[planItem.path] = .untouched(reason)
                            processedPaths.insert(planItem.path)
                            if let index = receiptIndexByPath[planItem.path] { staleIndices.insert(index) }
                            continuation.yield(.itemStale(originalPath: planItem.path, reason: reason))
                            continue
                        }
                    }

                    let unitItems: [DeduplicationPlan.Item]
                    if let unitID = planItem.mutationUnitID {
                        unitItems = mediaItems.filter { $0.mutationUnitID == unitID }
                    } else {
                        unitItems = [planItem]
                    }
                    let results: [MutationResult]
                    do {
                        results = try Self.quarantineValidateAndTrash(
                            items: unitItems,
                            fileOperations: fileOperations,
                            prepareJournal: { item, quarantineURL in
                                let record = try Self.makeIntentRecord(
                                    item: item,
                                    quarantineURL: quarantineURL
                                )
                                try Self.appendSpoolRecord(record, to: spoolHandle)
                                return record
                            },
                            recordJournal: { record in
                                try Self.appendSpoolRecord(record, to: spoolHandle)
                            }
                        )
                    } catch {
                        journalFailure = true
                        failedCount += unitItems.count
                        abortReason = "Deduplicate stopped because its recovery journal could not be updated safely."
                        continuation.yield(.criticalReceiptFailure(
                            errorMessage: "Chronoframe stopped before continuing because recovery metadata could not be persisted. No further files were touched. Details: \(error.localizedDescription)"
                        ))
                        break
                    }

                    for result in results {
                        processedPaths.insert(result.item.path)
                        outcomes[result.item.path] = result.outcome
                        guard let index = receiptIndexByPath[result.item.path] else { continue }
                        switch result.outcome {
                        case let .trashed(trashedURL):
                            // The `.trashed` journal transition was
                            // synchronized inside the atomic helper before
                            // this user-facing event is emitted.
                            deletedCount += 1
                            bytesReclaimed += result.item.sizeBytes
                            receiptItems[index].trashURL = trashedURL?.absoluteString
                            continuation.yield(.itemTrashed(
                                originalPath: result.item.path,
                                trashURL: trashedURL,
                                sizeBytes: result.item.sizeBytes
                            ))
                        case let .stale(reason), let .untouched(reason):
                            staleIndices.insert(index)
                            if reason.localizedCaseInsensitiveContains("manual recovery") {
                                unresolvedIndices.insert(index)
                            }
                            continuation.yield(.itemStale(originalPath: result.item.path, reason: reason))
                        case let .restored(reason), let .failed(reason):
                            staleIndices.insert(index)
                            if reason.localizedCaseInsensitiveContains("manual recovery") {
                                unresolvedIndices.insert(index)
                            }
                            failedCount += 1
                            continuation.yield(.itemFailed(originalPath: result.item.path, errorMessage: reason))
                        }
                    }
                    if abortReason != nil { break }
                }

                var receiptError: Error?
                let finalStatus = abortReason == nil && unresolvedIndices.isEmpty && !journalFailure
                    ? "COMPLETED"
                    : "ABORTED"
                do {
                    let recordedTrashURLs = try Self.loadSpoolRecords(from: spoolURL)
                    for index in receiptItems.indices {
                        if let trashURL = recordedTrashURLs[receiptItems[index].originalPath] {
                            receiptItems[index].trashURL = trashURL
                        }
                    }
                    // Drop items that were left untouched as stale (Finding #1)
                    // so the durable receipt records only real Trash moves and
                    // revert never tries to restore a file that was preserved.
                    let finalItems = receiptItems.enumerated()
                        .filter { !staleIndices.contains($0.offset) || unresolvedIndices.contains($0.offset) }
                        .map(\.element)
                    try Self.writeReceipt(
                        receiptURL: receiptURL,
                        runID: runID,
                        status: finalStatus,
                        createdAt: startedAt,
                        finishedAt: Date(),
                        destinationRoot: destinationRoot,
                        additionalSourceRoots: additionalSourceRoots,
                        items: finalItems,
                        bytesReclaimed: bytesReclaimed,
                        abortReason: abortReason,
                        recoveryState: unresolvedIndices.isEmpty && !journalFailure ? nil : .manualActionRequired
                    )
                    if unresolvedIndices.isEmpty && !journalFailure {
                        try? FileManager.default.removeItem(at: spoolURL)
                    }
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
                let activity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled, .userInitiated],
                    reason: "Chronoframe: active deduplicate revert"
                )
                defer {
                    ProcessInfo.processInfo.endActivity(activity)
                }

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
                        // Verify the Trash item still holds the exact bytes that
                        // were trashed before restoring it. The Trash is a
                        // user-writable location, so a tampered or replaced item
                        // must not be silently moved back to the library.
                        var verifiedTrashEntry: (device: dev_t, inode: ino_t)?
                        if let expected = item.expectedIdentity {
                            switch Self.verifyTrashItem(at: trashURL, expected: expected) {
                            case let .mismatch(reason):
                                failedCount += 1
                                continuation.yield(.itemFailed(originalPath: item.originalPath, errorMessage: reason))
                                continue
                            case let .verified(device, inode):
                                verifiedTrashEntry = (device, inode)
                            }
                        } else if receipt.schemaVersion >= 6 {
                            // A current-schema (v6+) receipt must carry an identity
                            // for every trashed item; a missing one means the
                            // receipt is corrupt or hand-edited. Fail closed rather
                            // than treating it as a legacy unconditional restore —
                            // the legacy exception applies only to schema ≤5.
                            failedCount += 1
                            continuation.yield(.itemFailed(
                                originalPath: item.originalPath,
                                errorMessage: "This receipt is missing the integrity information needed to safely restore this item, so it was left in Trash."
                            ))
                            continue
                        }
                        // Re-bind the verification to the entry we are about to
                        // move: confirm the path still resolves to the exact inode
                        // we hashed, immediately before the move closes the
                        // verify→restore window against a Trash-entry swap.
                        if let verifiedTrashEntry,
                           !Self.trashEntryStillMatches(trashURL, device: verifiedTrashEntry.device, inode: verifiedTrashEntry.inode) {
                            failedCount += 1
                            continuation.yield(.itemFailed(
                                originalPath: item.originalPath,
                                errorMessage: "The item in Trash changed during restore, so it was left in Trash."
                            ))
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

    enum MutationOutcome: Sendable, Equatable {
        case trashed(URL?)
        case stale(String)
        case failed(String)
        case restored(String)
        case untouched(String)
    }

    struct MutationResult: Sendable {
        let item: DeduplicationPlan.Item
        let outcome: MutationOutcome
    }

    /// Rename every member of a mutation unit out of the namespace first,
    /// then verify the exact inode through an O_NOFOLLOW descriptor. Pair
    /// units only proceed to Trash after every member validates.
    static func quarantineValidateAndTrash(
        items: [DeduplicationPlan.Item],
        fileOperations: any DeduplicateFileOperations,
        prepareJournal: (DeduplicationPlan.Item, URL) throws -> DeduplicateSpoolRecord,
        recordJournal: (DeduplicateSpoolRecord) throws -> Void
    ) throws -> [MutationResult] {
        var quarantined: [(item: DeduplicationPlan.Item, url: URL)] = []
        if let staleItem = items.first(where: { cheapPreflightReason(for: $0) != nil }),
           let reason = cheapPreflightReason(for: staleItem)
        {
            return items.map { item in
                item.path == staleItem.path
                    ? MutationResult(item: item, outcome: .stale(reason))
                    : MutationResult(
                        item: item,
                        outcome: .untouched("This mutation unit was left untouched because another member was no longer safe to delete.")
                    )
            }
        }
        let planned = items.map { item in
            let originalURL = URL(fileURLWithPath: item.path)
            return (
                item: item,
                quarantineURL: originalURL.deletingLastPathComponent().appendingPathComponent(
                    ".chronoframe-quarantine-\(UUID().uuidString)-\(originalURL.lastPathComponent)"
                )
            )
        }
        var journalByPath: [String: DeduplicateSpoolRecord] = [:]

        // Persist recovery metadata for the complete pair before renaming its
        // first member. A failure here leaves every original path untouched.
        for entry in planned {
            journalByPath[entry.item.path] = try prepareJournal(entry.item, entry.quarantineURL)
        }

        for entry in planned {
            let item = entry.item
            let originalURL = URL(fileURLWithPath: item.path)
            let quarantineURL = entry.quarantineURL
            do {
                try fileOperations.quarantineItem(at: originalURL, to: quarantineURL)
            } catch {
                let restoration = restoreQuarantined(quarantined, fileOperations: fileOperations)
                return items.map { candidate in
                    if candidate.path == item.path {
                        return MutationResult(
                            item: candidate,
                            outcome: .failed("Chronoframe could not safely quarantine this file, so the mutation unit was left untouched. \(error.localizedDescription)")
                        )
                    }
                    return MutationResult(
                        item: candidate,
                        outcome: .restored(restoration[candidate.path] ?? "This pair was restored after quarantine failed.")
                    )
                }
            }
            quarantined.append((item, quarantineURL))
            do {
                if var journal = journalByPath[item.path] {
                    journal.state = .quarantined
                    try recordJournal(journal)
                    journalByPath[item.path] = journal
                }
            } catch {
                _ = restoreQuarantined(quarantined, fileOperations: fileOperations)
                throw error
            }

            if let reason = quarantinedIdentityMismatch(item: item, url: quarantineURL) {
                let restoration = restoreQuarantined(quarantined, fileOperations: fileOperations)
                return items.map { candidate in
                    let detail = restoration[candidate.path]
                    if candidate.path == item.path {
                        return MutationResult(
                            item: candidate,
                            outcome: .stale(detail.map { reason + " " + $0 } ?? reason)
                        )
                    }
                    return MutationResult(
                        item: candidate,
                        outcome: .restored(detail ?? "This pair was restored because another member changed after the scan.")
                    )
                }
            }
        }

        var trashed: [(item: DeduplicationPlan.Item, trashURL: URL?)] = []
        for (offset, entry) in quarantined.enumerated() {
            do {
                let trashURL = try fileOperations.trashItem(at: entry.url)
                trashed.append((entry.item, trashURL))
                if var journal = journalByPath[entry.item.path] {
                    journal.state = .trashed
                    journal.actualTrashURL = trashURL?.absoluteString
                    do {
                        try recordJournal(journal)
                        journalByPath[entry.item.path] = journal
                    } catch {
                        for moved in trashed.reversed() {
                            guard let movedTrashURL = moved.trashURL else { continue }
                            _ = restoreItem(
                                from: movedTrashURL,
                                to: URL(fileURLWithPath: moved.item.path),
                                fileOperations: fileOperations,
                                context: "journal rollback"
                            )
                        }
                        for remaining in quarantined.dropFirst(offset + 1) {
                            _ = restoreItem(
                                from: remaining.url,
                                to: URL(fileURLWithPath: remaining.item.path),
                                fileOperations: fileOperations,
                                context: "journal rollback"
                            )
                        }
                        throw DedupeJournalTransitionError(underlying: error)
                    }
                }
            } catch let journalError as DedupeJournalTransitionError {
                // The rollback above has already preserved every reachable
                // member. Propagate so the run stops; continuing without a
                // durable transition would make recovery ambiguous.
                throw journalError.underlying
            } catch {
                var messages: [String: String] = [:]

                for moved in trashed.reversed() {
                    guard let trashURL = moved.trashURL else {
                        messages[moved.item.path] = "A paired file reached Trash, but its Trash location was unavailable for automatic restoration. Manual recovery is required."
                        continue
                    }
                    messages[moved.item.path] = restoreItem(
                        from: trashURL,
                        to: URL(fileURLWithPath: moved.item.path),
                        fileOperations: fileOperations,
                        context: "Trash rollback"
                    )
                }
                for remaining in quarantined[offset...] {
                    messages[remaining.item.path] = restoreItem(
                        from: remaining.url,
                        to: URL(fileURLWithPath: remaining.item.path),
                        fileOperations: fileOperations,
                        context: "quarantine rollback"
                    )
                }

                return items.map { candidate in
                    let message = messages[candidate.path]
                        ?? "The pair was restored because one member could not be moved to Trash."
                    if candidate.path == entry.item.path {
                        let failure = error.localizedDescription
                        return MutationResult(
                            item: candidate,
                            outcome: .failed(
                                message.localizedCaseInsensitiveContains("manual recovery")
                                    ? "\(failure) \(message)"
                                    : failure
                            )
                        )
                    }
                    if message.localizedCaseInsensitiveContains("manual recovery") {
                        return MutationResult(item: candidate, outcome: .failed(message))
                    }
                    return MutationResult(item: candidate, outcome: .restored(message))
                }
            }
        }

        return trashed.map { MutationResult(item: $0.item, outcome: .trashed($0.trashURL)) }
    }

    private struct DedupeJournalTransitionError: Error {
        let underlying: Error
    }

    static func cheapPreflightReason(for item: DeduplicationPlan.Item) -> String? {
        var st = stat()
        guard lstat(item.path, &st) == 0 else {
            return "The selected file no longer exists at its scanned location, so it was left untouched."
        }
        switch st.st_mode & S_IFMT {
        case S_IFLNK:
            return "A symlink now stands where a regular file was scanned, so it was left untouched."
        case S_IFREG:
            return Int64(st.st_size) == item.expectedIdentity.size
                ? nil
                : "The selected file changed size since the scan, so it was left untouched."
        default:
            return "The scanned path is no longer a regular file, so it was left untouched."
        }
    }

    static func quarantinedIdentityMismatch(item: DeduplicationPlan.Item, url: URL) -> String? {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
        guard descriptor >= 0 else {
            return "Chronoframe could not reopen the quarantined file safely, so it was preserved."
        }
        defer { _ = Darwin.close(descriptor) }

        var st = stat()
        guard fstat(descriptor, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
            return "The quarantined object is not the regular file that was scanned, so it was preserved."
        }
        guard Int64(st.st_size) == item.expectedIdentity.size else {
            return "The selected file changed size after the scan, so it was preserved."
        }
        do {
            let identity = try FileIdentityHasher().hashIdentity(descriptor: descriptor, size: Int64(st.st_size))
            return identity == item.expectedIdentity
                ? nil
                : "The selected file's contents changed after the scan, so it was preserved."
        } catch {
            return "Chronoframe could not verify the selected file's contents, so it was preserved."
        }
    }

    /// Re-open a Trash item through an `O_NOFOLLOW` descriptor and confirm its
    /// contents still match the identity captured when it was trashed. Returns
    /// a human-readable reason when it does not (so revert leaves it in Trash),
    /// or `nil` when it is safe to restore. Mirrors `quarantinedIdentityMismatch`
    /// but operates on a receipt's recorded identity rather than a live plan.
    enum TrashRestoreVerification: Equatable {
        /// The Trash item matched the recorded identity; carries the device/inode
        /// it was verified against so the caller can re-bind the restore to the
        /// exact entry immediately before moving it.
        case verified(device: dev_t, inode: ino_t)
        case mismatch(String)
    }

    /// Re-open a Trash item through an `O_NOFOLLOW` descriptor and confirm its
    /// contents still match the identity captured when it was trashed. On
    /// success returns the verified `(device, inode)`; on any problem returns a
    /// human-readable reason so revert leaves the item in Trash. Mirrors
    /// `quarantinedIdentityMismatch` but operates on a receipt's recorded
    /// identity rather than a live plan.
    static func verifyTrashItem(at url: URL, expected: FileIdentity) -> TrashRestoreVerification {
        let descriptor = url.path.withCString { Darwin.open($0, O_RDONLY | O_CLOEXEC | O_NOFOLLOW) }
        guard descriptor >= 0 else {
            return .mismatch("Chronoframe could not reopen this item in Trash to verify it, so it was left in Trash. Restore it manually if you trust it.")
        }
        defer { _ = Darwin.close(descriptor) }

        var st = stat()
        guard fstat(descriptor, &st) == 0, (st.st_mode & S_IFMT) == S_IFREG else {
            return .mismatch("The item in Trash is no longer the regular file that was deleted, so it was left in Trash.")
        }
        guard Int64(st.st_size) == expected.size else {
            return .mismatch("The item in Trash changed size since it was deleted, so it was left in Trash to avoid restoring altered contents.")
        }
        do {
            let identity = try FileIdentityHasher().hashIdentity(descriptor: descriptor, size: Int64(st.st_size))
            guard identity == expected else {
                return .mismatch("The item in Trash was modified since it was deleted, so it was left in Trash to avoid restoring altered contents.")
            }
            return .verified(device: st.st_dev, inode: st.st_ino)
        } catch {
            return .mismatch("Chronoframe could not verify this item's contents in Trash, so it was left in Trash. Restore it manually if you trust it.")
        }
    }

    /// Confirm the Trash path still resolves (no symlink) to the exact
    /// regular-file inode `verifyTrashItem` hashed. Called immediately before
    /// the path-based move so a swap of the user-writable Trash entry in the
    /// verify→restore window cannot redirect the restore to a different file.
    static func trashEntryStillMatches(_ url: URL, device: dev_t, inode: ino_t) -> Bool {
        var st = stat()
        let ok = url.path.withCString { lstat($0, &st) == 0 }
        return ok && (st.st_mode & S_IFMT) == S_IFREG && st.st_dev == device && st.st_ino == inode
    }

    static func restoreQuarantined(
        _ entries: [(item: DeduplicationPlan.Item, url: URL)],
        fileOperations: any DeduplicateFileOperations
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: entries.map { entry in
            (
                entry.item.path,
                restoreItem(
                    from: entry.url,
                    to: URL(fileURLWithPath: entry.item.path),
                    fileOperations: fileOperations,
                    context: "quarantine recovery"
                )
            )
        })
    }

    static func restoreItem(
        from source: URL,
        to original: URL,
        fileOperations: any DeduplicateFileOperations,
        context: String
    ) -> String {
        var st = stat()
        if lstat(original.path, &st) == 0 {
            return "The original path was recreated during \(context). Both objects were preserved; recover the quarantined item at \(source.path). Manual recovery is required."
        }
        do {
            try fileOperations.moveItem(at: source, to: original)
            return "This file was restored because another member of its mutation unit could not be safely deleted."
        } catch {
            return "Chronoframe could not complete \(context). Recover the preserved item at \(source.path). Manual recovery is required."
        }
    }

    static func currentSidecarOwners(for sidecarPath: String) -> Set<String> {
        let sidecarURL = URL(fileURLWithPath: sidecarPath).standardizedFileURL
        let directory = sidecarURL.deletingLastPathComponent()
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else {
            // Fail closed: an inaccessible directory is represented by a
            // synthetic owner that cannot be present in the captured plan.
            return ["<inaccessible-directory>"]
        }
        return Set(urls.compactMap { candidate -> String? in
            let path = candidate.standardizedFileURL.path
            guard MediaLibraryRules.isPhotoFile(path: path) else { return nil }
            let stem = candidate.deletingPathExtension().lastPathComponent
            let replaced = directory.appendingPathComponent(stem + ".xmp").standardizedFileURL.path
            let appended = directory.appendingPathComponent(candidate.lastPathComponent + ".xmp").standardizedFileURL.path
            return replaced == sidecarURL.path || appended == sidecarURL.path ? path : nil
        })
    }

    static func makeIntentRecord(
        item: DeduplicationPlan.Item,
        quarantineURL: URL
    ) throws -> DeduplicateSpoolRecord {
        let originalURL = URL(fileURLWithPath: item.path)
        let trashDirectory = try FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: originalURL,
            create: true
        )
        let predictedTrashURL = trashDirectory.appendingPathComponent(
            quarantineURL.lastPathComponent,
            isDirectory: false
        )
        var st = stat()
        guard lstat(predictedTrashURL.path, &st) != 0, errno == ENOENT else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.fileWriteFileExists.rawValue,
                userInfo: [
                    NSFilePathErrorKey: predictedTrashURL.path,
                    NSLocalizedDescriptionKey: "Chronoframe could not reserve a collision-free Trash recovery path.",
                ]
            )
        }
        let bookmark = try originalURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        return DeduplicateSpoolRecord(
            state: .intent,
            originalPath: item.path,
            quarantinePath: quarantineURL.path,
            expectedIdentity: item.expectedIdentity,
            predictedTrashURL: predictedTrashURL.absoluteString,
            preTrashBookmarkData: bookmark
        )
    }

    /// Re-stat a plan item's live path immediately before Trash and decide
    /// whether it still identifies the regular file that was scanned
    /// (Finding #1 / AGENTS-INVARIANT 5, 15). Returns a human-readable
    /// reason when the item is stale and must be preserved, or `nil` when the
    /// live file matches and is safe to trash.
    ///
    /// Retained as a focused test seam. Production uses quarantine +
    /// descriptor hashing above to close the path-based TOCTOU window.
    static func staleReason(for item: DeduplicationPlan.Item) -> String? {
        if let reason = cheapPreflightReason(for: item) { return reason }
        return quarantinedIdentityMismatch(item: item, url: URL(fileURLWithPath: item.path))
    }

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

    static func spoolURL(for receiptURL: URL) -> URL {
        receiptURL.appendingPathExtension("spool")
    }

    static func appendSpoolRecord(_ record: DeduplicateSpoolRecord, to handle: FileHandle) throws {
        var data = try JSONEncoder.dedupeSpool.encode(record)
        data.append(Data("\n".utf8))
        try handle.write(contentsOf: data)
        try handle.synchronize()
    }

    static func loadSpoolRecords(from spoolURL: URL) throws -> [String: String] {
        guard FileManager.default.fileExists(atPath: spoolURL.path) else { return [:] }
        let data = try Data(contentsOf: spoolURL)
        guard let raw = String(data: data, encoding: .utf8) else { return [:] }
        var records: [String: String] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            // A process can terminate in the middle of the final append. Keep
            // every complete prior line and ignore only the malformed tail.
            guard let record = try? JSONDecoder.dedupe.decode(
                DeduplicateSpoolRecord.self,
                from: Data(line.utf8)
            ) else { continue }
            if record.state == .trashed,
               let trashURL = record.actualTrashURL ?? record.predictedTrashURL
            {
                records[record.originalPath] = trashURL
            }
        }
        return records
    }

    static func loadLatestJournalRecords(from spoolURL: URL) throws -> [String: DeduplicateSpoolRecord] {
        guard FileManager.default.fileExists(atPath: spoolURL.path) else { return [:] }
        let data = try Data(contentsOf: spoolURL)
        guard let raw = String(data: data, encoding: .utf8) else { return [:] }
        var records: [String: DeduplicateSpoolRecord] = [:]
        for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let record = try? JSONDecoder.dedupe.decode(
                DeduplicateSpoolRecord.self,
                from: Data(line.utf8)
            ) else { continue }
            records[record.originalPath] = record
        }
        return records
    }

    @discardableResult
    public static func consolidatePendingReceipt(pendingURL: URL, spoolURL: URL) throws -> Bool {
        let data = try Data(contentsOf: pendingURL)
        var receipt = try JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: data)
        guard receipt.status == "PENDING" else { return false }
        let recordedTrashURLs = try loadSpoolRecords(from: spoolURL)
        guard !recordedTrashURLs.isEmpty else { return false }

        var bytesReclaimed: Int64 = 0
        for index in receipt.items.indices {
            if let trashURL = recordedTrashURLs[receipt.items[index].originalPath] {
                receipt.items[index].trashURL = trashURL
                bytesReclaimed += receipt.items[index].sizeBytes
            }
        }
        receipt.status = "ABORTED"
        receipt.finishedAt = Date()
        receipt.bytesReclaimed = bytesReclaimed
        receipt.abortReason = "Deduplicate was interrupted before the audit receipt was finalized."

        let encoded = try JSONEncoder.dedupe.encode(receipt)
        try ReceiptDurability.durablyWrite(data: encoded, to: pendingURL)
        try? FileManager.default.removeItem(at: spoolURL)
        return true
    }

    public static func recoverInterruptedRuns(at destinationRoot: URL) -> Int {
        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var recovered = 0
        for receiptURL in contents where receiptURL.lastPathComponent.hasPrefix("dedupe_audit_receipt_") && receiptURL.pathExtension == "json" {
            let spoolURL = Self.spoolURL(for: receiptURL)
            guard FileManager.default.fileExists(atPath: spoolURL.path) else { continue }
            if (try? Self.consolidatePendingReceipt(pendingURL: receiptURL, spoolURL: spoolURL)) == true {
                recovered += 1
            }
        }
        return recovered
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
        abortReason: String?,
        recoveryState: MutationRecoveryState? = nil
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
            abortReason: abortReason,
            recoveryState: recoveryState
        )
        let data = try JSONEncoder.dedupe.encode(receipt)
        try ReceiptDurability.durablyWrite(data: data, to: receiptURL)
    }
}

enum DedupeJournalItemState: String, Codable, Sendable {
    case intent
    case quarantined
    case trashed
    case restored
    case untouched
    case manualActionRequired
}

struct DeduplicateSpoolRecord: Codable, Sendable {
    var schemaVersion: Int
    var state: DedupeJournalItemState
    var originalPath: String
    var quarantinePath: String?
    var expectedIdentity: FileIdentity?
    var predictedTrashURL: String?
    var actualTrashURL: String?
    var preTrashBookmarkData: Data?

    init(
        schemaVersion: Int = 2,
        state: DedupeJournalItemState,
        originalPath: String,
        quarantinePath: String? = nil,
        expectedIdentity: FileIdentity? = nil,
        predictedTrashURL: String? = nil,
        actualTrashURL: String? = nil,
        preTrashBookmarkData: Data? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.originalPath = originalPath
        self.quarantinePath = quarantinePath
        self.expectedIdentity = expectedIdentity
        self.predictedTrashURL = predictedTrashURL
        self.actualTrashURL = actualTrashURL
        self.preTrashBookmarkData = preTrashBookmarkData
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case state
        case originalPath
        case quarantinePath
        case expectedIdentity
        case predictedTrashURL
        case actualTrashURL
        // Legacy v1 key.
        case trashURL
        case preTrashBookmarkData
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        originalPath = try container.decode(String.self, forKey: .originalPath)
        quarantinePath = try container.decodeIfPresent(String.self, forKey: .quarantinePath)
        expectedIdentity = try container.decodeIfPresent(FileIdentity.self, forKey: .expectedIdentity)
        predictedTrashURL = try container.decodeIfPresent(String.self, forKey: .predictedTrashURL)
        actualTrashURL = try container.decodeIfPresent(String.self, forKey: .actualTrashURL)
            ?? container.decodeIfPresent(String.self, forKey: .trashURL)
        preTrashBookmarkData = try container.decodeIfPresent(Data.self, forKey: .preTrashBookmarkData)
        state = try container.decodeIfPresent(DedupeJournalItemState.self, forKey: .state)
            ?? (actualTrashURL == nil ? .intent : .trashed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(state, forKey: .state)
        try container.encode(originalPath, forKey: .originalPath)
        try container.encodeIfPresent(quarantinePath, forKey: .quarantinePath)
        try container.encodeIfPresent(expectedIdentity, forKey: .expectedIdentity)
        try container.encodeIfPresent(predictedTrashURL, forKey: .predictedTrashURL)
        try container.encodeIfPresent(actualTrashURL, forKey: .actualTrashURL)
        try container.encodeIfPresent(preTrashBookmarkData, forKey: .preTrashBookmarkData)
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
    func quarantineItem(at sourceURL: URL, to quarantineURL: URL) throws
}

extension DeduplicateFileOperations {
    func quarantineItem(at sourceURL: URL, to quarantineURL: URL) throws {
        let result = sourceURL.path.withCString { source in
            quarantineURL.path.withCString { destination in
                Darwin.rename(source, destination)
            }
        }
        guard result == 0 else {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [
                    NSFilePathErrorKey: sourceURL.path,
                    NSLocalizedDescriptionKey: "Could not atomically quarantine the selected file: \(String(cString: strerror(errno)))",
                ]
            )
        }
    }
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

    static let dedupeSpool: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
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
