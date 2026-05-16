import Foundation

public enum RuntimePaths {
    public static func profilesFileURL() -> URL {
        let environment = ProcessInfo.processInfo.environment

        if let override = environment["CHRONOFRAME_PROFILES_PATH"], !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        #if !MAS_BUILD
        if let repositoryRoot = repositoryRootURL() {
            return repositoryRoot.appendingPathComponent("profiles.yaml")
        }
        #endif

        let appSupport = applicationSupportDirectory().appendingPathComponent("profiles.yaml")
        if !FileManager.default.fileExists(atPath: appSupport.deletingLastPathComponent().path) {
            try? FileManager.default.createDirectory(at: appSupport.deletingLastPathComponent(), withIntermediateDirectories: true)
        }
        return appSupport
    }

    public static func applicationSupportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("Chronoframe", isDirectory: true)
    }

    #if !MAS_BUILD
    private static func repositoryRootURL() -> URL? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["CHRONOFRAME_REPOSITORY_ROOT"], !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if isRepositoryRoot(url) {
                return url
            }
        }

        var candidate = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        for _ in 0..<8 {
            if isRepositoryRoot(candidate) {
                return candidate
            }
            candidate.deleteLastPathComponent()
        }

        return nil
    }

    private static func isRepositoryRoot(_ url: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: url.appendingPathComponent("ui/Package.swift").path
        )
    }
    #endif
}
