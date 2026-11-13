#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

/// NAS assessment state lives on this Mac under Application Support, never in the
/// assessed library (C-12).
public enum NASPaths {
    /// Test seam: replaces `RuntimePaths.applicationSupportDirectory()` so tests never
    /// touch the real Application Support folder. Nil in production.
    nonisolated(unsafe) static var applicationSupportOverride: URL?

    public static var root: URL {
        (applicationSupportOverride ?? RuntimePaths.applicationSupportDirectory())
            .appendingPathComponent("nas", isDirectory: true)
    }

    public static var registryURL: URL {
        root.appendingPathComponent("libraries.json")
    }

    public static func libraryDirectory(_ uuid: String) -> URL {
        root.appendingPathComponent("libraries", isDirectory: true)
            .appendingPathComponent(uuid, isDirectory: true)
    }

    public static func assessmentStoreURL(_ uuid: String) -> URL {
        libraryDirectory(uuid).appendingPathComponent("assessment.db")
    }

    public static var leaseDirectory: URL {
        root.appendingPathComponent("leases", isDirectory: true)
    }

    public static func ensureDirectories(for uuid: String?) throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: leaseDirectory, withIntermediateDirectories: true)
        if let uuid {
            try fileManager.createDirectory(at: libraryDirectory(uuid), withIntermediateDirectories: true)
        }
    }
}
