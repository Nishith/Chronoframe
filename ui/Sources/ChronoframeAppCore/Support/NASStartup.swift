#if canImport(ChronoframeCore)
import ChronoframeCore
#endif
import Foundation

public enum NASStartup {
    /// Points the share lease at Application Support. If the folder can't be created the
    /// lease falls back to the in-root file only, which is how leases behaved before NAS v1.
    /// Safe to call more than once.
    public static func configure() {
        let directory = NASPaths.leaseDirectory
        NASRemoteLeaseConfiguration.leaseDirectory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
}
