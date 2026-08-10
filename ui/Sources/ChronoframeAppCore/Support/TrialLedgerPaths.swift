#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

// MARK: - Trial ledger location (free-trial step 3)
//
// The allowance is GLOBAL, not per-destination: 500 files means 500 files across
// every folder a customer organizes, so the ledger cannot live inside a
// destination the way `.organize_cache.db` does. It also must not live inside a
// destination for a second reason — a destination can be deleted, moved to
// another Mac, or simply not chosen next time, and any of those would read as a
// fresh allowance.
//
// It therefore sits in Application Support alongside Guardian's state, keyed by
// nothing: one ledger per Mac, with the Apple Account key scoping rows inside it.

public enum TrialLedgerPaths {
    /// `…/Application Support/Chronoframe/trial/`.
    public static func stateDirectory() -> URL {
        RuntimePaths.applicationSupportDirectory()
            .appendingPathComponent("trial", isDirectory: true)
    }

    /// The reservation ledger database.
    public static func ledgerURL() -> URL {
        stateDirectory().appendingPathComponent("ledger.db")
    }

    public static func ensureStateDirectory() throws {
        try FileManager.default.createDirectory(
            at: stateDirectory(),
            withIntermediateDirectories: true
        )
    }
}
