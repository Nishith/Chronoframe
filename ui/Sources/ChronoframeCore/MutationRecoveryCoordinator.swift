import Darwin
import Foundation

public enum FilesystemPresence: Sendable, Equatable {
    case exists
    case missing
    case inaccessible
}

public protocol FilesystemPresenceChecking: Sendable {
    func presence(at path: String) -> FilesystemPresence
}

public struct POSIXFilesystemPresenceChecker: FilesystemPresenceChecking {
    public init() {}

    public func presence(at path: String) -> FilesystemPresence {
        var status = stat()
        if lstat(path, &status) == 0 { return .exists }
        switch errno {
        case ENOENT, ENOTDIR: return .missing
        case EACCES, EPERM: return .inaccessible
        default: return .inaccessible
        }
    }
}

public struct MutationRecoveryReport: Sendable, Equatable {
    public var recoveredItemCount: Int
    public var pendingItemCount: Int
    public var recoveryState: MutationRecoveryState?

    public init(
        recoveredItemCount: Int = 0,
        pendingItemCount: Int = 0,
        recoveryState: MutationRecoveryState? = nil
    ) {
        self.recoveredItemCount = recoveredItemCount
        self.pendingItemCount = pendingItemCount
        self.recoveryState = recoveryState
    }
}

/// Reconciles durable mutation intent before a new operation starts. Recovery
/// never equates a sandbox denial with a missing file and leaves every
/// ambiguous journal in place for a later relaunch or manual intervention.
public final class MutationRecoveryCoordinator: @unchecked Sendable {
    private let presenceChecker: any FilesystemPresenceChecking
    private let fileManager: FileManager
    private let identityHasher: FileIdentityHasher

    public init(
        presenceChecker: any FilesystemPresenceChecking = POSIXFilesystemPresenceChecker(),
        fileManager: FileManager = .default,
        identityHasher: FileIdentityHasher = FileIdentityHasher()
    ) {
        self.presenceChecker = presenceChecker
        self.fileManager = fileManager
        self.identityHasher = identityHasher
    }

    @discardableResult
    public func recover(destinationRoot: URL) -> MutationRecoveryReport {
        let logsDirectory = destinationRoot.appendingPathComponent(".organize_logs", isDirectory: true)
        guard presenceChecker.presence(at: logsDirectory.path) != .inaccessible else {
            return MutationRecoveryReport(
                pendingItemCount: 1,
                recoveryState: volumeRecoveryState(for: destinationRoot)
            )
        }
        guard let contents = try? fileManager.contentsOfDirectory(
            at: logsDirectory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return MutationRecoveryReport() }

        var aggregate = MutationRecoveryReport()
        for receiptURL in contents where
            receiptURL.lastPathComponent.hasPrefix("dedupe_audit_receipt_") &&
            receiptURL.pathExtension == "json"
        {
            let spoolURL = DeduplicateExecutor.spoolURL(for: receiptURL)
            let report = recoverDedupeReceipt(receiptURL: receiptURL, spoolURL: spoolURL)
            aggregate.recoveredItemCount += report.recoveredItemCount
            aggregate.pendingItemCount += report.pendingItemCount
            aggregate.recoveryState = Self.moreSevere(aggregate.recoveryState, report.recoveryState)
        }
        for receiptURL in contents where
            receiptURL.lastPathComponent.hasPrefix("reorganize_audit_receipt_") &&
            receiptURL.pathExtension == "json"
        {
            let report = recoverReorganizeReceipt(receiptURL: receiptURL)
            aggregate.recoveredItemCount += report.recoveredItemCount
            aggregate.pendingItemCount += report.pendingItemCount
            aggregate.recoveryState = Self.moreSevere(aggregate.recoveryState, report.recoveryState)
        }
        let transferReport = recoverTransferJobs(destinationRoot: destinationRoot)
        aggregate.recoveredItemCount += transferReport.recoveredItemCount
        aggregate.pendingItemCount += transferReport.pendingItemCount
        aggregate.recoveryState = Self.moreSevere(aggregate.recoveryState, transferReport.recoveryState)
        return aggregate
    }

    private func recoverTransferJobs(destinationRoot: URL) -> MutationRecoveryReport {
        let databaseURL = destinationRoot.appendingPathComponent(".organize_cache.db")
        guard presenceChecker.presence(at: databaseURL.path) == .exists,
              let database = try? OrganizerDatabase(url: databaseURL)
        else { return MutationRecoveryReport() }
        defer { database.close() }
        guard let jobs = try? database.loadQueuedJobs() else { return MutationRecoveryReport() }

        var report = MutationRecoveryReport()
        for job in jobs where job.status == .pending && job.mutationState != nil {
            let destinationPath = job.mutationState == .finalized
                ? (job.actualDestinationPath ?? job.intendedDestinationPath ?? job.destinationPath)
                : (job.intendedDestinationPath ?? job.destinationPath)
            switch presenceChecker.presence(at: destinationPath) {
            case .missing:
                // Leave PENDING. The next transfer resumes the copy.
                report.pendingItemCount += 1
            case .inaccessible:
                report.pendingItemCount += 1
                report.recoveryState = Self.moreSevere(
                    report.recoveryState,
                    volumeRecoveryState(for: URL(fileURLWithPath: destinationPath))
                )
            case .exists:
                guard let expected = FileIdentity(rawValue: job.hash) else {
                    report.pendingItemCount += 1
                    report.recoveryState = Self.moreSevere(report.recoveryState, .manualActionRequired)
                    continue
                }
                if (try? identityHasher.hashIdentity(at: URL(fileURLWithPath: destinationPath))) == expected {
                    try? database.updateJobMutation(
                        sourcePath: job.sourcePath,
                        runID: job.runID,
                        intendedDestinationPath: job.intendedDestinationPath ?? destinationPath,
                        actualDestinationPath: destinationPath,
                        mutationState: .finalized
                    )
                    try? database.updateJobStatus(sourcePath: job.sourcePath, status: .copied)
                    report.recoveredItemCount += 1
                } else {
                    // Never overwrite or remove an unexpected destination.
                    report.pendingItemCount += 1
                    report.recoveryState = Self.moreSevere(report.recoveryState, .manualActionRequired)
                }
            }
        }
        return report
    }

    private func recoverReorganizeReceipt(receiptURL: URL) -> MutationRecoveryReport {
        guard
            let data = try? Data(contentsOf: receiptURL),
            var receipt = try? JSONDecoder().decode(ReorganizeAuditReceipt.self, from: data),
            receipt.status == "PENDING"
        else { return MutationRecoveryReport() }

        var report = MutationRecoveryReport()
        for index in receipt.items.indices {
            let sourcePresence = presenceChecker.presence(at: receipt.items[index].sourcePath)
            let destinationPresence = presenceChecker.presence(at: receipt.items[index].destinationPath)
            switch (sourcePresence, destinationPresence) {
            case (.exists, .missing):
                receipt.items[index].completed = false
                receipt.items[index].mutationState = .intended
                report.recoveredItemCount += 1
            case (.missing, .exists):
                let destinationURL = URL(fileURLWithPath: receipt.items[index].destinationPath)
                if (try? identityHasher.hashIdentity(at: destinationURL).rawValue) == receipt.items[index].hash {
                    receipt.items[index].completed = true
                    receipt.items[index].mutationState = .moved
                    report.recoveredItemCount += 1
                } else {
                    receipt.items[index].mutationState = .failed
                    report.pendingItemCount += 1
                    report.recoveryState = Self.moreSevere(report.recoveryState, .manualActionRequired)
                }
            case (.inaccessible, _), (_, .inaccessible):
                report.pendingItemCount += 1
                report.recoveryState = Self.moreSevere(
                    report.recoveryState,
                    volumeRecoveryState(for: URL(fileURLWithPath: receipt.destinationRoot))
                )
            default:
                receipt.items[index].mutationState = .failed
                report.pendingItemCount += 1
                report.recoveryState = Self.moreSevere(report.recoveryState, .manualActionRequired)
            }
        }

        if case .some(.needsVolume(_, _)) = report.recoveryState {
            receipt.status = "PENDING"
            receipt.finishedAt = nil
        } else {
            receipt.status = "ABORTED"
            receipt.finishedAt = Date()
            receipt.abortReason = "Reorganize was interrupted and reconciled on the next launch."
        }
        if let encoded = try? JSONEncoder().encode(receipt) {
            try? ReceiptDurability.durablyWrite(data: encoded, to: receiptURL)
        }
        return report
    }

    private func recoverDedupeReceipt(receiptURL: URL, spoolURL: URL) -> MutationRecoveryReport {
        guard
            let receiptData = try? Data(contentsOf: receiptURL),
            var receipt = try? JSONDecoder.dedupe.decode(DeduplicateAuditReceipt.self, from: receiptData),
            receipt.status == "PENDING",
            let records = try? DeduplicateExecutor.loadLatestJournalRecords(from: spoolURL)
        else { return MutationRecoveryReport() }

        var recovered = 0
        var pending = 0
        var state: MutationRecoveryState?
        var verifiedTrashURLs: [String: String] = [:]
        var unverifiedTrashURLs: [String: String] = [:]
        var untouchedPaths = Set<String>()

        for item in receipt.items where records[item.originalPath] == nil {
            switch presenceChecker.presence(at: item.originalPath) {
            case .exists:
                untouchedPaths.insert(item.originalPath)
                recovered += 1
            case .inaccessible:
                state = Self.moreSevere(
                    state,
                    volumeRecoveryState(for: URL(fileURLWithPath: item.originalPath))
                )
                pending += 1
            case .missing:
                state = Self.moreSevere(state, .manualActionRequired)
                pending += 1
            }
        }

        for record in records.values {
            let originalPresence = presenceChecker.presence(at: record.originalPath)
            let quarantinePresence = record.quarantinePath.map {
                presenceChecker.presence(at: $0)
            } ?? .missing

            if quarantinePresence == .exists, let quarantinePath = record.quarantinePath {
                if originalPresence == .missing {
                    do {
                        try fileManager.moveItem(
                            at: URL(fileURLWithPath: quarantinePath),
                            to: URL(fileURLWithPath: record.originalPath)
                        )
                        untouchedPaths.insert(record.originalPath)
                        recovered += 1
                        continue
                    } catch {
                        state = Self.moreSevere(state, .manualActionRequired)
                        pending += 1
                        continue
                    }
                }
                state = Self.moreSevere(state, .manualActionRequired)
                pending += 1
                continue
            }

            let trashCandidates = resolvedTrashCandidates(for: record)
            var sawInaccessibleTrash = false
            var matchedTrashURL: URL?
            for candidate in trashCandidates {
                switch presenceChecker.presence(at: candidate.path) {
                case .inaccessible:
                    sawInaccessibleTrash = true
                case .missing:
                    continue
                case .exists:
                    guard let expected = record.expectedIdentity else {
                        // Legacy completed records have no expected hash but
                        // were already journaled after Trash succeeded.
                        if record.schemaVersion == 1, record.state == .trashed {
                            matchedTrashURL = candidate
                        }
                        continue
                    }
                    if (try? identityHasher.hashIdentity(at: candidate)) == expected {
                        matchedTrashURL = candidate
                    } else {
                        state = Self.moreSevere(state, .manualActionRequired)
                    }
                }
            }

            if let matchedTrashURL {
                verifiedTrashURLs[record.originalPath] = matchedTrashURL.absoluteString
                recovered += 1
                continue
            }
            if originalPresence == .exists, quarantinePresence == .missing, !sawInaccessibleTrash {
                untouchedPaths.insert(record.originalPath)
                recovered += 1
                continue
            }
            if originalPresence == .inaccessible || quarantinePresence == .inaccessible {
                state = Self.moreSevere(state, volumeRecoveryState(for: URL(fileURLWithPath: record.originalPath)))
            } else if originalPresence == .missing, quarantinePresence == .missing, sawInaccessibleTrash {
                state = Self.moreSevere(state, .trashLocationUnverified)
                if let predicted = record.predictedTrashURL {
                    unverifiedTrashURLs[record.originalPath] = predicted
                }
            } else {
                state = Self.moreSevere(state, .manualActionRequired)
            }
            pending += 1
        }

        for index in receipt.items.indices {
            let path = receipt.items[index].originalPath
            if let trashURL = verifiedTrashURLs[path] {
                receipt.items[index].trashURL = trashURL
            } else if let predictedTrashURL = unverifiedTrashURLs[path] {
                receipt.items[index].trashURL = predictedTrashURL
            }
        }
        receipt.items.removeAll { untouchedPaths.contains($0.originalPath) }
        receipt.bytesReclaimed = receipt.items.reduce(0) { partial, item in
            partial + (item.trashURL == nil ? 0 : item.sizeBytes)
        }
        receipt.recoveryState = state
        if case .some(.needsVolume(_, _)) = state {
            receipt.status = "PENDING"
            receipt.finishedAt = nil
        } else {
            receipt.status = "ABORTED"
            receipt.finishedAt = Date()
            receipt.abortReason = "Deduplicate was interrupted and Chronoframe reconciled its recovery journal."
        }

        if let encoded = try? JSONEncoder.dedupe.encode(receipt) {
            try? ReceiptDurability.durablyWrite(data: encoded, to: receiptURL)
        }
        if state == nil {
            try? fileManager.removeItem(at: spoolURL)
        }
        return MutationRecoveryReport(
            recoveredItemCount: recovered,
            pendingItemCount: pending,
            recoveryState: state
        )
    }

    private func resolvedTrashCandidates(for record: DeduplicateSpoolRecord) -> [URL] {
        var urls: [URL] = []
        if let actual = record.actualTrashURL, let url = URL(string: actual) { urls.append(url) }
        if let bookmark = record.preTrashBookmarkData {
            var stale = false
            if let url = try? URL(
                resolvingBookmarkData: bookmark,
                options: [.withSecurityScope, .withoutUI],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            ) {
                urls.append(url)
            }
        }
        if let predicted = record.predictedTrashURL, let url = URL(string: predicted) { urls.append(url) }
        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private func volumeRecoveryState(for url: URL) -> MutationRecoveryState {
        let components = url.standardizedFileURL.pathComponents
        if let volumesIndex = components.firstIndex(of: "Volumes"), components.indices.contains(volumesIndex + 1) {
            let name = components[volumesIndex + 1]
            return .needsVolume(volumeName: name, volumeIdentifier: nil)
        }
        return .manualActionRequired
    }

    private static func moreSevere(
        _ lhs: MutationRecoveryState?,
        _ rhs: MutationRecoveryState?
    ) -> MutationRecoveryState? {
        func rank(_ value: MutationRecoveryState?) -> Int {
            switch value {
            case .none: return 0
            case .needsVolume: return 1
            case .trashLocationUnverified: return 2
            case .manualActionRequired: return 3
            }
        }
        return rank(rhs) > rank(lhs) ? rhs : lhs
    }
}
