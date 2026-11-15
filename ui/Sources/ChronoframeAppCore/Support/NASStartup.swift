#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public enum NASStartup {
    /// The one entry point every process surface that can mutate a destination calls at launch
    /// or before it builds an engine: the app (`AppState`) and App Intents (`OrganizeFolderIntent`).
    /// `RuntimePaths` ignores `$HOME`, so under XCTest this would create folders in the real home.
    public static func configureForApp(
        isRunningUnderTests: Bool = NSClassFromString("XCTestCase") != nil
    ) {
        guard !isRunningUnderTests else { return }
        configure()
    }

    /// Points the share lease at Application Support. If the folder can't be created, a
    /// network-destination change does not start: `DestinationOperationLock.acquire(lockFileURL:)`
    /// rethrows its own directory-creation failure (D-NAS-134), and with no directory configured
    /// at all a network destination is refused (D-NAS-141). Safe to call more than once.
    public static func configure() {
        let directory = NASPaths.leaseDirectory
        NASRemoteLeaseConfiguration.leaseDirectory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
