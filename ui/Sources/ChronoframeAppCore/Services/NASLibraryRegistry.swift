#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// The saved NAS libraries, kept as a small JSON file on this Mac (C-12). It stores the
/// bookmark and the last identity observation, never credentials: the observation holds
/// only the host, share name and mount facts, with user info already stripped.
public final class NASLibraryRegistry: @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()

    public init(url: URL = NASPaths.registryURL) {
        self.url = url
    }

    public func load() throws -> [NASLibraryRecord] {
        lock.lock()
        defer { lock.unlock() }
        return try loadUnlocked()
    }

    public func upsert(_ record: NASLibraryRecord) throws {
        lock.lock()
        defer { lock.unlock() }
        var records = try loadUnlocked()
        if let index = records.firstIndex(where: { $0.libraryUUID == record.libraryUUID }) {
            records[index] = record
        } else {
            records.append(record)
        }
        try write(records)
    }

    public func remove(libraryUUID: String) throws {
        lock.lock()
        defer { lock.unlock() }
        let records = try loadUnlocked()
        let remaining = records.filter { $0.libraryUUID != libraryUUID }
        guard remaining.count != records.count else { return }
        try write(remaining)
    }

    private func loadUnlocked() throws -> [NASLibraryRecord] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            return []
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([NASLibraryRecord].self, from: data)
    }

    private func write(_ records: [NASLibraryRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try DestinationMetadataFile.replaceFile(at: url) { handle in
            try handle.write(contentsOf: data)
        }
    }
}
