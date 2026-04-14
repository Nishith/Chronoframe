import Foundation
import Combine

public final class HistoryStore: ObservableObject {
    @Published public private(set) var entries: [RunHistoryEntry]
    @Published public private(set) var destinationRoot: String
    @Published public private(set) var lastRefreshError: String?

    public init(entries: [RunHistoryEntry] = [], destinationRoot: String = "") {
        self.entries = entries
        self.destinationRoot = destinationRoot
        self.lastRefreshError = nil
    }

    public func refresh(destinationRoot: String) {
        self.destinationRoot = destinationRoot
        self.entries = []
        self.lastRefreshError = nil

        let trimmed = destinationRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let rootURL = URL(fileURLWithPath: trimmed)
        var gatheredEntries: [RunHistoryEntry] = []

        do {
            let logFile = rootURL.appendingPathComponent(".organize_log.txt")
            if let logEntry = makeEntryIfPresent(for: logFile, kind: .runLog, title: "Run Log") {
                gatheredEntries.append(logEntry)
            }

            let logsDirectory = rootURL.appendingPathComponent(".organize_logs", isDirectory: true)
            if FileManager.default.fileExists(atPath: logsDirectory.path) {
                let urls = try FileManager.default.contentsOfDirectory(
                    at: logsDirectory,
                    includingPropertiesForKeys: [.creationDateKey, .contentModificationDateKey],
                    options: [.skipsHiddenFiles]
                )

                for url in urls {
                    switch url.lastPathComponent {
                    case let name where name.hasPrefix("dry_run_report_") && name.hasSuffix(".csv"):
                        if let entry = makeEntryIfPresent(for: url, kind: .dryRunReport, title: "Dry Run Report") {
                            gatheredEntries.append(entry)
                        }
                    case let name where name.hasPrefix("audit_receipt_") && name.hasSuffix(".json"):
                        if let entry = makeEntryIfPresent(for: url, kind: .auditReceipt, title: "Audit Receipt") {
                            gatheredEntries.append(entry)
                        }
                    default:
                        continue
                    }
                }
            }
        } catch {
            lastRefreshError = error.localizedDescription
        }

        entries = gatheredEntries.sorted { $0.createdAt > $1.createdAt }
    }

    private func makeEntryIfPresent(for url: URL, kind: RunHistoryEntryKind, title: String) -> RunHistoryEntry? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let values = try? url.resourceValues(forKeys: [.creationDateKey, .contentModificationDateKey])
        let createdAt = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
        return RunHistoryEntry(kind: kind, title: title, path: url.path, createdAt: createdAt)
    }
}
