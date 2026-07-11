#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Guardian state locations (Phase 4)
//
// All Guardian state lives in Application Support, keyed by a stable library
// identity — NEVER inside the protected library. This is what lets scrub and
// mirror-read treat the library's own bytes (and its `.organize_logs`) as strictly
// read-only: Guardian's own mutable manifest, receipts, journals, and schedule
// state never touch the library folder.

public enum GuardianPaths {
    /// The per-library Guardian state directory:
    /// `…/Application Support/Chronoframe/guardian/<libraryUUID>/`.
    public static func stateDirectory(for identity: GuardianLibraryIdentity) -> URL {
        RuntimePaths.applicationSupportDirectory()
            .appendingPathComponent("guardian", isDirectory: true)
            .appendingPathComponent(identity.libraryUUID, isDirectory: true)
    }

    /// The versioned trusted-digest manifest database.
    public static func manifestURL(for identity: GuardianLibraryIdentity) -> URL {
        stateDirectory(for: identity).appendingPathComponent("manifest.db")
    }

    /// Persisted next-run / last-attempted / last-succeeded scheduling state.
    public static func scheduleURL(for identity: GuardianLibraryIdentity) -> URL {
        stateDirectory(for: identity).appendingPathComponent("schedule.json")
    }

    /// The lock-file location for a read-only library root. It lives in the
    /// library's Guardian state directory (Application Support), so acquiring the
    /// lock never writes into the library itself.
    public static func libraryLockFileURL(for identity: GuardianLibraryIdentity) -> URL {
        stateDirectory(for: identity).appendingPathComponent("library.lock")
    }

    /// Ensure the per-library state directory exists.
    public static func ensureStateDirectory(for identity: GuardianLibraryIdentity) throws {
        try FileManager.default.createDirectory(
            at: stateDirectory(for: identity),
            withIntermediateDirectories: true
        )
    }
}
