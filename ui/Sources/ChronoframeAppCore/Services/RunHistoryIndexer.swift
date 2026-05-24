#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public protocol RunHistoryIndexing: Sendable {
    func index(destinationRoot: String) throws -> [RunHistoryEntry]
}

public struct RunHistoryIndexer: RunHistoryIndexing {
    public init() {}

    public func index(destinationRoot: String) throws -> [RunHistoryEntry] {
        let trimmed = destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let rootURL = URL(fileURLWithPath: trimmed, isDirectory: true)
        var entries: [RunHistoryEntry] = []

        if let entry = makeEntryIfPresent(
            for: rootURL.appendingPathComponent(".organize_log.txt"),
            kind: .runLog,
            rootURL: rootURL
        ) {
            entries.append(entry)
        }

        if let entry = makeEntryIfPresent(
            for: rootURL.appendingPathComponent(".organize_cache.db"),
            kind: .queueDatabase,
            rootURL: rootURL
        ) {
            entries.append(entry)
        }

        let logsDirectoryURL = rootURL.appendingPathComponent(".organize_logs", isDirectory: true)
        if FileManager.default.fileExists(atPath: logsDirectoryURL.path) {
            let enumerator = FileManager.default.enumerator(
                at: logsDirectoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .isSymbolicLinkKey,
                    .contentModificationDateKey,
                    .creationDateKey,
                    .fileSizeKey,
                ],
                options: [.skipsPackageDescendants]
            )

            while let url = enumerator?.nextObject() as? URL {
                guard let kind = classifyArtifact(at: url) else { continue }
                guard let entry = makeEntryIfPresent(for: url, kind: kind, rootURL: rootURL) else { continue }
                entries.append(entry)
            }
        }

        return entries.sorted {
            if $0.createdAt == $1.createdAt {
                return $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private func classifyArtifact(at url: URL) -> RunHistoryEntryKind? {
        let fileName = url.lastPathComponent

        switch fileName {
        case let name where name.hasPrefix("dry_run_report_") && name.hasSuffix(".csv"):
            return .dryRunReport
        case let name where name.hasPrefix("dedupe_audit_receipt_") && name.hasSuffix(".json"):
            return .dedupeAuditReceipt
        case let name where name.hasPrefix("reorganize_audit_receipt_") && name.hasSuffix(".json"):
            return .reorganizeAuditReceipt
        case let name where name.hasPrefix("audit_receipt_") && name.hasSuffix(".json"):
            return .auditReceipt
        case let name where name.hasSuffix(".csv"):
            return .csvArtifact
        case let name where name.hasSuffix(".json"):
            return .jsonArtifact
        default:
            return nil
        }
    }

    private func makeEntryIfPresent(for url: URL, kind: RunHistoryEntryKind, rootURL: URL) -> RunHistoryEntry? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }

        let values = try? url.resourceValues(
            forKeys: [
                .isRegularFileKey,
                .isSymbolicLinkKey,
                .contentModificationDateKey,
                .creationDateKey,
                .fileSizeKey,
            ]
        )

        guard values?.isSymbolicLink != true else { return nil }
        guard values?.isRegularFile ?? true else { return nil }

        let createdAt = timestampFromFilename(url.lastPathComponent)
            ?? values?.contentModificationDate
            ?? values?.creationDate
            ?? .distantPast
        let fileSizeBytes = values?.fileSize.map(Int64.init)

        return RunHistoryEntry(
            kind: kind,
            title: title(for: url, kind: kind),
            path: url.path,
            relativePath: relativePath(for: url, rootURL: rootURL),
            fileSizeBytes: fileSizeBytes,
            createdAt: createdAt
        )
    }

    private func timestampFromFilename(_ filename: String) -> Date? {
        let prefixes = [
            "dry_run_report_",
            "dedupe_audit_receipt_",
            "reorganize_audit_receipt_",
            "audit_receipt_",
        ]
        guard let prefix = prefixes.first(where: { filename.hasPrefix($0) }) else {
            return nil
        }
        let remainder = filename.dropFirst(prefix.count)
        guard remainder.count >= 15 else { return nil }
        let timestamp = String(remainder.prefix(15))
        guard timestamp.range(of: #"^\d{8}_\d{6}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return Self.receiptTimestampFormatter.date(from: timestamp)
    }

    private static let receiptTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        return formatter
    }()

    private func title(for url: URL, kind: RunHistoryEntryKind) -> String {
        switch kind {
        case .csvArtifact, .jsonArtifact:
            return humanizedTitle(from: url.deletingPathExtension().lastPathComponent)
        case .dryRunReport, .auditReceipt, .dedupeAuditReceipt, .reorganizeAuditReceipt, .runLog, .queueDatabase:
            return kind.title
        }
    }

    private func relativePath(for url: URL, rootURL: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let filePath = url.standardizedFileURL.path

        guard filePath.hasPrefix(rootPath) else {
            return url.lastPathComponent
        }

        let relative = String(filePath.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return relative.isEmpty ? url.lastPathComponent : relative
    }

    private func humanizedTitle(from stem: String) -> String {
        stem
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .localizedCapitalized
    }
}
