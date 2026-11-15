#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Deduplicate review persistence
//
// A Deduplicate review is saved per dedupe root as one small JSON file under
// Application Support, never inside the root itself (the root may be read-only,
// external, or a folder the user does not expect Chronoframe to write into). The
// protocol lets tests inject an in-memory double.

public protocol DeduplicateReviewSnapshotStoring: Sendable {
    /// nil: missing, corrupt, or written by a different snapshot version.
    func load(folderPath: String) -> DeduplicateReviewSnapshot?
    func save(_ snapshot: DeduplicateReviewSnapshot) throws
    func remove(folderPath: String)
}

public struct DeduplicateReviewFileSnapshotStore: DeduplicateReviewSnapshotStoring {
    private let directory: URL

    public static func defaultDirectory() -> URL {
        // Unit tests construct session stores with the default snapshot store.
        // Give each one a private temporary directory so a test run never reads
        // or writes the user's real saved reviews and tests cannot see each
        // other's saves.
        if NSClassFromString("XCTestCase") != nil {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("chronoframe-dedupe-reviews-tests", isDirectory: true)
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        }
        return RuntimePaths.applicationSupportDirectory()
            .appendingPathComponent("dedupe_reviews", isDirectory: true)
    }

    public init(directory: URL = DeduplicateReviewFileSnapshotStore.defaultDirectory()) {
        self.directory = directory
    }

    public func load(folderPath: String) -> DeduplicateReviewSnapshot? {
        guard
            let data = try? Data(contentsOf: fileURL(forFolderPath: folderPath)),
            let snapshot = try? Self.makeDecoder().decode(DeduplicateReviewSnapshot.self, from: data),
            snapshot.version == DeduplicateReviewSnapshot.version
        else {
            return nil
        }
        return snapshot
    }

    public func save(_ snapshot: DeduplicateReviewSnapshot) throws {
        guard !snapshot.isEmpty else {
            remove(folderPath: snapshot.folderPath)
            return
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try Self.makeEncoder().encode(snapshot)
        try data.write(to: fileURL(forFolderPath: snapshot.folderPath), options: .atomic)
    }

    public func remove(folderPath: String) {
        try? FileManager.default.removeItem(at: fileURL(forFolderPath: folderPath))
    }

    private func fileURL(forFolderPath folderPath: String) -> URL {
        directory
            .appendingPathComponent(DeduplicateReviewKeys.folderKey(for: folderPath))
            .appendingPathExtension("json")
    }

    private static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        return encoder
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
